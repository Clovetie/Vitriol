--!strict
-- One repairable filling-station floodlight. Every Part, light and prompt was
-- preauthored in Edit mode; only server-owned state/properties change in Play.
local FloodlightService = {}
FloodlightService.__index = FloodlightService
local function get(parent: any, name: string, class: string): any
	local node = parent and parent:FindFirstChild(name)
	if not node or not node:IsA(class) then error("[Vitriol.Floodlight] missing authored " .. name .. " (" .. class .. ")", 0) end
	return node
end
function FloodlightService:init(s: any): ()
	self.Time, self.Session, self.Noise, self.Health = s.Time, s.Session, s.Noise, s.Health
	self.Players, self.Logger = s.Players, s.Logger
	local interactions = get(get(s.Workspace, "Map", "Folder"), "Interactions", "Folder")
	self.Switch = get(interactions, "Station_FloodlightSwitch", "Part")
	self.Prompt = get(self.Switch, "RepairFloodlight", "ProximityPrompt")
	self.Helper = get(self.Switch, "AssistFloodlight", "ProximityPrompt")
	self.Fixture = get(interactions, "Station_Floodlight", "Part")
	self.Beam = get(self.Fixture, "StationBeam", "PointLight")
	-- Structural repair persists for the server's whole run, across dawn and
	-- player deaths. Only a deliberate Night Braid attack can break it again.
	self.repaired, self.broken, self.running, self.nextBuzz = false, false, false, 0
	self.connection = nil
end
function FloodlightService:_day(): boolean
	return self.Time.phase == "Day" or self.Time.phase == "Dawn"
end
function FloodlightService:_publish(): ()
	local shining = self.running and self.repaired and self.Time.phase == "Night"
	self.Beam.Enabled = shining
	self.Fixture.Material = shining and Enum.Material.Neon or Enum.Material.Metal
	self.Fixture.Color = shining and Color3.fromRGB(202,230,238)
		or self.broken and Color3.fromRGB(115,55,48) or Color3.fromRGB(78,89,92)
	self.Fixture:SetAttribute("Powered", shining)
	self.Fixture:SetAttribute("Broken", self.broken)
	self.Switch:SetAttribute("Repaired", self.repaired)
	self.Switch:SetAttribute("Broken", self.broken)
	self.Prompt.Enabled = self.running and self.Prep ~= nil and self:_day() and not self.repaired
		and self.Session.state ~= "Ended" and (self.Time:dayRemaining() or 0) > 0
end
function FloodlightService:ready(player: any): boolean
	if not self.running or self.repaired or not self:_day() or self.Session.state == "Ended"
		or (self.Time:dayRemaining() or 0) <= 0 or not player or not player.UserId then return false end
	local connected = false
	for _, present in ipairs(self.Players:GetPlayers()) do
		if present == player then connected = true; break end
	end
	if not connected then return false end
	local health = self.Health.states[player.UserId]
	if not health or health.dead or health.awaitingDawn or health.permadead then return false end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if not root or not root.Position then return false end
	local a,b = root.Position,self.Switch.Position
	local dx,dy,dz = a.X-b.X,a.Y-b.Y,a.Z-b.Z
	return dx*dx+dy*dy+dz*dz <= 100 -- authored 10-stud repair reach
end
function FloodlightService:repair(player: any): boolean
	if not self:ready(player) then return false end
	self.repaired, self.broken = true, false
	self:_publish()
	local p = self.Fixture.Position
	if self.Noise then self.Noise:emitAt("AIR",p.X,p.Y,p.Z,0.65,self.Time.elapsedTotal or 0) end
	if self.Logger then self.Logger("info","station floodlight repaired until Braid sabotage; EM hum draws the distant Braid") end
	return true
end
function FloodlightService:damage(): boolean
	if not self.running or self.Time.phase ~= "Night" or not self.repaired then return false end
	self.repaired, self.broken = false, true
	self:_publish()
	if self.Logger then self.Logger("info", "Braid sabotaged station floodlight; Day repair required") end
	return true
end
function FloodlightService:signal(): any
	if self.running and self.repaired and self.Time.phase == "Night" then
		return self.Fixture.Position, 32, "StationLight" -- near prey outranks sabotage
	end
	return nil
end
function FloodlightService:tick(): ()
	if not self.Beam.Enabled or not self.Noise then return end
	local now = self.Time.elapsedTotal or 0
	if now < self.nextBuzz then return end
	self.nextBuzz = now + 3
	local p = self.Fixture.Position
	self.Noise:emitAt("EM",p.X,p.Y,p.Z,0.8,now)
	self.Noise:emitAt("AIR",p.X,p.Y,p.Z,0.35,now)
end
function FloodlightService:onPhaseChanged(phase: string): ()
	-- Dawn extinguishes the Night-only beam; it does NOT undo the repair.
	if phase == "Night" then self.nextBuzz = 0 end
	self:_publish()
end
function FloodlightService:start(): ()
	if self.running then return end
	self.running = true
	self:_publish()
	self.connection = self.Prompt.Triggered:Connect(function(player: any)
		if self.Prep then self.Prep:begin("RepairStationFloodlight",player) end
	end)
end
function FloodlightService:stop(): ()
	if not self.running then return end
	self.running = false
	if self.connection then self.connection:Disconnect(); self.connection=nil end
	self.Prompt.Enabled, self.Helper.Enabled, self.Beam.Enabled = false,false,false
end
return FloodlightService
