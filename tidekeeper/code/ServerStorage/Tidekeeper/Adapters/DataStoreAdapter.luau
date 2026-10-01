--!nonstrict
-- ServerStorage/Tidekeeper/Adapters/DataStoreAdapter (ModuleScript)
--
-- Layer L1. One of the four modules in the game allowed to yield, and one of
-- the four allowed to touch a Roblox data service. Everything above it is
-- synchronous and pure; everything about failure, retry, budget and locking
-- lives here so that the services never have to reason about any of it.
--
-- Implements doc 05: the key map (section 2), the session lock (section 7),
-- the retry policy (section 8) and the reapers (section 9).
--
-- THE RULES THIS FILE EXISTS TO ENFORCE
-- -------------------------------------
--   * A read that fails after every retry returns `false`. It NEVER returns a
--     fresh empty post. In a game whose entire content is history, silently
--     handing a player a blank slate is worse than refusing the session.
--   * A write whose session token has gone stale is ABANDONED, not forced.
--     Losing a session is survivable; overwriting a newer save is not.
--   * `UpdateAsync` is the retry primitive. Never get-then-set.
--   * Every call is budget-checked first, so a burst defers instead of
--     dropping.
--
-- Rate limits, verified 2026-10-01 (doc 10 section 6.2): the per-server
-- default is `60 + numPlayers * 40` requests/minute for standard read, write
-- and remove, and the per-experience ceiling -- which is shared with Open
-- Cloud -- is `300 + CCU * 40` read and `300 + CCU * 20` write. A 30-player
-- server therefore has 1 260 writes/minute against a design budget of five
-- requests per session.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local GameConfig = require(Tidekeeper.Config.GameConfig)
local Hash = require(Tidekeeper.Lib.Hash)
local RNG = require(Tidekeeper.Lib.RNG)

local DataStoreAdapter = {}
DataStoreAdapter.__index = DataStoreAdapter

-- doc 05 section 8. Attempt 1 is immediate; the rest are exponential with
-- jitter, as the creator docs recommend for DataUpdateConflict.
local BACKOFF = { 0, 0.5, 1.5, 4, 9 }
local MAX_ATTEMPTS = #BACKOFF
local JITTER_PER_MILLE = 250

-- Below this many remaining requests of a type, defer rather than spend.
local BUDGET_FLOOR = 8
local BUDGET_WAIT = 0.5
local BUDGET_MAX_DEFERRALS = 6

-- doc 05 section 7.
local LOCK_TTL = 90
local LOCK_REFRESH = 30
local LOCK_WAIT = 6
local LOCK_POLL = 1

local STORE_POST = "Post"
local STORE_LEDGER = "Ledger"
local STORE_POOL = "DrifterPool"
local STORE_RECEIPTS = "Receipts"
local STORE_SHOWCASE = "Showcase"
local STORE_META = "Meta"

DataStoreAdapter.STORE_POST = STORE_POST
DataStoreAdapter.STORE_LEDGER = STORE_LEDGER
DataStoreAdapter.STORE_POOL = STORE_POOL
DataStoreAdapter.STORE_RECEIPTS = STORE_RECEIPTS
DataStoreAdapter.STORE_SHOWCASE = STORE_SHOWCASE
DataStoreAdapter.STORE_META = STORE_META

DataStoreAdapter.RECEIPT_SHARDS = 256
DataStoreAdapter.POOL_SHARDS = 64
DataStoreAdapter.LEDGER_PAGE_ENTRIES = 64

-- doc 05 section 9: one pool shard per slow tick, never more.
DataStoreAdapter.REAP_AGE_EPOCHS = 28

local function newStats()
	return {
		read = 0,
		write = 0,
		remove = 0,
		list = 0,
		retries = 0,
		conflicts = 0,
		throttles = 0,
		deferrals = 0,
		failures = 0,
		abandonedWrites = 0,
		recoveriesApplied = 0,
		recoveriesSuperseded = 0,
		unlockedSessions = 0,
		bytesWritten = 0,
		bytesRead = 0,
	}
end

function DataStoreAdapter.new(options)
	local opts = options or {}
	local self = setmetatable({}, DataStoreAdapter)
	self.service = opts.service or game:GetService("DataStoreService")
	self.memory = opts.memory
	-- Yielding is injected so the session harness can advance a virtual clock
	-- instead of burning wall time. Production passes nothing and gets task.wait.
	self.waiter = opts.waiter or task.wait
	self.clock = opts.clock or os.time
	self.logger = opts.logger
	self.enforceBudget = opts.enforceBudget ~= false
	-- Jitter must be deterministic: math.random is a global unseedable stream
	-- shared with every other script in the place.
	self.rng = RNG.new(opts.seed or 20261001)
	self.stats = newStats()
	self.stores = {}
	self.locks = {}
	return self
end

function DataStoreAdapter:log(message)
	if self.logger ~= nil then
		self.logger("DataStoreAdapter", message)
	end
end

function DataStoreAdapter:store(name)
	local cached = self.stores[name]
	if cached ~= nil then
		return cached
	end
	local ok, store = pcall(function()
		return self.service:GetDataStore(name)
	end)
	if not ok then
		return nil, tostring(store)
	end
	self.stores[name] = store
	return store
end

-- ----------------------------------------------------------------- budget

function DataStoreAdapter:budgetFor(requestType)
	local ok, value = pcall(function()
		return self.service:GetRequestBudgetForRequestType(requestType)
	end)
	if not ok then
		return 0
	end
	return value
end

-- Returns true when there is room to spend, false when the caller should give
-- up. Defers up to BUDGET_MAX_DEFERRALS times, which at 0.5 s is three
-- seconds -- long enough to ride out a burst, short enough not to hold a
-- BindToClose hostage.
function DataStoreAdapter:awaitBudget(requestType)
	if not self.enforceBudget then
		return true
	end
	for _ = 1, BUDGET_MAX_DEFERRALS do
		if self:budgetFor(requestType) >= BUDGET_FLOOR then
			return true
		end
		self.stats.deferrals = self.stats.deferrals + 1
		self.waiter(BUDGET_WAIT)
	end
	return self:budgetFor(requestType) > 0
end

-- ------------------------------------------------------------ retry core

local function classify(message)
	local text = string.lower(tostring(message))
	if string.find(text, "conflict", 1, true) ~= nil then
		return "conflict"
	end
	if string.find(text, "throttl", 1, true) ~= nil then
		return "throttle"
	end
	if string.find(text, "quota", 1, true) ~= nil or string.find(text, "overlimit", 1, true) ~= nil then
		return "quota"
	end
	return "error"
end

function DataStoreAdapter:sleepFor(attempt)
	local base = BACKOFF[attempt]
	if base <= 0 then
		return
	end
	local jitter = base * (self.rng:range(0, JITTER_PER_MILLE) / 1000)
	self.waiter(base + jitter)
end

-- The single retry loop. `fn` must be idempotent-by-construction; every
-- caller below uses UpdateAsync, which is.
--
-- Returns (true, value) or (false, message, kind).
function DataStoreAdapter:attempt(kindCounter, fn)
	local lastMessage = "no attempt was made"
	local lastKind = "error"
	for attempt = 1, MAX_ATTEMPTS do
		if attempt > 1 then
			self.stats.retries = self.stats.retries + 1
			self:sleepFor(attempt)
		end
		local ok, result = pcall(fn)
		if ok then
			self.stats[kindCounter] = self.stats[kindCounter] + 1
			return true, result
		end
		lastMessage = tostring(result)
		lastKind = classify(lastMessage)
		if lastKind == "conflict" then
			self.stats.conflicts = self.stats.conflicts + 1
		elseif lastKind == "throttle" then
			self.stats.throttles = self.stats.throttles + 1
		end
		if lastKind == "quota" then
			-- A quota error does not get better by trying again in four
			-- seconds. Fail fast and let the caller degrade.
			break
		end
	end
	self.stats.failures = self.stats.failures + 1
	self:log("giving up after retries: " .. lastMessage)
	return false, lastMessage, lastKind
end

-- ------------------------------------------------------------ the lock

-- doc 05 section 7. The lock itself lives in MemoryStore because it must be
-- visible across servers within seconds and must expire on its own if a
-- server dies; the adapter owns the protocol because the protocol is about
-- who may write to DataStore.
function DataStoreAdapter:acquireLock(userId)
	if self.memory == nil then
		-- No MemoryStore: degrade to unlocked rather than refuse to play
		-- (doc 01 section 8). Recorded so the BudgetMeter can show it.
		return true, 0, "unlocked"
	end
	local token = Hash.mix(userId, math.floor(self.clock()), self.rng:nextUInt())
	local ok, held = self.memory:tryLock(userId, token, LOCK_TTL)
	if ok then
		self.locks[userId] = token
		return true, token
	end
	-- Someone else holds it. Wait out a teleport hop, then retry once.
	local waited = 0
	while waited < LOCK_WAIT do
		self.waiter(LOCK_POLL)
		waited = waited + LOCK_POLL
		ok, held = self.memory:tryLock(userId, token, LOCK_TTL)
		if ok then
			self.locks[userId] = token
			return true, token
		end
	end
	-- MemoryStore itself is down (throttled, or over the universe-wide
	-- quota). doc 01 section 8 is explicit that the lock is an OPTIMISATION
	-- over a rare event, not a prerequisite for playing: if the locking
	-- service is unavailable, run unlocked and record it, rather than
	-- refusing to let anybody into the game.
	if self.memory.degraded then
		self.stats.unlockedSessions = self.stats.unlockedSessions + 1
		self:log("MemoryStore is degraded; proceeding without a session lock for " .. tostring(userId))
		return true, 0, "unlocked"
	end
	return false, nil, "post is still closing up (held by " .. tostring(held) .. ")"
end

function DataStoreAdapter:refreshLock(userId)
	if self.memory == nil then
		return true
	end
	local token = self.locks[userId]
	if token == nil then
		return false, "no lock held"
	end
	return self.memory:refreshLock(userId, token, LOCK_TTL)
end

function DataStoreAdapter:releaseLock(userId)
	local token = self.locks[userId]
	self.locks[userId] = nil
	if self.memory == nil or token == nil then
		return true
	end
	return self.memory:releaseLock(userId, token)
end

function DataStoreAdapter:holdsLock(userId)
	if self.memory == nil or self.memory.degraded then
		return true
	end
	local token = self.locks[userId]
	if token == nil then
		return false
	end
	-- Answered from the token this adapter issued, not from a read. See
	-- MemoryAdapter:believesHeld for why that is safe, and why the read it
	-- replaces was costing a MemoryStore request on every single save.
	return self.memory:believesHeld(userId, token)
end

DataStoreAdapter.LOCK_TTL = LOCK_TTL
DataStoreAdapter.LOCK_REFRESH = LOCK_REFRESH

-- ------------------------------------------------------------- the post

function DataStoreAdapter:postKey(userId)
	return "p:" .. tostring(userId)
end

-- Returns (true, blobOrNil) or (false, message). `nil` with a `true` means
-- "this player has never played", which is a completely different thing from
-- "the read failed", and the caller must be able to tell them apart.
function DataStoreAdapter:loadPost(userId)
	local store, err = self:store(STORE_POST)
	if store == nil then
		return false, err
	end
	if not self:awaitBudget(Enum.DataStoreRequestType.GetAsync) then
		return false, "no read budget"
	end
	local key = self:postKey(userId)
	local ok, value = self:attempt("read", function()
		return store:GetAsync(key)
	end)
	if not ok then
		return false, value
	end
	if type(value) == "string" then
		self.stats.bytesRead = self.stats.bytesRead + #value
	end
	return true, value
end

-- `expectToken` is the session token from acquireLock. If the lock has moved
-- on, the write is abandoned and the payload goes to the recovery queue.
function DataStoreAdapter:savePost(userId, blob, expectToken)
	if expectToken ~= nil and not self:holdsLock(userId) then
		self.stats.abandonedWrites = self.stats.abandonedWrites + 1
		self:log("abandoning save for " .. tostring(userId) .. ": lock token is stale")
		if self.memory ~= nil then
			self.memory:pushRecovery(userId, blob)
		end
		return false, "stale session lock"
	end
	if #blob > GameConfig.MAX_POST_BLOB_BYTES * 2 then
		return false, "post blob is " .. tostring(#blob) .. " bytes, which cannot be right"
	end
	local store, err = self:store(STORE_POST)
	if store == nil then
		return false, err
	end
	if not self:awaitBudget(Enum.DataStoreRequestType.UpdateAsync) then
		return false, "no write budget"
	end
	local key = self:postKey(userId)
	local ok, message = self:attempt("write", function()
		return store:UpdateAsync(key, function()
			return blob
		end)
	end)
	if not ok then
		if self.memory ~= nil then
			self.memory:pushRecovery(userId, blob)
		end
		return false, message
	end
	self.stats.bytesWritten = self.stats.bytesWritten + #blob
	return true
end

-- --------------------------------------------------------- drifter pool

-- Write back a blob that an earlier save abandoned (see `savePost`: a stale
-- lock or an exhausted retry budget pushes the payload onto the recovery
-- queue). This is the ONLY writer that can run while another server owns the
-- player, so it is the only one that has to defend against going backwards:
-- by the time we retry, the server that stole the lock may already have
-- written something newer, and blindly restoring would *cause* the data loss
-- this queue exists to prevent.
--
-- `isNewer(oldBlob) -> boolean` is supplied by the caller, which owns the
-- codec; the adapter stays blob-level. Returning nil from an UpdateAsync
-- transform aborts the write without consuming a conflict, which is exactly
-- the semantics wanted when the stored value already wins.
--
-- Returns (ok, applied, reason). `ok=true, applied=false` means the queue
-- entry was resolved and should be acked -- the blob is simply obsolete.
function DataStoreAdapter:restorePost(userId, blob, isNewer)
	if type(blob) ~= "string" or #blob == 0 then
		return false, false, "empty blob"
	end
	if #blob > GameConfig.MAX_POST_BLOB_BYTES * 2 then
		return false, false, "blob too large"
	end
	local store, err = self:store(STORE_POST)
	if store == nil then
		return false, false, err
	end
	if not self:awaitBudget(Enum.DataStoreRequestType.UpdateAsync) then
		return false, false, "no write budget"
	end
	local key = self:postKey(userId)
	local applied = false
	local ok, message = self:attempt("write", function()
		return store:UpdateAsync(key, function(old)
			if old ~= nil and isNewer ~= nil and not isNewer(old) then
				applied = false
				return nil
			end
			applied = true
			return blob
		end)
	end)
	if not ok then
		return false, false, message
	end
	if applied then
		self.stats.recoveriesApplied = self.stats.recoveriesApplied + 1
		self.stats.bytesWritten = self.stats.bytesWritten + #blob
		self:log("restored an abandoned save for " .. tostring(userId))
		return true, true, "restored"
	end
	self.stats.recoveriesSuperseded = self.stats.recoveriesSuperseded + 1
	return true, false, "superseded"
end

function DataStoreAdapter:poolKey(current, epoch, shard)
	return "c" .. tostring(current) .. ":e" .. tostring(epoch) .. ":s" .. tostring(shard)
end

function DataStoreAdapter:shardFor(drifterId)
	return Hash.reduce(Hash.mix(drifterId, 0x9E37), DataStoreAdapter.POOL_SHARDS)
end

-- Append one packed Drifter to a warm shard. One UpdateAsync (doc 03 section
-- 6.3). The shard is an array of base64 strings, because DataStore values are
-- JSON and a byte array of 13 000 numbers is not a sensible thing to store.
function DataStoreAdapter:publishDrifter(current, epoch, shard, encoded)
	local store, err = self:store(STORE_POOL)
	if store == nil then
		return false, err
	end
	if not self:awaitBudget(Enum.DataStoreRequestType.UpdateAsync) then
		return false, "no write budget"
	end
	local key = self:poolKey(current, epoch, shard)
	local cap = GameConfig.MAX_RESIDENT_DRIFTERS * 9
	local ok, message = self:attempt("write", function()
		return store:UpdateAsync(key, function(old)
			local list = old or {}
			if #list >= cap then
				-- A full shard drops the OLDEST, not the newest: a shard that
				-- refuses new arrivals silently freezes a whole current.
				table.remove(list, 1)
			end
			list[#list + 1] = encoded
			return list
		end)
	end)
	if not ok then
		return false, message
	end
	self.stats.bytesWritten = self.stats.bytesWritten + #encoded
	return true
end

-- Take up to `n` Drifters from the tail of one warm shard, atomically. This
-- is THE at-most-once primitive of the whole exchange (doc 03 section 6.2):
-- the removal and the read are one UpdateAsync, so two servers cannot claim
-- the same record and a failed write means nothing was taken.
function DataStoreAdapter:claimDrifters(current, epoch, shard, n)
	local store, err = self:store(STORE_POOL)
	if store == nil then
		return false, err
	end
	if not self:awaitBudget(Enum.DataStoreRequestType.UpdateAsync) then
		return false, "no write budget"
	end
	local key = self:poolKey(current, epoch, shard)
	local taken = {}
	local ok, message = self:attempt("write", function()
		-- The transform can run more than once under contention, so it must
		-- rebuild `taken` from scratch every time rather than accumulate.
		for i = #taken, 1, -1 do
			taken[i] = nil
		end
		return store:UpdateAsync(key, function(old)
			if old == nil or #old == 0 then
				return nil
			end
			local list = old
			local count = 0
			while count < n and #list > 0 do
				count = count + 1
				taken[count] = list[#list]
				list[#list] = nil
			end
			-- RETURNING NIL HERE WOULD ABORT THE WRITE.
			--
			-- It used to say `if #list == 0 then return nil end`, reading as
			-- "the shard is empty now, so store nothing". What it actually
			-- did was cancel the whole transform: the records were copied
			-- into `taken` and handed to a resolve, and ALSO left in the
			-- shard for the next claimant. The session test found 27 real
			-- Drifters delivered twice over a simulated month.
			--
			-- An emptied shard is written back as an empty list and removed
			-- later by the reaper. One wasted key beats duplicated history.
			return list
		end)
	end)
	if not ok then
		return false, message
	end
	return true, taken
end

function DataStoreAdapter:reapPoolShard(current, epoch, shard)
	local store, err = self:store(STORE_POOL)
	if store == nil then
		return false, err
	end
	if not self:awaitBudget(Enum.DataStoreRequestType.RemoveAsync) then
		return false, "no remove budget"
	end
	local key = self:poolKey(current, epoch, shard)
	return self:attempt("remove", function()
		return store:RemoveAsync(key)
	end)
end

-- ------------------------------------------------------------- receipts

function DataStoreAdapter:receiptKey(ownerId)
	return "r:" .. tostring(ownerId % DataStoreAdapter.RECEIPT_SHARDS)
end

-- Receipts are appended to the RECIPIENT's shard, keyed by ownerId % 256, so
-- delivery costs one UpdateAsync amortised over everyone in that shard rather
-- than one write per recipient.
function DataStoreAdapter:appendReceipts(ownerId, encodedList)
	if #encodedList == 0 then
		return true
	end
	local store, err = self:store(STORE_RECEIPTS)
	if store == nil then
		return false, err
	end
	if not self:awaitBudget(Enum.DataStoreRequestType.UpdateAsync) then
		return false, "no write budget"
	end
	local key = self:receiptKey(ownerId)
	local field = tostring(ownerId)
	return self:attempt("write", function()
		return store:UpdateAsync(key, function(old)
			local shard = old or {}
			local mine = shard[field] or {}
			for i = 1, #encodedList do
				mine[#mine + 1] = encodedList[i]
			end
			-- An unbounded inbox is a way to make a post fail to save.
			while #mine > 256 do
				table.remove(mine, 1)
			end
			shard[field] = mine
			return shard
		end)
	end)
end

-- Read and clear this owner's own entries. Returns (true, list).
function DataStoreAdapter:drainReceipts(ownerId)
	local store, err = self:store(STORE_RECEIPTS)
	if store == nil then
		return false, err
	end
	if not self:awaitBudget(Enum.DataStoreRequestType.UpdateAsync) then
		return false, "no write budget"
	end
	local key = self:receiptKey(ownerId)
	local field = tostring(ownerId)
	local drained = {}
	local ok, message = self:attempt("write", function()
		for i = #drained, 1, -1 do
			drained[i] = nil
		end
		return store:UpdateAsync(key, function(old)
			if old == nil then
				return nil
			end
			local mine = old[field]
			if mine == nil then
				return old
			end
			for i = 1, #mine do
				drained[i] = mine[i]
			end
			old[field] = nil
			return old
		end)
	end)
	if not ok then
		return false, message
	end
	return true, drained
end

-- --------------------------------------------------------------- ledger

function DataStoreAdapter:ledgerKey(userId, page)
	return "l:" .. tostring(userId) .. ":" .. tostring(page)
end

function DataStoreAdapter:saveLedgerPage(userId, page, entries)
	local store, err = self:store(STORE_LEDGER)
	if store == nil then
		return false, err
	end
	if not self:awaitBudget(Enum.DataStoreRequestType.UpdateAsync) then
		return false, "no write budget"
	end
	local key = self:ledgerKey(userId, page)
	return self:attempt("write", function()
		return store:UpdateAsync(key, function()
			return entries
		end)
	end)
end

function DataStoreAdapter:loadLedgerPage(userId, page)
	local store, err = self:store(STORE_LEDGER)
	if store == nil then
		return false, err
	end
	if not self:awaitBudget(Enum.DataStoreRequestType.GetAsync) then
		return false, "no read budget"
	end
	local key = self:ledgerKey(userId, page)
	return self:attempt("read", function()
		return store:GetAsync(key)
	end)
end

-- --------------------------------------------------------- meta/showcase

function DataStoreAdapter:loadMeta()
	local store, err = self:store(STORE_META)
	if store == nil then
		return false, err
	end
	if not self:awaitBudget(Enum.DataStoreRequestType.GetAsync) then
		return false, "no read budget"
	end
	return self:attempt("read", function()
		return store:GetAsync("m:global")
	end)
end

function DataStoreAdapter:bumpShowcase(week, bucket, userId, renown)
	local store, err = self:store(STORE_SHOWCASE)
	if store == nil then
		return false, err
	end
	if not self:awaitBudget(Enum.DataStoreRequestType.UpdateAsync) then
		return false, "no write budget"
	end
	local key = "s:" .. tostring(week) .. ":" .. tostring(bucket)
	local field = tostring(userId)
	return self:attempt("write", function()
		return store:UpdateAsync(key, function(old)
			local board = old or {}
			board[field] = renown
			return board
		end)
	end)
end

function DataStoreAdapter:resetStats()
	self.stats = newStats()
end

function DataStoreAdapter:totalRequests()
	local s = self.stats
	return s.read + s.write + s.remove + s.list
end

return DataStoreAdapter
