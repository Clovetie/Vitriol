--!strict
-- CreatureService.luau
-- Location: ServerStorage > Vitriol > Services > CreatureService  (ModuleScript)
-- Purpose:  Lifecycle and cadence owner for the single MVP Braid. It creates one
--           creature when a player has a character, feeds it last-known vibration
--           targets, steps the body on the shared CadenceService and exposes a
--           wound-only debug surface. There is no creature death path and no second
--           Heartbeat connection.
-- Requires: Config/GameConfig, Config/MonsterConfig, Lib/{Genetics,RNG,Fabrik,Noise},
--           Shared/{Skeleton,SkeletonCodec}, Creature/{CreatureCore,Body/*}
-- Used by:  Bootstrap, DebugHandler, Grapple/KillChoreography (later)

local CreatureCore = require(script.Parent.Parent.Creature.CreatureCore)
local TendrilRig = require(script.Parent.Parent.Creature.Body.TendrilRig)
local Locomotion = require(script.Parent.Parent.Creature.Body.Locomotion)

local CreatureService = {}
CreatureService.__index = CreatureService

local function nowOf(timeService: any): number
	if timeService then
		return timeService.elapsedTotal or 0
	end
	return 0
end

function CreatureService:init(services: any): ()
	self.Config = services.Config
	self.Monster = services.Monster
	self.Players = services.Players
	self.Workspace = services.Workspace
	self.Cadence = services.Cadence
	self.Time = services.Time
	self.Threat = services.Threat
	self.Health = services.Health
	self.Noise = services.Noise
	self.Remotes = services.Remotes
	self.Logger = services.Logger
	self.creatures = {}
	self.order = {}
	self.nextId = 0
	self.running = false
	self.connections = {}
	self.presentedDeaths = {}

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	self.Genetics = require(ReplicatedStorage.Vitriol.Lib.Genetics)
	self.RNG = require(ReplicatedStorage.Vitriol.Lib.RNG)
	self.Fabrik = require(ReplicatedStorage.Vitriol.Lib.Fabrik)
	self.Skeleton = require(ReplicatedStorage.Vitriol.Shared.Skeleton)
	self.SkeletonCodec = require(ReplicatedStorage.Vitriol.Shared.SkeletonCodec)
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
			BudgetMs = self.Config.Budgets.PerceptionMs,
			Run = function(dt)
				self:think(dt)
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

function CreatureService:_spawnPosition(): number, number, number
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

function CreatureService:_nearestTarget(creature: any): any, any, number
	local players = self.Players and self.Players:GetPlayers() or {}
	local best, bestPlayer, bestSq = nil, nil, math.huge
	local cx, cy, cz = creature:position()
	for i = 1, #players do
		local player = players[i]
		local healthState = self.Health and self.Health.states and self.Health.states[player.UserId]
		if healthState == nil or not healthState.dead then
			local root = self:_playerRoot(player)
			if root and root.Position then
				local dx = root.Position.X - cx
				local dy = root.Position.Y - cy
				local dz = root.Position.Z - cz
				local distanceSq = dx * dx + dy * dy + dz * dz
				if distanceSq < bestSq then
					best, bestPlayer, bestSq = root, player, distanceSq
				end
			end
		end
	end
	return best, bestPlayer, bestSq
end

function CreatureService:think(_dt: number): ()
	self:reconcile()
	local now = nowOf(self.Time)
	for i = 1, #self.order do
		local creature = self.creatures[self.order[i]]
		if creature and creature:isThreatening() then
			local root, player, distanceSq = self:_nearestTarget(creature)
			if root and root.Position then
				-- The source is written to the shared vibration field before the
				-- creature receives a last-known target. The full Senses/Memory layer
				-- will replace this nearest-player bridge; it is intentionally narrow
				-- and makes the prototype playable without giving the monster vision.
				if self.Noise then
					local velocity = root.AssemblyLinearVelocity
					local speed = velocity and velocity.Magnitude or 0
					self.Noise:emitAt("VIBRATION", root.Position.X, root.Position.Y, root.Position.Z, 0.18 + math.min(speed / 20, 0.6), now)
				end
				creature:setTarget(root.Position.X, root.Position.Y, root.Position.Z, 0.5)
				local kill = self.Monster.Kill or {}
				if player and self.Health and distanceSq <= (kill.GrabDistance or 5.5) ^ 2 then
					self.Health:beginCreatureKill(player, creature.Id)
				end
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
		out[i] = self.creatures[self.order[i]]:snapshot()
	end
	return { count = #self.order, creatures = out }
end

function CreatureService:stop(): ()
	self.running = false
	if self.Cadence then
		self.Cadence:unregister(self.frameSlot)
		self.Cadence:unregister(self.thinkSlot)
	end
	self.frameSlot, self.thinkSlot = nil, nil
	for _, connection in ipairs(self.connections) do
		connection:Disconnect()
	end
	self.connections = {}
	while #self.order > 0 do
		self:_despawnAt(#self.order)
	end
end

return CreatureService
