--!strict
-- CreatureService.luau
-- Location: ServerStorage > Vitriol > Services > CreatureService  (ModuleScript)
-- Purpose:  Lifecycle and cadence owner for the single MVP Braid. It binds the
--           authored Braid_1 when a player has a character, feeds last-known vibration
--           targets, steps the body on the shared CadenceService and exposes a
--           wound-only debug surface. There is no creature death path and no second
--           Heartbeat connection.
-- Requires: Config/GameConfig, Config/MonsterConfig, Lib/{Genetics,RNG,Fabrik,Noise},
--           Shared/{Skeleton,SkeletonCodec}, Creature/{CreatureCore,Body/*}
-- Used by:  Bootstrap, DebugHandler, Grapple/KillChoreography (later)

local CreatureCore = require(script.Parent.Parent.Creature.CreatureCore)
local TendrilRig = require(script.Parent.Parent.Creature.Body.TendrilRig)
local Locomotion = require(script.Parent.Parent.Creature.Body.Locomotion)
local GarageNavigation = require(script.Parent.Parent.Creature.GarageNavigation)
local ChurchNavigation = require(script.Parent.Parent.Creature.ChurchNavigation)
local HouseAccess = require(script.Parent.Parent.Creature.HouseAccess)
local InstinctSearch = require(script.Parent.Parent.Creature.Brain.InstinctSearch)
local GarageHabit = require(script.Parent.Parent.Creature.Brain.GarageHabit)
local ShadowPredictor = require(script.Parent.Parent.Creature.Brain.ShadowPredictor)

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
	self.Session = services.Session
	self.DayPrep = services.DayPrep
	self.Floodlight = services.Floodlight
	self.Barricade = services.Barricade
	self.Placement = services.Placement
	self.HouseCover = services.HouseCover
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
	self.lastCharacters = {}

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	self.Genetics = require(ReplicatedStorage.Vitriol.Lib.Genetics)
	self.RNG = require(ReplicatedStorage.Vitriol.Lib.RNG)
	self.Fabrik = require(ReplicatedStorage.Vitriol.Lib.Fabrik)
	self.Skeleton = require(ReplicatedStorage.Vitriol.Shared.Skeleton)
	self.SkeletonCodec = require(ReplicatedStorage.Vitriol.Shared.SkeletonCodec)
	self.Noise = services.Noise
	self.NoiseMotion = require(ReplicatedStorage.Vitriol.Lib.Noise).new(8191)

	local root = self.Workspace:FindFirstChild("Vitriol")
	local folder = root and root:FindFirstChild("Creatures")
	if folder == nil or not folder:IsA("Folder") then
		error("[Vitriol.Creature] missing authored Workspace.Vitriol.Creatures", 0)
	end
	self.Folder = folder
	-- Map v1's garage footprint is read once. No runtime Path or marker is made.
	local map = self.Workspace:FindFirstChild("Map")
	self.Structures = map and map:FindFirstChild("Structures")
	self.Navigation = GarageNavigation.new(map, self.Workspace)
	self.ChurchRoute = ChurchNavigation.new(map, self.Workspace)
	self.HouseAccess = HouseAccess.new(map)
	self.Search = InstinctSearch.new(self.Monster.InstinctSearch,map)
	self.GarageHabit = GarageHabit.new(self.Monster.Memory,self.Navigation,self.Monster.InstinctSearch)
	self.Shadow = ShadowPredictor.new(self.Monster.Prediction,map,
		require(ReplicatedStorage.Vitriol.Lib.MarkovPredictor))
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
				self.lastCharacters[player.UserId] = nil
				if self.GarageHabit then self.GarageHabit:forget(player.UserId) end
				if self.Shadow then self.Shadow:forget(player.UserId) end
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

function CreatureService:_spawnPosition(): (number, number, number)
	local players = self.Players and self.Players:GetPlayers() or {}
	local first = players[1]
	local root = self:_playerRoot(first)
	local spawn = self.Monster.Spawn
	if root and root.Position then
		return root.Position.X + spawn.DistanceFromPlayer, root.Position.Y + spawn.HeightOffset, root.Position.Z + spawn.DistanceFromPlayer
	end
	local map = self.Workspace:FindFirstChild("Map")
	local spawns = map and map:FindFirstChild("Spawns")
	local location = (spawns and spawns:FindFirstChild("Spawn_Garage"))
		or self.Workspace:FindFirstChild("SpawnLocation")
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
	-- Do not publish into an unhandled RemoteEvent: the authoritative Braid
	-- Parts already replicate. Enable only alongside a real client decoder.
	if self.Config.Features.SkeletonStreaming == true and buffer ~= nil and self.Remotes and self.Remotes.stream then
		replicator = require(script.Parent.Parent.Creature.Replicator).new(id, {
			Codec = self.SkeletonCodec,
			Config = self.Config,
			Remote = self.Remotes.stream,
		})
	end
	-- One authored slot for the current one-creature MVP; do not clone or create.
	local model = self.Folder:FindFirstChild("Braid_1")
	if model == nil then
		error("[Vitriol.Creature] missing authored Creatures.Braid_1", 0)
	end
	local creature = CreatureCore.new({
		Id = id,
		Model = model,
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
		Barricade = self.Barricade,
		Placement = self.Placement,
		HouseCover = self.HouseCover,
		HouseAccess = self.HouseAccess,
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
	-- Once the Braid has appeared, keep its authored model alive while a player
	-- remains connected. A victim's Character briefly disappears after death;
	-- despawning/hiding the entire monster at that moment looks like a broken rig.
	if self.Threat and (hasCharacter or (#players > 0 and #self.order > 0)) then
		desired = self.Threat:creatureCount()
	end
	local cap = self.Config.Session.MaxCreatures or desired
	if desired > cap then
		desired = cap
	end
	-- Never create an extra model if the content or config exceeds authored slots.
	while #self.order < desired do
		if #self.order >= 1 then
			error("[Vitriol.Creature] creature demand exceeds one authored Braid slot", 0)
		end
		self:_spawnOne()
	end
	while #self.order > desired do
		self:_despawnAt(#self.order)
	end
end

function CreatureService:_nearestTarget(creature: any): (any, any, number, boolean?, any?)
	local players = self.Players and self.Players:GetPlayers() or {}
	local best, bestPlayer, bestSq, bestClear, bestHit = nil, nil, math.huge, nil, nil
	local cx, cy, cz = creature:position()
	local senses = self.Monster and self.Monster.Senses or {}
	local sightSq = (senses.DirectSightStuds or 90) ^ 2
	local heatSq = (senses.ThermalStuds or 22) ^ 2
	local living = false
	for i = 1, #players do
		local player = players[i]
		local healthState = self.Health and self.Health.states and self.Health.states[player.UserId]
		if healthState == nil or not healthState.dead then
			living = true
			local root = self:_playerRoot(player)
			if root and root.Position then
				local dx = root.Position.X - cx
				local dy = root.Position.Y - cy
				local dz = root.Position.Z - cz
				local distanceSq = dx * dx + dy * dy + dz * dz
				if distanceSq < bestSq and distanceSq <= sightSq
					and (not self.HouseAccess or not self.HouseAccess:roofOccludes(cx,cy,cz,
						root.Position.X,root.Position.Y,root.Position.Z)) then
					-- At most one horizontal ray per candidate (four survivors max),
					-- already filtered against characters at Think cadence.
					local hit = self.Navigation and self.Navigation:hit(cx, cz,
						root.Position.X, root.Position.Z, creature.RaycastParams)
					local clear = hit == nil
					local wall = hit and (not self.Structures or not hit.Instance
						or hit.Instance:IsDescendantOf(self.Structures))
					-- Heat may register behind a small prop, NOT through a building
					-- wall or across the map. Clear eye-less sight reaches farther.
					if clear or (distanceSq <= heatSq and not wall) then
						best, bestPlayer, bestSq, bestClear, bestHit = root, player, distanceSq, clear, hit
					end
				end
			end
		end
	end
	if not living then creature.LastKnownAt = nil end
	return best, bestPlayer, bestSq, bestClear, bestHit
end

-- A deliberate two-second sabotage while physically beside the powered feed.
-- This shares the existing Think cadence, never adds a per-frame job or object.
function CreatureService:_attackLight(creature: any, kind: string?, position: any?, dt: number): ()
	if not kind or not position then
		creature.LightAttackKind, creature.LightAttackTime = nil, 0
		return
	end
	local dx, dz = creature.X-position.X, creature.Z-position.Z
	-- The elevated body trails planted tendrils. Damage comes from a reaching
	-- tip, not only an eight-stud core contact that can never be attained.
	local reach = math.clamp((creature.Stats and creature.Stats.TendrilReach) or 14, 8, 16)
	if dx*dx + dz*dz > reach*reach then
		creature.LightAttackKind, creature.LightAttackTime = nil, 0
		return
	end
	if kind == "GarageLight" and self.Navigation then
		local hit = self.Navigation:hit(creature.X, creature.Z, position.X, position.Z, creature.RaycastParams)
		-- The generator itself is a valid hit. A wall between monster and feed
		-- is not: being close on the other side must not count as contact.
		if hit and hit.Instance ~= self.DayPrep.Generator then
			creature.LightAttackKind, creature.LightAttackTime = nil, 0
			return
		end
	end
	if creature.LightAttackKind ~= kind then
		creature.LightAttackKind, creature.LightAttackTime = kind, 0
	end
	creature.LightAttackTime += math.min(math.max(dt, 0), .35)
	if creature.LightAttackTime < 2 then return end
	local broke = false
	if kind == "GarageLight" and self.DayPrep then broke = self.DayPrep:damageGarage()
	elseif kind == "StationLight" and self.Floodlight then broke = self.Floodlight:damage() end
	creature.LightAttackKind, creature.LightAttackTime = nil, 0
	if broke then creature:clearTarget() end
end

-- When no live clue wins, keep looking at Night. The bounded search policy
-- never reads an unsensed character's position and cannot damage furniture.
function CreatureService:_search(creature: any, now: number): ()
	local habit=self.GarageHabit
	local access=self.HouseAccess
	local house=access and access:groundHouse(creature.X,creature.Y,creature.Z)
	local clueAge=creature.SearchClueAt and now-creature.SearchClueAt or math.huge
	local noFreshClue=clueAge > ((self.Monster and self.Monster.InstinctSearch or {}).ClueSeconds or 25)
	-- groundHouse() stops at the doorway before the radius-expanded core has
	-- fully cleared BOTH pier faces. Keep the already physical-ray-tested
	-- outward leg for this short seam, without a new candidate ray or an
	-- early Garage/road redirect back through the authored wall.
	if access and not house and noFreshClue and creature.SearchMode=="transit"
		and creature.ExitSweepKind=="exit" and creature.ExitSweepGoalX
		and creature.TargetX==creature.ExitSweepGoalX
		and creature.TargetZ==creature.ExitSweepGoalZ then
		local radius=(creature.Stats and creature.Stats.CoreRadius) or 1.5
		for _,h in ipairs(access.Houses) do
			if h.Name==creature.ExitSweepHouse and creature.X>h.DoorX-0.75
				and creature.X<=h.PierEastX+radius+0.5
				and creature.Z>=h.DoorMinZ-radius-0.5
				and creature.Z<=h.DoorMaxZ+radius+0.5
				and creature.Y<h.RoofBottom-0.5 then
				if habit then habit:interrupt(creature) end
				local dx,dz=creature.X-(creature.ExitSweepProgressX or creature.X),
					creature.Z-(creature.ExitSweepProgressZ or creature.Z)
				if dx*dx+dz*dz>=1 then
					creature.ExitSweepProgressX,creature.ExitSweepProgressZ=creature.X,creature.Z
					creature.ExitSweepProgressAt=now
				elseif now-(creature.ExitSweepProgressAt or now)>=3 then
					access:resetExitSweep(creature)
					-- This core is still inside the pier's expanded band: do not
					-- reselect a Garage ray pointing back through that wall tonight.
					-- Evidence stays intact and may be reconsidered next Night.
					if habit then
						creature.HabitNight,creature.HabitState=(self.Time and self.Time.nightIndex) or 0,"blocked"
					end
					creature.SearchMode,creature.SearchIndex="patrol",1
					creature.SearchGoalX,creature.SearchGoalZ=nil,nil
					creature.SearchAnchorX,creature.SearchAnchorY,creature.SearchAnchorZ=creature.X,creature.Y,creature.Z
					creature:clearTarget()
					creature.DecisionReason="blocked-house-exit"
					return
				end
				local low=math.min(h.LintelBottom,h.PorchBottom)-radius-1.5
				creature:setTarget(creature.ExitSweepGoalX,math.min(creature.Y,low),creature.ExitSweepGoalZ,0.2)
				creature.DecisionReason="physical-house-exit"
				return
			end
		end
	end
	if access and creature.ExitSweepHouse and (not house or creature.SearchMode~="transit" or not noFreshClue) then
		access:resetExitSweep(creature)
	end
	-- A witnessed Garage preference cannot pull an indoor core through a
	-- house wall or skip the lower-first doorway sweep. Even while finishing
	-- its one local patrol circuit, keep the old habit but suspend its route;
	-- it will spend one FRESH physical safety ray only after egress.
	if house and noFreshClue and habit then habit:interrupt(creature) end
	if house and creature.SearchMode=="transit" and noFreshClue then
		local ex,ey,ez,status=access:sweepExit(creature,now,self.Navigation,self.HouseCover)
		if ex then
			creature:setTarget(ex,ey,ez,0.2)
			creature.DecisionReason=status
			return
		elseif status=="scanning" then
			creature:clearTarget() -- defer the next spoke to the NEXT budgeted Think
			creature.DecisionReason="scanning-house-exit"
			return
		elseif status=="blocked" then
			-- No body-width-safe doorway ray: hunt locally for another full
			-- circuit, not through the user's installed closet/table or wall.
			creature.SearchMode,creature.SearchIndex="patrol",1
			creature.SearchGoalX,creature.SearchGoalZ=nil,nil
			creature.SearchAnchorX,creature.SearchAnchorY,creature.SearchAnchorZ=creature.X,creature.Y,creature.Z
			creature:clearTarget()
			creature.DecisionReason="blocked-house-exit"
			return
		end
	end
	if habit and not (house and noFreshClue) then
		local hx,hz,why=habit:lead(creature,now,(self.Time and self.Time.nightIndex) or 0,
			self.Navigation,self.HouseCover)
		if hx then
			creature:setTarget(hx,creature.Y,hz,0.2)
			creature.DecisionReason=why
			local night=(self.Time and self.Time.nightIndex) or 0
			if creature.GarageExplainNight ~= night then
				creature.GarageExplainNight=night
				creature.GarageExplainEvent="lead" -- emit AFTER Think is timed
			end
			return
		end
		if why == "blocked" then
			-- A failed habit ray must not be followed by two patrol rays in the
			-- SAME budgeted Think. Resume the safe local search next Think.
			creature:clearTarget()
			creature.DecisionReason="blocked-garage-approach"
			return
		end
		if why == "arrived" then self.Search:reset(creature) end
	end
	local tx,ty,tz=self.Search:next(creature,now,self.Navigation,self.HouseCover)
	if house and creature.SearchMode=="transit" and noFreshClue then
		-- The last local patrol leg JUST completed. Its road candidate has
		-- already spent its ray(s); start the circular exit fan NEXT Think.
		creature.SearchGoalX,creature.SearchGoalZ=nil,nil
		creature:clearTarget()
		creature.DecisionReason="house-exit-scan-pending"
		return
	end
	if tx then creature:setTarget(tx,ty,tz,0.2)
	else creature:clearTarget() end -- no safe ray: don't phase through a wall
	creature.DecisionReason=creature.SearchMode == "sweep" and "genuine-clue-sweep"
		or creature.SearchMode == "transit" and "road-region-patrol" or "bounded-local-patrol"
end

-- WP6 first instinct-only step: investigate an emitted, nearby vibration,
-- NEVER a hidden player's current root. Fresh prey, authored decoys and
-- unexpired LAST-OBSERVED prey still take precedence in think(). Coarsen the
-- event to an eight-stud cell so hearing does not become precise visual GPS.
function CreatureService:_investigateNoise(creature: any, now: number): boolean
	local field = self.Noise
	if not field or not field.strongestNearby then return false end
	local senses = (self.Monster and self.Monster.Senses) or {}
	local threshold = (senses.Threshold and senses.Threshold.VIBRATION) or 0.1
	local id, sx, sy, sz = field:strongestNearby("VIBRATION", creature.X, creature.Y, creature.Z,
		senses.NoiseInvestigationStuds or 32, now, threshold, creature.NoiseInvestigatedId)
	if not id then return false end
	local dx,dz=sx-creature.X,sz-creature.Z
	local stop=senses.NoiseInvestigationStopStuds or 7
	if dx*dx+dz*dz <= stop*stop then
		if creature.SearchNoiseId ~= id then
			creature.SearchNoiseId=id
			self.Search:note(creature,sx,sy,sz,now)
		end
		creature.NoiseInvestigatedId=id
		return false -- arrived; sweep nearby instead of circling a dying echo
	end
	local cell=(self.Monster and self.Monster.Memory and self.Monster.Memory.CellSize) or 8
	local tx=math.floor(sx/cell+0.5)*cell
	local tz=math.floor(sz/cell+0.5)*cell
	-- This first slice investigates only an accessible noise lane; no wall
	-- phasing or untested house/garage navigation is justified by sound alone.
	if self.Navigation and not self.Navigation:clear(creature.X,creature.Z,tx,tz,creature.RaycastParams) then
		creature.NoiseInvestigatedId=id
		return false
	end
	if creature.SearchNoiseId ~= id then
		creature.SearchNoiseId=id
		self.Search:note(creature,tx,sy,tz,now)
	end
	creature:setTarget(tx,sy,tz,0.25)
	return true
end

-- One bounded diagnostic per sustained pursuit/lure stall. The Braid has
-- stopped far short of station/garage and church in Play; exact core/foot/
-- route state is required before changing the approved planted-foot gait.
function CreatureService:_probeLure(creature: any, kind: string, lure: any, now: number): ()
	if creature.LureProbeKind ~= kind then
		creature.LureProbeKind, creature.LureProbeAt = kind, now
		creature.LureProbeX, creature.LureProbeZ = creature.X, creature.Z
		creature.LureProbeLoggedAt = nil
		return
	end
	if now - (creature.LureProbeAt or now) < 2.5 then return end
	local mx, mz = creature.X-(creature.LureProbeX or creature.X), creature.Z-(creature.LureProbeZ or creature.Z)
	local dx, dz = creature.X-lure.X, creature.Z-lure.Z
	local minDistance = kind == "Prey" and 6 or 18
	local stopped = mx*mx+mz*mz < 1 and dx*dx+dz*dz > minDistance*minDistance
	if stopped and (not creature.LureProbeLoggedAt or now-creature.LureProbeLoggedAt >= 8) then
		creature.LureProbeLoggedAt = now
		local obstacle = self.Navigation and self.Navigation:hit(creature.X, creature.Z,
			lure.X, lure.Z, creature.RaycastParams)
		local hit = obstacle and obstacle.Instance
		if self.Logger then self.Logger("warn", string.format(
			"pursuit stall %s core(%.1f,%.1f) goal(%.1f,%.1f) nav(%.1f,%.1f) feet=%d block=%s",
			kind, creature.X, creature.Z, lure.X, lure.Z,
			creature.TargetX or 0, creature.TargetZ or 0,
			creature.Locomotion:anchors(), hit and hit:GetFullName() or "none")) end
	end
	creature.LureProbeAt, creature.LureProbeX, creature.LureProbeZ = now, creature.X, creature.Z
end

function CreatureService:think(_dt: number): ()
	self:reconcile()
	local players = self.Players and self.Players:GetPlayers() or {}
	for i = 1, #players do
		local player = players[i]
		local character = player.Character
		if character ~= nil and self.lastCharacters[player.UserId] ~= character then
			self.lastCharacters[player.UserId] = character
			self.presentedDeaths[player.UserId] = nil -- a new life deserves its own camera event
		end
	end
	local now = nowOf(self.Time)
	local phase = self.Time and self.Time.phase or "Night"
	local runLive = self.Session == nil or self.Session.state ~= "Ended"
	local sensedUserId=nil
	for i = 1, #self.order do
		local creature = self.creatures[self.order[i]]
		if creature then
			-- The same authored Braid withdraws at dawn, reappears during dusk,
			-- and hunts only at night. A kill already underway may finish at dawn.
			local finishing = creature.AttackPhase == "EAT" or creature.AttackPhase == "RECOVER"
			creature:setDormant(not runLive or ((phase == "Dawn" or phase == "Day") and not finishing))
			if phase ~= "Night" and not finishing then
				creature.DecisionReason="day-dawn-withdrawal"
				creature:clearTarget()
				creature.LightAttackKind, creature.LightAttackTime = nil, 0
			end
		end
		if creature and not creature.Dormant and runLive and phase == "Night" and creature:isThreatening() then
			creature:excludeCharacters(players)
			local root, player, distanceSq, sensedClear, sensedHit = self:_nearestTarget(creature)
			creature.CoverPreyX, creature.CoverPreyZ = nil, nil
			creature.CoverExitIntent, creature.CoverIngressIntent = false, false
			if root and root.Position then
				if self.GarageHabit then self.GarageHabit:interrupt(creature) end
				if player then
					sensedUserId=player.UserId
					if self.Shadow then
						self.Shadow:observe(player.UserId,root.Position.X,root.Position.Y,root.Position.Z,now)
					end
				end
				creature.LastKnownPosition, creature.LastKnownAt = root.Position, now
				self.Search:note(creature,root.Position.X,root.Position.Y,root.Position.Z,now)
				-- Count ONLY a genuinely sensed outside→inside transition; do not
				-- inspect a hidden player's root for a visit, even at Garage.
				if self.GarageHabit and player then
					local previousEvidence=self.GarageHabit.Evidence
					local witnessed=self.GarageHabit:observe(player.UserId,root.Position.X,root.Position.Y,root.Position.Z)
					local threshold=(self.GarageHabit.Config and self.GarageHabit.Config.GarageVisitsForPrediction) or 3
					local night=(self.Time and self.Time.nightIndex) or 0
					if witnessed and previousEvidence < threshold and self.GarageHabit.Evidence >= threshold
						and creature.GarageWitnessExplainNight ~= night then
						creature.GarageWitnessExplainNight=night
						creature.GarageExplainEvent="witness-threshold" -- no player ID/coords; Output after timing
					end
					if witnessed and (creature.HabitState == "front" or creature.HabitState == "inside"
						or creature.HabitState == "pending" or creature.HabitState == "pendingInside") then
						-- The prediction has actual visual evidence; don't call its
						-- later arrival a miss or re-seek after this fresh clue fades.
						creature.HabitState="arrived"
					end
				end
			end
			if root and root.Position and self.Noise then
				-- Existing nearest-player noise bridge; never invent prey.
				local velocity = root.AssemblyLinearVelocity
				local speed = velocity and velocity.Magnitude or 0
				self.Noise:emitAt("VIBRATION", root.Position.X, root.Position.Y, root.Position.Z,
					0.18 + math.min(speed / 20, 0.6), now)
			end
			local roofHouse,escapeX,escapeY,escapeZ = nil,nil,nil,nil
			if self.HouseAccess then
				roofHouse,escapeX,escapeY,escapeZ = self.HouseAccess:escape(creature.X,creature.Y,creature.Z,
					(creature.Stats and creature.Stats.CoreRadius) or 1.5)
			end
			-- A grounded player beneath the solid roof needs an exterior
			-- descent first. Roof-level prey retains the approved high-prey chase.
			local roofPrey = roofHouse and root and root.Position
				and root.Position.Y >= roofHouse.RoofBottom-1
			local recover = escapeX ~= nil and not roofPrey
			creature.HouseRecovery = recover
			if creature.AttackPhase == nil then
				-- Bell > lit garage > station. A close living player always wins.
				-- One bell ring needs only ONE investigation; never stand frozen at
				-- its fixed source until the twelve-second ring times out.
				local checkedBell = false
				if self.DayPrep and self.DayPrep.bellRinging and self.DayPrep.bellStarted then
					local bell = self.DayPrep.BellLever.Position
					local bx, bz = creature.X-bell.X, creature.Z-bell.Z
					if bx*bx+bz*bz <= 12*12 then
						creature.BellInvestigatedAt = self.DayPrep.bellStarted
					end
					checkedBell = creature.BellInvestigatedAt == self.DayPrep.bellStarted
				end
				local lure, preyPriority, lightKind = nil, 70, nil
				if self.DayPrep then lure, preyPriority, lightKind = self.DayPrep:signal(checkedBell) end
				if not lure and self.Floodlight then
					lure, preyPriority, lightKind = self.Floodlight:signal()
				end
				local priorityRadius = preyPriority or 70
				-- A lure or hidden player's live coordinates cannot keep the
				-- Braid stranded on a solid roof after prey has disappeared.
				if recover then
					if self.GarageHabit then self.GarageHabit:interrupt(creature) end
					creature.DecisionReason="solid-roof-recovery"
					creature:setTarget(escapeX,escapeY,escapeZ,0.5)
					self:_attackLight(creature,nil,nil,_dt)
				elseif lure and distanceSq > priorityRadius * priorityRadius then
					if self.GarageHabit then self.GarageHabit:interrupt(creature) end
					creature.DecisionReason=lightKind or "authored-bell-lure"
					local tx, tz = lure.X, lure.Z
					if not lightKind and self.ChurchRoute then
						-- Bell lever sits inside the user's solid church union. Visit the
						-- real front opening rather than pulling straight into its west wall.
						tx, tz = self.ChurchRoute:route(creature.X, creature.Z, tx, tz,
							creature.RaycastParams, self.DayPrep.BellModel)
					elseif (lightKind == "GarageLight" or lightKind == "StationLight") and self.Navigation then
						-- Either powered light can be on the far side of the garage wall.
						-- Only the garage's queryable generator needs endpoint allowance.
						local endpoint = lightKind == "GarageLight" and self.DayPrep.Generator or nil
						local hit = self.Navigation:hit(creature.X, creature.Z, tx, tz, creature.RaycastParams)
						if hit and hit.Instance ~= endpoint then
							-- Reuse this exact obstruction in the detour; no duplicate
							-- initial ray before its bounded node-clearance fan.
							tx, tz = self.Navigation:route(creature.X, creature.Z, tx, tz,
								creature.RaycastParams, now, endpoint, hit)
						end
					end
					if tx then
						creature:setTarget(tx, lure.Y, tz, 0.4)
						creature.CoverExitIntent = true -- only a physical inside→outside encounter may break cover
					else creature:clearTarget() end -- no through-wall sabotage path
					self:_probeLure(creature, lightKind or "Bell", lure, now)
					self:_attackLight(creature, lightKind, lure, _dt)
				elseif root and root.Position then
					creature.DecisionReason="genuinely-sensed-prey"
					-- Only genuinely sensed, living prey can prompt furniture damage.
					-- Do not follow a hidden player's live root from last-known/lures.
					creature.CoverPreyX, creature.CoverPreyZ = root.Position.X, root.Position.Z
					self:_attackLight(creature, nil, nil, _dt)
					local navigation = self.Navigation
					-- _nearestTarget already ray-checked THIS living root from THIS
					-- core in this non-yielding Think. Reuse its clear/thermal result
					-- instead of shooting the identical segment a second time.
					-- An injected/legacy sensor that returns no fourth value still
					-- takes the original safety ray and cannot grant visibility.
					local visible = true
					if navigation then
						if sensedClear == nil then
							visible = navigation:clear(creature.X, creature.Z,
								root.Position.X, root.Position.Z, creature.RaycastParams)
						else visible = sensedClear end
					end
					local routeX, routeY, routeZ = root.Position.X, root.Position.Y, root.Position.Z
					-- Grounded prey behind the authored garage wall must be reached
					-- around a corner; high unreachable prey keeps its approved response.
					if navigation and not visible and root.Position.Y < 8 then
						-- Only an actual selected prey sensor HIT can skip the
						-- detour's duplicate start ray; nil rechecks physically.
						routeX, routeZ = navigation:route(creature.X, creature.Z,
							root.Position.X, root.Position.Z, creature.RaycastParams, now, nil, sensedHit)
					end
					if routeX ~= nil and self.HouseAccess then
						local hx,hy,hz = self.HouseAccess:route(creature.X,creature.Y,creature.Z,
							root.Position.X,root.Position.Y,root.Position.Z,
							(creature.Stats and creature.Stats.CoreRadius) or 1.5)
						if hx then
							routeX,routeY,routeZ=hx,hy,hz
							if navigation and not navigation:clear(creature.X,creature.Z,hx,hz,creature.RaycastParams) then
								-- Preserve the proven garage detour if the Braid approaches
								-- a house from the opposite side of that garage wall.
								local gx,gz=navigation:route(creature.X,creature.Z,hx,hz,creature.RaycastParams,now)
								routeX,routeZ=gx,gz
							end
						end
					end
					if routeX ~= nil then
						creature:setTarget(routeX, routeY, routeZ, 0.5)
					else
						creature:clearTarget() -- no safe way around: don't pound the wall
					end
					local barricadeBetween = self.Barricade and self.Barricade.boarded
						and self.Barricade:crossing(creature.X, creature.Z, root.Position.X, root.Position.Z)
					local placedBetween = self.Placement and self.Placement.Active[1] ~= nil
						and self.Placement:intercept(creature.X, creature.Z, root.Position.X, root.Position.Z)
					local coverBetween = self.HouseCover and self.HouseCover.activeCount > 0
						and self.HouseCover:intercept(creature.X, creature.Z, root.Position.X, root.Position.Z)
					if visible and not barricadeBetween and not placedBetween and not coverBetween and player and self.Health
						and creature:canPrepareChomp(root.Position.X, root.Position.Y, root.Position.Z) then
						creature:prepareChomp(player, root.Position.X, root.Position.Y, root.Position.Z)
					end
					self:_probeLure(creature, "Prey", root.Position, now)
				elseif creature.LastKnownAt and creature.LastKnownPosition
					and now - creature.LastKnownAt < ((self.Monster and self.Monster.Senses or {}).LastKnownSeconds or 8) then
					if self.GarageHabit then self.GarageHabit:interrupt(creature) end
					creature.DecisionReason="last-genuinely-observed-location"
					self:_attackLight(creature, nil, nil, _dt)
					local memory = creature.LastKnownPosition -- value captured when actually sensed
					local dx,dz=memory.X-creature.X,memory.Z-creature.Z
					local clueReached = dx*dx+dz*dz <= 7*7
					-- Horizontal proximity does NOT mean the last-seen indoor spot
					-- was reached if an ORIGINAL installed furniture piece still
					-- separates the core from that stored spot. Keep the SAME
					-- time-bounded genuine memory only while its physical crossing
					-- is blocked; expiry still cancels the pressure. No live root.
					if clueReached and self.HouseCover and self.HouseCover.activeCount > 0
						and self.HouseCover:intercept(creature.X, creature.Z, memory.X, memory.Z) then
						clueReached = false
					end
					if clueReached then
						creature.LastKnownAt = nil -- reached search spot; no live wallhack
						self:_search(creature,now) -- sweep the real clue, then patrol
					else
						local tx,ty,tz=memory.X,memory.Y,memory.Z
						local rememberedInsideHouse = false
						-- A genuinely LAST-SEEN position inside a house still needs
						-- the same authored doorway/roof staging as sensed prey. A
						-- ground-height clear ray alone cannot lower an elevated core
						-- beneath the porch or justify a direct pull through cover.
						-- This uses stored evidence, never a hidden player's live root.
						if self.HouseAccess then
							local hx,hy,hz=self.HouseAccess:route(creature.X,creature.Y,creature.Z,
								tx,ty,tz,(creature.Stats and creature.Stats.CoreRadius) or 1.5)
							if hx then
								tx,ty,tz=hx,hy,hz
								rememberedInsideHouse = true -- route exists ONLY for a genuine indoor memory
							end
						end
						if self.Navigation and not self.Navigation:clear(creature.X,creature.Z,tx,tz,creature.RaycastParams) then
							tx,tz=self.Navigation:route(creature.X,creature.Z,tx,tz,creature.RaycastParams,now)
						end
						if tx then
							creature:setTarget(tx,ty,tz,0.2)
							creature.CoverExitIntent = true -- last OBSERVED position, never a live hidden-player feed
							creature.CoverIngressIntent = rememberedInsideHouse -- only near real cover on the doorway route
						else creature:clearTarget() end
						self:_probeLure(creature,"LastKnown",memory,now)
					end
				else
					creature.LureProbeKind = nil
					self:_attackLight(creature, nil, nil, _dt)
					if not self:_investigateNoise(creature,now) then
						self:_search(creature,now) -- no clue: still hunting on a bounded route
					else
						if self.GarageHabit then self.GarageHabit:interrupt(creature) end
						creature.DecisionReason="real-local-vibration"
					end
				end
			else
				creature.LureProbeKind = nil
				self:_attackLight(creature, nil, nil, _dt)
			end
			if creature.AttackPhase ~= nil and creature.AttackPhase ~= "EAT" and creature.AttackPhase ~= "RECOVER" then
				local victim = creature.AttackPlayer
				local victimState = victim and self.Health and self.Health.states and self.Health.states[victim.UserId]
				local victimRoot = victim and self:_playerRoot(victim)
				if victim == nil or (victimState and victimState.dead) or victimRoot == nil or victimRoot.Position == nil then
					creature:abortChomp()
				elseif creature.AttackPhase == "CROUCH" then
					creature:updateChompTarget(victimRoot.Position.X, victimRoot.Position.Y, victimRoot.Position.Z)
				end
			end
		end
	end
	if self.Shadow then self.Shadow:markUnseenExcept(sensedUserId) end
	if self.GarageHabit then self.GarageHabit:markUnseenExcept(sensedUserId) end
end

function CreatureService:step(dt: number): ()
	for i = 1, #self.order do
		local id = self.order[i]
		local creature = self.creatures[id]
		if creature then
			local ok, err = pcall(function()
				creature:step(dt)
				-- Contact is checked on the FRAME after the actual lowered charge,
				-- never by the high standing core or a stale think-cadence distance.
				if not creature.Dormant and (self.Time == nil or self.Time.phase == "Night")
					and creature.AttackPhase == "CHARGE" and creature.AttackPlayer and self.Health then
					local player = creature.AttackPlayer
					local root = self:_playerRoot(player)
					if root and root.Position then
						local x, y, z = creature:position()
						local dx, dy, dz = root.Position.X - x, root.Position.Y - y, root.Position.Z - z
						local kill = self.Monster.Kill or {}
						if dx * dx + dy * dy + dz * dz <= (kill.ChompDistance or 3.3) ^ 2
							and (not self.Navigation or self.Navigation:clear(x, z,
								root.Position.X, root.Position.Z, creature.RaycastParams))
							-- The table is below the horizontal perception ray, but still
							-- covers a low chomp: don't kill through the original furniture.
							and (not self.HouseCover or self.HouseCover.activeCount == 0
								or not self.HouseCover:intercept(x, z, root.Position.X, root.Position.Z))
							and self.Health:beginCreatureKill(player, creature.Id) then
							creature:chompLanded()
						end
					end
				end
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

-- Server-only AIDebugDump. Never expose a live target through RF_DebugQuery:
-- survivors must not learn the Braid's private route from a public remote.
-- Allocations occur only on a deliberate diagnostic read, never per Think.
function CreatureService:aiDump(): any
	local out={phase=self.Time and self.Time.phase or "Unknown",
		garage=self.GarageHabit and self.GarageHabit:dump() or nil,
		shadowPrediction=self.Shadow and self.Shadow:dump() or nil,
		priority="roof recovery > active authored lure if sensed prey is outside lure priority radius > sensed living prey > bounded last-observed location > emitted nearby noise > recent genuine clue sweep > witnessed Garage habit > road/local patrol",
		creatures={}}
	local now=nowOf(self.Time)
	for i=1,#self.order do
		local c=self.creatures[self.order[i]]
		if c then
			out.creatures[#out.creatures+1]={id=c.Id,
				reason=c.AttackPhase and ("attack-"..c.AttackPhase) or c.DecisionReason or "not-yet-decided",
				x=c.X,z=c.Z,goalX=c.TargetX,goalZ=c.TargetZ,
				searchMode=c.SearchMode,habitState=c.HabitState,
				lastClueAge=c.SearchClueAt and math.max(0,now-c.SearchClueAt) or nil,
				dormant=c.Dormant}
		end
	end
	return out
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
