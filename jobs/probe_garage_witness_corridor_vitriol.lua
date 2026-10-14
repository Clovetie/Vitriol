-- READ ONLY/Edit: freshly compiled Studio Sources, real garage sensing corridor.
-- This is a physical preflight, NOT a live prey/Play/cadence measurement.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local server=game:GetService("ServerStorage").Vitriol
local replicated=game:GetService("ReplicatedStorage").Vitriol
local habitSrc=server.Creature.Brain.GarageHabit
local navSrc=server.Creature.GarageNavigation
assert(habitSrc:IsA("ModuleScript") and navSrc:IsA("ModuleScript"))
local habitMake,habitErr=loadstring(habitSrc.Source)
local navMake,navErr=loadstring(navSrc.Source)
local configMake,configErr=loadstring(replicated.Config.MonsterConfig.Source)
assert(habitMake,habitErr);assert(navMake,navErr);assert(configMake,configErr)
local cfg=configMake()
local nav=assert(navMake().new(workspace.Map,workspace),"real Garage navigation missing")
local habit=habitMake().new(cfg.Memory,nav,cfg.InstinctSearch)
local floor=workspace.Map.Structures.Millers_Garage.Floor
assert(floor.Position.X==-90 and floor.Position.Z==-56 and floor.Size.X==56 and floor.Size.Z==46,
 "Garage changed: re-survey this corridor")
local firstOutside=-55
local entry={-55,-60,-62,-63,-64,-65,-70,-80,-90}
local exit={-80,-70,-65,-64,-63,-62,-60,-55}
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local rays=0
local function witness(x,expected)
 -- Pure ground-height directional clearance from the existing authored east
 -- door. Only call observe after confirming that this point could be SENSED.
 local hit=nav:hit(firstOutside,floor.Position.Z,x,floor.Position.Z,params)
 rays+=1
 if hit then error("real Garage corridor occluded at X="..x.." by "..hit.Instance:GetFullName()) end
 local learned=habit:observe(91,x,4,floor.Position.Z)
 assert(learned==expected,"unexpected entry witness at Garage corridor X="..x)
end
for visit=1,3 do
 for _,x in ipairs(entry) do witness(x,x==-64) end
 assert(habit.Visits==visit,"Garage visits inflated during same interior stay")
 if visit<3 then
  for _,x in ipairs(exit) do witness(x,false) end
 end
end
assert(habit:dump().predictsGarage and habit.Visits==3,
 "three physically observable ground-level walks did not train fourth-visit preference")
local core={X=0,Y=8,Z=0,RaycastParams=params}
local x,z,reason=habit:lead(core,30,0,nav,nil)
assert(x==-55 and z==-56 and reason=="witnessed-three-garage-entries",
 "fourth-visit search did not select the authored front")
core.X,core.Z=x,z
local ix,iz,investigate=habit:lead(core,31,0,nav,nil)
assert(ix==-90 and iz==-56 and investigate=="physical-garage-investigation"
 and habit.PredictionMisses==0,"front-to-interior check failed")
return game:GetService("HttpService"):JSONEncode({ok=true,visits=habit.Visits,
 visibleCorridorRays=rays,front={x,z},interior={ix,iz},
 reason=reason,physicalInvestigation=investigate,source=habitSrc:GetFullName()})
