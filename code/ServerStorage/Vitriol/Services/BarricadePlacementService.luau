--!strict
-- Dormant manual-placement Tool. One preauthored Tool and eight preauthored
-- board slots. This service never grants/copies a Tool or creates Instances.
local Placement = {}
Placement.__index = Placement
local function get(parent: any, name: string, class: string): any
	local node = parent and parent:FindFirstChild(name)
	if not node or not node:IsA(class) then error("[Vitriol.Placement] missing authored " .. name .. " (" .. class .. ")", 0) end
	return node
end
function Placement:init(s: any): ()
	self.Workspace, self.Players, self.Health = s.Workspace, s.Players, s.Health
	self.Time, self.Session, self.Noise, self.Logger = s.Time, s.Session, s.Noise, s.Logger
	self.Map = get(self.Workspace, "Map", "Folder")
	self.Sockets = get(self.Map, "BarricadeSockets", "Folder")
	self.Placed = get(self.Map, "PlacedBarricades", "Folder")
	local root = get(s.ServerStorage, "Vitriol", "Folder")
	self.Pool = get(root, "BarricadePool", "Folder")
	self.Tools = get(root, "Tools", "Folder")
	self.Tool = get(self.Tools, "BarricadePlankTool", "Tool")
	self.Boards, self.Active, self.SocketOwners, self.Pressures, self.Connections = {}, {}, {}, {}, {}
	for i = 1, 8 do
		local name = string.format("Board_%02d", i)
		local board = self.Pool:FindFirstChild(name) or self.Placed:FindFirstChild(name)
		if not board or not board:IsA("Part") then error("[Vitriol.Placement] missing authored " .. name, 0) end
		self.Boards[i] = board
		get(board, "ReleaseBoard", "ProximityPrompt")
	end
	self.running = false
end
function Placement:_noise(position: any, intensity: number): ()
	if not self.Noise then return end
	local now = self.Time.elapsedTotal or 0
	self.Noise:emitAt("AIR", position.X, position.Y, position.Z, intensity, now)
	self.Noise:emitAt("VIBRATION", position.X, position.Y, position.Z, intensity, now)
end
function Placement:_eligible(player: any, requireTool: boolean): any
	if not self.running or self.Session.state == "Ended" or not player or not player.UserId
		or (self.Time.phase ~= "Day" and self.Time.phase ~= "Dawn") then return nil end
	local state = self.Health.states[player.UserId]
	if not state or state.dead or state.awaitingDawn or state.permadead then return nil end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root.Position or not root.CFrame then return nil end
	if requireTool and self.Tool.Parent ~= character then return nil end
	return root
end
function Placement:_forward(root: any): (number, number)
	local look = root.CFrame.LookVector
	local dx, dz = look.X, look.Z
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 0.01 then return 0, 0 end
	return dx / length, dz / length
end
function Placement:_socket(root: any, fx: number, fz: number): any
	local best, bestSq = nil, 12 * 12
	for _, marker in ipairs(self.Sockets:GetChildren()) do
		if marker:IsA("Part") and marker:GetAttribute("BarricadeSocket") == true
			and self.SocketOwners[marker.Name] == nil then
			local dx = marker.Position.X - root.Position.X
			local dz = marker.Position.Z - root.Position.Z
			local distSq = dx * dx + dz * dz
			if distSq < bestSq and dx * fx + dz * fz > math.sqrt(distSq) * 0.35 then
				best, bestSq = marker, distSq
			end
		end
	end
	return best
end
function Placement:_freeFrame(root: any, fx: number, fz: number): (any, any)
	local x, z = root.Position.X + fx * 7, root.Position.Z + fz * 7
	local hit = self.Workspace:Raycast(Vector3.new(x, root.Position.Y + 5, z), Vector3.new(0, -14, 0))
	if not hit or not hit.Instance or not hit.Position or not hit.Normal or hit.Normal.Y < 0.75
		or not hit.Instance:IsDescendantOf(self.Map) or hit.Instance:IsDescendantOf(self.Placed)
		or hit.Instance:IsDescendantOf(get(self.Map, "Interactions", "Folder")) then return nil, nil end
	for _, board in ipairs(self.Active) do
		local dx, dz = board.Position.X - x, board.Position.Z - z
		if dx * dx + dz * dz < 12 * 12 then return nil, nil end
	end
	local y = hit.Position.Y + 3.05
	local at = Vector3.new(x, y, z)
	return CFrame.lookAt(at, Vector3.new(x + fx, y, z + fz)), Vector3.new(8, 6, 0.8)
end
function Placement:place(player: any): boolean
	local root = self:_eligible(player, true)
	if not root then return false end
	local fx, fz = self:_forward(root)
	if fx == 0 and fz == 0 then return false end
	local socket = self:_socket(root, fx, fz)
	local frame, size
	if socket then frame, size = socket.CFrame, socket.Size
	else frame, size = self:_freeFrame(root, fx, fz) end
	if not frame then return false end
	local board
	for i = 1, #self.Boards do
		if self.Boards[i].Parent == self.Pool then board = self.Boards[i]; break end
	end
	if not board then return false end -- finite authored pool; never clone
	board.Size, board.CFrame = size, frame
	board.Parent = self.Placed
	board.Transparency, board.CanCollide, board.CanQuery = 0, true, true
	board.ReleaseBoard.Enabled = true
	board:SetAttribute("SocketName", socket and socket.Name or nil)
	if socket then self.SocketOwners[socket.Name] = board end
	self.Active[#self.Active + 1] = board
	self:_noise(board.Position, 0.7)
	return true
end
function Placement:_release(board: any, loud: boolean): boolean
	if board.Parent ~= self.Placed then return false end
	local socket = board:GetAttribute("SocketName")
	if socket then self.SocketOwners[socket] = nil end
	if loud then self:_noise(board.Position, 1.2) end
	for i = 1, #self.Active do
		if self.Active[i] == board then
			self.Active[i] = self.Active[#self.Active]
			self.Active[#self.Active] = nil
			break
		end
	end
	self.Pressures[board] = nil
	board.CanCollide, board.CanQuery, board.Transparency = false, false, 1
	board.ReleaseBoard.Enabled = false
	board:SetAttribute("SocketName", nil)
	board.Parent = self.Pool -- reuse the SAME preauthored part, never destroy it
	return true
end
-- Health wipes all carried Tools on death. Reclaim this unique authored Tool
-- BEFORE that sweep so it is still lost to the player, but not destroyed for the
-- entire server run. Also called on disconnect; never clone a replacement.
function Placement:reclaimTool(player: any): boolean
	if player == nil then return false end
	local parent = self.Tool.Parent
	if parent ~= nil and (parent == player.Character or parent == player:FindFirstChild("Backpack")
		or parent == player:FindFirstChild("StarterGear")) then
		self.Tool.Parent = self.Tools
		return true
	end
	return false
end
function Placement:release(player: any, board: any): boolean
	if not self.running or not player or not player.UserId or board.Parent ~= self.Placed then return false end
	local state = self.Health.states[player.UserId]
	if not state or state.dead or state.permadead then return false end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not root.Position then return false end
	local dx, dy, dz = root.Position.X - board.Position.X, root.Position.Y - board.Position.Y, root.Position.Z - board.Position.Z
	if dx * dx + dy * dy + dz * dz > 9 * 9 then return false end
	return self:_release(board, true)
end
function Placement:intercept(x: number, z: number, nx: number, nz: number): any
	for _, board in ipairs(self.Active) do
		local p, cf = board.Position, board.CFrame
		local axis = board.Size.X < board.Size.Z and cf.RightVector or cf.LookVector
		local ax, az = axis.X, axis.Z
		local before = (x - p.X) * ax + (z - p.Z) * az
		local after = (nx - p.X) * ax + (nz - p.Z) * az
		if before * after <= 0 then
			local tx, tz = -az, ax
			local mid = ((x + nx) * 0.5 - p.X) * tx + ((z + nz) * 0.5 - p.Z) * tz
			local width = board.Size.X < board.Size.Z and board.Size.Z or board.Size.X
			if math.abs(mid) <= width * 0.5 + 1 then return board end
		end
	end
	return nil
end
function Placement:press(board: any, dt: number): boolean
	if board.Parent ~= self.Placed then return false end
	local pressure = (self.Pressures[board] or 0) + math.min(math.max(dt, 0), 0.1)
	self.Pressures[board] = pressure
	if pressure >= 2.4 then
		self:_release(board, true)
		if self.Logger then self.Logger("info", "Braid breached a placed barricade") end
		return true
	end
	return false
end
function Placement:onPhaseChanged(phase: string): ()
	if phase ~= "Dawn" then return end
	while #self.Active > 0 do self:_release(self.Active[#self.Active], false) end
end
function Placement:start(): ()
	if self.running then return end
	self.running = true
	self.Connections[#self.Connections + 1] = self.Tool.Activated:Connect(function()
		local player = self.Players:GetPlayerFromCharacter(self.Tool.Parent)
		if player then self:place(player) end
	end)
	self.Connections[#self.Connections + 1] = self.Players.PlayerRemoving:Connect(function(player: any)
		self:reclaimTool(player)
	end)
	for i = 1, #self.Boards do
		local board = self.Boards[i]
		self.Connections[#self.Connections + 1] = board.ReleaseBoard.Triggered:Connect(function(player: any)
			self:release(player, board)
		end)
	end
end
function Placement:stop(): ()
	self.running = false
	for _, connection in ipairs(self.Connections) do connection:Disconnect() end
	self.Connections = {}
end
return Placement
