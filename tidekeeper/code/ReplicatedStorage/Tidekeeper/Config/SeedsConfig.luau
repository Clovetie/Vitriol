--!strict
-- ReplicatedStorage/Tidekeeper/Config/SeedsConfig (ModuleScript)
--
-- The 64 Seed Drifters (doc 07 section 5, doc 03 section 8).
--
-- WHY THEY EXIST
-- --------------
-- A new post, or a post in a quiet hour, must still have someone come up the
-- steps. Seeds are the floor under the exchange: they are not real players
-- and they never will be, and the Ledger says so. Without them the game's
-- first session is an empty pier, which is the one thing it cannot be.
--
-- WHY THEY HAVE NAMES
-- -------------------
-- doc 03 section 8 says a Seed is "a character, not a statistic". Until
-- iteration 7 they were statistics: 64 anonymous synthesized drifters
-- distinguished only by an index, and because nothing supplied a name for
-- their owner ids, every single one rendered in the Ledger as "Someone".
-- A session test claimed 2398 seed drifters in a simulated month, so the
-- Ledger -- the one surface that carries this game's entire emotional
-- argument -- was mostly a list of anonymous Someones.
--
-- A name is not decoration here. "Maren Holt came at low water and could not
-- get in" is a person you will recognise next week. "Someone came at low
-- water" is a log line.
--
-- THE TASTE BIAS
-- --------------
-- Each Seed leans hard on ONE of the eight taste axes. That is what makes
-- them legible as characters over time rather than reskins of the same
-- shopper: Silas Marr wants deep-water things, Rosalind Vale wants ornate
-- ones, Ruth Candle is kind and Seth Danver is shrewd. A player who notices
-- that has learned something real about the economy, which is the whole
-- design goal of taste vectors.
--
-- Columns:
--   1 id     1..64. Maps to owner id SEED_OWNER_BASE + id - 1.
--   2 name   display name, localisable (doc 11)
--   3 axis   index into DrifterConfig.AXIS_NAMES, 1..8
--   4 bias   the value forced onto that axis, within TASTE_MIN..TASTE_MAX
--
-- Layer: Config (data only).

return {
	-- Seed owner ids sit BELOW any real Roblox account id, so a receipt
	-- addressed to one is routed nowhere and costs nothing. ExchangeService
	-- reads these rather than keeping its own copies.
	SEED_OWNER_BASE = 1000000,
	SEED_COUNT = 64,

	SEEDS = {
		{ 1, "Maren Holt", 6, 70 },
		{ 2, "Oskar Vane", 1, 65 },
		{ 3, "Tilda Ash", 2, 70 },
		{ 4, "Bram Creel", 3, -60 },
		{ 5, "Isla Renn", 5, 75 },
		{ 6, "Caleb Drew", 7, 60 },
		{ 7, "Nessa Pike", 8, -70 },
		{ 8, "Rufus Quay", 4, 65 },
		{ 9, "Opal Birch", 2, 80 },
		{ 10, "Silas Marr", 6, 80 },
		{ 11, "Wren Tolley", 5, 60 },
		{ 12, "Dagan Frost", 8, 70 },
		{ 13, "Esme Fell", 1, -70 },
		{ 14, "Jonas Keel", 3, 70 },
		{ 15, "Lark Mowbray", 7, 75 },
		{ 16, "Verity Stone", 4, -65 },
		{ 17, "Hollis Crane", 6, 55 },
		{ 18, "Petra Lund", 2, -60 },
		{ 19, "Amos Teague", 1, 70 },
		{ 20, "Sorrel Hay", 5, 70 },
		{ 21, "Gideon Rooke", 8, 65 },
		{ 22, "Marigold Penn", 2, 75 },
		{ 23, "Thaddeus Orme", 3, 80 },
		{ 24, "Cora Linnet", 7, -70 },
		{ 25, "Ewan Sable", 6, 65 },
		{ 26, "Delphine Mar", 2, 65 },
		{ 27, "Barnaby Fisk", 4, 70 },
		{ 28, "Ruth Candle", 8, -75 },
		{ 29, "Elias Vorne", 3, 60 },
		{ 30, "Nell Harrow", 1, -65 },
		{ 31, "Crispin Dale", 5, -60 },
		{ 32, "Agnes Wyle", 7, 70 },
		{ 33, "Tobias Reed", 6, 60 },
		{ 34, "Fenna Shaw", 4, -70 },
		{ 35, "Lucian Coombe", 2, 60 },
		{ 36, "Mabel Trask", 8, -60 },
		{ 37, "Rowan Gale", 7, 65 },
		{ 38, "Hester Quill", 1, 75 },
		{ 39, "Jem Oakley", 5, 65 },
		{ 40, "Sybil Crowe", 3, 75 },
		{ 41, "Dorian Pell", 2, 70 },
		{ 42, "Winnie Barrow", 4, 60 },
		{ 43, "Alaric Finch", 6, 75 },
		{ 44, "Clemency Rook", 8, -65 },
		{ 45, "Hamish Dunn", 1, -60 },
		{ 46, "Lavinia Mead", 2, 85 },
		{ 47, "Corin Wade", 7, 55 },
		{ 48, "Ottoline Fay", 5, 80 },
		{ 49, "Ezra Blackwood", 3, 65 },
		{ 50, "Maud Sterling", 8, 75 },
		{ 51, "Piers Calloway", 4, 75 },
		{ 52, "Greta Lisle", 6, 70 },
		{ 53, "Ivor Benn", 1, 60 },
		{ 54, "Perpetua Crane", 2, 55 },
		{ 55, "Joss Tremain", 7, 80 },
		{ 56, "Edith Marrow", 5, 55 },
		{ 57, "Aubrey Strand", 6, 85 },
		{ 58, "Niamh Carrick", 3, -70 },
		{ 59, "Gilbert Hoy", 4, -60 },
		{ 60, "Rosalind Vale", 2, 90 },
		{ 61, "Seth Danver", 8, 80 },
		{ 62, "Bridie Nolan", 5, 85 },
		{ 63, "Alban Sykes", 1, 80 },
		{ 64, "Marguerite Lowe", 3, 85 },
	},
}
