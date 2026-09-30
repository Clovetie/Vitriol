--!nonstrict
-- ReplicatedStorage/Tidekeeper/Client/Strings (ModuleScript)
--
-- EVERY WORD THE PLAYER READS.
--
-- Layer: Client. Pure -- no services, no Instances, no clock. It is a table of
-- strings and nothing else, which is exactly what makes it translatable and
-- what makes `tools/tidekeeper-session-test.js` able to prove that no template
-- id can reach a player without prose.
--
-- WHY THE WORDS LIVE HERE AND NOT WHERE THEY ARE USED
-- ---------------------------------------------------
-- The server never sends a sentence (doc 08 section 8). A visit becomes
-- `(templateId, epoch, actorId, slots[])` -- 24 bytes of integers -- and the
-- client turns that into prose at the moment of reading. Three consequences,
-- and all three are the reason the game is built this way:
--
--   * 24 bytes instead of ~120, and a post keeps 200 entries;
--   * the copy can be rewritten AFTER the fact and every historical entry in
--     every player's Ledger improves retroactively. A Ledger full of stored
--     prose is a Ledger that can never be edited;
--   * a translation is this one file, not an archaeology dig through views.
--
-- A sentence hard-coded in a view is a sentence that cannot be translated, and
-- the determinism scan's `no-free-text` rule plus the localisation-coverage
-- test in the session suite are what stop that from happening quietly.
--
-- VARIANTS
-- --------
-- A template may carry several phrasings. The replay shows a dozen entries in
-- a row, and twelve identical sentences read like a spreadsheet, not a month
-- of visitors. `Format.render` picks the variant with a hash of
-- (actorId, epoch), so it is DETERMINISTIC: the same entry reads the same way
-- every time the player opens the Ledger, forever. A random variant would
-- make the replay lie about itself, which is the one thing the Ledger may
-- never do.
--
-- SLOT SYNTAX
-- -----------
--   {1} .. {n}   the raw integer in that slot
--   {find:1}     slot 1 is a find id      -> a find name
--   {class:1}    slot 1 is a drifter class-> a class name
--   {tide:1}     slot 1 is a tide code    -> a tide-state name
--   {plural:3|unit|units}  slot 3 chooses the word
--
-- Directives DO NOT NEST. The expander matches `{[^{}]+}`, so a `{1}` inside
-- a plural branch is invisible to the outer match and both halves leak to the
-- player as literal text. The coverage test asserts no rendered line contains
-- a brace, which is how the two variants that did this were caught.
--   {actor}      the visitor's display name, supplied by the caller
--   {coin}       the currency word
--
-- Slot arity is asserted against `Domain/Ledger.SLOT_COUNT`, so a template
-- that grows a slot cannot silently render "{4}" as literal text at a player.

local Strings = {}

Strings.LOCALE = "en"

-- --------------------------------------------------------------- vocabulary

-- Find names, indexed by find id. Iteration 5 expands this to the full 200
-- (doc 07 section 5); these are the ids the current content set actually
-- produces, and `Format` falls back to a generic noun for anything missing so
-- an unnamed find is shabby, never broken.
Strings.FIND = {
	[1] = "green float",
	[2] = "cork buoy",
	[3] = "ribbon of kelp",
	[4] = "gull feather",
	[5] = "cuttlebone",
	[6] = "sand dollar",
	[7] = "blue sea-glass",
	[8] = "oyster shell",
	[9] = "brass buckle",
	[10] = "driftwood knot",
	[11] = "mussel string",
	[12] = "copper nail",
	[13] = "whelk shell",
	[14] = "net weight",
	[15] = "tar button",
	[16] = "bone comb",
	[17] = "chart scrap",
	[18] = "clay bead",
	[19] = "lantern glass",
	[20] = "anchor chain link",
	[21] = "pearl button",
	[22] = "wax seal",
	[23] = "silver hook",
	[24] = "amber lump",
}

Strings.FIND_FALLBACK = "something the sea left"

-- Drifter classes, in DrifterConfig.CLASSES order.
Strings.CLASS = {
	[1] = "skiff",
	[2] = "lugger",
	[3] = "deepwater boat",
	[4] = "ferry",
	[5] = "dredger",
}
Strings.CLASS_FALLBACK = "boat"

-- Tide states, in Visit.TIDE_CODE order.
Strings.TIDE = {
	[1] = "low water",
	[2] = "the ebb",
	[3] = "the flood",
	[4] = "slack water",
	[5] = "high water",
}
Strings.TIDE_FALLBACK = "the turn"

-- Find groups, in FindsConfig.GROUP_NAMES order. Consumes a config key that
-- has been reserved and unread since iteration 1.
Strings.GROUP = {
	[1] = "shell",
	[2] = "glass",
	[3] = "metal",
	[4] = "bone",
	[5] = "cloth",
	[6] = "curio",
}

-- Taste axes, in DrifterConfig.AXIS_NAMES order. Shown in the Chart screen as
-- a visitor's leanings; never as a number.
Strings.AXIS = {
	[1] = "plain / ornate",
	[2] = "dull / bright",
	[3] = "rough / smooth",
	[4] = "old / new",
	[5] = "solitary / sociable",
	[6] = "cheap / dear",
	[7] = "small / large",
	[8] = "cruel / kind",
}

Strings.COIN = "coin"

-- ------------------------------------------------------------ Ledger prose
--
-- Keyed by `Domain/Ledger` template id. Each value is an array of variants.
-- Doc 04 section 4.1 requires >= 40 phrasings by iteration 4; the count is
-- asserted by the session suite rather than trusted to this comment.

Strings.LEDGER = {
	-- 1 T_SERVED_PLAIN  {find:1} {2}=price {3}=count
	[1] = {
		"{actor} took {plural:3|a|} {find:1} for {2} {coin}.",
		"{actor} looked a while, then paid {2} for {plural:3|the|} {find:1}.",
		"Sold: {find:1}, {2} {coin}. {actor} didn't haggle.",
		"{actor} came up the steps, bought {plural:3|a|} {find:1}, and went back down.",
	},
	-- 2 T_SERVED_WANT  {find:1} {2}=price {3}=metWant
	[2] = {
		"{actor} had been looking for {plural:3|a|} {find:1}. Paid {2} without blinking.",
		"That's what {actor} came for -- {find:1}, {2} {coin}, and a look of relief.",
		"{actor} turned the {find:1} over twice before paying {2}. It was the right one.",
		"You had exactly what {actor} wanted. {find:1}, {2} {coin}.",
	},
	-- 3 T_SERVED_WARM  {find:1} {2}=price {3}=count {4}=warmth
	[3] = {
		"{actor} again. Took {plural:3|a|} {find:1} for {2} and stayed to watch the water.",
		"{actor} knows the way up now. {find:1}, {2} {coin}, and no hurry about it.",
		"{actor} paid {2} for {plural:3|the|} {find:1} and left the shutters straightened.",
	},
	-- 4 T_SERVED_SOUR_PRICE  {find:1} {2}=price {3}=percent of base
	[4] = {
		"{actor} paid {2} for {plural:1|a|} {find:1} and made a face about it.",
		"{find:1}, {2} {coin}. {actor} counted it out slowly.",
		"{actor} thought {2} was steep. Paid anyway. Won't forget.",
	},
	-- 5 T_SERVED_FIRST_FIND  {find:1} {2}=price {3}=count
	[5] = {
		"First one you've ever sold: {find:1}, to {actor}, for {2} {coin}.",
		"{actor} bought the first {find:1} to cross this counter. {2} {coin}.",
		"You'd never sold {plural:3|a|} {find:1} before. {actor} has one now.",
	},
	-- 6 T_PARTIAL_BUDGET  {find:1} {2}=price {3}=count {4}=leftBehind
	[6] = {
		"{actor} bought {3} and left {4} on the shelf. Out of {coin}.",
		"{actor} wanted more than {3}, but {2} each adds up. {4} stayed behind.",
		"{3} of the {find:1} went with {actor}. {4} did not.",
	},
	-- 7 T_REFUSED_GATE  {1}=ruleIndex {2}=standing
	[7] = {
		"Your standing orders turned {actor} away. Rule {1}.",
		"{actor} didn't clear rule {1}. Went back down the steps.",
		"Rule {1} said no, so the post said no. {actor} didn't argue.",
	},
	-- 8 T_REFUSED_COLD  {1}=ruleIndex {2}=class
	[8] = {
		"{actor} tied up, read the shelf, and left with nothing.",
		"Nothing here for {actor} today.",
		"{actor} came in on {plural:2|a|} {class:2} and found nothing worth the rope.",
	},
	-- 9 T_MISSED_TIDE  {1}=class {2}=tide
	[9] = {
		"{actor} came at {tide:2}. A {class:1} can't make the channel then.",
		"{tide:2}. {actor}'s {class:1} sat off the bar and turned back.",
		"Too little water for {actor}. Came at {tide:2}, left at {tide:2}.",
	},
	-- 10 T_MISSED_TIDE_DEEPWATER  {1}=tide
	[10] = {
		"A deepwater boat stood off at {tide:1}. It needs more water than this.",
		"Something big waited out past the bar at {tide:1}, then gave up.",
		"{tide:1} is no use to a deepwater hull. It didn't come in.",
	},
	-- 11 T_NO_BERTH  {1}=class
	[11] = {
		"No berth free. The {class:1} circled once and went on.",
		"Every berth full. A {class:1} had to keep going.",
		"{actor} found the pier crowded and didn't wait.",
	},
	-- 12 T_GIFT  {find:1} {2}=warmth {3}=renown
	[12] = {
		"You gave {actor} the {find:1}. They didn't offer to pay and you didn't ask.",
		"{actor} left with a {find:1} and no {coin} changed hands.",
		"A {find:1}, given. {actor} will tell someone about that.",
	},
	-- ------------------------------------------------ 100..105 REMOTE
	-- Your drifter, at somebody else's post. Second person is deliberate and
	-- so is the distance: you did not see this happen, you were told about
	-- it. The host is never named -- you get a place and a feeling, never a
	-- person to go and find (doc 13 section 2).

	-- 100 T_REMOTE_SOLD  {1}=spent {2}=warmth
	[100] = {
		"Your drifter came back light. Spent {1} {coin} somewhere out east.",
		"Word from your traveller: {1} {coin} gone, and a good welcome.",
		"Your boat found a post that had what you wanted. {1} {coin}.",
		"{1} {coin} spent. Your drifter says the shelf there was worth the crossing.",
	},
	-- 101 T_REMOTE_EMPTY  {1}=warmth
	[101] = {
		"Your drifter found nothing worth the rope and came home.",
		"A long way out for an empty hold. Your traveller is back.",
		"Nothing doing out there. Your boat's tied up again.",
	},
	-- 102 T_REMOTE_MISSED  {1}=tide
	[102] = {
		"Your drifter reached the bar at {tide:1} and couldn't get in.",
		"{tide:1} out there too. Your boat turned back.",
		"Your traveller waited out the {tide:1} and gave it up.",
	},
	-- 103 T_REMOTE_NO_BERTH  {1}=warmth
	[103] = {
		"Every berth taken where your drifter went. It came home.",
		"Your boat found a crowded pier and no room.",
		"No berth for your traveller. It didn't wait about.",
	},
	-- 104 T_REMOTE_GIFTED  {1}=warmth
	[104] = {
		"Somebody out there gave your drifter something for nothing.",
		"Your traveller came home with a gift and no receipt.",
		"No {coin} changed hands. Somebody was kind to your boat.",
	},
	-- 105 T_REMOTE_LETTER  {1}=noteId
	[105] = {
		"Your drifter brought a note back.",
		"There's a letter in the hold.",
		"Somebody sent something back with your traveller.",
	},

	-- 200 T_EPOCH_SUMMARY  {1}=arrivals {2}=coin {3}=served {4}=passive
	[200] = {
		"{1} came in on that tide. {3} bought something. {2} {coin}.",
		"That tide: {1} in, {2} {coin}.",
		"{1} up the steps, {3} down with something. {2} {coin} in the tin.",
	},
	-- 201 T_EPOCH_QUIET  {1}=tide
	[201] = {
		"{tide:1}, and nobody came.",
		"Quiet through {tide:1}.",
		"Nothing at {tide:1} but the water.",
		"{tide:1}. The shelf stayed as you left it.",
	},
	-- 250 T_LONG_ABSENCE  {1}=skippedEpochs {2}=cacheCoin {3}=granted
	[250] = {
		"You were gone a long while. {1} tides ran without you. Someone left {2} {coin} under the stone, and {3} things went soft in the damp.",
		"{1} tides. The post kept itself: {2} {coin} in the cache, {3} spoiled.",
		"Long gone. {1} tides, {2} {coin} found, {3} lost to the wet.",
	},
}

-- --------------------------------------------------------------- UI labels

Strings.UI = {
	TAB_WORLD = "Shore",
	TAB_POST = "Post",
	TAB_CHART = "Chart",
	TAB_ALMANAC = "Almanac",

	LEDGER_TITLE = "While you were away",
	LEDGER_EMPTY = "Nothing since you last looked.",
	LEDGER_SKIP = "Skip",
	LEDGER_UNREAD = "{1} new",
	LEDGER_GROUP_EPOCH = "{tide:1}",

	POST_SHELVES = "Shelves {1}/{2}",
	POST_STOCK = "{1} in store",
	POST_COIN = "{1} {coin}",
	POST_RENOWN = "Renown {1}",
	POST_TIER = "Tier {1}",
	POST_EMPTY_SHELF = "empty",
	POST_SET_PRICE = "Price",

	ORDERS_TITLE = "Standing orders",
	ORDERS_EMPTY = "No orders. Everyone is served at the marked price.",
	ORDERS_ADD = "Add a rule",
	ORDERS_RULE = "Rule {1}",
	ORDERS_PREVIEW = "Of your last {1} visitors, this would change {2}.",
	ORDERS_FULL = "That's as many rules as the post can hold.",

	DISPATCH_TITLE = "Send your drifter",
	DISPATCH_SENT = "Gone out on the ebb.",
	DISPATCH_ALREADY = "Your drifter is already out. One to a tide.",
	DISPATCH_CARGO = "Cargo",
	DISPATCH_PHRASE = "Say",

	CHART_TITLE = "The chart",
	CHART_CURRENT = "Current {1}",
	CHART_LOCKED = "Opens at tier {1}",
	CHART_NEXT_LOW = "Low water in {1}",

	ALMANAC_TITLE = "Almanac",
	ALMANAC_HELD = "{1} of {2} found",

	TIDE_NOW = "{tide:1}",
	TIME_HOURS = "{1}h",
	TIME_MINUTES = "{1}m",
	TIME_SOON = "soon",

	-- Status codes from the remote handlers. The server sends the number;
	-- these are the only sentences a player ever sees about a failure.
	ERR_REJECTED = "That didn't go through. Try again in a moment.",
	ERR_NO_POST = "Your post is still coming out of the water. One moment.",
	ERR_BUSY = "Too quick. Give it a second.",
	ERR_OFFLINE = "Can't reach the post right now. Nothing you did is lost.",
}

-- Authored phrases a player may attach to a dispatched Drifter. THE COMPLETE
-- SET -- a player picks an index from this list and the index is what crosses
-- the wire (doc 13 section 2). There is no free text anywhere in this game, so
-- there is nothing to filter and no moderation hot path.
Strings.PHRASE = {
	[1] = "Fair winds.",
	[2] = "Looking for glass, if you have it.",
	[3] = "Keep the change.",
	[4] = "My shelf is thin this tide.",
	[5] = "Thank you for the last one.",
	[6] = "I'll be back at low water.",
	[7] = "Nothing needed. Just passing.",
	[8] = "Your prices are kind.",
	[9] = "Save me something bright.",
	[10] = "The water was rough out there.",
	[11] = "Good hunting.",
	[12] = "I owe you one.",
}

return Strings
