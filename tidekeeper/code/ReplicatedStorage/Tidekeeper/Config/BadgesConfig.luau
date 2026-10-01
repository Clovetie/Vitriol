--!strict
-- ReplicatedStorage/Tidekeeper/Config/BadgesConfig (ModuleScript)
--
-- The 40 achievements (doc 07 section 5). Config only -- awarding them is
-- iteration 8's job, and deliberately so: the data has to exist and be
-- validated before anything can be built against it.
--
-- WHAT A BADGE MAY READ, AND WHY THE LIST IS SHORT
-- -----------------------------------------------
-- A badge may test exactly one counter from STAT_NAMES against a threshold.
-- It may not run code, combine conditions, or read anything else.
--
-- That restriction is the whole design. The moment badges can express
-- arbitrary conditions they become a second progression system with its own
-- balance, its own exploits and its own save format, and every one of them
-- has to be re-tested whenever the economy moves. A flat table of
-- (stat, threshold) can be checked in one pass at the end of a resolve, is
-- trivially serialisable as a bitmask, and cannot disagree with the economy
-- because it only reads from it.
--
-- NOTHING HERE IS EVER REVOKED. doc 06 section 2 is explicit that a long
-- absence costs progress but never erases an achievement. So every stat is
-- a LIFETIME counter, never a current balance: "Purse of Fifty" is fifty
-- coin earned in total, not fifty coin held, because the second kind would
-- un-earn itself the moment the player spent it.
--
-- Columns:
--   1 id         1..40, stable forever, persisted as a bit index
--   2 name       display name, localisable (doc 11)
--   3 kind       1 counter, 2 milestone, 3 collection
--   4 stat       index into STAT_NAMES
--   5 threshold  the value the stat must reach
--   6 hidden     1 = not listed until earned (the long-tail ones)
--
-- Layer: Config (data only).

return {
	STAT_NAMES = {
		"visitorsServed",      -- 1
		"coinEarnedLifetime",  -- 2
		"shelvesUnlocked",     -- 3
		"tierReached",         -- 4
		"almanacEntries",      -- 5
		"lettersSent",         -- 6
		"lettersReceived",     -- 7
		"giftsGiven",          -- 8
		"driftersDispatched",  -- 9
		"currentsUnlocked",    -- 10
		"tideStatesSeen",      -- 11
		"tidesElapsed",        -- 12
	},

	KIND_COUNTER = 1,
	KIND_MILESTONE = 2,
	KIND_COLLECTION = 3,

	BADGES = {
		{ 1, "First Light", 2, 1, 1, 0 },
		{ 2, "Open for Trade", 1, 1, 10, 0 },
		{ 3, "A Hundred Hellos", 1, 1, 100, 0 },
		{ 4, "A Thousand Steps", 1, 1, 1000, 0 },
		{ 5, "Ten Thousand Tides", 1, 1, 10000, 1 },
		{ 6, "First Coin", 2, 2, 1, 0 },
		{ 7, "Purse of Fifty", 1, 2, 50, 0 },
		{ 8, "Five Hundred", 1, 2, 500, 0 },
		{ 9, "Five Thousand", 1, 2, 5000, 0 },
		{ 10, "Fifty Thousand", 1, 2, 50000, 1 },
		{ 11, "Second Shelf", 2, 3, 2, 0 },
		{ 12, "Full House", 1, 3, 6, 0 },
		{ 13, "Ten Shelves", 1, 3, 10, 0 },
		{ 14, "Sixteen Shelves", 1, 3, 16, 0 },
		{ 15, "Twenty-Four", 1, 3, 24, 1 },
		{ 16, "Tier Two", 2, 4, 2, 0 },
		{ 17, "Tier Three", 2, 4, 3, 0 },
		{ 18, "Tier Four", 2, 4, 4, 0 },
		{ 19, "Almanac Ten", 1, 5, 10, 0 },
		{ 20, "Almanac Fifty", 1, 5, 50, 0 },
		{ 21, "Almanac Hundred", 1, 5, 100, 0 },
		{ 22, "Almanac Complete", 3, 5, 200, 1 },
		{ 23, "First Letter Sent", 2, 6, 1, 0 },
		{ 24, "Correspondent", 1, 6, 25, 0 },
		{ 25, "Postmaster", 1, 6, 250, 1 },
		{ 26, "First Letter Home", 2, 7, 1, 0 },
		{ 27, "Well Liked", 1, 7, 50, 0 },
		{ 28, "First Gift", 2, 8, 1, 0 },
		{ 29, "Open Handed", 1, 8, 25, 0 },
		{ 30, "Nothing Asked", 1, 8, 200, 1 },
		{ 31, "First Dispatch", 2, 9, 1, 0 },
		{ 32, "Far Trader", 1, 9, 50, 0 },
		{ 33, "The Long Run", 1, 9, 500, 1 },
		{ 34, "Coldwater Regular", 2, 10, 1, 0 },
		{ 35, "The Glass Road", 2, 10, 2, 0 },
		{ 36, "Longrun Licence", 2, 10, 3, 0 },
		{ 37, "The Lantern Line", 2, 10, 4, 1 },
		{ 38, "Slack Water", 2, 11, 1, 0 },
		{ 39, "Spring Tide", 2, 11, 2, 0 },
		{ 40, "A Year of Tides", 1, 12, 365, 1 },
	},
}
