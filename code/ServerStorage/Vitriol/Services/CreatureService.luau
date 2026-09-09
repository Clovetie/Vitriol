--!strict
-- CreatureService.luau
-- Location: ServerStorage > Vitriol > Services > CreatureService  (ModuleScript)
-- Purpose:  Lifecycle and cadence owner for the single MVP Braid. Think is split:
--             stimulus bridge - may iterate players to emit vibration/scent/air;
--             observer       - samples NoiseField through Senses into CreatureMemory
--                              and steers from evidence, never from Players:GetPlayers.
--           Kill/health authority still iterates players for grab distance.
--           Woundable-only, one creature, no second Heartbeat, no sight.
-- Requires: Config/{GameConfig,MonsterConfig,SurvivalConfig},
--           Lib/{Genetics,RNG,Fabrik,Noise,UtilityAI},
--           Shared/{Skeleton,SkeletonCodec,CreatureMemory},
--           Creature/{CreatureCore,Body/*,Brain/Senses,Brain/Steering}
-- Used by:  Bootstrap, DebugHandler

local CreatureCore = require(script.Parent.Parent.Creature.CreatureCore)
local TendrilRig = require(script.Parent.Parent.Creature.Body.TendrilRig)
local Locomotion = require(script.Parent.Parent.Creature.Body.Locomotion)
local Senses = require(script.Parent.Parent.Creature.Brain.Senses)
local Steering = require(script.Parent.Parent.Creature.Brain.Steering)

local CreatureService = {}
CreatureService.__index = CreatureService

local function nowOf(timeService: any): number
	if timeService then
		return timeService.elapsedTotal or 0
	end
	return 0
end

local function speedOf(root: any): number
	local velocity = root and root.AssemblyLinearVelocity
	if velocity == nil then
		return 0
	end
	if velocity.Magnitude ~= nil then
		return velocity.Magnitude
	end
	local x = velocity.X or 0
	local y = velocity.Y or 0
	local z = velocity.Z or 0
	return math.sqrt(x * x + y * y + z * z)
end

function CreatureService:init(services: any): ()
	self.Config = services.Config
	self.Monster = services.Monster
	self.Survival = services.Survival
	self.Players = services.Players
	self.Workspace = services.Workspace
	self.Cadence = services.Cadence
	self.Time = services.Time
	self.Threat = services.Threat
	self.Health = services.Health
	self.Noise = services.Noise
	self.Remotes = services.Remotes
	self.Logger = services.Logger
	self.ResolveZone = services.ResolveZone
	self.creatures = {}
	self.order = {}
	self.nextId = 0
	self.running = false
	self.connections = {}
	self.presentedDeaths = {}
	self.lastZone = {}

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	self.Genetics = require(ReplicatedStorage.Vitriol.Lib.Genetics)
	self.RNG = require(ReplicatedStorage.Vitriol.Lib.RNG)
	self.Fabrik = require(ReplicatedStorage.Vitriol.Lib.Fabrik)
	self.Skeleton = require(ReplicatedStorage.Vitriol.Shared.Skeleton)
	self.SkeletonCodec = require(ReplicatedStorage.Vitriol.Shared.SkeletonCodec)
	self.CreatureMemory = require(ReplicatedStorage.Vitriol.Shared.CreatureMemory)
	self.UtilityAI = require(ReplicatedStorage.Vitriol.Lib.UtilityAI)
	self.Noise = services.Noise
	self.NoiseMotion = require(ReplicatedStorage.Vitriol.Lib.Noise).new(8191)

	local root = self.Workspace:FindFirstChild("Vitriol")
	if root == nil then
		root = Instance.new("Folder")
		root.Name = "Vitriol"
		root.Parent = self.Workspace
	end
	local folder = root:FindFirstChild("Creatures")
	if folder == nil then
		folder = Instance.new("Folder")
		folder.Name = "Creatures"
		folder.Parent = root
	end
	self.Folder = folder
end

function CreatureService:start(): ()
	if self.running then
		return
	end
	self.running = true
	if self.Players then
		self.connections[#self.connections + 1] = self.Players.PlayerAdded:Connect(function()
			self:reconcile()
		end)
		self.connections[#self.connections + 1] = self.Players.PlayerRemoving:Connect(function(player)
			if player then
				self.presentedDeaths[player.UserId] = nil
				self.lastZone[player.UserId] = nil
			end
			self:reconcile()
		end)
	end
	if self.Cadence then
		self.frameSlot = self.Cadence:register({
			Name = "Creature:Frame",
			PeriodSeconds = 1 / 60,
			BudgetMs = self.Config.Budgets.CreatureFrameMs,
			Run = function(dt)
				self:step(dt)
			end,
		})
		self.thinkSlot = self.Cadence:register({
			Name = "Creature:Think",
			PeriodSeconds = 1 / self.Config.Ticks.ThinkHz,
			BudgetMs = self.Config.Budgets.FrameShares.Think,
			Run = function(dt)
				self:think(dt)
			end,
		})
		self.senseSlot = self.Cadence:register({
			Name = "Creature:Sense",
			PeriodSeconds = 1 / self.Config.Ticks.SenseHz,
			BudgetMs = self.Config.Budgets.PerceptionMs,
			Run = function(dt)
				self:sense(dt)
			end,
		})
	end
	self:reconcile()
end

function CreatureService:_playerRoot(player: any): any
	local character = player and player.Character
	if character == nil then
		return nil
	end
	return character:FindFirstChild("HumanoidRootPart")
end

function CreatureService:_spawnPosition(): (number, number, number)
	local players = self.Players and self.Players:GetPlayers() or {}
	local first = players[1]
	local root = self:_playerRoot(first)
	local spawn = self.Monster.Spawn
	if root and root.Position then
		return root.Position.X + spawn.DistanceFromPlayer, root.Position.Y + spawn.HeightOffset, root.Position.Z + spawn.DistanceFromPlayer
	end
	local location = self.Workspace:FindFirstChild("SpawnLocation")
	if location and location.Position then
		return location.Position.X + spawn.DistanceFromPlayer, location.Position.Y + spawn.HeightOffset, location.Position.Z + spawn.DistanceFromPlayer
	end
	return spawn.FallbackX, spawn.FallbackY, spawn.FallbackZ
end

function CreatureService:_makeGenome(id: number): any
	local budgetCfg = self.Monster.Budget
	local threat = self.Threat and self.Threat.threat or 0
	local budget = budgetCfg.Threat0 + (budgetCfg.Threat1 - budgetCfg.Threat0) * threat
	local evolution = self.Monster.Evolution
	local genetics = self.Genetics.new(self.Monster.Genes, {
		budget = budget,
		sigma = evolution.Sigma,
		structuralChance = evolution.StructuralChance,
	})
	local genome = genetics:roll(self.RNG.new(id * 7919 + 37))
	return genetics, genome, genetics:express(genome)
end

function CreatureService:_attachBrain(creature: any): ()
	local stats = creature.Stats or {}
	stats.Genome = creature.Genome
	creature.Memory = self.CreatureMemory.new(self.Monster)
	creature.Senses = Senses.new({
		Field = self.Noise,
		Config = self.Monster,
		Stats = stats,
		RNG = self.RNG.new(creature.Id * 13 + 7),
		Workspace = self.Workspace,
		RaycastParams = creature.RaycastParams,
	})
	creature.Steering = Steering.new({
		Config = self.Monster,
		Stats = stats,
		Utility = self.UtilityAI.new(),
		Features = self.Config.Features,
		RNG = self.RNG.new(creature.Id * 29 + 3),
	})
	creature.SpawnX, creature.SpawnY, creature.SpawnZ = creature.X, creature.Y, creature.Z
	creature.LastDecision = nil
end

function CreatureService:_spawnOne(): any
	local x, y, z = self:_spawnPosition()
	self.nextId = self.nextId + 1
	local id = self.nextId
	local genetics, genome, stats = self:_makeGenome(id)
	local replicator = nil
	if buffer ~= nil and self.Remotes and self.Remotes.stream then
		replicator = require(script.Parent.Parent.Creature.Replicator).new(id, {
			Codec = self.SkeletonCodec,
			Config = self.Config,
			Remote = self.Remotes.stream,
		})
	end
	local creature = CreatureCore.new({
		Id = id,
		Config = self.Config,
		Monster = self.Monster,
		Workspace = self.Workspace,
		Parent = self.Folder,
		Stats = stats,
		Genome = genome,
		TendrilRig = TendrilRig,
		Locomotion = Locomotion,
		Fabrik = self.Fabrik,
		Skeleton = self.Skeleton,
		Noise = self.NoiseMotion,
		Replicator = replicator,
		X = x,
		Y = y,
		Z = z,
		Logger = self.Logger,
	})
	creature.Genetics = genetics
	self:_attachBrain(creature)
	self.creatures[id] = creature
	self.order[#self.order + 1] = id
	if self.Logger then
		self.Logger("info", "creature " .. tostring(id) .. " spawned: Braid, woundable-only")
	end
	return creature
end

function CreatureService:_despawnAt(index: number): ()
	local id = self.order[index]
	local creature = self.creatures[id]
	if creature then
		creature:destroy()
		self.creatures[id] = nil
	end
	local last = #self.order
	self.order[index] = self.order[last]
	self.order[last] = nil
end

function CreatureService:reconcile(): ()
	if not self.running then
		return
	end
	local players = self.Players and self.Players:GetPlayers() or {}
	local desired = 0
	local hasCharacter = false
	for i = 1, #players do
		if self:_playerRoot(players[i]) ~= nil then
			hasCharacter = true
			break
		end
	end
	if hasCharacter and self.Threat then
		desired = self.Threat:creatureCount()
	end
	local cap = self.Config.Session.MaxCreatures or desired
	if desired > cap then
		desired = cap
	end
	while #self.order < desired do
		self:_spawnOne()
	end
	while #self.order > desired do
		self:_despawnAt(#self.order)
	end
end

function CreatureService:_zoneAt(x: number, y: number, z: number): any
	if self.ResolveZone then
		return self.ResolveZone(x, y, z) or "Open"
	end
	return "Open"
end

-- Stimulus bridge: the only think-path that may iterate players. Emits into
-- NoiseField. Does not choose a creature target.
function CreatureService:emitStimuli(now: number): ()
	local field = self.Noise
	if field == nil or self.Players == nil then
		return
	end
	local players = self.Players:GetPlayers()
	local senses = self.Monster.Senses
	local still = senses.StillSpeedStuds or 0.35
	local sprint = senses.SprintSpeedStuds or 16
	local emission = (self.Survival and self.Survival.Emission) or {}
	local footsteps = emission.FootstepVibration or { Resting = 0, Walking = 0.25, Sprinting = 0.70 }
	local baseScent = emission.BaseScent or 0.20
	for i = 1, #players do
		local player = players[i]
		local healthState = self.Health and self.Health.states and self.Health.states[player.UserId]
		if healthState == nil or not healthState.dead then
			local root = self:_playerRoot(player)
			if root and root.Position then
				local x, y, z = root.Position.X, root.Position.Y, root.Position.Z
				local speed = speedOf(root)
				local intensity = footsteps.Resting or 0
				if speed >= sprint then
					intensity = footsteps.Sprinting or 0.70
				elseif speed >= still then
					intensity = footsteps.Walking or 0.25
				end
				if intensity > 0 then
					local material = nil
					local character = player.Character
					local humanoid = character and character:FindFirstChildOfClass("Humanoid")
					local floor = humanoid and humanoid.FloorMaterial
					if type(floor) == "table" and floor.Name then
						material = floor.Name
					elseif type(floor) == "string" then
						material = floor
					end
					field:emitAt("VIBRATION", x, y, z, intensity, now, nil, material)
				end
				-- Body scent only. HealthService already emits bleed SCENT/AIR;
				-- multiplying scentScale here would double-count blood.
				local scent = baseScent
				if speed >= sprint then
					scent = scent * 2
				end
				if scent > 0 then
					field:emitAt("SCENT", x, y, z, scent, now)
				end
				local zone = self:_zoneAt(x, y, z)
				local posture = "Idle"
				if speed >= sprint then
					posture = "Fleeing"
				elseif speed >= still then
					posture = "Scavenging"
				end
				local prev = self.lastZone[player.UserId]
				self.lastZone[player.UserId] = { zone = zone, posture = posture }
				if prev and (prev.zone ~= zone or prev.posture ~= posture) then
					for c = 1, #self.order do
						local creature = self.creatures[self.order[c]]
						if creature and creature.Memory then
							creature.Memory:observeTagged(zone, posture)
						end
					end
				end
			end
		end
	end
end

-- Observer: samples the field. Must not call Players:GetPlayers.
function CreatureService:sense(_dt: number): ()
	local now = nowOf(self.Time)
	for i = 1, #self.order do
		local creature = self.creatures[self.order[i]]
		if creature and creature.Senses and creature.Memory then
			local x, y, z = creature:position()
			local observations, n = creature.Senses:sample(x, y, z, now)
			for k = 1, n do
				local rec = observations[k]
				creature.Memory:observe(rec.channel, rec.x, rec.y, rec.z, rec.confidence, now, rec.intensity)
			end
			creature.Memory:decay(now)
		end
	end
end

-- Kill authority: player iteration is allowed here, not for targeting.
function CreatureService:_maybeGrab(creature: any): ()
	if not creature:isThreatening() or self.Health == nil or self.Players == nil then
		return
	end
	local kill = self.Monster.Kill or {}
	local grab = kill.GrabDistance or 5.5
	local grabSq = grab * grab
	local cx, cy, cz = creature:position()
	local players = self.Players:GetPlayers()
	for i = 1, #players do
		local player = players[i]
		local healthState = self.Health.states and self.Health.states[player.UserId]
		if healthState == nil or not healthState.dead then
			local root = self:_playerRoot(player)
			if root and root.Position then
				local dx = root.Position.X - cx
				local dy = root.Position.Y - cy
				local dz = root.Position.Z - cz
				if dx * dx + dy * dy + dz * dz <= grabSq then
					self.Health:beginCreatureKill(player, creature.Id)
				end
			end
		end
	end
end

function CreatureService:_logDecision(creature: any, request: any): ()
	local diagnostics = self.Config.Diagnostics or {}
	local features = self.Config.Features or {}
	if not diagnostics.LogDecisionDump and not features.DebugDecisionDump then
		return
	end
	if self.Logger == nil or request == nil then
		return
	end
	local scores = request.scores or {}
	local parts = {}
	local n = 0
	for name, score in pairs(scores) do
		n = n + 1
		parts[n] = tostring(name) .. ":" .. string.format("%.2f", score)
	end
	local line = "decision creature=" .. tostring(creature.Id)
		.. " action=" .. tostring(request.action)
		.. " channel=" .. tostring(request.channel or "none")
		.. " age=" .. string.format("%.2f", request.evidenceAge or 0)
		.. " conf=" .. string.format("%.2f", request.confidence or 0)
		.. " scores=" .. table.concat(parts, ",")
	self.Logger("info", line)
end

function CreatureService:think(_dt: number): ()
	self:reconcile()
	local now = nowOf(self.Time)
	self:emitStimuli(now)
	for i = 1, #self.order do
		local creature = self.creatures[self.order[i]]
		if creature and creature.Steering and creature.Memory then
			local x, y, z = creature:position()
			local evidence = creature.Memory:best(now)
			local lastKnown = creature.Memory:lastKnownRecord()
			local request = creature.Steering:decide({
				x = x,
				y = y,
				z = z,
				now = now,
				evidence = evidence,
				lastKnown = lastKnown,
				threatening = creature:isThreatening(),
				wound = creature.WoundLevel or 0,
				spawnX = creature.SpawnX,
				spawnY = creature.SpawnY,
				spawnZ = creature.SpawnZ,
				rng = creature.Steering.RNG,
			})
			creature.LastDecision = request
			if request and request.x ~= nil and creature:isThreatening() then
				creature:setTarget(request.x, request.y, request.z, request.confidence)
			else
				creature:clearTarget()
			end
			self:_logDecision(creature, request)
			if creature:isThreatening() then
				self:_maybeGrab(creature)
			end
		end
	end
end

function CreatureService:step(dt: number): ()
	for i = 1, #self.order do
		local id = self.order[i]
		local creature = self.creatures[id]
		if creature then
			local ok, err = pcall(function()
				creature:step(dt)
			end)
			if not ok then
				if self.Logger then
					self.Logger("error", "creature " .. tostring(id) .. " disabled after step error: " .. tostring(err))
				end
				creature:wound(1)
			end
		end
	end
end

function CreatureService:wound(id: number, amount: number): boolean
	local creature = self.creatures[id]
	if creature == nil then
		return false
	end
	creature:wound(amount)
	return true
end

function CreatureService:creature(id: number): any
	return self.creatures[id]
end

function CreatureService:presentVictimKill(player: any, state: any): ()
	-- Health owns the authoritative death edge. This presentation hook deliberately
	-- does not apply damage, destroy the character, or increment threat: it only tells
	-- the dead player where to look. The LocalScript keeps the camera at that player's
	-- head, so the victim sees the creature's final scene in first person while every
	-- other client keeps their ordinary third-person view.
	if player == nil or self.Remotes == nil or self.Remotes.creature == nil then
		return
	end
	local userId = player.UserId
	if userId == nil or self.presentedDeaths[userId] then
		return
	end
	local requestedId = state and (state.CreatureId or state.creatureId)
	local nearestId = nil
	if requestedId ~= nil and self.creatures[requestedId] ~= nil then
		nearestId = requestedId
	end
	local nearestSq = math.huge
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if nearestId == nil and root and root.Position then
		for i = 1, #self.order do
			local id = self.order[i]
			local creature = self.creatures[id]
			if creature then
				local x, y, z = creature:position()
				local dx = root.Position.X - x
				local dy = root.Position.Y - y
				local dz = root.Position.Z - z
				local distanceSq = dx * dx + dy * dy + dz * dz
				if distanceSq < nearestSq then
					nearestSq = distanceSq
					nearestId = id
				end
			end
		end
	end
	local sceneDuration = (state and (state.Duration or state.duration)) or (self.Monster.Kill and self.Monster.Kill.DurationSeconds) or 6.0
	local ok, err = pcall(function()
		self.Remotes.creature:FireAllClients({
			Kind = "VICTIM_KILL_START",
			VictimUserId = userId,
			CreatureId = nearestId,
			Duration = sceneDuration,
			FirstPerson = true,
		})
	end)
	if ok then
		self.presentedDeaths[userId] = true
	elseif self.Logger then
		self.Logger("warn", "victim camera event failed: " .. tostring(err))
	end
end

function CreatureService:snapshot(): any
	local out = {}
	for i = 1, #self.order do
		local creature = self.creatures[self.order[i]]
		local snap = creature:snapshot()
		local decision = creature.LastDecision
		if decision then
			snap.action = decision.action
			snap.channel = decision.channel
			snap.confidence = decision.confidence
			snap.evidenceAge = decision.evidenceAge
		end
		out[i] = snap
	end
	return { count = #self.order, creatures = out }
end

function CreatureService:stop(): ()
	self.running = false
	if self.Cadence then
		self.Cadence:unregister(self.frameSlot)
		self.Cadence:unregister(self.thinkSlot)
		self.Cadence:unregister(self.senseSlot)
	end
	self.frameSlot, self.thinkSlot, self.senseSlot = nil, nil, nil
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
	while #self.order > 0 do
		self:_despawnAt(#self.order)
	end
end

return CreatureService
