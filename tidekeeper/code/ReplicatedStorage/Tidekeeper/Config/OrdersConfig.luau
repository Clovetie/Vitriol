--!nonstrict
-- ReplicatedStorage/Tidekeeper/Config/OrdersConfig (ModuleScript)
--
-- The standing-order language (doc 06 section 5). A program is an ordered list
-- of `WHEN <condition> THEN <action>` rules, evaluated top to bottom, first
-- match wins.
--
-- Opcodes are part of the save format: a player's program is stored as the
-- bytecode below. NEVER renumber an opcode. To retire one, leave the row in
-- place and set minTier to 99 so the validator rejects new programs while old
-- ones still decode.
--
-- Layer: Config (data only).

return {
	BYTECODE_VERSION = 1,
	MAX_RULES_BY_TIER = { 6, 10, 16, 24 },

	-- Argument kind codes used by the rows below.
	--   0 none | 1 u8 | 2 u16 | 3 u32 | 4 i8
	ARG_NONE = 0,
	ARG_U8 = 1,
	ARG_U16 = 2,
	ARG_U32 = 3,
	ARG_I8 = 4,

	-- Conditions: {name, opcode, minTier, argKindA, argKindB, subTerms}
	-- `subTerms` > 0 means the opcode is composite and is followed by that many
	-- nested conditions in prefix order. Nesting depth is capped at 1 by
	-- Orders.validate -- "max 2 terms" in doc 06 section 5.2.
	CONDITIONS = {
		{ "ALWAYS", 1, 1, 0, 0, 0 },
		{ "CLASS_IS", 2, 1, 1, 0, 0 },
		{ "CURRENT_IS", 3, 1, 1, 0, 0 },
		{ "STANDING_GTE", 4, 2, 2, 0, 0 },
		{ "TIDE_IS", 5, 2, 1, 0, 0 },
		{ "WANTS_SOMETHING", 6, 2, 0, 0, 0 },
		{ "BUDGET_GTE", 7, 3, 3, 0, 0 },
		{ "BEACONS_GTE", 8, 3, 1, 0, 0 },
		{ "TASTE_GT", 9, 3, 1, 4, 0 },
		{ "AND", 10, 3, 0, 0, 2 },
		{ "VISITS_GTE", 11, 4, 2, 0, 0 },
		{ "OR", 12, 4, 0, 0, 2 },
	},

	-- Actions: {name, opcode, minTier, argKind}
	ACTIONS = {
		{ "SERVE", 1, 1, 0 },
		{ "REFUSE", 2, 1, 0 },
		{ "SERVE_ADJ", 3, 2, 4 },
		{ "ACCEPT_BARTER", 4, 2, 0 },
		{ "HOLD_BERTH", 5, 3, 0 },
		{ "OFFER_ONLY", 6, 3, 1 },
		{ "GIFT", 7, 4, 2 },
	},

	-- serve at +N% / -N%, clamped both in the editor and in the validator.
	PRICE_ADJUST_MAX = 40,
	MAX_NEST_DEPTH = 1,
	-- Tide state names accepted by TIDE_IS, in opcode-argument order 1..5.
	TIDE_ARG_NAMES = { "LOW", "EBB", "FLOOD", "SLACK", "HIGH" },
}
