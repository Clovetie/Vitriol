--!nonstrict
-- ReplicatedStorage/Tidekeeper/Shared/DrifterCodec (ModuleScript)
--
-- Drifter <-> 68-byte record (doc 05 section 4). Fixed width on purpose: the
-- warm shard is a flat array of these, so a shard of 200 drifters is exactly
-- 13 600 bytes before base64 and its size is knowable without serialising.
--
-- Layout (0-based offsets, little-endian):
--    0  v          u8
--    1  id         u64   see the identity note below
--    9  owner      u64
--   17  epoch      i32
--   21  current    u8
--   22  class      u8
--   23  tier       u8
--   24  standing   u16
--   26  renown     u16
--   28  budget     u32
--   32  taste      8 x i8
--   40  wants      4 x u16   (0 = empty slot)
--   48  cargo      4 x u16   (0 = empty slot)
--   56  letterId   u16
--   58  beacons    u8
--   59  look       u32
--   63  checksum   u32   FNV-1a over bytes 0..62
--   67  reserved   u8    must be 0
--
-- IDENTITY NOTE (a correction to doc 05 section 4)
-- ------------------------------------------------
-- Doc 05 specifies `id = (userId << 24) | epochLow`. That is not
-- representable: Roblox user ids already exceed 2^32, and shifting one left by
-- 24 produces a value above 2^53, which a Luau number cannot hold exactly. The
-- id would silently round and two different drifters would collide.
--
-- The shipped construction is `id = owner * 8192 + (epoch mod 8192)`:
--   * exact for every owner below 2^40 (GameConfig.OWNER_ID_MAX), which is
--     ~200x the largest user id in existence;
--   * still 8 bytes on the wire, so the record size is unchanged;
--   * unique per owner for 8192 consecutive epochs (~5.8 years), and drifters
--     expire after 7 days.

local Codec = require(script.Parent.Parent.Lib.Codec)
local Hash = require(script.Parent.Parent.Lib.Hash)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local DrifterConfig = require(script.Parent.Parent.Config.DrifterConfig)

local DrifterCodec = {}

local floor = math.floor

local SIZE = GameConfig.DRIFTER_BLOB_BYTES
local AXES = DrifterConfig.TASTE_AXES
local MAX_WANTS = DrifterConfig.MAX_WANTS
local MAX_CARGO = DrifterConfig.MAX_CARGO
local SPAN = GameConfig.DRIFTER_ID_EPOCH_SPAN

DrifterCodec.SIZE = SIZE
DrifterCodec.OFFSET_CHECKSUM = 63

function DrifterCodec.makeId(owner, epoch)
	assert(owner >= 0 and owner < GameConfig.OWNER_ID_MAX, "DrifterCodec.makeId: owner out of representable range")
	local low = epoch % SPAN
	if low < 0 then
		low = low + SPAN
	end
	return owner * SPAN + low
end

function DrifterCodec.ownerFromId(id)
	return floor(id / SPAN)
end

function DrifterCodec.epochLowFromId(id)
	return id % SPAN
end

local function writeFixedU16Slots(w, list, slots)
	local n = list and #list or 0
	for i = 1, slots do
		if i <= n then
			w:u16(list[i])
		else
			w:u16(0)
		end
	end
end

local function readFixedU16Slots(r, slots, out)
	local n = 0
	for _ = 1, slots do
		local v = r:u16()
		if v ~= 0 then
			n = n + 1
			out[n] = v
		end
	end
	for i = n + 1, slots do
		out[i] = nil
	end
	return out
end

-- Encode to a fresh 68-entry byte array.
function DrifterCodec.encode(d)
	local w = Codec.writer()
	w:u8(d.v or 1)
	w:u64(d.id)
	w:u64(d.owner)
	w:i32(d.epoch)
	w:u8(d.current)
	w:u8(d.class)
	w:u8(d.tier)
	w:u16(d.standing)
	w:u16(d.renown)
	w:u32(d.budget)
	for i = 1, AXES do
		w:i8(d.taste[i])
	end
	writeFixedU16Slots(w, d.wants, MAX_WANTS)
	writeFixedU16Slots(w, d.cargo, MAX_CARGO)
	w:u16(d.letterId or 0)
	w:u8(d.beacons or 0)
	w:u32(d.look or 0)
	local bytes = w.bytes
	-- Checksum covers bytes 0..62, i.e. 1-based entries 1..63.
	local sum = Hash.bytes(bytes, 1, 63)
	w:u32(sum)
	w:u8(0)
	assert(w.n == SIZE, "DrifterCodec.encode: produced " .. w.n .. " bytes, expected " .. SIZE)
	return w:build()
end

-- Decode from a byte array at `offset` (1-based, default 1).
-- Returns `(drifter, nil)` or `(nil, message)`. Never throws on bad input --
-- corrupt shards are an operational reality, not a programming error.
function DrifterCodec.decode(bytes, offset, out)
	local base = offset or 1
	if #bytes - base + 1 < SIZE then
		return nil, "DrifterCodec.decode: need " .. SIZE .. " bytes, have " .. (#bytes - base + 1)
	end
	local expected = Hash.bytes(bytes, base, base + 62)
	local stored = bytes[base + 63] + bytes[base + 64] * 256 + bytes[base + 65] * 65536 + bytes[base + 66] * 16777216
	if expected ~= stored then
		return nil, string.format("DrifterCodec.decode: checksum mismatch (computed %d, stored %d)", expected, stored)
	end
	local ok, result = pcall(function()
		local r = Codec.reader(bytes, base)
		local d = out or {}
		d.v = r:u8()
		d.id = r:u64()
		d.owner = r:u64()
		d.epoch = r:i32()
		d.current = r:u8()
		d.class = r:u8()
		d.tier = r:u8()
		d.standing = r:u16()
		d.renown = r:u16()
		d.budget = r:u32()
		d.taste = d.taste or {}
		for i = 1, AXES do
			d.taste[i] = r:i8()
		end
		d.wants = readFixedU16Slots(r, MAX_WANTS, d.wants or {})
		d.cargo = readFixedU16Slots(r, MAX_CARGO, d.cargo or {})
		d.letterId = r:u16()
		d.beacons = r:u8()
		d.look = r:u32()
		return d
	end)
	if not ok then
		return nil, tostring(result)
	end
	return result, nil
end

-- Encode a dense array of drifters into one flat shard blob:
--   u8 version | u16 count | count x 68 bytes | u32 checksum
function DrifterCodec.encodeShard(list, count)
	local n = count or #list
	local w = Codec.writer()
	w:u8(1)
	w:u16(n)
	for i = 1, n do
		local record = DrifterCodec.encode(list[i])
		for j = 1, SIZE do
			w:raw(record[j])
		end
	end
	w:u32(Hash.bytes(w.bytes, 1, w.n))
	return w:build()
end

function DrifterCodec.decodeShard(bytes, out)
	if #bytes < 7 then
		return nil, "DrifterCodec.decodeShard: blob too short"
	end
	local version = bytes[1]
	if version ~= 1 then
		return nil, "DrifterCodec.decodeShard: unknown shard version " .. tostring(version)
	end
	local count = bytes[2] + bytes[3] * 256
	local expectedLen = 3 + count * SIZE + 4
	if #bytes ~= expectedLen then
		return nil, string.format("DrifterCodec.decodeShard: length %d, expected %d for %d records", #bytes, expectedLen, count)
	end
	local body = 3 + count * SIZE
	local computed = Hash.bytes(bytes, 1, body)
	local stored = bytes[body + 1] + bytes[body + 2] * 256 + bytes[body + 3] * 65536 + bytes[body + 4] * 16777216
	if computed ~= stored then
		return nil, "DrifterCodec.decodeShard: shard checksum mismatch"
	end
	local list = out or {}
	for i = 1, count do
		local d, err = DrifterCodec.decode(bytes, 4 + (i - 1) * SIZE)
		if d == nil then
			return nil, string.format("DrifterCodec.decodeShard: record %d: %s", i, tostring(err))
		end
		list[i] = d
	end
	for i = count + 1, #list do
		list[i] = nil
	end
	return list, nil
end

return DrifterCodec
