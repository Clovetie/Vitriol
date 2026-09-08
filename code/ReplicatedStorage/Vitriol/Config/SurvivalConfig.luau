--!strict
-- SurvivalConfig.luau
-- Location: ReplicatedStorage > Vitriol > Config > SurvivalConfig  (ModuleScript)
-- Purpose:  Hunger / thirst drain curves, the coupling terms, and every debuff
--           declared as DATA (docs/05-SURVIVAL.md). Adding or removing a debuff
--           must never require a code change.
-- Requires: (none)
-- Used by:  Services/SurvivalService, Client/PostProcessDriver, Client/SurvivalHud

local SurvivalConfig = {}

-- Meters rise as need increases (0 = sated, 100 = critical).
-- Drain rates are per MINUTE at the named activity level (docs/05 §1).
SurvivalConfig.ActivityDrain = {
	--            thirst  hunger
	Resting = { thirst = 0.55, hunger = 0.30 },
	Walking = { thirst = 0.80, hunger = 0.42 },
	Sprinting = { thirst = 2.10, hunger = 0.95 },
	Carrying = { thirst = 1.10, hunger = 0.60 },
	Driving = { thirst = 0.70, hunger = 0.35 },
	Crawling = { thirst = 0.65, hunger = 0.35 },
}

-- Conditional multipliers (docs/05 §1).
SurvivalConfig.Modifiers = {
	BleedingThirst = 1.35,
	BleedingHunger = 1.10,
	HotThirst = 1.25,
	HotHunger = 1.05,
	ColdThirst = 1.10,
	ColdHunger = 1.25,
	ImmersedThirst = 0.90,
	StarvedThirst = 1.20,
	ParchedHunger = 1.15,
}

-- The coupling the design depends on: each meter accelerates the other once it
-- passes its threshold. `Width` makes it a smoothstep, never a cliff.
SurvivalConfig.Coupling = {
	ThirstFromHunger = 0.20, -- +20% thirst rate while hunger > threshold
	HungerFromThirst = 0.15,
	Threshold = 70,
	Width = 5,
	StaminaPenaltyPerMeter = 0.5,
}

SurvivalConfig.Stamina = {
	Max = 100,
	SprintDrainPerSecond = 14,
	RegenPerSecond = 9,
	RegenDelayAfterSprint = 1.5,
	ExhaustionDuration = 6,
}

-- Debuffs are pure data. SurvivalService composes them multiplicatively per key
-- and deduplicates cues by Priority (docs/05 §3.3).
SurvivalConfig.Debuffs = {
	Dry = {
		Trigger = { meter = "thirst", at = 55 },
		WalkSpeed = 0.97, StaminaRegen = 0.90,
		AudioCues = { "dry_mouth" }, Priority = 10,
	},
	Parched = {
		Trigger = { meter = "thirst", at = 80 },
		WalkSpeed = 0.88, JumpPower = 0.85, StaminaRegen = 0.65,
		ScentScale = 1.5, NoiseScale = 1.0,
		ScreenFx = { "ThirstPulse", "Desaturate" },
		AudioCues = { "dry_mouth", "throat_on_sprint" }, Priority = 40,
	},
	Desiccated = {
		Trigger = { meter = "thirst", at = 100 },
		WalkSpeed = 0.70, StaminaRegen = 0.35, HealthDrain = 0.4,
		ScentScale = 2.0, ScreenFx = { "Tunnel", "Desaturate" },
		AudioCues = { "heavy_breathing", "audio_muffle" }, Priority = 70,
	},
	Peckish = {
		Trigger = { meter = "hunger", at = 55 },
		WalkSpeed = 0.98, StaminaRegen = 0.92,
		AudioCues = { "stomach_soft" }, Priority = 10,
	},
	Starved = {
		Trigger = { meter = "hunger", at = 80 },
		WalkSpeed = 0.85, JumpPower = 0.80, StaminaRegen = 0.50,
		CarryCapacity = 0.6, HealthDrain = 0.25, RegionIntegrity = 0.85,
		-- A growling stomach is a noise source: hunger is audible to the creature.
		NoiseScale = 1.15,
		ScreenFx = { "Vignette", "HandShake" },
		AudioCues = { "stomach_growl" }, Priority = 45,
	},
	Collapse = {
		-- Compound trigger, see Collapse.Triggers below.
		WalkSpeed = 0.25, JumpPower = 0, StaminaRegen = 0,
		ScentScale = 1.6, NoiseScale = 1.0,
		ScreenFx = { "CollapseTunnel", "InputLag" },
		AudioCues = { "collapse_fall", "gasping" }, Priority = 100,
	},
	Bleeding = {
		WalkSpeed = 1.0, HealthDrain = 0.0, -- rate comes from the wound itself
		ScentScale = 1.0, -- plus 6 * woundRate, applied by HealthService
		ScreenFx = { "BloodVignette" }, AudioCues = { "drip" }, Priority = 60,
	},
	Sick = {
		Trigger = { timed = 90 },
		WalkSpeed = 0.90, DrainMultiplier = 1.5,
		ScreenFx = { "NauseaRoll" }, AudioCues = { "nausea" }, Priority = 55,
	},
	Exhausted = {
		Trigger = { timed = 6 },
		WalkSpeed = 0.75,
		AudioCues = { "gasping" }, Priority = 50,
	},
	Weakened = {
		Trigger = { timed = 60 },
		WalkSpeed = 0.92, StaminaRegen = 0.8, Priority = 20,
	},
}

-- Collapse is a compound state, not a single meter threshold (docs/05 §3.2).
SurvivalConfig.Collapse = {
	Triggers = {
		{ thirst = 100, hunger = 80 },
		{ hunger = 100, thirst = 80 },
	},
	HealthThreshold = 15,
	HealthRequiresBothMetersAt = 60,
	OnsetDelaySeconds = 1.5,
	-- Collapsing is LOUD. This is what ties the survival layer into the horror.
	FallVibrationIntensity = 0.9,
	CrawlDurationSeconds = 8,
	RecoveryRequiresBoth = true,
	WeakenedDurationSeconds = 60,
}

-- Consumption (docs/05 §4). All validated server-side by InventoryService.
SurvivalConfig.Consumables = {
	CleanWater = { thirst = -35, sickChance = 0.00, seconds = 2.0, noiseAir = 0.15 },
	DirtyWater = { thirst = -25, sickChance = 0.35, seconds = 2.5, noiseAir = 0.20 },
	CannedFood = { hunger = -40, sickChance = 0.00, seconds = 3.0, noiseAir = 0.40 },
	RawMeat = { hunger = -20, sickChance = 0.50, seconds = 3.0, noiseAir = 0.25 },
	CookedMeat = { hunger = -45, sickChance = 0.00, seconds = 3.0, noiseAir = 0.25 },
	SpoiledFood = { hunger = -15, sickChance = 1.00, seconds = 2.5, noiseAir = 0.30 },
	Bandage = { bleeding = true, health = 10, seconds = 3.0, noiseAir = 0.35 },
	Medkit = { bleeding = true, health = 25, seconds = 4.0, noiseAir = 0.40 },
}

-- Health, wounds and bleeding (docs/05 §1, §3.3; the part HealthService owns).
-- SurvivalService drives hunger/thirst; this block is the body's own ledger, and
-- the split is deliberate: HealthService is the ONLY writer of Humanoid health for
-- wounds, so a wound's rate cannot be applied twice.
SurvivalConfig.Health = {
	Max = 100,
	-- Below this the player is Incapacitated rather than dead (docs/05 §3.2:
	-- collapse is a compound state, and a corpse has no second chance).
	IncapacitatedThreshold = 15,
	-- Natural recovery, per second, only while it is cheap to heal: no bleeding and
	-- both meters below the coupling threshold (docs/05 §2).
	RegenPerSecond = 0.06,
	-- Regen additionally requires the meters (docs/05 §2), which SurvivalService owns
	-- from WP8; it reports that precondition through HealthService:metersAllowRegen
	-- rather than writing HP here. No threshold is duplicated in this table, because a
	-- second copy of "how hungry is too hungry" is two numbers that can disagree.
	-- A severed limb re-ranks the wound that caused it (docs/04 §4).
	SeveredBleedMultiplier = 2.5,
	-- Wounds are data, so a new injury type never needs a code change.
	--   BleedRate    : health lost per second while untreated
	--   ScentRate    : multiplier on Emission.BloodScentPerRate (docs/02 §2, blood x6)
	--   ClotSeconds  : time to stop bleeding unaided; bandages cut it to zero
	--   TreatSeconds : how long a bandage takes, and therefore how loud it is
	Wounds = {
		Laceration = { BleedRate = 0.30, ScentRate = 1.0, ClotSeconds = 45, TreatSeconds = 3.0 },
		Puncture = { BleedRate = 0.45, ScentRate = 1.4, ClotSeconds = 60, TreatSeconds = 3.5 },
		Avulsion = { BleedRate = 0.75, ScentRate = 2.0, ClotSeconds = 90, TreatSeconds = 4.5 },
		Bruise = { BleedRate = 0.0, ScentRate = 0.0, ClotSeconds = 20, TreatSeconds = 2.0 },
		Burn = { BleedRate = 0.20, ScentRate = 0.4, ClotSeconds = 30, TreatSeconds = 4.0 },
	},
	BleedCueSeconds = 4, -- how often the drip audio is re-cued; the HUD stays empty
}

-- Noise emitted by the player's own body, feeding NoiseField (docs/02 §2).
SurvivalConfig.Emission = {
	FootstepVibration = { Resting = 0.0, Walking = 0.25, Sprinting = 0.70, Crawling = 0.08, Carrying = 0.35 },
	BreathAir = 0.05,
	BaseScent = 0.20,
	BloodScentPerRate = 6.0,
	-- The drip a bleeding player makes (docs/05 §3.1's "drip audio" cue). Intensity is
	-- in the noise field's 0..1 perceptual units, the same currency every other
	-- emission here uses; what "loud" means for a given creature is its own
	-- threshold, which is MonsterConfig.Senses.Threshold's job (WP6), not this
	-- number's. Deliberately far below FootstepVibration: bleeding is a clue you can
	-- be quieter than, not a dinner bell.
	BloodAirIntensity = 0.06,
	CorpseScent = 0.80,
	CorpseScentDecaySeconds = 360,
}

return SurvivalConfig
