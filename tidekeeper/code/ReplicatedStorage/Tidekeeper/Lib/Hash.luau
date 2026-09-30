--!nonstrict
-- ReplicatedStorage/Tidekeeper/Lib/Hash (ModuleScript)
--
-- Layer L0: pure. No services, no `game`, no time reads, no yields.
--
-- Stable 32-bit hashing. THIS IS PART OF THE SAVE FORMAT AND THE SIMULATION
-- CONTRACT (doc 04 section 5). Changing any constant or step below changes
-- every seed in the game and every checksum already written to a DataStore.
-- If it ever must change, bump the schema version and migrate.
--
-- Implementation notes
-- --------------------
-- * Only `bit32` is used, never Luau's `&`/`|`/`~` operators. Two reasons:
--   the headless harness runs on a Lua 5.3 VM where those operators have
--   integer (not uint32) semantics, and the luaparse-based syntax checker
--   understands Lua 5.1. `bit32` is exact uint32 in Luau and is shimmed
--   identically in the harness.
-- * 32x32 multiplication is done in 16-bit halves. A naive `a * b` would
--   exceed 2^53 and lose low bits, which would make the hash silently
--   platform-dependent -- the worst possible failure mode for a save format.

local Hash = {}

local floor = math.floor
local bxor = bit32.bxor
local rshift = bit32.rshift

local TWO32 = 4294967296
local FNV_OFFSET = 2166136261
local FNV_PRIME = 16777619

-- Exact (a * b) mod 2^32.
local function mul32(a, b)
	local ah = floor(a / 65536) % 65536
	local al = a % 65536
	local bh = floor(b / 65536) % 65536
	local bl = b % 65536
	-- (ah*2^16 + al)(bh*2^16 + bl) mod 2^32
	--   = (ah*bl + al*bh) * 2^16 + al*bl        (the ah*bh term is >= 2^32)
	local lo = al * bl
	local mid = (ah * bl + al * bh) % 65536
	return (lo + mid * 65536) % TWO32
end
Hash.mul32 = mul32

-- Normalise any finite number to a uint32 word.
local function word(x)
	-- Lua's modulo is floored, so a negative lands on its two's-complement
	-- word exactly the way bit32 would see it.
	return floor(x) % TWO32
end
Hash.word = word

-- MurmurHash3 finalizer. Good avalanche, cheap, and famously stable.
local function fmix32(h)
	h = bxor(h, rshift(h, 16))
	h = mul32(h, 2246822507) -- 0x85ebca6b
	h = bxor(h, rshift(h, 13))
	h = mul32(h, 3266489909) -- 0xc2b2ae35
	h = bxor(h, rshift(h, 16))
	return h
end
Hash.fmix32 = fmix32

-- Absorb one uint32 word into the running state.
local function absorb(h, x)
	h = bxor(h, x)
	h = mul32(h, FNV_PRIME)
	h = bxor(h, rshift(h, 13))
	return h
end

-- Absorb a number that may exceed 32 bits (Drifter ids are up to 2^53). The
-- low word goes in first, then each successive higher word, so `5` and
-- `5 + 2^32` hash differently.
local function absorbWide(h, x)
	local v = floor(x)
	if v < 0 then
		-- Absorb a sentinel first so -5 and 5 cannot collide.
		h = absorb(h, 4294967295)
		v = -v
	end
	while v >= TWO32 do
		h = absorb(h, v % TWO32)
		v = floor(v / TWO32)
	end
	return absorb(h, v)
end

-- The seed function. Up to four stable integers in, one uint32 out.
-- Allocation-free: no varargs, no tables.
function Hash.mix(a, b, c, d)
	local h = FNV_OFFSET
	h = absorbWide(h, a)
	if b ~= nil then
		h = absorbWide(h, b)
	end
	if c ~= nil then
		h = absorbWide(h, c)
	end
	if d ~= nil then
		h = absorbWide(h, d)
	end
	return fmix32(h)
end

-- FNV-1a over a string. Used for content keys and tooling, never for money.
function Hash.string(s)
	local h = FNV_OFFSET
	for i = 1, #s do
		h = bxor(h, string.byte(s, i))
		h = mul32(h, FNV_PRIME)
	end
	return h
end

-- FNV-1a over a 1-based byte array slice [from, to] inclusive. This is the
-- checksum used by DrifterCodec and PostCodec (doc 05 section 4).
function Hash.bytes(bytes, from, to)
	local h = FNV_OFFSET
	for i = from, to do
		h = bxor(h, bytes[i])
		h = mul32(h, FNV_PRIME)
	end
	return h
end

-- Fold a uint32 into [0, n-1] without modulo bias for the small `n` the
-- simulation uses. Rejection is not possible here (we only get one word), so
-- we use the multiply-shift reduction, which is bias-free enough for n <= 2^16
-- and is what the arrival selector relies on.
function Hash.reduce(h, n)
	return floor(h * n / TWO32)
end

return Hash
