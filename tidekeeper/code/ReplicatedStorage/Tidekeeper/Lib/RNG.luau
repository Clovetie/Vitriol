--!nonstrict
-- ReplicatedStorage/Tidekeeper/Lib/RNG (ModuleScript)
--
-- Layer L0: pure. No services, no `game`, no time reads, no yields.
--
-- Seeded, splittable, deterministic random. `math.random` is FORBIDDEN
-- everywhere in this game (doc 04 section 5): its state is global, shared with
-- every other script in the place, and unseedable per-visit.
--
-- Algorithm: SplitMix32. 32-bit state, one uint32 out per step, good
-- statistical quality for simulation noise, and -- critically -- expressible in
-- exact integer arithmetic on an IEEE-754 double, so Studio, the headless
-- harness and a client-side replay all produce identical streams.
--
-- THIS IS PART OF THE SIMULATION CONTRACT. Changing the constants changes every
-- resolved history.

local Hash = require(script.Parent.Hash)

local RNG = {}
RNG.__index = RNG

local floor = math.floor
local bxor = bit32.bxor
local rshift = bit32.rshift
local mul32 = Hash.mul32

local TWO32 = 4294967296
local GOLDEN = 2654435769 -- 0x9E3779B9
local MIX_A = 569420461 -- 0x21f0aaad
local MIX_B = 1935289751 -- 0x735a2d97

-- Bates-4 scale: sd of the sum of four U(0,1) samples is sqrt(4/12).
local BATES_N = 4
local BATES_MEAN = 2.0
local BATES_INV_SD = 1.7320508075688772 -- 1 / sqrt(1/3)

function RNG.new(seed)
	local self = setmetatable({}, RNG)
	self.state = Hash.word(seed or 0)
	self.count = 0
	return self
end

-- Reuse an existing generator instead of allocating a new one. The resolver
-- calls this once per tide epoch, which is how `Visit.resolve` stays
-- allocation-free (doc 04 section 6).
function RNG:reseed(seed)
	self.state = Hash.word(seed or 0)
	self.count = 0
	return self
end

function RNG:clone()
	local other = setmetatable({}, RNG)
	other.state = self.state
	other.count = self.count
	return other
end

-- A child generator whose stream is independent of the parent's but fully
-- determined by (parent state, tag).
function RNG:split(tag)
	return RNG.new(Hash.mix(self.state, tag or 0, self.count))
end

-- One SplitMix32 step -> uint32.
function RNG:nextUInt()
	local z = (self.state + GOLDEN) % TWO32
	self.state = z
	self.count = self.count + 1
	z = mul32(bxor(z, rshift(z, 16)), MIX_A)
	z = mul32(bxor(z, rshift(z, 15)), MIX_B)
	return bxor(z, rshift(z, 15))
end

-- Uniform in [0, 1). Exactly nextUInt() / 2^32, so the value is a dyadic
-- rational and is identical on every IEEE-754 platform.
function RNG:nextNumber()
	return self:nextUInt() / TWO32
end

-- Uniform float in [lo, hi).
function RNG:float(lo, hi)
	return lo + (hi - lo) * self:nextNumber()
end

-- Uniform INTEGER in [lo, hi] inclusive, rejection-sampled so there is no
-- modulo bias. Total: returns lo when the range is empty or inverted.
function RNG:range(lo, hi)
	if hi <= lo then
		return lo
	end
	local span = hi - lo + 1
	-- Largest multiple of span that fits in 2^32; anything at or above it would
	-- bias the low values.
	local limit = TWO32 - (TWO32 % span)
	local v = self:nextUInt()
	while v >= limit do
		v = self:nextUInt()
	end
	return lo + (v % span)
end

-- True with probability `p` (a number in [0, 1]).
function RNG:chance(p)
	return self:nextNumber() < p
end

-- Integer-probability variant: true with probability perMille/1000. Preferred
-- in economy code because the threshold stays an integer.
function RNG:chancePerMille(perMille)
	return self:range(1, 1000) <= perMille
end

-- Approximately normal, mean `mu`, standard deviation `sd`.
--
-- This is a Bates-4 variate, not Box-Muller. That is deliberate: Box-Muller
-- needs `log` and `cos`, whose last bit is libm-dependent, and this value feeds
-- the match score that decides whether a player got paid. Bates-4 uses only
-- +, -, * and /, so it is bit-identical everywhere. It is bounded to
-- mu +/- 3.46*sd, which for the tiny noise term in doc 04 section 4 is a
-- feature, not a limitation.
function RNG:normal(mu, sd)
	local s = 0
	for _ = 1, BATES_N do
		s = s + self:nextNumber()
	end
	return mu + (s - BATES_MEAN) * BATES_INV_SD * sd
end

-- Uniform choice from a dense 1..n array. Returns nil for an empty array.
function RNG:pick(array, n)
	local count = n or #array
	if count <= 0 then
		return nil
	end
	return array[self:range(1, count)]
end

-- In-place Fisher-Yates. Deterministic given the generator state.
function RNG:shuffle(array, n)
	local count = n or #array
	for i = count, 2, -1 do
		local j = self:range(1, i)
		array[i], array[j] = array[j], array[i]
	end
	return array
end

-- Weighted index from a dense array of non-negative integer weights.
-- Returns 0 when every weight is zero.
function RNG:weightedIndex(weights, n)
	local count = n or #weights
	local total = 0
	for i = 1, count do
		total = total + weights[i]
	end
	if total <= 0 then
		return 0
	end
	local roll = self:range(1, total)
	local acc = 0
	for i = 1, count do
		acc = acc + weights[i]
		if roll <= acc then
			return i
		end
	end
	return count
end

RNG.TWO32 = TWO32

return RNG
