--!strict
-- DestructionConfig.luau
-- Location: ReplicatedStorage > Vitriol > Config > DestructionConfig  (ModuleScript)
-- Purpose:  Materials, joint durability, impulse thresholds, debris pooling and
--           the integrity-BFS caps (docs/07-DESTRUCTION-VEHICLES.md).
-- Requires: (none)
-- Used by:  Services/DestructionService, Services/VehicleService, Client/DebrisRenderer

local DestructionConfig = {}

-- Materials (docs/07 §2.3). HpMultiplier scales a part's base HP; Resistance
-- divides incoming impulse energy; Vibration/Air are the noise the creature hears.
DestructionConfig.Materials = {
	Glass = { HpMultiplier = 0.25, Resistance = 0.10, Debris = 6, Vibration = 0.35, Air = 0.85, SoundSet = "Glass" },
	Wood = { HpMultiplier = 1.00, Resistance = 0.50, Debris = 3, Vibration = 0.70, Air = 0.60, SoundSet = "Wood" },
	Masonry = { HpMultiplier = 3.50, Resistance = 2.20, Debris = 5, Vibration = 0.90, Air = 0.70, SoundSet = "Masonry" },
	Concrete = { HpMultiplier = 6.00, Resistance = 4.00, Debris = 6, Vibration = 1.00, Air = 0.75, SoundSet = "Concrete" },
	Metal = { HpMultiplier = 4.00, Resistance = 3.00, Debris = 2, Vibration = 0.95, Air = 0.90, SoundSet = "Metal" },
}

-- Base HP before the material multiplier, by structural role.
DestructionConfig.BaseHp = {
	Post = 140,
	Beam = 110,
	Wall = 160,
	Door = 70,
	Window = 25,
	Plank = 55,
	Roof = 130,
	Prop = 40,
}

-- Impact model (docs/07 §3.3). energy = 0.5 * mass * |dv|^2, divided by
-- material Resistance, compared against joint HP.
DestructionConfig.Impact = {
	ReferenceEnergy = 4000, -- energy that reads as Vibration 1.0
	MinDamageEnergy = 120, -- below this, ignore entirely (stops micro-jitter damage)
	CreatureDamageScale = 0.012, -- energy -> creature HP
	PlayerDamageScale = 0.02,
	-- An assembly containing an anchored part has INFINITE mass (verified), so
	-- the moving side takes all the damage in that case.
	AnchoredCollisionSelfDamageScale = 1.0,
}

-- Structural integrity BFS (docs/07 §2.4).
DestructionConfig.Integrity = {
	MaxNodesPerStep = 64,
	AmortiseOverFrames = 3,
	MaxChainDepth = 24,
	CollapseImpactFraction = 0.6, -- falling parts transfer this much energy on landing
	InferAdjacency = true, -- infer from bounding-box contact when Meta has no list
	AdjacencyContactInflation = 0.2, -- studs
}

-- Debris pooling (docs/07 §2.5). The single most important perf guard here.
DestructionConfig.Debris = {
	PoolSize = 96,
	MaxLivePhysics = 40, -- hard cap on simultaneous unanchored debris parts
	SettleSeconds = 2.5,
	LifetimeSeconds = 20,
	FadeSeconds = 1.5,
	CollideWhileSettling = true,
	CosmeticClientDebris = true, -- clients spawn non-simulating splinters
	CosmeticPerBreak = 3,
	CosmeticLifetimeSeconds = 3,
}

-- Interaction costs (docs/07 §4). Every interaction has a noise cost.
DestructionConfig.Interactions = {
	OpenDoor = { seconds = 0.8, air = 0.25 },
	KickDoor = { seconds = 0.3, vibration = 0.8, damage = 45 },
	Barricade = { seconds = 2.5, vibration = 0.55, planks = 2 },
	RemoveBarricade = { seconds = 2.0, vibration = 0.45 },
	SmashPlank = { seconds = 0.5, vibration = 0.75, damage = 60 },
	BreakWindow = { seconds = 0.3, air = 0.9, vibration = 0.3 },
	ClimbThroughWindow = { seconds = 1.2, air = 0.35, damageChance = 0.15, damage = 8 },
	SearchContainer = { seconds = 2.0, air = 0.3 },
	CarryObject = { seconds = 0.6, noiseMultiplier = 1.25 },
	ThrowObject = { seconds = 0.4, impulse = 60 },
	PushVehicle = { seconds = 0.0, force = 900, noiseMultiplier = 1.1 },
	CrankGenerator = { seconds = 4.0, vibration = 0.6, emPerSecond = 1.0 },
}

-- Tools (melee / improvised) for joint damage.
DestructionConfig.Tools = {
	Fists = 8,
	Plank = 22,
	Crowbar = 45,
	Axe = 70,
}

return DestructionConfig
