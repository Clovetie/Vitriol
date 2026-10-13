--!strict
-- Pure M6 survival math. This module does NOT run on its own: no scheduler,
-- Player/Instance lookup, client intent, inventory, Health write, remote,
-- noise, UI or authored-geometry mutation. An eventual server service owns
-- those boundaries and must pass its actual SurvivalConfig explicitly.
-- Meters measure NEED: 0 is sated, 100 is critical (docs/05-SURVIVAL.md).
local SurvivalModel = {}
SurvivalModel.__index = SurvivalModel

local EFFECT_DEFAULTS = {
	WalkSpeed=1, JumpPower=1, StaminaRegen=1, ScentScale=1,
	NoiseScale=1, CarryCapacity=1, InteractSpeed=1, RegionIntegrity=1,
	DrainMultiplier=1, HealthDrain=0,
}
local ADDITIVE = { HealthDrain=true }
local EXHAUST_AFTER_EMPTY_SECONDS = 3 -- docs/05 §3.1: strictly more than 3 s at zero
local function finite(value: any): boolean
	return type(value)=="number" and value==value and value > -math.huge and value < math.huge
end
local function clamp(value: number, low: number, high: number): number
	return math.max(low, math.min(high, value))
end
local function unitStep(value: number, threshold: number, width: number): number
	local t=clamp((value - (threshold-width*0.5))/width,0,1)
	return t*t*(3-2*t)
end

function SurvivalModel.new(config: any): any
	assert(config and config.ActivityDrain and config.Modifiers and config.Coupling
		and config.Debuffs and config.Stamina and config.Collapse,
		"[Vitriol.Survival] explicit authored SurvivalConfig required")
	local m,c=config.Modifiers,config.Coupling
	assert(c.Width > 0 and c.Threshold >= 0 and c.Threshold <= 100
		and math.abs(m.StarvedThirst - (1+c.ThirstFromHunger)) < 1e-6
		and math.abs(m.ParchedHunger - (1+c.HungerFromThirst)) < 1e-6,
		"[Vitriol.Survival] duplicated coupling/config mirrors disagree")
	local exhausted=config.Debuffs.Exhausted
	if exhausted then
		local timed=exhausted.Trigger and exhausted.Trigger.timed
		assert(finite(timed) and finite(config.Stamina.ExhaustionDuration)
			and timed>0 and math.abs(timed-config.Stamina.ExhaustionDuration)<1e-6,
			"[Vitriol.Survival] Exhausted timer and stamina duration disagree")
	end
	local self=setmetatable({}, SurvivalModel)
	self.Config=config
	self.state={thirst=0,hunger=0,stamina=config.Stamina.Max,
		sinceSprint=math.huge,emptyStaminaSeconds=0,timed={}}
	return self
end

-- A single smooth coupling term owns each cross-meter multiplier. The
-- Modifiers.StarvedThirst/ParchedHunger values mirror its maxima; new() checks
-- parity instead of applying both and accidentally squaring the effect.
function SurvivalModel:rates(activity: string, conditions: any?): (number?,number?)
	local base=self.Config.ActivityDrain[activity]
	if not base then return nil,nil end
	local state=self.state
	local m,c=self.Config.Modifiers,self.Config.Coupling
	local condition=conditions or {}
	local thirst=base.thirst
	local hunger=base.hunger
	if condition.bleeding then thirst=thirst*m.BleedingThirst; hunger=hunger*m.BleedingHunger end
	if condition.hot then thirst=thirst*m.HotThirst; hunger=hunger*m.HotHunger end
	if condition.cold then thirst=thirst*m.ColdThirst; hunger=hunger*m.ColdHunger end
	if condition.immersed then thirst=thirst*m.ImmersedThirst end
	local active=self:effects(condition)
	thirst=thirst*active.DrainMultiplier
	hunger=hunger*active.DrainMultiplier
	thirst=thirst*(1+c.ThirstFromHunger*unitStep(state.hunger,c.Threshold,c.Width))
	hunger=hunger*(1+c.HungerFromThirst*unitStep(state.thirst,c.Threshold,c.Width))
	return thirst,hunger -- per REAL minute, not per phase minute
end

-- Data-driven debuff composition; removals/additions require no if chain.
-- Timed effects can be activated only by an owning server service, never by
-- a client argument. Wound HealthDrain is NOT applied here (Health owns HP).
function SurvivalModel:effects(conditions: any?): (any,{string})
	local state=self.state
	local condition=conditions or {}
	local effects={ScreenFx={},AudioCues={}}
	for key,value in pairs(EFFECT_DEFAULTS) do effects[key]=value end
	local active={}
	for name,definition in pairs(self.Config.Debuffs) do
		local trigger=definition.Trigger
		local applies=(name=="Bleeding" and condition.bleeding==true)
			or (name=="Collapse" and condition.collapsed==true)
			or (trigger and trigger.meter and state[trigger.meter]>=trigger.at)
			or (trigger and trigger.timed and (state.timed[name] or 0)>0)
		if applies then active[#active+1]=name end
	end
	table.sort(active,function(a,b)
		local pa,pb=self.Config.Debuffs[a].Priority or 0,self.Config.Debuffs[b].Priority or 0
		return pa==pb and a<b or pa>pb
	end)
	local screenSeen,audioSeen={},{}
	for i=1,#active do
		local definition=self.Config.Debuffs[active[i]]
		for key,value in pairs(definition) do
			if EFFECT_DEFAULTS[key]~=nil and type(value)=="number" then
				if ADDITIVE[key] then effects[key]=effects[key]+value else effects[key]=effects[key]*value end
			end
		end
		for _,cue in ipairs(definition.ScreenFx or {}) do
			if not screenSeen[cue] then screenSeen[cue]=true;effects.ScreenFx[#effects.ScreenFx+1]=cue end
		end
		for _,cue in ipairs(definition.AudioCues or {}) do
			if not audioSeen[cue] then audioSeen[cue]=true;effects.AudioCues[#effects.AudioCues+1]=cue end
		end
	end
	return effects,active
end

function SurvivalModel:applyTimed(name: string): boolean
	local definition=self.Config.Debuffs[name]
	local duration=definition and definition.Trigger and definition.Trigger.timed
	if not finite(duration) or duration<=0 then return false end
	self.state.timed[name]=duration
	return true
end

-- Call ONLY after a future InventoryService has verified and committed an
-- interruptible, server-timed consumption action. A client item name/roll must
-- never reach this method through a remote. No item is removed and no noise/HP
-- is applied here; bandages and medkits belong to Health's single HP writer.
-- The roll is supplied by the SERVER for reproducible sick-chance tests.
-- Pure PRE-COMMIT validation: an interruptible action must check the item and
-- sick roll BEFORE it asks InventoryService to remove anything. This method
-- never changes a need meter, health, inventory, timer or noise field.
function SurvivalModel:consumableDefinition(item: string, roll: number?): (any?,string?)
	if type(item)~="string" then return nil,"invalid-item" end
	local entry=self.Config.Consumables and self.Config.Consumables[item]
	if not entry then return nil,"invalid-item" end
	if entry.health~=nil or entry.bleeding then return nil,"health-managed" end
	local thirst,hunger=entry.thirst or 0,entry.hunger or 0
	local chance=entry.sickChance or 0
	if not finite(thirst) or thirst>0 or not finite(hunger) or hunger>0
		or (thirst==0 and hunger==0) or not finite(chance)
		or chance<0 or chance>1
		or not finite(entry.seconds) or entry.seconds<=0
		or not finite(entry.noiseAir) or entry.noiseAir<0 then
		return nil,"invalid-consumable"
	end
	if chance>0 and (type(roll)~="number" or not finite(roll) or roll<0 or roll>=1) then
		return nil,"invalid-roll"
	end
	return entry,nil
end

function SurvivalModel:applyVerifiedConsumable(item: string, roll: number?): (any?,string?)
	local entry,err=self:consumableDefinition(item,roll)
	if not entry then return nil,err end
	local state=self.state
	state.thirst=clamp(state.thirst+(entry.thirst or 0),0,100)
	state.hunger=clamp(state.hunger+(entry.hunger or 0),0,100)
	local sick=(entry.sickChance or 0)>0 and (roll or 0)<entry.sickChance
	if sick then self:applyTimed("Sick") end
	return {thirst=state.thirst,hunger=state.hunger,sick=sick,
		seconds=entry.seconds,noiseAir=entry.noiseAir},nil
end

function SurvivalModel:collapseCandidate(health: number): boolean
	local state=self.state
	local config=self.Config.Collapse
	for _,threshold in ipairs(config.Triggers) do
		if state.thirst >= (threshold.thirst or 0) and state.hunger >= (threshold.hunger or 0) then
			return true
		end
	end
	return finite(health) and health < config.HealthThreshold
		and state.thirst >= config.HealthRequiresBothMetersAt
		and state.hunger >= config.HealthRequiresBothMetersAt
end

-- Deterministic, server-ready arithmetic only. Large calls are integrated in
-- one-second chunks so passing dt=60 cannot skip the 5-unit smooth threshold;
-- callers normally tick at the budgeted slow cadence. No health/remote/noise
-- side effect, and invalid activities/dt leave the state untouched.
function SurvivalModel:step(dt: number, activity: string, conditions: any?): (any?,string?)
	if not finite(dt) or dt<0 or dt>3600 then return nil,"invalid-dt" end
	if not self.Config.ActivityDrain[activity] then return nil,"invalid-activity" end
	local state=self.state
	local remaining=dt
	while remaining>0 do
		local part=math.min(remaining,1)
		local stamina=self.Config.Stamina
		-- Split at depletion or the end of the post-sprint wait; neither
		-- crossing counts an entire tick as empty. This also gives subsecond
		-- and whole-second calls the same exhaustion onset.
		if activity=="Sprinting" and state.stamina>0 and stamina.SprintDrainPerSecond>0 then
			part=math.min(part,state.stamina/stamina.SprintDrainPerSecond)
		elseif activity~="Sprinting" and state.stamina==0
			and state.sinceSprint<stamina.RegenDelayAfterSprint then
			part=math.min(part,stamina.RegenDelayAfterSprint-state.sinceSprint)
		end
		if state.stamina==0 and state.emptyStaminaSeconds<EXHAUST_AFTER_EMPTY_SECONDS then
			part=math.min(part,EXHAUST_AFTER_EMPTY_SECONDS-state.emptyStaminaSeconds)
		end
		-- A debuff expiring mid-tick contributes only until expiry.
		for _,left in pairs(state.timed) do
			if left>0 and left<part then part=left end
		end
		local wasEmpty=state.stamina==0
		local thirst,hunger=self:rates(activity,conditions)
		state.thirst=clamp(state.thirst+thirst*part/60,0,100)
		state.hunger=clamp(state.hunger+hunger*part/60,0,100)
		if activity=="Sprinting" then
			state.stamina=clamp(state.stamina-stamina.SprintDrainPerSecond*part,0,stamina.Max)
			state.sinceSprint=0 -- no regen while still demanding a sprint at zero
		else
			local before=state.sinceSprint
			state.sinceSprint=before+part
			-- A delay ending MID-step allows only the eligible remainder to
			-- regenerate. Count the whole interval if no sprint has happened.
			local eligible=before==math.huge and part
				or math.max(0,part-math.max(0,stamina.RegenDelayAfterSprint-before))
			if eligible>0 then
				local effects=self:effects(conditions)
				local penalty=1-self.Config.Coupling.StaminaPenaltyPerMeter
					*(state.hunger/100+state.thirst/100)*0.5
				state.stamina=clamp(state.stamina+stamina.RegenPerSecond
					*effects.StaminaRegen*math.max(0,penalty)*eligible,0,stamina.Max)
			end
		end
		if wasEmpty and state.stamina==0 then
			state.emptyStaminaSeconds=state.emptyStaminaSeconds+part
		elseif state.stamina>0 then
			state.emptyStaminaSeconds=0
		end
		for name,duration in pairs(state.timed) do
			local left=duration-part
			if left<=0 then state.timed[name]=nil else state.timed[name]=left end
		end
		if state.stamina==0 and state.emptyStaminaSeconds>EXHAUST_AFTER_EMPTY_SECONDS
			and not state.timed.Exhausted then
			self:applyTimed("Exhausted") -- data-owned 6 s; never client-activated
		end
		remaining=remaining-part
	end
	local effects,active=self:effects(conditions)
	return {thirst=state.thirst,hunger=state.hunger,stamina=state.stamina,
		effects=effects,debuffs=active,collapseCandidate=self:collapseCandidate(
			conditions and conditions.health or math.huge)},nil
end

return SurvivalModel
