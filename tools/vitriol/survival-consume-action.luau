-- Offline M6 consumption transaction: no Remote, InventoryService or noise.
TESTS={passed=0,failed=0}
local function check(ok,msg)
 if ok then TESTS.passed=TESTS.passed+1;print("PASS  "..msg)
 else TESTS.failed=TESTS.failed+1;warn("FAIL  "..msg) end
end
local function near(a,b)return math.abs(a-b)<1e-9 end
local cfg=VitriolRequire("SurvivalConfig")
local Action=VitriolRequire("SurvivalConsumeAction")
local Model=VitriolRequire("SurvivalModel")
local a=Action.new(cfg)
local m=Model.new(cfg)
m.state.thirst=60;m.state.hunger=75
check(a.phase=="Idle" and not a:cancel() and not a:begin("CleanWater",false)
 and not a:begin("CleanWater",nil),
 "no client/unverified eligibility can start a server item action")
local began,why=a:begin("MadeUp",true)
check(not began and why=="invalid-item" and a.phase=="Idle",
 "invented item is refused without starting a timer")
for _,item in ipairs({"Medkit","Bandage"}) do
 began,why=a:begin(item,true)
 check(not began and why=="health-managed" and a.phase=="Idle",
  "Health-managed items cannot be used to bypass the wound/HP writer")
end
began,why=a:begin("CleanWater",true)
check(began and why==nil and a.duration==2 and a.item=="CleanWater"
 and m.state.thirst==60,
 "server-verified clean water starts its authored two-second action with NO instant hydration")
check(not a:begin("CannedFood",true) and a.item=="CleanWater",
 "a second request cannot replace an in-progress action or make two commitments")
local premature,errorCode=a:commit(m,nil,function()error("called early")end)
check(premature==nil and errorCode=="not-ready" and m.state.thirst==60,
 "inventory callback is not called before the authored action has finished")
for _,bad in ipairs({-1,0/0,math.huge,5.1}) do
 local state,err=a:advance(bad,true)
 check(state==nil and err=="invalid-dt" and a.elapsed==0 and a.phase=="Preparing",
  "invalid dt cannot skip action progress")
end
local half=a:advance(.5,true)
check(half and near(half.elapsed,.5) and a.phase=="Preparing" and m.state.thirst==60,
 "real half-second progresses but cannot restore thirst early")
local interrupted,whyInterrupt=a:advance(.2,false)
check(interrupted==nil and whyInterrupt=="interrupted" and a.phase=="Idle"
 and m.state.thirst==60 and not a:cancel(),
 "a grab or lost server item interrupts the action without consuming it")
local consumedCalls=0
began=a:begin("CannedFood",true)
a:advance(3,true)
check(began and a.phase=="Ready" and m.state.hunger==75
 and a:advance(5,true).phase=="Ready",
 "finishing/overshooting time only arms commit, never invents food or auto-consumes")
local result,err=a:commit(m,nil,function(item)
 consumedCalls=consumedCalls+1
 return item=="CannedFood"
end)
check(result and result.hunger==35 and result.thirst==60 and not result.sick
 and result.noiseAir==.4 and consumedCalls==1 and a.phase=="Idle",
 "one owned canned food commits ONCE and grants only its authored hunger delta")
result,err=a:commit(m,nil,function()consumedCalls=consumedCalls+1;return true end)
check(result==nil and err=="not-ready" and consumedCalls==1 and m.state.hunger==35,
 "repeat commit without another timed action cannot duplicate food")
a:begin("DirtyWater",true);a:advance(2.5,true)
local preflight,preErr=m:consumableDefinition("DirtyWater",1)
check(preflight==nil and preErr=="invalid-roll" and m.state.thirst==60,
 "pre-commit sick-roll validation changes no needs")
result,err=a:commit(m,1,function()consumedCalls=consumedCalls+1;return true end)
check(result==nil and err=="invalid-roll" and consumedCalls==1
 and m.state.thirst==60 and a.phase=="Idle",
 "invalid sick roll aborts BEFORE inventory is removed")
a:begin("DirtyWater",true);a:advance(2.5,true)
result,err=a:commit(m,.2,function()consumedCalls=consumedCalls+1;return false end)
check(result==nil and err=="inventory-denied" and consumedCalls==2
 and m.state.thirst==60 and m.state.timed.Sick==nil,
 "missing/contested owned item cancels without hydration or Sick")
a:begin("CleanWater",true);a:advance(2,true)
result,err=a:commit(m,nil,function()error("inventory unavailable")end)
check(result==nil and err=="inventory-denied" and a.phase=="Idle"
 and m.state.thirst==60,
 "inventory error cannot award needs while ownership was unconfirmed")
a:begin("DirtyWater",true);a:advance(2.5,true)
local inventory={DirtyWater=1}
local nestedErr
result,err=a:commit(m,.2,function(item)
 local nested,nestedWhy=a:commit(m,.8,function()error("duplicate!")end)
 nestedErr=(nested==nil and nestedWhy=="not-ready")
 if inventory[item]~=1 then return false end
 inventory[item]=0;return true
end)
check(result and result.thirst==35 and result.hunger==35 and result.sick
 and result.seconds==2.5 and result.noiseAir==.2 and m.state.timed.Sick==90
 and inventory.DirtyWater==0 and nestedErr and a.phase=="Idle",
 "atomic owned-item callback commits once, resists reentrancy, then starts Sick from server roll")
local fresh=Action.new(cfg)
local full=Action.new(cfg)
fresh:begin("DirtyWater",true);full:begin("DirtyWater",true)
for i=1,5 do fresh:advance(.5,true) end
full:advance(2.5,true)
check(fresh.phase=="Ready" and full.phase=="Ready"
 and fresh.elapsed==full.elapsed and near(fresh.duration,2.5),
 "five split half-second steps equal one complete authored drink interval")
local otherConfig={}
for k,v in pairs(cfg) do otherConfig[k]=v end
local wrongModel=Model.new(otherConfig)
local didCall=false
result,err=fresh:commit(wrongModel,.5,function()didCall=true;return true end)
check(result==nil and err=="wrong-model" and not didCall and fresh.phase=="Idle"
 and wrongModel.state.thirst==0,
 "mismatched config cannot remove an item or credit another model")
local changedConfig={}
for k,v in pairs(cfg) do changedConfig[k]=v end
changedConfig.Consumables={}
for k,v in pairs(cfg.Consumables) do changedConfig.Consumables[k]=v end
changedConfig.Consumables.DirtyWater={thirst=-25,sickChance=.35,seconds=3,noiseAir=.2}
local changed=Action.new(changedConfig)
local changedModel=Model.new(changedConfig)
changed:begin("DirtyWater",true);changed:advance(3,true)
changedConfig.Consumables.DirtyWater.seconds=2.5
result,err=changed:commit(changedModel,.5,function()didCall=true;return true end)
check(result==nil and err=="changed-duration" and changed.phase=="Idle"
 and changedModel.state.thirst==0 and not didCall,
 "mutating authored action time mid-action fails before any inventory removal")
changedConfig.Consumables.DirtyWater.seconds=0
began,why=changed:begin("DirtyWater",true)
check(not began and why=="invalid-duration" and changed.phase=="Idle",
 "invalid authored duration cannot arm a free or infinite action")
print("Survival consume action: "..TESTS.passed.." passed, "..TESTS.failed.." failed")
return TESTS
