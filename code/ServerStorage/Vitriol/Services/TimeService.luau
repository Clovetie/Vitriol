--!strict
-- TimeService.luau
-- Location: ServerStorage > Vitriol > Services > TimeService  (ModuleScript)
-- Purpose:  The authoritative clock. Owns the phase machine (docs/06 §2), the derived
--            in-game time-of-day, the moon phase, the weather slot and the Threat
--            Level it publishes, and the ONE replicated view of all of it.
--
--            IT NEVER WRITES LIGHTING (docs/01 §5.1). Server code has no business
--            setting Lighting properties: clients write their own, because "each
--            player's screen is allowed to be slightly different" is a feature and a
--            replicated Lighting is neither authoritative nor cheap. The grep gate in
--            docs/06 §9.5 exists to keep this true; this file is the thing it checks.
--
--            THE CLOCK IS DERIVED, NOT INTEGRATED (docs/06 §2.2). dt advances elapsed
--            time INSIDE a phase; the hour hand is computed from that progress through
--            Shared/TimeModel. There is no second accumulator, so the sky and
--            PhaseName cannot disagree, and a phase boundary is hit exactly at Threat
--            0 and at Threat 1.
--
--            WHY A PART AND NOT A ValueInstance: attributes on a replicated Instance
--            update per-property, dedupe for free, and cost one instance total; a
--            NumberValue/BoolValue set would be six instances and six replication
--            paths to keep in sync. The attribute names are the ones docs/06 §6 lists;
--            clients listen with GetAttributeChangedSignal, never a per-frame poll.
-- Requires: Config/GameConfig, Config/DayNightConfig, Shared/TimeModel (all injected
--            by Bootstrap, so the module can be driven by a test harness)
-- Used by:  Bootstrap, SessionService, ThreatService, CreatureService (spawn rate),
--            Clients/LightingDriver (via the attributes and RE_TimeSync)

local TimeService = {}
TimeService.__index = TimeService

local LAZY = {}
local function gameConfig(): any
	if LAZY.GameConfig == nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		LAZY.GameConfig = require(ReplicatedStorage.Vitriol.Config.GameConfig)
	end
	return LAZY.GameConfig
end
local function dayNight(): any
	if LAZY.DayNight == nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		LAZY.DayNight = require(ReplicatedStorage.Vitriol.Config.DayNightConfig)
	end
	return LAZY.DayNight
end
local function timeModel(): any
	if LAZY.TimeModel == nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		LAZY.TimeModel = require(ReplicatedStorage.Vitriol.Shared.TimeModel)
	end
	return LAZY.TimeModel
end

local WORLD_FOLDER = "World"
local ROOT_FOLDER = "Vitriol"
local ANCHOR_NAME = "TimeAnchor"
local THREAT_MIN = 0
local THREAT_MAX = 1
local MAX_PHASE_ROLLOVERS = 64 -- a dt guard, not a tunable (see advance)

-- init(svc, services) -> ()
-- services = { Workspace, Cadence, Remotes, Noise, Session, Threat, Config,
--              DayNight, TimeModel, Logger }
function TimeService.init(svc: any, services: any): ()
	svc.Config = services.Config or gameConfig()
	svc.DayNight = services.DayNight or dayNight()
	svc.Model = services.TimeModel or timeModel()
	svc.Workspace = services.Workspace
	svc.Cadence = services.Cadence
	svc.Remotes = services.Remotes
	svc.Noise = services.Noise
	svc.Session = services.Session
	svc.Threat = services.Threat
	svc.log = services.Logger

	svc.phase = svc.Model.phaseOf(svc:openingClock())
	svc.phaseElapsed = 0
	svc.phaseLength = svc.Model.phaseSeconds(svc.phase, 0)
	svc.pendingDayPrep = 0 -- Dawn prep charges the following Day, not Dawn
	svc.prepFade = nil -- optional authoritative stage in the existing TimeSync
	svc.elapsedTotal = 0
	svc.nightIndex = 0
	svc.threat = 0
	svc.clockMinutes = 0
	svc.moonPhase = svc.DayNight.Moon.StartPhase
	svc.weather = "Clear" -- a DayNightConfig.Weather key, not a made-up name
	svc.rainIntensity = 0
	svc.weatherSeed = 0
	svc.wind = { x = 0, y = 0, z = 0, speed = 0 }
	svc.running = false
	svc.timeScale = 0 -- 0 means "read the config"; see setTimeScale
	svc.slotIds = {}
	-- Low-frequency, allocation-free section timings for the *scheduled* 1 Hz
	-- publish. Cadence measures the entire slot; these distinguish attribute
	-- replication from the RemoteEvent when a real Play sample exceeds budget.
	-- Immediate fade/prep publications are deliberately not mixed into this row.
	svc.publishCost = { samples=0, overBudget=0, peakMs=0,
		peakAttributesMs=0, peakRemoteMs=0, lastMs=0,
		lastAttributesMs=0, lastRemoteMs=0,
		peakSampleAttributesMs=0, peakSampleRemoteMs=0, peakPhase="" }
	svc.anchor = svc.Workspace and svc:acquireAnchor() or nil

	if svc.log then
		svc.log("info", "clock derived from phases; " .. string.format("%.0f", svc.Model.cycleSeconds(0)) .. " s per cycle at threat 0")
	end
end

-- openingClock(svc) -> clockHours
-- The hour the session starts at, resolved from Pacing.StartAt rather than a literal.
function TimeService:openingClock(): number
	local startHour = self.Model.phaseSpan(self.DayNight.Pacing.StartAt)
	if startHour == nil then
		startHour = self.Model.phaseSpan(self.DayNight.PHASES[1])
	end
	return startHour
end

-- acquireAnchor(svc) -> Instance
function TimeService:acquireAnchor(): any
	local root = self.Workspace:FindFirstChild(ROOT_FOLDER)
	local world = root and root:FindFirstChild(WORLD_FOLDER)
	local anchor = world and world:FindFirstChild(ANCHOR_NAME)
	if anchor == nil or not anchor:IsA("BasePart") then
		error("[Vitriol.Time] missing authored Workspace.Vitriol.World.TimeAnchor", 0)
	end
	return anchor
end

-- start(svc) -> ()
function TimeService:start(): ()
	if self.running then
		return
	end
	self.running = true
	local cadence = self.Cadence
	if cadence then
		self.slotIds.clock = cadence:register({
			Name = "Time:Clock",
			-- Frame cadence: a 1 Hz clock makes the sky visibly step, and the whole
			-- cost per frame is two adds plus a piecewise lookup.
			PeriodSeconds = 0,
			BudgetMs = self.Config.Budgets.FrameShares.TimeClock,
			Run = function(dt)
				self:advance(dt)
			end,
		})
		self.slotIds.publish = cadence:register({
			Name = "Time:Publish",
			PeriodSeconds = 1 / self.DayNight.Driver.SnapshotRateHz,
			BudgetMs = self.Config.Budgets.SlowShares.TimePublish,
			Run = function()
				self:publish(true) -- section timings only inside the budgeted slot
			end,
		})
	end
	self:publish()
end

-- advance(svc, dt) -> ()
-- One phase's elapsed time, then the boundary check, then the derived clock. The
-- loop is a `repeat` in disguise: a huge dt (a paused server, a test harness that
-- simulates a whole night in one call) must not skip a transition, because each
-- transition is an event other systems subscribe to.
function TimeService:advance(dt: number): ()
	if not self.running then
		return
	end
	local scale = self.Config.Session.SecondsPerRealSecond
	if self.timeScale > 0 then
		scale = self.timeScale
	end
	self:_advanceSeconds(dt * scale)
end

-- Shared phase-boundary path for natural ticking AND one server-authorized
-- preparation time jump. A jump must fire the same Session callbacks as time.
function TimeService:_advanceSeconds(elapsed: number): ()
	if elapsed <= 0 then return end
	self.elapsedTotal = self.elapsedTotal + elapsed
	self.phaseElapsed = self.phaseElapsed + elapsed
	local length = self.phaseLength
	local guard = 0
	while self.phaseElapsed >= length do
		self.phaseElapsed = self.phaseElapsed - length
		self:endPhase()
		length = self.Model.phaseSeconds(self.phase, self.threat)
		guard = guard + 1
		if guard >= MAX_PHASE_ROLLOVERS then
			-- A mis-set pacing table (a zero-length phase) must not hang the server.
			self.phaseElapsed = 0
			break
		end
	end
	self.phaseLength = length
	-- clockMinutes is MINUTES (docs/06 §6's attribute range is 0..1440), and
	-- phaseClock hands back an hour, so the conversion is clockToMinutes - the other
	-- direction divides by 60 and quietly turns a 6.66 h dawn into 0.11.
	self.clockMinutes = self.Model.clockToMinutes(self.Model.phaseClock(self.phase, self.phaseElapsed / length))
end

-- endPhase(svc) -> ()
-- Night -> Dawn is the only edge that advances the night index, because "nights
-- survived" counts nights and not days.
function TimeService:endPhase(): ()
	local previous = self.phase
	local nextPhase = self.Model.nextPhase(previous)
	if previous == "Night" then
		self.nightIndex = self.nightIndex + 1
		self.moonPhase = self.Model.nextMoonPhase(self.moonPhase)
		if self.Session then
			self.Session:nightEnded(self.nightIndex)
		end
	end
	self.phase = nextPhase
	self.phaseLength = self.Model.phaseSeconds(nextPhase, self.threat)
	if nextPhase == "Day" and self.pendingDayPrep > 0 then
		-- Dawn preparations debit the UPCOMING Day at its start. The same
		-- advance loop processes a completely exhausted Day into Dusk.
		local debt = math.min(self.pendingDayPrep, self.phaseLength)
		self.phaseElapsed = self.phaseElapsed + debt
		self.elapsedTotal = self.elapsedTotal + debt
		self.pendingDayPrep = 0
	end
	if self.Session then
		self.Session:phaseChanged(nextPhase, previous, self.phaseLength, self.elapsedTotal)
	end
end

-- phaseProgress(svc) -> 0..1
function TimeService:phaseProgress(): number
	if self.phaseLength > 0 then
		return self.phaseElapsed / self.phaseLength
	end
	return 0
end

-- Day allowance is separate from the current Dawn duration. In Dawn it
-- reflects already reserved time from the coming Day; outside Dawn/Day absent.
function TimeService:dayRemaining(): number?
	if self.phase == "Dawn" then
		return math.max(0, self.Model.phaseSeconds("Day", self.threat) - self.pendingDayPrep)
	elseif self.phase == "Day" then
		return math.max(0, self.phaseLength - self.phaseElapsed)
	end
	return nil
end

-- Spend server-owned Day seconds at the midpoint of an all-client blackout.
-- Cannot spill through Dusk or advance Night. Caller owns eligibility/vote.
function TimeService:spendPrepDay(seconds: number): number
	if not self.running or type(seconds) ~= "number" or seconds ~= seconds
		or seconds <= 0 or seconds == math.huge then return 0 end
	local remaining = self:dayRemaining()
	if not remaining or remaining <= 0 then return 0 end
	local spent = math.min(seconds, remaining)
	if self.phase == "Dawn" then
		self.pendingDayPrep = self.pendingDayPrep + spent
	else
		self:_advanceSeconds(spent)
	end
	self:publish() -- immediate shared server snapshot; do not wait for next slow slot
	return spent
end

-- One serialised fade record accompanies ordinary time snapshots and late-join
-- catch-up. Workspace:GetServerTimeNow is synchronised between Roblox peers; the
-- client can render the CURRENT stage without waiting for a streaming TimeAnchor.
-- Only the server-owned coordinator calls this. No additional remote/Instance.
function TimeService:setPrepFade(serial: number, stage: string, seconds: number): boolean
	if not self.running or type(serial) ~= "number" or serial ~= math.floor(serial)
		or serial < 1 or type(stage) ~= "string" or type(seconds) ~= "number"
		or seconds ~= seconds or seconds < 0 or seconds > 15 then return false end
	local previous = self.prepFade
	if previous and serial < previous.serial then return false end
	if previous and serial == previous.serial then
		local allowed = (previous.stage == "vote" and (stage == "blackout" or stage == "cancel"))
			or (previous.stage == "blackout" and (stage == "reveal" or stage == "cancel"))
			or ((previous.stage == "reveal" or previous.stage == "cancel") and stage == "clear")
		if not allowed then return false end
	elseif stage ~= "vote" then
		return false -- new serial cannot appear halfway through a blackout
	end
	if (stage == "clear" and seconds ~= 0) or (stage ~= "clear" and seconds <= 0) then return false end
	local workspace = self.Workspace
	if not workspace or type(workspace.GetServerTimeNow) ~= "function" then return false end
	self.prepFade = {serial=serial, stage=stage, seconds=seconds,
		startedAt=workspace:GetServerTimeNow()}
	self:publish() -- stages go out immediately, not only on the slow clock slot
	return true
end

-- publish(svc) -> ()
-- The replicated view. Every attribute is written only when it changed: an attribute
-- write produces a replication packet even at the same value, and this runs twice a
-- second for every player in the server.
function TimeService:publish(measureCost: boolean?): ()
	local before = measureCost and os.clock() or nil
	local progress = self:phaseProgress()
	local anchor = self.anchor
	if anchor then
		self:writeAttribute(anchor, "ClockMinutes", self.clockMinutes)
		self:writeAttribute(anchor, "NightIndex", self.nightIndex)
		self:writeAttribute(anchor, "ThreatLevel", self.threat)
		self:writeAttribute(anchor, "MoonPhase", self.moonPhase)
		self:writeAttribute(anchor, "WeatherSeed", self.weatherSeed)
		self:writeAttribute(anchor, "PhaseName", self.phase)
		self:writeAttribute(anchor, "PhaseProgress", progress)
		self:writeAttribute(anchor, "DayBudgetRemaining", self:dayRemaining())
		-- Wind and weather are only published when the feature that produces them is
		-- on (docs/06 §6): the Attune overlay advects scent with the wind, so an
		-- absent attribute means "nothing to draw", not "zero wind was measured".
		if self.Config.Features.Weather then
			self:writeAttribute(anchor, "WindX", self.wind.x)
			self:writeAttribute(anchor, "WindY", self.wind.y)
			self:writeAttribute(anchor, "WindZ", self.wind.z)
			self:writeAttribute(anchor, "WeatherKind", self.weather)
		end
	end
	local attributesDone = before and os.clock() or nil
	self:syncRemotes(progress)
	if before and attributesDone then
		local finish = os.clock()
		local attributesMs = (attributesDone - before) * 1000
		local remoteMs = (finish - attributesDone) * 1000
		local totalMs = (finish - before) * 1000
		local cost = self.publishCost
		cost.samples += 1
		cost.lastMs, cost.lastAttributesMs, cost.lastRemoteMs = totalMs, attributesMs, remoteMs
		if attributesMs > cost.peakAttributesMs then cost.peakAttributesMs = attributesMs end
		if remoteMs > cost.peakRemoteMs then cost.peakRemoteMs = remoteMs end
		if totalMs > cost.peakMs then
			cost.peakMs, cost.peakPhase = totalMs, self.phase
			cost.peakSampleAttributesMs, cost.peakSampleRemoteMs = attributesMs, remoteMs
		end
		if totalMs > self.Config.Budgets.SlowShares.TimePublish then
			-- Evidence only; NEVER suppress Cadence's warning.
			cost.overBudget += 1
		end
	end
end

-- writeAttribute(svc, instance, name, value) -> ()
function TimeService:writeAttribute(instance: any, name: string, value: any): ()
	if instance:GetAttribute(name) ~= value then
		instance:SetAttribute(name, value)
	end
end

-- syncRemotes(svc, progress) -> ()
-- Throttled by the same documented rate the attribute writes use; a late joiner is
-- answered directly by onPlayerAdded instead of waiting for this.
function TimeService:syncRemotes(progress: number): ()
	local sync = self.Remotes and self.Remotes.sync
	if sync == nil then
		return
	end
	-- No extra throttle: this runs at Driver.SnapshotRateHz by construction, and a
	-- 1 Hz broadcast of one small payload to four players is not a cost worth state.
	sync:FireAllClients(self.clockMinutes, self.phase, progress, self.threat, self.nightIndex, self.weather, self.Model.cycleSeconds(self.threat), self:dayRemaining(), self.prepFade)
end

-- onPlayerAdded(svc, player) -> ()
function TimeService:onPlayerAdded(player: any): ()
	local sync = self.Remotes and self.Remotes.sync
	if sync == nil then
		return
	end
	sync:FireClient(player, self.clockMinutes, self.phase, self:phaseProgress(), self.threat, self.nightIndex, self.weather, self.Model.cycleSeconds(self.threat), self:dayRemaining(), self.prepFade)
end

-- setThreat(svc, threat) -> ()
-- Called by ThreatService, never by a timer: Threat is event-driven. The clock's only
-- interest in it is re-lengthening the night, and it does that by rescaling the
-- elapsed fraction rather than restarting, so dying in the first minute of night
-- actually buys the group sleep instead of resetting the timer.
function TimeService:setThreat(threat: number): ()
	local clamped = threat
	if clamped < THREAT_MIN then
		clamped = THREAT_MIN
	end
	if clamped > THREAT_MAX then
		clamped = THREAT_MAX
	end
	if clamped == self.threat then
		return
	end
	local progress = self:phaseProgress()
	self.threat = clamped
	self.phaseLength = self.Model.phaseSeconds(self.phase, clamped)
	if self.phase == "Night" then
		self.phaseElapsed = progress * self.phaseLength
	end
end

-- setWeather(svc, kind, rainIntensity, wind, seed) -> ()
-- The hand the weather system (WP6) plays. Until it exists, the session harness and
-- DebugService use it, which is what makes the rain mask and advection testable.
function TimeService:setWeather(kind: string, rainIntensity: number, wind: any, seed: number?): ()
	self.weather = kind
	self.rainIntensity = rainIntensity
	if seed then
		self.weatherSeed = seed
	end
	local w = self.wind
	if wind then
		w.x = wind.X or wind.x or 0
		w.y = wind.Y or wind.y or 0
		w.z = wind.Z or wind.z or 0
	else
		w.x = 0
		w.y = 0
		w.z = 0
	end
	w.speed = math.sqrt(w.x * w.x + w.y * w.y + w.z * w.z)
	local weather = self.DayNight.Weather[kind]
	if weather == nil then
		self.log("warn", "unknown weather kind '" .. tostring(kind) .. "'; no DayNightConfig.Weather entry, so nothing is masked")
	end
	local noise = self.Noise
	if noise then
		-- The field owns masking and advection; the clock only tells it what the sky is
		-- doing (docs/02 §2 ownership table).
		noise:setWeather(weather)
		noise:setWind(w.x, w.y, w.z)
	end
	self:publish()
end

-- setTimeScale(svc, scale) -> ()
-- The `speedtime` half of docs/06 §8. It overrides here rather than writing
-- GameConfig.Session.SecondsPerRealSecond, because config is frozen at boot in this
-- project and a debug tool must not need an unfreeze to do its job.
function TimeService:setTimeScale(scale: number?): ()
	self.timeScale = scale or 0
end

-- seekTo(svc, clockHours) -> ()
-- The `setclock` half of docs/06 §8, and the reason the derived clock is worth its
-- indirection: seeking is not "add to an accumulator", it is choosing the phase that
-- owns that hour and the elapsed time that produces it. One code path reaches the
-- hour hand, so a debug command cannot desynchronise the sky from PhaseName.
function TimeService:seekTo(clockHours: number): ()
	local hours = clockHours % 24
	local phase = self.Model.phaseOf(hours)
	local progress = self.Model.phaseProgress(hours, phase)
	-- Debug seeks are not a preparation transaction; never carry an old
	-- Dawn reservation into a different designer-selected phase.
	self.pendingDayPrep = 0
	self.phase = phase
	self.phaseLength = self.Model.phaseSeconds(phase, self.threat)
	self.phaseElapsed = progress * self.phaseLength
	self.clockMinutes = self.Model.clockToMinutes(hours)
	self:publish()
end

-- seekToPhase(svc, phase) -> boolean
-- `phasetest`: land on the start of a named phase and let it play, so a designer can
-- watch a transition instead of waiting for one.
function TimeService:seekToPhase(phase: string): boolean
	local startHour = self.Model.phaseSpan(phase)
	if startHour == nil then
		return false
	end
	self:seekTo(startHour)
	return true
end

-- snapshot(svc) -> table  (RF_DebugQuery "clock", the AI dump)
function TimeService:snapshot(): any
	return {
		phase = self.phase,
		phaseProgress = self:phaseProgress(),
		clockMinutes = self.clockMinutes,
		clockHours = self.clockMinutes / 60,
		elapsedTotal = self.elapsedTotal,
		nightIndex = self.nightIndex,
		threat = self.threat,
		moonPhase = self.moonPhase,
		weather = self.weather,
		rainIntensity = self.rainIntensity,
		windSpeed = self.wind.speed,
		phaseSeconds = self.phaseLength,
		cycleSeconds = self.Model.cycleSeconds(self.threat),
	}
end

-- stop(svc) -> ()
function TimeService:stop(): ()
	self.running = false
	local cadence = self.Cadence
	if cadence then
		for _, id in pairs(self.slotIds) do
			cadence:unregister(id)
		end
	end
	self.slotIds = {}
end

return TimeService
