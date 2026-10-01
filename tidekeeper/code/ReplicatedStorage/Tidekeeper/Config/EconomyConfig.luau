--!nonstrict
-- ReplicatedStorage/Tidekeeper/Config/EconomyConfig (ModuleScript)
--
-- Prices, curves, Standing bands, match weights. Doc 06 is the rationale; this
-- file is the contract the simulation actually reads.
--
-- Every value that touches money or stock is an INTEGER. Floats appear only in
-- scoring, and a score never becomes a currency without passing through
-- math.floor at a documented place.
--
-- Layer: Config (data only).

return {
	-- Standing (doc 06 section 2) --------------------------------------------
	STANDING_MAX = 65535,
	-- Once a band is crossed, Standing never falls below it again.
	STANDING_BANDS = { 250, 1000, 4000, 12000, 30000 },
	-- 2.5% of (value - bandFloor) per tide epoch, computed in integers as
	-- floor(delta * STANDING_DECAY_PER_MILLE / 1000).
	STANDING_DECAY_PER_MILLE = 25,

	-- Standing and Renown deltas per visit outcome.
	STANDING_ON_SERVED = 34,
	STANDING_ON_PARTIAL = 12,
	STANDING_ON_REFUSED = -60,
	STANDING_ON_GIFT = 110,
	STANDING_ON_MISSED_TIDE = 0,
	RENOWN_ON_SERVED = 1,
	RENOWN_ON_GIFT = 9,

	-- Currents (doc 06 section 2) --------------------------------------------
	-- Index 1..5 maps to Current id 0..4: Shallows, Coldwater, Glass Road,
	-- Longrun, Lantern Line.
	CURRENT_COUNT = 5,
	CURRENT_NAMES = { "The Shallows", "Coldwater", "The Glass Road", "Longrun", "The Lantern Line" },
	CURRENT_MIN_TIER = { 1, 2, 2, 3, 4 },
	-- One 8-axis taste bias per Current, in the axis order of doc 03 section 5
	-- (see DrifterConfig.AXIS_NAMES). Arrays, not named keys, so the dead-config
	-- scanner does not read axis names as config knobs.
	CURRENT_TASTE_BIAS = {
		{ -40, 0, -30, 0, 0, 0, 0, 0 },
		{ 0, -60, 0, 0, 0, 0, 50, 0 },
		{ 0, 70, 60, 0, 0, 0, 0, 0 },
		{ 0, 0, 0, 40, 0, 65, 0, 0 },
		{ 0, 0, 0, 0, 70, 0, 0, 60 },
	},

	-- Price pressure (doc 06 section 3) --------------------------------------
	-- pricePressure(price, baseValue, dearTaste):
	--   r     = price / baseValue
	--   ideal = PRICE_IDEAL_BASE + PRICE_DEAR_COEFF * dearTaste
	--   result = clamp(PRICE_PRESSURE_PEAK - PRICE_PRESSURE_SLOPE * |r - ideal|, -1, 1)
	PRICE_IDEAL_BASE = 1.0,
	PRICE_DEAR_COEFF = 0.006,
	PRICE_PRESSURE_PEAK = 1.6,
	PRICE_PRESSURE_SLOPE = 2.2,
	-- Above this markup a successful sale still costs warmth.
	PRICE_SOUR_RATIO = 2.2,

	-- Match scoring (doc 04 section 4 stage 4) --------------------------------
	MATCH_W_TASTE = 1.0,
	MATCH_W_WANTS = 0.8,
	MATCH_W_PRICE = 0.6,
	MATCH_W_NOISE = 0.25,
	MATCH_NOISE_SD = 0.12,
	-- A candidate below this score is never bought. Tuned in iteration 5 with
	-- real Ledger data; provisional here and asserted only for sign.
	MATCH_THRESHOLD = 0.15,

	-- Warmth (-128..127 on the wire, i8) --------------------------------------
	WARMTH_BASE_SERVED = 30,
	WARMTH_BASE_PARTIAL = 6,
	WARMTH_BASE_REFUSED = -55,
	WARMTH_BASE_MISSED_TIDE = -4,
	WARMTH_BASE_NO_BERTH = -12,
	WARMTH_BASE_GIFT = 95,
	WARMTH_PER_WANT_MET = 18,
	WARMTH_SOUR_PRICE = -22,
	WARMTH_MIN = -128,
	WARMTH_MAX = 127,

	-- Passive income (doc 06 section 4) ---------------------------------------
	-- Coin to reach each tier, indexed BY THE TIER BEING BOUGHT. Index 1 is
	-- zero because every post starts at tier 1.
	--
	-- THESE NUMBERS WERE MEASURED, NOT INVENTED.
	-- tools/tests/economy-sim.lua simulates 12 seeds x 70 days of a
	-- diligent-but-not-optimal player (2 sessions/day, naive base-value
	-- pricing, buys the next tier the moment it can afford it) and reports
	-- the day each seed reached each tier. Final calibration against the
	-- pacing targets in doc 06 section 7:
	--
	--   tier    p10   median   p90      doc 06 target
	--   2         3        3     5      day 3
	--   3        14       17    20      day 16
	--   4        49       50    55      day 52
	--
	-- All 12 seeds reach tier 4. Three rounds of calibration were needed
	-- because PROMOTION COMPOUNDS: a promoted post has more shelves, a
	-- higher passive cap and access to richer currents, so each tier makes
	-- the next one arrive faster. The first attempt was read off a curve
	-- measured with every post locked at tier 1 -- which was the only curve
	-- obtainable at the time, since nothing in the game could promote a post
	-- -- and it put tier 4 at day 22 instead of day 52. A progression curve
	-- cannot be calibrated against a simulation that cannot progress.
	--
	-- The model is the FAST end of the distribution: it never hesitates and
	-- never spends on anything else. Real players will be slower, so these
	-- are a floor on the time-to-tier, not a promise.
	--
	-- Re-run after ANY change to income, find values or passive caps:
	--   node tidekeeper/tools/tidekeeper-session-test.js \
	--     --tests tools/tests/economy-sim.lua
	TIER_COST = { 0, 320, 3400, 15500 },

	PASSIVE_CAP_BY_TIER = { 40, 130, 420, 1200 },
	-- Passive coin is a per-mille share of the coin value actually shelved, so
	-- an empty post earns nothing even at tier 4.
	PASSIVE_RATE_PER_MILLE = 6,

	-- Stock upkeep -------------------------------------------------------------
	-- Perishables lose this share of their stack per epoch (integer floor, with
	-- a guaranteed minimum of 1 when the stack is non-empty and perishable).
	SPOIL_PER_MILLE = 80,
	-- Beachcombing nodes mature this many epochs after being harvested.
	COMB_RESPAWN_EPOCHS = 2,

	-- Long absence (doc 04 section 3.1) ---------------------------------------
	-- The "found while you were away" cache, so returning is pleasant.
	LONG_ABSENCE_CACHE_COIN = 120,
	LONG_ABSENCE_CACHE_ITEMS = 3,

	-- Per-visit limits ---------------------------------------------------------
	MAX_ITEMS_PER_VISIT = 4,
	MIN_PRICE = 1,
	MAX_PRICE = 4294967,
}
