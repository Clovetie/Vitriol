--!strict
-- SessionService.luau
-- Location: ServerStorage > Vitriol > Services > SessionService  (ModuleScript)
-- Purpose:  The session state machine on top of the clock: intermission, whether a
--            round is live, which night this is, the one-line log per phase change,
--            and the persisted "nights survived" record.
--
--            WHAT IT DELIBERATELY DOES NOT GATE. The clock runs whether or not anyone
--            is connected, and a phase change is logged whether or not a round is
--            live: Session.MinPlayers gates creature spawns and scoring, never the
--            day/night cycle (docs/06 §1's "8-14 minutes per day" is a property of the
--            world, not of the party). That is also what makes a zero-player dedicated
--            server a valid test of the whole loop, which WP4's acceptance requires.
--
--            IT DOES NOT OWN THE PHASE MACHINE. TimeService advances time and calls
--            phaseChanged on this module; the boundary exists so there is exactly one
--            derivation of "what phase is it" in the server (docs/06 §9.3 forbids a
--            second one). SessionService's job is what a phase change MEANS.
-- Requires: Config/GameConfig, Config/DayNightConfig, Shared/TimeModel, Shared/Remotes
-- Used by:  Bootstrap, ThreatService (night index), Diagnostics (snapshot)

local SessionService = {}
SessionService.__index = SessionService

local LAZY = {}
local function gameConfig(): any
	if LAZY.GameConfig == nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		LAZY.GameConfig = require(ReplicatedStorage.Vitriol.Config.GameConfig)
	end
	return LAZY.GameConfig
end

local STATE_INTERMISSION = "Intermission"
local STATE_RUNNING = "Running"
local STATE_ENDED = "Ended"

-- formatClock(seconds) -> "m:ss"  (the elapsed time in the acceptance line)
local function formatClock(seconds: number): string
	local whole = math.floor(seconds)
	return string.format("%d:%02d", math.floor(whole / 60), whole % 60)
end

-- init(svc, services) -> ()
-- services = { Players, Cadence, Remotes, Time, Threat, DataStore?, Config, Logger }
function SessionService.init(svc: any, services: any): ()
	svc.Config = services.Config or gameConfig()
	svc.Players = services.Players
	svc.Cadence = services.Cadence
	svc.Remotes = services.Remotes
	svc.Time = services.Time
	svc.Threat = services.Threat
	svc.DataStore = services.DataStore
	svc.log = services.Logger

	svc.state = STATE_INTERMISSION
	svc.intermissionLeft = svc.Config.Session.IntermissionSeconds
	svc.running = false
	svc.roundActive = false
	svc.startedAt = 0
	svc.elapsed = 0
	svc.nightsSurvived = 0
	svc.phaseChanges = 0
	svc.playersAlive = 0
	svc.kills = 0
	svc.lines = {} -- the last N acceptance lines, for the debug dump

	if svc.Players then
		svc.players = {}
		for _, player in ipairs(svc.Players:GetPlayers()) do
			svc.players[player.UserId] = true
		end
		svc.playersAlive = svc:countPlayers()
		svc.connections = {
			svc.Players.PlayerAdded:Connect(function(player)
				svc.players[player.UserId] = true
				svc.playersAlive = svc:countPlayers()
				svc:onPlayerJoined(player)
			end),
			svc.Players.PlayerRemoving:Connect(function(player)
				svc.players[player.UserId] = nil
				svc.playersAlive = svc:countPlayers()
				svc:onPlayerLeft(player)
			end),
		}
	else
		svc.players = {}
		svc.connections = {}
	end
end

-- countPlayers(svc) -> number
function SessionService:countPlayers(): number
	local n = 0
	for _ in pairs(self.players) do
		n = n + 1
	end
	return n
end

-- start(svc) -> ()
function SessionService:start(): ()
	if self.running then
		return
	end
	self.running = true
	if self.Cadence then
		self.slotId = self.Cadence:register({
			Name = "Session:Slow",
			PeriodSeconds = 1 / self.Config.Ticks.SlowHz,
			BudgetMs = self.Config.Budgets.SlowShares.Session,
			Run = function(dt)
				self:tick(dt)
			end,
		})
	end
	self:loadRecord()
end

-- tick(svc, dt) -> ()
-- The whole of SessionService's frame work: one countdown, or one elapsed add.
function SessionService:tick(dt: number): ()
	if self.state == STATE_INTERMISSION then
		self.intermissionLeft = self.intermissionLeft - dt
		if self.intermissionLeft <= 0 then
			self:beginRound()
		end
	elseif self.state == STATE_RUNNING then
		self.elapsed = self.elapsed + dt
	end
end

-- beginRound(svc) -> ()
function SessionService:beginRound(): ()
	self.state = STATE_RUNNING
	self.startedAt = self.elapsed
	-- MinPlayers gates whether the round is SCORABLE, never whether the clock runs:
	-- an empty server still dawns, and a live server with two players does not wait
	-- for a third to start being hunted.
	self.roundActive = self.playersAlive >= self.Config.Session.MinPlayers
	self:emit("round " .. self.Config.Session.RoundName .. " live at " .. formatClock(self.elapsed) .. (self.roundActive and "" or " (no players yet: clock runs, scoring waits)"))
end

-- endRound(svc, reason) -> ()
function SessionService:endRound(reason: string): ()
	if self.state == STATE_ENDED then
		return
	end
	self.state = STATE_ENDED
	self.roundActive = false
	self:emit("round ended (" .. reason .. ") after " .. formatClock(self.elapsed) .. ", " .. self.nightsSurvived .. " nights survived")
	self:saveRecord()
end

-- phaseChanged(svc, phase, previous, phaseLength, elapsedTotal) -> ()
-- The acceptance line: exactly one per phase change, with the elapsed time in it.
-- Emitted from TimeService's transition, never from a poll, so the count of lines is
-- the count of transitions by construction.
function SessionService:phaseChanged(phase: string, previous: string, phaseLength: number, elapsedTotal: number): ()
	self.phaseChanges = self.phaseChanges + 1
	local line = formatClock(elapsedTotal) .. "  " .. previous .. " -> " .. phase .. "  night " .. self.nightsSurvived .. "  length " .. string.format("%.0f", phaseLength) .. " s"
	self:emit(line)
	if self.Config.Diagnostics.LogPhaseChanges then
		-- Keep the last few lines reachable from the debug dump; a session that has
		-- been up for a week must not grow this forever.
			-- A ring, not a shifting array: keeping the last N lines by table.remove(1)
		-- would be an O(N) move inside a frame path for a log line nobody reads there.
		local cap = self.Config.Session.PhaseLogLines
		self.lines[(self.phaseChanges - 1) % cap + 1] = line
	end
end

-- nightEnded(svc, nightIndex) -> ()
function SessionService:nightEnded(nightIndex: number): ()
	self.nightsSurvived = nightIndex
	if self.Threat then
		self.Threat:nightsSurvived(nightIndex)
	end
end

-- killRegistered(svc) -> ()  (a completed kill is the loudest threat signal there is)
function SessionService:killRegistered(): ()
	self.kills = self.kills + 1
	if self.Threat then
		self.Threat:killRegistered()
	end
end

-- snapshot(svc) -> table
function SessionService:snapshot(): any
	return {
		state = self.state,
		elapsed = self.elapsed,
		nightsSurvived = self.nightsSurvived,
		phaseChanges = self.phaseChanges,
		playersAlive = self.playersAlive,
		kills = self.kills,
		roundActive = self.roundActive,
		lines = self.lines,
	}
end

-- onPlayerJoined(svc, player) -> ()
-- A late join is a time-sync event first: the client cannot render a sky it has not
-- been told about, and waiting for the next snapshot is a visible pop on join.
function SessionService:onPlayerJoined(player: any): ()
	self:emit("player " .. player.Name .. " joined (" .. self.playersAlive .. " alive)")
	if self.Time then
		self.Time:onPlayerAdded(player)
	end
end

-- onPlayerLeft(svc, player) -> ()
function SessionService:onPlayerLeft(player: any): ()
	self:emit("player " .. player.Name .. " left (" .. self.playersAlive .. " alive)")
	if self.playersAlive == 0 and self.state == STATE_RUNNING then
		-- An empty server keeps ticking but a round with nobody in it is over; the
		-- record is saved so the group's nights survive a mass-disconnect.
		self:saveRecord()
	end
end

-- emit(svc, message) -> ()
-- One prefix, one shape. A CI diff and a filtered console both read this line. The
-- method is NOT called log, because self.log is the injected sink: two names for one
-- slot is how a logger ends up calling itself.
function SessionService:emit(message: string): ()
	local sink = self.log
	if sink then
		sink("info", message)
	else
		print("[" .. self.Config.Diagnostics.Prefix .. "] " .. message)
	end
end

-- loadRecord(svc) -> () / saveRecord(svc) -> ()
-- The persistence seam, feature-flagged and never on the boot path: a server that
-- blocks on a DataStore call during start is a server that fails to start.
function SessionService:loadRecord(): ()
	local store = self.store
	if store == nil and self.DataStore and self.Config.Features.DataPersistence then
		store = self.DataStore:GetDataStore(self.Config.Session.DataStoreName)
		self.store = store
	end
	if store == nil then
		return
	end
	local ok, record = pcall(function()
		return store:GetAsync("global")
	end)
	if not ok then
		-- A read that failed is not a read that returned nothing: conflating them means
		-- a DataStore hiccup resets the group's progress to zero, quietly.
		self:emit("session record unreadable: " .. tostring(record))
		return
	end
	if type(record) == "table" and record.nightsSurvived ~= nil then
		self.nightsSurvived = record.nightsSurvived
		self:emit("restored session record: " .. self.nightsSurvived .. " nights survived")
	end
end

function SessionService:saveRecord(): ()
	local store = self.store
	if store == nil then
		return
	end
	local ok, err = pcall(function()
		store:UpdateAsync("global", function(old: any)
			return { nightsSurvived = self.nightsSurvived, kills = self.kills }
		end)
	end)
	if not ok then
		self:emit("session record not written: " .. tostring(err))
	end
end

-- stop(svc) -> ()
function SessionService:stop(): ()
	self.running = false
	if self.slotId and self.Cadence then
		self.Cadence:unregister(self.slotId)
		self.slotId = nil
	end
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
end

return SessionService
