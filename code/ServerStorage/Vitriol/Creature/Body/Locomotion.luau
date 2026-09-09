--!strict
-- Locomotion.luau
-- Location: ServerStorage > Vitriol > Creature > Body > Locomotion  (ModuleScript)
-- Purpose:  Anchor-and-haul movement for the code-generated creature. A small,
--           cached ray fan looks for purchase; when it finds enough surfaces the
--           core eases toward their centroid. With no purchase it glides toward its
--           last sensory target. No branch special-cases walls or ceilings: the
--           returned support normal is the creature's presentation up vector.
-- Requires: Config/MonsterConfig data injected by CreatureCore
-- Used by:  CreatureCore, tools/vitriol-smoke-test.js

local Locomotion = {}
Locomotion.__index = Locomotion

local EPS = 1e-6

local function unit(x: number, y: number, z: number): (number, number, number, number)
	local length = math.sqrt(x * x + y * y + z * z)
	if length < EPS then
		return 0, 0, 0, 0
	end
	return x / length, y / length, z / length, length
end

local function clamp(value: number, low: number, high: number): number
	if value < low then
		return low
	elseif value > high then
		return high
	end
	return value
end

function Locomotion.new(stats: any, options: any?): any
	local o = options or {}
	local self = setmetatable({}, Locomotion)
	self.Stats = stats
	self.Config = o.Config or {}
	self.Movement = self.Config.Locomotion or self.Config
	self.Workspace = o.Workspace
	self.RaycastParams = o.RaycastParams
	self.TargetX = nil
	self.TargetY = nil
	self.TargetZ = nil
	self.TargetConfidence = 0
	self.AnchorCount = 0
	self.AnchorX = {}
	self.AnchorY = {}
	self.AnchorZ = {}
	self.AnchorNX = {}
	self.AnchorNY = {}
	self.AnchorNZ = {}
	self.AnchorMaterial = {}
	self.AnchorTendril = {}
	self.DirectionX = {}
	self.DirectionY = {}
	self.DirectionZ = {}
	self.RayCount = self.Movement.AnchorRayCount or 7
	self.LastUpX, self.LastUpY, self.LastUpZ = 0, 1, 0
	return self
end

function Locomotion:setTarget(x: number, y: number, z: number, confidence: number?): ()
	self.TargetX = x
	self.TargetY = y
	self.TargetZ = z
	self.TargetConfidence = clamp(confidence or 1, 0, 1)
end

function Locomotion:clearTarget(): ()
	self.TargetX = nil
	self.TargetY = nil
	self.TargetZ = nil
	self.TargetConfidence = 0
end

function Locomotion:_buildDirections(x: number, y: number, z: number): ()
	local targetX = self.TargetX or x + 1
	local targetY = self.TargetY or y
	local targetZ = self.TargetZ or z
	local dx, dy, dz = targetX - x, targetY - y, targetZ - z
	local ux, uy, uz, distance = unit(dx, dy, dz)
	if distance < EPS then
		ux, uy, uz = 1, 0, 0
	end
	-- The fan is deliberately biased toward the last-known source, with vertical
	-- probes on either side. It is enough for floor, wall and ceiling purchase while
	-- keeping the per-creature query count bounded by Config.Locomotion.AnchorRayCount.
	local horizontalX, horizontalZ = ux, uz
	local horizontalLength = math.sqrt(horizontalX * horizontalX + horizontalZ * horizontalZ)
	if horizontalLength < EPS then
		horizontalX, horizontalZ = 1, 0
	else
		horizontalX, horizontalZ = horizontalX / horizontalLength, horizontalZ / horizontalLength
	end
	local sideX, sideZ = -horizontalZ, horizontalX
	local n = self.RayCount
	self.DirectionX[1], self.DirectionY[1], self.DirectionZ[1] = horizontalX, 0, horizontalZ
	self.DirectionX[2], self.DirectionY[2], self.DirectionZ[2] = 0, -1, 0
	self.DirectionX[3], self.DirectionY[3], self.DirectionZ[3] = 0, 1, 0
	self.DirectionX[4], self.DirectionY[4], self.DirectionZ[4] = sideX, 0, sideZ
	self.DirectionX[5], self.DirectionY[5], self.DirectionZ[5] = -sideX, 0, -sideZ
	self.DirectionX[6], self.DirectionY[6], self.DirectionZ[6] = horizontalX * 0.7 + sideX * 0.7, 0.35, horizontalZ * 0.7 + sideZ * 0.7
	self.DirectionX[7], self.DirectionY[7], self.DirectionZ[7] = horizontalX * 0.7 - sideX * 0.7, -0.35, horizontalZ * 0.7 - sideZ * 0.7
	if n < 7 then
		for i = n + 1, 7 do
			self.DirectionX[i], self.DirectionY[i], self.DirectionZ[i] = nil, nil, nil
		end
	end
end

function Locomotion:_clearAnchors(): ()
	self.AnchorCount = 0
end

function Locomotion:_tryAnchor(index: number, x: number, y: number, z: number, reach: number): boolean
	if self.Workspace == nil or self.Workspace.Raycast == nil or Vector3 == nil then
		return false
	end
	local direction = Vector3.new(self.DirectionX[index] * reach, self.DirectionY[index] * reach, self.DirectionZ[index] * reach)
	local origin = Vector3.new(x, y, z)
	local result = self.Workspace:Raycast(origin, direction, self.RaycastParams)
	if result == nil or result.Position == nil then
		return false
	end
	local count = self.AnchorCount + 1
	local position = result.Position
	local normal = result.Normal
	self.AnchorCount = count
	self.AnchorX[count] = position.X + normal.X * 0.12
	self.AnchorY[count] = position.Y + normal.Y * 0.12
	self.AnchorZ[count] = position.Z + normal.Z * 0.12
	self.AnchorNX[count] = normal.X
	self.AnchorNY[count] = normal.Y
	self.AnchorNZ[count] = normal.Z
	self.AnchorMaterial[count] = result.Material and result.Material.Name or "Default"
	self.AnchorTendril[count] = index
	return true
end

function Locomotion:step(dt: number, x: number, y: number, z: number): (number, number, number, number, number, number)
	self:_clearAnchors()
	self:_buildDirections(x, y, z)
	local reach = (self.Stats.TendrilReach or 14) * (self.Movement.ProbeReachMultiplier or 1.15)
	local maxAnchors = self.Movement.MaxAnchors or 4
	for i = 1, self.RayCount do
		if self.AnchorCount >= maxAnchors then
			break
		end
		self:_tryAnchor(i, x, y, z, reach)
	end

	local moveX, moveY, moveZ = 0, 0, 0
	local upX, upY, upZ = 0, 0, 0
	if self.AnchorCount >= (self.Movement.MinAnchors or 2) then
		local centerX, centerY, centerZ = 0, 0, 0
		for i = 1, self.AnchorCount do
			centerX += self.AnchorX[i]
			centerY += self.AnchorY[i]
			centerZ += self.AnchorZ[i]
			upX += self.AnchorNX[i]
			upY += self.AnchorNY[i]
			upZ += self.AnchorNZ[i]
		end
			centerX, centerY, centerZ = centerX / self.AnchorCount, centerY / self.AnchorCount, centerZ / self.AnchorCount
			local dx, dy, dz, distance = unit(centerX - x, centerY - y, centerZ - z)
			local grip = self.Movement.AnchorGrip or {}
			local gripSum = 0
			for i = 1, self.AnchorCount do
				gripSum += grip[self.AnchorMaterial[i]] or 0.6
			end
			local averageGrip = gripSum / math.max(self.AnchorCount, 1)
			local speed = (self.Stats.HaulSpeed or 8) * averageGrip
			local amount = math.min(distance, speed * dt / math.max(self.Movement.HaulSeconds or 0.35, 0.05))
			moveX, moveY, moveZ = dx * amount, dy * amount, dz * amount
		upX, upY, upZ = unit(upX, upY, upZ)
	else
		local targetX = self.TargetX or x
		local targetY = self.TargetY or y
		local targetZ = self.TargetZ or z
		local dx, dy, dz = unit(targetX - x, targetY - y, targetZ - z)
		local speed = (self.Stats.HaulSpeed or 8) * (self.Movement.GlideSpeedFraction or 0.45)
		moveX, moveY, moveZ = dx * speed * dt, dy * speed * dt, dz * speed * dt
		upX, upY, upZ = self.LastUpX, self.LastUpY, self.LastUpZ
	end
	if upX * upX + upY * upY + upZ * upZ < EPS then
		upX, upY, upZ = 0, 1, 0
	end
	self.LastUpX, self.LastUpY, self.LastUpZ = upX, upY, upZ
	return moveX, moveY, moveZ, upX, upY, upZ
end

function Locomotion:hold(): (number, number, number, number, number, number)
	-- A disabled/wounded creature remains rendered but no longer spends raycasts
	-- finding purchase every frame. Its last support normal keeps the silhouette
	-- stable until a future wound treatment re-enables threat.
	self:_clearAnchors()
	return 0, 0, 0, self.LastUpX, self.LastUpY, self.LastUpZ
end

function Locomotion:applyAnchors(rig: any): ()
	rig:clearAnchors()
	for i = 1, self.AnchorCount do
		rig:setAnchor(self.AnchorTendril[i], self.AnchorX[i], self.AnchorY[i], self.AnchorZ[i])
	end
end

function Locomotion:anchors(): number
	return self.AnchorCount
end

return Locomotion
