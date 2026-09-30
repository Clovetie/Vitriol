--!nonstrict
-- ReplicatedStorage/Tidekeeper/Domain/Resolve (ModuleScript)
--
-- Layer L2: pure. No services, no Instances, no yields, no time reads.
--
-- RESOLVE-ON-READ (doc 04 sections 2-3). The whole game is presentation on top
-- of this function.
--
--   Resolve.run(S, now, inbound) -> (S', entries, receipts, info)
--
-- pure          -- no services, no os.time, no yields, no Instance
-- total         -- defined for every input, including now < S.resolvedAt
-- deterministic -- same inputs, same outputs, bit for bit
-- bounded       -- at most GameConfig.MAX_CATCHUP_EPOCHS steps
--
-- `now` is an ARGUMENT. This module must never learn what time it is; that is
-- the property that lets the same code run on the server, in a headless test
-- and inside an offline solo session and necessarily agree.
--
-- `S` is NOT mutated. The resolver deep-copies on entry and returns the new
-- state. That costs one copy per session -- not per visit -- and it is what
-- makes the 1000-run replay proof (doc 04 section 5.1) possible at all.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local FindsConfig = require(script.Parent.Parent.Config.FindsConfig)
local Hash = require(script.Parent.Parent.Lib.Hash)
local RNG = require(script.Parent.Parent.Lib.RNG)
local Tables = require(script.Parent.Parent.Lib.Tables)
local Tide = require(script.Parent.Parent.Lib.Tide)
local Post = require(script.Parent.Post)
local Visit = require(script.Parent.Visit)
local Ledger = require(script.Parent.Ledger)
local Standing = require(script.Parent.Standing)

local Resolve = {}

local floor = math.floor

local MAX_EPOCHS = GameConfig.MAX_CATCHUP_EPOCHS
local MAX_ARRIVALS = GameConfig.MAX_ARRIVALS_PER_EPOCH

-- A reusable workspace, so a server resolving one player after another
-- allocates once rather than once per player.
function Resolve.newWorkspace()
	return {
		ctx = Visit.newContext(),
		rng = RNG.new(0),
		-- Arrival planning buffers.
		orderKey = {},
		orderIndex = {},
		assigned = {},
		epochCount = {},
		epochKey = {},
		epochSlot = {},
	}
end

-- --------------------------------------------------------------- per-epoch

local function respawnComb(S, epoch)
	local comb = S.comb
	local matured = 0
	for i = 1, #comb do
		local ready = comb[i]
		if ready > 0 and epoch >= ready then
			comb[i] = 0
			matured = matured + 1
		end
	end
	return matured
end

local function spoil(S)
	local store = S.store
	local lost = 0
	-- Walk backwards: removing an exhausted entry compacts the array.
	for i = #store, 1, -1 do
		local entry = store[i]
		if Post.isPerishable(entry.id) then
			local amount = floor(entry.qty * EconomyConfig.SPOIL_PER_MILLE / 1000)
			if amount < 1 then
				amount = 1
			end
			if amount > entry.qty then
				amount = entry.qty
			end
			entry.qty = entry.qty - amount
			lost = lost + amount
			if entry.qty == 0 then
				table.remove(store, i)
			end
		end
	end
	return lost
end

local function accruePassive(S)
	local cap = Post.passiveCap(S.tier)
	local earned = floor(Post.shelvedValue(S) * EconomyConfig.PASSIVE_RATE_PER_MILLE / 1000)
	if earned > cap then
		earned = cap
	end
	if earned < 0 then
		earned = 0
	end
	S.coin = S.coin + earned
	if S.coin > GameConfig.MAX_COIN then
		S.coin = GameConfig.MAX_COIN
	end
	S.stats.coinEarned = S.stats.coinEarned + earned
	return earned
end

-- ------------------------------------------------------------ long absence

-- Doc 04 section 3.1. The skipped time is summarised, never silently dropped,
-- and the summary is deliberately GENEROUS: returning players are the most
-- valuable players a live game has, and a return must never feel like a bill.
local function applyLongAbsence(S, skippedEpochs, rng)
	for i = 1, EconomyConfig.CURRENT_COUNT do
		S.standing[i] = Standing.floorOf(S.standing[i])
	end
	local perished = 0
	local store = S.store
	for i = #store, 1, -1 do
		if Post.isPerishable(store[i].id) then
			perished = perished + store[i].qty
			table.remove(store, i)
		end
	end
	S.coin = S.coin + EconomyConfig.LONG_ABSENCE_CACHE_COIN
	S.stats.coinEarned = S.stats.coinEarned + EconomyConfig.LONG_ABSENCE_CACHE_COIN
	local granted = 0
	local finds = Post.knownFindCount()
	for _ = 1, EconomyConfig.LONG_ABSENCE_CACHE_ITEMS do
		if finds > 0 then
			local findId = FindsConfig.FINDS[rng:range(1, finds)][1]
			local added = Post.addStock(S, findId, 1)
			granted = granted + added
		end
	end
	return perished, granted
end

-- ------------------------------------------------------------------- run

-- `inbound` is an array of validated Drifter records. `work` is an optional
-- workspace from `Resolve.newWorkspace()`; pass one to avoid re-allocating.
function Resolve.run(S, now, inbound, work)
	-- Never call this local `workspace`: that is a Roblox global, and shadowing
	-- it in a pure module is how platform surface sneaks back in.
	local scratch = work or Resolve.newWorkspace()
	local ctx = scratch.ctx
	local rng = scratch.rng
	local entries = {}
	local receipts = {}
	local info = {
		epochsSimulated = 0,
		firstEpoch = 0,
		lastEpoch = 0,
		clamped = false,
		skippedEpochs = 0,
		arrivalsPlaced = 0,
		arrivalsDropped = 0,
		visitsResolved = 0,
		passiveTotal = 0,
		soldUnits = 0,
		spoiledUnits = 0,
		grantedUnits = 0,
		perishedUnits = 0,
		coinEarned = 0,
	}

	local S2 = Tables.deepCopy(S)
	local target = floor(now)

	-- Clock skew, a re-entrant call, or a server whose clock went backwards.
	-- A no-op is the only safe answer: never simulate negative time.
	if target <= S2.resolvedAt then
		return S2, entries, receipts, info
	end

	local fromEpoch = Tide.epoch(S2.resolvedAt)
	local toEpoch = Tide.epoch(target)
	if toEpoch <= fromEpoch then
		S2.resolvedAt = target
		return S2, entries, receipts, info
	end

	local firstEpoch = fromEpoch + 1
	local span = toEpoch - fromEpoch
	if span > MAX_EPOCHS then
		info.clamped = true
		info.skippedEpochs = span - MAX_EPOCHS
		firstEpoch = toEpoch - MAX_EPOCHS + 1
		rng:reseed(Hash.mix(S2.postId, firstEpoch, S2.salt))
		local perished, granted = applyLongAbsence(S2, info.skippedEpochs, rng)
		info.perishedUnits = perished
		info.grantedUnits = info.grantedUnits + granted
		local entry = Ledger.entry(Ledger.T_LONG_ABSENCE, firstEpoch - 1, S2.owner, {
			info.skippedEpochs,
			EconomyConfig.LONG_ABSENCE_CACHE_COIN,
			granted,
		})
		entries[#entries + 1] = entry
	end

	local epochCount = toEpoch - firstEpoch + 1
	info.firstEpoch = firstEpoch
	info.lastEpoch = toEpoch
	info.epochsSimulated = epochCount

	-- ---------------------------------------------------------- arrivals
	--
	-- Every Drifter gets a deterministic epoch from its own id and the post's
	-- salt, so two servers resolving the same player land on the same
	-- schedule. Overflow spills forward; whatever will not fit is dropped and
	-- COUNTED -- a silent drop would be an invisible economy leak.
	local inboundCount = 0
	if inbound ~= nil then
		inboundCount = #inbound
	end
	local orderKey = scratch.orderKey
	local orderIndex = scratch.orderIndex
	for i = 1, inboundCount do
		orderKey[i] = Hash.mix(inbound[i].id, S2.salt)
		orderIndex[i] = i
	end
	Tables.insertionSortPairs(orderKey, orderIndex, inboundCount)

	local assigned = scratch.assigned
	local epochLoad = scratch.epochCount
	for e = 1, epochCount do
		epochLoad[e] = 0
	end
	for i = 1, inboundCount do
		local d = inbound[orderIndex[i]]
		local slot = Hash.reduce(Hash.mix(d.id, S2.salt, 7), epochCount) + 1
		local placed = 0
		for step = 0, epochCount - 1 do
			local candidate = slot + step
			if candidate > epochCount then
				candidate = candidate - epochCount
			end
			if placed == 0 and epochLoad[candidate] < MAX_ARRIVALS then
				epochLoad[candidate] = epochLoad[candidate] + 1
				placed = candidate
			end
		end
		assigned[i] = placed
		if placed == 0 then
			info.arrivalsDropped = info.arrivalsDropped + 1
		else
			info.arrivalsPlaced = info.arrivalsPlaced + 1
		end
	end

	-- ------------------------------------------------------------- epochs
	local epochKey = scratch.epochKey
	local epochSlot = scratch.epochSlot
	ctx.hostId = S2.owner
	ctx.maxBerths = GameConfig.MAX_BERTHS

	for offset = 0, epochCount - 1 do
		local e = firstEpoch + offset
		rng:reseed(Hash.mix(S2.postId, e, S2.salt))

		Standing.decayAll(S2.standing)
		respawnComb(S2, e)
		info.spoiledUnits = info.spoiledUnits + spoil(S2)

		-- Gather this epoch's arrivals and put them in the one true order:
		-- Hash.mix(drifterId, e) ascending (doc 04 section 3).
		local arrivals = 0
		for i = 1, inboundCount do
			if assigned[i] == offset + 1 then
				arrivals = arrivals + 1
				epochKey[arrivals] = Hash.mix(inbound[orderIndex[i]].id, e)
				epochSlot[arrivals] = orderIndex[i]
			end
		end
		Tables.insertionSortPairs(epochKey, epochSlot, arrivals)

		ctx.epoch = e
		ctx.tide = Tide.stateForEpoch(e)
		ctx.berthsUsed = 0

		local served = 0
		local coinThisEpoch = 0
		for k = 1, arrivals do
			local d = inbound[epochSlot[k]]
			local delta = Visit.resolve(S2, d, ctx, rng)
			local ok, message = Visit.apply(S2, delta)
			if not ok then
				error("Resolve: applying a visit delta failed: " .. tostring(message), 0)
			end
			Post.recordVisit(S2, d.owner, e)
			for j = 1, delta.itemCount do
				info.soldUnits = info.soldUnits + delta.itemQty[j]
			end
			coinThisEpoch = coinThisEpoch + delta.coin
			if delta.outcome == Ledger.SERVED then
				served = served + 1
			end
			if delta.outcome ~= Ledger.MISSED_TIDE then
				ctx.berthsUsed = ctx.berthsUsed + 1
			end
			local entry = Visit.cloneEntry(ctx)
			entries[#entries + 1] = entry
			receipts[#receipts + 1] = Visit.cloneReceipt(ctx)
			info.visitsResolved = info.visitsResolved + 1
		end

		local passive = accruePassive(S2)
		info.passiveTotal = info.passiveTotal + passive
		coinThisEpoch = coinThisEpoch + passive
		info.coinEarned = info.coinEarned + coinThisEpoch

		if arrivals == 0 then
			entries[#entries + 1] = Ledger.entry(Ledger.T_EPOCH_QUIET, e, S2.owner, { Visit.TIDE_CODE[ctx.tide] or 0 })
		else
			entries[#entries + 1] = Ledger.entry(Ledger.T_EPOCH_SUMMARY, e, S2.owner, {
				arrivals,
				coinThisEpoch,
				served,
				passive,
			})
		end
	end

	S2.resolvedAt = target
	return S2, entries, receipts, info
end

-- -------------------------------------------------------------- invariants

-- The seven invariants of doc 04 section 9, as one callable check.
-- `before` and `after` are post states; `info` is the third return of `run`.
-- Returns (true) or (false, message).
function Resolve.checkInvariants(before, after, info, entries, receipts)
	-- 1. Conservation of stock.
	local expected = Post.totalStock(before) + info.grantedUnits - info.soldUnits - info.spoiledUnits - info.perishedUnits
	local actual = Post.totalStock(after)
	if actual ~= expected then
		return false, string.format("conservation: stock is %d, accounting says %d", actual, expected)
	end
	-- 2. No negative anything.
	local ok, message = Post.checkInvariants(after)
	if not ok then
		return false, "structural: " .. message
	end
	-- 3. Monotonic time.
	if after.resolvedAt < before.resolvedAt then
		return false, "monotonic time: resolvedAt went backwards"
	end
	-- 4. Bounded passive generation.
	local maxPassive = Post.passiveCap(after.tier) * info.epochsSimulated
	if info.passiveTotal > maxPassive then
		return false, string.format("passive income %d exceeds the cap of %d", info.passiveTotal, maxPassive)
	end
	-- 5. Clamp safety.
	if info.epochsSimulated > MAX_EPOCHS then
		return false, string.format("simulated %d epochs, the clamp is %d", info.epochsSimulated, MAX_EPOCHS)
	end
	-- 6. Receipt exactly once: one receipt per resolved visit, no more.
	if #receipts ~= info.visitsResolved then
		return false, string.format("%d receipts for %d visits", #receipts, info.visitsResolved)
	end
	-- 7. Every ledger entry is well formed and epochs never go backwards.
	local previous = nil
	for i = 1, #entries do
		local valid, why = Ledger.isValid(entries[i])
		if not valid then
			return false, string.format("ledger entry %d: %s", i, why)
		end
		if previous ~= nil and entries[i].epoch < previous then
			return false, "ledger entries are not in ascending epoch order"
		end
		previous = entries[i].epoch
	end
	return true
end

-- Idempotence helper: resolving again with the same `now` must be a no-op.
-- Exposed because it is an invariant worth asserting from outside, not just a
-- property of the implementation.
function Resolve.isNoOp(S, now)
	return floor(now) <= S.resolvedAt
end

Resolve.MAX_EPOCHS = MAX_EPOCHS

return Resolve
