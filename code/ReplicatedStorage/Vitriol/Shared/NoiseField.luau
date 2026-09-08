--!strict
-- NoiseField.luau
-- Location: ReplicatedStorage > Vitriol > Shared > NoiseField  (ModuleScript)
-- Purpose:  The creature's world model of "what is making a disturbance where".
--           One SpatialHash per sensory channel, holding decaying impulses that
--           PROPAGATE: exponential decay, wind advection, weather masking and
--           surface coupling (docs/02-MONSTER-DESIGN.md §2).
--           A single call answers "how loud is it HERE, on THIS channel, RIGHT
--           NOW?" - which is the question every sense asks.
--
--           Shared, not server-only: the player's Attune UI samples the same field
--           (docs/00-VISION.md §5.1.1), so both read identical numbers instead of
--           the UI inventing its own approximation.
--
-- WHERE THE LINE IS DRAWN (decided in WP3, docs/02 §2 records it)
--   The FIELD is observer-independent. Decay, wind advection and surface coupling
--   are properties of propagation: they do the same thing to every creature AND to
--   the Attune overlay, so they live here. A creature's NOSE is
--   observer-dependent: acuity thresholds, localisation error, the downwind
--   ×1.5 sniff boost, water-immersion masking of the *smeller*, occlusion
--   raycasts - those live in Creature/Brain/Senses and must not be duplicated here.
--   Two consumers must agree on the field, so anything the field knows is
--   something the UI can also show; anything only a creature knows stays private.
--
--   Still NOT here: physics queries (perception does those), and any per-frame
--   allocation - advection is evaluated at sample time from the impulse's age, so
--   nothing is ever re-inserted or moved, which is what keeps this parallel-safe.
-- Requires: Lib/SpatialHash, Lib/Tables
-- Used by:  Services/NoiseService, Creature/Brain/Senses, Client/VibrationFx

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

-- Which channels the wind carries. Only SCENT: vibration travels through the
-- ground (an airborne wind does not move a footstep), THERMAL/EM/PRESSURE are
-- documented in docs/02 §2 as range-only channels. Override with cfg.Advected.
NoiseField.DEFAULT_ADVECTED = { SCENT = 1 }

-- Which config field of a weather entry masks which channel
-- (DayNightConfig.Weather.* = { VibrationMask, AirMask, ... }). This is a mapping,
-- not a tunable: the NUMBERS live in the config the caller passes in.
NoiseField.DEFAULT_MASK_KEYS = {
	VIBRATION = "VibrationMask",
	AIR = "AirMask",
}

-- The channel surface coupling applies to. docs/02 §2 gives coupling to VIBRATION
-- only (hard surfaces amplify, water decouples); AIR gets its own weather mask
-- instead, and scent has no surface to couple to.
NoiseField.DEFAULT_COUPLING_CHANNEL = "VIBRATION"

-- A material with no entry couples neutrally: the surface neither amplifies nor
-- absorbs. 1 is the absence of information, not a tuned value.
NoiseField.DEFAULT_COUPLING = 1

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
--        PreallocPerChannel = n, Advected = { [channel] = response },
--        MaskKeys = { [channel] = "WeatherFieldName" },
--        Coupling = { [material] = multiplier }, CouplingChannel = "VIBRATION",
--        AdvectedMaxAge = seconds, Wind = { x, y, z } }
-- The coupling table is INJECTED rather than required from MonsterConfig so the
-- field stays constructible from both sides (server + Attune UI) with the same
-- data, and so this module can be executed by the headless test harness.
function NoiseField.new(cfg: any?)
	local c = cfg or {}
	local self = setmetatable({}, NoiseField)
	self.channels = c.Channels or NoiseField.CHANNELS
	self.halflife = {}
	self.advect = {}
	self.mask = {}
	self.gain = {}
	self.maxAge = {}
	self.driftSpan = {}
	self.ageWindow = {}
	local hl = c.Halflife or NoiseField.DEFAULT_HALFLIFE
	local advected = c.Advected or NoiseField.DEFAULT_ADVECTED
	local maskKeys = c.MaskKeys or NoiseField.DEFAULT_MASK_KEYS
	for i = 1, #self.channels do
		local ch = self.channels[i]
		local life = hl[ch] or 1
		self.halflife[ch] = life
		self.mask[ch] = 1
		self.maxAge[ch] = life * DECAY_CUTOFF_MULT
		-- Advection only makes sense for a channel that decays: the drift search
		-- window is derived from the half-life, and a permanent impulse would
		-- drift forever.
		if life > 0 and advected[ch] then
			self.advect[ch] = advected[ch]
		else
			self.advect[ch] = nil
		end
		-- The advection search window in SECONDS, set here rather than only in
		-- setWind so `advectionWindow()` answers before the first weather tick.
		if self.advect[ch] then
			local windowAge = life * DECAY_CUTOFF_MULT
			if c.AdvectedMaxAge ~= nil and c.AdvectedMaxAge < windowAge then
				windowAge = c.AdvectedMaxAge
			end
			self.ageWindow[ch] = windowAge
		else
			self.ageWindow[ch] = 0
		end
		self.gain[ch] = maskKeys[ch]
		self.driftSpan[ch] = 0
	end

	self.coupling = c.Coupling
	self.couplingChannel = c.CouplingChannel or NoiseField.DEFAULT_COUPLING_CHANNEL
	-- The temporal window advection is searched over. Without a cap the search
	-- radius has to grow with wind * the channel's whole audibility lifetime
	-- (SCENT: 26 s half-life -> 199 s -> hundreds of studs of cell scan per
	-- sample), which is the kind of "correct" that ships a 90 ms frame. Scent older
	-- than the cap is the memory layer's business (docs/02 §3), where it lives in
	-- interest cells rather than a live field, so this is a division of labour and
	-- not a truncation of the model.
	self.advectedMaxAge = c.AdvectedMaxAge
	-- Recompute the drift distances for the cap (the window above is set before the
	-- field knows the wind).
	self:setWind(0, 0, 0)

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

	-- Wind, as a single slowly changing vector (docs/02 §2). Stored squared where
	-- possible so "is there any wind at all?" costs no sqrt.
	self.windX = 0
	self.windY = 0
	self.windZ = 0
	self.windMag2 = 0

	-- Scratch for the advected sample. One closure for the whole field, created
	-- here and reused by every query, so the sample path allocates nothing.
	self._sx = 0
	self._sy = 0
	self._sz = 0
	self._now = 0
	self._rSq = 0
	self._total = 0
	self._ageWindow = 0
	self._visit = function(_, e)
		local intensity = e.intensity
		if intensity and intensity > 0 then
			local age = self._now - e.time
			if age < 0 then
				age = 0
			end
			-- Outside the advection window the plume is no longer modelled here at all
			-- (see AdvectedMaxAge above), so the entry is skipped rather than sampled at
			-- a clamped position: a wrong-but-confident number is worse than an absent
			-- one, and absence is what the memory layer is for.
			if age <= self._ageWindow then
				local halfLife = e.halflife
				local factor = 1
				if halfLife and halfLife > 0 then
					factor = 0.5 ^ (age / halfLife)
				end
				-- The source has drifted since it emitted: p(t) = p0 + wind * age.
				local gx = e.x + self._driftX * age - self._sx
				local gy = e.y + self._driftY * age - self._sy
				local gz = e.z + self._driftZ * age - self._sz
				if gx * gx + gy * gy + gz * gz <= self._rSq then
					self._total = self._total + intensity * factor
				end
			end
		end
	end
	self._driftX = 0
	self._driftY = 0
	self._driftZ = 0

	local w = c.Wind
	if w then
		self:setWind(w.X or w.x or 0, w.Y or w.y or 0, w.Z or w.z or 0)
	end
	return self
end

-- hasChannel(field, channel) -> boolean
function NoiseField:hasChannel(channel: any): boolean
	return self.hashes[channel] ~= nil
end

-- setWind(field, x, y, z) -> magnitude
-- One call per weather change (or per second at most). The wind is a WORLD state;
-- the caller owns it (TimeService publishes it, docs/06 §6), and both the creature
-- and the Attune overlay feed the same vector into their own copies of this field.
function NoiseField:setWind(x: number, y: number, z: number): number
	self.windX = x
	self.windY = y
	self.windZ = z
	local m2 = x * x + y * y + z * z
	self.windMag2 = m2
	if m2 > 0 then
		local mag = math.sqrt(m2)
		for i = 1, #self.channels do
			local ch = self.channels[i]
			local adv = self.advect[ch]
			if adv then
				-- How far a still-relevant impulse could have drifted, i.e. how much
				-- the query radius has to grow so nothing that matters is missed.
				local windowAge = self.maxAge[ch]
				local cap = self.advectedMaxAge
				if cap ~= nil and cap < windowAge then
					windowAge = cap
				end
				self.ageWindow[ch] = windowAge
				self.driftSpan[ch] = mag * adv * windowAge
			else
				self.ageWindow[ch] = 0
				self.driftSpan[ch] = 0
			end
		end
	else
		for i = 1, #self.channels do
			-- No wind: no drift to search for. The window itself stays, because it
			-- describes how old an advected impulse the field models at all, which is
			-- a property of the channel, not of the weather.
			self.driftSpan[self.channels[i]] = 0
		end
	end
	return math.sqrt(m2)
end

-- setAdvectionWindow(field, seconds) -> ()  (nil clears the cap)
function NoiseField:setAdvectionWindow(seconds: number?): ()
	self.advectedMaxAge = seconds
	self:setWind(self.windX, self.windY, self.windZ)
end

-- advectionWindow(field, channel) -> seconds searched downwind
function NoiseField:advectionWindow(channel: any): number
	return self.ageWindow[channel] or 0
end

-- wind(field) -> x, y, z   (multi-return: the debug visualiser reads this per frame)
function NoiseField:wind(): number, number, number
	return self.windX, self.windY, self.windZ
end

-- setWeather(field, weather) -> ()
-- 'weather' is a DayNightConfig.Weather entry, e.g.
--   DayNightConfig.Weather.Rain = { VibrationMask = 0.50, AirMask = 0.80, ... }
-- Rain halving vibration range (docs/00-VISION.md §5.1.3) therefore costs one
-- call here, not a multiplier in every sense module - which is also the only way
-- the Attune overlay can show what the creature actually hears.
-- Pass nil to clear.
function NoiseField:setWeather(weather: any?): ()
	for i = 1, #self.channels do
		local ch = self.channels[i]
		local key = self.gain[ch]
		local v = 1
		if weather and key then
			v = weather[key] or 1
		end
		self.mask[ch] = v
	end
end

-- setChannelMask(field, channel, gain) -> boolean
-- The primitive form of setWeather, for a caller that has its own table of gains
-- (debug tooling, a scripted test). False for an unknown channel.
function NoiseField:setChannelMask(channel: any, gain: number): boolean
	if self.hashes[channel] == nil then
		return false
	end
	self.mask[channel] = gain
	return true
end

-- channelMask(field, channel) -> number
function NoiseField:channelMask(channel: any): number
	return self.mask[channel] or 1
end

-- couple(field, channel, material) -> multiplier
-- Exposed so an emitter that already knows its surface (DestructionService, a
-- vehicle impact) can report the coupled intensity it emitted, and so the mapping
-- is testable in isolation.
function NoiseField:couple(channel: any, material: any): number
	if material == nil or channel ~= self.couplingChannel or self.coupling == nil then
		return NoiseField.DEFAULT_COUPLING
	end
	return self.coupling[material] or NoiseField.DEFAULT_COUPLING
end

-- emit(field, channel, x, y, z, intensity, now, opts?) -> id?
--   opts = { Halflife = seconds?, Material = "Concrete"? }
-- Returns the impulse id, or nil for an unknown channel / non-positive intensity
-- (a silent event must not create an entry that will be sampled forever).
function NoiseField:emit(channel: any, x: number, y: number, z: number, intensity: number, now: number, opts: any?): any
	local hash = self.hashes[channel]
	if hash == nil or intensity == nil or intensity <= 0 then
		return nil
	end
	local coupled = intensity
	local halfLife = self.halflife[channel]
	if opts then
		local material = opts.Material
		if material ~= nil then
			coupled = intensity * self:couple(channel, material)
			if coupled <= 0 then
				return nil
			end
		end
		if opts.Halflife then
			halfLife = opts.Halflife
		end
	end

	local entry = self.pools[channel]:get()
	entry.intensity = coupled
	entry.time = now or 0
	entry.halflife = halfLife

	local nextId = self.nextId[channel] + 1
	self.nextId[channel] = nextId
	hash:insert(nextId, x, y, z, entry)
	return nextId
end

-- emitAt(field, channel, x, y, z, intensity, now, halflife?, material) -> id?
-- The allocation-free positional form, for the hot callers: a footstep per step,
-- a wheel impact per bump. Building an options table there would allocate more
-- than the impulse itself.
function NoiseField:emitAt(channel: any, x: number, y: number, z: number, intensity: number, now: number, halflife: number?, material: any): any
	local hash = self.hashes[channel]
	if hash == nil or intensity == nil or intensity <= 0 then
		return nil
	end
	local coupled = intensity
	if material ~= nil then
		coupled = intensity * self:couple(channel, material)
		if coupled <= 0 then
			return nil
		end
	end

	local entry = self.pools[channel]:get()
	entry.intensity = coupled
	entry.time = now or 0
	entry.halflife = halflife or self.halflife[channel]

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

-- _sampleAdvected(field, hash, x, y, z, radius, now, channel) -> number
-- Trace-back advection: rather than moving impulses downwind every tick (writes,
-- allocations, and a spatial index that must be rebuilt), the SAMPLE is marched
-- backwards along the wind by the age of each impulse. Same answer, no writes -
-- the semi-Lagrangian trick, done at query time because the query already knows
-- 'now'.
function NoiseField:_sampleAdvected(hash: any, channel: any, x: number, y: number, z: number, radius: number, now: number): number
	local adv = self.advect[channel]
	self._sx = x
	self._sy = y
	self._sz = z
	self._now = now
	self._rSq = radius * radius
	self._total = 0
	self._ageWindow = self.ageWindow[channel] or self.maxAge[channel]
	self._driftX = self.windX * adv
	self._driftY = self.windY * adv
	self._driftZ = self.windZ * adv
	-- Widened so a drifted-in source is still inside the cell range; the visitor
	-- applies the true radius to the drifted position.
	hash:query(x, y, z, radius + self.driftSpan[channel], self._visit)
	return self._total
end

-- sample(field, channel, x, y, z, radius, now) -> number
function NoiseField:sample(channel: any, x: number, y: number, z: number, radius: number, now: number): number
	local hash = self.hashes[channel]
	if hash == nil then
		return 0
	end
	local value
	if self.advect[channel] ~= nil and self.windMag2 > 0 then
		value = self:_sampleAdvected(hash, channel, x, y, z, radius, now)
	else
		value = hash:sampleDecay(x, y, z, radius, now)
	end
	local mask = self.mask[channel]
	if mask ~= 1 then
		value = value * mask
	end
	return value
end

-- sampleAll(field, x, y, z, radius, now, out?) -> { [channel] = number }
-- Writes into 'out' (default: the shared table) and returns it. Unknown channels
-- get 0 rather than nil so callers can index unconditionally.
function NoiseField:sampleAll(x: number, y: number, z: number, radius: number, now: number, out: any?): any
	local o = out or self.out
	for i = 1, #self.channels do
		local ch = self.channels[i]
		o[ch] = self:sample(ch, x, y, z, radius, now)
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
		local v = self:sample(ch, x, y, z, radius, now)
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
-- A drifted-out impulse is pruned on the same clock: drift only moves an impulse
-- that is already below audibility by then, which is why the sample window above
-- can be derived from maxAge rather than tracked per impulse.
function NoiseField:prune(now: number): number
	local removed = 0
	for i = 1, #self.channels do
		local ch = self.channels[i]
		local pool = self.pools[ch]
		local maxAge = self.maxAge[ch]
		-- Assigned before accumulating rather than 'removed += ...:prune(...)':
		-- both tools/check-syntax.js and the smoke harness expand '+=' on a single
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
