--!strict
-- CreatureCore.luau
-- Location: ServerStorage > Vitriol > Creature > CreatureCore  (ModuleScript)
-- Purpose:  One live, procedural Braid using the preauthored Braid_1 Model,
--           numeric TendrilRig, anchor-and-haul Locomotion and optional Replicator.
--           The creature is deliberately woundable but never killable: damage reduces
--           active tendrils and threat capacity, while the core remains alive until
--           the session or service explicitly despawns it.
-- Requires: injected TendrilRig, Locomotion, Fabrik, Skeleton, Replicator
-- Used by:  Services/CreatureService

local CreatureCore = {}
CreatureCore.__index = CreatureCore

local function clamp(value: number, low: number, high: number): number
	if value < low then
		return low
	elseif value > high then
		return high
	end
	return value
end

local function materialFrom(config: any): any
	local name = config.Material or "Slate"
	if Enum and Enum.Material then
		return Enum.Material[name] or Enum.Material.Slate
	end
	return name
end

local function colorFrom(rgb: any): any
	if Color3 == nil then
		return rgb
	end
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function setIf(part: any, key: string, value: any): ()
	if part ~= nil then
		part[key] = value
	end
end

function CreatureCore.new(options: any): any
	local o = options or {}
	local self = setmetatable({}, CreatureCore)
	self.Id = o.Id or 1
	self.Config = o.Config or {}
	self.Monster = o.Monster or {}
	self.Presentation = self.Monster.Presentation or {}
	self.Wounds = self.Monster.Wounds or {}
	self.Workspace = o.Workspace
	self.Parent = o.Parent
	self.Logger = o.Logger
	self.Replicator = o.Replicator
	self.Barricade = o.Barricade
	self.Placement = o.Placement
	self.HouseCover = o.HouseCover
	self.HouseAccess = o.HouseAccess
	self.HouseRecovery = false
	self.CoverPreyX, self.CoverPreyZ = nil, nil
	self.CoverExitIntent, self.CoverIngressIntent = false, false
	self.Stats = o.Stats
	self.Genome = o.Genome
	self.X = o.X or 0
	self.Y = o.Y or 0
	self.Z = o.Z or 0
	self.UpX, self.UpY, self.UpZ = 0, 1, 0
	self.Elapsed = 0
	self.WoundLevel = 0
	self.Disabled = false
	self.Destroyed = false
	self.TargetX, self.TargetY, self.TargetZ = nil, nil, nil
	self.AttackPhase, self.AttackPlayer = nil, nil
	self.AttackAge, self.AttackCooldownUntil = 0, 0
	self.AttackX, self.AttackY, self.AttackZ = nil, nil, nil
	self.ChargeX, self.ChargeZ, self.ChargeTraveled = 0, 0, 0
	self.RenderParts = {}
	self.RenderCFrames = {}
	self.RenderQuery = {}
	self.Dormant = false

	self.Model = assert(o.Model, "[Vitriol.Creature] authored Braid model required")
	if not self.Model:IsA("Model") then
		error("[Vitriol.Creature] Braid_1 must be a Model", 0)
	end
	self.Model:SetAttribute("CreatureId", self.Id)
	self.Model:SetAttribute("Archetype", "Braid")
	self.Model:SetAttribute("WoundLevel", 0)
	self.Model:SetAttribute("Threatening", true)
	local rayParams = nil
	if RaycastParams ~= nil then
		rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { self.Model }
	end
	self.RaycastParams = rayParams

	self.TendrilRig = o.TendrilRig.new(self.Stats, {
		Skeleton = o.Skeleton,
		Fabrik = o.Fabrik,
		Noise = o.Noise,
		Config = self.Monster,
		Seed = self.Id * 97 + 11,
		CoreX = self.X,
		CoreY = self.Y,
		CoreZ = self.Z,
	})
	self.Locomotion = o.Locomotion.new(self.Stats, {
		Config = self.Monster,
		Workspace = self.Workspace,
		RaycastParams = rayParams,
	})
	self:_buildVisual()
	self:_render()
	return self
end

function CreatureCore:_buildVisual(): ()
	local presentation = self.Presentation
	local material = materialFrom(presentation)
	local core = self.Model:FindFirstChild("Core")
	if core == nil or not core:IsA("BasePart") then
		error("[Vitriol.Creature] authored Braid_1.Core missing", 0)
	end
	local coreDiameter = (self.Stats.CoreRadius or 1.5) * 2
	core.Size = Vector3.new(coreDiameter, coreDiameter, coreDiameter)
	core.Color = colorFrom(presentation.CoreColor or { 22, 18, 24 })
	core.Material = material
	core.Transparency = presentation.CoreTransparency or 0
	core.CanQuery = true
	self.CorePart = core
	self.RenderParts[1] = core
	self.RenderQuery[1] = core.CanQuery
	self.RenderCFrames[1] = CFrame.new(self.X, self.Y, self.Z)

	local skeletons = self.TendrilRig:skeletons()
	local partIndex = 1
	for i = 1, #skeletons do
		local chain = skeletons[i]
		for j = 1, chain.count - 1 do
			local segment = self.Model:FindFirstChild("Tendril_" .. i .. "_" .. j)
			if segment == nil or not segment:IsA("BasePart") then
				error(("[Vitriol.Creature] authored Braid segment missing: %d_%d"):format(i, j), 0)
			end
			partIndex = partIndex + 1
			segment.Material = material
			segment.Color = colorFrom(presentation.TendrilColor or { 48, 36, 52 })
			segment.Transparency = presentation.SegmentTransparency or 0
			-- Roblox Cylinder length runs along LOCAL X (not Y). A small overlap
			-- hides seams between independently damped joint positions.
			segment.Size = Vector3.new(chain.len[j] * (presentation.SegmentDepthMultiplier or 1.08), chain.radius[j] * 2, chain.radius[j] * 2)
			self.RenderParts[partIndex] = segment
			self.RenderQuery[partIndex] = segment.CanQuery
			self.RenderCFrames[partIndex] = CFrame.new(self.X, self.Y, self.Z)
		end
	end
	-- Hide unused authored segments for shorter genomes. No render slot is added.
	for _, part in ipairs(self.Model:GetChildren()) do
		if part.Name ~= "Core" and not table.find(self.RenderParts, part) then
			part.Transparency = 1
		end
	end
	self.RenderCount = partIndex
end

function CreatureCore:setTarget(x: number, y: number, z: number, confidence: number?): ()
	self.TargetX, self.TargetY, self.TargetZ = x, y, z
	self.Locomotion:setTarget(x, y, z, confidence)
	self.TendrilRig:setTarget(x, y, z)
end

function CreatureCore:clearTarget(): ()
	self.TargetX, self.TargetY, self.TargetZ = nil, nil, nil
	self.Locomotion:clearTarget()
	self.TendrilRig:clearTarget()
end

-- A grounded attack is a visible, interruptible CROUCH -> CHARGE -> contact
-- -> EAT/RECOVER sequence. Neither a ray probe nor a high core can kill a
-- player: CreatureService checks live distance after the lowered lunge.
function CreatureCore:canPrepareChomp(x: number, y: number, z: number): boolean
	if not self:isThreatening() or self.AttackPhase ~= nil or self.Elapsed < self.AttackCooldownUntil then return false end
	if self.Locomotion:anchors() < ((self.Monster.Locomotion or {}).MinAnchors or 2) then return false end
	local config = self.Monster.Kill or {}
	local floorY = self.TendrilRig.SupportY
	if floorY == nil then return false end
	local vertical = y - floorY
	if vertical < -1 or vertical > (config.TargetHeightAboveFloor or 4.5) then return false end
	local dx, dz = x - self.X, z - self.Z
	return dx * dx + dz * dz <= (config.PrepareDistance or 7.5) ^ 2
end

function CreatureCore:prepareChomp(player: any, x: number, y: number, z: number): boolean
	if not self:canPrepareChomp(x, y, z) then return false end
	self.AttackPlayer = player
	self.AttackX, self.AttackY, self.AttackZ = x, y, z
	self.AttackPhase, self.AttackAge = "CROUCH", 0
	return true
end

function CreatureCore:updateChompTarget(x: number, y: number, z: number): ()
	if self.AttackPhase == "CROUCH" then
		self.AttackX, self.AttackY, self.AttackZ = x, y, z
		self:setTarget(x, y, z)
	end
end

function CreatureCore:chompLanded(): ()
	if self.AttackPhase ~= "CHARGE" then return end
	self.AttackPhase, self.AttackAge = "EAT", 0
end

function CreatureCore:abortChomp(): ()
	if self.AttackPhase == nil then return end
	self.AttackPhase, self.AttackAge = "RECOVER", 0
	self.AttackCooldownUntil = self.Elapsed + (self.Monster.Kill and self.Monster.Kill.MissCooldownSeconds or 1.2)
end

function CreatureCore:_advanceChomp(dt: number): ()
	local phase = self.AttackPhase
	if phase == nil then self.Locomotion:setCrouch(0); return end
	local config = self.Monster.Kill or {}
	self.AttackAge += dt
	if phase == "CROUCH" then
		local duration = math.max(config.CrouchSeconds or 0.55, 0.01)
		self.Locomotion:setCrouch(self.AttackAge / duration)
		if self.AttackAge >= duration then
			local dx, dz = (self.AttackX or self.X) - self.X, (self.AttackZ or self.Z) - self.Z
			local length = math.sqrt(dx * dx + dz * dz)
			if length < 1e-4 then
				-- A player directly under the high body must still be chompable.
				dx, dz, length = self.TendrilRig.HeadingX, self.TendrilRig.HeadingZ, 1
			end
			self.ChargeX, self.ChargeZ = dx / length, dz / length
			self.ChargeTraveled = 0
			self.AttackPhase, self.AttackAge = "CHARGE", 0
		end
	elseif phase == "CHARGE" then
		self.Locomotion:setCrouch(1)
		if self.AttackAge >= (config.ChargeSeconds or 0.24) then self:abortChomp() end
	elseif phase == "EAT" then
		self.Locomotion:setCrouch(1)
		if self.AttackAge >= (config.DurationSeconds or 5.8) + 0.2 then
			self.AttackPhase, self.AttackAge = "RECOVER", 0
		end
	elseif phase == "RECOVER" then
		local duration = math.max(config.RecoverySeconds or 0.55, 0.01)
		self.Locomotion:setCrouch(1 - self.AttackAge / duration)
		if self.AttackAge >= duration then
			self.AttackPhase, self.AttackPlayer = nil, nil
			self.Locomotion:setCrouch(0)
		end
	end
end

-- A character (including a corpse) is never a structural foothold. Update
-- the cached raycast filter at think cadence, not inside every frame's ray fan.
function CreatureCore:excludeCharacters(players: any): ()
	if self.RaycastParams == nil then return end
	local excluded = { self.Model }
	for i = 1, #players do
		local character = players[i].Character
		if character then excluded[#excluded + 1] = character end
	end
	self.RaycastParams.FilterDescendantsInstances = excluded
end

function CreatureCore:_segmentCFrame(x: number, y: number, z: number, nx: number, ny: number, nz: number, px: number, py: number, pz: number): any
	local mid = Vector3.new((x + px) * 0.5, (y + py) * 0.5, (z + pz) * 0.5)
	local dx, dy, dz = px - x, py - y, pz - z
	local length = math.sqrt(dx * dx + dy * dy + dz * dz)
	if length < 1e-6 then
		return CFrame.new(mid)
	end
	-- Cylinder extends along its local X. Use a stable orthonormal basis
	-- even when the segment points straight up (parallel to the support normal).
	local ux, uy, uz = dx / length, dy / length, dz / length
	local hx, hy, hz = nx, ny, nz
	if math.abs(ux * hx + uy * hy + uz * hz) > 0.95 then
		hx, hy, hz = 0, 0, 1
		if math.abs(uz) > 0.95 then
			hx, hy, hz = 0, 1, 0
		end
	end
	local zx, zy, zz = uy * hz - uz * hy, uz * hx - ux * hz, ux * hy - uy * hx
	local zLength = math.sqrt(zx * zx + zy * zy + zz * zz)
	if zLength < 1e-6 then
		return CFrame.new(mid)
	end
	zx, zy, zz = zx / zLength, zy / zLength, zz / zLength
	local yx, yy, yz = zy * uz - zz * uy, zz * ux - zx * uz, zx * uy - zy * ux
	return CFrame.fromMatrix(mid, Vector3.new(ux, uy, uz), Vector3.new(yx, yy, yz), Vector3.new(zx, zy, zz))
end

function CreatureCore:_render(): ()
	local skeletons = self.TendrilRig:skeletons()
	self.RenderCFrames[1] = CFrame.new(self.X, self.Y, self.Z)
	local partIndex = 1
	for i = 1, #skeletons do
		local chain = skeletons[i]
		for j = 1, chain.count - 1 do
			partIndex = partIndex + 1
			self.RenderCFrames[partIndex] = self:_segmentCFrame(
				chain.x[j], chain.y[j], chain.z[j],
				self.UpX, self.UpY, self.UpZ,
				chain.x[j + 1], chain.y[j + 1], chain.z[j + 1]
			)
		end
	end
	if self.Workspace and self.Workspace.BulkMoveTo then
		self.Workspace:BulkMoveTo(self.RenderParts, self.RenderCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	else
		-- Headless/session fallback and a useful Studio fallback for old engine builds.
		for i = 1, self.RenderCount do
			self.RenderParts[i].CFrame = self.RenderCFrames[i]
		end
	end
end

-- Daytime withdrawal reuses the authored model; no replacement or cloning.
function CreatureCore:setDormant(value: boolean): ()
	local dormant = value == true
	if self.Dormant == dormant or self.Destroyed then return end
	self.Dormant = dormant
	self.Model:SetAttribute("Dormant", dormant)
	if dormant then
		self:clearTarget()
		self.CoverExitIntent, self.CoverIngressIntent = false, false
		self.HouseRecovery = false
		-- Every new Night starts without a phantom clue or a held patrol goal.
		self.SearchClueAt, self.SearchMode, self.SearchGoalX = nil, nil, nil
		self.SearchGoalZ, self.NoiseInvestigatedId, self.SearchNoiseId = nil, nil, nil
		self.SearchRegionNextIndex, self.SearchRegionTries = nil, nil
		if self.HouseCover then self.HouseCover:loseContact() end
		if self.AttackPhase ~= "EAT" then
			self.AttackPhase, self.AttackPlayer = nil, nil
			self.Locomotion:setCrouch(0)
		end
	else
		self.Locomotion.AnchorAge = math.huge
	end
	for i = 1, self.RenderCount do
		local part = self.RenderParts[i]
		part.Transparency = dormant and 1 or (i == 1 and (self.Presentation.CoreTransparency or 0)
			or (self.Presentation.SegmentTransparency or 0))
		part.CanQuery = not dormant and self.RenderQuery[i] or false
	end
end

function CreatureCore:step(dt: number): ()
	if self.Destroyed or self.Dormant then
		return
	end
	self.Elapsed = self.Elapsed + dt
	if self.Disabled and self.AttackPhase ~= nil then
		self.AttackPhase, self.AttackPlayer = nil, nil
	end
	self:_advanceChomp(dt)
	-- A low numeric TargetY alone cannot compress an anchored high stance.
	-- During ONLY the clue-less, bounded house egress use the existing
	-- foot-supported crouch to fit below the authored lintel before moving
	-- outward. Real prey/chomp owns the normal stance/crouch immediately.
	local reason=self.DecisionReason
	if self.AttackPhase==nil and self.ExitSweepCrouch ~= nil
		and (reason=="physical-house-exit-lowering" or reason=="scanning-house-exit"
			or reason=="physical-house-exit" or reason=="physical-house-exit-stage") then
		self.Locomotion:setCrouch(self.ExitSweepCrouch)
	end
	local scale = 1 - self.WoundLevel * (1 - (self.Wounds.SpeedMultiplierAtMax or 0.2))
	if self.Disabled then
		scale = 0
	end
	local passage = self.HouseAccess
	local radius = self.Stats.CoreRadius or 1.5
	if passage and not self.Disabled then
		local cap, minY = passage:heightCap(self.X,self.Y,self.Z,radius)
		self.Locomotion:setPassageHeight(cap,minY)
	else
		self.Locomotion:setPassageHeight(nil,nil)
	end
	local dx, dy, dz, upX, upY, upZ
	if self.Disabled then
		dx, dy, dz, upX, upY, upZ = self.Locomotion:hold()
	else
		local stanceX, stanceZ, stanceCount = self.TendrilRig:stanceCentroid()
		dx, dy, dz, upX, upY, upZ = self.Locomotion:step(dt * scale, self.X, self.Y, self.Z,
			stanceX, stanceZ, stanceCount)
	end
	if self.AttackPhase == "CHARGE" then
		local kill = self.Monster.Kill or {}
		local distance = math.min(math.max(0, (kill.ChargeDistance or 4.5) - self.ChargeTraveled),
			(kill.ChargeDistance or 4.5) * dt / math.max(kill.ChargeSeconds or 0.24, 0.01))
		dx, dz = self.ChargeX * distance, self.ChargeZ * distance
		self.ChargeTraveled += distance
	elseif self.AttackPhase ~= nil then
		-- Root in place for the telegraphed crouch, the chomp and the rise.
		dx, dz = 0, 0
	end
	if passage and not self.Disabled then
		dx,dy,dz = passage:constrain(self.X,self.Y,self.Z,dx,dy,dz,radius,dt,self.HouseRecovery)
	end
	-- Physically honor the one preauthored garage barrier. The Braid presses it
	-- for a bounded tell before breaching; it cannot teleport through a boarded
	-- entry merely because BulkMoveTo bypasses physics on anchored rig parts.
	if self.TargetX ~= nil and self.AttackPhase == nil then
		-- Empty authored defenses are the normal case (the Tool stays stored).
		-- Skip even the interception calls on the 60 Hz creature frame path.
		local gate = self.Barricade
		if gate and gate.boarded then
			local movingThrough = gate:crossing(self.X, self.Z, self.X + dx, self.Z + dz)
			-- Foot-led hauling can settle short of the gate, so a real nearby
			-- cross-gate pursuit must still build breach pressure on idle frames.
			local bracing = gate:pressing(self.X, self.Z, self.TargetX, self.TargetZ,
				self.Locomotion.AnchorPart, self.Locomotion.AnchorCount)
			if (movingThrough or bracing) and not gate:press(dt) and movingThrough then
				dx, dz = 0, 0
			end
		end
		local placement = self.Placement
		if placement and placement.Active[1] ~= nil then
			local placed = placement:intercept(self.X, self.Z, self.X + dx, self.Z + dz)
			if placed and not placement:press(placed, dt) then dx, dz = 0, 0 end
		end
	end
	-- The original furniture is solid in both directions, even when the
	-- Braid lost prey or began charging before cover was placed. Damage needs
	-- nearby sustained bracing toward sensed prey, a genuinely recent INSIDE
	-- memory on ingress, or a physical egress toward a server-owned clue/lure.
	-- Neither an expired/outside memory nor a hidden live prey root authorizes it.
	local cover = self.HouseCover
	if cover and cover.activeCount > 0 then
		local crossing = cover:intercept(self.X, self.Z, self.X + dx, self.Z + dz)
		local bracing = nil
		if self.TargetX ~= nil and self.AttackPhase == nil then
			if self.CoverPreyX ~= nil then
				-- Freshly sensed prey: brace against the ACTUAL doorway waypoint,
				-- not a deep-room straight ray through a solid pier.
				bracing = cover:bracing(self.X, self.Z, self.TargetX, self.TargetZ)
			elseif self.CoverIngressIntent then
				-- Sight can break behind the original cover while the body remains
				-- braced. ONLY a still-valid, genuinely seen indoor memory can
				-- continue its bounded contact tell from outside; the waypoint
				-- must still cross the actual nearby original item.
				bracing = cover:bracing(self.X, self.Z, self.TargetX, self.TargetZ)
			elseif self.CoverExitIntent then
				-- A generic remembered clue/lure motivates EXIT only, never a
				-- hidden-player-finding breach from outside the house.
				bracing = cover:bracing(self.X, self.Z, self.TargetX, self.TargetZ, true)
			end
		end
		local broke = false
		if bracing then broke = cover:press(bracing, dt, self)
		else cover:loseContact() end
		if crossing and (crossing ~= bracing or not broke) then dx, dz = 0, 0 end
	end
	self.X, self.Y, self.Z = self.X + dx, self.Y + dy, self.Z + dz
	self.UpX, self.UpY, self.UpZ = upX, upY, upZ
	self.TendrilRig:setCore(self.X, self.Y, self.Z, dt)
	self.Locomotion:applyAnchors(self.TendrilRig)
	local urgency = self.TargetX ~= nil and (self.Disabled and 0 or 0.8) or 0
	self.TendrilRig:step(dt, urgency)
	self:_render()
	if self.Replicator then
		self.Replicator:publish(dt, nil, self.TendrilRig:skeletons(), self.X, self.Y, self.Z)
	end
end

function CreatureCore:wound(amount: number): number
	if self.Destroyed then
		return self.WoundLevel
	end
	self.WoundLevel = clamp(self.WoundLevel + math.max(amount, 0), 0, self.Wounds.Max or 1)
	local disableAt = self.Wounds.DisableThreatAt or 0.85
	self.Disabled = self.WoundLevel >= disableAt
	local fraction = 1 - self.WoundLevel * (1 - (self.Wounds.ActiveTendrilFractionAtMax or 0.25))
	self.TendrilRig:setActiveFraction(fraction)
	self.Model:SetAttribute("WoundLevel", self.WoundLevel)
	self.Model:SetAttribute("Threatening", not self.Disabled)
	if self.WoundLevel > 0 and self.Presentation.WoundColor then
		local woundColor = colorFrom(self.Presentation.WoundColor)
		for i = 1, self.RenderCount do
			self.RenderParts[i].Color = woundColor
		end
	end
	if self.Disabled then
		self:clearTarget()
	end
	return self.WoundLevel
end

function CreatureCore:isThreatening(): boolean
	return not self.Disabled and not self.Destroyed
end

function CreatureCore:position(): (number, number, number)
	return self.X, self.Y, self.Z
end

function CreatureCore:snapshot(): any
	return {
		id = self.Id,
		x = self.X,
		y = self.Y,
		z = self.Z,
		wound = self.WoundLevel,
		threatening = self:isThreatening(),
		anchors = self.Locomotion:anchors(),
	}
end

function CreatureCore:destroy(): ()
	if self.Destroyed then
		return
	end
	self.Destroyed = true
	if self.Model then
		self.Model:SetAttribute("Threatening", false)
		for _, part in ipairs(self.Model:GetChildren()) do
			if part:IsA("BasePart") then
				part.Transparency = 1
				part.CanQuery = false
			end
		end
	end
end

return CreatureCore
