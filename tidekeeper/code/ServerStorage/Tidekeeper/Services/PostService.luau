--!nonstrict
-- ServerStorage/Tidekeeper/Services/PostService (ModuleScript)
--
-- Layer L3. Owns the resident post table: the in-memory `S` for every player
-- on this server, the session lock that keeps a second server away from it,
-- and the write policy that keeps the whole game inside five DataStore
-- requests per session (doc 05 section 5).
--
-- THE WRITE POLICY, WHICH IS THE WHOLE COST MODEL
-- -----------------------------------------------
-- Naive designs autosave every 30 seconds. At a ten-minute session that is
-- twenty writes per player; at 500 CCU it is over the experience-level write
-- quota (`300 + CCU * 20` per minute, re-verified 2026-10-01) with nothing
-- left for anything else. TIDEKEEPER writes on:
--
--   * a dirty check every SAVE_INTERVAL seconds, and ONLY IF THE STATE
--     ACTUALLY CHANGED (a version counter bumped by the mutators, not a
--     timer);
--   * logout;
--   * BindToClose.
--
-- A player who idles writes ONCE, at logout. A player who plays hard writes
-- perhaps three times. The mean measured in the session harness is what doc
-- 03 section 6.3 quotes, and the harness fails the build if it regresses.
--
-- LOCKING (doc 05 section 4)
-- Roblox will happily run the same user on two servers during a soft shutdown
-- or a teleport. The lock is a MemoryStore hash-map entry holding this
-- server's JobId with a 90-second TTL, refreshed on the `slow` slot. Losing
-- the lock is not an error to retry -- it means ANOTHER SERVER IS AUTHORITY
-- NOW, so this server drops the save and abandons the state rather than
-- overwriting a newer one. Silent data loss beats loud data corruption, and
-- corruption is what a last-writer-wins save produces.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local GameConfig = require(Tidekeeper.Config.GameConfig)
local Hash = require(Tidekeeper.Lib.Hash)
local Tide = require(Tidekeeper.Lib.Tide)
local PostCodec = require(Tidekeeper.Shared.PostCodec)
local Post = require(Tidekeeper.Domain.Post)
local Resolve = require(Tidekeeper.Domain.Resolve)

local PostService = {}
PostService.__index = PostService

local SAVE_INTERVAL = 120
local LOCK_REFRESH_INTERVAL = 45

local function newStats()
	return {
		loaded = 0,
		created = 0,
		saved = 0,
		savesSkippedClean = 0,
		saveFailures = 0,
		lockLost = 0,
		lockDenied = 0,
		resolveRuns = 0,
		resolveChunks = 0,
		invariantFailures = 0,
		recoveriesApplied = 0,
		recoveriesDropped = 0,
		recoveriesDeferred = 0,
	}
end

function PostService.new(options)
	local opts = options or {}
	local self = setmetatable({}, PostService)
	self.data = opts.data
	self.memory = opts.memory
	self.exchange = opts.exchange
	self.ledger = opts.ledger
	self.cadence = opts.cadence
	self.clock = opts.clock or os.time
	self.jobId = opts.jobId or "studio"
	self.logger = opts.logger
	self.resident = {}
	self.order = {}
	self.stats = newStats()
	self.lastLockRefresh = 0
	return self
end

function PostService:log(message)
	if self.logger ~= nil then
		self.logger("PostService", message)
	end
end

function PostService:get(userId)
	local slot = self.resident[userId]
	if slot == nil then
		return nil
	end
	return slot.state
end

function PostService:slotOf(userId)
	return self.resident[userId]
end

-- Mutators call this. The save loop writes only when `version > savedVersion`,
-- which is what turns "autosave" from a timer into a fact about the data.
function PostService:markDirty(userId)
	local slot = self.resident[userId]
	if slot ~= nil then
		slot.version = slot.version + 1
	end
end

-- --------------------------------------------------------------- join

-- Returns (ok, slot | errorMessage). Costs, in the happy path:
--   1 MemoryStore UpdateAsync  (acquire the lock)
--   1 DataStore  GetAsync      (load the post)
--   1 DataStore  UpdateAsync   (drain the receipt inbox)
-- ...and the receipt drain is skipped when the inbox index says it is empty.
function PostService:load(userId, postId)
	if self.resident[userId] ~= nil then
		return true, self.resident[userId]
	end
	-- The lock protocol lives in DataStoreAdapter (it is about who may write
	-- to DataStore) even though the lock itself is a MemoryStore entry.
	local gotLock, _token, why = self.data:acquireLock(userId)
	if not gotLock then
		self.stats.lockDenied = self.stats.lockDenied + 1
		return false, why or "another server holds this post"
	end

	local now = self.clock()
	local ok, encoded = self.data:loadPost(userId)
	if not ok then
		-- A failed READ must never be treated as "no data". Creating a fresh
		-- post here would erase a real one. The player is told to rejoin.
		self.data:releaseLock(userId)
		return false, "could not read your post: " .. tostring(encoded)
	end

	local S
	if encoded == nil then
		local salt = Hash.mix(userId, now, 101)
		S = Post.new(postId or userId, userId, salt, now)
		self.stats.created = self.stats.created + 1
	else
		local decoded, why = PostCodec.decodeFromString(encoded)
		if decoded == nil then
			self.data:releaseLock(userId)
			return false, "your post did not decode: " .. tostring(why)
		end
		S = decoded
		self.stats.loaded = self.stats.loaded + 1
	end

	local slot = {
		userId = userId,
		state = S,
		version = 0,
		savedVersion = 0,
		lastSave = now,
		joinedAt = now,
		lockHeld = true,
		resolving = false,
	}
	self.resident[userId] = slot
	self.order[#self.order + 1] = userId
	return true, slot
end

-- --------------------------------------------------------- chunked resolve

-- Queue the catch-up. Returns the chunk plan so the caller can tell the
-- client how long the Ledger animation needs to be.
--
-- The plan is pure in (resolvedAt, now) and the Drifter-to-chunk assignment
-- is pure in (id, salt, chunkCount), so this is replayable. See
-- CadenceService.planChunks for why that matters more than it sounds.
function PostService:queueResolve(userId, onComplete)
	local slot = self.resident[userId]
	if slot == nil then
		return nil
	end
	local S = slot.state
	local now = self.clock()
	local chunks = self.cadence.planChunks(S.resolvedAt, now)
	if #chunks == 0 then
		if onComplete ~= nil then
			onComplete({}, {})
		end
		return {}
	end

	-- Claim once, for the whole window, then distribute across chunks. One
	-- claim means one set of requests and one at-most-once decision.
	local firstEpoch = chunks[1].from
	local lastEpoch = chunks[#chunks].to
	local want = math.min(GameConfig.MAX_ARRIVALS_PER_EPOCH * #chunks, GameConfig.MAX_RESIDENT_DRIFTERS)
	local inbound = self.exchange:claim(S, firstEpoch, lastEpoch, want, 3)

	local buckets = {}
	for i = 1, #chunks do
		buckets[i] = {}
	end
	for i = 1, #inbound do
		local d = inbound[i]
		local which = self.cadence.chunkForDrifter(d.id, S.salt, #chunks)
		local bucket = buckets[which]
		bucket[#bucket + 1] = d
	end

	local work = Resolve.newWorkspace()
	local allEntries = {}
	local allReceipts = {}
	slot.resolving = true
	self.stats.resolveRuns = self.stats.resolveRuns + 1

	self.cadence:enqueueResolve({
		name = "resolve:" .. tostring(userId),
		chunks = chunks,
		step = function(chunk, index)
			self.stats.resolveChunks = self.stats.resolveChunks + 1
			local S2, entries, receipts = Resolve.run(slot.state, chunk.now, buckets[index], work)
			slot.state = S2
			for i = 1, #entries do
				allEntries[#allEntries + 1] = entries[i]
			end
			for i = 1, #receipts do
				allReceipts[#allReceipts + 1] = receipts[i]
			end
			local ok, why = Post.checkInvariants(S2)
			if not ok then
				self.stats.invariantFailures = self.stats.invariantFailures + 1
				self:log("INVARIANT VIOLATION after chunk " .. index .. " for " .. userId .. ": " .. tostring(why))
			end
			self:markDirty(userId)
		end,
		done = function()
			slot.resolving = false
			if onComplete ~= nil then
				onComplete(allEntries, allReceipts)
			end
		end,
	})
	return chunks
end

-- ---------------------------------------------------------------- save

-- Returns (ok, reason). `force` skips the dirty check (logout, BindToClose).
function PostService:save(userId, force)
	local slot = self.resident[userId]
	if slot == nil then
		return false, "not resident"
	end
	if not slot.lockHeld then
		return false, "lock lost"
	end
	if not force and slot.version == slot.savedVersion then
		self.stats.savesSkippedClean = self.stats.savesSkippedClean + 1
		return true, "clean"
	end
	if slot.resolving then
		-- Never persist a half-resolved window: `resolvedAt` would advance
		-- past epochs whose entries were never written.
		return false, "resolve in flight"
	end
	local encoded, why = PostCodec.encodeToString(slot.state)
	if encoded == nil then
		self.stats.saveFailures = self.stats.saveFailures + 1
		return false, "encode failed: " .. tostring(why)
	end
	if #encoded > GameConfig.MAX_POST_BLOB_BYTES then
		self.stats.saveFailures = self.stats.saveFailures + 1
		self:log("post blob for " .. userId .. " is " .. #encoded .. " bytes, over budget; refusing to save")
		return false, "blob over budget"
	end
	local ok, err = self.data:savePost(userId, encoded, true)
	if not ok then
		if err == "stale session lock" then
			slot.lockHeld = false
			self.stats.lockLost = self.stats.lockLost + 1
			return false, "lock lost"
		end
		self.stats.saveFailures = self.stats.saveFailures + 1
		return false, tostring(err)
	end
	slot.savedVersion = slot.version
	slot.lastSave = self.clock()
	self.stats.saved = self.stats.saved + 1
	return true, "saved"
end

-- Drain the failed-save recovery queue. `savePost` pushes a blob here when a
-- write is abandoned, and until now nothing ever read it back -- the safety
-- net caught the payload and then dropped it on the floor.
--
-- Three outcomes per entry, and the distinction is the whole point:
--   * resident on THIS server -> leave it queued (deferred). We hold the
--     lock and will write something newer ourselves in a moment; restoring
--     underneath a live session would fight our own save.
--   * the stored post is newer -> ack and drop. The lock moved on and the
--     other server already persisted past this blob; the entry is obsolete.
--   * otherwise -> restore it, then ack.
--
-- Undecodable blobs are acked too: a blob we cannot parse can never be
-- restored, and leaving it queued would block the queue forever.
function PostService:sweepRecovery(max)
	if self.memory == nil or self.data == nil then
		return 0
	end
	local ok, items, id = self.memory:popRecovery(max or 4)
	if not ok or items == nil or #items == 0 then
		return 0
	end
	local applied = 0
	local unresolved = 0
	for i = 1, #items do
		local item = items[i]
		local value = item
		-- MemoryStore hands back either the raw value or a wrapper with it.
		if type(value) == "table" and value.blob == nil and value.value ~= nil then
			value = value.value
		end
		local userId = type(value) == "table" and value.userId or nil
		local blob = type(value) == "table" and value.blob or nil
		if userId == nil or type(blob) ~= "string" then
			self.stats.recoveriesDropped = self.stats.recoveriesDropped + 1
		elseif self.resident[userId] ~= nil then
			self.stats.recoveriesDeferred = self.stats.recoveriesDeferred + 1
			unresolved = unresolved + 1
		else
			local candidate = PostCodec.decodeFromString(blob)
			if candidate == nil then
				self.stats.recoveriesDropped = self.stats.recoveriesDropped + 1
			else
				local mine = candidate.resolvedAt or 0
				local wrote, didApply = self.data:restorePost(userId, blob, function(oldBlob)
					local stored = PostCodec.decodeFromString(oldBlob)
					if stored == nil then
						-- Unreadable stored value: our decodable blob wins.
						return true
					end
					return mine > (stored.resolvedAt or 0)
				end)
				if wrote then
					if didApply then
						self.stats.recoveriesApplied = self.stats.recoveriesApplied + 1
						applied = applied + 1
					else
						self.stats.recoveriesDropped = self.stats.recoveriesDropped + 1
					end
				else
					unresolved = unresolved + 1
				end
			end
		end
	end
	-- ReadAsync hands back ONE id covering the whole batch, so the ack is
	-- all-or-nothing: acking now would also delete the entries we chose to
	-- defer or failed to write. If anything is unresolved we ack nothing and
	-- let the 30s invisibility window expire, which re-presents the batch to
	-- the next sweep. Slower, but it cannot lose a blob.
	if unresolved == 0 and id ~= nil then
		self.memory:ackRecovery(id)
	end
	return applied
end

-- Registered on the `slow` slot. Saves at most one post per call: a burst of
-- twenty simultaneous saves is exactly the shape that trips the per-server
-- queue (30 requests deep, then error codes 301-306).
function PostService:tick()
	local now = self.clock()
	if now - self.lastLockRefresh >= LOCK_REFRESH_INTERVAL then
		self.lastLockRefresh = now
		self:refreshLocks()
	end
	local oldest = nil
	local oldestAge = -1
	for i = 1, #self.order do
		local userId = self.order[i]
		local slot = self.resident[userId]
		if slot ~= nil and slot.lockHeld and not slot.resolving and slot.version > slot.savedVersion then
			local age = now - slot.lastSave
			if age >= SAVE_INTERVAL and age > oldestAge then
				oldest = userId
				oldestAge = age
			end
		end
	end
	if oldest ~= nil then
		self:save(oldest, false)
	else
		-- Only when this server owes no save: the recovery queue is empty in
		-- the healthy case, so this costs one MemoryStore read on an idle
		-- tick and nothing at all when the queue is dry.
		self:sweepRecovery(4)
	end
end

function PostService:refreshLocks()
	for i = 1, #self.order do
		local userId = self.order[i]
		local slot = self.resident[userId]
		if slot ~= nil and slot.lockHeld then
			local ok = self.data:refreshLock(userId)
			if not ok then
				slot.lockHeld = false
				self.stats.lockLost = self.stats.lockLost + 1
				self:log("lost the lock on " .. tostring(userId) .. "; this server is no longer authority")
			end
		end
	end
end

-- --------------------------------------------------------------- leave

-- Order matters and it is not obvious: SAVE FIRST, then publish the Drifter,
-- then release the lock. If publishing came first and the save failed, a
-- visitor would exist in the exchange carrying goods the owner's post never
-- recorded selling.
function PostService:unload(userId, now)
	local slot = self.resident[userId]
	if slot == nil then
		return false, "not resident"
	end
	if slot.resolving then
		self.cadence:flushResolves()
	end
	local savedOk, savedWhy = self:save(userId, true)
	if savedOk and self.exchange ~= nil then
		self.exchange:publish(slot.state, now or self.clock())
	end
	if slot.lockHeld then
		self.data:releaseLock(userId)
	end
	self.resident[userId] = nil
	for i = 1, #self.order do
		if self.order[i] == userId then
			table.remove(self.order, i)
			break
		end
	end
	return savedOk, savedWhy
end

function PostService:residentCount()
	return #self.order
end

function PostService:epochNow()
	return Tide.epoch(self.clock())
end

function PostService:resetStats()
	self.stats = newStats()
end

return PostService
