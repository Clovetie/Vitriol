--!strict
-- Server-owned garage fuel/lamp choice. Instances are preauthored in Edit mode.
local DayPrepService = {}
DayPrepService.__index = DayPrepService
local function get(parent: any, name: string, class: string): any
	local node = parent and parent:FindFirstChild(name)
	if not node or not node:IsA(class) then error("[Vitriol.DayPrep] missing authored " .. name .. " (" .. class .. ")", 0) end
	return node
end
function DayPrepService:init(s: any): ()
	self.Players, self.Health, self.Time, self.Session = s.Players, s.Health, s.Time, s.Session
	self.Noise, self.Cadence, self.Logger = s.Noise, s.Cadence, s.Logger
	local interactions = get(get(s.Workspace, "Map", "Folder"), "Interactions", "Folder")
	self.Can = get(interactions, "Garage_FuelCan", "Part")
	self.CanPrompt = get(self.Can, "TakeFuel", "ProximityPrompt")
	self.Generator = get(interactions, "Garage_Generator", "Part")
	self.GeneratorPrompt = get(self.Generator, "PowerLamp", "ProximityPrompt")
	self.GarageRepairPrompt = get(self.Generator, "RepairGarageLight", "ProximityPrompt")
	self.GarageRepairHelper = get(self.Generator, "AssistGarageLight", "ProximityPrompt")
	self.LampPart = get(interactions, "Garage_GeneratorLamp", "Part")
	self.Lamp = get(self.LampPart, "PoweredLight", "PointLight")
	self.BellLever = get(interactions, "Church_BellLever", "Part")
	self.BellPrompt = get(self.BellLever, "PrimeBell", "ProximityPrompt")
	-- User-authored ground bell and rope replace the old prototype cylinder.
	-- HoistPos remains stationary; only the nested bell Model + Rope move.
	self.BellRoot = get(interactions, "Bell", "Model")
	self.BellHoistPos = get(self.BellRoot, "HoistPos", "Part")
	self.BellRope = get(self.BellRoot, "Rope", "Part")
	self.BellModel = get(self.BellRoot, "Bell", "Model")
	self.BellPart = get(self.BellModel, "Bell", "MeshPart")
	self.BellLight = get(self.BellPart, "BellPulse", "PointLight")
	self.BellSound = get(self.BellPart, "BellRing", "Sound")
	self.BellGround = self.BellModel:GetPivot()
	self.RopeGround = self.BellRope.CFrame
	local from, to = self.BellGround.Position, self.BellHoistPos.Position
	local lift = Vector3.new(to.X-from.X,to.Y-from.Y,to.Z-from.Z)
	self.BellRaised = self.BellGround + lift
	self.RopeRaised = self.RopeGround + lift
	self.hoistDuration = 2.4
	self.hoistElapsed,self.hoistActive,self.bellHoisted,self.hoistPending = 0,false,false,false
	self.hoistSlot = nil
	self.owner, self.available, self.powered, self.running = nil, true, false, false
	-- Same-slot labels for exceptional DayPrep:Pulse Output, never a clock
	-- sample, new scheduler or client-visible transaction state.
	self.lastPulseAction,self.lastPulseFrom,self.lastPulseTo="none","none","none"
	self.lastPulseHum=false
	self.garageIntact = true -- run-persistent repair; only the Braid breaks it
	self.bellArmed, self.bellRang, self.bellRinging, self.bellPulseOn = false, false, false, false
	self.bellAt, self.bellStarted, self.bellUntil, self.nextGeneratorHum = nil, nil, nil, 0
	self.connections = {}
end
function DayPrepService:_day(): boolean
	return self.Time.phase == "Day" or self.Time.phase == "Dawn"
end
function DayPrepService:_publish(): ()
	self.Can.Transparency = self.available and 0 or 1
	self.Can.CanQuery = self.available
	self.CanPrompt.Enabled = self.running and self.Prep ~= nil and self.available and self:_day()
	self.GeneratorPrompt.Enabled = self.running and self.Prep ~= nil and self.garageIntact
		and not self.powered and self:_day()
	self.GarageRepairPrompt.Enabled = self.running and self.Prep ~= nil and not self.garageIntact
		and self:_day() and self.Session.state ~= "Ended" and (self.Time:dayRemaining() or 0) > 0
	self.Lamp.Enabled = self.powered and self.garageIntact
	self.LampPart.Material = self.powered and Enum.Material.Neon or Enum.Material.Metal
	self.LampPart.Color = self.powered and Color3.fromRGB(239, 177, 96)
		or not self.garageIntact and Color3.fromRGB(115,55,48) or Color3.fromRGB(75, 82, 83)
	self.Generator:SetAttribute("Powered", self.powered and self.garageIntact)
	self.Generator:SetAttribute("Broken", not self.garageIntact)
	self.LampPart:SetAttribute("Broken", not self.garageIntact)
	self.BellPrompt.Enabled = self.running and self.Prep ~= nil and self:_day() and not self.bellArmed
		and self.Session.state ~= "Ended"
	self.BellLever:SetAttribute("Armed", self.bellArmed)
	self.BellPart:SetAttribute("Ringing", self.bellRinging)
	self.BellLight.Enabled = self.bellPulseOn
	-- Pulse only the authored PointLight. Never recolor/re-materialize the user's
	-- MeshPart: the model's chosen finish must survive each Night strike.
end
function DayPrepService:_valid(player: any, part: any): boolean
	if not self.running or not player or not player.UserId or not self:_day() or self.Session.state == "Ended" then return false end
	local state = self.Health.states[player.UserId]
	if not state or state.dead or state.awaitingDawn or state.permadead then return false end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root.Position then return false end
	local a, b = root.Position, part.Position
	local dx, dy, dz = a.X - b.X, a.Y - b.Y, a.Z - b.Z
	return dx * dx + dy * dy + dz * dz <= 100 -- 10-stud authored prompt reach
end
-- Action-specific preflight mirrors each synchronous commit method, so a
-- pending vote is cancelled if fuel ownership or the one-use bell changed.
function DayPrepService:ready(action: string, player: any): boolean
	if action == "TakeFuel" then
		return self.available and self.owner == nil and self:_valid(player, self.Can)
	elseif action == "PowerGarage" then
		return self.garageIntact and not self.powered and self.owner == (player and player.UserId)
			and self:_valid(player, self.Generator)
	elseif action == "RepairGarageLight" then
		return not self.garageIntact and self:_valid(player, self.Generator)
			and (self.Time:dayRemaining() or 0) > 0
	elseif action == "PrimeBell" then
		return not self.bellArmed and self:_valid(player, self.BellLever)
	end
	return false
end
function DayPrepService:_noise(intensity: number): ()
	if self.Noise then
		local p = self.Generator.Position
		self.Noise:emitAt("AIR", p.X, p.Y, p.Z, intensity, self.Time.elapsedTotal or 0)
	end
end
function DayPrepService:pickup(player: any): boolean
	if not self.available or self.owner ~= nil or not self:_valid(player, self.Can) then return false end
	-- Serialized server callbacks have one winner; no yield before the claim.
	self.available, self.owner = false, player.UserId
	player:SetAttribute("CarryFuelCan", true)
	self:_publish()
	self:_noise(0.3)
	return true
end
function DayPrepService:power(player: any): boolean
	if not self.garageIntact or self.powered or self.owner ~= (player and player.UserId)
		or not self:_valid(player, self.Generator) then return false end
	self.owner, self.powered = nil, true
	player:SetAttribute("CarryFuelCan", false)
	self:_publish()
	self:_noise(1.2)
	if self.Logger then self.Logger("info", "garage lamp powered with one fuel can (audible at night)") end
	return true
end
function DayPrepService:repairGarage(player: any): boolean
	if not self:ready("RepairGarageLight", player) then return false end
	self.garageIntact = true
	self:_publish()
	self:_noise(0.7)
	if self.Logger then self.Logger("info", "garage light repaired for current run unless Braid breaks it") end
	return true
end
function DayPrepService:damageGarage(): boolean
	if not self.running or self.Time.phase ~= "Night" or not self.powered
		or not self.garageIntact then return false end
	self.garageIntact, self.powered = false, false
	self:_publish()
	if self.Logger then self.Logger("info", "Braid sabotaged garage light; repair before fueling it again") end
	return true
end
-- World preparation, not a carried Tool. Death after priming does not mint
-- another use; Dawn resets the single authored bell for the next cycle.
function DayPrepService:primeBell(player: any): boolean
	if self.bellArmed or not self:_valid(player, self.BellLever) then return false end
	self.bellArmed = true
	self:_publish()
	if self.Logger then self.Logger("info", "church bell primed for one Night signal") end
	return true
end

-- A one-shot 20 Hz slot exists only during the brief hoist; it reuses the
-- existing Cadence heartbeat and moves ONLY the user's nested bell and Rope.
function DayPrepService:_tickHoist(dt: number): ()
	if not self.hoistActive then return end
	self.hoistElapsed = math.min(self.hoistDuration, self.hoistElapsed + math.max(dt,0))
	local p = self.hoistElapsed / self.hoistDuration
	local eased = p*p*(3-2*p)
	self.BellModel:PivotTo(self.BellGround:Lerp(self.BellRaised,eased))
	self.BellRope.CFrame = self.RopeGround:Lerp(self.RopeRaised,eased)
	if p >= 1 then
		self.hoistActive,self.bellHoisted = false,true
		if self.hoistSlot then self.Cadence:unregister(self.hoistSlot); self.hoistSlot=nil end
		if self.Logger then self.Logger("info","user's bell and rope reached HoistPos") end
	end
end
function DayPrepService:startBellHoist(): boolean
	if not self.running or not self.bellArmed or not self.hoistPending
		or self.hoistActive or self.bellHoisted then return false end
	self.hoistActive,self.hoistElapsed = true,0
	self.hoistSlot = self.Cadence:register({
		Name="DayPrep:BellHoist", PeriodSeconds=1/20,
		BudgetMs=self.Session.Config.Budgets.FrameShares.BellHoist,
		Run=function(dt) self:_tickHoist(dt) end,
	})
	return true
end
function DayPrepService:_resetBellHoist(): ()
	if self.hoistSlot then self.Cadence:unregister(self.hoistSlot); self.hoistSlot=nil end
	self.hoistActive,self.bellHoisted,self.hoistPending,self.hoistElapsed = false,false,false,0
	self.BellModel:PivotTo(self.BellGround)
	self.BellRope.CFrame=self.RopeGround
end
function DayPrepService:onPrepReveal(action: string): ()
	if action=="PrimeBell" then self:startBellHoist() end
end

-- One existing 0.25-second DayPrep slot drives three visible pulses. The user-
-- supplied Sound already contains three strikes; play it ONCE, not three times.
-- The lure persists for twelve seconds, but nearby prey wins in CreatureService.
function DayPrepService:_tickBell(): ()
	local now = self.Time.elapsedTotal or 0
	local wasRinging, wasPulse = self.bellRinging, self.bellPulseOn
	if self.Time.phase ~= "Night" or self.Session.state == "Ended" then
		if self.bellRinging or self.bellPulseOn then
			self.bellRinging, self.bellPulseOn = false, false
			self:_publish()
		end
		return
	end
	if self.bellAt and not self.bellRang and now >= self.bellAt
		and (not self.hoistPending or self.bellHoisted) then
		self.bellRang, self.bellRinging, self.bellPulseOn = true, true, true
		self.bellStarted, self.bellUntil = now, now + 12
		if self.BellSound.SoundId ~= "" then self.BellSound:Play() end
		if self.Noise then
			local p = self.BellLever.Position
			self.Noise:emitAt("AIR", p.X, p.Y, p.Z, 1.0, now)
			self.Noise:emitAt("VIBRATION", p.X, p.Y, p.Z, 0.8, now)
		end
		if self.Logger then self.Logger("info", "church bell rang; distant Braid lured for one short window") end
	end
	if self.bellRinging then
		if now >= (self.bellUntil or 0) then
			self.bellRinging, self.bellPulseOn = false, false
		else
			local elapsed = now - (self.bellStarted or now)
			self.bellPulseOn = elapsed < 3 and elapsed % 1 < 0.4
		end
		if self.bellRinging ~= wasRinging or self.bellPulseOn ~= wasPulse then self:_publish() end
	end
end

function DayPrepService:drop(player: any): ()
	if not player then return end
	if self.owner == player.UserId then
		self.owner, self.available = nil, true -- restore the same authored pickup
		self:_publish()
	end
	player:SetAttribute("CarryFuelCan", false)
end
function DayPrepService:onPhaseChanged(phase: string): ()
	if phase == "Dawn" then
		self:_resetBellHoist() -- bell and user's rope return together to ground
		self.powered = false -- one can powers one night
		if self.owner == nil then self.available = true end
		if self.bellRang then self.BellSound:Stop() end
		self.bellArmed, self.bellRang, self.bellRinging, self.bellPulseOn = false, false, false, false
		self.bellAt, self.bellStarted, self.bellUntil = nil, nil, nil
	elseif phase == "Night" then
		local now = self.Time.elapsedTotal or 0
		self.bellAt = self.bellArmed and now + 3 or nil
		self.nextGeneratorHum = now + 3
	end
	self:_publish()
end
function DayPrepService:signal(bellInvestigated: boolean?): any
	if self.Time.phase ~= "Night" then return nil end
	-- A distant bell diverts the Braid once; once it reaches the source it
	-- resumes investigating other lights/prey instead of freezing for 12 s.
	if self.bellRinging and not bellInvestigated then return self.BellLever.Position, 30 end
	if self.powered and self.garageIntact then
		return self.Generator.Position, 70, "GarageLight" -- attack accessible power feed
	end
	return nil
end
function DayPrepService:start(): ()
	if self.running then return end
	self.running = true
	self:_publish()
	self.connections[#self.connections + 1] = self.CanPrompt.Triggered:Connect(function(player: any)
		if self.Prep then self.Prep:begin("TakeFuel",player) end -- fail closed without a vote
	end)
	self.connections[#self.connections + 1] = self.GeneratorPrompt.Triggered:Connect(function(player: any)
		if self.Prep then self.Prep:begin("PowerGarage",player) end
	end)
	self.connections[#self.connections + 1] = self.GarageRepairPrompt.Triggered:Connect(function(player: any)
		if self.Prep then self.Prep:begin("RepairGarageLight",player) end
	end)
	self.connections[#self.connections + 1] = self.BellPrompt.Triggered:Connect(function(player: any)
		if self.Prep then self.Prep:begin("PrimeBell",player) end
	end)
	self.connections[#self.connections + 1] = self.Players.PlayerRemoving:Connect(function(player: any) self:drop(player) end)
	self.connections[#self.connections + 1] = self.Players.PlayerAdded:Connect(function(player: any)
		player:SetAttribute("CarryFuelCan", self.owner == player.UserId)
	end)
	for _, player in ipairs(self.Players:GetPlayers()) do player:SetAttribute("CarryFuelCan", self.owner == player.UserId) end
	self.slowSlot = self.Cadence:register({
		Name = "DayPrep:Pulse", PeriodSeconds = 0.25, BudgetMs = self.Session.Config.Budgets.SlowShares.DayPrep,
		Run = function(dt)
			-- Snapshot action/stage BEFORE tick, since blackout commits may clear
			-- the transaction or switch it to reveal in this very measured slot.
			local tx=self.Prep and self.Prep.current
			self.lastPulseAction=tx and tx.Action or "none"
			self.lastPulseFrom=tx and tx.Stage or "none"
			self.lastPulseHum=false
			self:_tickBell()
			if self.Prep then self.Prep:tick(dt) end
			tx=self.Prep and self.Prep.current
			self.lastPulseTo=tx and tx.Stage or "none"
			if self.Floodlight then self.Floodlight:tick() end
			local now = self.Time.elapsedTotal or 0
			if self.powered and self.Time.phase == "Night" and now >= self.nextGeneratorHum then
				self.nextGeneratorHum = now + 3
				self.lastPulseHum=true
				self:_noise(0.65)
			end
		end,
	})
end
function DayPrepService:stop(): ()
	if not self.running then return end
	self.running = false
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	self.connections = {}
	if self.slowSlot then self.Cadence:unregister(self.slowSlot); self.slowSlot = nil end
	self:_resetBellHoist()
	if self.bellRang then self.BellSound:Stop() end
	self.bellRinging, self.bellPulseOn = false, false
	self.BellLight.Enabled = false
	self.CanPrompt.Enabled, self.GeneratorPrompt.Enabled, self.BellPrompt.Enabled = false, false, false
	self.GarageRepairPrompt.Enabled, self.GarageRepairHelper.Enabled = false, false
end
return DayPrepService
