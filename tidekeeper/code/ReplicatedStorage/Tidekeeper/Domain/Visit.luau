--!nonstrict
-- ReplicatedStorage/Tidekeeper/Domain/Visit (ModuleScript)
--
-- Layer L2: pure. No services, no Instances, no yields, no time reads.
--
-- ONE DRIFTER, ONE POST, ONE DETERMINISTIC OUTCOME. This is the atom of the
-- whole game (doc 04 section 4) and the most heavily tested function in it.
--
-- Stages, in order: berth -> gate -> offer -> match -> purchase -> barter ->
-- settle -> narrate.
--
-- CONTRACT
-- --------
-- * `Visit.resolve` does NOT mutate `S`. It fills a delta, which the caller
--   applies with `Visit.apply`. Separating them is what makes the conservation
--   invariant checkable and what lets the client replay a visit against a
--   read-only mirror of the post.
-- * `Visit.resolve` allocates NOTHING in the steady path. Every scratch array,
--   the delta, the ledger entry and the receipt live in a context built once
--   by `Visit.newContext()` and reused for every visit in the run. The budget
--   is 18 us median / 50 us p99 (doc 04 section 6); the harness measures it
--   rather than asserting it by eye.
-- * Money is integer throughout. Scores are floats; a score never becomes
--   money without passing through math.floor here.

local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local DrifterConfig = require(script.Parent.Parent.Config.DrifterConfig)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local OrdersConfig = require(script.Parent.Parent.Config.OrdersConfig)
local MathExt = require(script.Parent.Parent.Lib.MathExt)
local Tables = require(script.Parent.Parent.Lib.Tables)
local Post = require(script.Parent.Post)
local Drifter = require(script.Parent.Drifter)
local Orders = require(script.Parent.Orders)
local Ledger = require(script.Parent.Ledger)
local Almanac = require(script.Parent.Almanac)
local Standing = require(script.Parent.Standing)

local Visit = {}

local floor = math.floor
local abs = math.abs

local AXES = DrifterConfig.TASTE_AXES
local MAX_ITEMS = EconomyConfig.MAX_ITEMS_PER_VISIT
local MAX_SHELVES = GameConfig.MAX_SHELF_SLOTS
-- Outstanding barter claims are bounded: an unbounded queue is a way for a
-- griefer to make someone's post blob refuse to save.
local MAX_CLAIMS = 64

local W_TASTE = EconomyConfig.MATCH_W_TASTE
local W_WANTS = EconomyConfig.MATCH_W_WANTS
local W_PRICE = EconomyConfig.MATCH_W_PRICE
local W_NOISE = EconomyConfig.MATCH_W_NOISE
local NOISE_SD = EconomyConfig.MATCH_NOISE_SD
local THRESHOLD = EconomyConfig.MATCH_THRESHOLD

-- Tide state name -> the 1..5 code used in ledger slots and TIDE_IS arguments.
local TIDE_CODE = {}
for i = 1, #OrdersConfig.TIDE_ARG_NAMES do
	TIDE_CODE[OrdersConfig.TIDE_ARG_NAMES[i]] = i
end
Visit.TIDE_CODE = TIDE_CODE

-- --------------------------------------------------------------- pricing

-- doc 06 section 3.
--
-- NOTE, a correction to the docs: doc 06 writes the signature as
-- `pricePressure(p, budget, dearTaste)` but its body never uses `budget` -- it
-- uses the find's base value V. The second parameter here is therefore
-- `baseValue`, which is what the formula actually needs. Budget is applied
-- separately, in the purchase stage, where it belongs.
function Visit.pricePressure(price, baseValue, dearTaste)
	if baseValue <= 0 then
		return -1
	end
	local r = price / baseValue
	local ideal = EconomyConfig.PRICE_IDEAL_BASE + EconomyConfig.PRICE_DEAR_COEFF * dearTaste
	local v = EconomyConfig.PRICE_PRESSURE_PEAK - EconomyConfig.PRICE_PRESSURE_SLOPE * abs(r - ideal)
	if v > 1 then
		return 1
	end
	if v < -1 then
		return -1
	end
	return v
end

-- The per-visitor price a standing order's `serve at +/-N%` produces. Always
-- an integer, never below MIN_PRICE.
function Visit.adjustedPrice(price, adjustPercent)
	if adjustPercent == 0 then
		return price
	end
	local p = MathExt.applyPercent(price, adjustPercent)
	if p < EconomyConfig.MIN_PRICE then
		return EconomyConfig.MIN_PRICE
	end
	if p > EconomyConfig.MAX_PRICE then
		return EconomyConfig.MAX_PRICE
	end
	return p
end

-- --------------------------------------------------------------- context

-- Allocate every buffer the hot path will ever need, once.
function Visit.newContext()
	local ctx = {
		epoch = 0,
		tide = "SLACK",
		berthsUsed = 0,
		maxBerths = GameConfig.MAX_BERTHS,
		hostId = 0,
	}

	ctx.facts = {
		class = 0,
		current = 0,
		standing = 0,
		tide = "SLACK",
		wantsSomething = false,
		budget = 0,
		beacons = 0,
		taste = nil,
		visits = 0,
	}

	-- Parallel scratch arrays, capacity MAX_SHELVES.
	ctx.candShelf = {}
	ctx.candScore = {}
	ctx.sortKey = {}
	ctx.sortSlot = {}
	for i = 1, MAX_SHELVES do
		ctx.candShelf[i] = 0
		ctx.candScore[i] = 0
		ctx.sortKey[i] = 0
		ctx.sortSlot[i] = 0
	end

	ctx.delta = {
		actorId = 0,
		outcome = 0,
		coin = 0,
		spent = 0,
		warmth = 0,
		standing = 0,
		renown = 0,
		currentIndex = 1,
		itemCount = 0,
		itemId = {},
		itemQty = {},
		itemPrice = {},
		claimCount = 0,
		claimId = {},
		claimQty = {},
		holdBerth = false,
		gifted = false,
		firstFind = false,
		metWant = 0,
		sourPrice = false,
		gatedByStanding = false,
		ruleIndex = 0,
		leftBehind = 0,
		primaryFind = 0,
		ownerId = 0,
		epoch = 0,
	}
	for i = 1, MAX_ITEMS do
		ctx.delta.itemId[i] = 0
		ctx.delta.itemQty[i] = 0
		ctx.delta.itemPrice[i] = 0
	end
	for i = 1, DrifterConfig.MAX_CARGO do
		ctx.delta.claimId[i] = 0
		ctx.delta.claimQty[i] = 0
	end

	ctx.entry = { templateId = 0, epoch = 0, actorId = 0, slotCount = 0, slots = {} }
	for i = 1, GameConfig.MAX_LEDGER_SLOTS do
		ctx.entry.slots[i] = 0
	end

	ctx.receipt = {
		v = 1,
		drifterId = 0,
		hostId = 0,
		epoch = 0,
		outcome = 0,
		spent = 0,
		warmth = 0,
		flags = 0,
		noteId = 0,
	}

	ctx.tmpl = {
		class = 0,
		gatedByStanding = false,
		gifted = false,
		firstFind = false,
		sourPrice = false,
		warmth = 0,
		metWant = false,
	}

	return ctx
end

local function resetDelta(delta)
	delta.actorId = 0
	delta.outcome = 0
	delta.coin = 0
	delta.spent = 0
	delta.warmth = 0
	delta.standing = 0
	delta.renown = 0
	delta.currentIndex = 1
	delta.itemCount = 0
	delta.claimCount = 0
	delta.holdBerth = false
	delta.gifted = false
	delta.firstFind = false
	delta.metWant = 0
	delta.sourPrice = false
	delta.gatedByStanding = false
	delta.ruleIndex = 0
	delta.leftBehind = 0
	delta.primaryFind = 0
	delta.ownerId = 0
	delta.epoch = 0
end

-- --------------------------------------------------------------- narration

local function narrate(ctx, D, outcome, primaryFind, primaryPrice)
	local delta = ctx.delta
	local tmpl = ctx.tmpl
	tmpl.class = D.class
	tmpl.gatedByStanding = delta.ruleIndex > 0 and delta.gatedByStanding == true
	tmpl.gifted = delta.gifted
	tmpl.firstFind = delta.firstFind
	tmpl.sourPrice = delta.sourPrice
	tmpl.warmth = delta.warmth
	tmpl.metWant = delta.metWant > 0

	local templateId = Ledger.selectTemplate(outcome, tmpl)
	local entry = ctx.entry
	entry.templateId = templateId
	entry.epoch = ctx.epoch
	entry.actorId = D.id
	local slots = entry.slots

	if templateId == Ledger.T_MISSED_TIDE then
		slots[1] = D.class
		slots[2] = TIDE_CODE[ctx.tide] or 0
		entry.slotCount = 2
	elseif templateId == Ledger.T_MISSED_TIDE_DEEPWATER then
		slots[1] = TIDE_CODE[ctx.tide] or 0
		entry.slotCount = 1
	elseif templateId == Ledger.T_NO_BERTH then
		slots[1] = D.class
		entry.slotCount = 1
	elseif templateId == Ledger.T_REFUSED_GATE then
		slots[1] = delta.ruleIndex
		slots[2] = D.standing
		entry.slotCount = 2
	elseif templateId == Ledger.T_REFUSED_COLD then
		slots[1] = delta.ruleIndex
		slots[2] = D.class
		entry.slotCount = 2
	elseif templateId == Ledger.T_PARTIAL_BUDGET then
		slots[1] = primaryFind
		slots[2] = primaryPrice
		slots[3] = delta.itemCount
		slots[4] = delta.leftBehind
		entry.slotCount = 4
	elseif templateId == Ledger.T_GIFT then
		slots[1] = primaryFind
		slots[2] = delta.warmth
		slots[3] = delta.renown
		entry.slotCount = 3
	elseif templateId == Ledger.T_SERVED_WARM then
		slots[1] = primaryFind
		slots[2] = primaryPrice
		slots[3] = delta.itemCount
		slots[4] = delta.warmth
		entry.slotCount = 4
	elseif templateId == Ledger.T_SERVED_SOUR_PRICE then
		slots[1] = primaryFind
		slots[2] = primaryPrice
		slots[3] = floor(primaryPrice * 100 / math.max(1, Post.baseValue(primaryFind)))
		entry.slotCount = 3
	elseif templateId == Ledger.T_SERVED_WANT then
		slots[1] = primaryFind
		slots[2] = primaryPrice
		slots[3] = delta.metWant
		entry.slotCount = 3
	else
		slots[1] = primaryFind
		slots[2] = primaryPrice
		slots[3] = delta.itemCount
		entry.slotCount = 3
	end

	local receipt = ctx.receipt
	receipt.v = 1
	receipt.drifterId = D.id
	receipt.hostId = ctx.hostId
	receipt.epoch = ctx.epoch
	receipt.outcome = outcome
	receipt.spent = delta.spent
	receipt.warmth = delta.warmth
	receipt.flags = 0
	receipt.noteId = 0
	if D.letterId ~= nil and D.letterId > 0 then
		receipt.flags = 1
		receipt.noteId = D.letterId
	end
end

local function finish(ctx, D, outcome, primaryFind, primaryPrice)
	local delta = ctx.delta
	delta.outcome = outcome
	delta.warmth = MathExt.clampInt(delta.warmth, EconomyConfig.WARMTH_MIN, EconomyConfig.WARMTH_MAX)
	delta.primaryFind = primaryFind or 0
	narrate(ctx, D, outcome, primaryFind or 0, primaryPrice or 0)
	return delta, ctx.entry, ctx.receipt
end

-- --------------------------------------------------------------- resolve

-- `ctx` must come from `Visit.newContext()` and must have `epoch`, `tide`,
-- `hostId`, `berthsUsed` and `maxBerths` set by the caller.
function Visit.resolve(S, D, ctx, rng)
	local delta = ctx.delta
	resetDelta(delta)
	delta.actorId = D.id
	delta.ownerId = D.owner
	delta.epoch = ctx.epoch
	delta.currentIndex = D.current + 1

	-- Stage 1: berth ------------------------------------------------------
	if not Drifter.admitsTide(D.class, ctx.tide) then
		delta.warmth = EconomyConfig.WARMTH_BASE_MISSED_TIDE
		delta.standing = EconomyConfig.STANDING_ON_MISSED_TIDE
		return finish(ctx, D, Ledger.MISSED_TIDE, 0, 0)
	end
	if ctx.berthsUsed >= ctx.maxBerths then
		delta.warmth = EconomyConfig.WARMTH_BASE_NO_BERTH
		return finish(ctx, D, Ledger.NO_BERTH, 0, 0)
	end

	-- Stage 2: gate -------------------------------------------------------
	local facts = ctx.facts
	facts.class = D.class
	facts.current = D.current
	facts.standing = D.standing
	facts.tide = ctx.tide
	facts.budget = D.budget
	facts.beacons = D.beacons
	facts.taste = D.taste
	facts.visits = Post.visitCount(S, D.owner)
	facts.wantsSomething = false
	local wants = D.wants
	for i = 1, #wants do
		if Post.stockOf(S, wants[i]) > 0 then
			facts.wantsSomething = true
		end
	end

	local action, ruleIndex = Orders.evaluate(S.orders, facts)
	delta.ruleIndex = ruleIndex
	delta.gatedByStanding = false
	if ruleIndex > 0 then
		local rule = S.orders.rules[ruleIndex]
		if rule ~= nil and rule.cond ~= nil and rule.cond.op == Orders.STANDING_GTE then
			delta.gatedByStanding = true
		end
	end

	local op = action.op
	if op == Orders.HOLD_BERTH then
		-- A held berth is not a rejection of this visitor; it is the host
		-- keeping the slot for something bigger. No Standing penalty.
		delta.holdBerth = true
		delta.warmth = EconomyConfig.WARMTH_BASE_NO_BERTH
		return finish(ctx, D, Ledger.NO_BERTH, 0, 0)
	end
	if op == Orders.REFUSE then
		delta.warmth = EconomyConfig.WARMTH_BASE_REFUSED
		delta.standing = EconomyConfig.STANDING_ON_REFUSED
		return finish(ctx, D, Ledger.REFUSED, 0, 0)
	end

	local adjust = 0
	local groupFilter = 0
	local acceptBarter = false
	local giftId = 0
	if op == Orders.SERVE_ADJ then
		adjust = action.a or 0
	elseif op == Orders.OFFER_ONLY then
		groupFilter = action.a or 0
	elseif op == Orders.ACCEPT_BARTER then
		acceptBarter = true
	elseif op == Orders.GIFT then
		giftId = action.a or 0
	end

	-- Stage 2b: gift is a short circuit; it bypasses match and purchase.
	if giftId > 0 then
		if Post.stockOf(S, giftId) > 0 then
			delta.itemCount = 1
			delta.itemId[1] = giftId
			delta.itemQty[1] = 1
			delta.itemPrice[1] = 0
			delta.gifted = true
			delta.spent = 0
			delta.warmth = EconomyConfig.WARMTH_BASE_GIFT
			delta.standing = EconomyConfig.STANDING_ON_GIFT
			delta.renown = EconomyConfig.RENOWN_ON_GIFT
			if Drifter.wantsFind(D, giftId) then
				delta.metWant = 1
			end
			return finish(ctx, D, Ledger.SERVED, giftId, 0)
		end
		-- Nothing to give: fall through and trade normally rather than
		-- silently producing a no-op visit.
	end

	-- Stage 3: offer ------------------------------------------------------
	local shelves = S.shelves
	local shelfCount = #shelves
	local candShelf = ctx.candShelf
	local candScore = ctx.candScore
	local candidates = 0
	for i = 1, shelfCount do
		local shelf = shelves[i]
		local id = shelf.id
		local admit = Post.stockOf(S, id) > 0
		if admit and groupFilter > 0 and Post.groupOf(id) ~= groupFilter then
			admit = false
		end
		if admit then
			candidates = candidates + 1
			candShelf[candidates] = i
			candScore[candidates] = 0
		end
	end

	-- Stage 4: match ------------------------------------------------------
	local dear = Drifter.dearTaste(D)
	local sortKey = ctx.sortKey
	local sortSlot = ctx.sortSlot
	for i = 1, candidates do
		local shelf = shelves[candShelf[i]]
		local id = shelf.id
		local price = Visit.adjustedPrice(shelf.price, adjust)
		local taste = Post.tasteOf(id)
		local score = W_TASTE * MathExt.cosine(taste, D.taste, AXES)
		if Drifter.wantsFind(D, id) then
			score = score + W_WANTS
		end
		score = score + W_PRICE * Visit.pricePressure(price, Post.baseValue(id), dear)
		score = score + W_NOISE * rng:normal(0, NOISE_SD)
		candScore[i] = score
		-- Sort descending by score. The key is negated and the find id added as
		-- a 1e-6 tiebreak so that two identically scored items always resolve
		-- in the same order -- table.sort is not stable and this is money.
		sortKey[i] = -score + id * 1e-9
		sortSlot[i] = i
	end
	Tables.insertionSortPairs(sortKey, sortSlot, candidates)

	-- Stage 5: purchase ---------------------------------------------------
	local budget = Drifter.effectiveBudget(D)
	local maxItems = Drifter.classMaxItems(D.class)
	if maxItems > MAX_ITEMS then
		maxItems = MAX_ITEMS
	end
	local spent = 0
	local bought = 0
	local leftBehind = 0
	local primaryFind = 0
	local primaryPrice = 0
	local sour = false
	local metWant = 0
	local firstFind = false

	for rank = 1, candidates do
		local i = sortSlot[rank]
		if candScore[i] >= THRESHOLD then
			local shelf = shelves[candShelf[i]]
			local id = shelf.id
			local price = Visit.adjustedPrice(shelf.price, adjust)
			if bought >= maxItems then
				leftBehind = leftBehind + 1
			elseif price > budget - spent then
				leftBehind = leftBehind + 1
			else
				bought = bought + 1
				spent = spent + price
				delta.itemId[bought] = id
				delta.itemQty[bought] = 1
				delta.itemPrice[bought] = price
				if bought == 1 then
					primaryFind = id
					primaryPrice = price
				end
				if Drifter.wantsFind(D, id) then
					metWant = metWant + 1
				end
				local base = Post.baseValue(id)
				if base > 0 and price > base * EconomyConfig.PRICE_SOUR_RATIO then
					sour = true
				end
			end
		end
	end
	delta.itemCount = bought
	delta.spent = spent
	delta.coin = spent
	delta.leftBehind = leftBehind
	delta.metWant = metWant
	delta.sourPrice = sour

	-- Stage 6: barter -----------------------------------------------------
	-- A claim, not a transfer (doc 03 section 9): the host gains the RIGHT to
	-- the cargo, and the item moves only when the other player's post next
	-- resolves. Nothing is created here.
	if acceptBarter then
		local cargo = D.cargo
		local claims = 0
		for i = 1, #cargo do
			if claims < DrifterConfig.MAX_CARGO then
				claims = claims + 1
				delta.claimId[claims] = cargo[i]
				delta.claimQty[claims] = 1
			end
		end
		delta.claimCount = claims
	end

	-- Stage 7: settle -----------------------------------------------------
	local outcome
	if bought > 0 and leftBehind == 0 then
		outcome = Ledger.SERVED
	else
		outcome = Ledger.PARTIAL
	end

	-- "First one of these you have ever sold." Tracked in its own bitset:
	-- S.almanac records what the host has HELD, which is always true of
	-- anything on a shelf, so it could never fire this.
	if primaryFind > 0 and Almanac.has(S.sold, primaryFind) == false then
		firstFind = true
	end
	delta.firstFind = firstFind

	local warmth
	if outcome == Ledger.SERVED then
		warmth = EconomyConfig.WARMTH_BASE_SERVED
		delta.standing = EconomyConfig.STANDING_ON_SERVED
		delta.renown = EconomyConfig.RENOWN_ON_SERVED
	else
		warmth = EconomyConfig.WARMTH_BASE_PARTIAL
		delta.standing = EconomyConfig.STANDING_ON_PARTIAL
	end
	warmth = warmth + EconomyConfig.WARMTH_PER_WANT_MET * metWant
	if sour then
		warmth = warmth + EconomyConfig.WARMTH_SOUR_PRICE
	end
	delta.warmth = warmth

	-- Stage 8: narrate ----------------------------------------------------
	return finish(ctx, D, outcome, primaryFind, primaryPrice)
end

-- ----------------------------------------------------------------- apply

-- Apply a delta to `S`. Separate from `resolve` on purpose: `resolve` is a
-- pure function of its inputs, and every mutation of the post state happens
-- here, in one place that can be audited.
--
-- Returns (true) or (false, message). A failure leaves `S` untouched only for
-- the checks made before the first write; the caller treats a false as a bug,
-- not as a recoverable condition.
function Visit.apply(S, delta)
	if delta.primaryFind > 0 and delta.outcome == Ledger.SERVED then
		Almanac.record(S.sold, delta.primaryFind)
	end
	local claims = S.claims
	for i = 1, delta.claimCount do
		if #claims < MAX_CLAIMS then
			claims[#claims + 1] = {
				id = delta.claimId[i],
				qty = delta.claimQty[i],
				fromOwner = delta.ownerId,
				epoch = delta.epoch,
			}
		end
	end
	for i = 1, delta.itemCount do
		local taken = Post.removeStock(S, delta.itemId[i], delta.itemQty[i])
		if taken ~= delta.itemQty[i] then
			return false, string.format("stock underflow applying find %d", delta.itemId[i])
		end
	end
	S.coin = S.coin + delta.coin
	if S.coin > GameConfig.MAX_COIN then
		S.coin = GameConfig.MAX_COIN
	end
	S.stats.coinEarned = S.stats.coinEarned + delta.coin
	local index = delta.currentIndex
	S.standing[index] = Standing.grant(S.standing[index], delta.standing)
	S.renown = S.renown + delta.renown

	-- Lifetime gift counter (schema v3). Counted here rather than at the
	-- decision site so that a gift only counts once it has actually been
	-- applied -- a delta that failed its stock check never happened.
	if delta.gifted then
		S.stats.giftsGiven = (S.stats.giftsGiven or 0) + 1
	end

	local outcome = delta.outcome
	if outcome == Ledger.SERVED then
		S.stats.served = S.stats.served + 1
	elseif outcome == Ledger.REFUSED then
		S.stats.refused = S.stats.refused + 1
	elseif outcome == Ledger.PARTIAL then
		S.stats.partial = S.stats.partial + 1
	elseif outcome == Ledger.MISSED_TIDE then
		S.stats.missed = S.stats.missed + 1
	elseif outcome == Ledger.NO_BERTH then
		S.stats.noBerth = S.stats.noBerth + 1
	end
	return true
end

-- Copy the reused entry/receipt out of the context so they can be kept. The
-- hot path never calls these; Resolve does, once per visit.
function Visit.cloneEntry(ctx)
	local slots = {}
	for i = 1, ctx.entry.slotCount do
		slots[i] = ctx.entry.slots[i]
	end
	return Ledger.entry(ctx.entry.templateId, ctx.entry.epoch, ctx.entry.actorId, slots)
end

function Visit.cloneReceipt(ctx)
	local r = ctx.receipt
	return {
		v = r.v,
		drifterId = r.drifterId,
		hostId = r.hostId,
		epoch = r.epoch,
		outcome = r.outcome,
		spent = r.spent,
		warmth = r.warmth,
		flags = r.flags,
		noteId = r.noteId,
	}
end

return Visit
