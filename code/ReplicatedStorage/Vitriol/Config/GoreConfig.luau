--!strict
-- GoreConfig.luau
-- Location: ReplicatedStorage > Vitriol > Config > GoreConfig  (ModuleScript)
-- Purpose:  Body regions, sever rules, the Gore module contract defaults and the
--           shipped intensity gate (docs/04-KILL-CHOREOGRAPHY.md).
-- Requires: (none)
-- Used by:  Services/GoreService, Shared/RegionIntegrity, Shared/GoreAdapter,
--           Creature/Body/KillChoreography
--
-- NOTE: the project owner's "provided gore module" is NOT present in this
-- repository yet. GoreAdapter degrades to the built-in fallback (§Fallback)
-- until it lands, so the whole kill system stays playable and balanceable.

local GoreConfig = {}

-- Body regions (docs/04 §2.1). integrity is the shear budget before severance.
GoreConfig.Regions = {
	{ name = "Head", integrity = 60, vulnerability = 1.4, severable = true, downstream = {} },
	{ name = "Torso", integrity = 180, vulnerability = 0.7, severable = false, downstream = {} },
	{ name = "LeftArm", integrity = 70, vulnerability = 1.1, severable = true, downstream = { "LeftHand" } },
	{ name = "RightArm", integrity = 70, vulnerability = 1.1, severable = true, downstream = { "RightHand" } },
	{ name = "LeftLeg", integrity = 90, vulnerability = 1.0, severable = true, downstream = {} },
	{ name = "RightLeg", integrity = 90, vulnerability = 1.0, severable = true, downstream = {} },
	{ name = "LeftHand", integrity = 35, vulnerability = 1.3, severable = true, downstream = {} },
	{ name = "RightHand", integrity = 35, vulnerability = 1.3, severable = true, downstream = {} },
}

-- Tenderizing (docs/04 §2.2). stress = omega * radius * grip * vulnerability.
GoreConfig.Tenderize = {
	RampSeconds = 1.5, -- the creature "settles in"
	ShearMultiplier = 1.0,
	BaseOmega = 8, -- overridden by the ShearRate gene (6-14 Hz)
	GripFromMashFailure = 0.5, -- rises toward 1.0 as the escape mash stalls
	DefaultRegionRadius = 0.5,
	DamagePerIntegrity = 0.08, -- victim HP lost per integrity point
}

-- Escape (docs/03-MONSTER-TECH.md §6.3).
GoreConfig.Escape = {
	BaseMash = 30, -- scaled by the GripTenacity gene
	IntegrityWeight = 0.6, -- 0.4 + 0.6 * meanRegionIntegrity
	DropImpulse = 25,
	InjuryOnLateEscape = 20, -- HP penalty for escaping after heavy shear
}

-- Kill state timings (docs/04 §1.1).
GoreConfig.Timings = {
	Grab = { min = 0.15, max = 0.30 },
	Lift = { min = 0.30, max = 0.80 },
	Drag = { min = 0.0, max = 4.0 },
	Coil = { min = 0.60, max = 1.20 },
	Tenderize = { min = 2.5, max = 6.0 },
	Consume = { min = 2.0, max = 4.0 },
	Discard = 0.5,
	Throw = 0.4,
	Fumble = 0.6,
}

-- Discard behaviour (docs/04 §4). A flung limb becomes a landmark.
GoreConfig.Discard = {
	Chance = 0.65,
	Impulse = 60,
	ScentIntensity = 0.8,
	ScentDecaySeconds = 360,
	AddsSpatialMemory = true,
}

---------------------------------------------------------------------------
-- Gore module contract (docs/04 §3). GoreAdapter is the ONLY caller.
---------------------------------------------------------------------------
GoreConfig.Kinds = {
	"blood_spray",
	"blood_mist",
	"blood_pool",
	"chunk",
	"severed",
	"viscera",
	"gib_burst",
}

GoreConfig.Contract = {
	-- If the supplied module exposes a different entry point, change ONLY these.
	ModuleName = "Gore",
	ModuleLocations = {
		"ServerStorage/Vitriol/Assets/GoreAssets/Gore",
		"ReplicatedStorage/Vitriol/Shared/Gore",
	},
	EntryPoint = "emit", -- module.emit(kind, params)
	WaitForModuleSeconds = 5,
	LogMissingOnce = true,
}

-- Budget: gore must never be why the server drops frames (docs/04 §3.2).
GoreConfig.Budget = {
	MaxActiveEmitters = 24,
	MaxDecals = 16,
	DecalRaycastsPerSecond = 8,
	MinDistanceToCamera = 3, -- never spawn inside the near plane
}

GoreConfig.Lifetimes = {
	blood_spray = 6,
	blood_mist = 4,
	blood_pool = 180,
	chunk = 60,
	severed = 360,
	viscera = 45,
	gib_burst = 8,
}

-- Intensity is a SHIPPED setting, not a debug value (docs/04 §5).
-- LOW must produce zero sever visuals and still complete the kill.
GoreConfig.Intensity = {
	Default = "FULL",
	Options = { "LOW", "FULL" },
	LOW = { SeverVisuals = false, BloodScale = 0.35, PoolDecals = false, ChunkScale = 0.0 },
	FULL = { SeverVisuals = true, BloodScale = 1.0, PoolDecals = true, ChunkScale = 1.0 },
}

GoreConfig.BloodColor = { 96, 12, 16 } -- desaturated on purpose

-- Built-in fallback used when no gore module is present (docs/04 §3.3).
GoreConfig.Fallback = {
	Enabled = true,
	ChunkSize = { 0.25, 0.45 },
	ChunkMaterial = "Slate",
	ChunkLifetime = 8,
	ChunkFadeSeconds = 2,
	ParticleRate = 40,
	ParticleSpeed = { 6, 14 },
	ParticleLifetime = { 0.4, 1.0 },
	DecalSize = { 2, 4 },
}

return GoreConfig
