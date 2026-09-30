--!nonstrict
-- ServerStorage/Tidekeeper/Services/PlayerService (ModuleScript)
--
-- Layer L3. The join and leave choreography. Every other service is a
-- capability; this one is the ORDER THOSE CAPABILITIES HAPPEN IN, and the
-- order is where the bugs live.
--
-- THE JOIN SEQUENCE, AND WHY IT IS THIS SEQUENCE
-- ----------------------------------------------
--  1. policy        -- before anything monetised is even described.
--  2. lock + load   -- lock FIRST. Reading a post we are not authority for
--                      and then discovering that at save time means we have
--                      already shown the player a state that will be thrown
--                      away.
--  3. drain inbox   -- receipts must be absorbed BEFORE the resolve, because
--                      a receipt can change standing, and standing changes
--                      who gets served during the catch-up.
--  4. claim + queue -- one claim for the whole window, chunked resolve.
--  5. handshake     -- the client gets the post state and the chunk count so
--                      it can pace the Ledger animation.
--  6. stream        -- entries go out per chunk as they are produced.
--
-- A FAILURE AT ANY STEP BEFORE 5 MUST NOT CREATE A FRESH POST. The single
-- most expensive bug a persistence layer can have is treating "the read
-- failed" as "new player". Every early return here releases the lock and
-- tells the player to rejoin, which is annoying and recoverable, instead of
-- silently deleting a month of play, which is neither.
--
-- THE LEAVE SEQUENCE
--  1. flush any in-flight resolve   (never persist a half-resolved window)
--  2. save                          (authoritative state first)
--  3. publish the Drifter           (only if the save succeeded)
--  4. queue the showcase bump
--  5. consider a notification
--  6. release the lock
--
-- Steps 2 and 3 in that order is a correctness requirement, not tidiness:
-- a Drifter published from a state that was never saved is a visitor
-- carrying goods its owner never recorded parting with.

local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local GameConfig = require(Tidekeeper.Config.GameConfig)
local NotifyConfig = require(Tidekeeper.Config.NotifyConfig)
local NetContract = require(Tidekeeper.Shared.NetContract)
local Tide = require(Tidekeeper.Lib.Tide)
local Post = require(Tidekeeper.Domain.Post)

local PlayerService = {}
PlayerService.__index = PlayerService

local function newStats()
	return {
		joins = 0,
		joinFailures = 0,
		leaves = 0,
		receiptsAbsorbed = 0,
		entriesStreamed = 0,
		rejoinsAsked = 0,
	}
end

function PlayerService.new(options)
	local opts = options or {}
	local self = setmetatable({}, PlayerService)
	self.players = opts.players or Players
	self.posts = opts.posts
	self.exchange = opts.exchange
	self.ledger = opts.ledger
	self.notify = opts.notify
	self.showcase = opts.showcase
	self.policy = opts.policy
	self.remotes = opts.remotes
	self.clock = opts.clock or os.time
	self.logger = opts.logger
	self.sessions = {}
	self.stats = newStats()
	self.connections = {}
	return self
end

function PlayerService:log(message)
	if self.logger ~= nil then
		self.logger("PlayerService", message)
	end
end

function PlayerService:sessionOf(userId)
	return self.sessions[userId]
end

-- ---------------------------------------------------------------- join

function PlayerService:onJoin(player)
	local userId = player.UserId
	self.stats.joins = self.stats.joins + 1

	-- 1. Policy, first, always (doc 13 section 1).
	if self.policy ~= nil then
		self.policy:load(player)
	end

	-- 2. Lock and load.
	local ok, slotOrWhy = self.posts:load(userId, userId)
	if not ok then
		self.stats.joinFailures = self.stats.joinFailures + 1
		self.stats.rejoinsAsked = self.stats.rejoinsAsked + 1
		self:log("join failed for " .. tostring(userId) .. ": " .. tostring(slotOrWhy))
		self:tellClientToRejoin(player, tostring(slotOrWhy))
		return false, slotOrWhy
	end
	local slot = slotOrWhy
	local S = slot.state

	local session = {
		userId = userId,
		player = player,
		joinedAt = self.clock(),
		entriesSeen = 0,
		optInPrompted = false,
		chunkCount = 0,
	}
	self.sessions[userId] = session

	-- 3. Receipts BEFORE the resolve. A receipt can move standing, and
	-- standing decides who gets served in the epochs we are about to run.
	local drained, receipts = self.exchange:drainInbox(userId)
	if drained and #receipts > 0 then
		local absorbed = self.ledger:absorbReceipts(userId, S, receipts)
		self.stats.receiptsAbsorbed = self.stats.receiptsAbsorbed + absorbed
		self.posts:markDirty(userId)
		if self.notify ~= nil then
			self.notify:considerInbox(userId, #receipts, Tide.epoch(self.clock()))
		end
	end

	-- 4 and 5. Plan the catch-up, tell the client how long it is, then let
	-- CadenceService feed it one chunk a frame.
	local chunks = self.posts:queueResolve(userId, function(entries, outboundReceipts)
		self:onResolveComplete(userId, entries, outboundReceipts)
	end)
	session.chunkCount = chunks and #chunks or 0

	self:sendHandshake(player, S, session.chunkCount)
	return true
end

function PlayerService:onResolveComplete(userId, entries, receipts)
	local slot = self.posts:slotOf(userId)
	if slot == nil then
		-- The player left mid-resolve. The entries still matter to the
		-- people the receipts are addressed to, so they go out anyway.
		if receipts ~= nil and #receipts > 0 then
			self.exchange:deliverReceipts(receipts)
		end
		return
	end
	self.ledger:appendAll(userId, slot.state, entries)
	self.posts:markDirty(userId)
	self.stats.entriesStreamed = self.stats.entriesStreamed + #entries

	-- Receipts to the OWNERS of the Drifters we just served. This is the
	-- other half of the asynchronous loop: their traveller comes home with
	-- a story about what you did.
	if #receipts > 0 then
		self.exchange:deliverReceipts(receipts)
	end

	local session = self.sessions[userId]
	if session ~= nil then
		session.entriesSeen = session.entriesSeen + #entries
	end
	self:sendLedger(userId, entries)
end

-- --------------------------------------------------------------- leave

function PlayerService:onLeave(player)
	local userId = player.UserId
	self.stats.leaves = self.stats.leaves + 1
	local slot = self.posts:slotOf(userId)
	if slot ~= nil then
		if self.showcase ~= nil then
			self.showcase:queueBump(userId, slot.state)
		end
		self:considerFarewell(userId, slot.state)
	end
	-- unload does: flush resolve, save, publish, release lock, in that order.
	local ok, why = self.posts:unload(userId, self.clock())
	if not ok then
		self:log("save on leave failed for " .. tostring(userId) .. ": " .. tostring(why))
	end
	if self.notify ~= nil then
		self.notify:flush(userId)
		self.notify:forget(userId)
	end
	if self.ledger ~= nil then
		self.ledger:forget(userId)
	end
	if self.policy ~= nil then
		self.policy:forget(userId)
	end
	self.sessions[userId] = nil
	return ok
end

-- What, if anything, is worth telling this person about later. All four
-- kinds are reports on facts, never invitations (doc 13 section 4).
function PlayerService:considerFarewell(userId, S)
	if self.notify == nil then
		return
	end
	local now = self.clock()
	local epoch = Tide.epoch(now)

	-- Everything below reports a FACT ABOUT THIS PLAYER'S OWN POST that is
	-- already true or already scheduled. Nothing invites, nothing counts
	-- down, nothing is withheld until you come back. `consider` keeps only
	-- the highest-priority one, and the daily cap means at most one goes
	-- out -- so the bar for offering a candidate at all is "would I want to
	-- be told this?".

	-- 1. Deepwater tide (priority 1). A high water at a known hour, which
	--    is when the deepwater classes can reach the post at all.
	local nextEpochStart = Tide.epochStart(epoch + 1)
	if Tide.stateForEpoch(epoch + 1) == "HIGH" then
		self.notify:consider(userId, NotifyConfig.KIND_DEEPWATER, { atTime = nextEpochStart }, nil, nextEpochStart)
	end

	-- 2. Spring tide (priority 2). The widest range of the day, computed
	--    from the same three constituents the whole game runs on, so the
	--    time in the message is exactly the time in the world.
	local low, high = Tide.rangeForDay(now + 86400)
	if high ~= nil and low ~= nil and (high - low) > Tide.MAX_HEIGHT * 1.6 then
		self.notify:consider(userId, NotifyConfig.KIND_SPRING_TIDE, { atTime = now + 86400 }, nil, now + 86400)
	end

	-- 3. A named return (priority 3). Somebody whose Drifter has been to
	--    this post before is due back. The parameter is a user id, which
	--    the platform renders as a player mention -- the one case where a
	--    notification can name a person, and it names someone the player
	--    has already met.
	local ring = S.ring
	if #ring > 0 then
		local who = ring[1].owner
		if who ~= nil and who ~= userId and Post.visitCount(S, who) >= 2 then
			self.notify:consider(userId, NotifyConfig.KIND_NAMED_RETURN, { who = who })
		end
	end
end

-- ------------------------------------------------------------- transport

-- These three exist so the whole service can be driven by the harness with
-- a null transport. Nothing here knows what a RemoteEvent is beyond the
-- handle it was given.

function PlayerService:sendHandshake(player, S, chunkCount)
	if self.remotes == nil then
		return
	end
	local ev = self.remotes[NetContract.RE_POST_SNAPSHOT]
	if ev ~= nil then
		ev:FireClient(player, {
			v = GameConfig.SCHEMA_VERSION,
			tier = S.tier,
			coin = S.coin,
			renown = S.renown,
			current = S.current,
			epoch = Tide.epoch(self.clock()),
			chunks = chunkCount,
			shelves = Post.shelfCount(S),
		})
	end
end

function PlayerService:sendLedger(userId, entries)
	if self.remotes == nil or #entries == 0 then
		return
	end
	local session = self.sessions[userId]
	if session == nil then
		return
	end
	local ev = self.remotes[NetContract.RE_LEDGER_BATCH]
	if ev ~= nil then
		ev:FireClient(session.player, entries)
	end
end

function PlayerService:tellClientToRejoin(player, reason)
	if self.remotes == nil then
		return
	end
	local ev = self.remotes[NetContract.RE_POST_SNAPSHOT]
	if ev ~= nil then
		-- A numeric code, not the reason string: the client owns the words
		-- (doc 13 section 2), and the reason is for the server log.
		ev:FireClient(player, { v = GameConfig.SCHEMA_VERSION, fault = 1 })
	end
end

-- ---------------------------------------------------------------- wiring

function PlayerService:bind()
	self.connections[#self.connections + 1] = self.players.PlayerAdded:Connect(function(player)
		self:onJoin(player)
	end)
	self.connections[#self.connections + 1] = self.players.PlayerRemoving:Connect(function(player)
		self:onLeave(player)
	end)
	-- Anyone already in when the server script ran (Studio, or a slow require).
	local existing = self.players:GetPlayers()
	for i = 1, #existing do
		self:onJoin(existing[i])
	end
end

function PlayerService:unbindAll()
	for i = 1, #self.connections do
		self.connections[i]:Disconnect()
	end
	self.connections = {}
end

-- BindToClose. Every resident post, saved, in order, with the resolve queue
-- drained first. Roblox gives us 30 seconds; a full server of 50 is 50
-- writes, which is over the per-server queue depth of 30, so the adapter's
-- budget waiter is what keeps this from erroring out.
function PlayerService:shutdown()
	local players = self.players:GetPlayers()
	for i = 1, #players do
		self:onLeave(players[i])
	end
end

function PlayerService:resetStats()
	self.stats = newStats()
end

return PlayerService
