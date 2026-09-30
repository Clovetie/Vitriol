--!nonstrict
-- ReplicatedStorage/Tidekeeper/Domain/Standing (ModuleScript)
--
-- Layer L2: pure. No services, no Instances, no yields, no time reads.
--
-- Reputation maths (doc 06 section 2). Standing is per-Current, integer,
-- 0..65535, and decays toward a BAND FLOOR rather than toward zero.
--
-- The band floor is the most important retention decision in the economy: a
-- fortnight away costs progress but can never erase an achievement. Every
-- function here preserves that property, and the harness asserts it directly.

local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)

local Standing = {}

local floor = math.floor

local BANDS = EconomyConfig.STANDING_BANDS
local BAND_COUNT = #BANDS
local MAX = EconomyConfig.STANDING_MAX
local DECAY = EconomyConfig.STANDING_DECAY_PER_MILLE

Standing.MAX = MAX
Standing.BAND_COUNT = BAND_COUNT

-- 0 when below the first band, else the index of the highest band reached.
function Standing.bandOf(value)
	local band = 0
	for i = 1, BAND_COUNT do
		if value >= BANDS[i] then
			band = i
		end
	end
	return band
end

-- The value Standing can never fall below, given that `value` has been reached.
function Standing.floorOf(value)
	local band = Standing.bandOf(value)
	if band == 0 then
		return 0
	end
	return BANDS[band]
end

function Standing.nextBandAt(value)
	for i = 1, BAND_COUNT do
		if value < BANDS[i] then
			return BANDS[i]
		end
	end
	return nil
end

-- Progress toward the next band, in [0, 1]. 1 when already at the top band.
function Standing.bandProgress(value)
	local from = Standing.floorOf(value)
	local to = Standing.nextBandAt(value)
	if to == nil then
		return 1
	end
	if to <= from then
		return 1
	end
	return (value - from) / (to - from)
end

-- One tide epoch of decay. Integer arithmetic throughout: 2.5% of the distance
-- above the band floor, floored, so the value is exactly reproducible and can
-- never drift by a fraction of a point.
function Standing.decay(value)
	local base = Standing.floorOf(value)
	local excess = value - base
	if excess <= 0 then
		return base
	end
	local lost = floor(excess * DECAY / 1000)
	-- Without this, any value within 40 points of its floor would be immortal.
	if lost < 1 then
		lost = 1
	end
	local result = value - lost
	if result < base then
		return base
	end
	return result
end

-- Decay applied `n` times. Written as a loop rather than a closed form because
-- the floor() inside makes the closed form wrong, and "approximately right" is
-- not a thing a save format may be.
function Standing.decayN(value, n)
	local v = value
	for _ = 1, n do
		v = Standing.decay(v)
	end
	return v
end

-- Apply a delta and clamp to [0, MAX]. Negative deltas still cannot push a
-- player below a band they have crossed.
function Standing.grant(value, delta)
	local result = value + delta
	if result > MAX then
		result = MAX
	end
	if result < 0 then
		result = 0
	end
	if delta < 0 then
		local base = Standing.floorOf(value)
		if result < base then
			result = base
		end
	end
	return result
end

-- The whole 5-Current vector, one epoch of decay. Mutates in place; the caller
-- already owns a private copy of the state (Resolve deep-copies on entry).
function Standing.decayAll(vector)
	for i = 1, EconomyConfig.CURRENT_COUNT do
		vector[i] = Standing.decay(vector[i])
	end
	return vector
end

return Standing
