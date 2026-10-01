--!nonstrict
-- ServerStorage/Tidekeeper/Services/ExchangeService (ModuleScript)
--
-- Layer L3. THE DRIFTER EXCHANGE (doc 03). This is the part of TIDEKEEPER
-- that has not been built on Roblox before, and it is the part where a bug is
-- unrecoverable rather than annoying.
--
-- THE ONE PROPERTY EVERYTHING ELSE HANGS OFF
-- ------------------------------------------
-- A Drifter must be delivered to EXACTLY ONE resolve. Not at-least-once with
-- dedup downstream -- at-most-once at the source, because `Resolve.run`'s
-- arrival scheduling is `mod epochCount` and a re-delivered batch does not
-- duplicate an item, it rewrites history into a different history (see
-- HANDOFF, "the one non-commuting property"). Three mechanisms enforce it:
--
--   1. The claim is a SINGLE `UpdateAsync` on one warm shard that reads and
--      removes in the same transform. A failed write means nothing was taken.
--   2. Claimed ids go into `self.delivered` before they are handed to anyone.
--      A second claim of the same id is refused and counted, so a retry that
--      somehow re-reads a shard cannot re-deliver.
--   3. `handOff` moves the batch out of the service in one step. A caller
--      cannot ask for "the same batch again"; it can only ask for more.
--
-- STORAGE SHAPE (doc 03 section 6.2)
--   HOT   MemoryStore hash map  c{cur}:e{epoch} -> 64-bit shard-fill bitmap
--   WARM  DataStore DrifterPool c{cur}:e{epoch}:s{shard} -> array of base64
--
-- MemoryStore holds the INDEX ONLY -- about 17 KB across all currents and
-- live epochs -- because its quota is `64 KB + 1.2 KB * users` universe-wide
-- and any design that pools player data there dies at the moment of success.
--
-- LIQUIDITY (doc 03 section 8): live Drifters, then Echoes from up to six
-- epochs back with a decayed budget, then Seed Drifters. The Ledger is never
-- empty; that is a hard invariant and the harness asserts it against a
-- completely empty exchange.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local GameConfig = require(Tidekeeper.Config.GameConfig)
local EconomyConfig = require(Tidekeeper.Config.EconomyConfig)
local DrifterConfig = require(Tidekeeper.Config.DrifterConfig)
local Codec = require(Tidekeeper.Lib.Codec)
local Hash = require(Tidekeeper.Lib.Hash)
local RNG = require(Tidekeeper.Lib.RNG)
local Tide = require(Tidekeeper.Lib.Tide)
local DrifterCodec = require(Tidekeeper.Shared.DrifterCodec)
local ReceiptCodec = require(Tidekeeper.Shared.ReceiptCodec)
local Drifter = require(Tidekeeper.Domain.Drifter)
local LettersConfig = require(Tidekeeper.Config.LettersConfig)
local SeedsConfig = require(Tidekeeper.Config.SeedsConfig)
local Post = require(Tidekeeper.Domain.Post)

local ExchangeService = {}
ExchangeService.__index = ExchangeService

ExchangeService.SOURCE_LIVE = 1
ExchangeService.SOURCE_ECHO = 2
ExchangeService.SOURCE_SEED = 3

-- doc 03 section 8: Echoes reach back six epochs, no further. Beyond that
-- the decayed budget stops being "word travels slowly" and starts being a
-- fabrication.
local ECHO_EPOCH_REACH = 6
local ECHO_BUDGET_PER_MILLE = 620

-- doc 03 section 9, fairness.
local SAME_HOST_COOLDOWN_EPOCHS = 6
local MAX_PER_OWNER_PER_DAY = 3

-- 64 hand-authored Seed Drifters (doc 03 section 8). Iteration 5 gives them
-- names and letters; here they are a deterministic, stable population whose
-- ids cannot collide with a real account.
-- These used to be local literals here, duplicating the content. They are
-- now read from the one place the 64 Seed characters are defined, so adding
-- a Seed cannot leave the exchange addressing a different population than
-- the Ledger names.
local SEED_OWNER_BASE = SeedsConfig.SEED_OWNER_BASE
local SEED_COUNT = SeedsConfig.SEED_COUNT

local function newStats()
	return {
		published = 0,
		publishSkippedSameEpoch = 0,
		claimAttempts = 0,
		claimedLive = 0,
		claimedEcho = 0,
		claimedSeed = 0,
		duplicatesRefused = 0,
		fairnessSkips = 0,
		decodeFailures = 0,
		receiptsDelivered = 0,
		receiptBatches = 0,
		indexWrites = 0,
		emptyEpochs = 0,
	}
end

function ExchangeService.new(options)
	local opts = options or {}
	local self = setmetatable({}, ExchangeService)
	self.data = opts.data
	self.memory = opts.memory
	self.clock = opts.clock or os.time
	self.logger = opts.logger
	self.stats = newStats()
	-- Every drifter id this server has ever handed to a resolve. In a real
	-- server this is bounded by session churn; the reaper below trims it.
	self.delivered = {}
	self.deliveredCount = 0
	-- Owner -> the epoch we last published for them, on THIS server.
	--
	-- `S.publishedAt` is the real answer but it is not in PostCodec yet, so
	-- it does not survive a save (OD16: persist it in schema v2 with a
	-- migration). Until then this covers the case that actually happens --
	-- two short sessions on the same server inside one 6.2-hour epoch --
	-- and the at-most-once gate remains the backstop for the cross-server
	-- case, which costs a dropped Drifter rather than corrupt history.
	self.lastPublish = {}
	self.decodeBuffer = {}
	return self
end

function ExchangeService:log(message)
	if self.logger ~= nil then
		self.logger("ExchangeService", message)
	end
end

-- ------------------------------------------------------------- publish

-- Build the visitor snapshot from AUTHORITATIVE SERVER STATE at logout
-- (doc 03 section 3). Never from a client payload -- that is the whole
-- reason this runs here and not in a remote handler.
--
-- Deterministic in (postId, salt, epoch): the same post leaving at the same
-- epoch produces the same Drifter, which is what makes the harness able to
-- replay a 30-day lifetime.
-- Which currents a post of this tier may trade in. A tier-1 post sees only
-- the home current; the deep-water currents open up as the post grows. This
-- is what stops a brand-new post from being handed visitors whose budgets
-- and tastes belong to a different stage of the game.
function ExchangeService:currentAllowed(tier, current)
	local minTier = EconomyConfig.CURRENT_MIN_TIER[current + 1]
	if minTier == nil then
		return false
	end
	return tier >= minTier
end

function ExchangeService:buildDrifter(S, epoch)
	local rng = RNG.new(Hash.mix(S.postId, epoch, S.salt))
	local d = Drifter.synthesize(rng, S.owner, epoch, S.current, S.tier)

	-- Override the synthesised guesses with what the owner ACTUALLY did.
	-- Taste is derived from behaviour, never from a questionnaire
	-- (doc 03 section 5).
	d.standing = S.standing[S.current + 1] or 0
	if d.standing > EconomyConfig.STANDING_MAX then
		d.standing = EconomyConfig.STANDING_MAX
	end
	d.renown = math.min(S.renown, 65535)
	d.budget = self:budgetFor(S, d.class)

	-- Wants: the finds this owner has never held. An Almanac gap is a want.
	local wants = {}
	local wantCount = 0
	local stride = 1 + Hash.reduce(Hash.mix(S.postId, epoch, 3), 7)
	local id = 1 + Hash.reduce(Hash.mix(S.salt, epoch, 5), 64)
	while wantCount < DrifterConfig.MAX_WANTS and id <= Post.knownFindCount() do
		if Post.stockOf(S, id) == 0 then
			wantCount = wantCount + 1
			wants[wantCount] = id
		end
		id = id + stride
	end
	d.wants = wants

	-- Cargo is COPIED, NOT MOVED (doc 03 section 3.1): at most four ids off
	-- the owner's shelves, offered as a barter claim the recipient accepts or
	-- declines. There is no transfer, so there is no duplication exploit.
	--
	-- THE PLAYER'S OWN CHOICE WINS. `RF_Dispatch` records `S.dispatchCargo`
	-- and `S.dispatchLetter` on the post and relies on publication at logout
	-- to carry them. Until iteration 7 this function ignored both: it
	-- recomputed cargo by walking the shelves in slot order and hard-coded
	-- `d.letterId = 0`. The effect was that the entire dispatch screen was
	-- inert -- a player chose what to send and who-knows-what went instead,
	-- and no letter ever reached another player, which also made Ledger
	-- template 105 ("your drifter brought a note back") unreachable prose.
	-- Nothing caught it because each half is valid on its own; the defect
	-- lived in the gap between the handler and this service. That gap now
	-- has a check: tools/tidekeeper-dead-write-scan.js.
	--
	-- The shelf walk remains as the FALLBACK for a post that logs out
	-- without ever opening the dispatch screen, which is the common case.
	local cargo = {}
	local cargoCount = 0
	local chosen = S.dispatchCargo
	if chosen ~= nil and #chosen > 0 then
		for i = 1, #chosen do
			local id = chosen[i]
			-- Re-validate against CURRENT stock. The choice was made earlier
			-- in the session and the shelf may have sold out since; trusting
			-- the stale selection would ship cargo the post no longer holds.
			if cargoCount < DrifterConfig.MAX_CARGO and id ~= nil and id > 0 and Post.stockOf(S, id) > 0 then
				cargoCount = cargoCount + 1
				cargo[cargoCount] = id
			end
		end
	end
	if cargoCount == 0 then
		for slot = 1, #S.shelves do
			local shelf = S.shelves[slot]
			if shelf ~= nil and shelf.id ~= nil and shelf.id > 0 and cargoCount < DrifterConfig.MAX_CARGO then
				cargoCount = cargoCount + 1
				cargo[cargoCount] = shelf.id
			end
		end
	end
	d.cargo = cargo

	-- The letter is an index into an authored phrase list, never free text
	-- (doc 13 section 2). Clamp rather than trust: the field is server-set,
	-- but a stale value from before a content change must not address a
	-- phrase that no longer exists.
	local letterId = S.dispatchLetter or 0
	if letterId < 0 or letterId > LettersConfig.MAX_LETTER_ID then
		letterId = 0
	end
	d.letterId = letterId
	return d
end

-- Budget is derived server-side from the owner's economy and NEVER declared
-- (doc 03 section 9, anti-inflation). Class multiplies it; the class itself
-- came from tier and tide at publication.
function ExchangeService:budgetFor(S, class)
	local base = 40 + math.floor(S.coin / 24) + Post.shelvedValue(S)
	local scaled = math.floor(base * Drifter.classValuePerMille(class) / 1000)
	if scaled < 1 then
		scaled = 1
	end
	if scaled > 4294967295 then
		scaled = 4294967295
	end
	return scaled
end

-- One UpdateAsync into the warm shard, one UpdateAsync on the hot index.
-- Two requests per logout, which is the budget in doc 03 section 6.3.
function ExchangeService:publish(S, now)
	local epoch = Tide.epoch(now)
	-- ONE DRIFTER PER POST PER EPOCH, enforced here and not only at the
	-- dispatch remote.
	--
	-- A Drifter's id is `DrifterCodec.makeId(owner, epoch)`, so a second
	-- publication in the same epoch produces a COLLIDING ID. The session
	-- test caught exactly that: over a simulated month, 27 real Drifters
	-- were removed from their shards and then refused by the at-most-once
	-- gate as duplicates -- silently dropped people. Two short sessions
	-- inside one 6.2-hour epoch is not an edge case, it is a Saturday.
	--
	-- Refusing the second publication is also the honest reading of the
	-- fiction: you have one traveller, and they have already left.
	local lastEpoch = S.publishedAt or self.lastPublish[S.owner]
	if lastEpoch ~= nil and lastEpoch >= epoch then
		self.stats.publishSkippedSameEpoch = self.stats.publishSkippedSameEpoch + 1
		return false, "already published this epoch"
	end
	local d = self:buildDrifter(S, epoch)
	local ok, why = Drifter.validate(d)
	if not ok then
		self:log("refusing to publish a malformed drifter: " .. tostring(why))
		return false, why
	end
	local bytes = DrifterCodec.encode(d)
	local encoded = Codec.base64Encode(bytes, #bytes)
	local shard = self.data:shardFor(d.id)
	local wrote, err = self.data:publishDrifter(d.current, epoch, shard, encoded)
	if not wrote then
		return false, err
	end
	self.stats.published = self.stats.published + 1
	S.publishedAt = epoch
	-- Lifetime dispatch counters (schema v3). Incremented only after the
	-- write landed: a drifter that failed to publish was not dispatched, and
	-- a badge must never be earned by an error path.
	if S.stats ~= nil then
		S.stats.driftersDispatched = (S.stats.driftersDispatched or 0) + 1
		if d.letterId ~= nil and d.letterId > 0 then
			S.stats.lettersSent = (S.stats.lettersSent or 0) + 1
		end
	end
	self.lastPublish[S.owner] = epoch
	-- The index is best-effort. If MemoryStore is over quota the claim side
	-- falls back to probing shards; it gets slower, never wrong.
	local marked = self.memory:markShard(d.current, epoch, shard)
	if marked then
		self.stats.indexWrites = self.stats.indexWrites + 1
	end
	return true, d
end

-- --------------------------------------------------------------- claim

-- Fairness gate, doc 03 section 9. Returns true when this host may serve
-- this Drifter.
function ExchangeService:admits(S, d, epoch, perOwner)
	if d.owner == S.owner then
		return false
	end
	-- "A Drifter may not be claimed by the same host twice within 6 epochs."
	-- The ring is most-recent-first, so the first hit is the most recent.
	local ring = S.ring
	for i = 1, #ring do
		if ring[i].owner == d.owner then
			if epoch - ring[i].epoch < SAME_HOST_COOLDOWN_EPOCHS then
				return false
			end
			break
		end
	end
	-- "A host may serve at most 3 Drifters from one owner per day." The ring
	-- covers the last 48 visits, which at 3.86 epochs a day is well over a
	-- day's worth.
	if Post.visitCount(S, d.owner) >= MAX_PER_OWNER_PER_DAY * 2 then
		return false
	end
	local seen = perOwner[d.owner] or 0
	if seen >= MAX_PER_OWNER_PER_DAY then
		return false
	end
	return true
end

function ExchangeService:decodeOne(encoded)
	local okBytes, bytes = pcall(function()
		return Codec.base64Decode(encoded)
	end)
	if not okBytes then
		self.stats.decodeFailures = self.stats.decodeFailures + 1
		return nil
	end
	local ok, d = pcall(function()
		return DrifterCodec.decode(bytes, 1, nil)
	end)
	if not ok or d == nil then
		self.stats.decodeFailures = self.stats.decodeFailures + 1
		return nil
	end
	return d
end

-- The at-most-once gate. Called exactly once per candidate, immediately
-- after it leaves the store and before anybody sees it.
--
-- SEED DRIFTERS ARE EXEMPT, and finding that out cost a red build. A Seed's
-- id is `DrifterCodec.makeId(owner, epoch)` over a synthetic owner, so it is
-- deterministic and it RECURS BY DESIGN -- the same wandering character
-- turning up again is the entire point of them. Putting seeds in the
-- at-most-once set meant every seed was usable exactly once per server
-- lifetime, after which a quiet exchange produced an empty Ledger: the one
-- failure mode the seed population exists to prevent.
--
-- The property that matters is about REAL people's Drifters, because those
-- are the ones that were removed from a shard and cannot be recreated.
function ExchangeService:take(id)
	if self.delivered[id] ~= nil then
		self.stats.duplicatesRefused = self.stats.duplicatesRefused + 1
		return false
	end
	self.delivered[id] = true
	self.deliveredCount = self.deliveredCount + 1
	return true
end

-- Claim up to `want` Drifters for this post, covering the epoch window
-- [firstEpoch, lastEpoch]. Returns a list.
--
-- Cost: 1 MemoryStore GetAsync per epoch probed and 1 DataStore UpdateAsync
-- per shard touched, bounded by `maxRequests` so that a sparse exchange
-- cannot turn one join into forty requests.
function ExchangeService:claim(S, firstEpoch, lastEpoch, want, maxRequests)
	self.stats.claimAttempts = self.stats.claimAttempts + 1
	local out = {}
	local count = 0
	if not self:currentAllowed(S.tier, S.current) then
		-- The post drifted into a current it has not earned (a tier
		-- rollback, or a save from a future schema). Fall back to the home
		-- current rather than refusing to produce visitors.
		S.current = 0
	end
	local perOwner = {}
	local localSeen = {}
	local budget = maxRequests or 3
	local spent = 0

	local function consider(d, source)
		if d == nil then
			return false
		end
		if not self:admits(S, d, lastEpoch, perOwner) then
			self.stats.fairnessSkips = self.stats.fairnessSkips + 1
			return false
		end
		if source == ExchangeService.SOURCE_SEED then
			-- Recurrence is the point; only guard against the same seed
			-- appearing twice in ONE batch.
			if localSeen[d.id] then
				return false
			end
		elseif not self:take(d.id) then
			return false
		end
		localSeen[d.id] = true
		perOwner[d.owner] = (perOwner[d.owner] or 0) + 1
		count = count + 1
		out[count] = d
		if source == ExchangeService.SOURCE_LIVE then
			self.stats.claimedLive = self.stats.claimedLive + 1
		elseif source == ExchangeService.SOURCE_ECHO then
			self.stats.claimedEcho = self.stats.claimedEcho + 1
		else
			self.stats.claimedSeed = self.stats.claimedSeed + 1
		end
		return true
	end

	-- Tier 1: live Drifters in this post's current, newest epoch first.
	-- Every MemoryStore index probe is charged against the same budget as a
	-- DataStore claim. It was not, originally, and the session test showed
	-- the consequence immediately: a sparse exchange sent the claim walking
	-- backwards through six echo epochs probing the index for each, at
	-- nearly seven MemoryStore requests per session against a design target
	-- of two. A budget that only counts the expensive-looking call is not a
	-- budget.
	local epoch = lastEpoch
	while epoch >= firstEpoch and count < want and spent < budget do
		spent = spent + 1
		local okIndex, shards = self.memory:shardsFor(S.current, epoch)
		if okIndex and #shards > 0 then
			for i = 1, #shards do
				if count >= want or spent >= budget then
					break
				end
				spent = spent + 1
				local okClaim, taken = self.data:claimDrifters(S.current, epoch, shards[i], want - count)
				if okClaim and taken ~= nil then
					for j = 1, #taken do
						consider(self:decodeOne(taken[j]), ExchangeService.SOURCE_LIVE)
					end
				end
			end
		else
			self.stats.emptyEpochs = self.stats.emptyEpochs + 1
		end
		epoch = epoch - 1
	end

	-- Tier 2: Echoes. Real Drifters from up to six epochs back, replayed at a
	-- decayed budget and marked in the Ledger ("word travels slowly out
	-- here"). Honest, not fake: the person existed and did visit.
	epoch = firstEpoch - 1
	local floorEpoch = firstEpoch - ECHO_EPOCH_REACH
	while epoch >= floorEpoch and count < want and spent < budget do
		spent = spent + 1
		local okIndex, shards = self.memory:shardsFor(S.current, epoch)
		if okIndex and #shards > 0 then
			for i = 1, #shards do
				if count >= want or spent >= budget then
					break
				end
				spent = spent + 1
				local okClaim, taken = self.data:claimDrifters(S.current, epoch, shards[i], want - count)
				if okClaim and taken ~= nil then
					for j = 1, #taken do
						local d = self:decodeOne(taken[j])
						if d ~= nil then
							d.budget = math.floor(d.budget * ECHO_BUDGET_PER_MILLE / 1000)
							if d.budget < 1 then
								d.budget = 1
							end
							consider(d, ExchangeService.SOURCE_ECHO)
						end
					end
				end
			end
		end
		epoch = epoch - 1
	end

	-- Tier 3: Seeds. The Ledger is never empty -- a hard invariant.
	local attempt = 0
	while count < want and attempt < SEED_COUNT do
		attempt = attempt + 1
		local d = self:seedDrifter(S, lastEpoch, attempt)
		consider(d, ExchangeService.SOURCE_SEED)
	end
	return out
end

-- A Seed Drifter is a character, not a statistic (doc 03 section 8). Its
-- owner id is below any real account id, so a receipt addressed to one is
-- routed nowhere and costs nothing.
function ExchangeService:seedDrifter(S, epoch, index)
	local which = Hash.reduce(Hash.mix(S.postId, epoch, index, 17), SEED_COUNT)
	local owner = SEED_OWNER_BASE + which
	local rng = RNG.new(Hash.mix(owner, epoch, S.salt))
	local tier = 1 + Hash.reduce(Hash.mix(owner, 23), math.min(S.tier, GameConfig.MAX_TIER))
	local d = Drifter.synthesize(rng, owner, epoch, S.current, tier)
	-- Seeds are recognisable: modest budgets, no cargo, and they recur.
	d.budget = math.floor(d.budget * 700 / 1000) + 25
	d.cargo = {}
	-- ...and each one leans hard on a single taste axis, which is what makes
	-- a Seed a character you learn rather than another anonymous shopper.
	-- `which` is 0-based; the config is 1-based.
	local seed = SeedsConfig.SEEDS[which + 1]
	if seed ~= nil and d.taste ~= nil then
		d.taste[seed[3]] = seed[4]
	end
	return d
end

function ExchangeService:isSeed(ownerId)
	return ownerId >= SEED_OWNER_BASE and ownerId < SEED_OWNER_BASE + SEED_COUNT
end

-- ------------------------------------------------------------ receipts

-- Receipts are grouped by recipient shard, so delivering thirty receipts to
-- thirty players costs far fewer than thirty writes. Seeds are dropped here
-- rather than earlier so the count still balances upstream.
function ExchangeService:deliverReceipts(receipts)
	if #receipts == 0 then
		return true, 0
	end
	local byOwner = {}
	local owners = {}
	local ownerCount = 0
	for i = 1, #receipts do
		local r = receipts[i]
		local owner = DrifterCodec.ownerFromId(r.drifterId)
		if not self:isSeed(owner) then
			local bucket = byOwner[owner]
			if bucket == nil then
				bucket = {}
				byOwner[owner] = bucket
				ownerCount = ownerCount + 1
				owners[ownerCount] = owner
			end
			local bytes = ReceiptCodec.encode(r)
			bucket[#bucket + 1] = Codec.base64Encode(bytes, #bytes)
		end
	end
	-- Sorted, because two servers delivering the same set must produce the
	-- same sequence of writes.
	table.sort(owners)
	local delivered = 0
	for i = 1, ownerCount do
		local owner = owners[i]
		local ok = self.data:appendReceipts(owner, byOwner[owner])
		if ok then
			delivered = delivered + #byOwner[owner]
			self.stats.receiptBatches = self.stats.receiptBatches + 1
		end
	end
	self.stats.receiptsDelivered = self.stats.receiptsDelivered + delivered
	return true, delivered
end

-- Read this player's own inbox. One UpdateAsync, folded into the join path.
function ExchangeService:drainInbox(ownerId)
	local ok, encodedList = self.data:drainReceipts(ownerId)
	if not ok then
		return false, encodedList
	end
	local out = {}
	local n = 0
	for i = 1, #encodedList do
		local okBytes, bytes = pcall(function()
			return Codec.base64Decode(encodedList[i])
		end)
		if okBytes then
			local rec = ReceiptCodec.decode(bytes, 1, nil)
			if rec ~= nil then
				n = n + 1
				out[n] = rec
			end
		end
	end
	return true, out
end

-- --------------------------------------------------------------- upkeep

-- The delivered set is a leak if it is never trimmed. A Drifter's TTL is
-- seven days, so anything older than the reap horizon can never come back.
function ExchangeService:trimDelivered(currentEpoch)
	local horizon = currentEpoch - GameConfig.MAX_CATCHUP_EPOCHS
	local removed = 0
	local ids = {}
	local n = 0
	for id in pairs(self.delivered) do
		n = n + 1
		ids[n] = id
	end
	table.sort(ids)
	for i = 1, n do
		local id = ids[i]
		local epochLow = DrifterCodec.epochLowFromId(id)
		if epochLow < horizon % GameConfig.DRIFTER_ID_EPOCH_SPAN then
			self.delivered[id] = nil
			self.deliveredCount = self.deliveredCount - 1
			removed = removed + 1
		end
	end
	return removed
end

function ExchangeService:resetStats()
	self.stats = newStats()
end

return ExchangeService
