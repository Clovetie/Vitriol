--!strict
-- One server-owned, preauthored garage barrier. No runtime Instances/UI.
local BarricadeService = {}
BarricadeService.__index = BarricadeService
local function get(parent: any, name: string, class: string): any
	local node = parent and parent:FindFirstChild(name)
	if not node or not node:IsA(class) then error("[Vitriol.Barricade] missing authored " .. name .. " (" .. class .. ")", 0) end
	return node
end
function BarricadeService:init(s: any): ()
	self.Players, self.Health, self.Time, self.Session = s.Players, s.Health, s.Time, s.Session
	self.Noise, self.Logger = s.Noise, s.Logger
	local map = get(s.Workspace, "Map", "Folder")
	local interactions = get(map, "Interactions", "Folder")
	self.Gate = get(interactions, "Garage_BoardedGate", "Part")
	self.Latch = get(interactions, "Garage_BoardingLatch", "Part")
	self.Prompt = get(self.Latch, "BoardGarage", "ProximityPrompt")
	self.boarded, self.spent, self.running, self.pressure = false, false, false, 0
	self.connection = nil
end
function BarricadeService:_day(): boolean
	return self.Time.phase == "Day" or self.Time.phase == "Dawn"
end
function BarricadeService:_publish(): ()
	self.Gate.Transparency = self.boarded and 0 or 1
	self.Gate.CanCollide = self.boarded
	self.Gate.CanQuery = self.boarded
	self.Gate:SetAttribute("Barricaded", self.boarded)
	-- An occupant may always abandon a boarded bay to escape. Opening it
	-- spends the boards for the night and makes noise; it never mints a plank.
	self.Prompt.Enabled = self.running and self.Session.state ~= "Ended"
		and (self.boarded or (self.Prep ~= nil and self:_day() and not self.spent))
	self.Prompt.ActionText = self.boarded and "Throw gate open (loud)" or "Board service bay (noisy)"
	self.Prompt.HoldDuration = self.boarded and 0.8 or 3
end
function BarricadeService:_noise(intensity: number): ()
	if not self.Noise then return end
	local p = self.Gate.Position
	local now = self.Time.elapsedTotal or 0
	self.Noise:emitAt("AIR", p.X, p.Y, p.Z, intensity, now)
	self.Noise:emitAt("VIBRATION", p.X, p.Y, p.Z, intensity, now)
end
function BarricadeService:_validPlayer(player: any): boolean
	if not self.running or self.Session.state == "Ended" or not player or not player.UserId then return false end
	local state = self.Health.states[player.UserId]
	if not state or state.dead or state.awaitingDawn or state.permadead then return false end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root.Position then return false end
	local a, b = root.Position, self.Latch.Position
	local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return dx * dx + dy * dy + dz * dz <= 9 * 9
end
function BarricadeService:readyBoard(player: any): boolean
	return not self.spent and not self.boarded and self:_day() and self:_validPlayer(player)
end
function BarricadeService:board(player: any): boolean
	if self.spent or not self:_day() or not self:_validPlayer(player) then return false end
	-- Triggered is server-owned. No yield before committing the only plank set.
	self.spent, self.boarded, self.pressure = true, true, 0
	self:_publish()
	self:_noise(0.9)
	if self.Logger then self.Logger("info", "garage service bay boarded; one noisy barrier spent") end
	return true
end
function BarricadeService:unboard(player: any): boolean
	if not self.boarded or not self:_validPlayer(player) then return false end
	self.boarded = false -- boards were already spent; no re-use until Dawn
	self:_publish()
	self:_noise(1.4)
	if self.Logger then self.Logger("info", "garage barricade opened by a survivor") end
	return true
end
function BarricadeService:crossing(x: number, z: number, nx: number, nz: number): boolean
	if not self.boarded then return false end
	local plane = self.Gate.Position.X
	if (x < plane and nx < plane) or (x > plane and nx > plane) then return false end
	local zMid = (z + nz) * 0.5
	return math.abs(zMid - self.Gate.Position.Z) <= self.Gate.Size.Z * 0.5 + 1
end
-- The planted-foot-led body can remain beyond five studs even when a front
-- tendril has already latched to the gate. Require a real gate foothold OR a
-- near core, and always a chase target across the bay. A distant target by
-- itself cannot break anything.
function BarricadeService:pressing(x: number, z: number, tx: number, tz: number, contacts: any?, contactCount: number?): boolean
	if not self.boarded then return false end
	local plane = self.Gate.Position.X
	local forward = tx - x
	if math.abs(forward) < 1e-4 then return false end
	local fraction = (plane - x) / forward
	if fraction < 0 or fraction > 1 then return false end
	local crossingZ = z + (tz - z) * fraction
	local halfWidth = self.Gate.Size.Z * 0.5 + 1
	if math.abs(crossingZ - self.Gate.Position.Z) > halfWidth
		or math.abs(z - self.Gate.Position.Z) > halfWidth + 3 then return false end
	if math.abs(x - plane) <= 5 then return true end
	-- The ray fan already caches the actual BasePart under each foot. Never
	-- infer a breach from a generic floor/wall hit near the bay or a long ray
	-- to a distant player. It must touch THIS preauthored boarded gate.
	if contacts then
		for i = 1, contactCount or 0 do
			if contacts[i] == self.Gate then return true end
		end
	end
	return false
end
function BarricadeService:press(dt: number): boolean
	if not self.boarded then return false end
	if self.pressure == 0 and self.Logger then
		self.Logger("info", "Braid bracing boarded garage gate")
	end
	self.pressure += math.min(math.max(dt, 0), 0.1)
	if self.pressure >= 2.4 then
		self.boarded = false -- one successful breach; spent until Dawn
		self:_publish()
		self:_noise(1.7)
		if self.Logger then self.Logger("info", "Braid breached the garage barricade") end
		return true
	end
	return false
end
function BarricadeService:onPhaseChanged(phase: string): ()
	if phase == "Dawn" then
		self.boarded, self.spent, self.pressure = false, false, 0
	end
	self:_publish()
end
function BarricadeService:start(): ()
	if self.running then return end
	self.running = true
	self:_publish()
	self.connection = self.Prompt.Triggered:Connect(function(player: any)
		if self.boarded then self:unboard(player) -- the Night emergency exit is free
		elseif self.Prep then self.Prep:begin("BoardGarage",player) end
	end)
end
function BarricadeService:stop(): ()
	if not self.running then return end
	self.running = false
	if self.connection then self.connection:Disconnect(); self.connection = nil end
	self.Prompt.Enabled = false
end
return BarricadeService
