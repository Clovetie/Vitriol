--!strict
-- BloodAdapter.luau
-- Location: ReplicatedStorage > Vitriol > Shared > BloodAdapter  (ModuleScript)
-- Purpose:  The only visual-blood caller in Vitriol. It reuses 24 authored
--           Gore.BloodDrop parts; no Instance is allocated during gameplay.
--           LOW/FULL content gates remain; missing authored parts disable visuals
--           without changing gameplay. BloodEngine is deliberately inactive.
-- Requires: Config/BloodConfig is injected by Bootstrap
-- Used by:  Bootstrap, HealthService, Creature/Body/KillChoreography
--
-- The bundled BloodEngine v1.1.x allocates droplets/decals; it remains installed
-- but cannot be called under the authored-objects-only policy.

local BloodAdapter = {}
BloodAdapter.__index = BloodAdapter

local SEVER_KINDS = {
	severed = true,
	chunk = true,
	viscera = true,
	gib_burst = true,
}

local function clamp01(value: number): number
	if value < 0 then
		return 0
	elseif value > 1 then
		return 1
	end
	return value
end

function BloodAdapter.new(options: any?): any
	local o = options or {}
	local self = setmetatable({}, BloodAdapter)
	self.Config = o.Config or {}
	self.IntensityName = o.Intensity or self.Config.DefaultIntensity or "LOW"
	self.Workspace = o.Workspace
	self.Parent = o.Parent
	self.Logger = o.Logger
	self.UsingFallback = true
	self.warned = false
	self.fallbackParts = {}
	self.fallbackCount = 0
	self.maxFallback = ((self.Config.Budget or {}).MaxActiveEmitters or 24)
	-- BloodEngine allocates droplets/decals at runtime. It is intentionally
	-- NOT attached under the authored-objects-only rule. Keep the supplied
	-- module for offline compatibility, never call its constructor or Emit.
	return self
end

function BloodAdapter:_logOnce(message: string): ()
	if self.warned then
		return
	end
	self.warned = true
	if self.Logger then
		self.Logger("info", message)
	end
end

function BloodAdapter:setIntensity(name: string): boolean
	local options = self.Config.Intensity or {}
	if options[name] == nil then
		return false
	end
	self.IntensityName = name
	return true
end

function BloodAdapter:intensity(): any
	local options = self.Config.Intensity or {}
	return options[self.IntensityName] or options.LOW or { BloodScale = 0 }
end

function BloodAdapter:_fallback(position: any, direction: any, scale: number, lifetime: number): boolean
	if self.Workspace == nil or position == nil then
		return false
	end
	local root = self.Workspace:FindFirstChild("Vitriol")
	local gore = root and root:FindFirstChild("Gore")
	if gore == nil then
		self:_logOnce("missing authored Workspace.Vitriol.Gore pool; blood visuals disabled")
		return false
	end
	local fallback = self.Config.Fallback or {}
	if fallback.Enabled == false then
		return false
	end
	local index = (self.fallbackCursor or 0) % self.maxFallback + 1
	local part = gore:FindFirstChild("BloodDrop_" .. tostring(index))
	if part == nil or not part:IsA("BasePart") then
		self:_logOnce("authored BloodDrop pool incomplete; blood visuals disabled")
		return false
	end
	self.fallbackCursor = index
	part.Size = Vector3.new(scale, scale, scale)
	part.CFrame = CFrame.new(position)
	part.Transparency = 0
	local materialName = fallback.ChunkMaterial or "Slate"
	part.Material = Enum.Material[materialName] or Enum.Material.Slate
	local rgb = self.Config.BloodColor or { 96, 12, 16 }
	part.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	-- Preauthored parts stay anchored; movement/expiry only change properties.
	self.fallbackCount = math.min(self.fallbackCount + 1, self.maxFallback)
	self.fallbackParts[index] = part
	self.fallbackExpiry = self.fallbackExpiry or {}
	self.fallbackExpiry[index] = os.clock() + lifetime
	return true
end

-- Called by Bootstrap's existing slow slot; no timer/Heartbeat/Instance is added.
function BloodAdapter:prune(now: number): ()
	if self.fallbackExpiry == nil then
		return
	end
	for index, expiry in pairs(self.fallbackExpiry) do
		if now >= expiry then
			local part = self.fallbackParts[index]
			if part then
				part.Transparency = 1
			end
			self.fallbackExpiry[index] = nil
		end
	end
end

function BloodAdapter:emit(kind: string, params: any): boolean
	local p = params or {}
	local policy = self:intensity()
	if SEVER_KINDS[kind] and policy.SeverVisuals == false then
		return false
	end
	if kind == "blood_pool" and policy.PoolDecals == false then
		return false
	end
	if (kind == "chunk" or kind == "gib_burst") and policy.ChunkScale == 0 then
		return false
	end
	local position = p.Position
	if position == nil then
		return false
	end
	local scale = clamp01(p.Intensity or 1) * (policy.BloodScale or 0.35)
	if scale <= 0 then
		return false
	end
	local direction = p.Direction
	if direction == nil and Vector3 ~= nil then
		direction = Vector3.new(0, 1, 0)
	end
	local kinds = self.Config.Kinds
	if kinds ~= nil and kinds[kind] ~= true then
		return false
	end
	local fallback = self.Config.Fallback or {}
	local lifetime = p.LifeTime or fallback.ChunkLifetime or ((self.Config.Engine or {}).PoolLifetimeSeconds or 180)

	local chunkSize = fallback.ChunkSize or { 0.05, math.huge }
	local dropScale = math.max(scale * 0.35, chunkSize[1] or 0.05)
	if chunkSize[2] ~= nil then
		dropScale = math.min(dropScale, chunkSize[2])
	end
	return self:_fallback(position, direction, dropScale, lifetime)
end

function BloodAdapter:destroy(): ()
	for _, part in pairs(self.fallbackParts) do
		part.Transparency = 1
	end
	table.clear(self.fallbackParts)
	self.fallbackExpiry = nil
	self.fallbackCount = 0
end

return BloodAdapter
