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

-- Find names, indexed by find id. All 200 (doc 07 section 5) as of iteration
-- 7. Iteration 6 added the 176 new rows to FindsConfig but NOT here, so for
-- one iteration every find above id 24 rendered as "something the sea left" --
-- the data shipped and the words did not. `Format` still falls back to a
-- generic noun so an unnamed find is shabby rather than broken, but the
-- coverage test now asserts the fallback never fires for a real find id.
--
-- These are player-facing copy and belong here, not in FindsConfig: that
-- module's `name` column is a stable lookup key that must never change, while
-- these are localised (doc 11) and may be reworded freely.
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
	[25] = "limpet shell",
	[26] = "periwinkle",
	[27] = "blue mussel",
	[28] = "rough oyster",
	[29] = "cluster of barnacles",
	[30] = "slipper shell",
	[31] = "dog whelk",
	[32] = "pink tellin",
	[33] = "banded cockle",
	[34] = "cuttlebone",
	[35] = "scallop fan",
	[36] = "auger shell",
	[37] = "necklace shell",
	[38] = "white piddock",
	[39] = "otter shell",
	[40] = "saddle oyster",
	[41] = "chip of nautilus",
	[42] = "plate of abalone",
	[43] = "spined murex",
	[44] = "small conch",
	[45] = "wentletrap",
	[46] = "tiger cowrie",
	[47] = "whole nautilus",
	[48] = "singing conch",
	[49] = "red spondylus",
	[50] = "paper argonaut",
	[51] = "triton horn",
	[52] = "blister pearl",
	[53] = "junonia",
	[54] = "tusk shell",
	[55] = "green bottle base",
	[56] = "chip of window",
	[57] = "lip of a jar",
	[58] = "cloudy marble",
	[59] = "white glass pebble",
	[60] = "amber sea-glass",
	[61] = "lilac sea-glass",
	[62] = "sealed bottle neck",
	[63] = "scratched lens",
	[64] = "small float",
	[65] = "green insulator",
	[66] = "frosted sea-glass",
	[67] = "netted float",
	[68] = "red sea-glass",
	[69] = "apothecary vial",
	[70] = "lamp chimney",
	[71] = "silvered mirror shard",
	[72] = "string of beads",
	[73] = "glass inkwell",
	[74] = "big cobalt float",
	[75] = "black sea-glass",
	[76] = "lighthouse prism",
	[77] = "ship's decanter",
	[78] = "millefiori bead",
	[79] = "glass eye",
	[80] = "sealed bottle",
	[81] = "ribbed poison bottle",
	[82] = "roman tear vial",
	[83] = "carnival glass plate",
	[84] = "witch ball",
	[85] = "bottle cap",
	[86] = "rusted hook",
	[87] = "lead sinker",
	[88] = "scrap of tin",
	[89] = "coil of wire",
	[90] = "boot eyelet",
	[91] = "copper tack",
	[92] = "brass screw",
	[93] = "zinc anode",
	[94] = "rusted pocket knife",
	[95] = "plain buckle",
	[96] = "worn coin",
	[97] = "steel thimble",
	[98] = "small ship's bell",
	[99] = "copper sheathing",
	[100] = "brass porthole ring",
	[101] = "sextant arm",
	[102] = "pewter spoon",
	[103] = "lead seal",
	[104] = "telegraph key",
	[105] = "brass oil lamp",
	[106] = "whole sextant",
	[107] = "ship's chronometer",
	[108] = "handful of silver",
	[109] = "brass octant",
	[110] = "diving helmet bolt",
	[111] = "little admiralty anchor",
	[112] = "gold signet",
	[113] = "bronze bell tongue",
	[114] = "astrolabe quadrant",
	[115] = "fish vertebra",
	[116] = "crab claw",
	[117] = "urchin shell",
	[118] = "cuttle quill",
	[119] = "gull-feather quill",
	[120] = "dogfish purse",
	[121] = "seal tooth",
	[122] = "small shark tooth",
	[123] = "chip of whale rib",
	[124] = "small bird skull",
	[125] = "sea-washed antler",
	[126] = "fossil shark tooth",
	[127] = "chip of walrus tusk",
	[128] = "whale vertebra",
	[129] = "scrimshaw needle",
	[130] = "ivory bodkin",
	[131] = "chip of narwhal",
	[132] = "scrimshaw tooth",
	[133] = "panel of whale jaw",
	[134] = "narwhal spiral",
	[135] = "lump of ambergris",
	[136] = "ammonite",
	[137] = "mammoth ivory bead",
	[138] = "albatross skull",
	[139] = "scrimshaw busk",
	[140] = "baleen comb",
	[141] = "pair of whale ears",
	[142] = "ivory dice",
	[143] = "sea-lizard fossil",
	[144] = "scrap of net",
	[145] = "rope end",
	[146] = "canvas patch",
	[147] = "lost sock",
	[148] = "square of sacking",
	[149] = "ball of twine",
	[150] = "scrap of flag",
	[151] = "piece of oilskin",
	[152] = "sailor's scarf",
	[153] = "wrapped net float",
	[154] = "worn kit bag",
	[155] = "square of blanket",
	[156] = "signal flag",
	[157] = "faded ensign",
	[158] = "embroidered cuff",
	[159] = "sailmaker's palm",
	[160] = "piece of hammock",
	[161] = "wool guernsey",
	[162] = "stained silk scarf",
	[163] = "admiral's cuff",
	[164] = "embroidered sampler",
	[165] = "eastern silk",
	[166] = "bundle of prayer flags",
	[167] = "battle ensign",
	[168] = "lace collar",
	[169] = "mourning ribbon",
	[170] = "sailor's valentine cloth",
	[171] = "scrap of kimono",
	[172] = "strip of tapestry",
	[173] = "driftwood knob",
	[174] = "lump of pumice",
	[175] = "tar ball",
	[176] = "bundle of feathers",
	[177] = "bunch of dried weed",
	[178] = "empty bottle",
	[179] = "cork float",
	[180] = "clay pipe stem",
	[181] = "bone domino",
	[182] = "tin of buttons",
	[183] = "corner of a chart",
	[184] = "ship's biscuit",
	[185] = "knot board",
	[186] = "scrimshaw counter",
	[187] = "drowning charm",
	[188] = "tide tables",
	[189] = "pocket compass",
	[190] = "page from a log",
	[191] = "sailor's valentine",
	[192] = "figurehead's hand",
	[193] = "sealed message bottle",
	[194] = "gilded mermaid's purse",
	[195] = "salt-stiffened music box",
	[196] = "charts of nowhere",
	[197] = "a captain's whole log",
	[198] = "small reliquary",
	[199] = "star globe",
	[200] = "dead man's fiddle",
}

Strings.FIND_FALLBACK = "something the sea left"


-- --------------------------------------------------------------- letters

-- The 120 authored letter phrases, indexed by letter id (doc 07 section 5,
-- doc 13 section 2). A letter is an INDEX, never free text -- see
-- Config/LettersConfig for why that is a safety decision rather than a
-- technical one, and for the rules any new phrase must satisfy.
--
-- An id is PERSISTED in receipts and drifter blobs. A phrase may be
-- reworded; an id must never be reused for a different sentiment.
Strings.LETTER = {
	[1] = "Thank you. That was the one I was looking for.",
	[2] = "Much obliged. It travelled well.",
	[3] = "This will sit on my best shelf.",
	[4] = "You were fair with me. I will remember it.",
	[5] = "Thanks for keeping the lamp lit.",
	[6] = "I did not expect to find that so far from home.",
	[7] = "You have a good eye. Thank you.",
	[8] = "That was kinder than the price suggested.",
	[9] = "Thank you for not haggling me down.",
	[10] = "My post is better for this. Thank you.",
	[11] = "I had looked for one of these a long while.",
	[12] = "You sent me off with more than I came for.",
	[13] = "Grateful. Genuinely.",
	[14] = "The wrapping was a nice touch.",
	[15] = "Thank you for the trouble you went to.",
	[16] = "This one is staying with me.",
	[17] = "I will tell the others where I found it.",
	[18] = "A fair trade and a good one. Thanks.",
	[19] = "Hello from the far side of the water.",
	[20] = "A stranger's greeting, honestly meant.",
	[21] = "Good tide to you.",
	[22] = "I came by. Your post was shut, so I left this.",
	[23] = "Hello. Your shelves are well kept.",
	[24] = "Just passing. Thought I would say so.",
	[25] = "Greetings from a long way out.",
	[26] = "I have heard of your post. Now I have seen it.",
	[27] = "Hello. Sorry to have missed you.",
	[28] = "A friendly hand from a boat you do not know.",
	[29] = "Fair winds to whoever reads this.",
	[30] = "I stopped here because it looked welcoming.",
	[31] = "Hello. I will come again.",
	[32] = "Someone told me to look for your pier.",
	[33] = "Good morning, whenever morning finds you.",
	[34] = "A note, because you were not in.",
	[35] = "I liked the look of your lamp from the water.",
	[36] = "Hello. Nothing needed. Just hello.",
	[37] = "Your prices are honest.",
	[38] = "That shelf by the door is the best one.",
	[39] = "I would buy more if I had the coin.",
	[40] = "You stock things I have not seen elsewhere.",
	[41] = "The one in the corner is worth more than you ask.",
	[42] = "I have nothing to trade today, but I looked.",
	[43] = "Keep hold of that one. It is rarer than it looks.",
	[44] = "You should ask more for these.",
	[45] = "I came for one thing and wanted four.",
	[46] = "Your shelves are better stocked than mine.",
	[47] = "I left something behind for you.",
	[48] = "Save me one of those for next time.",
	[49] = "Everything here looks cared for.",
	[50] = "I could not afford it. I looked a long time anyway.",
	[51] = "The glass you keep is very fine.",
	[52] = "You have a feel for what is worth keeping.",
	[53] = "I will bring something worth trading next tide.",
	[54] = "That was the best thing I have seen all season.",
	[55] = "No room in my hold. Next time.",
	[56] = "Your post is worth the crossing.",
	[57] = "The water was high and kind today.",
	[58] = "Rough crossing. Worth it.",
	[59] = "Fog the whole way. I found you anyway.",
	[60] = "Calm out there tonight.",
	[61] = "The tide turned early. I had to go.",
	[62] = "It blew hard off the bar. I waited it out.",
	[63] = "Clear sky, flat sea, good day for it.",
	[64] = "The gulls followed me the whole way here.",
	[65] = "Rain the entire crossing and I did not mind.",
	[66] = "Low water nearly stopped me reaching your pier.",
	[67] = "There was ice in the wind this morning.",
	[68] = "The sea was green as glass today.",
	[69] = "I have not seen a tide run like that in years.",
	[70] = "Warm night. I slept on deck.",
	[71] = "A storm is coming. Bring your things in.",
	[72] = "The light on your point can be seen a long way.",
	[73] = "Spring tide tomorrow. Be ready for visitors.",
	[74] = "Quiet water. Quiet day. No complaints.",
	[75] = "The wind was against me both ways somehow.",
	[76] = "Good light this evening. You should have seen it.",
	[77] = "Keep at it. The post is coming along.",
	[78] = "This place will be something.",
	[79] = "You have built more than you think.",
	[80] = "I remember when this was one shelf.",
	[81] = "Do not let it go quiet. It is worth keeping.",
	[82] = "Whatever you are doing, it is working.",
	[83] = "Someone out here is rooting for you.",
	[84] = "The hard part is behind you.",
	[85] = "I have seen worse posts do better. Yours will.",
	[86] = "Stay with it.",
	[87] = "A good post takes seasons, not tides.",
	[88] = "You are further along than you were.",
	[89] = "Mine looked like this once. Keep going.",
	[90] = "You do not need anyone's permission to keep going.",
	[91] = "This is the kind of place people come back to.",
	[92] = "I noticed the work you put in.",
	[93] = "Patience and a clean shelf. That is all it takes.",
	[94] = "You will be glad you kept the lamp lit.",
	[95] = "Do not undersell what you have made here.",
	[96] = "Next season will be better than this one.",
	[97] = "Safe passage.",
	[98] = "Fair winds and an easy tide.",
	[99] = "Until the next high water.",
	[100] = "I will look for your lamp again.",
	[101] = "Goodbye for now. Keep well.",
	[102] = "May your shelves never stay full.",
	[103] = "See you when the tide allows.",
	[104] = "Keep the light burning.",
	[105] = "Off to the next one. Be well.",
	[106] = "Mind the bar on your way out.",
	[107] = "A safe berth to you, wherever you are.",
	[108] = "Go gently.",
	[109] = "Until then.",
	[110] = "Calm seas to you.",
	[111] = "I will be back this way.",
	[112] = "Keep a berth free for me.",
	[113] = "Take care of the place.",
	[114] = "Farewell from a passing boat.",
	[115] = "Sorry to have missed you.",
	[116] = "I could not wait for the tide. Next time.",
	[117] = "I had to turn back. Nothing to do with you.",
	[118] = "Sorry, no coin this trip.",
	[119] = "I wanted to stay longer than I could.",
	[120] = "I will make it up to you next crossing.",
}

Strings.LETTER_FALLBACK = "a note you cannot quite make out"

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
		"Quiet sale. {plural:3|A|} {find:1}, {2} {coin}, and {actor} was gone before the kettle went.",
		"{actor} knew what they wanted and it was {plural:3|a|} {find:1}. {2} {coin}.",
		"{plural:3|A|} {find:1} off the shelf. {actor} paid {2} and said nothing much.",
		"{actor} paid {2} for {plural:3|the|} {find:1} and asked after the weather.",
		"One {find:1} fewer. {actor} left {2} {coin} on the board.",
		"{actor} handled half the shelf and bought {plural:3|a|} {find:1} anyway. {2} {coin}.",
		"Trade: {find:1} for {2}. {actor} shook on it.",
	},
	-- 2 T_SERVED_WANT  {find:1} {2}=price {3}=metWant
	[2] = {
		"{actor} had been looking for {plural:3|a|} {find:1}. Paid {2} without blinking.",
		"That's what {actor} came for -- {find:1}, {2} {coin}, and a look of relief.",
		"{actor} turned the {find:1} over twice before paying {2}. It was the right one.",
		"You had exactly what {actor} wanted. {find:1}, {2} {coin}.",
		"{actor} asked for {find:1} by name. You had it. {2} {coin}.",
		"The {find:1} went to {actor}, who had clearly come a long way for it. {2}.",
		"{actor} stopped mid-sentence when they saw the {find:1}. Paid {2}.",
		"Months of looking, {actor} said. {find:1}, {2} {coin}, and a handshake.",
		"{actor} paid {2} for the {find:1} and wrapped it before leaving the step.",
		"Right thing, right shelf, right tide. {actor} took the {find:1} for {2}.",
		"{actor} did not ask the price of the {find:1} until after deciding. {2} {coin}.",
	},
	-- 3 T_SERVED_WARM  {find:1} {2}=price {3}=count {4}=warmth
	[3] = {
		"{actor} again. Took {plural:3|a|} {find:1} for {2} and stayed to watch the water.",
		"{actor} knows the way up now. {find:1}, {2} {coin}, and no hurry about it.",
		"{actor} paid {2} for {plural:3|the|} {find:1} and left the shutters straightened.",
		"{actor} let themselves in, took {plural:3|a|} {find:1}, left {2} {coin} and a story.",
		"Regular now. {actor}, {find:1}, {2}. You barely had to look up.",
		"{actor} brought the mug back from last time, then bought {plural:3|a|} {find:1} for {2}.",
		"{plural:3|A|} {find:1} for {actor}, {2} {coin}, and a long sit on the rail after.",
		"{actor} asked about the roof before asking about the {find:1}. Paid {2}.",
		"{actor} paid {2}, took {plural:3|the|} {find:1}, and swept the step on the way out.",
	},
	-- 4 T_SERVED_SOUR_PRICE  {find:1} {2}=price {3}=percent of base
	[4] = {
		"{actor} paid {2} for {plural:1|a|} {find:1} and made a face about it.",
		"{find:1}, {2} {coin}. {actor} counted it out slowly.",
		"{actor} thought {2} was steep. Paid anyway. Won't forget.",
		"{find:1} at {2} {coin} -- {3} per cent of what it is worth. {actor} noticed.",
		"{actor} paid {2}. They will remember what the {find:1} cost here.",
		"{3} per cent of fair, and {actor} knew it. Took the {find:1} anyway.",
		"{actor} held the {find:1} a long moment at {2} {coin}, then paid without a word.",
		"Sold at {3} per cent of base. {actor} did not thank you for the {find:1}.",
	},
	-- 5 T_SERVED_FIRST_FIND  {find:1} {2}=price {3}=count
	[5] = {
		"First one you've ever sold: {find:1}, to {actor}, for {2} {coin}.",
		"{actor} bought the first {find:1} to cross this counter. {2} {coin}.",
		"You'd never sold {plural:3|a|} {find:1} before. {actor} has one now.",
		"First {find:1} ever to leave this post. {actor} paid {2}.",
		"Nobody had bought {plural:3|a|} {find:1} here before. {actor} did. {2} {coin}.",
		"That one sat a long time. {actor} finally took {plural:3|it|them} for {2}.",
		"{actor} opened the account on {plural:3|the|} {find:1}. {2} {coin}.",
		"A first: {find:1}, {2} {coin}, to {actor}.",
	},
	-- 6 T_PARTIAL_BUDGET  {find:1} {2}=price {3}=count {4}=leftBehind
	[6] = {
		"{actor} bought {3} and left {4} on the shelf. Out of {coin}.",
		"{actor} wanted more than {3}, but {2} each adds up. {4} stayed behind.",
		"{3} of the {find:1} went with {actor}. {4} did not.",
		"{actor} bought {plural:3|a|} {find:1} for {2} and left {4} on the shelf for want of coin.",
		"Short by a little. {actor} took {plural:3|a|} {find:1} at {2}, put {4} back.",
		"{actor} counted twice, took {plural:3|the|} {find:1} for {2}, and left {4} behind.",
		"{4} {plural:4|thing|things} went back on the shelf. {actor} could only cover the {find:1} at {2}.",
		"{actor} paid {2} for {plural:3|a|} {find:1} and looked at the other {4} on the way out.",
	},
	-- 7 T_REFUSED_GATE  {1}=ruleIndex {2}=standing
	[7] = {
		"Your standing orders turned {actor} away. Rule {1}.",
		"{actor} didn't clear rule {1}. Went back down the steps.",
		"Rule {1} said no, so the post said no. {actor} didn't argue.",
		"Rule {1}: standing of {2} is not enough. {actor} was turned away.",
		"{actor} stood at {2} and your rule {1} wants more. No trade.",
		"The post is picky now. Rule {1} shut the door on {actor}.",
		"{actor} came up, read the board, and went back down. Rule {1}.",
		"Standing {2}. Rule {1} says no. {actor} did not take it personally.",
	},
	-- 8 T_REFUSED_COLD  {1}=ruleIndex {2}=class
	[8] = {
		"{actor} tied up, read the shelf, and left with nothing.",
		"Nothing here for {actor} today.",
		"{actor} came in on {plural:2|a|} {class:2} and found nothing worth the rope.",
		"Rule {1} turns away {class:2} boats. This one went on down the coast.",
		"A {class:2} tried the pier. Rule {1} said no.",
		"You do not trade with {class:2} crews. Rule {1}, and {actor} knew it already.",
		"Rule {1} held. The {class:2} did not tie up.",
		"{actor} brought a {class:2} alongside and your own rule sent them off.",
	},
	-- 9 T_MISSED_TIDE  {1}=class {2}=tide
	[9] = {
		"{actor} came at {tide:2}. A {class:1} can't make the channel then.",
		"{tide:2}. {actor}'s {class:1} sat off the bar and turned back.",
		"Too little water for {actor}. Came at {tide:2}, left at {tide:2}.",
		"A {class:1} drawing too much for {tide:2}. {actor} waited, then went.",
		"{actor} misread the tide. {tide:2} and a {class:1} do not mix.",
		"The bar was dry enough at {tide:2} to stop a {class:1}. {actor} turned.",
		"{tide:2}. {actor} could see the post and could not reach it.",
		"A {class:1} needs more water than {tide:2} gives. {actor} came back out.",
	},
	-- 10 T_MISSED_TIDE_DEEPWATER  {1}=tide
	[10] = {
		"A deepwater boat stood off at {tide:1}. It needs more water than this.",
		"Something big waited out past the bar at {tide:1}, then gave up.",
		"{tide:1} is no use to a deepwater hull. It didn't come in.",
		"Deep hull, {tide:1}, no chance. It stood off and left.",
		"Whatever it was, it was too deep for {tide:1}.",
		"A big one sat on the horizon through {tide:1} and never closed.",
		"The deepwater boat waited through {tide:1}. The water never came.",
		"{tide:1}. Too shallow for the thing that was waiting out there.",
	},
	-- 11 T_NO_BERTH  {1}=class
	[11] = {
		"No berth free. The {class:1} circled once and went on.",
		"Every berth full. A {class:1} had to keep going.",
		"{actor} found the pier crowded and didn't wait.",
		"The {class:1} looked for a gap, found none, and carried on.",
		"Berths all taken. A {class:1} went past without slowing much.",
		"A {class:1} hung off the pier a while. Nowhere to put it.",
		"You could have used another berth. The {class:1} did not wait.",
		"Full up. The {class:1} went to find someone with room.",
	},
	-- 12 T_GIFT  {find:1} {2}=warmth {3}=renown
	[12] = {
		"You gave {actor} the {find:1}. They didn't offer to pay and you didn't ask.",
		"{actor} left with a {find:1} and no {coin} changed hands.",
		"A {find:1}, given. {actor} will tell someone about that.",
		"{actor} tried to pay for the {find:1}. You would not take it.",
		"The {find:1} went with {actor} for nothing. Word travels.",
		"You put the {find:1} in {actor}'s hands and closed them over it.",
		"No charge for the {find:1}. {actor} looked at you oddly and then thanked you.",
		"Given, not sold: {find:1}. {actor} will say so somewhere down the coast.",
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
		"Your drifter came home with {1} {coin} and sand in the bilge.",
		"Someone bought from your boat. {1} {coin} back.",
		"Trade made somewhere out there. {1} {coin} in the hold.",
		"Your traveller found a buyer. {1} {coin}.",
		"The boat is back and lighter by a few things. {1} {coin}.",
		"Sold well, wherever it was. {1} {coin} home.",
		"Your drifter did the rounds and returned with {1} {coin}.",
	},
	-- 101 T_REMOTE_EMPTY  {1}=warmth
	[101] = {
		"Your drifter found nothing worth the rope and came home.",
		"A long way out for an empty hold. Your traveller is back.",
		"Nothing doing out there. Your boat's tied up again.",
		"Your drifter came back with everything it left with.",
		"No takers out there. The hold is as you packed it.",
		"The boat went, looked, and came home full.",
		"Nothing sold. Not every tide is a market.",
		"Your traveller found the shelves elsewhere already full.",
	},
	-- 102 T_REMOTE_MISSED  {1}=tide
	[102] = {
		"Your drifter reached the bar at {tide:1} and couldn't get in.",
		"{tide:1} out there too. Your boat turned back.",
		"Your traveller waited out the {tide:1} and gave it up.",
		"Your boat sat off a strange bar through {tide:1} and never got in.",
		"{tide:1} somewhere else, too. Your drifter came home with nothing moved.",
		"Wrong water at the far end. {tide:1}, and the channel was shut.",
		"Your traveller could see the post and not reach it. {tide:1}.",
		"Out past the bar at {tide:1}, then home again.",
	},
	-- 103 T_REMOTE_NO_BERTH  {1}=warmth
	[103] = {
		"Every berth taken where your drifter went. It came home.",
		"Your boat found a crowded pier and no room.",
		"No berth for your traveller. It didn't wait about.",
		"Your drifter found the berths full and came back.",
		"Nowhere to tie up out there. The boat returned loaded.",
		"Busy pier, no room. Your traveller did not land.",
		"Your boat circled a crowded post and gave it up.",
		"Someone else was already alongside. Your drifter came home.",
	},
	-- 104 T_REMOTE_GIFTED  {1}=warmth
	[104] = {
		"Somebody out there gave your drifter something for nothing.",
		"Your traveller came home with a gift and no receipt.",
		"No {coin} changed hands. Somebody was kind to your boat.",
		"Someone out there gave your drifter something for nothing.",
		"Your boat came back with a gift in the hold and no bill.",
		"A stranger would not take payment. Your traveller brought it home anyway.",
		"Nothing spent, something gained. Somebody was kind.",
		"Your drifter was given a thing freely and told to pass it on.",
	},
	-- 105 T_REMOTE_LETTER  {1}=noteId
	[105] = {
		"Your drifter brought a note back.",
		"There's a letter in the hold.",
		"Somebody sent something back with your traveller.",
		"A folded note came back in the hold.",
		"Your traveller was handed a letter and asked to carry it.",
		"Someone wrote something down and sent it with your boat.",
		"There is a note on the table. It came in with the tide.",
		"Your drifter carried a message home.",
	},

	-- 200 T_EPOCH_SUMMARY  {1}=arrivals {2}=coin {3}=served {4}=passive
	[200] = {
		"{1} came in on that tide. {3} bought something. {2} {coin}.",
		"That tide: {1} in, {2} {coin}.",
		"{1} up the steps, {3} down with something. {2} {coin} in the tin.",
		"{1} in on the tide, {3} served, {2} {coin} taken.",
		"{1} arrivals, {3} sales, {2} {coin}. {4} of them you never met.",
		"A working tide: {1} up the steps, {2} {coin} in the tin.",
		"{2} {coin} that tide, from {3} of {1} who came.",
		"Tide closed. {1} in, {3} served, {2} {coin}.",
		"{1} came, {3} bought, {2} {coin}. {4} handled themselves.",
	},
	-- 201 T_EPOCH_QUIET  {1}=tide
	[201] = {
		"{tide:1}, and nobody came.",
		"Quiet through {tide:1}.",
		"Nothing at {tide:1} but the water.",
		"{tide:1}. The shelf stayed as you left it.",
		"{tide:1}. The gulls had the pier to themselves.",
		"No one at {tide:1}. The shelf is exactly as you left it.",
		"{tide:1} came and went. Nothing with it.",
		"An empty {tide:1}. Not every one pays.",
		"{tide:1}, and only the water moving.",
	},
	-- 250 T_LONG_ABSENCE  {1}=skippedEpochs {2}=cacheCoin {3}=granted
	[250] = {
		"You were gone a long while. {1} tides ran without you. Someone left {2} {coin} under the stone, and {3} things went soft in the damp.",
		"{1} tides. The post kept itself: {2} {coin} in the cache, {3} spoiled.",
		"Long gone. {1} tides, {2} {coin} found, {3} lost to the wet.",
		"{1} tides without you. {2} {coin} waited under the stone. {3} did not keep.",
		"The post stood {1} tides alone. {2} {coin} in the cache, {3} gone soft.",
		"You have been away {1} tides. Someone kept paying: {2} {coin}. {3} spoiled.",
		"After {1} tides the damp had {3} of it. The cache held {2} {coin}.",
		"{1} tides of absence. {2} {coin} found, {3} lost.",
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
	ERR_ILLEGAL = "That can't be done just now.",
	ERR_COOLDOWN = "You've already been over that ground. Give it a few tides.",

	-- Buying a tier. The cost comes from the server in the snapshot, never
	-- from a local copy of the table.
	UPGRADE_OFFER = "Make it a tier {1} post — {2} coin",
	UPGRADE_MAXED = "The post is as big as it gets.",
	UPGRADE_SHORT = "You need {1} more.",
	UPGRADE_DONE = "The builders come in on the next low water.",

	-- Choosing a letter to send out with a drifter.
	LETTER_TITLE = "Send a note",
	LETTER_NONE = "No note",
	LETTER_CATEGORY = "{1}",
	LETTER_CHOSEN = "You wrote: {1}",
}


return Strings
