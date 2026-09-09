--!strict
-- MonsterConfig.luau
-- Location: ReplicatedStorage > Vitriol > Config > MonsterConfig  (ModuleScript)
-- Purpose:  Creature genome ranges, sensory model, action set, and the RL
--           hyper-parameters (docs/02-MONSTER-DESIGN.md).
--           NOTE: Lib/Genetics carries a DEFAULT_GENES copy so it stays
--           Config-free and unit-testable. THIS table is the runtime source of
--           truth and is injected via Genetics.new(MonsterConfig.Genes).
-- Requires: (none)
-- Used by:  Services/{CreatureService,EvolutionService,PerceptionService},
--           Creature/Brain/*, Lib/Genetics (injected)

local MonsterConfig = {}

---------------------------------------------------------------------------
-- Genome (docs/02 §5.1). cost is multiplied by the gene value and summed
-- against the metabolic budget, which is why there is no "good at everything".
---------------------------------------------------------------------------
MonsterConfig.Genes = {
	{ name = "Speed", cost = 0.14, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Strength", cost = 0.13, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Endurance", cost = 0.09, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Mass", cost = 0.12, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Adhesion", cost = 0.07, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Softness", cost = 0.06, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "SenseVibration", cost = 0.05, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "SenseAir", cost = 0.05, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "SenseScent", cost = 0.05, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "SenseThermal", cost = 0.04, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "SenseEM", cost = 0.04, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Cunning", cost = 0.10, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Patience", cost = 0.04, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Aggression", cost = 0.05, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Metabolism", cost = 0.08, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Regeneration", cost = 0.06, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "Armour", cost = 0.09, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "ShearRate", cost = 0.06, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "GripTenacity", cost = 0.05, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "TendrilLength", cost = 0.05, min = 0, max = 1, kind = "float", default = 0.5 },
	{ name = "TendrilCount", cost = 0.02, min = 6, max = 14, kind = "int", default = 8 },
}

-- Metabolic budget grows with Threat Level (docs/02 §5.2). Interpolated.
MonsterConfig.Budget = {
	Threat0 = 0.85,
	Threat1 = 1.15,
}

MonsterConfig.Evolution = {
	Sigma = 0.06, -- gaussian mutation width
	StructuralChance = 0.10, -- chance of a tendril-count change (VISIBLE)
	EliteCount = 12, -- genomes kept per lineage
	Immigrants = 2, -- random newcomers, to keep genetic drift alive
	CrossoverDominance = 0.5, -- bias toward the fitter parent
	SpeciesPriorSmoothing = 0.15, -- exponential smoothing of the aggregate prior
}

---------------------------------------------------------------------------
-- Senses (docs/02 §2). Ranges are multiplied by the acuity gene at runtime.
---------------------------------------------------------------------------
MonsterConfig.Senses = {
	Channels = { "VIBRATION", "AIR", "SCENT", "THERMAL", "EM", "PRESSURE" },
	-- WP6A observer: the Braid is eyeless. These are the only channels Senses
	-- samples; THERMAL/EM/PRESSURE remain in the field for later WPs.
	ObserverChannels = { "VIBRATION", "AIR", "SCENT" },
	-- Base ranges in studs (docs/02 §2). Expressed stats may override per gene.
	Range = { VIBRATION = 80, AIR = 70, SCENT = 50, THERMAL = 14, EM = 80, PRESSURE = 6 },
	-- Localisation error in studs at acuity 0, scaled by distance.
	ErrorScale = { VIBRATION = 0.35, AIR = 0.20, SCENT = 0.60, THERMAL = 0.10, EM = 0.45, PRESSURE = 0.05 },
	Threshold = { VIBRATION = 0.10, AIR = 0.08, SCENT = 0.06, THERMAL = 0.15, EM = 0.05, PRESSURE = 0.20 },
	-- Material coupling for vibration (multiplier on emitted intensity).
	VibrationCoupling = { Concrete = 1.6, Asphalt = 1.5, Wood = 1.2, Grass = 0.7, Sand = 0.5, Water = 0.1 },
	-- How fast each channel's memory of an event decays (seconds, half-life).
	DecayHalfLife = { VIBRATION = 1.2, AIR = 0.8, SCENT = 45, THERMAL = 3, EM = 0.5, PRESSURE = 0.3 },
	-- How far downwind the field is actually searched for a drifting scent, in
	-- seconds of drift (Shared/NoiseField). Older evidence is the memory layer's
	-- job (docs/02 §3), not the local field's, and the cap is what keeps the
	-- advected sample O(radius^3) in the CELL size rather than O(wind*half-life)^3.
	AdvectionMaxAgeSeconds = 20,
	-- The noise field's spatial cell, studs. Larger than Memory.CellSize because the
	-- field queries by ear-shot radius (tens of studs) and memory queries by interest
	-- cell: one cell size cannot serve both, and a too-small cell turns a sample into a
	-- scan of dozens of buckets.
	NoiseCellSize = 16,
	MaxOcclusionRaysPerTick = 6,
	MaxCandidatesPerTick = 12,
	-- GetPartBoundsInRadius is a bounding-box broad phase (docs/08 §3.1), not exact
	-- geometry. Cached OverlapParams.MaxParts is MaxCandidatesPerTick.
	BroadPhaseRadius = 80,
	-- Observer-only terms (docs/02 §2). Rain/wind/coupling stay on NoiseField.
	DownwindSniffBoost = 1.5,
	WaterImmersionMask = { SCENT = 0.05, VIBRATION = 0.15, AIR = 0.45 },
	AirOcclusionFactor = 0.25,
	-- Stimulus-bridge movement gates, studs/s. Below Still the player is silent on
	-- VIBRATION; at/above Sprint they use SurvivalConfig.Emission.FootstepVibration.Sprinting.
	StillSpeedStuds = 0.35,
	SprintSpeedStuds = 16,
}

---------------------------------------------------------------------------
-- Threat Level (docs/02 §12, docs/00 P5). The one dial every other system reads.
---------------------------------------------------------------------------
MonsterConfig.Threat = {
	-- The difficulty curve as data: night index -> Threat, from docs/02 §12.
	-- Nights past the last entry extrapolate by ThreatPerNightBeyond.
	Curve = { 0.20, 0.35, 0.50, 0.70, 0.85 },
	ThreatPerNightBeyond = 0.10,
	-- A bigger group is a bigger meal: the dial moves with the table, not with one
	-- player's skill. Scales are ADDED to the curve, then clamped.
	PlayersAboveOne = 0.05,
	PlayerCountFloor = 1, -- a 0-player (test) server runs like a solo player
	PerKill = 0.04, -- a completed kill is the loudest signal there is (docs/04 §5)
	PerSurvivedNightBonus = 0.02, -- the group got better too; it is not only the monster
	Min = 0.0,
	Max = 1.0,
	-- How fast the published number is allowed to move, per second. Threat is a
	-- director output, and a director that snaps is felt as a cheat (P4).
	MaxChangePerSecond = 0.02,
	-- Creatures per creature-count ladder, keyed by threat (docs/02 §13 open q 2).
	-- MVP decision: the threat dial changes pacing and behaviour, never count.
	-- An empty threshold list makes creatureCount() stay at one, so Threat 1
	-- remains one readable, woundable monster rather than a surprise swarm.
	CreatureCountAtThreat = {},
}

---------------------------------------------------------------------------
-- Memory (docs/02 §3)
---------------------------------------------------------------------------
MonsterConfig.Memory = {
	WorkingCapacity = 12,
	CellSize = 8, -- spatial hash cell, studs
	Interest = { Kill = 1.0, Grab = 0.6, PreyPerceived = 0.25, LoudNoise = 0.15 },
	InterestDecayHalfLife = 90,
	TimeHeatmapBuckets = 6, -- sixths of a night
	-- Working-evidence confidence half-life. Field decay stays on NoiseField;
	-- this is the observer's memory of a perception (docs/02 §3.1).
	EvidenceHalfLife = 4.5,
	LastKnownMaxAgeSeconds = 22,
	SearchWanderRadius = 16,
	PatrolRadius = 22,
	ConfidenceFloor = 0.08,
}

---------------------------------------------------------------------------
-- Prediction (docs/02 §4)
---------------------------------------------------------------------------
MonsterConfig.Prediction = {
	LocationClasses = { "Open", "Road", "House", "Garage", "Basement", "Roof", "Woods", "Water" },
	PostureClasses = { "Idle", "Scavenging", "Fleeing", "Hiding", "Driving", "Fighting" },
	MinObservations = 12, -- before this, predictions are not trusted
	PredictabilityHigh = 0.60, -- above this: ambush/intercept bonus + a tell
	PredictabilityLow = 0.30, -- below this: fall back to searching
	MinProbabilityToIntercept = 0.50,
}

---------------------------------------------------------------------------
-- Actions (docs/02 §7). 'requires' gates are checked against expressed stats.
---------------------------------------------------------------------------
MonsterConfig.Actions = {
	SEARCH = {},
	INVESTIGATE = {},
	STALK = {},
	AMBUSH = { requires = { Cunning = 0.25 } },
	CHARGE = {},
	CIRCLE = { requires = { Speed = 0.25 } },
	FLUSH = { requires = { Strength = 0.30 } },
	BREACH = { requires = { Strength = 0.45 } },
	LURE = { requires = { Cunning = 0.55 } },
	BURROW = { requires = { Softness = 0.45, Adhesion = 0.30 } },
	FEIGN = { requires = { Cunning = 0.50 } },
	INTERCEPT = { requires = { Cunning = 0.30 } },
	RETREAT = {},
	CONSUME = {}, -- only selectable while holding prey
}

-- Commitment timers stop the creature flip-flopping (docs/02 §9.2).
MonsterConfig.Commitment = {
	MinChargeSeconds = 0.8,
	MaxChargeSeconds = 8.0,
	PreemptScoreDelta = 0.25,
	RefractorySeconds = 0.4,
	CommitRange = 16, -- studs; inside this, CHARGE can beat STALK
}

---------------------------------------------------------------------------
-- Learning (docs/02 §8). Linear function approximation + replacing traces.
---------------------------------------------------------------------------
MonsterConfig.Learning = {
	Alpha = 0.09,
	AlphaDecayN0 = 400, -- alpha = Alpha / (1 + n / N0)
	Gamma = 0.94,
	Lambda = 0.80, -- eligibility trace decay
	TemperatureStart = 1.4,
	TemperatureEnd = 0.35,
	TemperatureTauNights = 3,
	EpsilonFloor = 0.05, -- never stop being surprising
	RewardClamp = 30,
	WeightNormCap = 24,
	KappaNewborn = 2.5, -- how much a newborn trusts its body
	KappaVeteran = 0.60,
	KappaTauDecisions = 120,
	-- Potential-based shaping (Ng, Harada & Russell 1999). ONLY this form
	-- preserves the optimal policy; do not "improve" it.
	ShapingPotentialScale = 1 / 100,
	Rewards = {
		Grab = 8,
		Consume = 25,
		LocalisePrey = 1.2,
		ProximityPerSecond = 0.10,
		ProximityStuds = 5,
		LoseHotTrail = -2.0,
		DamagePerHp = -0.10,
		KnownHazardExtra = -4.0,
		AmbushRevealed = -1.5,
		EnergyPerUnit = -0.008,
		ElapsedPerSecond = -0.02,
	},
	FeatureBuckets = {
		NightPhase = 6,
		LightLevel = 4,
		PreyDistance = 5,
		PreyCount = 4,
		PreyPosture = 6,
		Predictability = 3,
		LastChannel = 7, -- 6 channels + none
		TimeSincePerception = 4,
		TrailState = 4,
		Injury = 4,
		Metabolism = 4,
		Confidence = 3,
		Terrain = 3,
		HazardNearby = 4,
		RecentNoise = 4,
	},
}

---------------------------------------------------------------------------
-- Skeleton / IK (docs/03). Consumed by TendrilRig.
---------------------------------------------------------------------------
MonsterConfig.Rig = {
	-- Cone limits taper along the tendril: stiff base, whippy tip.
	MaxAngleProximal = 35,
	MaxAngleDistal = 70,
	Tolerance = 0.02,
	MaxIterations = 8,
	PlaneBias = 0.6,
	RestBlendIdle = 0.35,
	RestBlendUrgent = 0.0,
	DampBaseStiffness = 30,
	DampTipStiffness = 6,
	NoiseAmplitude = 0.06,
	NoiseFrequency = 0.7,
	TaperExponent = 0.85, -- radius falloff along the chain
}

MonsterConfig.Locomotion = {
	AnchorRayCount = 7,
	AnchorRaySpreadDeg = 55,
	MinAnchors = 2,
	MaxAnchors = 4,
	HaulSeconds = 0.35,
	AnchorGrip = { Concrete = 1.0, Wood = 0.9, Metal = 0.8, Grass = 0.5, Glass = 0.2 },
	GlideSpeedFraction = 0.45, -- open-ground fallback
	ProbeReachMultiplier = 1.15,
}

---------------------------------------------------------------------------
-- Runtime presentation (code-generated MVP; no mesh asset is required).
---------------------------------------------------------------------------
MonsterConfig.Presentation = {
	CoreColor = { 22, 18, 24 },
	TendrilColor = { 48, 36, 52 },
	WoundColor = { 96, 28, 32 },
	Material = "Slate",
	SegmentDepthMultiplier = 0.90,
	CoreTransparency = 0.0,
	SegmentTransparency = 0.0,
	Shadow = true,
}

-- Wounds are disabling, never lethal. A monster may become unable to threaten
-- players, but CreatureService never removes it because of health reaching zero.
MonsterConfig.Wounds = {
	Max = 1.0,
	DisableThreatAt = 0.85,
	SpeedMultiplierAtMax = 0.20,
	ActiveTendrilFractionAtMax = 0.25,
}

MonsterConfig.Spawn = {
	DistanceFromPlayer = 28,
	HeightOffset = 3,
	FallbackX = 0,
	FallbackY = 6,
	FallbackZ = 0,
}

-- The first playable attack is a bounded, server-owned scene. It is deliberately
-- separate from Wounds: it can kill a player, but it can never kill the Braid.
-- CreatureService starts it only after the procedural core reaches this distance.
MonsterConfig.Kill = {
	GrabDistance = 5.5,
	DurationSeconds = 5.8,
	DamageAtLift = 8,
	DamageAtTenderize = 12,
	DismemberAtTenderize = true,
}

---------------------------------------------------------------------------
-- Archetypes (docs/02 §10). Adding a species = a new entry + a rig asset.
---------------------------------------------------------------------------
MonsterConfig.Archetypes = {
	Braid = {
		Enabled = true,
		RigAsset = "Braid",
		Actions = nil, -- nil = use MonsterConfig.Actions
		Notes = "MVP generalist. All channels, all actions.",
	},
	Screamer = {
		Enabled = false,
		RigAsset = "Screamer",
		GeneOverrides = { SenseAir = 1.0, SenseVibration = 0.15 },
		ActionWhitelist = { "SEARCH", "STALK", "CHARGE", "FLUSH", "LURE" },
		Notes = "Hunts by air-sound only; its call masks player hearing.",
	},
	Root = {
		Enabled = false,
		RigAsset = "Root",
		GeneOverrides = { Speed = 0.0, TendrilLength = 1.0, SenseVibration = 1.0 },
		ActionWhitelist = { "SEARCH", "AMBUSH", "FLUSH", "BREACH", "CONSUME" },
		Notes = "Never relocates its core. A territory, not a pursuer.",
	},
}

return MonsterConfig
