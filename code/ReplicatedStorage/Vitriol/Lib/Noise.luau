--!strict
-- Noise.luau
-- Location: ReplicatedStorage > Vitriol > Lib > Noise  (ModuleScript)
-- Purpose:  Deterministic value noise for organic secondary motion (tendril idle
--           life, sway) and for the scent/terrain fields in Shared/NoiseField.
--           MUST be seeded and allocation-free in the hot path, so the server and
--           every client agree without exchanging anything
--           (docs/03-MONSTER-TECH.md §3.3).
--
-- WHY A PERMUTATION TABLE AND NOT AN ARITHMETIC HASH
--   The obvious implementation - xorshift32 used as a hash of the lattice index -
--   is wrong, and it was wrong here first. xorshift32 is a *state transition*,
--   not a hash: fed the small sequential integers a lattice produces, its high
--   bits never fill, and every output lands in a narrow band. Measured on the
--   broken version: value1(i) for i = 0..63 returned 0.074226..0.081643, i.e. a
--   field with a total dynamic range of 0.007 instead of 1.0. That is not noise,
--   it is a near-constant, and it would have made every tendril twitch in unison.
--   The same clustering appears in Luau and in the fengari test harness, so it is
--   a design bug, not a VM artifact.
--
--   The fix is the one Perlin used: a seeded permutation of 0..255, indexed by
--   the coordinate bytes. Cost is three array reads per lattice point - cheaper
--   than the eight xorshift rounds a well-mixed arithmetic hash would need - and
--   the distribution is uniform by construction, because it IS a permutation.
--
--   Still no large multiplies anywhere: a 32-bit multiply overflows 2^53 on VMs
--   with double-based integer math. The only multiplication is `byte * 256` on a
--   value <= 255 (max 65280), which is exact everywhere. Same constraint as
--   Lib/RNG.
-- Pure: no services, no Instances, no yields, no math.random.
-- Requires: (none)
-- Used by:  Creature/Body/TendrilRig, Client/LocalRigDriver, Shared/NoiseField

local MASK32 = 0xFFFFFFFF
local LIMIT_HI = 1073741823 -- 2^30 - 1, keeps lattice indices safely integral
local LIMIT_LO = -1073741824
local PERM_SIZE = 256
local PERM_MASK = 255
local INV16 = 1 / 65536 -- hash values are 16-bit
local INV32 = 1 / 4294967296 -- for normalising the 32-bit xorshift draw
local band, bxor, lshift, rshift = bit32.band, bit32.bxor, bit32.lshift, bit32.rshift

local Noise = {}
Noise.__index = Noise

-- Floor, clamped into a range that is guaranteed to convert to an integer.
local function lattice(v: number): number
	local i = math.floor(v)
	if i > LIMIT_HI then
		return LIMIT_HI
	elseif i < LIMIT_LO then
		return LIMIT_LO
	end
	return i
end

local function smooth(t: number): number
	return t * t * (3 - 2 * t)
end

-- buildPermutation(seed) -> table of 512 bytes
--
-- Fisher-Yates shuffle of 0..255, driven by a chained xorshift32. Chaining is
-- exactly what makes the xorshift acceptable HERE and unacceptable as a direct
-- lattice hash: each draw depends on the whole history, so the values spread
-- across the full 32 bits instead of clustering around the seed's magnitude.
--
-- The table is doubled to 512 entries so that a sum of two bytes (max 510) is
-- always a valid index, which is what lets the hash skip a mask per step.
local function buildPermutation(seed: number): any
	local p = {}
	for i = 0, PERM_SIZE - 1 do
		p[i] = i
	end

	local state = band(math.floor(seed) + 0x9E3779B9, MASK32)
	if state == 0 then
		state = 0x9E3779B9
	end

	for i = PERM_SIZE - 1, 1, -1 do
		state = band(bxor(state, lshift(state, 13)), MASK32)
		state = bxor(state, rshift(state, 17))
		state = band(bxor(state, lshift(state, 5)), MASK32)

		-- Normalise to [0, 1) in the FLOAT domain. On VMs whose bitwise ops are
		-- 32-bit signed the xorshift pattern reads negative, and folding that half
		-- up onto [0, 2^32) is a bijection. `u` is a float and is never fed back
		-- into a bitwise op - hence the separate variable from `state`.
		--
		-- Scale ONCE. An earlier version pre-multiplied by 1/65536 and then
		-- divided by 2^32, dividing by 2^48 in total: the draw collapsed to ~0,
		-- Fisher-Yates swapped with index 0 on nearly every iteration, and the
		-- "permutation" was a fixed near-reversal whose first 64 entries averaged
		-- 0.64 instead of 0.50.
		local u = state
		if u < 0 then
			u = u + 4294967296
		end
		local j = math.floor(u * INV32 * (i + 1))
		if j > i then
			j = i
		elseif j < 0 then
			j = 0
		end

		local swap = p[i]
		p[i] = p[j]
		p[j] = swap
	end

	for i = 0, PERM_SIZE - 1 do
		p[i + PERM_SIZE] = p[i]
	end
	return p
end

-- Hash functions. Each returns 16 bits (0..65535) so a smooth field is not
-- visibly banded - 256 levels across a full period shows up as contour lines on
-- a large scent cloud, 65536 does not.
local function hash1(p: any, sb: number, i: number): number
	local a = p[band(i, PERM_MASK)]
	local b = p[a + sb]
	return b * 256 + p[band(b + a, PERM_MASK)]
end

local function hash2(p: any, sb: number, i: number, j: number): number
	local a = p[band(i, PERM_MASK)]
	local b = p[a + band(j, PERM_MASK)]
	local c = p[b + sb]
	return c * 256 + p[band(c + a, PERM_MASK)]
end

local function hash3(p: any, sb: number, i: number, j: number, k: number): number
	local a = p[band(i, PERM_MASK)]
	local b = p[a + band(j, PERM_MASK)]
	local c = p[b + band(k, PERM_MASK)]
	local d = p[c + sb]
	return d * 256 + p[band(d + a, PERM_MASK)]
end

-- new(seed) -> Noise
-- Builds a 512-entry permutation table: 512 allocations, once per instance. Do
-- not construct per frame; rigs and fields own one instance each.
function Noise.new(seed: number?)
	local self = setmetatable({}, Noise)
	local s = band(seed or 0, MASK32)
	self.seed = s
	self.perm = buildPermutation(s)
	-- Three decorrelated seed bytes, for v3's independent axes.
	self.sbA = band(s, PERM_MASK)
	self.sbB = band(s + 71, PERM_MASK)
	self.sbC = band(s + 157, PERM_MASK)
	return self
end

-- sample1(p, sb, x) -> number in [0, 1)
-- Smooth 1D sample with an explicit seed byte, so v3's three axes can share one
-- code path and stay C1-continuous at the lattice boundaries (the value at f=1
-- of one cell is exactly the value at f=0 of the next, because both read the
-- hash of the same lattice index). Sampling a raw hash instead would give a step
-- function, which on a tendril reads as a twitch rather than as drift.
local function sample1(p: any, sb: number, x: number): number
	local i0 = lattice(x)
	local f = x - i0
	if f < 0 then
		f = 0
	elseif f > 1 then
		f = 1
	end
	local a = hash1(p, sb, i0) * INV16
	local b = hash1(p, sb, i0 + 1) * INV16
	return a + (b - a) * smooth(f)
end

-- value1(noise, x) -> number in [0, 1)
function Noise:value1(x: number): number
	return sample1(self.perm, self.sbA, x)
end

-- value3(noise, x, y, z) -> number in [0, 1)
-- Trilinear interpolation over the 8 surrounding lattice corners.
function Noise:value3(x: number, y: number, z: number): number
	local i0, j0, k0 = lattice(x), lattice(y), lattice(z)
	local fx, fy, fz = x - i0, y - j0, z - k0
	if fx < 0 then
		fx = 0
	elseif fx > 1 then
		fx = 1
	end
	if fy < 0 then
		fy = 0
	elseif fy > 1 then
		fy = 1
	end
	if fz < 0 then
		fz = 0
	elseif fz > 1 then
		fz = 1
	end

	local u, v, w = smooth(fx), smooth(fy), smooth(fz)
	local p = self.perm
	local sb = self.sbA

	local c000 = hash3(p, sb, i0, j0, k0) * INV16
	local c100 = hash3(p, sb, i0 + 1, j0, k0) * INV16
	local c010 = hash3(p, sb, i0, j0 + 1, k0) * INV16
	local c110 = hash3(p, sb, i0 + 1, j0 + 1, k0) * INV16
	local c001 = hash3(p, sb, i0, j0, k0 + 1) * INV16
	local c101 = hash3(p, sb, i0 + 1, j0, k0 + 1) * INV16
	local c011 = hash3(p, sb, i0, j0 + 1, k0 + 1) * INV16
	local c111 = hash3(p, sb, i0 + 1, j0 + 1, k0 + 1) * INV16

	local x00 = c000 + (c100 - c000) * u
	local x10 = c010 + (c110 - c010) * u
	local x01 = c001 + (c101 - c001) * u
	local x11 = c011 + (c111 - c011) * u

	local y0 = x00 + (x10 - x00) * v
	local y1 = x01 + (x11 - x01) * v
	return y0 + (y1 - y0) * w
end

-- v3(noise, seedOffset, t) -> x, y, z in [-1, 1]
-- The per-tendril idle offset. Three decorrelated 1D samples at slightly
-- different rates and seed bytes so the motion does not read as one oscillator.
function Noise:v3(seedOffset: number, t: number): (number, number, number)
	local p = self.perm
	local a = sample1(p, self.sbA, t + seedOffset)
	local b = sample1(p, self.sbB, t * 1.13 + seedOffset + 131.7)
	local c = sample1(p, self.sbC, t * 0.87 + seedOffset + 271.3)
	return a * 2 - 1, b * 2 - 1, c * 2 - 1
end

-- fbm1(noise, x, octaves) -> number in [0, 1)
-- Fractal Brownian motion, for layered organic drift. Normalised so the output
-- range does not grow with the octave count.
function Noise:fbm1(x: number, octaves: number?): number
	local oct = octaves or 3
	local sum = 0
	local amp = 0.5
	local norm = 0
	local freq = 1
	for _ = 1, oct do
		sum += self:value1(x * freq) * amp
		norm += amp
		amp *= 0.5
		freq *= 2
	end
	if norm <= 0 then
		return 0
	end
	return sum / norm
end

return Noise
