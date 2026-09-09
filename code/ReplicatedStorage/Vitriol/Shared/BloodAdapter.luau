--!strict
-- BloodAdapter.luau
-- Location: ReplicatedStorage > Vitriol > Shared > BloodAdapter  (ModuleScript)
-- Purpose:  The only visual-blood caller in Vitriol. It integrates the upstream
--           BloodEngine API when a ModuleScript is installed in the documented
--           hierarchy, applies the LOW/FULL content gate, enforces a bounded
--           fallback, and never lets a missing asset break gameplay.
-- Requires: Config/BloodConfig is injected by Bootstrap
-- Used by:  Bootstrap, HealthService, Creature/Body/KillChoreography
--
-- BloodEngine reference: rotntake/BloodEngine v1.1.x. Its public surface is
-- BloodEngine.new(settings), Engine:Emit(origin, direction, data?) and
-- Engine:EmitAmount(origin, direction, amount, data?). Vitriol deliberately uses
-- Emit, not EmitAmount: EmitAmount yields between droplets and would create a
-- second scheduler inside an otherwise cadence-owned server.

local BloodAdapter = {}
BloodAdapter.__index = BloodAdapter

local SEVER_KINDS = {
	severed = true,
	chunk = true,
	viscera = true,
	gib_burst = true,
}

local function child(parent: any, name: string): any
	if parent == nil then
		return nil
	end
	return parent:FindFirstChild(name)
end

local function moduleAt(root: any, path: string): any
	local node = root
	for name in string.gmatch(path, "[^/]+") do
		node = child(node, name)
		if node == nil then
			return nil
		end
	end
	return node
end

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
	self.ServerStorage = o.ServerStorage
	self.ReplicatedStorage = o.ReplicatedStorage
	self.Parent = o.Parent
	self.Logger = o.Logger
	self.Engine = nil
	self.EngineModule = nil
	self.UsingFallback = true
	self.warned = false
	self.fallbackParts = {}
	self.fallbackCount = 0
	self.maxFallback = ((self.Config.Budget or {}).MaxActiveEmitters or 24)
	self:_attach(o.BloodModule)
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

function BloodAdapter:_settings(): any
	local engine = self.Config.Engine or {}
	local settings = {
		Limit = engine.Limit or 120,
		FolderName = engine.FolderName or "Vitriol_Blood",
		Type = engine.Type or "Default",
		RandomOffset = engine.RandomOffset == true,
		OffsetRange = engine.OffsetRange or { -2, 2 },
		DropletVelocity = engine.DropletVelocity or { 1, 2 },
		DropletDelay = engine.DropletDelay or { 0, 0 },
		Expansion = engine.Expansion ~= false,
		MaximumSize = engine.MaximumSize or 0.7,
		Filter = {},
	}
	if self.Parent then
		settings.Filter[1] = self.Parent
	end
	if Vector3 ~= nil then
		local size = engine.StartingSize or { 0.04, 0.24, 0.04 }
		settings.StartingSize = Vector3.new(size[1], size[2], size[3])
	end
	if Color3 ~= nil then
		local color = self.Config.BloodColor or { 96, 12, 16 }
		settings.DropletColor = Color3.fromRGB(color[1], color[2], color[3])
	end
	return settings
end

function BloodAdapter:_attach(injected: any?): boolean
	local module = injected
	if module == nil then
		local locations = (self.Config.Engine or {}).ModuleLocations or {}
		for i = 1, #locations do
			local location = locations[i]
			local root = nil
			if string.sub(location, 1, 14) == "ServerStorage/" then
				root = self.ServerStorage
			elseif string.sub(location, 1, 18) == "ReplicatedStorage/" then
				root = self.ReplicatedStorage
			end
			local relative = string.gsub(location, "^[^/]+/", "")
			module = moduleAt(root, relative)
			if module ~= nil then
				-- A source checkout may represent BloodEngine as a Folder with
				-- init.lua, while Studio may hold a ModuleScript named BloodEngine.
				-- Accept both Explorer shapes without changing the gameplay seam.
				local initChild = child(module, "init")
				if initChild ~= nil then
					module = initChild
				end
				break
			end
		end
	end
	if module == nil then
		self:_logOnce("BloodEngine not found; using the bounded stylised fallback")
		return false
	end

	local ok, loaded = pcall(require, module)
	if not ok or loaded == nil or type(loaded.new) ~= "function" then
		self:_logOnce("BloodEngine was present but could not be initialised; using fallback")
		return false
	end
	local made, engine = pcall(loaded.new, self:_settings())
	if not made or engine == nil or type(engine.Emit) ~= "function" then
		self:_logOnce("BloodEngine API mismatch; expected new() and Emit(); using fallback")
		return false
	end
	self.EngineModule = loaded
	self.Engine = engine
	self.UsingFallback = false
	if self.Logger then
		self.Logger("info", "BloodEngine connected")
	end
	return true
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
	if Instance == nil or self.Workspace == nil or position == nil then
		return false
	end
	local folder = self.Parent
	if folder == nil then
		folder = self.Workspace:FindFirstChild("Vitriol")
	end
	if folder == nil then
		return false
	end
	local fallback = self.Config.Fallback or {}
	if fallback.Enabled == false then
		return false
	end
	local gore = folder:FindFirstChild("Gore")
	if gore == nil then
		gore = Instance.new("Folder")
		gore.Name = "Gore"
		gore.Parent = folder
	end
	local part = Instance.new("Part")
	part.Name = "BloodDrop"
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(scale, scale, scale)
	part.CFrame = CFrame.new(position)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	local materialName = fallback.ChunkMaterial or "Slate"
	part.Material = Enum.Material[materialName] or Enum.Material.Slate
	local rgb = self.Config.BloodColor or { 96, 12, 16 }
	part.Color = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	part.Parent = gore
	if direction ~= nil then
		-- The headless harness represents Vector3 as a table. Roblox's real
		-- Vector3 supports scalar multiplication; failed assignment is only a
		-- cosmetic fallback mismatch and must never abort Health:Slow.
		pcall(function()
			part.AssemblyLinearVelocity = direction * (scale * 12)
		end)
	end
	self.fallbackCount = self.fallbackCount + 1
	self.fallbackParts[self.fallbackCount] = part
	if self.fallbackCount > self.maxFallback then
		local old = self.fallbackParts[1]
		if old then
			old:Destroy()
		end
		for i = 2, self.fallbackCount do
			self.fallbackParts[i - 1] = self.fallbackParts[i]
		end
		self.fallbackParts[self.fallbackCount] = nil
		self.fallbackCount = self.fallbackCount - 1
	end
	local Debris = game:GetService("Debris")
	if Debris and Debris.AddItem then
		Debris:AddItem(part, lifetime)
	end
	return true
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
	if not self.UsingFallback and self.Engine ~= nil then
			local data = {
				Type = (self.Config.Engine or {}).Type or "Default",
				DefaultSize = { scale * 0.35, math.max(scale, 0.1) },
			}
			local ok = pcall(function()
			self.Engine:Emit(position, direction, data)
		end)
		if ok then
			return true
		end
		self:_logOnce("BloodEngine emit failed; switching to fallback")
		self.UsingFallback = true
	end
	local chunkSize = fallback.ChunkSize or { 0.05, math.huge }
	local dropScale = math.max(scale * 0.35, chunkSize[1] or 0.05)
	if chunkSize[2] ~= nil then
		dropScale = math.min(dropScale, chunkSize[2])
	end
	return self:_fallback(position, direction, dropScale, lifetime)
end

function BloodAdapter:destroy(): ()
	if self.Engine and type(self.Engine.Destroy) == "function" then
		pcall(function()
			self.Engine:Destroy()
		end)
	end
	self.Engine = nil
	for i = 1, self.fallbackCount do
		local part = self.fallbackParts[i]
		if part then
			part:Destroy()
		end
	end
	table.clear(self.fallbackParts)
	self.fallbackCount = 0
end

return BloodAdapter
