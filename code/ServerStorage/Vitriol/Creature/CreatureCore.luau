--!strict
-- CreatureCore.luau
-- Location: ServerStorage > Vitriol > Creature > CreatureCore  (ModuleScript)
-- Purpose:  One live, procedural Braid. It owns the code-generated Model, numeric
--           TendrilRig, anchor-and-haul Locomotion and optional Skeleton Replicator.
--           The creature is deliberately woundable but never killable: damage reduces
--           active tendrils and threat capacity, while the core remains alive until
--           the session or service explicitly despawns it.
-- Requires: injected TendrilRig, Locomotion, Fabrik, Skeleton, Replicator
-- Used by:  Services/CreatureService

local CreatureCore = {}
CreatureCore.__index = CreatureCore

local PI_OVER_TWO = math.pi * 0.5

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
	self.RenderParts = {}
	self.RenderCFrames = {}

	self.Model = Instance.new("Model")
	self.Model.Name = "Braid_" .. tostring(self.Id)
	self.Model:SetAttribute("CreatureId", self.Id)
	self.Model:SetAttribute("Archetype", "Braid")
	self.Model:SetAttribute("WoundLevel", 0)
	self.Model:SetAttribute("Threatening", true)
	self.Model.Parent = self.Parent

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
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	local coreDiameter = (self.Stats.CoreRadius or 1.5) * 2
	core.Size = Vector3.new(coreDiameter, coreDiameter, coreDiameter)
	core.Color = colorFrom(presentation.CoreColor or { 22, 18, 24 })
	core.Material = material
	core.Transparency = presentation.CoreTransparency or 0
	core.Anchored = true
	core.CanCollide = false
	core.CanTouch = false
	core.CanQuery = true
	core.CastShadow = presentation.Shadow ~= false
	core.Parent = self.Model
	self.CorePart = core
	self.RenderParts[1] = core
	self.RenderCFrames[1] = CFrame.new(self.X, self.Y, self.Z)

	local skeletons = self.TendrilRig:skeletons()
	local partIndex = 1
	for i = 1, #skeletons do
		local chain = skeletons[i]
		for j = 1, chain.count - 1 do
			partIndex = partIndex + 1
			local segment = Instance.new("Part")
			segment.Name = "Tendril_" .. tostring(i) .. "_" .. tostring(j)
			segment.Shape = Enum.PartType.Cylinder
			segment.Material = material
			segment.Color = colorFrom(presentation.TendrilColor or { 48, 36, 52 })
			segment.Transparency = presentation.SegmentTransparency or 0
			segment.Size = Vector3.new(chain.radius[j] * 2, chain.len[j] * (presentation.SegmentDepthMultiplier or 0.9), chain.radius[j] * 2)
			segment.Anchored = true
			segment.CanCollide = false
			segment.CanTouch = false
			segment.CanQuery = false
			segment.CastShadow = presentation.Shadow ~= false
			segment.Parent = self.Model
			self.RenderParts[partIndex] = segment
			self.RenderCFrames[partIndex] = CFrame.new(self.X, self.Y, self.Z)
		end
	end
	self.RenderCount = partIndex
end

function CreatureCore:setTarget(x: number, y: number, z: number, confidence: number?): ()
	self.TargetX, self.TargetY, self.TargetZ = x, y, z
	self.Locomotion:setTarget(x, y, z, confidence)
end

function CreatureCore:clearTarget(): ()
	self.TargetX, self.TargetY, self.TargetZ = nil, nil, nil
	self.Locomotion:clearTarget()
end

function CreatureCore:_segmentCFrame(x: number, y: number, z: number, nx: number, ny: number, nz: number, px: number, py: number, pz: number): any
	local midX, midY, midZ = (x + px) * 0.5, (y + py) * 0.5, (z + pz) * 0.5
	local from = Vector3.new(x, y, z)
	local to = Vector3.new(px, py, pz)
	local up = Vector3.new(nx, ny, nz)
	local cf = CFrame.lookAt(Vector3.new(midX, midY, midZ), to, up)
	if CFrame.Angles ~= nil then
		cf = cf * CFrame.Angles(PI_OVER_TWO, 0, 0)
	end
	return cf
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

function CreatureCore:step(dt: number): ()
	if self.Destroyed then
		return
	end
	self.Elapsed = self.Elapsed + dt
	local scale = 1 - self.WoundLevel * (1 - (self.Wounds.SpeedMultiplierAtMax or 0.2))
	if self.Disabled then
		scale = 0
	end
	local dx, dy, dz, upX, upY, upZ
	if self.Disabled then
		dx, dy, dz, upX, upY, upZ = self.Locomotion:hold()
	else
		dx, dy, dz, upX, upY, upZ = self.Locomotion:step(dt * scale, self.X, self.Y, self.Z)
	end
	self.X, self.Y, self.Z = self.X + dx, self.Y + dy, self.Z + dz
	self.UpX, self.UpY, self.UpZ = upX, upY, upZ
	self.TendrilRig:setCore(self.X, self.Y, self.Z)
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

function CreatureCore:position(): number, number, number
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
		self.Model:Destroy()
	end
end

return CreatureCore
