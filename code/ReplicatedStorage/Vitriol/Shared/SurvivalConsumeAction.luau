--!strict
-- Pure M6 consumption transaction boundary. This is NOT an InventoryService,
-- prompt, client intent or scheduler. One action belongs to ONE server player
-- ledger; its future owner supplies verified eligibility and an atomic,
-- non-yielding consumeOwned callback. No meter changes until that callback
-- actually removes a server-owned item AFTER the authored time has elapsed.
local SurvivalConsumeAction={}
SurvivalConsumeAction.__index=SurvivalConsumeAction
local EPS=1e-9
local function finite(v: any): boolean
	return type(v)=="number" and v==v and v>-math.huge and v<math.huge
end

function SurvivalConsumeAction.new(config: any): any
	assert(config and config.Consumables,"[Vitriol.Survival] authored Consumables required")
	return setmetatable({Config=config,phase="Idle",item=nil,elapsed=0,duration=0},
		SurvivalConsumeAction)
end

function SurvivalConsumeAction:cancel(): boolean
	if self.phase=="Idle" then return false end
	self.phase="Idle";self.item=nil;self.elapsed=0;self.duration=0
	return true
end

-- `verified` must be supplied by the server's inventory/action authority,
-- NEVER by a client payload. Health-managed items are another service's job.
function SurvivalConsumeAction:begin(item: string,verified: boolean): (boolean,string?)
	if self.phase~="Idle" then return false,"busy" end
	if verified~=true then return false,"not-verified" end
	local entry=type(item)=="string" and self.Config.Consumables[item]
	if not entry then return false,"invalid-item" end
	if entry.health~=nil or entry.bleeding then return false,"health-managed" end
	if not finite(entry.seconds) or entry.seconds<=0 or entry.seconds>30 then
		return false,"invalid-duration"
	end
	self.phase="Preparing";self.item=item;self.elapsed=0
	self.duration=entry.seconds
	return true,nil
end

-- The owner must verify each tick that the player is still alive, has this
-- item, and is not grabbed/interrupted. A false/missing verdict cancels it;
-- a forged dt cannot skip straight to Ready or mutate the action.
function SurvivalConsumeAction:advance(dt: number,stillValid: boolean): (any?,string?)
	if not finite(dt) or dt<0 or dt>5 then return nil,"invalid-dt" end
	if self.phase=="Idle" then return nil,"idle" end
	if stillValid~=true then self:cancel();return nil,"interrupted" end
	if self.phase=="Preparing" then
		self.elapsed=math.min(self.duration,self.elapsed+dt)
		if self.elapsed>=self.duration-EPS then
			self.elapsed=self.duration;self.phase="Ready"
		end
	end
	return {phase=self.phase,item=self.item,elapsed=self.elapsed,duration=self.duration},nil
end

-- Callable only AFTER the real action time. `consumeOwned(item)` must atomically
-- validate and remove precisely one owned item, synchronously returning true
-- only on successful removal. Validate the roll and config BEFORE calling it.
-- Mark Committing first, so even a reentrant inventory callback cannot double
-- spend one action. Only successful removal grants meters, Sick and AIR metadata.
function SurvivalConsumeAction:commit(model: any,roll: number?,consumeOwned: any): (any?,string?)
	if self.phase~="Ready" then return nil,"not-ready" end
	if not model or model.Config~=self.Config
		or type(model.consumableDefinition)~="function" then
		self:cancel();return nil,"wrong-model"
	end
	local item=self.item
	local entry,err=model:consumableDefinition(item,roll)
	if not entry then self:cancel();return nil,err end
	if entry.seconds~=self.duration then
		self:cancel();return nil,"changed-duration"
	end
	if type(consumeOwned)~="function" then
		self:cancel();return nil,"missing-inventory"
	end
	self.phase="Committing"
	local ok,consumed=pcall(consumeOwned,item)
	if not ok or consumed~=true then
		self:cancel();return nil,"inventory-denied"
	end
	local result,applyErr=model:applyVerifiedConsumable(item,roll)
	self:cancel()
	assert(result, "[Vitriol.Survival] committed item failed stable model preflight: " .. tostring(applyErr))
	return result,nil
end

return SurvivalConsumeAction
