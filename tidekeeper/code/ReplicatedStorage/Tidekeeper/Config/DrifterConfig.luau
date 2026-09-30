--!nonstrict
-- ReplicatedStorage/Tidekeeper/Config/DrifterConfig (ModuleScript)
--
-- Drifter classes, taste axes and budget bands (doc 03 sections 4-5).
--
-- Taste axes are int8 (-100..100 in practice). They are NEVER shown to the
-- player as numbers -- the UI renders them as phrases (doc 03 section 5). The
-- names here exist for tooling and for the Orders language's `taste.<axis>`
-- condition.
--
-- Layer: Config (data only).

return {
	TASTE_AXES = 8,
	TASTE_MIN = -100,
	TASTE_MAX = 100,
	-- Lua index 1..8 corresponds to doc 03's 0-based axis 0..7.
	AXIS_NAMES = {
		"salvage_craft",
		"plain_ornate",
		"cheap_dear",
		"hoard_spend",
		"solitary_social",
		"shallow_deep",
		"steady_erratic",
		"kind_shrewd",
	},
	-- The "dear" axis drives pricePressure. Doc 04 section 4 writes `D.taste[2]`
	-- using doc 03's 0-based numbering; in Lua that is index 3.
	AXIS_DEAR = 3,
	AXIS_SOCIAL = 5,
	AXIS_KIND = 8,

	-- Classes (doc 03 section 4). Array rows so the dead-config scanner does not
	-- treat the class names as config keys:
	--   {name, id, minTier, valueMultiplierPerMille, arrivalWeightPerMille, maxItems}
	-- Tide admissibility is a separate array below because it is a set.
	CLASSES = {
		{ "SKIFF", 0, 1, 1000, 550, 1 },
		{ "LAUNCH", 1, 2, 2200, 250, 2 },
		{ "LUGGER", 2, 3, 5000, 140, 3 },
		{ "DEEPWATER", 3, 4, 14000, 60, 4 },
	},
	-- Per class (same row order as CLASSES), the tide states that admit it.
	-- Strings match Tide.state() exactly.
	CLASS_TIDES = {
		{ "LOW", "EBB", "FLOOD", "SLACK", "HIGH" },
		{ "EBB", "FLOOD", "SLACK", "HIGH" },
		{ "SLACK", "HIGH" },
		{ "HIGH" },
	},

	-- Budget bands by class row: {min, max} in coin, before the visitor's own
	-- tier and Standing scale it.
	BUDGET_BANDS = {
		{ 20, 140 },
		{ 120, 620 },
		{ 500, 2400 },
		{ 2000, 11000 },
	},

	MAX_WANTS = 4,
	MAX_CARGO = 4,
	MAX_BEACONS = 255,
}
