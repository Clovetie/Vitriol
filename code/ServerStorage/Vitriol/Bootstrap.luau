--!strict
-- Bootstrap.luau
-- Location: ServerStorage > Vitriol > Bootstrap  (ModuleScript)
-- Purpose:  Builds the server runtime: the shared singletons, the one cadence driver,
--            the services in dependency order, and the wiring between them. Returns
--            the container so Diagnostics can read it. It is a ModuleScript and NOT a
--            Script on purpose: a Script parked in ServerStorage never runs (a script
--            thread starts only under Workspace or ServerScriptService - docs/08 §10),
--            so `ServerScriptService.Vitriol.Main` is the only thing in the tree that
--            executes, and it calls ensure() here.
--
--            WHY THE WIRING LIVES IN ONE FILE. Every service takes its collaborators
--            through init(services) rather than requiring them, which is what lets the
--            headless harness run the real service code; the cost is that the graph has
--            to be assembled somewhere visible. Here it is, in one page, so
--            "who talks to whom" is readable without a call graph tool (docs/01 §3's
--            single-writer rule is enforceable by eye).
--
--            ensure() IS IDEMPOTENT. Script execution order in Roblox is not
--            guaranteed, so Diagnostics/Profiler must not assume Main got there
--            first; both call ensure() and the second call returns the same container.
-- Requires: Config/*, Shared/Remotes, Shared/NetContract, Shared/NoiseField,
--            Services/*. The RemoteHandlers under ServerScriptService require THIS
--            module (not the other way round): they are Scripts, so they run on their
--            own, and a server Script must not be depended on by the boot path that
--            exists to start services.
-- Used by:  ServerScriptService.Vitriol.Main, Diagnostics.Profiler

local Bootstrap = {}

local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local vitriol = ServerStorage.Vitriol
local shared = ReplicatedStorage.Vitriol

local GameConfig = require(shared.Config.GameConfig)
local DayNightConfig = require(shared.Config.DayNightConfig)
local MonsterConfig = require(shared.Config.MonsterConfig)
local SurvivalConfig = require(shared.Config.SurvivalConfig)
local GoreConfig = require(shared.Config.GoreConfig)
local BloodConfig = require(shared.Config.BloodConfig)
local Remotes = require(shared.Shared.Remotes)
local NetContract = require(shared.Shared.NetContract)
local NoiseField = require(shared.Shared.NoiseField)
local BloodAdapter = require(shared.Shared.BloodAdapter)

local CadenceService = require(vitriol.Services.CadenceService)
local TimeService = require(vitriol.Services.TimeService)
local ThreatService = require(vitriol.Services.ThreatService)
local SessionService = require(vitriol.Services.SessionService)
local HealthService = require(vitriol.Services.HealthService)
local KillChoreography = require(vitriol.Creature.Body.KillChoreography)
local CreatureService = require(vitriol.Services.CreatureService)

local instance: any = nil

-- log(level, message) -> ()
-- One prefix for the whole server (docs/01 §12's convention, and the format the
-- session test greps). warn() for anything a player would notice.
local function log(level: string, message: string): ()
	local line = "[" .. GameConfig.Diagnostics.Prefix .. "] " .. level .. ": " .. message
	if level == "error" or level == "warn" then
		warn(line)
	else
		print(line)
	end
end

-- checkBudgetShares() -> ()
-- The documented budgets are a table of ROW totals, and the shares are a split of a
-- row. If somebody adds a service and a share without taking it from the row, the
-- server silently over-spends a budget nobody approved, so say it out loud at boot.
local function checkBudgetShares(): ()
	local rows = {
		{ name = "Slow", total = GameConfig.Budgets.SlowMs, shares = GameConfig.Budgets.SlowShares },
		{ name = "Frame", total = GameConfig.Budgets.CreatureFrameMs, shares = GameConfig.Budgets.FrameShares },
	}
	for i = 1, #rows do
		local row = rows[i]
		local sum = 0
		for _, value in pairs(row.shares) do
			sum = sum + value
		end
		if sum > row.total then
			log("error", "Budgets." .. row.name .. "Shares sums to " .. string.format("%.3f", sum) .. " ms, over the " .. string.format("%.3f", row.total) .. " ms row budget in docs/01 §4")
		end
	end
end

-- buildNoiseField() -> NoiseField
-- Owned by Bootstrap until PerceptionService (WP6) takes it; the prune slot is here
-- for the same reason - the field has to be maintained by someone from day one, and
-- "who prunes the field" is exactly the question that leaves a 40 MB hash in a
-- long-running server.
local function buildNoiseField(): any
	local senses = MonsterConfig.Senses
	return NoiseField.new({
		Channels = senses.Channels,
		Halflife = senses.DecayHalfLife,
		CellSize = senses.NoiseCellSize,
		AdvectedMaxAge = senses.AdvectionMaxAgeSeconds,
		Coupling = senses.VibrationCoupling,
		CouplingChannel = "VIBRATION",
	})
end

-- ensure() -> runtime
function Bootstrap.ensure(): any
	if instance ~= nil then
		return instance
	end

	local runtime: any = {
		Config = GameConfig,
		DayNight = DayNightConfig,
		Monster = MonsterConfig,
		Survival = SurvivalConfig,
		GoreConfig = GoreConfig,
		BloodConfig = BloodConfig,
		Workspace = Workspace,
		Players = Players,
		Logger = log,
		NetContract = NetContract,
		Remotes = Remotes,
		log = log,
		LodTier = 0,
	}

	Remotes.init()
	runtime.Remotes = {
		time = Remotes.get("RE_TimeSync"),
		stream = Remotes.get("RE_SkeletonStream"),
		creature = Remotes.get("RE_CreatureEvent"),
		survival = Remotes.get("RE_SurvivalSync"),
		destruction = Remotes.get("RE_Destruction"),
		intent = Remotes.get("RE_ClientIntent"),
		debug = Remotes.get("RF_DebugQuery"),
	}

	checkBudgetShares()

	runtime.Cadence = CadenceService.new({
		Config = GameConfig,
		Logger = log,
		OnSample = function(name: string, ms: number, budget: number)
			-- The Profiler polls, so this hook exists only to catch the rare slot that
			-- blows its budget hard enough to matter between polls (a 4x overshoot is
			-- audibly a stutter, and waiting 10 s to say so is too late to care).
			if budget > 0 and ms > budget * GameConfig.Budgets.WatchdogMultiplier * 2 then
				log("warn", "cadence " .. name .. " took " .. string.format("%.3f", ms) .. " ms against a " .. string.format("%.3f", budget) .. " ms budget")
			end
		end,
	})

	runtime.Noise = buildNoiseField()
	runtime.Blood = BloodAdapter.new({
		Config = BloodConfig,
		Workspace = Workspace,
		ServerStorage = ServerStorage,
		ReplicatedStorage = ReplicatedStorage,
		Logger = log,
	})

	-- One instance per service, so no service can be constructed twice and no module
	-- table is ever mutated by two owners.
	runtime.Time = setmetatable({}, TimeService)
	runtime.Threat = setmetatable({}, ThreatService)
	runtime.Session = setmetatable({}, SessionService)
	runtime.Health = setmetatable({}, HealthService)
	runtime.Creature = setmetatable({}, CreatureService)

	runtime.Time:init({
		Workspace = Workspace,
		Cadence = runtime.Cadence,
		Remotes = { sync = runtime.Remotes.time },
		Noise = runtime.Noise,
		Session = runtime.Session,
		Config = GameConfig,
		DayNight = DayNightConfig,
		Logger = log,
	})
	runtime.Threat:init({
		Players = Players,
		Cadence = runtime.Cadence,
		Time = runtime.Time,
		Config = GameConfig,
		Monster = MonsterConfig,
		Logger = log,
	})
	runtime.Session:init({
		Players = Players,
		Cadence = runtime.Cadence,
		Remotes = runtime.Remotes,
		Time = runtime.Time,
		Threat = runtime.Threat,
		Config = GameConfig,
		Logger = log,
	})
	runtime.Health:init({
		Players = Players,
		Cadence = runtime.Cadence,
		Noise = runtime.Noise,
		Blood = runtime.Blood,
		BloodConfig = BloodConfig,
		KillChoreography = KillChoreography,
		KillConfig = MonsterConfig.Kill,
		GoreConfig = GoreConfig,
		Time = runtime.Time,
		Config = GameConfig,
		Survival = SurvivalConfig,
		OnVictimKillStart = function(player: any, scene: any)
			if runtime.Creature then
				runtime.Creature:presentVictimKill(player, scene)
			end
		end,
		OnDeath = function(state: any)
			if runtime.Creature then
				runtime.Creature:presentVictimKill(state.player, state)
			end
		end,
		Logger = log,
	})
	runtime.Creature:init({
		Players = Players,
		Cadence = runtime.Cadence,
		Noise = runtime.Noise,
		Time = runtime.Time,
		Threat = runtime.Threat,
		Health = runtime.Health,
		Remotes = runtime.Remotes,
		Workspace = Workspace,
		Monster = MonsterConfig,
		Survival = SurvivalConfig,
		Config = GameConfig,
		Logger = log,
	})

	runtime.NoiseSlot = runtime.Cadence:register({
		Name = "Noise:Prune",
		PeriodSeconds = 1 / GameConfig.Ticks.SlowHz,
		BudgetMs = GameConfig.Budgets.SlowShares.Noise,
		Run = function()
			runtime.Noise:prune(runtime.Time.elapsedTotal)
		end,
	})

	instance = runtime

	-- THE ONLY RunService BINDING IN THE SERVER. The closure body calls one method,
	-- which is why hot-loop-scan's "in a RunService file" count is zero: every priced
	-- call that belongs to scheduling lives in CadenceService, where it is visible.
	runtime.connection = RunService.Heartbeat:Connect(function(dt: number)
		runtime.Cadence:pump(dt)
	end)

	runtime.Time:start()
	runtime.Threat:start()
	runtime.Session:start()
	runtime.Health:start()
	runtime.Creature:start()
	runtime.Cadence:start()

	if GameConfig.Diagnostics.LogServiceLifecycle then
		log("info", "runtime up: " .. table.concat({ "cadence", "time", "threat", "session", "health", "creature", "blood" }, ", "))
	end
	return runtime
end

-- runtime(timeoutSeconds?) -> table?
-- For a consumer that may run before Main: wait for the container rather than
-- duplicating the boot.
function Bootstrap.runtime(): any
	return instance
end

-- stop() -> ()  (the shutdown path; every service's stop is called in reverse order)
function Bootstrap.stop(): ()
	local runtime = instance
	if runtime == nil then
		return
	end
	runtime.Creature:stop()
	runtime.Health:stop()
	runtime.Session:stop()
	if runtime.Blood then
		runtime.Blood:destroy()
	end
	if runtime.NoiseSlot then
		runtime.Cadence:unregister(runtime.NoiseSlot)
		runtime.NoiseSlot = nil
	end
	runtime.Threat:stop()
	runtime.Time:stop()
	runtime.Cadence:stop()
	if runtime.connection then
		runtime.connection:Disconnect()
	end
	instance = nil
end

return Bootstrap
