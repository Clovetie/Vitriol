--!strict
-- ReplicatedStorage/Tidekeeper/Config/LettersConfig (ModuleScript)
--
-- The 120 authored letter phrases (doc 07 section 5, doc 13 section 2).
--
-- WHY A NUMBER AND NOT A STRING
-- -----------------------------
-- A letter in TIDEKEEPER is an INDEX into this list. There is no free text
-- anywhere in the game, which is a safety decision taken in iteration 1 and
-- never revisited: it means there is no text filtering on any hot path, no
-- way to smuggle a message past moderation, and the worst thing a stranger
-- can send a nine-year-old is phrase 41. The cost is expressiveness. The
-- benefit is that the async social layer is safe by construction rather than
-- by moderation, which is the only kind of safe that scales.
--
-- Every phrase in here is therefore written to be harmless when sent by a
-- stranger, to a child, in any order, out of any context, at any time:
--   * no requests for personal information, age, location or contact;
--   * no arrangements to meet, here or anywhere else;
--   * no insults, no pressure, no negging, no begging for items;
--   * nothing that reads as a threat, even sarcastically;
--   * nothing that only makes sense as a reply, since letters arrive alone.
-- Adding a phrase means re-reading that list. The ids are PERSISTED in
-- receipts and drifter blobs, so a phrase may be reworded but an id must
-- NEVER be reused for a different sentiment.
--
-- Columns:
--   1 id        u16, 1..120, stable forever
--   2 category  index into CATEGORY_NAMES
--
-- The TEXT lives in Client/Strings.LETTER, not here. Same split as finds:
-- this module is the stable, persisted, server-validated data, and Strings
-- holds the localisable copy (doc 11). The server never needs the words.
--
-- Layer: Config (data only).

return {
	CATEGORY_NAMES = { "Thanks", "Greeting", "Goods", "Weather", "Encouragement", "Farewell", "Regret" },

	-- The server validates a dispatched letter index against this ceiling so a
	-- forged or stale index cannot address a phrase that does not exist.
	MAX_LETTER_ID = 120,

	LETTERS = {
		{ 1, 1 },
		{ 2, 1 },
		{ 3, 1 },
		{ 4, 1 },
		{ 5, 1 },
		{ 6, 1 },
		{ 7, 1 },
		{ 8, 1 },
		{ 9, 1 },
		{ 10, 1 },
		{ 11, 1 },
		{ 12, 1 },
		{ 13, 1 },
		{ 14, 1 },
		{ 15, 1 },
		{ 16, 1 },
		{ 17, 1 },
		{ 18, 1 },
		{ 19, 2 },
		{ 20, 2 },
		{ 21, 2 },
		{ 22, 2 },
		{ 23, 2 },
		{ 24, 2 },
		{ 25, 2 },
		{ 26, 2 },
		{ 27, 2 },
		{ 28, 2 },
		{ 29, 2 },
		{ 30, 2 },
		{ 31, 2 },
		{ 32, 2 },
		{ 33, 2 },
		{ 34, 2 },
		{ 35, 2 },
		{ 36, 2 },
		{ 37, 3 },
		{ 38, 3 },
		{ 39, 3 },
		{ 40, 3 },
		{ 41, 3 },
		{ 42, 3 },
		{ 43, 3 },
		{ 44, 3 },
		{ 45, 3 },
		{ 46, 3 },
		{ 47, 3 },
		{ 48, 3 },
		{ 49, 3 },
		{ 50, 3 },
		{ 51, 3 },
		{ 52, 3 },
		{ 53, 3 },
		{ 54, 3 },
		{ 55, 3 },
		{ 56, 3 },
		{ 57, 4 },
		{ 58, 4 },
		{ 59, 4 },
		{ 60, 4 },
		{ 61, 4 },
		{ 62, 4 },
		{ 63, 4 },
		{ 64, 4 },
		{ 65, 4 },
		{ 66, 4 },
		{ 67, 4 },
		{ 68, 4 },
		{ 69, 4 },
		{ 70, 4 },
		{ 71, 4 },
		{ 72, 4 },
		{ 73, 4 },
		{ 74, 4 },
		{ 75, 4 },
		{ 76, 4 },
		{ 77, 5 },
		{ 78, 5 },
		{ 79, 5 },
		{ 80, 5 },
		{ 81, 5 },
		{ 82, 5 },
		{ 83, 5 },
		{ 84, 5 },
		{ 85, 5 },
		{ 86, 5 },
		{ 87, 5 },
		{ 88, 5 },
		{ 89, 5 },
		{ 90, 5 },
		{ 91, 5 },
		{ 92, 5 },
		{ 93, 5 },
		{ 94, 5 },
		{ 95, 5 },
		{ 96, 5 },
		{ 97, 6 },
		{ 98, 6 },
		{ 99, 6 },
		{ 100, 6 },
		{ 101, 6 },
		{ 102, 6 },
		{ 103, 6 },
		{ 104, 6 },
		{ 105, 6 },
		{ 106, 6 },
		{ 107, 6 },
		{ 108, 6 },
		{ 109, 6 },
		{ 110, 6 },
		{ 111, 6 },
		{ 112, 6 },
		{ 113, 6 },
		{ 114, 6 },
		{ 115, 7 },
		{ 116, 7 },
		{ 117, 7 },
		{ 118, 7 },
		{ 119, 7 },
		{ 120, 7 },
	},
}
