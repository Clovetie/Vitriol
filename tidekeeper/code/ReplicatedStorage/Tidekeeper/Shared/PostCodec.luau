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
--   u32  stats[6]
--   u32  checksum                  FNV-1a over everything before it
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

PostCodec.STAT_ORDER = { "served", "refused", "partial", "missed", "noBerth", "coinEarned" }

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
	w:u32(S.postId)
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
		w:u32(stats[PostCodec.STAT_ORDER[i]])
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
		S.postId = r:u32()
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

		S.stats = {}
		for i = 1, #PostCodec.STAT_ORDER do
			S.stats[PostCodec.STAT_ORDER[i]] = r:u32()
		end

		if r:pos() ~= body + 1 then
			error(string.format("consumed %d bytes, expected %d", r:pos() - 1, body), 0)
		end
		return S
	end)

	if not ok then
		return nil, "CORRUPT", tostring(result)
	end
	return result, nil
end

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
