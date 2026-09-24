--!strict
-- RNG.luau
-- Location: ReplicatedStorage > QTE > Lib > RNG (ModuleScript)
--           Vendored copy (source: Vitriol, iteration 3), unmodified. The QTE
--           folder is self-contained on purpose: drop it into a place on its own
--           and nothing else has to come with it.
-- Purpose:  Deterministic, seedable pseudo-random number generator.
--           EVERY random decision in the QTE package comes from an RNG instance,
--           so a QTE sequence is reproducible from a seed (the test suite relies
--           on it: same seed, same tasks) and nothing touches math.random.
--           Pure: no services, no Instances, no yields.
-- Requires: (none)
-- Used by:  Lib/Genetics, Creature/Brain/Policy, EvolutionService, tests

-- xorshift32 with a shift/XOR-only seed mixer (see mixSeed).
-- 32-bit state, ~2^32 period, plenty for gameplay; chosen because it is tiny,
-- fast, allocation-free and trivially reproducible. Not cryptographic.

local MASK32 = 0xFFFFFFFF
local INV32 = 1 / 4294967296
local TAU = math.pi * 2

local RNG = {}
RNG.__index = RNG

-- Seed mixer: a shift/XOR-only avalanche (no 32-bit multiply).
--
-- The usual splitmix32 mixer multiplies by large odd constants and masks, which
-- is exact in Luau's 64-bit integers but NOT on VMs whose integer math is
-- double-based (the product overflows 2^53 and loses precision). Shifts and XOR
-- are exact on both, so the seed mixer avoids multiplication entirely. Cost is
-- irrelevant: this runs once per RNG, not per draw.
local function mixSeed(seed: number): number
	local z = (math.floor(seed) + 0x9E3779B9) & MASK32
	for _ = 1, 8 do
		z = (z ~ (z << 13)) & MASK32
		z = z ~ (z >> 17)
		z = (z ~ (z << 5)) & MASK32
		z = (z + 0x9E3779B9) & MASK32
	end
	-- xorshift32 has an absorbing state at 0; never allow it.
	if z == 0 then
		z = 0x9E3779B9
	end
	return z
end

-- new(seed) -> RNG
function RNG.new(seed: number)
	local self = setmetatable({}, RNG)
	self.state = mixSeed(seed or 1)
	self.calls = 0
	self._spare = nil :: number?
	return self
end

-- Raw 32-bit pattern.
--
-- In Luau this is always in [0, 2^32-1]. On a VM whose bitwise ops use 32-bit
-- signed semantics (the fengari test harness) the same pattern reads as a
-- negative number, so callers that need a uniform float must go through next(),
-- which normalises in the float domain where the conversion is always exact.
function RNG:nextInt32(): number
	local x = self.state
	x = (x ~ (x << 13)) & MASK32
	x = x ~ (x >> 17)
	x = (x ~ (x << 5)) & MASK32
	self.state = x
	self.calls += 1
	return x
end

-- Uniform float in [0, 1).
function RNG:next(): number
	local v = self:nextInt32() * INV32
	if v < 0 then
		-- Only reachable on VMs with 32-bit signed bitwise ops; folding the
		-- negative half up into [0.5, 1) is a bijection, so the output stays
		-- uniform over [0, 1).
		v += 1
	end
	return v
end

-- Uniform float in [a, b).
function RNG:range(a: number, b: number): number
	return a + (b - a) * self:next()
end

-- Uniform integer in [a, b] inclusive.
function RNG:int(a: number, b: number): number
	if b < a then
		return a
	end
	local span = b - a + 1
	local v = a + math.floor(self:next() * span)
	if v > b then
		v = b
	end
	return v
end

-- 50/50 boolean with a bias.
function RNG:chance(p: number): boolean
	return self:next() < p
end

-- Uniform element from an array (1-based).
function RNG:pick(list: {any}): any
	local n = #list
	if n == 0 then
		return nil
	end
	return list[self:int(1, n)]
end

-- Weighted pick. `list` is an array of {weight = number, ...} entries.
-- Returns the entry itself, or nil for an empty/zero-weight list.
function RNG:weighted(list: {any}): any
	local total = 0
	for i = 1, #list do
		local w = list[i].weight
		if w and w > 0 then
			total += w
		end
	end
	if total <= 0 then
		return nil
	end
	local roll = self:next() * total
	local acc = 0
	for i = 1, #list do
		local w = list[i].weight
		if w and w > 0 then
			acc += w
			if roll <= acc then
				return list[i]
			end
		end
	end
	return list[#list]
end

-- Standard normal via Box-Muller, with the spare cached (one sqrt per two draws).
function RNG:gaussian(): number
	local spare = self._spare
	if spare then
		self._spare = nil
		return spare
	end
	local u1 = self:next()
	if u1 < 1e-12 then
		u1 = 1e-12
	end
	local u2 = self:next()
	local mag = math.sqrt(-2 * math.log(u1))
	local a = mag * math.cos(TAU * u2)
	local b = mag * math.sin(TAU * u2)
	self._spare = b
	return a
end

-- Gaussian with mean and standard deviation, clamped to [lo, hi].
function RNG:gaussianClamped(mean: number, sd: number, lo: number, hi: number): number
	local v = mean + self:gaussian() * sd
	if v < lo then
		v = lo
	elseif v > hi then
		v = hi
	end
	return v
end

-- Three independent gaussians (for positional error). Returns 3 values.
function RNG:gaussian3(): number, number, number
	return self:gaussian(), self:gaussian(), self:gaussian()
end

-- Independent child stream. Use one per creature so their streams never correlate.
function RNG:fork(): any
	return RNG.new(self:nextInt32())
end

-- Snapshot for save/debug.
function RNG:serialize(): {state: number, calls: number}
	return { state = self.state, calls = self.calls }
end

function RNG.deserialize(data: {state: number, calls: number?}): any
	local self = setmetatable({}, RNG)
	self.state = data.state & MASK32
	if self.state == 0 then
		self.state = 0x9E3779B9
	end
	self.calls = data.calls or 0
	self._spare = nil
	return self
end

return RNG
