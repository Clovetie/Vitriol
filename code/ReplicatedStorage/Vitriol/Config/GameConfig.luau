--!strict
-- GameConfig.luau
-- Location: ReplicatedStorage > Vitriol > Config > GameConfig  (ModuleScript)
-- Purpose:  Session shape, tick budgets, LOD tiers and feature flags.
--           Every number here is justified in docs/ (section noted per block).
-- Requires: (none)
-- Used by:  all Services, Bootstrap, Profiler

local GameConfig = {}

-- Feature flags (docs/01-ARCHITECTURE.md §10).
-- A flag that ships false for two iterations gets DELETED, not left rotting.
GameConfig.Features = {
	CreatureIK = true,
	CreatureLearning = false, -- WP7 turns this on; A/B against instinct-only
	SpeciesPersistence = false, -- cross-server evolution, post-MVP
	Destruction = true,
	Vehicles = true,
	Survival = true,
	Weather = false,
	DebugPilot = false, -- keyboard-drive a creature in Studio
	DebugNoiseMarkers = false,
	DebugDecisionDump = false,
	DataPersistence = false, -- session records; blocking on GetAsync at boot is a bug
}

-- Network contract (WP2/WP3). One place defines the remotes, the bind timeout and
-- the admission limits the server applies to anything a client sends.
GameConfig.Net = {
	CommsFolder = "Comms", -- ReplicatedStorage > Vitriol > Comms
	BindTimeoutSeconds = 5, -- client WaitForChild per remote; then degrade, never hang
	-- Token buckets for NetContract, per player per message kind.
	--   Burst             tokens available after idling
	--   SustainedPerSecond  refill rate
	--   MinGapSeconds     hard floor between two accepted messages of a kind
	Rate = {
		ClientIntent = { Burst = 8, SustainedPerSecond = 12, MinGapSeconds = 0.04 },
		DebugQuery = { Burst = 3, SustainedPerSecond = 2, MinGapSeconds = 0.25 },
	},
	-- Payload bounds for NetContract. A hold longer than MaxHeldSeconds is either a
	-- stuck key or a lie, and either way the server has its own timer for it.
	MaxHeldSeconds = 30,
	MaxStringBytes = 48,
	MaxListLength = 16,
	MaxPositionMagnitude = 20000, -- studs; the map is far smaller, so larger is a bug
	DebugArgumentMin = -24, -- 'setclock' / 'speedtime' range, docs/06 §8
	DebugArgumentMax = 1000,
}

-- What a client is allowed to ask for, grouped by the service that answers it
-- (docs/07 §4). NetContract builds its intent enum from this list, and
-- DestructionConfig.Interactions holds the noise cost of each one that makes noise.
-- Adding an interaction = one line here + one line in the owning service.
GameConfig.Intents = {
	{
		Group = "Destruction",
		Actions = {
			"OpenDoor",
			"KickDoor",
			"Barricade",
			"RemoveBarricade",
			"SmashPlank",
			"BreakWindow",
			"ClimbThroughWindow",
			"SearchContainer",
			"CarryObject",
			"ThrowObject",
			"PushVehicle",
			"CrankGenerator",
		},
	},
	{ Group = "Vehicle", Actions = { "EnterVehicle", "ExitVehicle" } },
	{ Group = "Survival", Actions = { "Consume", "TreatWound", "DropHeld" } },
	{ Group = "Sense", Actions = { "Attune", "AttuneRelease" } },
}

-- Session shape (docs/00-VISION.md §8.1).
GameConfig.Session = {
	MinPlayers = 1,
	MaxPlayers = 4,
	-- MVP decision: threat never increases the number of monsters. One
	-- woundable creature is the readable prototype; a later, explicit design
	-- change can raise this without changing CreatureService's lifecycle code.
	MaxCreatures = 1,
	IntermissionSeconds = 15,
	CorpseLifetimeSeconds = 360, -- corpses keep emitting scent for the night
	DiscardLifetimeSeconds = 360,
	-- The clock multiplier a test harness uses (docs/00 §7): 60 makes a full night
	-- pass in seconds. Production is 1, and it lives in config precisely so a shipped
	-- build can be diffed for it.
	SecondsPerRealSecond = 1,
	RoundName = "Quarry", -- the log line's subject: a session is named, not numbered
	DataStoreName = "vitriol-session",
	PhaseLogLines = 8, -- how many phase-change lines the debug dump can reach
}

-- Tick cadences (docs/01-ARCHITECTURE.md §4). Nothing invents its own loop.
GameConfig.Ticks = {
	ThinkHz = 6, -- per creature, staggered
	SenseHz = 10, -- per creature, staggered
	SlowHz = 1, -- survival / clock / GC
	-- One Heartbeat-driven scheduler (Services/CadenceService) owns every cadence,
	-- so there is exactly one place that decides how finely a 1 Hz job may drift.
	CadenceSlopSeconds = 0.25, -- max lateness tolerated before a slot skips a beat
	SkeletonStreamHzNear = 15,
	SkeletonStreamHzMid = 8,
	SkeletonStreamHzFar = 4,
	StaggerPhaseSpread = true, -- offset each creature's tick by index/count
}

-- Per-cadence server budgets in milliseconds, and the watchdog that enforces
-- them (docs/01-ARCHITECTURE.md §9). Exceeding 2x for 10 consecutive samples
-- auto-degrades one LOD tier.
GameConfig.Budgets = {
	CreatureFrameMs = 1.2,
	PerceptionMs = 1.0,
	DestructionMs = 0.5,
	-- The Slow row of docs/01 §4 is ONE 0.4 ms budget shared by everything on the
	-- second cadence, so the split is data: a slot that exceeds its share is named in
	-- the log, and Bootstrap checks that the shares still add up to the row.
	SlowShares = {
		TimePublish = 0.05,
		Session = 0.05,
		Threat = 0.05,
		Health = 0.10,
		Noise = 0.10,
	},
	FrameShares = {
		-- The clock is a frame-cadence job (a 1 Hz sky visibly steps); this is its
		-- slice of the 1.2 ms frame row, which is otherwise spent on IK and steering.
		TimeClock = 0.02,
		Health = 0.05,
		Think = 0.15, -- instinct steering on the Think cadence (WP6A)
	},
	SlowMs = 0.4,
	ReplicationMs = 0.3,
	WatchdogMultiplier = 2.0,
	WatchdogSamples = 10,
}

-- Distance LOD ladder (docs/03-MONSTER-TECH.md §8.3).
GameConfig.LOD = {
	NearStuds = 60,
	MidStuds = 140,
	FarStuds = 300,
	StreamRadius = 320, -- who receives the skeleton stream at all
	NearJoints = 16,
	MidJoints = 8,
	FarJoints = 4,
	OffscreenJoints = 3,
	-- The ladder itself, ordered cheapest-last. The watchdog walks these by index, so
	-- the tiers are config rather than an if-chain in Diagnostics/Profiler.
	Tiers = { "NEAR", "MID", "FAR", "OFFSCREEN" },
}

-- Diagnostics (WP4). Everything the boot path and the watchdog log.
GameConfig.Diagnostics = {
	Prefix = "vitriol", -- one prefix so a filtered console shows only this game; the
	-- brackets are added by the logger, not stored in the value
	LogPhaseChanges = true, -- the acceptance line: one per phase change
	LogServiceLifecycle = true, -- init/start/stop of each service, for CI diffs
	ProfilerReportSeconds = 10, -- how often the budget summary is printed
	ProfilerDegradeLog = true, -- log the auto-degrade decision itself
	LogNetRejections = false, -- one line per rejected client payload; noisy by design
	LogDecisionDump = false, -- WP6A observer dump: action/channel/age/conf, no player ids
	DebugRemoteEnabled = true, -- binds RF_DebugQuery; flip false before shipping
}

-- Collision groups (docs/03-MONSTER-TECH.md §9). Registered once at boot.
GameConfig.CollisionGroups = {
	"Vitriol_Creature",
	"Vitriol_Player",
	"Vitriol_Structure",
	"Vitriol_Vehicle",
	"Vitriol_Debris",
	"Vitriol_NonCollide",
}

-- CollectionService tags used across the project.
GameConfig.Tags = {
	Creature = "Vitriol_Creature",
	Structure = "Vitriol_Structure",
	Joint = "Vitriol_Joint",
	Vehicle = "Vitriol_Vehicle",
	Zone = "Vitriol_Zone",
	Debris = "Vitriol_Debris",
	Gore = "Vitriol_Gore",
	Interactable = "Vitriol_Interactable",
}

-- Animation asset IDs (human-authored; docs/10-HUMAN-AUTHORED.md §7).
-- IDs live here and NOWHERE else in code.
GameConfig.AnimationIds = {
	Crawl = 0,
	CarryBox = 0,
	CarryPlank = 0,
	Bandage = 0,
	Eat = 0,
	Drink = 0,
	Barricade = 0,
	CrankGenerator = 0,
	Collapse = 0,
}

return GameConfig
