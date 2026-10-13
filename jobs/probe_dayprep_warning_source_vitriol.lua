-- READ ONLY Vitriol/Edit: compile actual Studio Sources, exercise actual
-- DayPrepService 0.25s slot against pure Lua fakes. No Play-time claim.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local vitriol=game:GetService("ServerStorage").Vitriol
local prepSource=vitriol.Services.DayPrepService
local bootstrap=vitriol.Bootstrap
assert(prepSource:IsA("ModuleScript") and bootstrap:IsA("ModuleScript"),"script class drift")
local make,err=loadstring(prepSource.Source);assert(make,err or "DayPrep Source failed compile")
assert(loadstring(bootstrap.Source),"Bootstrap Source failed compile")
assert(string.find(bootstrap.Source,'name == "DayPrep:Pulse"',1,true)
 and string.find(bootstrap.Source,"prep.lastPulseFrom",1,true)
 and string.find(bootstrap.Source,"prep.lastPulseHum",1,true),
 "Bootstrap lost same-slot exceptional warning branch")
local module=make()
local slot=nil
local function signal()
 return {Connect=function() return {Disconnect=function() end} end}
end
local trigger=signal()
local service=setmetatable({running=false,connections={},
 CanPrompt={Triggered=trigger},GeneratorPrompt={Triggered=trigger},
 GarageRepairPrompt={Triggered=trigger},BellPrompt={Triggered=trigger},
 Players={PlayerAdded=signal(),PlayerRemoving=signal(),GetPlayers=function() return {} end},
 Cadence={register=function(_,spec) slot=spec;return 1 end},
 Session={Config={Budgets={SlowShares={DayPrep=.05}}}},
 Time={phase="Day",elapsedTotal=1},
 Floodlight={tick=function() end},powered=false,
 _publish=function() end,_tickBell=function() end,
},module)
service.Prep={current={Action="CoverHouse01Closet",Stage="blackout"},
 tick=function(self) if self.current then self.current.Stage="reveal" end end}
service:start()
assert(service.Prep and service.Prep.current and service.Prep.current.Stage=="blackout",
 "pure Lua prep fixture changed during start")
assert(slot and slot.Name=="DayPrep:Pulse" and slot.BudgetMs==.05,"slot/budget drift")
slot.Run(.25)
assert(service.lastPulseAction=="CoverHouse01Closet"
 and service.lastPulseFrom=="blackout" and service.lastPulseTo=="reveal"
 and service.lastPulseHum==false,"commit-stage context wrong")
local hum=0
service.Prep.current=nil
service.Time.phase="Night";service.powered=true;service.nextGeneratorHum=0
service._noise=function() hum+=1 end
slot.Run(.25)
assert(service.lastPulseAction=="none" and service.lastPulseFrom=="none"
 and service.lastPulseTo=="none" and service.lastPulseHum==true and hum==1,
 "Night scheduled hum context wrong")
return game:GetService("HttpService"):JSONEncode({ok=true,editOnly=true,
 slot=slot.Name,budget=slot.BudgetMs,syntheticPaths={"blackout->reveal","none/hum"},
 realWorldMutated=false,playTimingMeasured=false})
