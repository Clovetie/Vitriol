--!strict
-- NoiseField.luau
-- Location: ReplicatedStorage > Vitriol > Shared > NoiseField  (ModuleScript)
-- Purpose:  The creature's world model of "what is making a disturbance where".
--           One SpatialHash per sensory channel, holding decaying impulses.
--           A single call answers "how loud is it HERE, on THIS channel, RIGHT
--           NOW?" - which is the question every sense asks
--           (docs/02-MONSTER-DESIGN.md §2).
--
--           Shared, not server-only: the player's Attune UI samples the same field
--           (docs/00-VISION.md §5.1.1), so both read identical numbers instead of
--           the UI inventing its own approximation.
--
--           This module never does a physics query. Occlusion raycasts, wind
--           advection and acuity thresholds belong to the sense modules; NoiseField
--           only stores and sums impulses, which keeps it allocation-free,
--           parallel-safe and unit-testable.
-- Requires: Lib/SpatialHash, Lib/Tables
-- Used by:  Services/NoiseService, Creature/Senses/*, Client/AttuneController

local SpatialHash = require(script.Parent.Parent.Lib.SpatialHash)
local Tables = require(script.Parent.Parent.Lib.Tables)

local NoiseField = {}
NoiseField.__index = NoiseField

-- docs/02 §2. Half-lives are the ONLY thing that separates the channels here:
-- PRESSURE is gone almost instantly (it is a proximity sense), SCENT lingers for
-- most of a night (that is what makes blood trails worth following).
NoiseField.DEFAULT_HALFLIFE = {
	VIBRATION = 0.9,
	AIR = 0.45,
	SCENT = 26,
	THERMAL = 3.5,
	EM = 1.2,
	PRESSURE = 0.25,
}

NoiseField.CHANNELS = { "VIBRATION", "AIR", "SCENT", "THERMAL", "EM", "PRESSURE" }

local DEFAULTS = {
	cellSize = 16,
	preallocPerChannel = 32,
}

-- Number of half-lives after which an impulse is treated as gone.
-- log2(1 / 0.005): the age at which an impulse has decayed to 0.5% of its
-- original intensity.
local DECAY_CUTOFF_MULT = math.log(200) / math.log(2)

-- new(cfg?) -> NoiseField
-- cfg: { Channels = {...}, Halflife = { [channel] = seconds }, CellSize = n,
--        PreallocPerChannel = n }
function NoiseField.new(cfg: any?)
	local c = cfg or {}
	local self = setmetatable({}, NoiseField)
	self.channels = c.Channels or NoiseField.CHANNELS
	self.halflife = {}
	local hl = c.Halflife or NoiseField.DEFAULT_HALFLIFE
	for i = 1, #self.channels do
		local ch = self.channels[i]
		self.halflife[ch] = hl[ch] or 1
	end

	local cell = c.CellSize or DEFAULTS.cellSize
	local pre = c.PreallocPerChannel or DEFAULTS.preallocPerChannel
	self.hashes = {}
	self.nextId = {}
	self.pools = {}
	for i = 1, #self.channels do
		local ch = self.channels[i]
		self.hashes[ch] = SpatialHash.new(cell)
		self.nextId[ch] = 0
		self.pools[ch] = Tables.newPool(function()
			return {}
		end, pre)
	end

	-- Reusable output table for sampleAll, so a full 6-channel sweep allocates
	-- nothing. Callers must read it before the next call.
	self.out = {}
	return self
end

-- hasChannel(field, channel) -> boolean
function NoiseField:hasChannel(channel: any): boolean
	return self.hashes[channel] ~= nil
end

-- emit(field, channel, x, y, z, intensity, now, halflifeOverride?) -> id?
-- Returns the impulse id, or nil for an unknown channel / non-positive intensity
-- (a silent event must not create an entry that will be sampled forever).
function NoiseField:emit(channel: any, x: number, y: number, z: number, intensity: number, now: number, halflifeOverride: number?): any
	local hash = self.hashes[channel]
	if hash == nil or intensity == nil or intensity <= 0 then
		return nil
	end

	local entry = self.pools[channel]:get()
	entry.intensity = intensity
	entry.time = now or 0
	entry.halflife = halflifeOverride or self.halflife[channel]

	local nextId = self.nextId[channel] + 1
	self.nextId[channel] = nextId
	hash:insert(nextId, x, y, z, entry)
	return nextId
end

-- remove(field, channel, id) -> boolean
-- Used when an emitter is destroyed (a generator switched off stops being an EM
-- source immediately; waiting for decay would leave a phantom).
function NoiseField:remove(channel: any, id: any): boolean
	local hash = self.hashes[channel]
	if hash == nil then
		return false
	end
	local entry = hash:get(id)
	if entry == nil then
		return false
	end
	hash:remove(id)
	self.pools[channel]:release(entry)
	return true
end

-- sample(field, channel, x, y, z, radius, now) -> number
function NoiseField:sample(channel: any, x: number, y: number, z: number, radius: number, now: number): number
	local hash = self.hashes[channel]
	if hash == nil then
		return 0
	end
	return hash:sampleDecay(x, y, z, radius, now)
end

-- sampleAll(field, x, y, z, radius, now, out?) -> { [channel] = number }
-- Writes into `out` (default: the shared table) and returns it. Unknown channels
-- get 0 rather than nil so callers can index unconditionally.
function NoiseField:sampleAll(x: number, y: number, z: number, radius: number, now: number, out: any?): any
	local o = out or self.out
	for i = 1, #self.channels do
		local ch = self.channels[i]
		o[ch] = self.hashes[ch]:sampleDecay(x, y, z, radius, now)
	end
	return o
end

-- loudestChannel(field, x, y, z, radius, now) -> channel?, intensity
-- Cheap "which sense should wake up?" probe used by the sense scheduler so a
-- creature does not run all six sense bodies when nothing is happening.
function NoiseField:loudestChannel(x: number, y: number, z: number, radius: number, now: number): any, number
	local bestChannel = nil
	local bestValue = 0
	for i = 1, #self.channels do
		local ch = self.channels[i]
		local v = self.hashes[ch]:sampleDecay(x, y, z, radius, now)
		if v > bestValue then
			bestValue = v
			bestChannel = ch
		end
	end
	return bestChannel, bestValue
end

-- prune(field, now) -> number removed
-- Drops fully-decayed impulses and returns their entries to the pool. Slow
-- cadence only (docs/01-ARCHITECTURE.md §4).
--
-- An impulse is worth keeping while it could still be heard at the longest sense
-- range. Below 0.5% of its original intensity it never will be, and 0.5% is
-- reached at age = halflife * log2(200) ~= halflife * 7.644. Deriving the cut-off
-- from the half-life means one prune rule serves every channel: PRESSURE
-- (0.25 s half-life) is swept every ~2 s of signal age, SCENT (26 s) after ~199 s.
function NoiseField:prune(now: number): number
	local removed = 0
	for i = 1, #self.channels do
		local ch = self.channels[i]
		local pool = self.pools[ch]
		local maxAge = self.halflife[ch] * DECAY_CUTOFF_MULT
		-- Assigned before accumulating rather than `removed += ...:prune(...)`:
		-- both tools/check-syntax.js and the smoke harness expand `+=` on a single
		-- line, and a multi-line closure as the right-hand side defeats that.
		local swept = self.hashes[ch]:prune(now, maxAge, function(_, entry)
			if entry then
				pool:release(entry)
			end
		end)
		removed += swept
	end
	return removed
end

-- count(field, channel?) -> number
function NoiseField:count(channel: any?): number
	if channel ~= nil then
		local hash = self.hashes[channel]
		if hash == nil then
			return 0
		end
		return hash:count()
	end
	local total = 0
	for i = 1, #self.channels do
		total += self.hashes[self.channels[i]]:count()
	end
	return total
end

-- clear(field) -> ()
function NoiseField:clear(): ()
	for i = 1, #self.channels do
		local ch = self.channels[i]
		self.hashes[ch]:clear()
		self.pools[ch] = Tables.newPool(function()
			return {}
		end, 0)
		self.nextId[ch] = 0
	end
end

return NoiseField
