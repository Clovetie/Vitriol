--!strict
-- Four ORIGINAL, anchored furniture Parts from two user-owned houses. Each is
-- moved to a preauthored doorway pose via the shared daytime prep transaction.
-- Never scale, clone, weld, destroy or create game/UI Instances in Play.
local HouseCoverService = {}
HouseCoverService.__index = HouseCoverService
local function get(parent: any, name: string, class: string): any
	local node = parent and parent:FindFirstChild(name)
	if not node or not node:IsA(class) then
		error("[Vitriol.HouseCover] missing authored " .. name .. " (" .. class .. ")", 0)
	end
	return node
end
local KINDS = { "Table", "Closet" }
local HOUSES = { "House_01", "House_02" }
function HouseCoverService:init(s: any): ()
	self.Players, self.Health, self.Time, self.Session = s.Players, s.Health, s.Time, s.Session
	self.Noise, self.Logger = s.Noise, s.Logger
	local map = get(s.Workspace, "Map", "Folder")
	local interiors = get(map, "Interiors", "Folder")
	local targets = get(get(map, "Interactions", "Folder"), "HouseCoverTargets", "Folder")
	local structures = get(map, "Structures", "Folder")
	self.Pieces, self.ByAction, self.running, self.connections = {}, {}, false, {}
	self.activeCount, self.Pressing = 0, nil
	for _, name in ipairs(HOUSES) do
		local house = get(structures, name, "Model")
		local floor = get(house, "Floor", "Part")
		local pier = get(house, "EastPier_-13", "Part")
		local doorX, doorZ = pier.Position.X, floor.Position.Z
		for _, kind in ipairs(KINDS) do
			local label = name .. "_" .. kind
			local part = get(interiors, label, "Part")
			local marker = get(targets, label .. "Target", "Part")
			local action = "Cover" .. name:gsub("_", "") .. kind
			local piece = {
				Part = part, Home = part.CFrame, Target = marker.CFrame,
				Prompt = get(part, "MoveToEntrance", "ProximityPrompt"),
				Helper = get(part, "AssistHouseCover", "ProximityPrompt"),
				House = name, Kind = kind, Action = action,
				DoorX = doorX, DoorZ = doorZ, Width = part.Size.X,
				Placed = false, Broken = false, Pressure = 0,
			}
			-- Fail closed if invisible markers no longer describe the authored
			-- east doorway. The real furniture remains unchanged at boot.
			local p = marker.Position
			if math.abs(p.X - (doorX - 2.5)) > 0.1 or math.abs(p.Z - (doorZ + (kind == "Table" and -3.5 or 5))) > 0.1
				or not part.Anchored or not part.CanCollide then
				error("[Vitriol.HouseCover] changed doorway/target/furniture: " .. label, 0)
			end
			self.Pieces[#self.Pieces + 1] = piece
			self.ByAction[action] = piece
		end
	end
end
function HouseCoverService:_day(): boolean
	return self.Time.phase == "Day" or self.Time.phase == "Dawn"
end
function HouseCoverService:_publish(piece: any): ()
	local part = piece.Part
	part:SetAttribute("HouseCoverPlaced", piece.Placed)
	part:SetAttribute("HouseCoverBroken", piece.Broken)
	piece.Prompt.Enabled = self.running and self.Prep ~= nil and not piece.Placed
		and self:_day() and self.Session.state ~= "Ended" and (self.Time:dayRemaining() or 0) > 0
	-- Helpers are visible only inside the existing coordinator's three-real-
	-- second vote. Do not overwrite Helper.Enabled here.
end
function HouseCoverService:_valid(player: any, piece: any): boolean
	if not self.running or not self:_day() or self.Session.state == "Ended" or not player or not player.UserId
		or (self.Time:dayRemaining() or 0) <= 0 then return false end
	local connected = false
	for _, present in ipairs(self.Players:GetPlayers()) do
		if present == player then connected = true; break end
	end
	if not connected then return false end
	local state = self.Health.states[player.UserId]
	if not state or state.dead or state.awaitingDawn or state.permadead then return false end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not root.Position then return false end
	local a, b = root.Position, piece.Part.Position
	local dx,dy,dz = a.X-b.X,a.Y-b.Y,a.Z-b.Z
	return dx*dx+dy*dy+dz*dz <= 100
end
function HouseCoverService:_landingFree(piece: any): boolean
	-- Moving an anchored closet onto another survivor can trap them. Cancel
	-- BEFORE the prep clock is charged; ask occupants to clear the doorway.
	local p = piece.Target.Position
	for _, player in ipairs(self.Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root and root.Position then
			local pos = root.Position
			if math.abs(pos.X-p.X) < piece.Part.Size.Z*0.5+1.25
				and math.abs(pos.Z-p.Z) < piece.Width*0.5+1.25
				and math.abs(pos.Y-p.Y) < 6 then return false end
		end
	end
	return true
end
function HouseCoverService:ready(action: string, player: any): boolean
	local piece = self.ByAction[action]
	return piece ~= nil and not piece.Placed and self:_valid(player, piece) and self:_landingFree(piece)
end
function HouseCoverService:move(action: string, player: any): boolean
	if not self:ready(action, player) then return false end
	local piece = self.ByAction[action]
	piece.Part.CFrame = piece.Target
	piece.Placed, piece.Broken, piece.Pressure = true, false, 0
	self.activeCount += 1
	self:_publish(piece)
	if self.Noise then
		local p = piece.Part.Position
		self.Noise:emitAt("AIR",p.X,p.Y,p.Z,0.75,self.Time.elapsedTotal or 0)
	end
	if self.Logger then self.Logger("info", piece.House .. " " .. piece.Kind .. " moved to doorway until dislodged") end
	return true
end
-- Pure horizontal footprint check. Neither Part is enlarged to seal the
-- 16-stud door: table covers 9 studs at knee height; closet covers 6. The
-- gap/space above table remain real, not a fake invulnerable safe zone.
function HouseCoverService:_intercept(piece: any, x: number, z: number, nx: number, nz: number): boolean
	local plane = piece.Target.Position.X
	-- The same original Part blocks passage in BOTH directions. A Braid that
	-- has entered cannot ghost out through the closet on its way to a target.
	if x == nx or (x <= plane and nx <= plane) or (x >= plane and nx >= plane) then return false end
	local t = (plane-x)/(nx-x)
	if t < 0 or t > 1 then return false end
	local crossingZ = z+(nz-z)*t
	return math.abs(crossingZ-piece.Target.Position.Z) <= piece.Width*0.5
end
function HouseCoverService:intercept(x: number, z: number, nx: number, nz: number): any?
	if self.activeCount == 0 or self.Time.phase ~= "Night" then return nil end
	for _, piece in ipairs(self.Pieces) do
		if piece.Placed and self:_intercept(piece,x,z,nx,nz) then return piece end
	end
	return nil
end
function HouseCoverService:bracing(x: number, z: number, targetX: number, targetZ: number, egressOnly: boolean?): any?
	if self.activeCount == 0 or self.Time.phase ~= "Night" then return nil end
	for _, piece in ipairs(self.Pieces) do
		local plane = piece.Target.Position.X
		local fromInside = x < plane
		if piece.Placed and (not egressOnly or fromInside)
			and math.abs(x-plane) <= 12 and math.abs(targetX-plane) > 1
			and (x-plane)*(targetX-plane) < 0
			and math.abs(z-piece.Target.Position.Z) <= piece.Width*0.5+3
			and self:_intercept(piece,x,z,targetX,targetZ) then return piece end
	end
	return nil
end
function HouseCoverService:loseContact(): ()
	-- A partial push is not permanent damage. The Braid must stay at the
	-- SAME item while pursuing sensed prey or physically exiting to a valid
	-- server-owned lure/last-observed destination for the whole breach tell.
	local previous = self.Pressing
	if previous then previous.Pressure = 0; self.Pressing = nil end
end
function HouseCoverService:press(piece: any, dt: number, creature: any?): boolean
	if not self.running or self.Time.phase ~= "Night" or not piece.Placed then return false end
	if self.Pressing ~= piece then self:loseContact(); self.Pressing = piece end
	piece.Pressure += math.min(math.max(dt,0),0.1)
	if piece.Pressure < 2.4 then return false end
	piece.Part.CFrame = piece.Home -- dislodge ORIGINAL item, do not destroy it
	piece.Placed, piece.Broken, piece.Pressure = false, true, 0
	self.Pressing = nil
	self.activeCount -= 1
	self:_publish(piece)
	if self.Noise then
		local p = piece.Target.Position
		self.Noise:emitAt("AIR",p.X,p.Y,p.Z,1.2,self.Time.elapsedTotal or 0)
	end
	if self.Logger then
		-- Append to the EXISTING one-per-break Output line. The Studio bridge
		-- cannot inspect Play; capture actual contact context without a new
		-- cadence job, raycast, runtime Instance or ordinary-frame log.
		local context = ""
		if creature and creature.X and creature.Y and creature.Z then
			local gx = creature.TargetX and string.format("%.1f", creature.TargetX) or "none"
			local gz = creature.TargetZ and string.format("%.1f", creature.TargetZ) or "none"
			local feet = creature.Locomotion and creature.Locomotion:anchors() or 0
			context = string.format(" core(%.1f,%.1f,%.1f) nav(%s,%s) reason=%s feet=%d",
				creature.X, creature.Y, creature.Z, gx, gz,
				tostring(creature.DecisionReason or "none"), feet)
		end
		self.Logger("info", "Braid dislodged "..piece.House.." "..piece.Kind.."; paid Day move required"..context)
	end
	return true
end
function HouseCoverService:onPhaseChanged(_phase: string): ()
	-- Placed state is deliberately NOT reset at Dawn/death. It lasts until a
	-- dedicated Night Braid attack, and is never written to a DataStore.
	self:loseContact()
	for _, piece in ipairs(self.Pieces) do piece.Pressure = 0; self:_publish(piece) end
end
function HouseCoverService:start(): ()
	if self.running then return end
	self.running = true
	for _, piece in ipairs(self.Pieces) do
		self:_publish(piece)
		self.connections[#self.connections + 1] = piece.Prompt.Triggered:Connect(function(player: any)
			if self.Prep then self.Prep:begin(piece.Action,player) end
		end)
	end
end
function HouseCoverService:stop(): ()
	if not self.running then return end
	self.running = false
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.connections = {}
	for _, piece in ipairs(self.Pieces) do piece.Prompt.Enabled=false;piece.Helper.Enabled=false end
end
return HouseCoverService
