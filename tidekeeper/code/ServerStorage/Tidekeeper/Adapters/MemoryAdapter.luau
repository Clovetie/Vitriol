--!nonstrict
-- ServerStorage/Tidekeeper/Adapters/MemoryAdapter (ModuleScript)
--
-- Layer L1. MemoryStore: hash maps for the exchange index and the session
-- locks, one queue for failed-save recovery.
--
-- THE NUMBER THIS FILE IS SHAPED BY
-- ---------------------------------
-- MemoryStore's memory quota is `64 KB + 1.2 KB * [number of users]` and it
-- applies to the WHOLE UNIVERSE, not to a server (doc 05 section 1, re-verified
-- 2026-10-01). At 1 000 CCU that is about 1.2 MB in total. Roblox also applies
-- an eight-day traceback before the quota falls again after users leave, which
-- helps on the way down and not at all on the way up.
--
-- So: MemoryStore is a COORDINATION CACHE, never storage. This adapter holds
-- exactly two kinds of thing --
--
--   xidx  c{current}:e{epoch}  -> a 64-bit shard-fill bitmap, ~26 bytes
--   lock  p:{userId}           -> a session token, ~24 bytes, TTL 90 s
--
-- -- plus a recovery queue that is empty in the normal case. Everything else
-- is in DataStore.
--
-- The request quota is `1000 + 120 * CCU` units per minute universe-wide
-- (corrected 2026-10-01; it was documented as `100 * CCU` when doc 10 was
-- written). `HashMap:UpdateAsync` costs at least two units, which is why the
-- index write at logout is a single UpdateAsync on a single key rather than a
-- read-modify-write pair.
--
-- DEGRADES, NEVER BLOCKS. Every method returns a falsy first value on
-- failure and the caller carries on with a staler exchange. doc 01 section 8:
-- "The game still works, drifters are staler. Never block the session."

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local EconomyConfig = require(Tidekeeper.Config.EconomyConfig)

local MemoryAdapter = {}
MemoryAdapter.__index = MemoryAdapter

local MAP_INDEX = "xidx"
local MAP_LOCK = "lock"
local QUEUE_RECOVERY = "recov"

MemoryAdapter.MAP_INDEX = MAP_INDEX
MemoryAdapter.MAP_LOCK = MAP_LOCK
MemoryAdapter.QUEUE_RECOVERY = QUEUE_RECOVERY

-- doc 05 section 2: the hot index lives for two epochs and no longer.
local INDEX_TTL = 44714
local RECOVERY_TTL = 86400

-- Per-item accounting overhead. The docs state the sorted-map size limit is
-- measured "including keys"; nothing is said about hash maps, so we charge
-- for keys there too (OD9, doc 10 section 6.2). 16 bytes is a guess at the
-- structural overhead and it is deliberately pessimistic.
local ITEM_OVERHEAD = 16

local function newStats()
	return {
		get = 0,
		set = 0,
		update = 0,
		remove = 0,
		queueAdd = 0,
		queueRead = 0,
		units = 0,
		failures = 0,
		quotaRejections = 0,
		degradedSince = 0,
	}
end

function MemoryAdapter.new(options)
	local opts = options or {}
	local self = setmetatable({}, MemoryAdapter)
	self.service = opts.service or game:GetService("MemoryStoreService")
	self.waiter = opts.waiter or task.wait
	self.clock = opts.clock or os.time
	self.logger = opts.logger
	self.stats = newStats()
	self.degraded = false
	self.maps = {}
	-- Tokens this adapter issued, so a release can tell "mine" from
	-- "somebody else's" without spending a read.
	self.heldTokens = {}
	self.queue = nil
	-- Local mirror of what we believe we are holding, used by BudgetMeter.
	-- It is an estimate of OUR share of a universe-wide number, and the
	-- reports say so rather than pretending it is the real figure.
	self.estimatedBytes = 0
	self.items = {}
	return self
end

function MemoryAdapter:log(message)
	if self.logger ~= nil then
		self.logger("MemoryAdapter", message)
	end
end

function MemoryAdapter:hashMap(name)
	local cached = self.maps[name]
	if cached ~= nil then
		return cached
	end
	local ok, map = pcall(function()
		return self.service:GetHashMap(name)
	end)
	if not ok then
		self:degrade("GetHashMap failed: " .. tostring(map))
		return nil
	end
	self.maps[name] = map
	return map
end

function MemoryAdapter:degrade(why)
	if not self.degraded then
		self.degraded = true
		self.stats.degradedSince = self.clock()
		self:log("degrading to DataStore-only: " .. tostring(why))
	end
end

-- Quota accounting is OUR OWN estimate. MemoryStore does not expose usage to
-- a game server; the Observability dashboard does, to a human. Calling this a
-- measurement would be a lie, so it is named an estimate everywhere it
-- appears.
function MemoryAdapter:chargeItem(key, value, remove)
	local size = #tostring(key) + #tostring(value) + ITEM_OVERHEAD
	if remove then
		local held = self.items[key]
		if held ~= nil then
			self.estimatedBytes = self.estimatedBytes - held
			self.items[key] = nil
		end
		return
	end
	local held = self.items[key] or 0
	self.estimatedBytes = self.estimatedBytes + size - held
	self.items[key] = size
end

function MemoryAdapter:quotaFor(userCount)
	return 65536 + 1229 * userCount
end

function MemoryAdapter:requestUnitsPerMinute(ccu)
	return 1000 + 120 * ccu
end

local function note(self, kind, units)
	self.stats[kind] = self.stats[kind] + 1
	self.stats.units = self.stats.units + units
end

local function fail(self, message)
	self.stats.failures = self.stats.failures + 1
	local text = string.lower(tostring(message))
	if string.find(text, "memory", 1, true) ~= nil or string.find(text, "quota", 1, true) ~= nil or string.find(text, "overlimit", 1, true) ~= nil then
		self.stats.quotaRejections = self.stats.quotaRejections + 1
		self:degrade(message)
	end
	return false, tostring(message)
end

-- --------------------------------------------------------- the hot index

function MemoryAdapter:indexKey(current, epoch)
	return "c" .. tostring(current) .. ":e" .. tostring(epoch)
end

-- The index records WHICH SHARDS ARE NON-EMPTY, as a pair of 32-bit words
-- covering 64 shards. 26 bytes per entry, 64 shards * 5 currents * 2 live
-- epochs = 640 entries ~= 17 KB, which fits the quota at any CCU (doc 03
-- section 6.2).
function MemoryAdapter:markShard(current, epoch, shard)
	local map = self:hashMap(MAP_INDEX)
	if map == nil then
		return false, "no hash map"
	end
	local key = self:indexKey(current, epoch)
	local word = 1
	local bit = shard
	if shard >= 32 then
		word = 2
		bit = shard - 32
	end
	local mask = bit32.lshift(1, bit)
	local ok, err = pcall(function()
		map:UpdateAsync(key, function(old)
			local lo = 0
			local hi = 0
			if type(old) == "table" then
				lo = old[1] or 0
				hi = old[2] or 0
			end
			if word == 1 then
				lo = bit32.bor(lo, mask)
			else
				hi = bit32.bor(hi, mask)
			end
			return { lo, hi }
		end, INDEX_TTL)
	end)
	if not ok then
		return fail(self, err)
	end
	note(self, "update", 2)
	self:chargeItem(key, "0000000000000000", false)
	return true
end

-- Returns (true, shardList) where shardList is ascending. An empty list is a
-- legitimate answer and means "nobody published into this epoch".
function MemoryAdapter:shardsFor(current, epoch)
	local map = self:hashMap(MAP_INDEX)
	if map == nil then
		return false, "no hash map"
	end
	local key = self:indexKey(current, epoch)
	local ok, value = pcall(function()
		return map:GetAsync(key)
	end)
	if not ok then
		return fail(self, value)
	end
	note(self, "get", 1)
	local out = {}
	if type(value) ~= "table" then
		return true, out
	end
	local lo = value[1] or 0
	local hi = value[2] or 0
	local count = 0
	for i = 0, 31 do
		if bit32.band(bit32.rshift(lo, i), 1) == 1 then
			count = count + 1
			out[count] = i
		end
	end
	for i = 0, 31 do
		if bit32.band(bit32.rshift(hi, i), 1) == 1 then
			count = count + 1
			out[count] = i + 32
		end
	end
	return true, out
end

function MemoryAdapter:clearIndex(current, epoch)
	local map = self:hashMap(MAP_INDEX)
	if map == nil then
		return false
	end
	local key = self:indexKey(current, epoch)
	local ok, err = pcall(function()
		map:RemoveAsync(key)
	end)
	if not ok then
		return fail(self, err)
	end
	note(self, "remove", 1)
	self:chargeItem(key, "", true)
	return true
end

-- ------------------------------------------------------------- the lock

function MemoryAdapter:lockKey(userId)
	return "p:" .. tostring(userId)
end

-- Returns (true) when we took it, or (false, holderToken) when someone else
-- has it. The transform is the whole protocol: acquiring and reading in one
-- atomic step is the only version of this that is correct under a rejoin
-- race.
function MemoryAdapter:tryLock(userId, token, ttl)
	local map = self:hashMap(MAP_LOCK)
	if map == nil then
		-- No lock service means no lock. Say so; the caller decides.
		return true, nil
	end
	local key = self:lockKey(userId)
	local holder = nil
	local ok, err = pcall(function()
		map:UpdateAsync(key, function(old)
			if old ~= nil and old ~= token then
				holder = old
				return nil
			end
			holder = token
			return token
		end, ttl)
	end)
	if not ok then
		fail(self, err)
		return false, "error"
	end
	note(self, "update", 2)
	if holder ~= token then
		return false, holder
	end
	self.heldTokens[key] = token
	self:chargeItem(key, tostring(token), false)
	return true, token
end

-- A one-winner-per-name lease, for work that must happen but must not happen
-- on every server at once.
--
-- The pool reaper is the case this exists for (OD21): 5 Currents x 64 shards
-- of expired pool keys need deleting once per tide epoch, and twenty servers
-- each deleting all 320 of them is twenty times the request budget for the
-- same result. One server takes the lease for an epoch and does the work;
-- the rest skip it and cost nothing.
--
-- Same atomic transform as `tryLock`, and the same honest degradation: if
-- MemoryStore is unavailable this returns false, so NOBODY reaps. That is
-- the right way round -- a missed reap is growth we can see in the metrics,
-- while twenty servers reaping blind is a quota fire during an outage.
function MemoryAdapter:tryLease(name, token, ttl)
	local map = self:hashMap(MAP_LOCK)
	if map == nil then
		return false, nil
	end
	local key = "lease:" .. tostring(name)
	local holder = nil
	local ok, err = pcall(function()
		map:UpdateAsync(key, function(old)
			if old ~= nil and old ~= token then
				holder = old
				return nil
			end
			holder = token
			return token
		end, ttl)
	end)
	if not ok then
		fail(self, err)
		return false, "error"
	end
	note(self, "update", 2)
	if holder ~= token then
		return false, holder
	end
	self:chargeItem(key, tostring(token), false)
	return true, token
end

function MemoryAdapter:refreshLock(userId, token, ttl)
	local map = self:hashMap(MAP_LOCK)
	if map == nil then
		return true
	end
	local key = self:lockKey(userId)
	local kept = false
	local ok, err = pcall(function()
		map:UpdateAsync(key, function(old)
			if old ~= nil and old ~= token then
				return nil
			end
			kept = true
			return token
		end, ttl)
	end)
	if not ok then
		return fail(self, err)
	end
	note(self, "update", 2)
	if kept then
		self.heldTokens[key] = token
	else
		self.heldTokens[key] = nil
	end
	return kept
end

-- RELEASING IS A REMOVE, NOT AN UPDATE.
--
-- This originally did `UpdateAsync(key, function(old) ... return nil end)`,
-- reading as "transform the lock into nothing". It does not work, and the
-- session test is what found it: returning nil from a MemoryStore transform
-- ABORTS the update, it does not delete the key. Every lock was therefore
-- held until its 90-second TTL expired, which meant a player who left and
-- rejoined within a minute and a half was locked out of their own post.
--
-- There is no atomic compare-and-delete in the MemoryStore API, so ownership
-- is checked against the token this adapter issued (`heldTokens`) and the
-- delete is unconditional after that. The residual race -- our lock expired,
-- another server took it, and we then remove theirs -- is bounded by two
-- things: the TTL is refreshed every 45 seconds against a 90-second
-- expiry, and `DataStoreAdapter:savePost` re-checks `holdsLock` before every
-- write, so the worst case is a redundant lock acquisition, never a
-- double write.
function MemoryAdapter:releaseLock(userId, token)
	local map = self:hashMap(MAP_LOCK)
	if map == nil then
		return true
	end
	local key = self:lockKey(userId)
	if self.heldTokens[key] ~= token then
		-- Not ours (or already released). Removing it would take someone
		-- else's lock away.
		return true
	end
	local ok, err = pcall(function()
		map:RemoveAsync(key)
	end)
	self.heldTokens[key] = nil
	if not ok then
		return fail(self, err)
	end
	note(self, "remove", 1)
	self:chargeItem(key, "", true)
	return true
end

-- Do we still believe we hold this lock, WITHOUT spending a request?
--
-- `lockHolder` is a MemoryStore read, and calling it before every save cost
-- one request per session for information we already have: `tryLock` records
-- the token it issued and `refreshLock` -- which runs on the `slow` cadence
-- slot every 45 seconds against a 90-second TTL -- clears it the moment
-- another server takes over. The refresh is the authority; this is the
-- cached answer between refreshes, and it is never staler than one refresh
-- interval.
function MemoryAdapter:believesHeld(userId, token)
	return self.heldTokens[self:lockKey(userId)] == token
end

function MemoryAdapter:lockHolder(userId)
	local map = self:hashMap(MAP_LOCK)
	if map == nil then
		return nil
	end
	local key = self:lockKey(userId)
	local ok, value = pcall(function()
		return map:GetAsync(key)
	end)
	if not ok then
		fail(self, value)
		return nil
	end
	note(self, "get", 1)
	return value
end

-- --------------------------------------------------------- recovery queue

function MemoryAdapter:recoveryQueue()
	if self.queue ~= nil then
		return self.queue
	end
	local ok, q = pcall(function()
		return self.service:GetQueue(QUEUE_RECOVERY, 30)
	end)
	if not ok then
		self:degrade("GetQueue failed: " .. tostring(q))
		return nil
	end
	self.queue = q
	return q
end

-- A save that could not land goes here so the next join can retry it. This
-- is the only place in the game where a post blob sits in MemoryStore, and it
-- is bounded by how many saves are failing -- i.e. it is empty unless
-- something is already wrong.
function MemoryAdapter:pushRecovery(userId, blob)
	local q = self:recoveryQueue()
	if q == nil then
		return false
	end
	local ok, err = pcall(function()
		q:AddAsync({ userId = userId, blob = blob, at = self.clock() }, RECOVERY_TTL, 0)
	end)
	if not ok then
		return fail(self, err)
	end
	note(self, "queueAdd", 1)
	self:chargeItem("recov:" .. tostring(userId), blob, false)
	return true
end

function MemoryAdapter:popRecovery(max)
	local q = self:recoveryQueue()
	if q == nil then
		return false
	end
	local ok, items, id = pcall(function()
		return q:ReadAsync(max or 8, false, 0)
	end)
	if not ok then
		return fail(self, items)
	end
	note(self, "queueRead", 1)
	return true, items, id
end

function MemoryAdapter:ackRecovery(id)
	local q = self:recoveryQueue()
	if q == nil or id == nil then
		return false
	end
	local ok, err = pcall(function()
		q:RemoveAsync(id)
	end)
	if not ok then
		return fail(self, err)
	end
	note(self, "remove", 1)
	return true
end

-- ------------------------------------------------------------- reporting

function MemoryAdapter:report(userCount)
	local quota = self:quotaFor(userCount or 0)
	return {
		estimatedBytes = self.estimatedBytes,
		quotaBytes = quota,
		fractionOfQuota = quota > 0 and (self.estimatedBytes / quota) or 0,
		degraded = self.degraded,
		currents = EconomyConfig.CURRENT_COUNT,
		stats = self.stats,
	}
end

function MemoryAdapter:resetStats()
	self.stats = newStats()
end

return MemoryAdapter
