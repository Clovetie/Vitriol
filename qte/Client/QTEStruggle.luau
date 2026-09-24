--!strict
-- QTEStruggle.luau
-- Location: ReplicatedStorage > QTE > Client > QTEStruggle  (ModuleScript)
--           (required by the place's own bootstrap, or by the LocalScript beside it)
-- Purpose:  The Roblox shell for the QTE stack: input in, pixels out, nothing else.
--           All of the rules (which QTE, how long, what a score means) live in the
--           pure modules - Config/QTEConfig -> Lib/QTECatalog -> Lib/QTEEngine ->
--           Lib/QTEDirector - and are covered by tools/vitriol/tests-qte.luau. This
--           file is deliberately the thin, untestable part:
--
--             * reads the device (UserInputService) into the engine's sample table,
--             * draws the engine's view (widgets) with a pooled instance set,
--             * owns the frame loop, the freeze and the watchdog,
--             * reports the outcome; it never decides it.
--
--           What v5 got wrong and this does not: no task.wait/watchdog chains (one
--           loop, driven by RunService), no TakeDamage/HealthChanged writes (the
--           result is a Signal; the game owns health), the mouse is read with
--           GuiService:GetGuiInset() applied (GetMouseLocation is in screen space,
--           not GUI space), and the pool is filtered by the device the player is
--           actually holding.
--
--           The interface is NOT built here. UI/QTEOverlay owns every frame and
--           label (and tools/qte-build-ui.js generates the importable copy of it
--           from that same spec); this file only writes text, colours, sizes and
--           visibility onto the pooled widgets under the stage.
--
-- Requires: Config/QTEConfig, Lib/QTECatalog, Lib/QTEDirector, Lib/QTEEngine,
--           Lib/Signal, UI/QTEOverlay  (all siblings - see README.md §3)
-- Used by:  the place's client bootstrap, e.g. Client/QTEStruggleClient

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

-- The package is self-contained: every module it needs is a sibling of this file,
-- so the whole QTE folder can be dropped anywhere that replicates (ReplicatedStorage,
-- ReplicatedStorage.SomeGame.Modules, ...) without editing a single path here.
local Root = script.Parent.Parent

local QTEConfig = require(Root.Config.QTEConfig)
local QTECatalog = require(Root.Lib.QTECatalog)
local QTEDirector = require(Root.Lib.QTEDirector)
local QTEEngine = require(Root.Lib.QTEEngine)
local Signal = require(Root.Lib.Signal)
local QTEOverlay = require(Root.UI.QTEOverlay)

local QTEStruggle = {}
QTEStruggle.__index = QTEStruggle

-- ── Small helpers ────────────────────────────────────────────────────────────
local function colour(rgb: any): Color3
	if rgb == nil then
		return Color3.fromRGB(QTEOverlay.Theme.Paper[1], QTEOverlay.Theme.Paper[2], QTEOverlay.Theme.Paper[3])
	end
	return Color3.fromRGB(rgb[1] or 255, rgb[2] or 255, rgb[3] or 255)
end

local function findFirst(parent: any, name: string): any
	-- One FindFirstChild per QTE start, never on a frame: a direct index on a
	-- missing child throws, and the hot-loop scan prices traversal on hot paths.
	local child = parent[name]
	if child == nil then
		return nil
	end
	return child
end

local function describeDevice(): any
	-- PreferredInput is the modern signal; the *Enabled flags are the fallback for
	-- clients that do not report it. v5 only asked "is TouchEnabled", which
	-- mis-detects a laptop with a touchscreen as a phone.
	local caps = {}
	local keyboard = UserInputService.KeyboardEnabled
	local pointer = UserInputService.MouseEnabled
	local touch = UserInputService.TouchEnabled
	local gamepad = UserInputService.GamepadEnabled
	local preferred = nil
	if UserInputService.PreferredInput ~= nil then
		preferred = UserInputService.PreferredInput
	end
	local isTouchPreferred = preferred ~= nil and preferred == Enum.PreferredInput.Touch
	local isGamepadPreferred = preferred ~= nil and preferred == Enum.PreferredInput.Gamepad

	if (gamepad and isGamepadPreferred) or (gamepad and not keyboard and not touch) then
		caps = QTEConfig.Devices.Gamepad
	elseif (touch and isTouchPreferred) or (touch and not keyboard and not pointer) then
		caps = QTEConfig.Devices.Touch
	else
		caps = QTEConfig.Devices.KeyboardMouse
	end
	return caps
end

-- ── Construction ─────────────────────────────────────────────────────────────
-- opts = {
--   seed = number,
--   preset = "Normal",
--   freeze = false,          -- freeze the character while a QTE runs
--   applyConsequences = false, -- v5 healed/damaged directly; the game's health owner should
--   gui = ScreenGui?,        -- your own ScreenGui; when omitted QTEOverlay is used
--   guiName = "QTEOverlay",  -- name to look for / create under PlayerGui
-- }
function QTEStruggle.new(opts: any?): any
	local o = opts or {}
	local self = setmetatable({}, QTEStruggle)
	self.players = o.Players or Players
	self.player = o.Player or self.players.LocalPlayer
	self.userInputService = o.UserInputService or UserInputService
	self.runService = o.RunService or RunService
	self.guiService = o.GuiService or GuiService
	self.workspace = o.Workspace or Workspace

	self.seed = o.seed or 1
	self.freeze = o.freeze == true
	self.applyConsequences = o.applyConsequences == true
	self.capabilities = o.capabilities or describeDevice()
	self.director = QTEDirector.new({
		seed = self.seed,
		preset = o.preset or QTEConfig.DefaultPreset,
		capabilities = self.capabilities,
	})
	self.engine = nil
	self.task = nil
	self.phase = "idle" -- idle | run | verdict
	self.verdictClock = 0
	self.chain = nil
	self.chainIndex = 0
	self.lastGrade = nil

	-- Signals: the game reacts to these; the shell does not decide what they mean.
	self.resultSignal = Signal.new()
	self.startedSignal = Signal.new()

	-- Input state, in engine token space.
	self.down = {}
	self.pointer = { x = 0.5, y = 0.5 }
	self.pointerPixels = 0
	self.clicks = 0
	self.clickPoint = nil
	self.beat = false
	self.look = { x = 0, y = 0, z = -1 }
	self.velocity = { x = 0, y = 0, z = 0 }

	self.tokenByKeyCode = {}
	self.tokenByUserInput = {}
	self:buildInputMaps()

	self.gui = o.gui
	self.guiName = o.guiName or "QTEOverlay"
	self.parts = nil
	self.stage = nil
	self.labels = {}
	self.pools = { text = {}, bar = {}, track = {}, target = {}, grid = {}, chips = {}, dot = {}, cell = {} }
	self.poolUse = {}
	self.chipLabels = {}
	self.connections = {}
	self.loopConnection = nil
	self.frozen = nil

	self:bindInput()
	self:bindCharacter()
	return self
end

function QTEStruggle:resolveGui(): any
	-- One ScreenGui, resolved once. If the game passed `gui` in, that is used as-is;
	-- otherwise UI/QTEOverlay ensures its own tree under PlayerGui - which means an
	-- imported-and-restyled QTEOverlay.rbxmx is picked up and completed, never
	-- replaced, so hand-authored looks survive.
	local playerGui = self.playerGui or self.player:FindFirstChildOfClass("PlayerGui")
	if playerGui == nil then
		return nil
	end
	self.playerGui = playerGui
	local gui = self.gui or QTEOverlay.ensure(playerGui, { name = self.guiName })
	self.gui = gui
	return gui
end

-- ── Input maps ───────────────────────────────────────────────────────────────
-- InputMap speaks TOKENS; the platform speaks KeyCode names and UserInputTypes.
-- One inversion per device, done once at construction.
function QTEStruggle:buildInputMaps(): ()
	local keyboard = QTEConfig.InputMap.Keyboard
	for token, keyName in pairs(keyboard) do
		local keyCode = Enum.KeyCode[keyName]
		if keyCode ~= nil then
			self.tokenByKeyCode[keyCode] = token
		end
	end
	local gamepad = QTEConfig.InputMap.Gamepad
	for token, keyName in pairs(gamepad) do
		local keyCode = Enum.KeyCode[keyName]
		if keyCode ~= nil and self.tokenByKeyCode[keyCode] == nil then
			self.tokenByKeyCode[keyCode] = token
		end
	end
	-- Mouse and touch answer the Click capability; the engine only needs a token
	-- for them, and both map to the same one so a definition works on either.
	self.tokenByUserInput[Enum.UserInputType.MouseButton1] = "Click"
	self.tokenByUserInput[Enum.UserInputType.Touch] = "Click"
	self.tokenByUserInput[Enum.UserInputType.Gamepad1] = nil
end

function QTEStruggle:tokenForInput(input: any): string?
	local byUserInput = self.tokenByUserInput[input.UserInputType]
	if byUserInput ~= nil then
		return byUserInput
	end
	if input.KeyCode ~= nil and input.KeyCode ~= Enum.KeyCode.Unknown then
		return self.tokenByKeyCode[input.KeyCode]
	end
	return nil
end

function QTEStruggle:bindInput(): ()
	local uis = self.userInputService
	self.connections[#self.connections + 1] = uis.InputBegan:Connect(function(input: any, processed: boolean)
		if processed then
			return
		end
		local token = self:tokenForInput(input)
		if token == nil then
			return
		end
		self.down[token] = true
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			self.clicks += 1
			self.clickPoint = { x = self.pointer.x, y = self.pointer.y }
		end
	end)
	self.connections[#self.connections + 1] = uis.InputEnded:Connect(function(input: any)
		local token = self:tokenForInput(input)
		if token ~= nil then
			self.down[token] = nil
		end
	end)
	-- Motion only arrives through InputChanged: mouse look for the
	-- pointer, touch drag for the same thing, and the camera for Look QTEs.
	self.connections[#self.connections + 1] = uis.InputChanged:Connect(function(input: any)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			self:readPointer()
		end
	end)
	self.connections[#self.connections + 1] = uis.LastInputTypeChanged:Connect(function()
		local caps = describeDevice()
		local changed = false
		for cap in pairs(caps) do
			if self.capabilities[cap] ~= true then
				changed = true
			end
		end
		if changed then
			-- A player who picked up a gamepad must not keep getting keyboard
			-- prompts; re-filter the pool for the next QTE.
			self.capabilities = caps
			self.director:setCapabilities(caps)
		end
	end)
end

function QTEStruggle:bindCharacter(): ()
	local character = self.player.Character
	if character ~= nil then
		self:bindHumanoid(character)
	end
	self.connections[#self.connections + 1] = self.player.CharacterAdded:Connect(function(newCharacter: any)
		if self.phase ~= "idle" then
			self:cancel("respawn")
		end
		self:bindHumanoid(newCharacter)
	end)
end

function QTEStruggle:bindHumanoid(character: any): ()
	self.humanoid = findFirst(character, "Humanoid")
	self.root = findFirst(character, "HumanoidRootPart")
end

-- ── Pointer / camera sampling ────────────────────────────────────────────────
function QTEStruggle:readPointer(): ()
	local mouse = self.userInputService:GetMouseLocation()
	local inset = self.guiService:GetGuiInset()
	local camera = self.workspace.CurrentCamera
	local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
	local x = mouse.X - inset.X
	local y = mouse.Y - inset.Y
	local nx = x / math.max(1, viewport.X)
	local ny = y / math.max(1, viewport.Y)
	self.pointerPixels = math.abs(nx - self.pointer.x) * viewport.X + math.abs(ny - self.pointer.y) * viewport.Y
	self.pointer = { x = math.clamp(nx, 0, 1), y = math.clamp(ny, 0, 1) }
end

function QTEStruggle:sample(dt: number): any
	self:readPointer()
	local camera = self.workspace.CurrentCamera
	if camera ~= nil then
		local look = camera.CFrame.LookVector
		self.look = { x = look.X, y = look.Y, z = look.Z }
	end
	local root = self.root
	if root ~= nil then
		local v = root.AssemblyLinearVelocity
		self.velocity = { x = v.X, y = v.Y, z = v.Z }
	end
	local keys = {}
	for token, isDown in pairs(self.down) do
		if isDown then
			keys[token] = true
		end
	end
	local sample = {
		dt = dt,
		keys = keys,
		pointer = { x = self.pointer.x, y = self.pointer.y },
		clicks = self.clicks,
		clickPoint = self.clickPoint,
		pointerTravel = self.pointerPixels / math.max(1, 1280),
		look = self.look,
		velocity = self.velocity,
		beat = self.beat,
	}
	self.clicks = 0
	self.clickPoint = nil
	self.beat = false
	return sample
end

-- markBeat() -> ()
-- For beat-driven QTEs (FootstepSync, Rhythm with cueSource = "beat"): the game
-- calls this on the animation marker or server event that is the beat.
function QTEStruggle:markBeat(): ()
	self.beat = true
end

-- ── GUI ──────────────────────────────────────────────────────────────────────
function QTEStruggle:ensureStage(): any
	local existing = self.stage
	if existing ~= nil and existing.Parent ~= nil then
		return existing
	end
	local gui = self.gui or self:resolveGui()
	if gui == nil then
		return nil
	end
	-- parts() is one traversal at the start of a run; the frame loop only writes to
	-- the instances it returns (never searches for them).
	local parts = self.parts or QTEOverlay.parts(gui)
	if parts == nil or parts.root == nil then
		-- Only reachable when a game passes its own `gui` that has no QTE subtree.
		-- That is the game's to fix, so say it once instead of every frame.
		if not self.warnedBadGui then
			self.warnedBadGui = true
			warn(QTEConfig.Diagnostics.Prefix .. ": the ScreenGui handed to QTEStruggle has no QTE subtree, so nothing can be drawn")
		end
		return nil
	end
	self.parts = parts
	self.stage = parts.root
	self.surface = parts.surface or parts.root
	self.labels = {
		title = parts.title,
		hint = parts.hint,
		fill = parts.fill,
		verdict = parts.verdict,
		accent = parts.accent,
		ui = parts.root,
	}
	return self.stage
end

function QTEStruggle:acquire(kind: string): any
	local pool = self.pools[kind]
	local used = (self.poolUse[kind] or 0) + 1
	self.poolUse[kind] = used
	local instance = pool[used]
	if instance == nil then
		instance = self:makeWidget(kind)
		pool[used] = instance
	end
	instance.Visible = true
	return instance
end

function QTEStruggle:hideUnused(kind: string): ()
	local pool = self.pools[kind]
	local used = self.poolUse[kind] or 0
	for i = used + 1, #pool do
		pool[i].Visible = false
	end
end

function QTEStruggle:makeWidget(kind: string): any
	local surface = self.surface or self.stage
	if kind == "text" then
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextStrokeTransparency = 0.5
		label.Visible = false
		label.Parent = surface
		return label
	elseif kind == "bar" then
		local track = Instance.new("Frame")
		track.BackgroundColor3 = colour(QTEOverlay.Theme.Ink)
		track.BackgroundTransparency = 0.4
		track.BorderSizePixel = 0
		track.Visible = false
		track.Parent = surface
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.BorderSizePixel = 0
		fill.Parent = track
		return track
	elseif kind == "track" then
		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = colour(QTEOverlay.Theme.Ink)
		frame.BackgroundTransparency = 0.4
		frame.BorderSizePixel = 0
		frame.Visible = false
		frame.Parent = surface
		local zone = Instance.new("Frame")
		zone.Name = "Zone"
		zone.BorderSizePixel = 0
		zone.BackgroundColor3 = colour(QTEOverlay.Theme.Good)
		zone.BackgroundTransparency = 0.55
		zone.Parent = frame
		local marker = Instance.new("Frame")
		marker.Name = "Marker"
		marker.BorderSizePixel = 0
		marker.BackgroundColor3 = colour(QTEOverlay.Theme.Paper)
		marker.Parent = frame
		return frame
	elseif kind == "chips" then
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Visible = false
		row.Parent = surface
		return row
	elseif kind == "target" then
		local dot = Instance.new("Frame")
		dot.BorderSizePixel = 0
		dot.BackgroundTransparency = 0.25
		dot.Visible = false
		dot.Parent = surface
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = dot
		return dot
	elseif kind == "path" then
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.Visible = false
		frame.Parent = surface
		return frame
	elseif kind == "grid" then
		local frame = Instance.new("Frame")
		frame.BackgroundTransparency = 1
		frame.Visible = false
		frame.Parent = surface
		return frame
	end
	-- no visual: an invisible frame keeps the pool logic uniform
	local spare = Instance.new("Frame")
	spare.BackgroundTransparency = 1
	spare.Visible = false
	spare.Parent = surface
	return spare
end

-- ── Drawing ──────────────────────────────────────────────────────────────────
function QTEStruggle:draw(view: any): ()
	local stage = self:ensureStage()
	if stage == nil then
		return
	end
	local labels = self.labels
	if labels.title ~= nil then
		labels.title.Text = view.prompt or ""
		labels.title.TextColor3 = colour(QTEOverlay.Theme.Paper)
	end
	if labels.accent ~= nil then
		-- The one accent in the composition, and it carries the QTE's own colour.
		labels.accent.BackgroundColor3 = colour(view.accent)
	end
	if labels.hint ~= nil then
		labels.hint.Text = view.sub or ""
		labels.hint.Visible = view.sub ~= nil
	end
	if labels.fill ~= nil then
		local fraction = 0
		if view.timeLimit and view.timeLimit > 0 then
			fraction = math.clamp(view.remaining / view.timeLimit, 0, 1)
		end
		labels.fill.Size = UDim2.fromScale(fraction, 1)
		labels.fill.BackgroundColor3 = colour(view.accent)
	end

	for kind in pairs(self.poolUse) do
		self.poolUse[kind] = 0
	end
	local surface = self.surface or stage
	local size = surface.AbsoluteSize
	local width = math.max(1, size.X)
	local height = math.max(1, size.Y)
	local widgets = view.widgets or {}
	for i = 1, #widgets do
		local w = widgets[i]
		if w.kind == "text" then
			local label = self:acquire("text")
			label.Size = UDim2.fromScale(0.9, 0.34)
			label.Position = UDim2.fromScale(0.5, 0.5)
			label.AnchorPoint = Vector2.new(0.5, 0.5)
			label.Text = tostring(w.value or "")
			label.TextColor3 = colour(w.colour or view.accent)
			label.TextSize = math.clamp(18 * (w.scale or 1), 12, 48)
		elseif w.kind == "bar" then
			local track = self:acquire("bar")
			track.Size = UDim2.fromScale(0.8, 0.06)
			track.Position = UDim2.fromScale(0.1, 0.5)
			local fill = findFirst(track, "Fill")
			fill.Size = UDim2.fromScale(math.clamp(w.value or 0, 0, 1), 1)
			fill.BackgroundColor3 = colour(w.colour or view.accent)
		elseif w.kind == "track" then
			local frame = self:acquire("track")
			local vertical = w.orientation == "v"
			if vertical then
				frame.Size = UDim2.fromScale(0.08, 0.9)
				frame.Position = UDim2.fromScale(0.46, 0.05)
			else
				frame.Size = UDim2.fromScale(0.9, 0.07)
				frame.Position = UDim2.fromScale(0.05, 0.6)
			end
			local zone = findFirst(frame, "Zone")
			local marker = findFirst(frame, "Marker")
			local zoneFrom = 0
			local zoneTo = 0
			if w.zone ~= nil then
				zoneFrom = w.zone.from or 0
				zoneTo = w.zone.to or 0
			end
			if vertical then
				zone.Size = UDim2.fromScale(1, math.max(0, zoneTo - zoneFrom))
				zone.Position = UDim2.fromScale(0, 1 - zoneTo)
				marker.Size = UDim2.fromScale(1, 0.02)
				marker.Position = UDim2.fromScale(0, 1 - math.clamp(w.value or 0, 0, 1))
			else
				zone.Size = UDim2.fromScale(math.max(0, zoneTo - zoneFrom), 1)
				zone.Position = UDim2.fromScale(zoneFrom, 0)
				marker.Size = UDim2.fromScale(0.012, 1)
				marker.Position = UDim2.fromScale(math.clamp(w.value or 0, 0, 1), 0)
			end
			zone.BackgroundColor3 = colour(w.zoneColour or { 120, 255, 150 })
			marker.BackgroundColor3 = colour(w.colour or view.accent)
		elseif w.kind == "target" then
			local dot = self:acquire("target")
			local radius = (w.radius or 0.04) * width
			dot.Size = UDim2.fromOffset(radius * 2, radius * 2)
			dot.Position = UDim2.fromOffset((w.x or 0.5) * width - radius, (w.y or 0.5) * height - radius)
			dot.BackgroundColor3 = colour(w.colour or view.accent)
			dot.BackgroundTransparency = 1 - math.clamp(w.alpha or 0.9, 0, 1)
		elseif w.kind == "path" then
			local frame = self:acquire("path")
			frame.Size = UDim2.fromScale(1, 1)
			frame.Position = UDim2.fromScale(0, 0)
			local points = w.points or {}
			for j = 1, #points do
				local dot = self:acquire("dot")
				local done = j < (w.index or 1)
				local radius = 8
				dot.Size = UDim2.fromOffset(radius * 2, radius * 2)
				dot.Position = UDim2.fromOffset(points[j].x * width - radius, points[j].y * height - radius)
				dot.BackgroundColor3 = done and colour({ 120, 255, 150 }) or colour(w.colour or view.accent)
				dot.Parent = frame
			end
		elseif w.kind == "chips" then
			local row = self:acquire("chips")
			local items = w.items or {}
			local count = math.max(1, #items)
			row.Size = UDim2.fromScale(0.9, 0.3)
			row.Position = UDim2.fromScale(0.05, 0.62)
			local chipSize = 1 / count
			for j = 1, count do
				local chip = self:acquire("cell")
				chip.Parent = row
				chip.Size = UDim2.fromScale(chipSize * 0.86, 0.7)
				chip.Position = UDim2.fromScale((j - 1) * chipSize, 0.15)
				chip.BackgroundTransparency = j == (w.index or 0) and 0.35 or 0.75
				chip.BackgroundColor3 = colour(w.colour or view.accent)
				-- The label is cached: looking it up per cell per frame is a
				-- traversal on the hot path, and the scan prices traversals.
				local label = self.chipLabels[chip]
				if label == nil then
					label = Instance.new("TextLabel")
					label.Size = UDim2.fromScale(1, 1)
					label.BackgroundTransparency = 1
					label.TextScaled = true
					label.Font = Enum.Font.GothamBold
					label.TextColor3 = colour(QTEOverlay.Theme.Paper)
					label.Parent = chip
					self.chipLabels[chip] = label
				end
				label.Text = tostring(items[j])
			end
		elseif w.kind == "grid" then
			local grid = self:acquire("grid")
			grid.Size = UDim2.fromScale(1, 1)
			grid.Position = UDim2.fromScale(0, 0)
			local cols = w.cols or 3
			local rows = w.rows or 3
			local cells = w.cells or {}
			for index = 1, cols * rows do
				local cell = self:acquire("cell")
				cell.Parent = grid
				local col = (index - 1) % cols
				local row = math.floor((index - 1) / cols)
				cell.Size = UDim2.fromScale(1 / cols * 0.9, 1 / rows * 0.9)
				cell.Position = UDim2.fromScale(col / cols + 0.02, row / rows + 0.02)
				local state = cells[index] or "idle"
				local shade = 0.85
				if state == "lit" or state == "hit" then
					shade = 0.1
				elseif state == "wrong" or state == "miss" then
					shade = 0.5
				end
				cell.BackgroundTransparency = shade
				cell.BackgroundColor3 = colour(w.colour or view.accent)
			end
		end
	end
	for kind in pairs(self.pools) do
		self:hideUnused(kind)
	end
end

function QTEStruggle:showVerdict(text: string, tint: any): ()
	local stage = self.stage
	if stage == nil then
		return
	end
	local verdict = self.labels.verdict
	if verdict == nil then
		return
	end
	verdict.Text = text
	verdict.TextColor3 = colour(tint)
	verdict.TextTransparency = 0
end

-- ── Run control ──────────────────────────────────────────────────────────────
function QTEStruggle:isActive(): boolean
	return self.phase == "run"
end

function QTEStruggle:start(defId: string?, startOpts: any?): any
	local o = startOpts or {}
	if self.phase == "run" then
		return nil
	end
	local task = nil
	if defId ~= nil then
		task = self.director:beginNamed(defId, o.healthFraction)
	end
	if task == nil then
		task = self.director:begin(o.healthFraction)
	end
	if task == nil then
		return nil
	end
	self.task = task
	self.engine = QTEEngine.new(task, {})
	self.phase = "run"
	self.freezeOn = o.freeze or self.freeze
	if self.freezeOn then
		self:setFrozen(true)
	end
	local stage = self:ensureStage()
	if stage ~= nil then
		QTEOverlay.setVisible(self.gui, true)
	end
	if self.labels.verdict ~= nil then
		self.labels.verdict.TextTransparency = 1
	end
	self:ensureLoop()
	self.startedSignal:fire(task)
	return task
end

function QTEStruggle:ensureLoop(): ()
	if self.loopConnection ~= nil then
		return
	end
	self.loopConnection = self.runService.Heartbeat:Connect(function(dt: number)
		self:step(dt)
	end)
end

function QTEStruggle:step(dt: number): ()
	if self.phase == "run" then
		local engine = self.engine
		if engine == nil then
			self.phase = "idle"
			return
		end
		local sample = self:sample(math.min(dt, 0.1))
		local view = engine:tick(sample)
		self:draw(view)
		if engine:isDone() then
			self:finish()
		end
		return
	end
	if self.phase == "verdict" then
		self.verdictClock -= dt
		if self.verdictClock <= 0 then
			self:hideStage()
		end
	end
end

function QTEStruggle:finish(reason: string?): ()
	local engine = self.engine
	local task = self.task
	if engine == nil or task == nil then
		self:cancel(reason or "cancelled")
		return
	end
	local result = engine:result()
	result.id = task.id
	result.mode = task.mode
	local outcome = self.director:record(result)
	local grade = outcome.grade
	self.lastGrade = grade

	-- The verdict word is chosen from the resolution reason first, so a false start
	-- reads as a false start rather than as a generic miss. QTEConfig.Copy owns the
	-- wording; this only picks the list.
	local copy
	if grade.name == "fail" then
		if result.reason == "false_start" then
			copy = QTEConfig.Copy.FalseStart
		elseif result.reason == "wrong_input" then
			copy = QTEConfig.Copy.WrongKey
		elseif result.reason == "timeout" then
			copy = QTEConfig.Copy.Late
		else
			copy = QTEConfig.Copy.Miss
		end
		self:showVerdict(copy[(self.director.runs % #copy) + 1], QTEOverlay.Theme.Danger)
	else
		if grade.name == "sloppy" then
			copy = QTEConfig.Copy.Sloppy
		elseif grade.name == "clean" then
			copy = QTEConfig.Copy.Clean
		else
			copy = QTEConfig.Copy.Perfect
		end
		self:showVerdict(copy[(self.director.runs % #copy) + 1], QTEOverlay.Theme.Good)
	end

	local payload = {
		id = task.id,
		mode = task.mode,
		label = task.label,
		state = result.state,
		reason = result.reason,
		score = grade.score,
		grade = grade.name,
		escapeWeight = grade.escapeWeight,
		elapsed = result.elapsed,
		misses = result.misses,
		streak = outcome.streak,
		timeLimit = task.timeLimit,
	}
	self.engine = nil
	self.task = nil
	self.phase = "verdict"
	self.verdictClock = QTEConfig.Timing.FailureHoldSeconds
	if self.freezeOn then
		self:setFrozen(false)
	end
	self.resultSignal:fire(payload)

	if self.applyConsequences and (grade.damage > 0 or grade.heal > 0) then
		-- Off by default: a QTE result is reported, not applied. A game with a
		-- single owner of health (as any sane one has) wants resultSignal and
		-- nothing else; a game that wants v5's direct writes opts in here.
		local humanoid = self.humanoid
		if humanoid ~= nil then
			if grade.damage > 0 then
				humanoid:TakeDamage(grade.damage)
			elseif grade.heal > 0 then
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + grade.heal)
			end
		end
	end
end

function QTEStruggle:cancel(reason: string?): ()
	if self.engine ~= nil then
		local task = self.task
		local result = self.engine:result()
		self.resultSignal:fire({
			id = task and task.id or "?",
			state = "cancelled",
			reason = reason or "cancelled",
			score = 0,
			grade = "fail",
			escapeWeight = 0,
			elapsed = result.elapsed,
			misses = result.misses,
			cancelled = true,
		})
	end
	self.engine = nil
	self.task = nil
	if self.freezeOn then
		self:setFrozen(false)
	end
	self.phase = "idle"
	self:stopLoop()
	self:hideStage()
end

function QTEStruggle:hideStage(): ()
	self.phase = "idle"
	if self.stage ~= nil then
		QTEOverlay.setVisible(self.gui, false)
	end
	if self.labels.verdict ~= nil then
		self.labels.verdict.TextTransparency = 1
	end
	self:stopLoop()
end

function QTEStruggle:stopLoop(): ()
	if self.loopConnection ~= nil then
		self.loopConnection:Disconnect()
		self.loopConnection = nil
	end
end

function QTEStruggle:setFrozen(frozen: boolean): ()
	local humanoid = self.humanoid
	if humanoid == nil then
		return
	end
	if frozen then
		self.frozen = { walk = humanoid.WalkSpeed, jump = humanoid.JumpPower }
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	elseif self.frozen ~= nil then
		humanoid.WalkSpeed = self.frozen.walk
		humanoid.JumpPower = self.frozen.jump
		self.frozen = nil
	end
end

-- ── Chains ───────────────────────────────────────────────────────────────────
function QTEStruggle:startChain(ids: any): ()
	self.chain = ids
	self.chainIndex = 1
	self:start(self.chain[1])
end

function QTEStruggle:advanceChain(): ()
	if self.chain == nil then
		return
	end
	self.chainIndex += 1
	local nextId = self.chain[self.chainIndex]
	if nextId == nil then
		self.chain = nil
		return
	end
	self:start(nextId)
end

-- ── Server hook ──────────────────────────────────────────────────────────────
-- bind(creatureEvent) -> ()
-- RE_CreatureEvent already reaches the client (ClientMain binds VictimCamera to it).
-- A payload of { qte = "start", id = "Spam", healthFraction = 0.3 } begins a
-- struggle QTE; { qte = "cancel" } aborts one. The SERVER starts struggles because
-- it owns the kill choreography; the client only reports back, and the server
-- treats the report as a request, never as truth (README.md §10).
function QTEStruggle:bind(creatureEvent: any): ()
	if creatureEvent == nil then
		return
	end
	self.connections[#self.connections + 1] = creatureEvent.OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		local kind = payload.qte or payload.QTE
		if kind == "start" then
			self:start(payload.id, { healthFraction = payload.healthFraction, freeze = payload.freeze })
		elseif kind == "beat" then
			self:markBeat()
		elseif kind == "cancel" then
			self:cancel(payload.reason)
		end
	end)
end

-- ── v5 public API, mapped one-to-one ─────────────────────────────────────────
-- The old manager's callers should not have to be rewritten: every documented
-- entry point still exists, on the object, with the same meaning.
function QTEStruggle:StartRandomQTE(healthFraction: number?): any
	return self:start(nil, { healthFraction = healthFraction })
end

function QTEStruggle:StartQTE(id: string, healthFraction: number?): any
	return self:start(id, { healthFraction = healthFraction })
end

function QTEStruggle:StartChain(ids: any): ()
	self:startChain(ids)
end

function QTEStruggle:RegisterCustomQTE(def: any): boolean
	return self.director:registerCustom(def)
end

function QTEStruggle:SetDifficulty(preset: string): boolean
	return self.director:setPreset(preset)
end

function QTEStruggle:SetConfig(partial: any): ()
	-- v5 accepted a table of mixed knobs. Time-multiplier style tables are mapped to
	-- a preset; anything else is reported rather than silently ignored.
	if type(partial) ~= "table" then
		return
	end
	if partial.preset ~= nil then
		self.director:setPreset(partial.preset)
	end
	if partial.freeze ~= nil then
		self.freeze = partial.freeze == true
	end
	if partial.applyConsequences ~= nil then
		self.applyConsequences = partial.applyConsequences == true
	end
end

function QTEStruggle:GetStats(): any
	local stats = self.director:stats()
	stats.active = self:isActive()
	stats.capabilities = self.capabilities
	stats.lastGrade = self.lastGrade
	return stats
end

function QTEStruggle:ResetStats(): ()
	self.director:reset()
end

function QTEStruggle:GetQTEList(): any
	local list = {}
	for i = 1, #QTECatalog.list do
		local def = QTECatalog.list[i]
		list[i] = { id = def.id, label = def.label, mode = def.mode, category = def.category, weight = def.weight }
	end
	return list
end

function QTEStruggle:ResetAppearances(): ()
	self.director:resetAppearances()
end

function QTEStruggle:destroy(): ()
	self:cancel("destroyed")
	for i = 1, #self.connections do
		self.connections[i]:Disconnect()
	end
	self.connections = {}
	self.resultSignal:disconnectAll()
	self.startedSignal:disconnectAll()
end

return QTEStruggle
