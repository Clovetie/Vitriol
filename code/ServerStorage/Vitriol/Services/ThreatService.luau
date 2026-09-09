--!strict
-- ThreatService.luau
-- Location: ServerStorage > Vitriol > Services > ThreatService  (ModuleScript)
-- Purpose:  THE DIAL (docs/00 P5, docs/02 §12). One number, 0..1, that every other
--            system reads: it lengthens the night, scales creature count, spawn rate
--            and aggression. It is the single point where "the game gets harder" is
--            decided, precisely so that no subsystem can invent its own difficulty
--            ramp and disagree with the others.
--
--            INPUTS, exactly the three docs/02 §12 lists: nights survived, players
--            alive, creature kills this session. The curve is data
--            (MonsterConfig.Threat.Curve) because balance lives in config, and the
--            extrapolation past the table is a rate rather than a hand-written tail so
--            a night 12 server does not invent a number nobody tuned.
--
--            IT SMOOTHS, AND THAT IS A GAMEPLAY RULE. The published value moves at
--            most MonsterConfig.Threat.MaxChangePerSecond per second. A threat that
--            snaps when a player dies makes the next 20 seconds feel like punishment
--            for a death rather than consequence; a ramp is read as "something knows
--            we are hurt" - which is exactly the fiction (docs/00 P4: the player
--            should be able to narrate the system that is hunting them).
-- Requires: Config/MonsterConfig, Config/GameConfig
-- Used by:  Bootstrap, TimeService (setThreat), CreatureService (count/aggression)

local ThreatService = {}
ThreatService.__index = ThreatService

local LAZY = {}
local function monsterConfig(): any
	if LAZY.MonsterConfig == nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		LAZY.MonsterConfig = require(ReplicatedStorage.Vitriol.Config.MonsterConfig)
	end
	return LAZY.MonsterConfig
end
local function gameConfig(): any
	if LAZY.GameConfig == nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		LAZY.GameConfig = require(ReplicatedStorage.Vitriol.Config.GameConfig)
	end
	return LAZY.GameConfig
end

-- ThreatOf(nightIndex, cfg) -> number
-- The curve, with linear extrapolation past its last entry.
local function curveAt(nightIndex: number, cfg: any): number
	local curve = cfg.Curve
	local index = nightIndex + 1
	if index < 1 then
		index = 1
	end
	if index <= #curve then
		return curve[index]
	end
	return curve[#curve] + cfg.ThreatPerNightBeyond * (index - #curve)
end

-- init(svc, services) -> ()
-- services = { Players, Cadence, Time, Config, Monster, Logger }
function ThreatService.init(svc: any, services: any): ()
	svc.Config = services.Config or gameConfig()
	local monster = services.Monster or monsterConfig()
	svc.Monster = monster
	svc.Threat = monster.Threat
	svc.Players = services.Players
	svc.Cadence = services.Cadence
	svc.Time = services.Time
	svc.log = services.Logger

	svc.nights = 0
	svc.kills = 0
	svc.playersAlive = 0
	svc.threat = 0
	svc.target = 0
	svc.override = nil
	svc.dirty = true
	svc.running = false
	svc.history = {}

	if svc.Players then
		svc.players = {}
		for _, player in ipairs(svc.Players:GetPlayers()) do
			svc.players[player.UserId] = true
		end
		svc.playersAlive = svc:countPlayers()
	end
	svc.players = svc.players or {}
	svc:recompute()
end

function ThreatService:countPlayers(): number
	local n = 0
	for _ in pairs(self.players) do
		n = n + 1
	end
	return n
end

-- start(svc) -> ()
function ThreatService:start(): ()
	if self.running then
		return
	end
	self.running = true
	if self.Cadence then
		self.slotId = self.Cadence:register({
			Name = "Threat:Slow",
			-- Slow cadence, deliberately: the value is smoothed over tens of seconds,
			-- and every consumer (night length, spawn rate) integrates it anyway.
			PeriodSeconds = 1 / self.Config.Ticks.SlowHz,
			BudgetMs = self.Config.Budgets.SlowShares.Threat,
			Run = function(dt)
				self:tick(dt)
			end,
		})
	end
	self:publish()
end

-- recompute(svc) -> ()
-- Target threat from the three inputs. Event-driven: nothing here is a loop, and a
-- caller that changes an input calls this once.
function ThreatService:recompute(): ()
	local cfg = self.Threat
	local players = math.max(self.playersAlive, cfg.PlayerCountFloor)
	local target = curveAt(self.nights, cfg)
	target = target + cfg.PlayersAboveOne * math.max(players - cfg.PlayerCountFloor, 0)
	target = target + cfg.PerKill * self.kills
	target = target + cfg.PerSurvivedNightBonus * self.nights
	if target < cfg.Min then
		target = cfg.Min
	end
	if target > cfg.Max then
		target = cfg.Max
	end
	self.target = target
	self.dirty = true
end

-- tick(svc, dt) -> ()
function ThreatService:tick(dt: number): ()
	if self.override ~= nil then
		self.threat = self.override
		self:publish()
		return
	end
	if self.threat == self.target then
		return
	end
	local maxDelta = self.Threat.MaxChangePerSecond * dt
	local delta = self.target - self.threat
	if delta > maxDelta then
		delta = maxDelta
	elseif delta < -maxDelta then
		delta = -maxDelta
	end
	self.threat = self.threat + delta
	if math.abs(self.threat - self.target) <= maxDelta then
		self.threat = self.target
	end
	self:publish()
end

-- publish(svc) -> ()
function ThreatService:publish(): ()
	local time = self.Time
	if time and time.setThreat then
		time:setThreat(self.threat)
	end
	self.dirty = false
end

-- creatureCount(svc) -> number
-- docs/02 §13 open question 2 answered with data: creatures per night is a threat
-- threshold table, not a formula nobody can tune.
function ThreatService:creatureCount(): number
	local thresholds = self.Threat.CreatureCountAtThreat
	local n = 1
	for i = 1, #thresholds do
		if self.threat >= thresholds[i] then
			n = i + 1
		end
	end
	local cap = self.Config.Session.MaxCreatures
	if cap ~= nil and n > cap then
		n = cap
	end
	return n
end

-- nightsSurvived(svc, nights) -> ()  (from the clock, at Night -> Dawn)
function ThreatService:nightsSurvived(nights: number): ()
	self.nights = nights
	self:recompute()
end

-- killRegistered(svc) -> ()
function ThreatService:killRegistered(): ()
	self.kills = self.kills + 1
	self:recompute()
end

-- playerChanged(svc) -> ()  (join or leave; SessionService drives playersAlive)
function ThreatService:playerChanged(playersAlive: number): ()
	self.playersAlive = playersAlive
	self:recompute()
end

-- setOverride(svc, value?) -> ()  (DebugService: pin the dial to test a night)
function ThreatService:setOverride(value: number?): ()
	self.override = value
	if value == nil then
		self:recompute()
	end
	self:publish()
end

-- snapshot(svc) -> table
function ThreatService:snapshot(): any
	return {
		threat = self.threat,
		target = self.target,
		nights = self.nights,
		kills = self.kills,
		playersAlive = self.playersAlive,
		creatureCount = self:creatureCount(),
	}
end

-- stop(svc) -> ()
function ThreatService:stop(): ()
	self.running = false
	if self.slotId and self.Cadence then
		self.Cadence:unregister(self.slotId)
		self.slotId = nil
	end
end

return ThreatService
