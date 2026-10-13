--!strict
-- T taps the user's authored CheckWatch animation once. The per-player Arms
-- template is engine-copied under ClientMain; never mint/clone runtime objects.
-- The accepted overlay survives for SharedFade, but its old flat viewport and
-- floating readout are hidden: time is drawn on the welded physical Screen.
local WatchController = {}
WatchController.__index = WatchController

local function child(parent: any, name: string, class: string): any?
	local object = parent and parent:FindFirstChild(name)
	if object and object:IsA(class) then return object end
	warn("[vitriol.watch] missing authored " .. name .. " (" .. class .. ")")
	return nil
end

function WatchController.new(s: any): any?
	local playerGui = s.Player:WaitForChild("PlayerGui", 15)
	if not playerGui or not playerGui:IsA("PlayerGui") then return nil end
	local gui = s.Overlay or playerGui:FindFirstChild("VitriolWatchOverlay")
	if not gui or not gui:IsA("ScreenGui") then return nil end
	if gui.Parent ~= playerGui then gui.Parent = playerGui end
	local fade = child(gui, "SharedFade", "Frame")
	local rig = child(s.Template, "Arms", "Model")
	local upper = child(rig, "RightUpperArm", "MeshPart")
	local wrist = child(upper, "WristWatch", "Model")
	local screen = child(wrist, "Screen", "Part")
	local surface = child(screen, "WatchSurface", "SurfaceGui")
	local face = child(surface, "WatchFaceText", "TextLabel")
	local animator = child(child(rig, "Humanoid", "Humanoid"), "Animator", "Animator")
	local animation = child(rig, "CheckWatch", "Animation")
	local self: any = setmetatable({}, WatchController)
	self.Player, self.Input, self.Workspace, self.RunService = s.Player, s.Input, s.Workspace, s.RunService
	self.Gui, self.Fade, self.Rig, self.Face, self.Surface = gui, fade, rig, face, surface
	self.Animator, self.Animation = animator, animation
	self.RigHome = rig and rig.Parent or nil
	self.View, self.Readout = gui:FindFirstChild("WristViewmodel"), gui:FindFirstChild("WatchReadout")
	self.DaySeconds = s.DayNight.Pacing.DaySeconds
	self.phase, self.progress, self.budgetRemaining = nil, 0, nil
	self.connections = {}
	self.hiddenArms = {} -- existing character/viewmodel Parts and prior local visibility
	self.active, self.track, self.startedAt = false, nil, 0
	return self -- even without Arms, keep the existing shared prep fade working
end

function WatchController:receive(phase: any, progress: any, budgetRemaining: any?): ()
	if type(phase) ~= "string" or type(progress) ~= "number" then return end
	self.phase, self.progress = phase, math.clamp(progress, 0, 1)
	self.budgetRemaining = type(budgetRemaining) == "number" and budgetRemaining or nil
	self:update()
end
function WatchController:update(): ()
	if not self.Face then return end
	local phase = self.phase
	if phase == "Day" or phase == "Dawn" then
		local remaining = phase == "Day" and self.DaySeconds * (1 - self.progress) or self.DaySeconds
		if self.budgetRemaining ~= nil then remaining = self.budgetRemaining end
		local seconds = math.max(0, math.ceil(remaining))
		self.Face.Text = string.format("DAY %02d:%02d", math.floor(seconds / 60), seconds % 60)
	else
		self.Face.Text = string.upper(tostring(phase or "--")) .. " --:--"
	end
end
function WatchController:appearance(character: any): ()
	if not self.Rig or character ~= self.Player.Character then return end
	-- The nested preauthored Shirt is part of the template, not created here.
	local shirt = self.Rig:FindFirstChildWhichIsA("Shirt")
	local actual = character:FindFirstChildWhichIsA("Shirt")
	if shirt then shirt.ShirtTemplate = actual and actual.ShirtTemplate or "" end
	local colors = character:FindFirstChildWhichIsA("BodyColors")
	for _, name in ipairs({"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand"}) do
		local part = self.Rig:FindFirstChild(name)
		local worn = character:FindFirstChild(name) or character:FindFirstChild(string.sub(name, 1, 4) == "Left" and "Left Arm" or "Right Arm")
		if part and part:IsA("BasePart") then
			if worn and worn:IsA("BasePart") then part.Color = worn.Color
			elseif colors then
				part.Color = string.sub(name, 1, 4) == "Left" and colors.LeftArmColor3 or colors.RightArmColor3
			end
		end
	end
end
-- Cache the already-existing limb Parts once per tap; LocalTransparencyModifier
-- hides only this player's real arms, never their replicated appearance for peers.
-- Also hide the left viewmodel arm so the physical right-hand watch stays clear.
function WatchController:maskArms(character: any): ()
	self.hiddenArms = {}
	local function mask(part: any)
		if part and part:IsA("BasePart") then
			self.hiddenArms[#self.hiddenArms+1] = {Part=part, Before=part.LocalTransparencyModifier}
			part.LocalTransparencyModifier = 1
		end
	end
	for _, side in ipairs({"Left", "Right"}) do
		for _, section in ipairs({"UpperArm", "LowerArm", "Hand"}) do
			mask(character:FindFirstChild(side .. section))
		end
		mask(character:FindFirstChild(side .. " Arm")) -- R6
	end
	for _, section in ipairs({"UpperArm", "LowerArm", "Hand"}) do
		mask(self.Rig:FindFirstChild("Left" .. section))
	end
end
function WatchController:hide(): ()
	self.active = false
	for _, saved in ipairs(self.hiddenArms) do
		if saved.Part.Parent then saved.Part.LocalTransparencyModifier = saved.Before end
	end
	self.hiddenArms = {}
	if self.Surface then self.Surface.Enabled = false end
	if self.track then self.track:Stop(0.18); self.track = nil end
	if self.Rig and self.RigHome then self.Rig.Parent = self.RigHome end
end
function WatchController:tap(): ()
	if self.active or not self.Player.Character or not self.Rig or not self.Face
		or not self.Surface or not self.Animator or not self.Animation then return end
	local camera = self.Workspace.CurrentCamera
	if not camera then return end
	self:appearance(self.Player.Character)
	self:update()
	-- Parenting the EXISTING per-player model to CurrentCamera makes it local
	-- viewmodel geometry. There is no new Camera, viewport, GUI or copied rig.
	self.Rig.Parent = camera
	self.Rig:PivotTo(camera.CFrame * CFrame.new(-0.5, -1.15, 0.35))
	local ok, track = pcall(function() return self.Animator:LoadAnimation(self.Animation) end)
	if not ok or not track then
		warn("[vitriol.watch] CheckWatch failed to load: " .. tostring(track))
		self.Rig.Parent = self.RigHome
		return
	end
	self.track, self.active, self.startedAt = track, true, os.clock()
	self:maskArms(self.Player.Character)
	track.Looped = false
	track.Priority = Enum.AnimationPriority.Action
	self.Surface.Enabled = true
	-- Ended (not Stopped) waits for the fade-out to finish before hiding.
	local ended: any = nil
	ended = track.Ended:Connect(function()
		ended:Disconnect()
		if self.track == track then self:hide() end
	end)
	track:Play(0.18)
end
function WatchController:start(): ()
	self.Gui.Enabled = true -- SharedFade must remain enabled while watch is down
	if self.View then self.View.Visible = false end
	if self.Readout then self.Readout.Visible = false end
	self:hide()
	self:update()
	self.connections[#self.connections+1] = self.Player.CharacterRemoving:Connect(function() self:hide() end)
	self.connections[#self.connections+1] = self.Player.CharacterAdded:Connect(function(character: any)
		self:hide()
		self:appearance(character)
	end)
	self.connections[#self.connections+1] = self.Player.CharacterAppearanceLoaded:Connect(function(character: any)
		self:appearance(character)
	end)
	if self.Player.Character then self:appearance(self.Player.Character) end
	self.connections[#self.connections+1] = self.Input.InputBegan:Connect(function(input: any, processed: boolean)
		if not processed and input.KeyCode == Enum.KeyCode.T then self:tap() end
	end)
	-- Only follow the camera while the watch is active; no descendant search
	-- or allocations in this per-frame callback.
	local frameSignal = self.RunService.RenderStepped
	self.connections[#self.connections+1] = frameSignal:Connect(function()
		if not self.active then return end
		local camera = self.Workspace.CurrentCamera
		if not camera or self.Rig.Parent ~= camera or not self.Player.Character then self:hide(); return end
		self.Rig:PivotTo(camera.CFrame * CFrame.new(-0.5, -1.15, 0.35))
		-- Roblox's default first-person transparency controller can rewrite the
		-- character's local arm visibility; keep the cached limbs hidden while up.
		for _, saved in ipairs(self.hiddenArms) do
			if saved.Part.Parent then saved.Part.LocalTransparencyModifier = 1 end
		end
		local track = self.track
		if not track then return end
		-- Fade the authored pose back into neutral before its last keyframe.
		if track.Length > 0 and track.IsPlaying and track.TimePosition >= math.max(0, track.Length - 0.35) then
			track:Stop(0.35)
		elseif track.Length == 0 and os.clock() - self.startedAt > 8 then
			warn("[vitriol.watch] CheckWatch animation did not load in time")
			self:hide()
		end
	end)
	print("[vitriol.watch] bound authored Arms/Screen; tap T for CheckWatch")
end
function WatchController:stop(): ()
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.connections = {}
	self:hide()
	self.Gui.Enabled = false
end
return WatchController
