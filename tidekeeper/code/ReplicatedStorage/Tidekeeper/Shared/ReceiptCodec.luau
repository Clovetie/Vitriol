--!nonstrict
-- ReplicatedStorage/Tidekeeper/Shared/ReceiptCodec (ModuleScript)
--
-- Layer: Shared wire format. Pure -- no services, no Instances, no yields.
--
-- The 28-byte receipt of doc 05 section 5. A receipt is the other half of the
-- async loop: the host's server resolved a visit, and this is what lands in
-- the visitor's Ledger.
--
--    0  1  v
--    1  8  drifterId
--    9  8  hostId
--   17  4  epoch          int32
--   21  1  outcome        1..5
--   22  4  spent          u32
--   26  1  warmth         i8
--   27  1  flags          bit0 -> a u16 noteId follows, making the record 30 B
--
-- `flags` is the only variable-length part and it exists so that a note can be
-- added later without a schema bump: a reader that finds bit0 clear stops at
-- 28 bytes, and one that finds it set reads two more.

local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local Codec = require(script.Parent.Parent.Lib.Codec)
local Hash = require(script.Parent.Parent.Lib.Hash)

local ReceiptCodec = {}

local BASE_BYTES = GameConfig.RECEIPT_BLOB_BYTES
local NOTE_BYTES = 2
local FLAG_NOTE = 1

ReceiptCodec.BASE_BYTES = BASE_BYTES
ReceiptCodec.FLAG_NOTE = FLAG_NOTE

-- Receipts are delivered through a shard shared by many owners, so a shard
-- that is 200 records long is normal and one that is 20 000 long is a bug.
ReceiptCodec.MAX_SHARD_RECORDS = 400

function ReceiptCodec.byteLength(r)
	if r.noteId ~= nil and r.noteId > 0 then
		return BASE_BYTES + NOTE_BYTES
	end
	return BASE_BYTES
end

function ReceiptCodec.encode(r)
	local w = Codec.writer()
	local flags = 0
	local hasNote = r.noteId ~= nil and r.noteId > 0
	if hasNote then
		flags = bit32.bor(flags, FLAG_NOTE)
	end
	w:u8(r.v)
	w:u64(r.drifterId)
	w:u64(r.hostId)
	w:i32(r.epoch)
	w:u8(r.outcome)
	w:u32(r.spent)
	w:i8(r.warmth)
	w:u8(flags)
	if hasNote then
		w:u16(r.noteId)
	end
	return w:build()
end

-- Reads one receipt starting at `offset` (1-based). Returns (record, nextOffset)
-- or (nil, message).
function ReceiptCodec.decode(bytes, offset, out)
	local start = offset or 1
	if #bytes - start + 1 < BASE_BYTES then
		return nil, "receipt truncated"
	end
	local r = Codec.reader(bytes, start)
	local rec = out or {}
	rec.v = r:u8()
	rec.drifterId = r:u64()
	rec.hostId = r:u64()
	rec.epoch = r:i32()
	rec.outcome = r:u8()
	rec.spent = r:u32()
	rec.warmth = r:i8()
	rec.flags = r:u8()
	if bit32.band(rec.flags, FLAG_NOTE) ~= 0 then
		if #bytes - (start + BASE_BYTES) + 1 < NOTE_BYTES then
			return nil, "receipt note truncated"
		end
		rec.noteId = r:u16()
	else
		rec.noteId = 0
	end
	if rec.outcome < 1 or rec.outcome > 5 then
		return nil, "receipt outcome out of range"
	end
	return rec, r:pos()
end

-- A shard is `count:u16` then the records back to back, then an FNV-1a of
-- everything before it. Same shape as the drifter shard, for the same reason:
-- a shard that has been migrated and corrupted should be detectable without
-- being parseable.
function ReceiptCodec.encodeShard(list, count)
	local n = count or #list
	if n > ReceiptCodec.MAX_SHARD_RECORDS then
		error("ReceiptCodec.encodeShard: " .. tostring(n) .. " records exceeds the shard cap")
	end
	local w = Codec.writer()
	w:u16(n)
	for i = 1, n do
		local enc = ReceiptCodec.encode(list[i])
		w:bytes_(enc, #enc)
	end
	local body = w:build()
	local out = Codec.writer()
	out:bytes_(body, #body)
	out:u32(Hash.bytes(body, 1, #body))
	return out:build()
end

-- Returns (list, count) or (nil, message).
function ReceiptCodec.decodeShard(bytes, out)
	local total = #bytes
	if total < 6 then
		return nil, "receipt shard too short"
	end
	local bodyLen = total - 4
	local expect = Hash.bytes(bytes, 1, bodyLen)
	local tail = Codec.reader(bytes, bodyLen + 1)
	local stored = tail:u32()
	if stored ~= expect then
		return nil, "receipt shard checksum mismatch"
	end
	local head = Codec.reader(bytes, 1)
	local n = head:u16()
	local list = out or {}
	local offset = 3
	for i = 1, n do
		local rec, nextOffset = ReceiptCodec.decode(bytes, offset, nil)
		if rec == nil then
			return nil, "record " .. tostring(i) .. ": " .. tostring(nextOffset)
		end
		list[i] = rec
		offset = nextOffset
	end
	return list, n
end

return ReceiptCodec
