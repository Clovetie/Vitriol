--!nonstrict
-- ReplicatedStorage/Tidekeeper/Domain/Post (ModuleScript)
--
-- Layer L2: pure. No services, no Instances, no yields, no time reads.
--
-- The post: stock, shelves, tier, Standing, Almanac, the visitor ring.
-- This module owns the SHAPE of `S`, the state that `Resolve` steps and that
-- `PostCodec` persists.
--
-- Two representation decisions that everything else depends on:
--
--  * `store` is a DENSE ARRAY SORTED BY FIND ID, not a `[findId] = qty` map.
--    A map would be one line shorter and would make the whole simulation
--    non-deterministic, because `pairs` order is unspecified and the resolver
--    iterates stock. Binary search keeps lookups O(log n) over at most 160
--    entries.
--  * every quantity, price and coin figure is an INTEGER. There is no float
--    anywhere in the post state.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local FindsConfig = require(script.Parent.Parent.Config.FindsConfig)
local OrdersConfig = require(script.Parent.Parent.Config.OrdersConfig)
local Tables = require(script.Parent.Parent.Lib.Tables)
local Almanac = require(script.Parent.Almanac)

local Post = {}

local floor = math.floor

local MAX_SHELVES = GameConfig.MAX_SHELF_SLOTS
local MAX_STORE = GameConfig.MAX_STORE_ENTRIES
local MAX_STACK = GameConfig.MAX_STOCK_PER_ENTRY
local RING = GameConfig.VISITOR_RING_SIZE

-- find id -> row in FindsConfig.FINDS, built once at load.
local FIND_ROW = {}
for i = 1, #FindsConfig.FINDS do
	FIND_ROW[FindsConfig.FINDS[i][1]] = i
end

Post.COL_ID = 1
Post.COL_NAME = 2
Post.COL_VALUE = 3
Post.COL_PERISHABLE = 4
Post.COL_GROUP = 5
Post.COL_ZONE = 6
Post.COL_RARITY = 7
Post.COL_TASTE = 8

function Post.findRow(findId)
	local row = FIND_ROW[findId]
	if row == nil then
		return nil
	end
	return FindsConfig.FINDS[row]
end

function Post.baseValue(findId)
	local row = Post.findRow(findId)
	if row == nil then
		return 0
	end
	return row[Post.COL_VALUE]
end

function Post.isPerishable(findId)
	local row = Post.findRow(findId)
	if row == nil then
		return false
	end
	return row[Post.COL_PERISHABLE] == 1
end

function Post.groupOf(findId)
	local row = Post.findRow(findId)
	if row == nil then
		return 0
	end
	return row[Post.COL_GROUP]
end

function Post.tasteOf(findId)
	local row = Post.findRow(findId)
	if row == nil then
		return nil
	end
	return row[Post.COL_TASTE]
end

function Post.knownFindCount()
	return #FindsConfig.FINDS
end

-- A brand-new post, tier 1, on The Shallows.
function Post.new(postId, owner, salt, now)
	local standing = {}
	for i = 1, EconomyConfig.CURRENT_COUNT do
		standing[i] = 0
	end
	local comb = {}
	for i = 1, GameConfig.MAX_COMB_NODES do
		comb[i] = 0
	end
	return {
		v = GameConfig.SCHEMA_VERSION,
		postId = postId,
		owner = owner,
		salt = salt,
		tier = 1,
		season = 1,
		current = 0,
		resolvedAt = floor(now),
		coin = 0,
		renown = 0,
		standing = standing,
		almanac = Almanac.new(),
		sold = Almanac.new(),
		comb = comb,
		shelves = {},
		store = {},
		orders = { version = 1, rules = {} },
		ring = {},
		claims = {},
		stats = { served = 0, refused = 0, partial = 0, missed = 0, noBerth = 0, coinEarned = 0 },
		-- Schema v2 (OD16). The tide epoch of the most recent Drifter this
		-- post published. Persisting it is what makes
		-- one-Drifter-per-post-per-epoch hold ACROSS SERVERS: before v2 the
		-- rule lived in a server-local table, so a player who hopped servers
		-- inside one 6.2-hour epoch could publish twice and collide their own
		-- id.
		--
		-- ABSENT means "never published". It is deliberately NOT 0, because
		-- epoch 0 is a real epoch -- the first 6.2 hours after TideConfig.EPOCH
		-- -- and a sentinel that collides with a real value is a bug waiting
		-- for a launch day. The codec maps nil <-> the wire value 0 by storing
		-- epoch + 1, so the persisted form has an unambiguous sentinel too.
	}
end

-- ------------------------------------------------------------------- stock

function Post.stockOf(S, findId)
	local index, found = Tables.binarySearch(S.store, #S.store, "id", findId)
	if not found then
		return 0
	end
	return S.store[index].qty
end

-- Returns (addedQty, message). Refuses rather than truncating silently when
-- the store is already at MAX_STORE distinct entries.
function Post.addStock(S, findId, qty)
	if qty <= 0 then
		return 0, "quantity must be positive"
	end
	local store = S.store
	local n = #store
	local index, found = Tables.binarySearch(store, n, "id", findId)
	if found then
		local entry = store[index]
		local room = MAX_STACK - entry.qty
		local added = qty
		if added > room then
			added = room
		end
		entry.qty = entry.qty + added
		Almanac.record(S.almanac, findId)
		return added, nil
	end
	if n >= MAX_STORE then
		return 0, "store is full"
	end
	local added = qty
	if added > MAX_STACK then
		added = MAX_STACK
	end
	table.insert(store, index, { id = findId, qty = added })
	-- Holding one is what puts a find in the Almanac.
	Almanac.record(S.almanac, findId)
	return added, nil
end

-- Returns the quantity actually removed (never more than is present).
function Post.removeStock(S, findId, qty)
	if qty <= 0 then
		return 0
	end
	local store = S.store
	local index, found = Tables.binarySearch(store, #store, "id", findId)
	if not found then
		return 0
	end
	local entry = store[index]
	local taken = qty
	if taken > entry.qty then
		taken = entry.qty
	end
	entry.qty = entry.qty - taken
	if entry.qty == 0 then
		table.remove(store, index)
		-- A shelf pointing at a find with no stock is not an error; it simply
		-- shows as empty. Leaving it in place preserves the player's layout.
	end
	return taken
end

function Post.totalStock(S)
	local total = 0
	local store = S.store
	for i = 1, #store do
		total = total + store[i].qty
	end
	return total
end

function Post.distinctStock(S)
	return #S.store
end

-- ------------------------------------------------------------------ shelves

function Post.maxShelves(tier)
	local n = tier * 6
	if n > MAX_SHELVES then
		return MAX_SHELVES
	end
	return n
end

-- Place `findId` at `slot` for `price`. Slots are dense 1..maxShelves.
function Post.setShelf(S, slot, findId, price)
	local limit = Post.maxShelves(S.tier)
	if slot < 1 or slot > limit then
		return false, string.format("slot %d is outside 1..%d at tier %d", slot, limit, S.tier)
	end
	if Post.findRow(findId) == nil then
		return false, "unknown find id " .. tostring(findId)
	end
	if price < EconomyConfig.MIN_PRICE or price > EconomyConfig.MAX_PRICE then
		return false, "price out of range"
	end
	if price ~= floor(price) then
		return false, "price must be an integer"
	end
	S.shelves[slot] = { id = findId, price = price }
	return true
end

function Post.clearShelf(S, slot)
	if S.shelves[slot] == nil then
		return false
	end
	-- Shelves are a dense array so the codec can write a count; removing from
	-- the middle compacts, which is also what the UI does.
	table.remove(S.shelves, slot)
	return true
end

function Post.shelfCount(S)
	return #S.shelves
end

-- Total coin value currently on display, used by the passive income cap.
function Post.shelvedValue(S)
	local total = 0
	for i = 1, #S.shelves do
		local shelf = S.shelves[i]
		local qty = Post.stockOf(S, shelf.id)
		if qty > 0 then
			total = total + shelf.price * qty
		end
	end
	return total
end

-- -------------------------------------------------------------------- tier

function Post.maxOrderRules(tier)
	local caps = OrdersConfig.MAX_RULES_BY_TIER
	local n = caps[tier]
	if n == nil then
		return caps[1]
	end
	return n
end

function Post.passiveCap(tier)
	local caps = EconomyConfig.PASSIVE_CAP_BY_TIER
	local n = caps[tier]
	if n == nil then
		return caps[1]
	end
	return n
end

-- ------------------------------------------------------------ visitor ring

-- Most-recent-first, bounded at VISITOR_RING_SIZE. Used by the Orders
-- condition `visits >= N` ("a returning face") and by the Ledger's
-- "you have seen this one before" flag.
function Post.recordVisit(S, owner, epoch)
	local ring = S.ring
	table.insert(ring, 1, { owner = owner, epoch = epoch })
	for i = #ring, RING + 1, -1 do
		ring[i] = nil
	end
	return #ring
end

function Post.visitCount(S, owner)
	local ring = S.ring
	local n = 0
	for i = 1, #ring do
		if ring[i].owner == owner then
			n = n + 1
		end
	end
	return n
end

-- --------------------------------------------------------------- invariants

-- The structural half of doc 04 section 9. Returns (true) or (false, message).
-- Cheap enough to run in Studio after every resolve; the harness runs it after
-- every single epoch.
function Post.checkInvariants(S)
	if S.coin < 0 then
		return false, "coin is negative"
	end
	if S.coin > GameConfig.MAX_COIN then
		return false, "coin exceeds MAX_COIN"
	end
	if S.tier < 1 or S.tier > GameConfig.MAX_TIER then
		return false, "tier out of range"
	end
	local store = S.store
	local previous = -1
	for i = 1, #store do
		local entry = store[i]
		if entry.qty <= 0 then
			return false, string.format("store entry %d (find %d) has non-positive quantity", i, entry.id)
		end
		if entry.qty > MAX_STACK then
			return false, string.format("store entry %d exceeds the maximum stack", i)
		end
		if entry.id <= previous then
			return false, "store is not strictly ascending by find id"
		end
		previous = entry.id
	end
	if #store > MAX_STORE then
		return false, "store has too many distinct entries"
	end
	local limit = Post.maxShelves(S.tier)
	if #S.shelves > limit then
		return false, string.format("%d shelves at tier %d, limit %d", #S.shelves, S.tier, limit)
	end
	for i = 1, #S.shelves do
		local shelf = S.shelves[i]
		if shelf == nil then
			return false, "shelves array has a hole at " .. i
		end
		if Post.findRow(shelf.id) == nil then
			return false, "shelf " .. i .. " references unknown find " .. tostring(shelf.id)
		end
		if shelf.price < EconomyConfig.MIN_PRICE then
			return false, "shelf " .. i .. " is priced below the minimum"
		end
	end
	for i = 1, EconomyConfig.CURRENT_COUNT do
		local value = S.standing[i]
		if value == nil or value < 0 or value > EconomyConfig.STANDING_MAX then
			return false, "standing[" .. i .. "] is out of range"
		end
	end
	if not Almanac.isValid(S.almanac) then
		return false, "almanac is not a 32-byte bitset"
	end
	if not Almanac.isValid(S.sold) then
		return false, "sold bitset is not a 32-byte bitset"
	end
	if #S.ring > RING then
		return false, "visitor ring is over capacity"
	end
	return true
end

return Post
