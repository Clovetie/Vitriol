-- Headless M6 server-side timed consumption with an injected FAKE inventory.
-- NoiseField and Health seam are real; no Bootstrap, Remote or client intent.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1;print("PASS  "..msg)
 else SESSION.failed=SESSION.failed+1;print("FAIL  "..msg) end
end
local function approx(a,b)return math.abs(a-b)<1e-7 end
local C=VitriolRequire("SurvivalConfig")
local Service=VitriolRequire("SurvivalService")
local NoiseField=VitriolRequire("NoiseField")
local p={UserId=9101,Character={}}
local q={UserId=9102,Character={}}
local forged={UserId=9101,Character={}}
local players={list={p,q},GetPlayers=function(self)return self.list end}
local health={states={}}
function health:metersAllowRegen(id,ok)
 if self.states[id] then self.states[id].metersAllowRegen=ok end
end
health.states[9101]={player=p,character=p.Character,root={Position={X=11,Y=2,Z=4}},
 humanoid={Health=75},bleedRate=0,dead=false}
health.states[9102]={player=q,character=q.Character,root={Position={X=100,Y=2,Z=4}},
 humanoid={Health=90},bleedRate=0,dead=false}
local inventory={items={[9101]={CleanWater=1,DirtyWater=2,CannedFood=1},
 [9102]={CannedFood=1,CleanWater=1}},claims=0}
function inventory:hasOwned(player,item)
 local items=self.items[player.UserId] or {}
 return (items[item] or 0)>0
end
function inventory:consumeOwned(player,item)
 if not self:hasOwned(player,item) then return false end
 self.items[player.UserId][item]=self.items[player.UserId][item]-1
 self.claims=self.claims+1
 return true
end
local permitted={[9101]=true,[9102]=true}
local sickRoll=.2
local noise=NoiseField.new()
local time={elapsedTotal=12}
local svc=setmetatable({},Service)
local beforeRemote=COUNTERS.remoteFires
local beforeInstance=COUNTERS.runtimeInstanceNew
local beforeHeartbeat=COUNTERS.heartbeatConnections
svc:init({Players=players,Health=health,Survival=C,Noise=noise,Time=time,
 ResolveActivity=function()return "Resting" end,
 ResolveEnvironment=function()return {} end})
svc:observe(p);svc:observe(q)
svc.models[9101].model.state.thirst=80 -- enough need to measure full -35/-25 without 0 clamp
local ok,err=svc:beginConsumption(p,"CleanWater")
check(not ok and err=="unwired" and svc.models[9101].consume.phase=="Idle",
 "without a server Inventory/interrupt/roll authority no action is allowed")
svc.Inventory=inventory
svc.CanConsume=function(player) return permitted[player.UserId] end
svc.RollSick=function() return sickRoll end
ok,err=svc:beginConsumption(forged,"CleanWater")
check(not ok and err=="ineligible" and inventory.claims==0,
 "forged old Player object cannot reserve or consume another player's inventory")
ok,err=svc:beginConsumption(p,"Medkit")
check(not ok and err=="not-owned-or-interrupted" and inventory.claims==0,
 "an unowned Health-managed item cannot bypass Inventory or HealthService")
ok,err=svc:beginConsumption(p,"CleanWater")
check(ok and err==nil and svc.models[9101].consume.duration==2
 and inventory.items[9101].CleanWater==1,
 "owned water starts one authored two-second server action, no inventory removed yet")
local early,earlyErr=svc:commitConsumption(p)
check(early==nil and earlyErr=="not-ready" and inventory.items[9101].CleanWater==1,
 "cannot commit a drink early by calling the server method directly")
local beforeDrink=svc.models[9101].model.state.thirst
svc:pulse(1)
check(svc.models[9101].consume.phase=="Preparing"
 and inventory.items[9101].CleanWater==1
 and svc.models[9101].model.state.thirst>beforeDrink,
 "one second advances needs and timer but does not invent hydration")
svc:pulse(1)
check(svc.models[9101].consume.phase=="Ready" and inventory.claims==0,
 "timer completion remains a server-ready state, not an automatic commit")
local justBefore=svc.models[9101].model.state.thirst
local noiseId=noise.nextId.AIR
local result,why=svc:commitConsumption(p)
check(result and why==nil and approx(result.thirst,justBefore-35)
 and inventory.items[9101].CleanWater==0 and inventory.claims==1,
 "atomic inventory removal gives exactly one authored thirst restoration")
check(noise.nextId.AIR==noiseId+1 and noise:sample("AIR",11,2,4,5,12)>=.15
 and health.states[9101].metersAllowRegen==true,
 "successful water commit inserts one real AIR impulse and updates Health regen gate")
result,why=svc:commitConsumption(p)
check(result==nil and why=="not-ready" and noise.nextId.AIR==noiseId+1
 and inventory.claims==1,
 "duplicate commit cannot grant another item or another noise burst")
ok,err=svc:beginConsumption(p,"CleanWater")
check(not ok and err=="not-owned-or-interrupted",
 "server Inventory owns the exhaustion of the only clean-water item")
ok=svc:beginConsumption(q,"CannedFood")
check(ok and svc.models[9102].consume.phase=="Preparing"
 and inventory.items[9102].CannedFood==1,
 "a second player's food action is independent of the first owner's finished water")
permitted[9102]=false
svc:pulse(.2)
check(svc.models[9102].consume.phase=="Idle" and inventory.items[9102].CannedFood==1,
 "server interruption cancels the second player's action without costing food")
permitted[9102]=true
ok=svc:beginConsumption(q,"CannedFood")
local qChar=q.Character
q.Character={};health.states[9102].character=q.Character
svc:pulse(.2)
check(ok and svc.models[9102].consume.phase=="Idle"
 and inventory.items[9102].CannedFood==1,
 "character replacement cancels consumption; a new body cannot inherit paid action time")
q.Character=qChar;health.states[9102].character=qChar
svc:beginConsumption(p,"DirtyWater")
svc:pulse(2.5)
sickRoll=0/0
local beforeInvalid=svc.models[9101].model.state.thirst
result,why=svc:commitConsumption(p)
check(result==nil and why=="invalid-roll" and inventory.items[9101].DirtyWater==2
 and approx(svc.models[9101].model.state.thirst,beforeInvalid),
 "invalid server sick roll is rejected before any inventory or meter write")
sickRoll=.2
svc:beginConsumption(p,"DirtyWater");svc:pulse(2.5)
local oldConsume=inventory.consumeOwned
inventory.consumeOwned=function()return false end
local beforeDenied=svc.models[9101].model.state.thirst
result,why=svc:commitConsumption(p)
check(result==nil and why=="inventory-denied"
 and approx(svc.models[9101].model.state.thirst,beforeDenied)
 and inventory.items[9101].DirtyWater==2,
 "atomic Inventory denial cannot hydrate or apply Sick")
inventory.consumeOwned=oldConsume
svc:beginConsumption(p,"DirtyWater");svc:pulse(2.5)
local beforePoison=svc.models[9101].model.state.thirst
noiseId=noise.nextId.AIR
result,why=svc:commitConsumption(p)
check(result and result.sick and approx(result.thirst,beforePoison-25)
 and svc.models[9101].model.state.timed.Sick==90
 and inventory.items[9101].DirtyWater==1,
 "owned dirty water restores thirst and applies authored Sick from a SERVER roll")
check(noise.nextId.AIR==noiseId+1 and noise:sample("AIR",11,2,4,5,12)>=.2,
 "dirty water emits precisely one authored AIR impulse after owned-item commit")
svc:beginConsumption(p,"DirtyWater");svc:pulse(2.5)
local realNoise=svc.Noise
svc.Noise={emitAt=function()return nil end}
local oldPosition=health.states[9101].root.Position
noiseId=noise.nextId.AIR
result,why=svc:commitConsumption(p)
check(result and why==nil and svc.models[9101].pendingAir
 and inventory.items[9101].DirtyWater==0 and noise.nextId.AIR==noiseId,
 "rejected AIR insertion queues ONE physical event without re-consuming the committed item")
ok,err=svc:beginConsumption(p,"CannedFood")
check(not ok and err=="ineligible" and inventory.items[9101].CannedFood==1,
 "an unflushed AIR event blocks another item rather than building an unbounded noise queue")
health.states[9101].root.Position={X=400,Y=2,Z=400}
svc.Noise=realNoise
svc:pulse(.2)
check(not svc.models[9101].pendingAir and noise.nextId.AIR==noiseId+1
 and noise:sample("AIR",oldPosition.X,oldPosition.Y,oldPosition.Z,5,12)>=.2,
 "retry inserts once at real completion point, not hidden live/player-moved coordinates")
svc:pulse(.2)
check(noise.nextId.AIR==noiseId+1 and inventory.claims==3,
 "later ticks cannot emit again or reconsume the third server-owned item")
svc:beginConsumption(q,"CannedFood")
health.states[9102].dead=true
svc:pulse(.2)
check(svc.models[9102].consume.phase=="Idle" and inventory.items[9102].CannedFood==1,
 "death cancels preparation without losing the item or making phantom chewing noise")
health.states[9102].dead=false
svc:beginConsumption(q,"CannedFood")
svc:detach(q)
check(svc.models[9102].consume.phase=="Idle" and inventory.items[9102].CannedFood==1,
 "disconnect cancels the action but preserves server inventory for the authoritative owner")
check(COUNTERS.remoteFires==beforeRemote and COUNTERS.runtimeInstanceNew==beforeInstance
 and COUNTERS.heartbeatConnections==beforeHeartbeat,
 "consumption seam did not create Instances, a new scheduler, or disclose a remote")
print("Survival consume service: "..SESSION.passed.." passed, "..SESSION.failed.." failed")
return SESSION
