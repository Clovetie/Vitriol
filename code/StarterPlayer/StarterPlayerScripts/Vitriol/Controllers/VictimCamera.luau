--!strict
-- VictimCamera.luau
-- Location: StarterPlayer > StarterPlayerScripts > Vitriol > Controllers > VictimCamera (ModuleScript)
-- Purpose:  Local-only first-person presentation for a server-authoritative death
--           event. The camera remains at the victim's eye and looks toward the
--           replicated creature core; no camera state is changed for spectators.

local VictimCamera = {}
VictimCamera.__index = VictimCamera

function VictimCamera.new(options: any?): any
	local o = options or {}
	local self = setmetatable({}, VictimCamera)
	self.Players = o.Players or game:GetService("Players")
	self.RunService = o.RunService or game:GetService("RunService")
	self.Workspace = o.Workspace or game:GetService("Workspace")
	self.Player = o.Player or self.Players.LocalPlayer
	self.Camera = self.Workspace.CurrentCamera
	self.active = false
	self.elapsed = 0
	self.duration = 0
	self.character = nil
	self.oldType = nil
	self.oldSubject = nil
	self.oldFov = nil
	self.connection = nil
	return self
end

function VictimCamera:_eye(): any
	local current = self.Player.Character or self.character
	if current == nil then
		return nil
	end
	return current:FindFirstChild("Head") or current:FindFirstChild("HumanoidRootPart")
end

function VictimCamera:_core(creatureId: any): any
	if creatureId == nil then
		return nil
	end
	local root = self.Workspace:FindFirstChild("Vitriol")
	local creatures = root and root:FindFirstChild("Creatures")
	if creatures == nil then
		return nil
	end
	local model = creatures:FindFirstChild("Braid_" .. tostring(creatureId))
	return model and model:FindFirstChild("Core")
end

function VictimCamera:stop(): ()
	if not self.active then
		return
	end
	self.active = false
	self.RunService:UnbindFromRenderStep("VitriolVictimCamera")
	local camera = self.Camera or self.Workspace.CurrentCamera
	if camera then
		camera.CameraType = self.oldType or Enum.CameraType.Custom
		camera.CameraSubject = self.oldSubject
		if self.oldFov ~= nil then
			camera.FieldOfView = self.oldFov
		end
	end
	self.character = nil
	self.oldType, self.oldSubject, self.oldFov = nil, nil, nil
end

function VictimCamera:start(payload: any): ()
	if payload == nil or payload.VictimUserId ~= self.Player.UserId then
		return
	end
	self:stop()
	self.Camera = self.Workspace.CurrentCamera
	if self.Camera == nil then
		return
	end
	self.character = self.Player.Character
	if self:_eye() == nil then
		return
	end
	self.oldType = self.Camera.CameraType
	self.oldSubject = self.Camera.CameraSubject
	self.oldFov = self.Camera.FieldOfView
	self.Camera.CameraType = Enum.CameraType.Scriptable
	self.Camera.FieldOfView = 52
	self.elapsed = 0
	self.duration = math.max(tonumber(payload.Duration) or 6, 1)
	self.active = true

	local scene = self
	self.RunService:BindToRenderStep("VitriolVictimCamera", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		if not scene.active then
			return
		end
		scene.elapsed += math.max(dt, 0)
		local eye = scene:_eye()
		if eye == nil then
			scene:stop()
			return
		end
		local origin = eye.Position
		local target = scene:_core(payload.CreatureId)
		local lookAt = origin + eye.CFrame.LookVector * 12
		if target and target.Position then
			lookAt = target.Position
		end
		scene.Camera.CFrame = CFrame.lookAt(origin, lookAt, eye.CFrame.UpVector)
		if scene.elapsed >= scene.duration then
			scene:stop()
		end
	end)
end

function VictimCamera:bind(remote: any): ()
	if remote then
		self.connection = remote.OnClientEvent:Connect(function(payload: any)
			self:start(payload)
		end)
	end
	self.Player.CharacterAdded:Connect(function()
		if self.active then
			self:stop()
		end
	end)
end

function VictimCamera:destroy(): ()
	self:stop()
	if self.connection then
		self.connection:Disconnect()
		self.connection = nil
	end
end

return VictimCamera
