--!strict
-- BloodConfig.luau
-- Location: ReplicatedStorage > Vitriol > Config > BloodConfig  (ModuleScript)
-- Purpose:  The shipped, low-intensity blood presentation policy and the adapter
--           settings for rotntake/BloodEngine. Body integrity and kill timing stay
--           in GoreConfig for backwards compatibility; visual blood no longer has
--           a legacy Gore module dependency.
-- Requires: Config/GoreConfig
-- Used by:  Shared/BloodAdapter, Creature/Body/KillChoreography, HealthService

local GoreConfig = require(script.Parent.GoreConfig)
local BloodConfig = {}

-- BloodEngine's documented constructor is BloodEngine.new(settings), followed by
-- Engine:Emit(origin, direction, optional per-emission settings). These values are
-- intentionally conservative: the engine is an effect budget, not a second gameplay
-- system. See the upstream MIT project README and docs/04 §3.
BloodConfig.Engine = {
	ModuleName = "BloodEngine",
	ModuleLocations = {
		-- The supplied project hierarchy: ReplicatedStorage > VModules > BloodEngine.
		"ReplicatedStorage/VModules/BloodEngine",
		"ServerStorage/Vitriol/Assets/BloodEngine",
		"ServerStorage/Vitriol/Assets/GoreAssets/BloodEngine",
		"ReplicatedStorage/Vitriol/Assets/BloodEngine",
		"ReplicatedStorage/Vitriol/Shared/BloodEngine",
	},
	Limit = 120,
	FolderName = "Vitriol_Blood",
	Type = "Default",
	RandomOffset = false,
	OffsetRange = { -2, 2 },
	DropletVelocity = { 1, 2 },
	DropletDelay = { 0, 0 },
	StartingSize = { 0.04, 0.24, 0.04 },
	Expansion = true,
	MaximumSize = 0.7,
	PoolLifetimeSeconds = 180,
}

-- FULL is still stylised and budgeted. LOW removes sever visuals, not the gameplay
-- state transition, so accessibility/content settings cannot change the simulation.
BloodConfig.Intensity = GoreConfig.Intensity
-- The prototype ships LOW even though the legacy GoreConfig kept FULL as its
-- historical default. Settings can opt into FULL without changing wound state.
BloodConfig.DefaultIntensity = "LOW"
BloodConfig.BloodColor = GoreConfig.BloodColor
BloodConfig.Budget = GoreConfig.Budget
BloodConfig.Fallback = GoreConfig.Fallback

-- Limb removal is an opt-in presentation layer. LOW keeps this false by default;
-- enabling it still leaves the player's health/death authority in HealthService.
BloodConfig.Dismemberment = {
	Enabled = false,
	AllowedRegions = { "LeftArm", "RightArm", "LeftLeg", "RightLeg", "LeftHand", "RightHand" },
}

BloodConfig.Kinds = {
	blood_spray = true,
	blood_mist = true,
	blood_pool = true,
	severed = true,
	chunk = true,
	viscera = true,
	gib_burst = true,
}

return BloodConfig
