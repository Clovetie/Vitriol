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
-- Alternate which forward foot lands first. Tables are module constants, not
-- Instances or per-frame allocations; the planted tips stay fixed for a stride.
local RAY_ORDER_A = { 1, 2, 4, 6, 7, 5, 3 }
local RAY_ORDER_B = { 1, 2, 5, 7, 6, 4, 3 }

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
	self.AnchorAge = math.huge
	self.StrideNumber = 0
	self.AnchorX = {}
	self.AnchorY = {}
	self.AnchorZ = {}
	self.AnchorNX = {}
	self.AnchorNY = {}
	self.AnchorNZ = {}
	self.AnchorMaterial = {}
	self.AnchorPart = {} -- existing raycast hit Instances; no new game objects
	self.AnchorTendril = {}
	self.DirectionX = {}
	self.DirectionY = {}
	self.DirectionZ = {}
	self.RayCount = self.Movement.AnchorRayCount or 7
	self.LastUpX, self.LastUpY, self.LastUpZ = 0, 1, 0
	self.Crouch = 0
	self.PassageMaxY, self.PassageMinY = nil, nil
	return self
end

-- Only while beneath a real authored roof/lintel. Nil restores the approved
-- high stance and the original wall/ceiling anchoring everywhere else.
function Locomotion:setPassageHeight(maxY: number?, minY: number?): ()
	self.PassageMaxY, self.PassageMinY = maxY, minY
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

function Locomotion:setCrouch(amount: number): ()
	self.Crouch = clamp(amount, 0, 1)
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
	-- Diagonal DOWNWARD probes find multiple distinct footfalls on one flat
	-- floor. The old horizontal-only fan saw just one floor contact and
	-- permanently fell back to a sliding, unsupported glide.
	self.DirectionX[4], self.DirectionY[4], self.DirectionZ[4] = sideX, -0.60, sideZ
	self.DirectionX[5], self.DirectionY[5], self.DirectionZ[5] = -sideX, -0.60, -sideZ
	self.DirectionX[6], self.DirectionY[6], self.DirectionZ[6] = horizontalX * 0.9 + sideX * 0.35, -0.60, horizontalZ * 0.9 + sideZ * 0.35
	self.DirectionX[7], self.DirectionY[7], self.DirectionZ[7] = horizontalX * 0.9 - sideX * 0.35, -0.60, horizontalZ * 0.9 - sideZ * 0.35
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
	-- A roof underside is a clearance boundary, not a load-bearing floor.
	-- A low passage cannot reuse rooftop contacts to haul its body upward.
	if self.PassageMaxY ~= nil and position.Y > self.PassageMaxY+0.1 then return false end
	local normal = result.Normal
	self.AnchorCount = count
	self.AnchorX[count] = position.X + normal.X * 0.12
	self.AnchorY[count] = position.Y + normal.Y * 0.12
	self.AnchorZ[count] = position.Z + normal.Z * 0.12
	self.AnchorNX[count] = normal.X
	self.AnchorNY[count] = normal.Y
	self.AnchorNZ[count] = normal.Z
	self.AnchorMaterial[count] = result.Material and result.Material.Name or "Default"
	self.AnchorPart[count] = result.Instance
	-- The rig has two banks along the travel axis: front legs reach forward,
	-- rear legs brace/push. Reserve two probe contacts per bank and map each
	-- ray to an actual root in the correct bank, never to a crossed tendril.
	local legs = math.max(self.Stats.TendrilCount or 8, 1)
	local frontCount = math.ceil(legs / 2)
	local front = index == 1 or index == 6 or index == 7
	local hx, hz = self.DirectionX[1] or 1, self.DirectionZ[1] or 0
	local bestLeg, bestScore = nil, -math.huge
	for leg = 1, legs do
		local free = true
		for i = 1, count - 1 do
			if self.AnchorTendril[i] == leg then free = false; break end
		end
		if free and (leg <= frontCount) == front then
			local slots = front and frontCount or legs - frontCount
			local slot = front and leg or leg - frontCount
			local spread = (slot - (slots + 1) * 0.5) / math.max((slots - 1) * 0.5, 1)
			local forward = front and 0.8 or -0.8
			local side = spread * 0.85
			local dx, dz = hx * forward - hz * side, hz * forward + hx * side
			local length = math.sqrt(dx * dx + dz * dz)
			local score = ((position.X - x) * dx + (position.Z - z) * dz) / length - math.abs(spread) * 0.01
			if score > bestScore then bestScore, bestLeg = score, leg end
		end
	end
	self.AnchorTendril[count] = bestLeg or ((index - 1) % legs + 1)
	return true
end

function Locomotion:step(dt: number, x: number, y: number, z: number, stanceX: number?, stanceZ: number?, stanceCount: number?): (number, number, number, number, number, number)
	local reach = (self.Stats.TendrilReach or 14) * (self.Movement.ProbeReachMultiplier or 1.15)
	local minAnchors = self.Movement.MinAnchors or 2
	local strideSeconds = math.max(self.Movement.HaulSeconds or 0.35, 0.05)
	local refresh = self.AnchorCount < minAnchors or self.AnchorAge >= strideSeconds
	if not refresh then
		for i = 1, self.AnchorCount do
			local dx, dy, dz = self.AnchorX[i] - x, self.AnchorY[i] - y, self.AnchorZ[i] - z
			if dx * dx + dy * dy + dz * dz > reach * reach
				or (self.PassageMaxY ~= nil and self.AnchorY[i] > self.PassageMaxY+0.1) then
				refresh = true -- displaced or rooftop purchase must be re-evaluated
				break
			end
		end
	end
	if refresh then
		self:_clearAnchors()
		self:_buildDirections(x, y, z)
		self.StrideNumber += 1
		local order = self.StrideNumber % 2 == 0 and RAY_ORDER_B or RAY_ORDER_A
		local maxAnchors = self.Movement.MaxAnchors or 4
		for i = 1, #order do
			if self.AnchorCount >= maxAnchors then break end
			local ray = order[i]
			if ray <= self.RayCount then
				if self:_tryAnchor(ray, x, y, z, reach) and ray == 2 and self.AnchorNY[self.AnchorCount] > 0.7 then
					-- Use the downward hit to place side/forward feet as far out
					-- as the REAL tendril can reach. A fixed steep ray landed feet
					-- too close to the body, capping travel despite faster speed.
					local height = math.max(0, y - self.AnchorY[self.AnchorCount] + 0.12)
					local legReach = self.Stats.TendrilReach or 14
					local lateral = math.sqrt(math.max(legReach * legReach - height * height, 0)) * 0.85
					if lateral > 0.1 then
						local slope = clamp(height / lateral, 0.30, 1.4)
						for sideRay = 4, 7 do self.DirectionY[sideRay] = -slope end
					end
				end
			end
		end
		self.AnchorAge = 0
	else
		self.AnchorAge += dt
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
		upX, upY, upZ = unit(upX, upY, upZ)
		if upX * upX + upY * upY + upZ * upZ < EPS then
			upX, upY, upZ = self.LastUpX, self.LastUpY, self.LastUpZ
		end
		-- The planted feet carry the body at a fraction of tendril reach,
		-- rather than letting its belly drag at radius-height. Keep a radius of
		-- clearance even on short genomes or when a wall is the support surface.
		local standing = math.max((self.Stats.CoreRadius or 1.5) + 0.12,
			(self.Stats.TendrilReach or 14) * (self.Movement.SupportHeightFraction or 0.34))
		local lowered = (self.Stats.CoreRadius or 1.5) + (self.Config.Kill and self.Config.Kill.ChompClearance or 0.55)
		local clearance = standing + (lowered - standing) * self.Crouch
		local goalX = centerX + upX * clearance
		local goalY = centerY + upY * clearance
		local goalZ = centerZ + upZ * clearance
		-- During grounded pursuit, the ray fan tells us WHERE THE FLOOR IS,
		-- not where to pull the body horizontally. Its forward-biased samples
		-- used to drive the core several studs beyond its real supporting feet.
		-- Instead, follow the moving centroid of planted tendrils with just a
		-- small prey-facing allowance. Feet move first, and the mass follows.
		if stanceX ~= nil and stanceZ ~= nil and (stanceCount or 0) >= minAnchors
			and self.TargetX ~= nil and self.Crouch < EPS
			and math.abs((self.TargetY or y) - y) < (self.Stats.TendrilReach or 14) * 0.6 then
			local fx, _, fz = unit(self.TargetX - x, 0, (self.TargetZ or z) - z)
			local lead = (self.Stats.TendrilReach or 14) * (self.Movement.StanceBodyLeadFraction or 0.04)
			goalX, goalZ = stanceX + upX * clearance + fx * lead,
				stanceZ + upZ * clearance + fz * lead
		end
		if self.TargetX ~= nil then
			-- A shallow compression/release in each footfall makes support
			-- legible; it never lowers the core below safe surface clearance.
			local phase = clamp(self.AnchorAge / strideSeconds, 0, 1)
			local bob = math.sin(phase * math.pi) * (self.Movement.StepBobHeight or 0.18)
			goalX, goalY, goalZ = goalX + upX * bob, goalY + upY * bob, goalZ + upZ * bob
		end
		if self.TargetX == nil then
			-- With no living prey, keep the planted support but do not let the
			-- asymmetric foot fan march the Braid away from its last victim.
			local height = (x - centerX) * upX + (y - centerY) * upY + (z - centerZ) * upZ
			local correction = clearance - height
			goalX, goalY, goalZ = x + upX * correction, y + upY * correction, z + upZ * correction
		end
		local dx, dy, dz, distance = unit(goalX - x, goalY - y, goalZ - z)
		local grip = self.Movement.AnchorGrip or {}
		local gripSum = 0
		for i = 1, self.AnchorCount do
			gripSum += grip[self.AnchorMaterial[i]] or 0.6
		end
		local averageGrip = gripSum / math.max(self.AnchorCount, 1)
		local speed = math.max(self.Stats.HaulSpeed or 8, self.Movement.MinGroundHaulSpeed or 18) * averageGrip
		-- HaulSpeed is studs per SECOND. Dividing by the stride duration made
		-- the core snap to each centroid, then wait motionless for re-planting.
		-- Travel at a bounded speed while the alternating feet re-plant ahead.
		local amount = math.min(distance, speed * dt)
		moveX, moveY, moveZ = dx * amount, dy * amount, dz * amount
	else
		local targetX = self.TargetX or x
		local targetY = self.TargetY or y
		local targetZ = self.TargetZ or z
		local dx, dy, dz = unit(targetX - x, targetY - y, targetZ - z)
		local speed = (self.Stats.HaulSpeed or 8) * (self.Movement.GlideSpeedFraction or 0.45)
		moveX, moveY, moveZ = dx * speed * dt, dy * speed * dt, dz * speed * dt
		upX, upY, upZ = self.LastUpX, self.LastUpY, self.LastUpZ
	end
	-- Keep the SAME horizontal foot-led haul. Constrain only the vertical
	-- component when a measured doorway/ceiling would intersect the core.
	if self.PassageMaxY ~= nil then
		moveY = math.min(moveY, self.PassageMaxY-y)
		moveY = math.max(moveY, (self.PassageMinY or -math.huge)-y)
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
	if self.AnchorCount >= (self.Movement.MinAnchors or 2) then
		local x, y, z, nx, ny, nz = 0, 0, 0, 0, 0, 0
		for i = 1, self.AnchorCount do
			x, y, z = x + self.AnchorX[i], y + self.AnchorY[i], z + self.AnchorZ[i]
			nx, ny, nz = nx + self.AnchorNX[i], ny + self.AnchorNY[i], nz + self.AnchorNZ[i]
		end
		nx, ny, nz = unit(nx, ny, nz)
		rig:setSupportPlane(x / self.AnchorCount, y / self.AnchorCount, z / self.AnchorCount, nx, ny, nz)
	end
	for i = 1, self.AnchorCount do
		rig:seedFoot(self.AnchorTendril[i], self.AnchorX[i], self.AnchorY[i], self.AnchorZ[i])
	end
end

function Locomotion:anchors(): number
	return self.AnchorCount
end

return Locomotion
