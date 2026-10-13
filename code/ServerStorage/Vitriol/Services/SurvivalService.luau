--!strict
-- LOCAL-ONLY M6 server ownership adapter. NOT required/started by Bootstrap.
-- No Cadence registration, remote, health write, Instance construction or
-- client-supplied activity. Integration must supply server-verified samplers
-- and an explicitly budgeted tick; this module does not create either.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SurvivalModel = require(ReplicatedStorage.Vitriol.Shared.SurvivalModel)
local SurvivalCollapse = require(ReplicatedStorage.Vitriol.Shared.SurvivalCollapse)
local SurvivalConsumeAction = require(ReplicatedStorage.Vitriol.Shared.SurvivalConsumeAction)
local SurvivalService = {}
SurvivalService.__index = SurvivalService

local function finite(value: any): boolean
	return type(value)=="number" and value==value and value>-math.huge and value<math.huge
end

-- Requires explicit server-only activity/environment samplers. They MUST NOT
-- take their answers from a client Remote or an unverified client attribute.
-- Environment may report hot/cold/immersed; bleeding and HP are ALWAYS
-- sourced from HealthService's server-owned ledger, not the sampler.
function SurvivalService:init(services: any): ()
	assert(services and services.Players and services.Health and services.Survival
		and type(services.ResolveActivity)=="function"
		and type(services.ResolveEnvironment)=="function",
		"[Vitriol.Survival] explicit server samplers and Health required")
	self.Players=services.Players
	self.Health=services.Health
	self.Config=services.Survival
	self.ResolveActivity=services.ResolveActivity
	self.ResolveEnvironment=services.ResolveEnvironment
	-- Optional until the guarded live wiring: actual NoiseField + server Time.
	self.Noise=services.Noise
	self.Time=services.Time
	-- Optional until a real server InventoryService exists. Never accept a
	-- client-supplied "owned" flag, sickness roll or interruption verdict.
	self.Inventory=services.Inventory
	self.CanConsume=services.CanConsume
	self.RollSick=services.RollSick
	self.models={} -- run-local UserId -> {model, player, conditions}; not a DataStore
end

local function connected(self: any,player: any): boolean
	if not player then return false end
	for _,present in ipairs(self.Players:GetPlayers()) do
		if present==player then return true end
	end
	return false
end

local function eligible(self: any,player: any): any
	local id=player and player.UserId
	local h=id and self.Health.states[id]
	if not h or h.player~=player or h.dead or h.permadead or h.awaitingDawn
		or not h.humanoid or not finite(h.humanoid.Health) or h.humanoid.Health<=0 then
		return nil
	end
	return h
end

local function bodyPosition(h: any,player: any): any?
	if not h or not h.character or h.character~=player.Character then return nil end
	local p=h.root and h.root.Position
	if not p or not finite(p.X) or not finite(p.Y) or not finite(p.Z) then return nil end
	return p
end

local function consumptionWired(self: any): boolean
	return self.Inventory and type(self.Inventory.hasOwned)=="function"
		and type(self.Inventory.consumeOwned)=="function"
		and type(self.CanConsume)=="function" and type(self.RollSick)=="function"
		and self.Noise and type(self.Noise.emitAt)=="function"
		and self.Time and finite(self.Time.elapsedTotal) or false
end

local function canConsume(self: any,player: any,h: any,item: string): boolean
	local ok,allowed=pcall(self.CanConsume,player,h,item)
	if not ok or allowed~=true then return false end
	local owns,has=pcall(self.Inventory.hasOwned,self.Inventory,player,item)
	return owns and has==true
end

function SurvivalService:_entry(player: any): any
	local id=player.UserId
	local entry=self.models[id]
	if not entry then
		entry={model=SurvivalModel.new(self.Config),
			collapse=SurvivalCollapse.new(self.Config.Collapse),
			consume=SurvivalConsumeAction.new(self.Config),
			player=player,conditions={}}
		self.models[id]=entry
	else
		entry.player=player -- same run ledger survives disconnect/rejoin
	end
	return entry
end

-- A future Bootstrap may call this when a legitimate player joins; never
-- allocate a ledger for a stale/forged Player object outside Players.
function SurvivalService:observe(player: any): any?
	if not player or not finite(player.UserId) or not connected(self,player) then return nil end
	return self:_entry(player)
end

function SurvivalService:detach(player: any): ()
	local id=player and player.UserId
	local entry=id and self.models[id]
	if entry and entry.player==player then
		entry.player=nil -- preserve run-local meters, not a free reconnect refill
		entry.conditions={}
		entry.consume:cancel()
		entry.consumeCharacter=nil
		entry.pendingAir=nil -- no delayed eating noise at another body
		entry.collapseCharacter=nil
		-- The physical body is gone. Never replay its pending fall at a new
		-- character's position after reconnect; do not erase collapse state.
		entry.collapse:cancelPendingFall()
		self.Health:metersAllowRegen(id,false)
	end
end

-- A successful need commit may have to retry a rejected AIR insertion. Keep a
-- single event at its ACTUAL action-completion point/time; block another item
-- until it is inserted, so retries cannot grow an unbounded noise queue.
function SurvivalService:_flushAir(entry: any,player: any,h: any): boolean
	local pending=entry.pendingAir
	if not pending then return true end
	if not h or pending.character~=h.character or h.character~=player.Character then
		entry.pendingAir=nil -- no ghost chewing at a new body
		return false
	end
	if not self.Noise or type(self.Noise.emitAt)~="function" then return false end
	local id=self.Noise:emitAt("AIR",pending.x,pending.y,pending.z,
		pending.intensity,pending.time)
	if not id then return false end
	entry.pendingAir=nil
	return true
end

-- Explicit SERVER action seam only: no InventoryService exists in the running
-- game and no client intent reaches this. An injected authority must validate
-- ownership and interruption throughout; absent dependencies fail CLOSED.
function SurvivalService:beginConsumption(player: any,item: string): (boolean,string?)
	if not consumptionWired(self) then return false,"unwired" end
	if not connected(self,player) then return false,"ineligible" end
	local h=eligible(self,player)
	local entry=h and self.models[player.UserId]
	if not entry or entry.player~=player or not bodyPosition(h,player)
		or entry.pendingAir then return false,"ineligible" end
	if entry.consume.phase~="Idle" then return false,"busy" end
	if not canConsume(self,player,h,item) then return false,"not-owned-or-interrupted" end
	local started,err=entry.consume:begin(item,true)
	if started then entry.consumeCharacter=h.character end
	return started,err
end

function SurvivalService:advanceConsumption(player: any,dt: number): (any?,string?)
	local entry=player and self.models[player.UserId]
	if not entry or entry.player~=player or entry.consume.phase=="Idle" then
		return nil,"idle"
	end
	if not finite(dt) or dt<0 or dt>5 then return nil,"invalid-dt" end
	local h=connected(self,player) and eligible(self,player)
	if not h or entry.consumeCharacter~=h.character or not bodyPosition(h,player)
		or not consumptionWired(self)
		or not canConsume(self,player,h,entry.consume.item) then
		entry.consume:cancel();entry.consumeCharacter=nil
		return nil,"interrupted"
	end
	return entry.consume:advance(dt,true)
end

-- Inventory.consumeOwned must be a synchronous, atomic, server-only claim:
-- true ONLY after precisely one item has been removed. Model preflight checks
-- Sick roll BEFORE the claim. Then capture a real body AIR event; failed
-- insertion stays pending for a bounded retry, never reclaims/duplicates food.
function SurvivalService:commitConsumption(player: any): (any?,string?)
	local entry=player and self.models[player.UserId]
	if not entry or entry.player~=player or entry.consume.phase~="Ready" then
		return nil,"not-ready"
	end
	local h=connected(self,player) and eligible(self,player)
	local p=h and bodyPosition(h,player)
	local item=entry.consume.item
	if not p or entry.consumeCharacter~=h.character or not consumptionWired(self)
		or not canConsume(self,player,h,item) then
		entry.consume:cancel();entry.consumeCharacter=nil
		return nil,"interrupted"
	end
	-- Freeze the actual completion point/time BEFORE calling Inventory. A
	-- callback is required not to yield, but it still must not move the noise
	-- to a later or hidden player position if it mutates other server state.
	local px,py,pz=p.X,p.Y,p.Z
	local completedAt=self.Time.elapsedTotal
	local body=h.character
	local definition=self.Config.Consumables[item]
	local roll=nil
	if definition and (definition.sickChance or 0)>0 then
		local ok,value=pcall(self.RollSick,player,item)
		if not ok then entry.consume:cancel();entry.consumeCharacter=nil;return nil,"invalid-roll" end
		roll=value -- model preflight rejects non-finite/client-forged values
	end
	local result,err=entry.consume:commit(entry.model,roll,function(ownedItem)
		return self.Inventory:consumeOwned(player,ownedItem)
	end)
	entry.consumeCharacter=nil
	if not result then return nil,err end
	if result.noiseAir>0 then
		entry.pendingAir={character=body,x=px,y=py,z=pz,
			intensity=result.noiseAir,time=completedAt}
		self:_flushAir(entry,player,h)
	end
	local threshold=self.Config.Coupling.Threshold
	self.Health:metersAllowRegen(player.UserId,
		result.thirst<threshold and result.hunger<threshold)
	return result,nil
end

-- Explicitly called by a future budgeted server tick. Does not run by itself.
-- Return number of advanced live players and rejected samplers. Invalid dt
-- rejects the whole call before any player is touched. A source bug (invalid
-- activity/environment) fails that player's regen flag closed, not its meters.
function SurvivalService:pulse(dt: number): (number?,string?)
	if not finite(dt) or dt<0 or dt>5 then return nil,"invalid-dt" end
	local advanced,rejected=0,0
	for _,player in ipairs(self.Players:GetPlayers()) do
		local h=eligible(self,player)
		if h then
			local entry=self:_entry(player)
			if entry.pendingAir then self:_flushAir(entry,player,h) end
			if entry.consume.phase~="Idle" then self:advanceConsumption(player,dt) end
			-- Existing onset progresses with REAL server dt even if an activity
			-- sampler fails. A replacement character can never inherit its fall.
			if entry.collapse.phase~="Idle" and entry.collapseCharacter==h.character
				and h.character==player.Character then
				entry.collapse:advance(dt)
				if entry.collapse.fallPending and self.Noise and self.Time then
					self:emitPendingFall(player)
				end
			end
			local activity=self.ResolveActivity(player,h)
			local env=self.ResolveEnvironment(player,h)
			if type(env)~="table" then
				rejected=rejected+1
				self.Health:metersAllowRegen(player.UserId,false)
			else
				local conditions={
					bleeding=(h.bleedRate or 0)>0,
					health=h.humanoid.Health,
					hot=env.hot==true,
					cold=env.cold==true,
					immersed=env.immersed==true,
					collapsed=entry.collapse.phase~="Idle",
				}
				local result=entry.model:step(dt,activity,conditions)
				if result then
					if conditions.collapsed then
						-- Onset starts with zero stamina. Only the future movement
						-- controller may enforce sprint/crawl; no WalkSpeed write here.
						entry.model.state.stamina=0
						result.stamina=0
					end
					entry.conditions=conditions
					-- The candidate is evaluated AFTER the need step. Arm at the
					-- end of this tick; its full 1.5 s begins NEXT server tick.
					if result.collapseCandidate and entry.collapse.phase=="Idle" then
						self:beginCollapse(player)
					end
					local threshold=self.Config.Coupling.Threshold
					self.Health:metersAllowRegen(player.UserId,
						result.thirst<threshold and result.hunger<threshold)
					advanced=advanced+1
				else
					rejected=rejected+1
					self.Health:metersAllowRegen(player.UserId,false)
				end
			end
		else
			local id=player and player.UserId
			local entry=id and self.models[id]
			if entry and entry.player==player then
				entry.consume:cancel();entry.consumeCharacter=nil
				entry.pendingAir=nil -- a dead/missing body makes no ghost AIR noise
			end
			if id then self.Health:metersAllowRegen(id,false) end
		end
	end
	if rejected>0 then return advanced,"rejected-sampler" end
	return advanced,nil
end

-- EXPLICIT server-only collapse operations. They are not registered with a
-- cadence and no client intent is routed here. The caller must use its own
-- real server tick and Movement/Noise systems before this becomes gameplay.
function SurvivalService:beginCollapse(player: any): boolean
	if not connected(self,player) then return false end
	local h=eligible(self,player)
	local entry=h and self.models[player.UserId]
	if not entry or entry.player~=player or not h.character
		or h.character~=player.Character or not h.root
		or not entry.model:collapseCandidate(h.humanoid.Health)
		or not entry.collapse:begin(true) then return false end
	entry.collapseCharacter=h.character -- physical body identity, not a live-player locator
	entry.model.state.stamina=0
	entry.model.state.sinceSprint=0
	entry.conditions.collapsed=true
	return true
end

function SurvivalService:advanceCollapse(player: any,dt: number): (any?,string?)
	if not connected(self,player) then return nil,"ineligible" end
	local h=eligible(self,player)
	if not h then return nil,"ineligible" end
	local entry=self.models[player.UserId]
	if not entry or entry.player~=player or entry.collapse.phase=="Idle" then
		return nil,"not-armed"
	end
	if entry.collapseCharacter~=h.character or h.character~=player.Character then
		return nil,"stale-body"
	end
	if not finite(dt) or dt<0 or dt>5 then return nil,"invalid-dt" end
	return entry.collapse:advance(dt)
end

-- A real fall is eligible only on the SAME living physical body that armed
-- it, with a fresh finite root Position. This is bodily noise, not a hidden
-- player tracker or a location sent to another player/client.
local function pendingFall(self: any,player: any): (any?,any?)
	if not connected(self,player) then return nil,nil end
	local h=eligible(self,player)
	local entry=h and self.models[player.UserId]
	if not entry or entry.player~=player or not entry.collapse.fallPending
		or not h.character or h.character~=player.Character
		or entry.collapseCharacter~=h.character then return nil,nil end
	local root=h.root
	local p=root and root.Position
	if not p or not finite(p.X) or not finite(p.Y) or not finite(p.Z) then return nil,nil end
	return entry,p
end

-- Backward-compatible explicit server request retrieval for an eventual
-- external noise owner. Taking it spends it; a caller MUST emit it. The
-- preferred integration below emits and spends it in one synchronous path.
function SurvivalService:takeFallForNoise(player: any): any?
	local entry,p=pendingFall(self,player)
	if not entry then return nil end
	local fall=entry.collapse:takeFall()
	return {channel=fall.channel,intensity=fall.intensity,x=p.X,y=p.Y,z=p.Z}
end

-- Offline-tested direct NoiseField seam. No scheduler invokes this today.
-- NoiseField:emitAt returns an id iff a real impulse was inserted. An absent
-- emitter, bad timestamp or rejected channel leaves the event PENDING, so a
-- failed preflight cannot silently eat the only fall. Successful emission is
-- immediately followed by consuming the one-shot event (no yields/remotes).
function SurvivalService:emitPendingFall(player: any): (boolean,string?)
	if not self.Noise or type(self.Noise.emitAt)~="function"
		or not self.Time or not finite(self.Time.elapsedTotal) then
		return false,"missing-emitter"
	end
	local entry,p=pendingFall(self,player)
	if not entry then return false,"not-pending" end
	local id=self.Noise:emitAt("VIBRATION",p.X,p.Y,p.Z,
		entry.collapse.config.FallVibrationIntensity,self.Time.elapsedTotal)
	if not id then return false,"emit-rejected" end
	entry.collapse:takeFall()
	return true,nil
end

-- Server-only snapshot for an owner-specific future RE_SurvivalSync sender.
-- Do NOT return the mutable model or use FireAllClients. No HUD bars implied.
function SurvivalService:snapshot(player: any): any?
	local entry=player and self.models[player.UserId]
	local h=eligible(self,player)
	if not entry or entry.player~=player or not h or not connected(self,player) then return nil end
	local state=entry.model.state
	-- Health/phase facts are current, not the last pulse's cached conditions:
	-- a just-respawned or rejoined owner must not briefly see a false cue.
	local _,debuffs=entry.model:effects({
		bleeding=(h.bleedRate or 0)>0,collapsed=entry.collapse.phase~="Idle"})
	return {thirst=state.thirst,hunger=state.hunger,stamina=state.stamina,
		debuffs=debuffs}
end

return SurvivalService
