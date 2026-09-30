--!nonstrict
-- ReplicatedStorage/Tidekeeper/Lib/Codec (ModuleScript)
--
-- Layer L0: pure. No services, no `game`, no time reads, no yields.
--
-- Little-endian byte-array primitives: the substrate every wire format in
-- doc 05 is built from.
--
-- WHY A BYTE ARRAY AND NOT `buffer`
-- ---------------------------------
-- Doc 05 section 3.1 says the persisted representation is `buffer` + manual bit
-- packing + base64. That is still true, but the *packing* is what needs to be
-- pure, testable and layer-0. So the codec produces and consumes a 1-based
-- array of integers in [0, 255], and the single conversion to `buffer` lives in
-- the DataStore adapter at L1 (iteration 3), where the platform types belong.
-- This keeps the whole save format unit-testable with zero Roblox surface, and
-- it is the same split the sibling project used for its replicator.
--
-- Every writer validates. A codec that silently truncates an out-of-range value
-- is a codec that corrupts saves six months later.

local MathExt = require(script.Parent.MathExt)

local Codec = {}

local floor = math.floor
local char = string.char
local byte = string.byte
local concat = table.concat

local TWO32 = 4294967296

-- ---------------------------------------------------------------- Writer

local Writer = {}
Writer.__index = Writer

function Codec.writer(initial)
	local self = setmetatable({}, Writer)
	self.bytes = initial or {}
	self.n = 0
	return self
end

function Writer:len()
	return self.n
end

function Writer:raw(v)
	self.n = self.n + 1
	self.bytes[self.n] = v
	return self
end

local function requireInt(v, lo, hi, what)
	if not MathExt.isInteger(v) then
		error(string.format("Codec: %s expects an integer, got %s", what, tostring(v)), 0)
	end
	if v < lo or v > hi then
		error(string.format("Codec: %s out of range [%d, %d]: %d", what, lo, hi, v), 0)
	end
end

function Writer:u8(v)
	requireInt(v, 0, 255, "u8")
	return self:raw(v)
end

function Writer:i8(v)
	requireInt(v, -128, 127, "i8")
	if v < 0 then
		v = v + 256
	end
	return self:raw(v)
end

function Writer:u16(v)
	requireInt(v, 0, 65535, "u16")
	self:raw(v % 256)
	return self:raw(floor(v / 256))
end

function Writer:i16(v)
	requireInt(v, -32768, 32767, "i16")
	if v < 0 then
		v = v + 65536
	end
	self:raw(v % 256)
	return self:raw(floor(v / 256))
end

function Writer:u32(v)
	requireInt(v, 0, 4294967295, "u32")
	for _ = 1, 4 do
		self:raw(v % 256)
		v = floor(v / 256)
	end
	return self
end

function Writer:i32(v)
	requireInt(v, -2147483648, 2147483647, "i32")
	if v < 0 then
		v = v + TWO32
	end
	for _ = 1, 4 do
		self:raw(v % 256)
		v = floor(v / 256)
	end
	return self
end

-- 48-bit unsigned. Used for the visitor ring, where a full 64 bits is waste.
function Writer:u48(v)
	requireInt(v, 0, 281474976710655, "u48")
	for _ = 1, 6 do
		self:raw(v % 256)
		v = floor(v / 256)
	end
	return self
end

-- 64-bit unsigned on the wire, but the VALUE must stay below 2^53 so it is
-- exactly representable in a Luau number. The writer enforces that rather than
-- letting a silent rounding error reach a DataStore.
function Writer:u64(v)
	requireInt(v, 0, 9007199254740992, "u64 (values must be < 2^53 to survive a Luau number)")
	for _ = 1, 8 do
		self:raw(v % 256)
		v = floor(v / 256)
	end
	return self
end

-- LEB128 unsigned varint. Compact for the many small counts in a post blob.
function Writer:varint(v)
	requireInt(v, 0, 9007199254740992, "varint")
	while v >= 128 do
		self:raw((v % 128) + 128)
		v = floor(v / 128)
	end
	return self:raw(v)
end

function Writer:zeros(count)
	for _ = 1, count do
		self:raw(0)
	end
	return self
end

function Writer:bytes_(arr, count)
	local n = count or #arr
	for i = 1, n do
		self:u8(arr[i])
	end
	return self
end

-- Overwrite a previously written byte (for back-patching lengths/checksums).
function Writer:patchU32(offset1, v)
	requireInt(v, 0, 4294967295, "patchU32")
	for i = 0, 3 do
		self.bytes[offset1 + i] = v % 256
		v = floor(v / 256)
	end
	return self
end

function Writer:build()
	local out = {}
	for i = 1, self.n do
		out[i] = self.bytes[i]
	end
	return out
end

-- ---------------------------------------------------------------- Reader

local Reader = {}
Reader.__index = Reader

function Codec.reader(bytes, offset)
	local self = setmetatable({}, Reader)
	self.bytes = bytes
	self.p = offset or 1
	self.n = #bytes
	return self
end

function Reader:pos()
	return self.p
end

function Reader:seek(p)
	self.p = p
	return self
end

function Reader:remaining()
	return self.n - self.p + 1
end

function Reader:raw()
	if self.p > self.n then
		error(string.format("Codec: read past end at offset %d of %d", self.p, self.n), 0)
	end
	local v = self.bytes[self.p]
	if v == nil or v < 0 or v > 255 or v ~= floor(v) then
		error(string.format("Codec: byte %d is not a byte: %s", self.p, tostring(v)), 0)
	end
	self.p = self.p + 1
	return v
end

Reader.u8 = Reader.raw

function Reader:i8()
	local v = self:raw()
	if v >= 128 then
		return v - 256
	end
	return v
end

function Reader:u16()
	local a = self:raw()
	local b = self:raw()
	return a + b * 256
end

function Reader:i16()
	local v = self:u16()
	if v >= 32768 then
		return v - 65536
	end
	return v
end

function Reader:u32()
	local v = 0
	local scale = 1
	for _ = 1, 4 do
		v = v + self:raw() * scale
		scale = scale * 256
	end
	return v
end

function Reader:i32()
	local v = self:u32()
	if v >= 2147483648 then
		return v - TWO32
	end
	return v
end

function Reader:u48()
	local v = 0
	local scale = 1
	for _ = 1, 6 do
		v = v + self:raw() * scale
		scale = scale * 256
	end
	return v
end

function Reader:u64()
	local v = 0
	local scale = 1
	for _ = 1, 8 do
		v = v + self:raw() * scale
		scale = scale * 256
	end
	return v
end

function Reader:varint()
	local v = 0
	local scale = 1
	while true do
		local b = self:raw()
		v = v + (b % 128) * scale
		if b < 128 then
			return v
		end
		scale = scale * 128
	end
end

function Reader:bytes_(count, out)
	local dest = out or {}
	for i = 1, count do
		dest[i] = self:raw()
	end
	return dest
end

-- ---------------------------------------------------------------- base64

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INV = {}
for i = 1, 64 do
	B64_INV[byte(B64, i)] = i - 1
end

function Codec.base64Encode(bytes, count)
	local n = count or #bytes
	local out = {}
	local w = 0
	local i = 1
	while i + 2 <= n do
		local a, b, c = bytes[i], bytes[i + 1], bytes[i + 2]
		local v = a * 65536 + b * 256 + c
		w = w + 1
		out[w] = char(
			byte(B64, floor(v / 262144) + 1),
			byte(B64, (floor(v / 4096) % 64) + 1),
			byte(B64, (floor(v / 64) % 64) + 1),
			byte(B64, (v % 64) + 1)
		)
		i = i + 3
	end
	local rest = n - i + 1
	if rest == 1 then
		local v = bytes[i] * 16
		w = w + 1
		out[w] = char(byte(B64, floor(v / 64) + 1), byte(B64, (v % 64) + 1)) .. "=="
	elseif rest == 2 then
		local v = bytes[i] * 1024 + bytes[i + 1] * 4
		w = w + 1
		out[w] = char(byte(B64, floor(v / 4096) + 1), byte(B64, (floor(v / 64) % 64) + 1), byte(B64, (v % 64) + 1))
			.. "="
	end
	return concat(out)
end

function Codec.base64Decode(str)
	local out = {}
	local n = 0
	local acc = 0
	local bits = 0
	for i = 1, #str do
		local ch = byte(str, i)
		local v = B64_INV[ch]
		if v ~= nil then
			acc = acc * 64 + v
			bits = bits + 6
			if bits >= 8 then
				bits = bits - 8
				local shift = 2 ^ bits
				local b = floor(acc / shift)
				acc = acc - b * shift
				n = n + 1
				out[n] = b
			end
		elseif ch ~= 61 and ch ~= 10 and ch ~= 13 and ch ~= 32 then
			error(string.format("Codec: invalid base64 character %q at %d", string.sub(str, i, i), i), 0)
		end
	end
	return out
end

function Codec.toHex(bytes, count)
	local n = count or #bytes
	local out = {}
	for i = 1, n do
		out[i] = string.format("%02x", bytes[i])
	end
	return concat(out)
end

function Codec.equal(a, b)
	local na = #a
	if na ~= #b then
		return false
	end
	for i = 1, na do
		if a[i] ~= b[i] then
			return false
		end
	end
	return true
end

Codec.Writer = Writer
Codec.Reader = Reader

return Codec
