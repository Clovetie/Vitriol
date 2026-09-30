--!nonstrict
-- ReplicatedStorage/Tidekeeper/Domain/Orders (ModuleScript)
--
-- Layer L2: pure. No services, no Instances, no yields, no time reads.
--
-- The standing-order interpreter (doc 06 section 5). A program is an ORDERED
-- LIST of `WHEN <condition> THEN <action>` rules, evaluated top to bottom,
-- first match wins. This is the game's depth, and it is the thing that keeps
-- running while the player is asleep.
--
-- Three properties this module must have, in priority order:
--   1. TOTAL. A malformed program must never error during a resolve; a resolve
--      that throws is a player's week of history lost. Every entry point is
--      defensive and `evaluate` falls back to the default action.
--   2. DETERMINISTIC. No table iteration, no randomness, no clock.
--   3. ROUND-TRIPPING. encode(decode(b)) == b for every valid program, because
--      the bytecode is what is written to the DataStore.
--
-- The evaluator takes a FACTS table rather than the post and the drifter, so
-- the same program can be run against a hypothetical visitor by the client's
-- live preview panel (doc 06 section 5.5) without constructing a fake post.

local OrdersConfig = require(script.Parent.Parent.Config.OrdersConfig)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local DrifterConfig = require(script.Parent.Parent.Config.DrifterConfig)
local Codec = require(script.Parent.Parent.Lib.Codec)

local Orders = {}

local CONDITIONS = OrdersConfig.CONDITIONS
local ACTIONS = OrdersConfig.ACTIONS

local C_NAME = 1
local C_OP = 2
local C_MIN_TIER = 3
local C_ARG_A = 4
local C_ARG_B = 5
local C_SUB = 6

local A_NAME = 1
local A_OP = 2
local A_MIN_TIER = 3
local A_ARG = 4

local COND_BY_OP = {}
local COND_BY_NAME = {}
for i = 1, #CONDITIONS do
	local row = CONDITIONS[i]
	COND_BY_OP[row[C_OP]] = row
	COND_BY_NAME[row[C_NAME]] = row
end

local ACTION_BY_OP = {}
local ACTION_BY_NAME = {}
for i = 1, #ACTIONS do
	local row = ACTIONS[i]
	ACTION_BY_OP[row[A_OP]] = row
	ACTION_BY_NAME[row[A_NAME]] = row
end

-- Named opcodes for the rest of the domain layer. Reading `Orders.SERVE` in
-- Visit is worth more than saving this block.
Orders.ALWAYS = COND_BY_NAME.ALWAYS[C_OP]
Orders.CLASS_IS = COND_BY_NAME.CLASS_IS[C_OP]
Orders.CURRENT_IS = COND_BY_NAME.CURRENT_IS[C_OP]
Orders.STANDING_GTE = COND_BY_NAME.STANDING_GTE[C_OP]
Orders.TIDE_IS = COND_BY_NAME.TIDE_IS[C_OP]
Orders.WANTS_SOMETHING = COND_BY_NAME.WANTS_SOMETHING[C_OP]
Orders.BUDGET_GTE = COND_BY_NAME.BUDGET_GTE[C_OP]
Orders.BEACONS_GTE = COND_BY_NAME.BEACONS_GTE[C_OP]
Orders.TASTE_GT = COND_BY_NAME.TASTE_GT[C_OP]
Orders.AND = COND_BY_NAME.AND[C_OP]
Orders.VISITS_GTE = COND_BY_NAME.VISITS_GTE[C_OP]
Orders.OR = COND_BY_NAME.OR[C_OP]

Orders.SERVE = ACTION_BY_NAME.SERVE[A_OP]
Orders.REFUSE = ACTION_BY_NAME.REFUSE[A_OP]
Orders.SERVE_ADJ = ACTION_BY_NAME.SERVE_ADJ[A_OP]
Orders.ACCEPT_BARTER = ACTION_BY_NAME.ACCEPT_BARTER[A_OP]
Orders.HOLD_BERTH = ACTION_BY_NAME.HOLD_BERTH[A_OP]
Orders.OFFER_ONLY = ACTION_BY_NAME.OFFER_ONLY[A_OP]
Orders.GIFT = ACTION_BY_NAME.GIFT[A_OP]

-- A post with no program serves everyone at list price. That default matters:
-- it is what a brand-new player's post does, and it has to be reasonable.
local DEFAULT_ACTION = { op = Orders.SERVE, a = 0 }
Orders.DEFAULT_ACTION = DEFAULT_ACTION

function Orders.conditionName(op)
	local row = COND_BY_OP[op]
	if row == nil then
		return "UNKNOWN"
	end
	return row[C_NAME]
end

function Orders.actionName(op)
	local row = ACTION_BY_OP[op]
	if row == nil then
		return "UNKNOWN"
	end
	return row[A_NAME]
end

function Orders.empty()
	return { version = OrdersConfig.BYTECODE_VERSION, rules = {} }
end

-- Convenience builders so tests and the iteration-4 editor construct the same
-- shape. `cond` and `act` are the only supported way to make a node.
function Orders.cond(op, a, b)
	return { op = op, a = a, b = b }
end

function Orders.compound(op, left, right)
	return { op = op, terms = { left, right } }
end

function Orders.act(op, a)
	return { op = op, a = a }
end

function Orders.rule(cond, action)
	return { cond = cond, action = action }
end

-- ---------------------------------------------------------------- evaluate

local function evalCond(node, facts, depth)
	if type(node) ~= "table" then
		return false
	end
	local op = node.op
	if op == Orders.ALWAYS then
		return true
	elseif op == Orders.CLASS_IS then
		return facts.class == node.a
	elseif op == Orders.CURRENT_IS then
		return facts.current == node.a
	elseif op == Orders.STANDING_GTE then
		return facts.standing >= node.a
	elseif op == Orders.TIDE_IS then
		return facts.tide == OrdersConfig.TIDE_ARG_NAMES[node.a]
	elseif op == Orders.WANTS_SOMETHING then
		return facts.wantsSomething == true
	elseif op == Orders.BUDGET_GTE then
		return facts.budget >= node.a
	elseif op == Orders.BEACONS_GTE then
		return facts.beacons >= node.a
	elseif op == Orders.TASTE_GT then
		local axis = node.a
		if axis < 1 or axis > DrifterConfig.TASTE_AXES then
			return false
		end
		return facts.taste[axis] > node.b
	elseif op == Orders.VISITS_GTE then
		return facts.visits >= node.a
	elseif op == Orders.AND then
		if depth >= OrdersConfig.MAX_NEST_DEPTH + 1 then
			return false
		end
		local terms = node.terms
		if terms == nil then
			return false
		end
		return evalCond(terms[1], facts, depth + 1) and evalCond(terms[2], facts, depth + 1)
	elseif op == Orders.OR then
		if depth >= OrdersConfig.MAX_NEST_DEPTH + 1 then
			return false
		end
		local terms = node.terms
		if terms == nil then
			return false
		end
		return evalCond(terms[1], facts, depth + 1) or evalCond(terms[2], facts, depth + 1)
	end
	return false
end

Orders.evalCondition = function(node, facts)
	return evalCond(node, facts, 0)
end

-- Returns (action, ruleIndex). `ruleIndex` is 0 when nothing matched and the
-- default applied -- the Ledger uses it to say "your rule 3 did this".
function Orders.evaluate(program, facts)
	if type(program) ~= "table" then
		return DEFAULT_ACTION, 0
	end
	local rules = program.rules
	if type(rules) ~= "table" then
		return DEFAULT_ACTION, 0
	end
	for i = 1, #rules do
		local rule = rules[i]
		if type(rule) == "table" and evalCond(rule.cond, facts, 0) then
			local action = rule.action
			if type(action) == "table" and ACTION_BY_OP[action.op] ~= nil then
				return action, i
			end
			return DEFAULT_ACTION, i
		end
	end
	return DEFAULT_ACTION, 0
end

-- ---------------------------------------------------------------- validate

local function argInRange(kind, value)
	if kind == OrdersConfig.ARG_NONE then
		return value == nil or value == 0
	end
	if type(value) ~= "number" or value ~= math.floor(value) then
		return false
	end
	if kind == OrdersConfig.ARG_U8 then
		return value >= 0 and value <= 255
	elseif kind == OrdersConfig.ARG_U16 then
		return value >= 0 and value <= 65535
	elseif kind == OrdersConfig.ARG_U32 then
		return value >= 0 and value <= 4294967295
	elseif kind == OrdersConfig.ARG_I8 then
		return value >= -128 and value <= 127
	end
	return false
end

local function validateCond(node, tier, depth)
	if type(node) ~= "table" then
		return false, "condition is not a table"
	end
	local row = COND_BY_OP[node.op]
	if row == nil then
		return false, "unknown condition opcode " .. tostring(node.op)
	end
	if tier < row[C_MIN_TIER] then
		return false, string.format("condition %s requires tier %d", row[C_NAME], row[C_MIN_TIER])
	end
	local subTerms = row[C_SUB]
	if subTerms > 0 then
		if depth >= OrdersConfig.MAX_NEST_DEPTH then
			return false, string.format("condition %s is nested too deeply", row[C_NAME])
		end
		local terms = node.terms
		if type(terms) ~= "table" or #terms ~= subTerms then
			return false, string.format("condition %s needs exactly %d terms", row[C_NAME], subTerms)
		end
		for i = 1, subTerms do
			local ok, message = validateCond(terms[i], tier, depth + 1)
			if not ok then
				return false, message
			end
		end
		return true
	end
	if not argInRange(row[C_ARG_A], node.a) then
		return false, string.format("condition %s: first argument is out of range", row[C_NAME])
	end
	if not argInRange(row[C_ARG_B], node.b) then
		return false, string.format("condition %s: second argument is out of range", row[C_NAME])
	end
	if node.op == Orders.TASTE_GT and (node.a < 1 or node.a > DrifterConfig.TASTE_AXES) then
		return false, "TASTE_GT: axis is out of range"
	end
	return true
end

local function validateAction(node, tier)
	if type(node) ~= "table" then
		return false, "action is not a table"
	end
	local row = ACTION_BY_OP[node.op]
	if row == nil then
		return false, "unknown action opcode " .. tostring(node.op)
	end
	if tier < row[A_MIN_TIER] then
		return false, string.format("action %s requires tier %d", row[A_NAME], row[A_MIN_TIER])
	end
	if not argInRange(row[A_ARG], node.a) then
		return false, string.format("action %s: argument is out of range", row[A_NAME])
	end
	if node.op == Orders.SERVE_ADJ then
		local limit = OrdersConfig.PRICE_ADJUST_MAX
		if node.a < -limit or node.a > limit then
			return false, string.format("SERVE_ADJ: adjustment must be within +/-%d%%", limit)
		end
	end
	return true
end

-- Returns (true) or (false, message). `tier` gates both the rule count and
-- which opcodes are legal (doc 06 sections 5.2 and 5.3).
function Orders.validate(program, tier)
	if type(program) ~= "table" then
		return false, "program is not a table"
	end
	if program.version ~= OrdersConfig.BYTECODE_VERSION then
		return false, "unknown program version " .. tostring(program.version)
	end
	local rules = program.rules
	if type(rules) ~= "table" then
		return false, "program has no rules array"
	end
	local limit = OrdersConfig.MAX_RULES_BY_TIER[tier]
	if limit == nil then
		return false, "unknown tier " .. tostring(tier)
	end
	if #rules > limit then
		return false, string.format("%d rules at tier %d, limit %d", #rules, tier, limit)
	end
	for i = 1, #rules do
		local rule = rules[i]
		if type(rule) ~= "table" then
			return false, string.format("rule %d is not a table", i)
		end
		local ok, message = validateCond(rule.cond, tier, 0)
		if not ok then
			return false, string.format("rule %d: %s", i, message)
		end
		ok, message = validateAction(rule.action, tier)
		if not ok then
			return false, string.format("rule %d: %s", i, message)
		end
	end
	return true
end

-- ----------------------------------------------------------------- bytecode

local function writeArg(w, kind, value)
	local v = value or 0
	if kind == OrdersConfig.ARG_U8 then
		w:u8(v)
	elseif kind == OrdersConfig.ARG_U16 then
		w:u16(v)
	elseif kind == OrdersConfig.ARG_U32 then
		w:u32(v)
	elseif kind == OrdersConfig.ARG_I8 then
		w:i8(v)
	end
end

local function readArg(r, kind)
	if kind == OrdersConfig.ARG_U8 then
		return r:u8()
	elseif kind == OrdersConfig.ARG_U16 then
		return r:u16()
	elseif kind == OrdersConfig.ARG_U32 then
		return r:u32()
	elseif kind == OrdersConfig.ARG_I8 then
		return r:i8()
	end
	return nil
end

local function encodeCond(w, node)
	local row = COND_BY_OP[node.op]
	w:u8(node.op)
	if row[C_SUB] > 0 then
		for i = 1, row[C_SUB] do
			encodeCond(w, node.terms[i])
		end
		return
	end
	writeArg(w, row[C_ARG_A], node.a)
	writeArg(w, row[C_ARG_B], node.b)
end

local function decodeCond(r)
	local op = r:u8()
	local row = COND_BY_OP[op]
	if row == nil then
		error("Orders: unknown condition opcode " .. tostring(op), 0)
	end
	if row[C_SUB] > 0 then
		local terms = {}
		for i = 1, row[C_SUB] do
			terms[i] = decodeCond(r)
		end
		return { op = op, terms = terms }
	end
	local a = readArg(r, row[C_ARG_A])
	local b = readArg(r, row[C_ARG_B])
	return { op = op, a = a, b = b }
end

-- Program -> byte array. The caller is responsible for having validated; this
-- errors on a malformed program rather than writing a blob that cannot be read
-- back.
function Orders.encode(program)
	local w = Codec.writer()
	w:u8(program.version)
	local rules = program.rules
	w:u8(#rules)
	for i = 1, #rules do
		local rule = rules[i]
		encodeCond(w, rule.cond)
		local actionRow = ACTION_BY_OP[rule.action.op]
		if actionRow == nil then
			error("Orders.encode: unknown action opcode " .. tostring(rule.action.op), 0)
		end
		w:u8(rule.action.op)
		writeArg(w, actionRow[A_ARG], rule.action.a)
	end
	if w.n > GameConfig.MAX_ORDERS_BYTES then
		error(string.format("Orders.encode: %d bytes exceeds the %d byte budget", w.n, GameConfig.MAX_ORDERS_BYTES), 0)
	end
	return w:build()
end

-- Byte array -> (program, nil) or (nil, message). Total: a corrupt program in
-- a DataStore must degrade to "no orders", never to a crashed resolve.
function Orders.decode(bytes, offset, length)
	local ok, result = pcall(function()
		local r = Codec.reader(bytes, offset or 1)
		local version = r:u8()
		if version ~= OrdersConfig.BYTECODE_VERSION then
			error("unsupported bytecode version " .. tostring(version), 0)
		end
		local count = r:u8()
		local rules = {}
		for i = 1, count do
			local cond = decodeCond(r)
			local op = r:u8()
			local actionRow = ACTION_BY_OP[op]
			if actionRow == nil then
				error("unknown action opcode " .. tostring(op), 0)
			end
			rules[i] = { cond = cond, action = { op = op, a = readArg(r, actionRow[A_ARG]) } }
		end
		if length ~= nil and r:pos() - (offset or 1) ~= length then
			error(string.format("trailing bytes: consumed %d of %d", r:pos() - (offset or 1), length), 0)
		end
		return { version = version, rules = rules }
	end)
	if not ok then
		return nil, "Orders.decode: " .. tostring(result)
	end
	return result, nil
end

function Orders.byteLength(program)
	return #Orders.encode(program)
end

return Orders
