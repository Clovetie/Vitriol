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

local TAU = math.pi * 2
local EPS = 1e-6

local function clamp(value: number, low: number, high: number): number
	if value < low then
		return low
	elseif value > high then
		return high
	end
	return value
end

local function unit(x: number, y: number, z: number): number, number, number
	local length = math.sqrt(x * x + y * y + z * z)
	if length < EPS then
		return 0, 1, 0
	end
	return x / length, y / length, z / length
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
	rig.Anchored = {}
	rig.AnchorX = {}
	rig.AnchorY = {}
	rig.AnchorZ = {}

	local count = stats.TendrilCount or 8
	local joints = stats.JointsPerTendril or 10
	local segmentLength = stats.TendrilReach / math.max(joints - 1, 1)
	local coreRadius = stats.CoreRadius or 1.5
	local rigConfig = rig.RigConfig
	for i = 1, count do
		local theta = (i - 1) / count * TAU
		local radialX = math.cos(theta)
		local radialZ = math.sin(theta)
		local radialY = 0.10 * math.sin(theta * 2)
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
		rig.Anchored[i] = false
	end
	return rig
end

function TendrilRig:setCore(x: number, y: number, z: number): ()
	self.CoreX = x
	self.CoreY = y
	self.CoreZ = z
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
	return true
end

function TendrilRig:clearAnchors(): ()
	for i = 1, #self.Chains do
		self.Anchored[i] = false
	end
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
		local theta = (i - 1) / total * TAU
		local radialX = math.cos(theta)
		local radialZ = math.sin(theta)
		local radialY = 0.10 * math.sin(theta * 2)
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
		else
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
		local solved = self.Fabrik.solve(chain, targetX, targetY, targetZ, self.Options[i])
		if not solved and i <= active and self.Anchored[i] then
			solvedAll = false
		end
		local idleBlend = rigConfig.RestBlendIdle or 0.35
		local urgentBlend = rigConfig.RestBlendUrgent or 0
		local blend = idleBlend + (urgentBlend - idleBlend) * self.Urgency
		if not self.Anchored[i] or i > active then
			self.Fabrik.blendToRest(chain, rest, blend)
		end
		local baseStiffness = rigConfig.DampBaseStiffness or 30
		local tipStiffness = rigConfig.DampTipStiffness or 6
		self.Fabrik.dampChain(display, chain, baseStiffness, tipStiffness, dt)
		display.dirty = true
	end
	return solvedAll
end

function TendrilRig:skeletons(): any
	return self.Display
end

function TendrilRig:simulationSkeletons(): any
	return self.Chains
end

function TendrilRig:tip(index: number): number, number, number
	local chain = self.Display[index]
	if chain == nil then
		return self.CoreX, self.CoreY, self.CoreZ
	end
	return chain:tipX(), chain:tipY(), chain:tipZ()
end

return TendrilRig
