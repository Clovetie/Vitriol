--!nonstrict
-- ReplicatedStorage/Tidekeeper/Client/OrdersView (ModuleScript)
--
-- The standing-order editor. Layer: Client. Pure.
--
-- Standing orders are the deepest system in the game (doc 06 section 6) and
-- the one most likely to be edited by an eleven-year-old on a phone. Two
-- design consequences, both enforced here:
--
--   1. A RULE IS BUILT FROM PICKERS, NEVER TYPED. Every condition operand and
--      every action operand is an index into a list this module publishes.
--      There is no expression parser, no text field, and therefore no way to
--      express something the validator has to reject after the fact.
--   2. THE PREVIEW RUNS THE REAL INTERPRETER. `Orders.evaluate` is a pure
--      function, so the client can run it against the player's own recent
--      visitors and say "this would have changed 3 of your last 20". A
--      preview computed by a second, simpler implementation would eventually
--      disagree with the server, and the player would be right to distrust
--      the whole feature.

local Orders = require(script.Parent.Parent.Domain.Orders)
local OrdersConfig = require(script.Parent.Parent.Config.OrdersConfig)
local Drifter = require(script.Parent.Parent.Domain.Drifter)
local Format = require(script.Parent.Format)
local Strings = require(script.Parent.Strings)

local OrdersView = {}

-- The pickers. Order is the UI order; the `op` is the wire value.
OrdersView.CONDITIONS = {
	{ op = Orders.ALWAYS, label = "Always", operands = 0 },
	{ op = Orders.CLASS_IS, label = "Arrives by", operands = 1, domain = "class" },
	{ op = Orders.WANTS_SOMETHING, label = "Wants something I have", operands = 0 },
	{ op = Orders.STANDING_GTE, label = "Standing is at least", operands = 1, domain = "number" },
	{ op = Orders.TIDE_IS, label = "Tide is", operands = 1, domain = "tide" },
	{ op = Orders.CURRENT_IS, label = "Comes from current", operands = 1, domain = "current" },
	{ op = Orders.BUDGET_GTE, label = "Carries at least", operands = 1, domain = "number" },
	{ op = Orders.BEACONS_GTE, label = "Has visited at least", operands = 1, domain = "number" },
	{ op = Orders.VISITS_GTE, label = "Has been here at least", operands = 1, domain = "number" },
	{ op = Orders.TASTE_GT, label = "Leans toward", operands = 2, domain = "axis" },
}

OrdersView.ACTIONS = {
	{ op = Orders.SERVE, label = "Serve at the marked price", operands = 0 },
	{ op = Orders.SERVE_ADJ, label = "Serve, adjust price by", operands = 1, domain = "percent" },
	{ op = Orders.REFUSE, label = "Turn away", operands = 0 },
	{ op = Orders.GIFT, label = "Give it freely", operands = 0 },
	{ op = Orders.ACCEPT_BARTER, label = "Accept a trade", operands = 0 },
	{ op = Orders.HOLD_BERTH, label = "Hold a berth", operands = 0 },
	{ op = Orders.OFFER_ONLY, label = "Offer only", operands = 1, domain = "group" },
}

-- The operand domains, so a picker never offers an out-of-range value.
function OrdersView.domainValues(domain)
	if domain == "class" then
		return Strings.CLASS
	elseif domain == "tide" then
		return Strings.TIDE
	elseif domain == "group" then
		return Strings.GROUP
	elseif domain == "axis" then
		return Strings.AXIS
	end
	return nil
end

-- Render the rule list.
function OrdersView.build(program, tier)
	local rows = {}
	local rules = (program and program.rules) or {}
	for i = 1, #rules do
		local rule = rules[i]
		rows[i] = {
			index = i,
			label = Format.label("ORDERS_RULE", { i }),
			conditionOp = rule.cond and rule.cond.op or Orders.ALWAYS,
			conditionText = Orders.conditionName(rule.cond and rule.cond.op),
			actionOp = rule.action and rule.action.op or Orders.SERVE,
			actionText = Orders.actionName(rule.action and rule.action.op),
		}
	end
	local ok, why = Orders.validate(program or Orders.empty(), tier or 1)
	-- How many rules this tier may hold. The limit is per tier, so the
	-- screen must read it per tier rather than hard-coding the ceiling --
	-- and the player is told they are full rather than finding out when the
	-- server refuses the next one.
	local limit = OrdersConfig.MAX_RULES_BY_TIER[tier or 1] or 0
	local full = #rows >= limit
	return {
		rows = rows,
		limit = limit,
		isFull = full,
		addText = Format.label("ORDERS_ADD"),
		fullText = full and Format.label("ORDERS_FULL") or nil,
		isEmpty = #rows == 0,
		emptyText = Format.label("ORDERS_EMPTY"),
		title = Format.label("ORDERS_TITLE"),
		valid = ok,
		invalidReason = why,
	}
end

-- THE PREVIEW. `recent` is an array of drifters the player actually received
-- (the client already has them: the Ledger replay reconstructs them). Runs
-- the real interpreter twice -- once with the current program, once with the
-- candidate -- and counts the visitors whose outcome would change.
--
-- Bounded by construction: the visitor ring holds at most a couple of dozen
-- entries, and `Orders.evaluate` is the same pure function the server runs.
function OrdersView.preview(candidate, recent, facts)
	local changed = 0
	local total = #recent
	local refused = 0
	for i = 1, total do
		local f = facts[i]
		if f ~= nil then
			local before = f.currentAction
			local after = Orders.evaluate(candidate, f)
			if after ~= nil and before ~= nil and after.op ~= before.op then
				changed = changed + 1
			end
			if after ~= nil and after.op == Orders.REFUSE then
				refused = refused + 1
			end
		end
	end
	return {
		total = total,
		changed = changed,
		refused = refused,
		text = Format.label("ORDERS_PREVIEW", { total, changed }),
	}
end

-- The payload for RF_SetOrders: the encoded bytecode, nothing else. The
-- server decodes and re-validates it; sending the rule table would mean
-- trusting the client's idea of what a rule is.
function OrdersView.setOrdersPayload(seq, program)
	local bytes = Orders.encode(program)
	return { seq = seq, bytes = bytes }
end

-- Re-exported so the view's consumers do not each reach into Domain. It is
-- `Drifter.CLASS_COUNT`, already a count -- an earlier version wrote
-- `#Drifter.CLASS_NAMES`, a table that has never existed, which made this
-- module throw AT LOAD TIME and take the whole Orders screen with it.
-- Nothing caught it for an entire iteration because no test ever required
-- this file; `check-syntax` parses, it does not execute.
OrdersView.CLASS_COUNT = Drifter.CLASS_COUNT

return OrdersView
