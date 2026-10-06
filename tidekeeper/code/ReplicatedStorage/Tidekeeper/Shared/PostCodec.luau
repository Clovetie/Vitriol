--!nonstrict
-- ReplicatedStorage/Tidekeeper/Shared/PostCodec (ModuleScript)
--
-- Post <-> versioned blob (doc 05 section 3). The blob is a byte array; the
-- DataStore adapter at L1 (iteration 3) is the only thing that turns it into a
-- `buffer` and a base64 string. Keeping the packing here and pure is what
-- makes the save format unit-testable with no Roblox surface at all.
--
-- LAYOUT (little-endian, version 1)
--
--   u8   version                   always first, always readable
--   u8   flags                     reserved, must be 0
--   u32  postId
--   u64  owner
--   u32  salt
--   u8   tier
--   u8   current
--   u16  season
--   u32  resolvedAt                unix seconds (valid to 2106)
--   u32  coin
--   u32  renown
--   u16  standing[5]
--   u8   almanac[32]               held
--   u8   sold[32]                  ever sold
--   u8   combCount + i32 comb[n]
--   u8   shelfCount + n x (u16 id, u32 price)
--   u16  storeCount + n x (u16 id, u16 qty)
--   u16  orderBytes + n x u8
--   u8   ringCount + n x u48       owner*8192 + (epoch mod 8192)
--   u8   claimCount + n x (u16 id, u16 qty, u64 fromOwner, i32 epoch)
--   u32  stats[6]                  v1/v2. v3 writes stats[12] -- see
--                                  STAT_ORDER and STATS_BY_VERSION below.
--   u32  publishedAt               v2+ ONLY. (tide epoch of the last published
--                                  Drifter) + 1, so 0 means never. Epoch 0 is
--                                  a real epoch. See OD16 / section 6.
--   u8   badges[5]                 v3 ONLY. 40 achievement bits, id 1 = byte
--                                  1 bit 0. Ids are persisted bit indices and
--                                  are never renumbered (BadgesConfig).
--   u32  checksum                  FNV-1a over everything before it
--
-- VERSION HISTORY
--   v1  the original layout, shipped in iteration 2.
--   v2  appends `publishedAt` (iteration 4). A v1 blob is migrated by leaving
--       it absent, which reads as "this post has never published", and the very
--       worst that can happen is one extra Drifter in the epoch the player
--       first logs in after the update. Appending at the tail rather than
--       inserting in the middle is deliberate: it keeps the v1 reader and the
--       v2 reader byte-identical up to the new field.
--
-- Two rules the format obeys forever:
--   * the version byte is first, and a blob NEWER than the server is refused
--     outright (Shared/Version);
--   * a reader never trusts a length. Every count is bounded by the same
--     GameConfig constant the writer used, so a corrupt blob fails a check
--     instead of allocating four million table entries.

local Codec = require(script.Parent.Parent.Lib.Codec)
local Hash = require(script.Parent.Parent.Lib.Hash)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local Version = require(script.Parent.Version)

local PostCodec = {}

local floor = math.floor

local ALMANAC_BYTES = 32
local CURRENTS = EconomyConfig.CURRENT_COUNT
local RING_SPAN = GameConfig.DRIFTER_ID_EPOCH_SPAN
local MAX_CLAIMS = 64

-- The lifetime counters, in wire order. APPEND ONLY: the index of a name is
-- its position in every v3 blob ever written.
--
-- The first six are the original v1 set. The six added in v3 are the badge
-- stats that could not be derived from state the post already holds --
-- `visitorsServed` is `served` and `tierReached` is `S.tier`, so those cost
-- nothing, but "how many letters has this player sent" is only knowable if
-- somebody counts it. See Domain/Badges.statsOf for the full mapping.
PostCodec.STAT_ORDER = {
	"served",
	"refused",
	"partial",
	"missed",
	"noBerth",
	"coinEarned",
	-- v3
	"lettersSent",
	"lettersReceived",
	"giftsGiven",
	"driftersDispatched",
	"tidesElapsed",
	"tideStatesSeen", -- a 5-bit mask, not a count: Tide.CODE n -> bit n-1
}

-- How many of STAT_ORDER each schema version stores. A v1 or v2 blob stops
-- after six, and the migration supplies zeroes for the rest.
PostCodec.STATS_V1 = 6
PostCodec.BADGE_BYTES = 5

local function packRing(owner, epoch)
	local low = epoch % RING_SPAN
	if low < 0 then
		low = low + RING_SPAN
	end
	return owner * RING_SPAN + low
end

local function unpackRing(value)
	return floor(value / RING_SPAN), value % RING_SPAN
end

PostCodec.packRing = packRing
PostCodec.unpackRing = unpackRing

-- Encode. Errors (rather than truncating) if the state violates a bound: a
-- post that cannot be written is a bug to fix now, not a save to corrupt.
function PostCodec.encode(S)
	local w = Codec.writer()
	w:u8(Version.CURRENT)
	w:u8(0)
	-- v4+: postId is u64. It was u32 until iteration 13, and `postId` IS a
	-- Roblox UserId (PostService calls `Post.new(postId or userId, userId,
	-- ...)`). Modern UserIds have passed 2^32 -- the real Studio run that
	-- found this had id 7221743187 -- so EVERY save for a recent account
	-- died with "Codec: u32 out of range [0, 4294967295]: 7221743187" and
	-- that player's post could never be written at all.
	--
	-- `owner` beside it was always u64; only this field was narrow.
	w:u64(S.postId)
	w:u64(S.owner)
	w:u32(S.salt)
	w:u8(S.tier)
	w:u8(S.current)
	w:u16(S.season)
	w:u32(S.resolvedAt)
	w:u32(S.coin)
	w:u32(S.renown)
	for i = 1, CURRENTS do
		w:u16(S.standing[i])
	end
	for i = 1, ALMANAC_BYTES do
		w:u8(S.almanac[i])
	end
	for i = 1, ALMANAC_BYTES do
		w:u8(S.sold[i])
	end

	local comb = S.comb
	w:u8(#comb)
	for i = 1, #comb do
		w:i32(comb[i])
	end

	local shelves = S.shelves
	w:u8(#shelves)
	for i = 1, #shelves do
		w:u16(shelves[i].id)
		w:u32(shelves[i].price)
	end

	local store = S.store
	w:u16(#store)
	for i = 1, #store do
		w:u16(store[i].id)
		w:u16(store[i].qty)
	end

	-- Orders are already bytecode by the time they reach the post state; the
	-- codec stores the encoded form verbatim so a program the server does not
	-- understand still round-trips instead of being silently dropped.
	local orderBytes = S.ordersBytecode
	if orderBytes == nil then
		orderBytes = {}
	end
	if #orderBytes > GameConfig.MAX_ORDERS_BYTES then
		error("PostCodec.encode: orders bytecode exceeds its budget", 0)
	end
	w:u16(#orderBytes)
	for i = 1, #orderBytes do
		w:u8(orderBytes[i])
	end

	local ring = S.ring
	w:u8(#ring)
	for i = 1, #ring do
		w:u48(packRing(ring[i].owner, ring[i].epoch))
	end

	local claims = S.claims
	local claimCount = #claims
	if claimCount > MAX_CLAIMS then
		claimCount = MAX_CLAIMS
	end
	w:u8(claimCount)
	for i = 1, claimCount do
		local claim = claims[i]
		w:u16(claim.id)
		w:u16(claim.qty)
		w:u64(claim.fromOwner)
		w:i32(claim.epoch)
	end

	local stats = S.stats
	for i = 1, #PostCodec.STAT_ORDER do
		w:u32(stats[PostCodec.STAT_ORDER[i]] or 0)
	end

	-- v2 tail. Stored as epoch + 1 so that the wire value 0 means "never
	-- published" and cannot be confused with epoch 0, which is a real epoch
	-- (the first 6.2 hours after TideConfig.EPOCH). A sentinel that collides
	-- with a legal value is a bug that only shows up on launch day.
	w:u32((S.publishedAt ~= nil) and (S.publishedAt + 1) or 0)

	-- v3 tail. Forty achievement bits. A bitmask rather than a list because
	-- badges are never revoked and never reordered, so the set only ever
	-- grows and a fixed five bytes is both smaller and cheaper to test than
	-- any variable-length form.
	local badges = S.badges
	for i = 1, PostCodec.BADGE_BYTES do
		w:u8((badges ~= nil and badges[i]) or 0)
	end

	w:u32(Hash.bytes(w.bytes, 1, w.n))

	if w.n > GameConfig.MAX_POST_BLOB_BYTES then
		error(string.format("PostCodec.encode: %d bytes exceeds the %d byte budget", w.n, GameConfig.MAX_POST_BLOB_BYTES), 0)
	end
	return w:build()
end

-- Decode. Returns `(state, nil)` or `(nil, reason, message)`. `reason` is one
-- of the Version constants, or "CORRUPT".
function PostCodec.decode(bytes)
	if type(bytes) ~= "table" or #bytes < 8 then
		return nil, "CORRUPT", "blob is too short to contain a header"
	end
	local version = bytes[1]
	local status, message = Version.classify(version)
	if status ~= Version.OK then
		return nil, status, message
	end

	local body = #bytes - 4
	local computed = Hash.bytes(bytes, 1, body)
	local stored = bytes[body + 1] + bytes[body + 2] * 256 + bytes[body + 3] * 65536 + bytes[body + 4] * 16777216
	if computed ~= stored then
		return nil, "CORRUPT", string.format("checksum mismatch (computed %d, stored %d)", computed, stored)
	end

	local ok, result = pcall(function()
		local r = Codec.reader(bytes, 1)
		local S = {}
		S.v = r:u8()
		local flags = r:u8()
		if flags ~= 0 then
			error("unknown flags byte " .. tostring(flags), 0)
		end
		-- v1..v3 wrote postId as u32; v4+ writes u64. Reading the right
		-- width per version is what lets an existing post load.
		if S.v >= 4 then
			S.postId = r:u64()
		else
			S.postId = r:u32()
		end
		S.owner = r:u64()
		S.salt = r:u32()
		S.tier = r:u8()
		S.current = r:u8()
		S.season = r:u16()
		S.resolvedAt = r:u32()
		S.coin = r:u32()
		S.renown = r:u32()
		S.standing = {}
		for i = 1, CURRENTS do
			S.standing[i] = r:u16()
		end
		S.almanac = r:bytes_(ALMANAC_BYTES, {})
		S.sold = r:bytes_(ALMANAC_BYTES, {})

		local combCount = r:u8()
		if combCount > GameConfig.MAX_COMB_NODES then
			error("comb node count " .. combCount .. " exceeds the maximum", 0)
		end
		S.comb = {}
		for i = 1, combCount do
			S.comb[i] = r:i32()
		end

		local shelfCount = r:u8()
		if shelfCount > GameConfig.MAX_SHELF_SLOTS then
			error("shelf count " .. shelfCount .. " exceeds the maximum", 0)
		end
		S.shelves = {}
		for i = 1, shelfCount do
			S.shelves[i] = { id = r:u16(), price = r:u32() }
		end

		local storeCount = r:u16()
		if storeCount > GameConfig.MAX_STORE_ENTRIES then
			error("store entry count " .. storeCount .. " exceeds the maximum", 0)
		end
		S.store = {}
		for i = 1, storeCount do
			S.store[i] = { id = r:u16(), qty = r:u16() }
		end

		local orderLength = r:u16()
		if orderLength > GameConfig.MAX_ORDERS_BYTES then
			error("orders bytecode length " .. orderLength .. " exceeds the budget", 0)
		end
		S.ordersBytecode = r:bytes_(orderLength, {})

		local ringCount = r:u8()
		if ringCount > GameConfig.VISITOR_RING_SIZE then
			error("visitor ring count " .. ringCount .. " exceeds the maximum", 0)
		end
		S.ring = {}
		for i = 1, ringCount do
			local owner, epochLow = unpackRing(r:u48())
			S.ring[i] = { owner = owner, epoch = epochLow }
		end

		local claimCount = r:u8()
		if claimCount > MAX_CLAIMS then
			error("claim count " .. claimCount .. " exceeds the maximum", 0)
		end
		S.claims = {}
		for i = 1, claimCount do
			S.claims[i] = { id = r:u16(), qty = r:u16(), fromOwner = r:u64(), epoch = r:i32() }
		end

		-- Read only as many counters as this blob's version wrote. The rest
		-- are filled in by the v2 -> v3 migration, not invented here.
		local statCount = (version >= 3) and #PostCodec.STAT_ORDER or PostCodec.STATS_V1
		S.stats = {}
		for i = 1, statCount do
			S.stats[PostCodec.STAT_ORDER[i]] = r:u32()
		end

		-- The ONLY version-conditional read in the format. A v1 blob simply
		-- stops here, and `Version.migrate` below supplies the default. The
		-- trailing `r:pos()` check then proves we consumed exactly the bytes
		-- this version defines -- so a v1 blob carrying v2 bytes, or the
		-- reverse, is CORRUPT rather than silently misparsed.
		if version >= 2 then
			local rawPublished = r:u32()
			if rawPublished > 0 then
				S.publishedAt = rawPublished - 1
			end
		end

		if version >= 3 then
			S.badges = {}
			for i = 1, PostCodec.BADGE_BYTES do
				S.badges[i] = r:u8()
			end
		end

		if r:pos() ~= body + 1 then
			error(string.format("consumed %d bytes, expected %d", r:pos() - 1, body), 0)
		end
		return S
	end)

	if not ok then
		return nil, "CORRUPT", tostring(result)
	end

	-- Walk the decoded TABLE up to the current schema. The bytes were read
	-- with the layout their own version declares; migration is a pure
	-- table-to-table step on top of that, which is why Shared/Version knows
	-- nothing about byte offsets.
	local migrated, reason, why = Version.migrate(result, version)
	if migrated == nil then
		return nil, reason, why
	end
	return migrated, nil
end

-- Register this format's migrations. Called once at module load, and exposed
-- so the harness can restore them after Version._reset(). Idempotent: the
-- underlying Version.register refuses a duplicate, so the guard is here
-- rather than an assert that would make a second call fatal.
function PostCodec.registerMigrations()
	if not Version.hasMigration(1) then
		-- v1 -> v2: the post has no recorded publication. `publishedAt`
		-- stays absent, which is what "never" is, and
		-- ExchangeService:publish treats "never" as publishable. The worst
		-- case is one extra Drifter in the epoch a player first logs in
		-- after the update, which is a strictly better failure than
		-- suppressing a real one.
		Version.register(1, 2, function(d)
			d.publishedAt = nil
			d.v = 2
			return d
		end)
	end
	if not Version.hasMigration(2) then
		-- v2 -> v3: six new lifetime counters and the badge mask. All start
		-- at zero, which is the honest answer -- we genuinely do not know how
		-- many letters a pre-v3 player sent, and inventing a number would
		-- hand out achievements nobody earned.
		--
		-- The one place that stings is `tidesElapsed`: a long-standing player
		-- restarts that count at zero. Backfilling it from `resolvedAt` was
		-- considered and rejected, because it would award the long-absence
		-- badges to someone who had simply been away.
		Version.register(2, 3, function(d)
			d.stats = d.stats or {}
			for i = PostCodec.STATS_V1 + 1, #PostCodec.STAT_ORDER do
				d.stats[PostCodec.STAT_ORDER[i]] = 0
			end
			d.badges = { 0, 0, 0, 0, 0 }
			d.v = 3
			return d
		end)
	end
	if not Version.hasMigration(3) then
		-- v3 -> v4: `postId` widens from u32 to u64. Nothing in the decoded
		-- table changes -- the field already holds a number and the reader
		-- picked its width from the version byte -- so this migration only
		-- restamps the version.
		--
		-- It exists because the FORMAT changed even though the SHAPE did
		-- not, and skipping the registration would leave a v3 blob failing
		-- the migration-chain check rather than loading. Found by a real
		-- Studio run: postId is a UserId, modern UserIds exceed 2^32, and
		-- every affected player's save threw instead of writing.
		Version.register(3, 4, function(d)
			d.v = 4
			return d
		end)
	end
	return true
end

PostCodec.registerMigrations()

-- Convenience for the adapter layer: blob -> base64 string and back.
function PostCodec.encodeToString(S)
	return Codec.base64Encode(PostCodec.encode(S))
end

function PostCodec.decodeFromString(text)
	local okDecode, bytes = pcall(Codec.base64Decode, text)
	if not okDecode then
		return nil, "CORRUPT", tostring(bytes)
	end
	return PostCodec.decode(bytes)
end

return PostCodec
