--!strict
-- Senses.luau
-- Location: ServerStorage > Vitriol > Creature > Brain > Senses  (ModuleScript)
-- Purpose:  Observer half of perception. Samples Shared/NoiseField on vibration,
--           scent and air, applies acuity / localisation error / downwind sniff
--           / water-immersion / occlusion, and returns memory events.
--           There is no sight channel. This module never calls Players:GetPlayers
--           and never inspects a character root to choose a target: it only reads
--           the field. Player iteration belongs to the stimulus bridge.
--
--           Propagation (decay, wind advection, rain mask, surface coupling) is
--           NoiseField's. Duplicating it here would let the Attune overlay and
--           the creature disagree (docs/02 §2).
-- Requires: injected NoiseField, MonsterConfig.Senses, stats, RNG
-- Used by:  Services/CreatureService

local Senses = {}
Senses.__index = Senses

Senses.SIGHT = "SIGHT"

local function clamp01(value: number): number
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

function Senses.new(options: any): any
	local o = options or {}
	local self = setmetatable({}, Senses)
	self.Field = o.Field
	self.Config = o.Config or {}
	self.Senses = self.Config.Senses or self.Config
	self.Stats = o.Stats or {}
	self.RNG = o.RNG
	self.Workspace = o.Workspace
	self.channels = self.Senses.ObserverChannels or { "VIBRATION", "AIR", "SCENT" }
	self.threshold = self.Senses.Threshold or {}
	self.errorScale = self.Senses.ErrorScale or {}
	self.range = self.Senses.Range or {}
	self.downwind = self.Senses.DownwindSniffBoost or 1.5
	self.waterMask = self.Senses.WaterImmersionMask or {}
	self.airOcclusion = self.Senses.AirOcclusionFactor or 0.25
	self.maxRays = self.Senses.MaxOcclusionRaysPerTick or 6
	self.maxCandidates = self.Senses.MaxCandidatesPerTick or 12
	self.broadRadius = self.Senses.BroadPhaseRadius or 80
	self.out = {}
	self.outCount = 0
	self.raysThisTick = 0
	self.overlap = nil
	self.rayParams = o.RaycastParams
	if OverlapParams ~= nil then
		local params = OverlapParams.new()
		params.MaxParts = self.maxCandidates
		self.overlap = params
	end
	if self.rayParams == nil and RaycastParams ~= nil then
		self.rayParams = RaycastParams.new()
	end
	return self
end

function Senses.hasSight(): boolean
	return false
end

function Senses:hasChannel(channel: any): boolean
	if channel == Senses.SIGHT or channel == "Sight" or channel == "VISION" then
		return false
	end
	for i = 1, #self.channels do
		if self.channels[i] == channel then
			return true
		end
	end
	return false
end

function Senses:_acuity(channel: any): number
	local acuities = self.Stats.SenseAcuity
	if acuities and acuities[channel] ~= nil then
		return acuities[channel]
	end
	return 0.5
end

function Senses:_range(channel: any): number
	local ranges = self.Stats.SenseRange
	if ranges and ranges[channel] ~= nil then
		return ranges[channel]
	end
	return self.range[channel] or 40
end

function Senses:_broadPhase(x: number, y: number, z: number): any
	-- Bounding-box query, not exact geometry (WorldRoot docs). Cached params.
	local workspace = self.Workspace
	if workspace == nil or workspace.GetPartBoundsInRadius == nil or Vector3 == nil then
		return nil
	end
	return workspace:GetPartBoundsInRadius(Vector3.new(x, y, z), self.broadRadius, self.overlap)
end

function Senses:_occlude(x: number, y: number, z: number, tx: number, ty: number, tz: number): number
	if self.raysThisTick >= self.maxRays then
		return 1
	end
	local workspace = self.Workspace
	if workspace == nil or workspace.Raycast == nil or Vector3 == nil then
		return 1
	end
	self.raysThisTick = self.raysThisTick + 1
	local origin = Vector3.new(x, y, z)
	local delta = Vector3.new(tx - x, ty - y, tz - z)
	local hit = workspace:Raycast(origin, delta, self.rayParams)
	if hit == nil then
		return 1
	end
	return self.airOcclusion
end

-- sample(senses, x, y, z, now, opts?) -> observations, count
-- opts: { immersed = bool }. Never reads Players. Writes into a reused array.
function Senses:sample(x: number, y: number, z: number, now: number, opts: any?): (any, number)
	self.outCount = 0
	self.raysThisTick = 0
	local field = self.Field
	if field == nil then
		return self.out, 0
	end
	local immersed = opts and opts.immersed
	self:_broadPhase(x, y, z)
	local wx, wy, wz = 0, 0, 0
	if field.wind then
		wx, wy, wz = field:wind()
	end
	local windMag2 = wx * wx + wy * wy + wz * wz
	for i = 1, #self.channels do
		local channel = self.channels[i]
		if channel ~= Senses.SIGHT then
			local radius = self:_range(channel)
			local raw, ix, iy, iz, age = field:bestImpulse(channel, x, y, z, radius, now)
			if raw > 0 and ix ~= nil then
				if immersed then
					raw = raw * (self.waterMask[channel] or 1)
				end
				if channel == "SCENT" and windMag2 > 0 then
					-- Downwind sniff: the nose is boosted when the wind blows the
					-- plume toward the observer. Upwind is unchanged (the field
					-- already moved the plume).
					local toObsX = x - ix
					local toObsY = y - iy
					local toObsZ = z - iz
					if wx * toObsX + wy * toObsY + wz * toObsZ > 0 then
						raw = raw * self.downwind
					end
				end
				if channel == "AIR" then
					raw = raw * self:_occlude(x, y, z, ix, iy, iz)
				end
				local acuity = self:_acuity(channel)
				local thresh = self.threshold[channel] or 0.1
				if acuity > 0.05 then
					thresh = thresh / acuity
				end
				if raw >= thresh then
					local dx = ix - x
					local dy = iy - y
					local dz = iz - z
					local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
					local err = (1 - acuity) * (self.errorScale[channel] or 0.3) * dist
					local ox, oy, oz = 0, 0, 0
					if err > 0 and self.RNG and self.RNG.gaussian3 then
						ox, oy, oz = self.RNG:gaussian3()
						ox, oy, oz = ox * err, oy * err, oz * err
					end
					local conf = clamp01((raw / thresh - 1)) * acuity
					if conf < 0 then
						conf = 0
					elseif conf > 1 then
						conf = 1
					end
					if conf > 0 then
						self.outCount = self.outCount + 1
						local rec = self.out[self.outCount]
						if rec == nil then
							rec = {}
							self.out[self.outCount] = rec
						end
						rec.channel = channel
						rec.x = ix + ox
						rec.y = iy + oy
						rec.z = iz + oz
						rec.confidence = conf
						rec.intensity = raw
						rec.age = age or 0
						rec.time = now
					end
				end
			end
		end
	end
	return self.out, self.outCount
end

function Senses:loudest(x: number, y: number, z: number, now: number): any
	local observations, n = self:sample(x, y, z, now)
	local best = nil
	for i = 1, n do
		local rec = observations[i]
		if best == nil or rec.confidence > best.confidence then
			best = rec
		end
	end
	return best
end

return Senses
