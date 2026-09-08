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
}

-- Session shape (docs/00-VISION.md §8.1).
GameConfig.Session = {
	MinPlayers = 1,
	MaxPlayers = 4,
	MaxCreatures = 3,
	IntermissionSeconds = 15,
	CorpseLifetimeSeconds = 360, -- corpses keep emitting scent for the night
	DiscardLifetimeSeconds = 360,
}

-- Tick cadences (docs/01-ARCHITECTURE.md §4). Nothing invents its own loop.
GameConfig.Ticks = {
	ThinkHz = 6, -- per creature, staggered
	SenseHz = 10, -- per creature, staggered
	SlowHz = 1, -- survival / clock / GC
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
