--!nonstrict
-- ReplicatedStorage/Tidekeeper/Config/FindsConfig (ModuleScript)
--
-- *** REPRESENTATIVE SUBSET -- 24 of the planned 200 finds. ***
--
-- Iteration 2 needs enough finds to exercise matching, pricing, spoilage,
-- grouping and the Almanac bitset honestly; it does not need the full catalogue,
-- and inventing 200 rows of untuned content now would be fake progress.
-- Iteration 5 owns the remaining 176 rows and the drop tables (doc 09).
--
-- Contract for the missing rows: ids 1..256 only (the Almanac bitset is 32
-- bytes), ids are never reused, and every row must keep the column order below.
--
-- Columns:
--   1 id              u16, 1..256, stable forever
--   2 name            string, display key (not player-facing copy; doc 11)
--   3 baseValue       integer coin, the `V` in pricePressure
--   4 perishable      0 | 1
--   5 group           index into GROUP_NAMES (the `offer only <group>` action)
--   6 zone            1 inner flats .. 4 outer bar (doc 02 section 7)
--   7 rarityPerMille  beachcombing weight within its zone
--   8 tasteVec        8 signed axes, DrifterConfig.AXIS_NAMES order
--
-- Layer: Config (data only).

return {
	GROUP_NAMES = { "Shell", "Glass", "Metal", "Bone", "Cloth", "Curio" },
	MAX_FIND_ID = 256,
	ZONE_COUNT = 4,

	FINDS = {
		-- id  name                    V   per grp zone rar  taste
		{ 1, "cockle_shell", 3, 0, 1, 1, 220, { -70, -50, -60, -10, 10, -60, 0, -20 } },
		{ 2, "razor_shell", 5, 0, 1, 1, 170, { -60, -20, -50, -10, 0, -40, 20, -10 } },
		{ 3, "sea_glass_green", 9, 0, 2, 1, 120, { -30, 30, -20, 0, 20, -20, -10, 10 } },
		{ 4, "sea_glass_cobalt", 26, 0, 2, 2, 55, { -10, 60, 20, 10, 30, 10, -10, 20 } },
		{ 5, "bottle_stopper", 7, 0, 2, 1, 140, { -40, 10, -30, 0, 0, -30, 10, 0 } },
		{ 6, "bent_nail", 2, 0, 3, 1, 240, { -90, -70, -80, -20, -30, -70, 30, -40 } },
		{ 7, "brass_button", 14, 0, 3, 2, 95, { 10, 40, 0, 0, 40, -10, 0, 0 } },
		{ 8, "ship_rivet", 21, 0, 3, 2, 70, { -20, -30, 10, -10, -20, 30, 0, 20 } },
		{ 9, "compass_card", 88, 0, 3, 3, 24, { 40, 50, 50, 20, 10, 70, -20, 30 } },
		{ 10, "gull_bone", 4, 1, 4, 1, 180, { -60, -40, -50, -20, -30, -20, 40, -50 } },
		{ 11, "whale_ear", 140, 0, 4, 4, 9, { 20, 20, 70, 30, -10, 90, -10, 40 } },
		{ 12, "scrimshaw_pin", 190, 0, 4, 3, 12, { 70, 80, 70, 30, 40, 60, -20, 30 } },
		{ 13, "sail_scrap", 6, 1, 5, 1, 160, { -50, -40, -40, -10, 0, -30, 20, -20 } },
		{ 14, "net_float", 11, 0, 5, 2, 110, { -30, -20, -20, 0, 10, -10, 10, -10 } },
		{ 15, "signal_flag", 47, 0, 5, 3, 38, { 30, 40, 20, 20, 60, 20, 10, 20 } },
		{ 16, "lamp_wick", 8, 1, 5, 2, 130, { 0, -10, -20, -10, 30, 0, 0, 40 } },
		{ 17, "tide_token", 33, 0, 6, 2, 60, { 20, 30, 20, 30, 40, 40, 20, 30 } },
		{ 18, "clock_spring", 120, 0, 6, 3, 18, { 60, 50, 60, 10, -20, 70, -40, 40 } },
		{ 19, "message_vial", 64, 0, 6, 3, 30, { 10, 40, 30, 40, 80, 50, 30, 70 } },
		{ 20, "lantern_glass", 310, 0, 2, 4, 6, { 30, 90, 80, 20, 60, 60, -30, 50 } },
		{ 21, "deepwater_coral", 420, 1, 6, 4, 4, { 0, 70, 90, 40, 20, 100, 0, 30 } },
		{ 22, "chart_fragment", 205, 0, 6, 4, 8, { 50, 30, 60, 30, 10, 90, -10, 20 } },
		{ 23, "salt_cake", 12, 1, 6, 1, 105, { -70, -60, -40, -30, -10, -50, 50, -30 } },
		{ 24, "keeper_seal", 760, 0, 6, 4, 2, { 80, 100, 100, 50, 50, 80, -40, 60 } },
	},
}
