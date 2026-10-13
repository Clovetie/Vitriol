--!strict
-- TendrilRig.luau
-- Location: ServerStorage > Vitriol > Creature > Body > TendrilRig  (ModuleScript)
-- Purpose:  Builds the code-generated Braid body and solves every tendril with the
--           shared constrained FABRIK solver. The simulation is flat-array data;
--           no MeshPart, Bone or CFrame is required here, which keeps the solver
--           executable in the smoke harness and lets a renderer be swapped later.
-- Requires: injected Skeleton, Fabrik, optional Noise
-- Used by:  CreatureCore, tools/vitriol-smoke-test.js

local TendrilRig = {}
TendrilRig.__index = TendrilRig

local EPS = 1e-6

local function clamp(value: number, low: number, high: number): number
	if value < low then
		return low
	elseif value > high then
		return high
	end
	return value
end

local function unit(x: number, y: number, z: number): (number, number, number)
	local length = math.sqrt(x * x + y * y + z * z)
	if length < EPS then
		return 0, 1, 0
	end
	return x / length, y / length, z / length
end

-- An elongated pair of banks rather than N equally spaced radial spokes.
-- Front tendrils reach ahead of travel; rear tendrils brace/push behind it.
-- Slots spread each bank across the width, keeping the creature bilateral.
local function bankDirection(index: number, total: number, hx: number, hz: number): (number, number, number)
	local frontCount = math.ceil(total / 2)
	local front = index <= frontCount
	local slots = front and frontCount or total - frontCount
	local slot = front and index or index - frontCount
	local spread = (slot - (slots + 1) * 0.5) / math.max((slots - 1) * 0.5, 1)
	local forward = front and 0.8 or -0.8
	local side = spread * 0.85
	local dx, dz = hx * forward - hz * side, hz * forward + hx * side
	local length = math.sqrt(dx * dx + dz * dz)
	return dx / length, dz / length, spread
end

-- new(stats, options) -> TendrilRig
-- options = { Skeleton, Fabrik, Noise, Config, Seed, CoreX, CoreY, CoreZ }
function TendrilRig.new(stats: any, options: any): any
	local o = options or {}
	local rig = setmetatable({}, TendrilRig)
	rig.Stats = stats
	rig.Config = o.Config or {}
	rig.RigConfig = rig.Config.Rig or {}
	rig.Fabrik = o.Fabrik
	rig.Skeleton = o.Skeleton
	rig.Noise = o.Noise
	rig.Seed = o.Seed or 1
	rig.CoreX = o.CoreX or 0
	rig.CoreY = o.CoreY or 0
	rig.CoreZ = o.CoreZ or 0
	rig.Time = 0
	rig.Urgency = 0
	rig.ActiveCount = stats.TendrilCount or 8
	rig.Chains = {}
	rig.Display = {}
	rig.Rest = {}
	rig.Options = {}
	rig.SupportOptions = {}
	rig.Anchored = {}
	rig.AnchorX = {}
	rig.AnchorY = {}
	rig.AnchorZ = {}
	-- World-space stance feet are owned by the rig, not rebuilt from the
	-- moving core every frame. This is Lua state, not authored/game Instances.
	rig.FootReady, rig.FootX, rig.FootY, rig.FootZ = {}, {}, {}, {}
	rig.Swinging, rig.SwingAge = {}, {}
	rig.SwingDuration, rig.NextStepAt = {}, {}
	rig.GaitVariation, rig.SeekDrive, rig.Seeking = {}, {}, {}
	rig.TargetX, rig.TargetY, rig.TargetZ = nil, nil, nil
	rig.SwingFromX, rig.SwingFromY, rig.SwingFromZ = {}, {}, {}
	rig.SwingToX, rig.SwingToY, rig.SwingToZ = {}, {}, {}
	rig.MoveX, rig.MoveZ = 0, 0
	rig.HeadingX, rig.HeadingZ = 1, 0
	rig.SupportY = nil
	rig.SupportX, rig.SupportZ = 0, 0
	rig.SupportNX, rig.SupportNY, rig.SupportNZ = 0, 1, 0

	local count = stats.TendrilCount or 8
	local joints = stats.JointsPerTendril or 10
	local segmentLength = stats.TendrilReach / math.max(joints - 1, 1)
	local coreRadius = stats.CoreRadius or 1.5
	local rigConfig = rig.RigConfig
	for i = 1, count do
		local radialX, radialZ, spread = bankDirection(i, count, 1, 0)
		local radialY = 0.08 * spread
		local rootX = rig.CoreX + radialX * coreRadius
		local rootY = rig.CoreY + radialY
		local rootZ = rig.CoreZ + radialZ * coreRadius
		local directionX, directionY, directionZ = unit(radialX, -0.12 + radialY, radialZ)
		local chain = rig.Skeleton.new(joints, {
			segmentLength = segmentLength,
			rootRadius = coreRadius * 0.28,
			tipRadius = coreRadius * 0.035,
		})
		chain:setRestPose(rootX, rootY, rootZ, directionX, directionY, directionZ)
		chain:reset()
		local display = rig.Skeleton.new(joints, {
			segmentLength = segmentLength,
			rootRadius = coreRadius * 0.28,
			tipRadius = coreRadius * 0.035,
		})
		display:setRestPose(rootX, rootY, rootZ, directionX, directionY, directionZ)
		display:reset()
		local rest = rig.Skeleton.new(joints, {
			segmentLength = segmentLength,
			rootRadius = coreRadius * 0.28,
			tipRadius = coreRadius * 0.035,
		})
		rest:setRestPose(rootX, rootY, rootZ, directionX, directionY, directionZ)
		rest:reset()

		local maxAngles = {}
		for j = 2, joints - 1 do
			local progress = (j - 1) / math.max(joints - 2, 1)
			local proximal = rigConfig.MaxAngleProximal or 35
			local distal = rigConfig.MaxAngleDistal or 70
			maxAngles[j] = proximal + (distal - proximal) * progress
		end
		rig.Chains[i] = chain
		rig.Display[i] = display
		rig.Rest[i] = rest
		rig.Options[i] = {
			tolerance = rigConfig.Tolerance or 0.02,
			maxIterations = rigConfig.MaxIterations or 8,
			maxAngles = maxAngles,
			planeBias = rigConfig.PlaneBias or 0.6,
			upX = 0,
			upY = 1,
			upZ = 0,
		}
		-- FABRIK's post-solve cone pass can pull a tip several studs AWAY
		-- from its contact point. For supported legs the foot target must win;
		-- these preallocated options leave the solved bone lengths intact.
		rig.SupportOptions[i] = {
			tolerance = rigConfig.Tolerance or 0.02,
			maxIterations = rigConfig.MaxIterations or 8,
		}
		rig.Anchored[i] = false
		rig.FootReady[i] = false
		rig.Swinging[i] = false
		rig.Seeking[i] = false
		rig.GaitVariation[i] = ((i * 17 + rig.Seed * 7) % 31) / 30
		rig.SeekDrive[i] = ((i * 11 + rig.Seed * 3) % 37) / 36
		rig.NextStepAt[i] = 0
	end
	return rig
end

function TendrilRig:setCore(x: number, y: number, z: number, dt: number?): ()
	local elapsed = dt or 0
	if elapsed > 1e-4 then
		self.MoveX = (x - self.CoreX) / elapsed
		self.MoveZ = (z - self.CoreZ) / elapsed
		local speed = math.sqrt(self.MoveX * self.MoveX + self.MoveZ * self.MoveZ)
		if speed > 1 then
			local blend = clamp(elapsed * 10, 0, 1)
			local nx = self.HeadingX * (1 - blend) + self.MoveX / speed * blend
			local nz = self.HeadingZ * (1 - blend) + self.MoveZ / speed * blend
			local length = math.sqrt(nx * nx + nz * nz)
			if length > EPS then self.HeadingX, self.HeadingZ = nx / length, nz / length end
		end
	else
		self.MoveX, self.MoveZ = 0, 0
	end
	self.CoreX = x
	self.CoreY = y
	self.CoreZ = z
end

function TendrilRig:setTarget(x: number, y: number, z: number): ()
	self.TargetX, self.TargetY, self.TargetZ = x, y, z
end

function TendrilRig:clearTarget(): ()
	self.TargetX, self.TargetY, self.TargetZ = nil, nil, nil
end

function TendrilRig:setActiveFraction(fraction: number): ()
	local total = #self.Chains
	local f = clamp(fraction, 0, 1)
	self.ActiveCount = math.max(1, math.floor(total * f + 0.5))
end

function TendrilRig:setAnchor(index: number, x: number, y: number, z: number): boolean
	if index < 1 or index > #self.Chains then
		return false
	end
	self.Anchored[index] = true
	self.AnchorX[index] = x
	self.AnchorY[index] = y
	self.AnchorZ[index] = z
	self.FootReady[index] = true
	self.FootX[index], self.FootY[index], self.FootZ[index] = x, y, z
	self.Swinging[index], self.Seeking[index] = false, false
	return true
end

-- Contacts measured by the ray fan SEED a leg only once. Replacing its foot
-- every new raycast teleported four load-bearing tips every 0.12 seconds,
-- visually skidding across the floor. After seeding, stance/swing owns it.
function TendrilRig:seedFoot(index: number, x: number, y: number, z: number): boolean
	if index < 1 or index > #self.Chains then return false end
	if not self.FootReady[index] then
		self.FootReady[index] = true
		self.FootX[index], self.FootY[index], self.FootZ[index] = x, y, z
	end
	return true
end

function TendrilRig:clearAnchors(): ()
	for i = 1, #self.Chains do
		self.Anchored[i] = false
	end
	self.SupportY = nil
end

-- Reuse the load-bearing contacts as a local support plane. The other tendrils
-- can gesture toward that surface without extra raycasts or gameplay objects.
function TendrilRig:setSupportPlane(x: number, y: number, z: number, nx: number, ny: number, nz: number): ()
	self.SupportX, self.SupportY, self.SupportZ = x, y, z
	self.SupportNX, self.SupportNY, self.SupportNZ = nx, ny, nz
end

-- A leg's desired landing point is predicted from body velocity and projected
-- to the cached contact plane. Unlike a body-relative target, its STANCE foot
-- stays at a world-space coordinate until that leg is explicitly swung.
function TendrilRig:_footHome(i: number, radialX: number, radialZ: number): (number, number, number)
	local rigConfig = self.RigConfig
	local reach = self.Stats.TendrilReach or 14
	local temperament = self.GaitVariation[i] or 0.5
	local span = reach * ((rigConfig.FreeLegSpanFraction or 0.40) + (temperament - 0.5) * 0.15)
	local ahead = rigConfig.FootHomeLookahead or 0.12
	-- Rear roots need outward BACKWARD purchase, not the same forward
	-- prediction as front roots. The shared forward lead folded rear strands
	-- under the body and made their middle sections droop across the floor.
	local bankSign = i <= math.ceil(#self.Chains / 2) and 1 or -1
	local leadX, leadZ = self.MoveX * ahead * bankSign, self.MoveZ * ahead * bankSign
	local length = math.sqrt(leadX * leadX + leadZ * leadZ)
	local maxLead = reach * 0.08
	if length > maxLead then
		leadX, leadZ = leadX * maxLead / length, leadZ * maxLead / length
	end
	-- Give every leg a forward landing intent even if the core pauses: otherwise
	-- following planted feet deadlocks when velocity-derived foot homes stop.
	-- Rear legs still plant behind their roots; they simply push forward next.
	local intentX, intentZ = 0, 0
	if self.TargetX ~= nil and math.abs((self.TargetY or self.CoreY) - self.CoreY) < reach * 0.6 then
		local tx, tz = self.TargetX - self.CoreX, self.TargetZ - self.CoreZ
		local distance = math.sqrt(tx * tx + tz * tz)
		if distance > EPS then
			local advance = math.min(distance, reach * (rigConfig.FootAdvanceFraction or 0.16))
			intentX, intentZ = tx / distance * advance, tz / distance * advance
		end
	end
	local px = self.CoreX + radialX * span + leadX + intentX
	local py = self.CoreY
	local pz = self.CoreZ + radialZ * span + leadZ + intentZ
	-- Within reach, each leg independently searches a little toward the
	-- prey while retaining a ground contact. An unreachable HIGH target gets
	-- no artificial foot pull: preserve the user's preferred chaotic response.
	if self.TargetX ~= nil and math.abs((self.TargetY or py) - self.CoreY) < reach * 0.35 then
		local dx, dz = self.TargetX - self.CoreX, self.TargetZ - self.CoreZ
		local distance = math.sqrt(dx * dx + dz * dz)
		if distance > EPS and distance < reach * 1.5 then
			local affinity = 0.3 + 0.7 * (self.SeekDrive[i] or 0.5)
			local pull = (1 - distance / (reach * 1.5)) * reach
				* (rigConfig.FootTargetPullFraction or 0.12) * affinity
			px, pz = px + dx / distance * pull, pz + dz / distance * pull
		end
	end
	local signed = (px - self.SupportX) * self.SupportNX
		+ (py - self.SupportY) * self.SupportNY
		+ (pz - self.SupportZ) * self.SupportNZ
	local offset = signed - 0.12
	local footX, footY, footZ = px - self.SupportNX * offset,
		py - self.SupportNY * offset, pz - self.SupportNZ * offset
	-- Aim far out, but leave a little IK slack. Clamp ONLY along the support
	-- plane; clamping the whole vector would lift the foot off the ground.
	local radius = self.Stats.CoreRadius or 1.5
	local baseX = self.CoreX + radialX * radius
	local baseY = self.CoreY
	local baseZ = self.CoreZ + radialZ * radius
	local baseHeight = (baseX - self.SupportX) * self.SupportNX
		+ (baseY - self.SupportY) * self.SupportNY
		+ (baseZ - self.SupportZ) * self.SupportNZ - 0.12
	local planeX = baseX - self.SupportNX * baseHeight
	local planeY = baseY - self.SupportNY * baseHeight
	local planeZ = baseZ - self.SupportNZ * baseHeight
	local tx, ty, tz = footX - planeX, footY - planeY, footZ - planeZ
	local lateral = math.sqrt(tx * tx + ty * ty + tz * tz)
	local maxLateral = math.sqrt(math.max((reach * 0.96) ^ 2 - baseHeight * baseHeight, 0))
	if lateral > maxLateral and lateral > EPS then
		local ratio = maxLateral / lateral
		footX, footY, footZ = planeX + tx * ratio, planeY + ty * ratio, planeZ + tz * ratio
	end
	return footX, footY, footZ
end

function TendrilRig:_freeFoot(i: number, radialX: number, radialZ: number, dt: number): (number, number, number)
	local hx, hy, hz = self:_footHome(i, radialX, radialZ)
	if not self.FootReady[i] then
		self.FootX[i], self.FootY[i], self.FootZ[i] = hx, hy, hz
		self.FootReady[i] = true
	end
	if self.Swinging[i] then
		local duration = self.SwingDuration[i] or math.max(self.RigConfig.FootSwingSeconds or 0.12, 0.02)
		local phase = clamp((self.SwingAge[i] or 0) + dt / duration, 0, 1)
		self.SwingAge[i] = phase
		local smooth = phase * phase * (3 - 2 * phase)
		local lift = math.sin(phase * math.pi) * (self.RigConfig.FootSwingHeight or 0.52)
			* (0.65 + (self.GaitVariation[i] or 0.5) * 0.7)
		local x = self.SwingFromX[i] + (self.SwingToX[i] - self.SwingFromX[i]) * smooth + self.SupportNX * lift
		local y = self.SwingFromY[i] + (self.SwingToY[i] - self.SwingFromY[i]) * smooth + self.SupportNY * lift
		local z = self.SwingFromZ[i] + (self.SwingToZ[i] - self.SwingFromZ[i]) * smooth + self.SupportNZ * lift
		if phase >= 1 then
			self.FootX[i], self.FootY[i], self.FootZ[i] = self.SwingToX[i], self.SwingToY[i], self.SwingToZ[i]
			self.Swinging[i] = false
		end
		return x, y, z
	end
	local dx, dy, dz = hx - self.FootX[i], hy - self.FootY[i], hz - self.FootZ[i]
	-- Each tendril makes its OWN stance/swing decision, with different drift
	-- tolerance, recovery and sweep time. No global front/rear metronome.
	local variation = self.GaitVariation[i] or 0.5
	local threshold = (self.RigConfig.FootReplantDistance or 1.9) * (0.75 + variation * 0.55)
	-- Intent still advances the stance when the mass is waiting on those feet.
	local moving = self.MoveX * self.MoveX + self.MoveZ * self.MoveZ > 1
	if self.TargetX ~= nil and math.abs((self.TargetY or self.CoreY) - self.CoreY) < (self.Stats.TendrilReach or 14) * 0.6 then
		local tx, tz = self.TargetX - self.CoreX, self.TargetZ - self.CoreZ
		moving = moving or tx * tx + tz * tz > 1
	end
	if moving and self.Time >= (self.NextStepAt[i] or 0)
		and dx * dx + dy * dy + dz * dz > threshold * threshold then
		local total = #self.Chains
		local maxSwing = math.max(1, math.min(total - 2,
			math.floor(total * (self.RigConfig.FootMaxSwingFraction or 0.4) + 0.5)))
		local airborne, bankAirborne = 0, 0
		local frontCount = math.ceil(total / 2)
		local sameBankFront = i <= frontCount
		local bankSize = sameBankFront and frontCount or total - frontCount
		local bankLimit = math.max(1, math.floor(bankSize * (self.RigConfig.FootBankSwingFraction or 0.34)))
		for leg = 1, total do
			if self.Swinging[leg] then
				airborne += 1
				if (leg <= frontCount) == sameBankFront then
					bankAirborne += 1
				end
			end
		end
		if airborne < maxSwing and bankAirborne < bankLimit then
			local duration = math.max(0.02, (self.RigConfig.FootSwingSeconds or 0.12) * (0.8 + variation * 0.4))
			self.Swinging[i], self.SwingAge[i], self.SwingDuration[i] = true, 0, duration
			self.NextStepAt[i] = self.Time + duration
				+ (self.RigConfig.FootRecoverySeconds or 0.08) * (0.5 + variation)
			self.SwingFromX[i], self.SwingFromY[i], self.SwingFromZ[i] = self.FootX[i], self.FootY[i], self.FootZ[i]
			self.SwingToX[i], self.SwingToY[i], self.SwingToZ[i] = hx, hy, hz
		end
	end
	return self.FootX[i], self.FootY[i], self.FootZ[i]
end

function TendrilRig:step(dt: number, urgency: number?): boolean
	self.Time = self.Time + math.max(dt, 0)
	self.Urgency = clamp(urgency or 0, 0, 1)
	local stats = self.Stats
	local rigConfig = self.RigConfig
	local coreRadius = stats.CoreRadius or 1.5
	local total = #self.Chains
	local active = self.ActiveCount
	local solvedAll = true
	for i = 1, total do
		local chain = self.Chains[i]
		local display = self.Display[i]
		local rest = self.Rest[i]
		local radialX, radialZ, spread = bankDirection(i, total, self.HeadingX, self.HeadingZ)
		local radialY = 0.08 * spread
		local baseX = self.CoreX + radialX * coreRadius
		local baseY = self.CoreY + radialY
		local baseZ = self.CoreZ + radialZ * coreRadius
		local dirX, dirY, dirZ = unit(radialX, -0.12 + radialY, radialZ)
		rest:setRestPose(baseX, baseY, baseZ, dirX, dirY, dirZ)
		rest:reset()
		chain.x[1], chain.y[1], chain.z[1] = baseX, baseY, baseZ
		local targetX = rest:tipX()
		local targetY = rest:tipY()
		local targetZ = rest:tipZ()
		if i <= active and self.Anchored[i] then
			targetX = self.AnchorX[i]
			targetY = self.AnchorY[i]
			targetZ = self.AnchorZ[i]
		elseif i <= active and self.SupportY ~= nil then
			self.Seeking[i] = false
			local reach = stats.TendrilReach or 14
			if self.TargetX ~= nil and (self.SeekDrive[i] or 0) > (rigConfig.FootSeekerThreshold or 0.78)
				and math.abs((self.TargetY or self.CoreY) - self.CoreY) < reach * 0.6 then
				local tx, ty, tz = self.TargetX, self.TargetY or self.CoreY, self.TargetZ
				local dx, dy, dz = tx - baseX, ty - baseY, tz - baseZ
				if dx * dx + dy * dy + dz * dz < (reach * 0.90) ^ 2 then
					-- High-drive strands reach for nearby prey while other tips
					-- keep the elevated core planted. Their small tremor differs
					-- per leg; an unreachable high target is deliberately ignored.
					local tremor = math.sin(self.Time * (2 + self.GaitVariation[i]) + i) * 0.25
					targetX, targetY, targetZ = tx + tremor * radialX, ty + tremor, tz + tremor * radialZ
					self.Seeking[i], self.Swinging[i] = true, false
				end
			end
			if not self.Seeking[i] then
				targetX, targetY, targetZ = self:_freeFoot(i, radialX, radialZ, dt)
			end
		else
			self.Seeking[i] = false
			self.FootReady[i], self.Swinging[i] = false, false
			local nx, ny, nz = 0, 0, 0
			if self.Noise ~= nil then
				nx, ny, nz = self.Noise:v3(self.Seed + i * 17, self.Time * (rigConfig.NoiseFrequency or 0.7))
			else
				nx = math.sin(self.Time * 0.7 + i)
				ny = math.sin(self.Time * 0.9 + i * 2)
				nz = math.cos(self.Time * 0.6 + i)
			end
			local amplitude = (rigConfig.NoiseAmplitude or 0.06) * (1 - self.Urgency)
			targetX = targetX + nx * amplitude
			targetY = targetY + ny * amplitude
			targetZ = targetZ + nz * amplitude
		end
		local supportTarget = i <= active and (self.Anchored[i] or self.SupportY ~= nil)
		local solved = self.Fabrik.solve(chain, targetX, targetY, targetZ,
			supportTarget and self.SupportOptions[i] or self.Options[i])
		if not solved and i <= active and self.Anchored[i] then
			solvedAll = false
		end
		local idleBlend = rigConfig.RestBlendIdle or 0.35
		local urgentBlend = rigConfig.RestBlendUrgent or 0
		local blend = idleBlend + (urgentBlend - idleBlend) * self.Urgency
		if i > active or (not self.Anchored[i] and self.SupportY == nil) then
			self.Fabrik.blendToRest(chain, rest, blend)
		end
		local baseStiffness = rigConfig.DampBaseStiffness or 30
		local tipStiffness = rigConfig.DampTipStiffness or 6
		self.Fabrik.dampChain(display, chain, baseStiffness, tipStiffness, dt)
		display.dirty = true
	end
	return solvedAll
end

-- World-space load-bearing feet, excluding lifted and prey-reaching tips.
-- The next core step uses this to keep its mass above actual support rather
-- than blindly following a forward-biased probe centroid.
function TendrilRig:stanceCentroid(): (number?, number?, number)
	local x, z, count = 0, 0, 0
	for i = 1, self.ActiveCount do
		if self.FootReady[i] and not self.Swinging[i] and not self.Seeking[i] then
			x += self.FootX[i]
			z += self.FootZ[i]
			count += 1
		end
	end
	if count == 0 then return nil, nil, 0 end
	return x / count, z / count, count
end

function TendrilRig:skeletons(): any
	return self.Display
end

function TendrilRig:simulationSkeletons(): any
	return self.Chains
end

function TendrilRig:tip(index: number): (number, number, number)
	local chain = self.Display[index]
	if chain == nil then
		return self.CoreX, self.CoreY, self.CoreZ
	end
	return chain:tipX(), chain:tipY(), chain:tipZ()
end

return TendrilRig
