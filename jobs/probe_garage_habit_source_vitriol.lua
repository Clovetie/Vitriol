-- READ ONLY Edit: compile freshly synced Studio Sources, use real authored
-- Garage floor/door and one real clearance ray. No Braid/player/Part changes.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local vitriol=game:GetService("ServerStorage").Vitriol
local brain=vitriol.Creature.Brain.GarageHabit
assert(brain:IsA("ModuleScript"),"GarageHabit must be authored ModuleScript")
local make,err=loadstring(brain.Source)
assert(make,err or "GarageHabit Source failed to compile")
local configMake,configErr=loadstring(game:GetService("ReplicatedStorage").Vitriol.Config.MonsterConfig.Source)
assert(configMake,configErr or "MonsterConfig Source failed to compile")
local config=configMake()
local navMake,navErr=loadstring(vitriol.Creature.GarageNavigation.Source)
assert(navMake,navErr or "GarageNavigation Source failed to compile")
local nav=assert(navMake().new(workspace.Map,workspace),"Authored Garage route missing")
local serviceMake,serviceErr=loadstring(vitriol.Services.CreatureService.Source)
assert(serviceMake,serviceErr or "CreatureService Source failed to compile")
local habit=make().new(config.Memory,nav,config.InstinctSearch)
local floor=workspace.Map.Structures.Millers_Garage.Floor
local x,z=nav.Nodes[1][1],nav.Nodes[1][2]
assert(x==-55 and z==-56 and floor.Size.X==56 and floor.Size.Z==46,
 "Authored garage changed; re-survey before claiming route")
local outsideX=floor.Position.X+floor.Size.X/2+7
local garageRoof=workspace.Map.Structures.Millers_Garage.Roof
local continuous=make().new(config.Memory,nav,config.InstinctSearch)
assert(not continuous:observe(92,outsideX,4,floor.Position.Z))
continuous:markUnseenExcept(nil)
assert(not continuous:observe(92,floor.Position.X,4,floor.Position.Z)
 and continuous.Visits==0,"Unseen travel to Garage interior fabricated a visit")
assert(not continuous:observe(92,outsideX,4,floor.Position.Z))
assert(not continuous:observe(92,floor.Position.X,garageRoof.Position.Y,floor.Position.Z)
 and continuous.ObservedInside[92]==nil,"Roof sighting was mistaken for grounded outside evidence")
assert(not continuous:observe(92,floor.Position.X,4,floor.Position.Z)
 and continuous.Visits==0,"Roof-to-interior drop fabricated a witnessed entry")
assert(not continuous:observe(92,outsideX,4,floor.Position.Z))
assert(continuous:observe(92,floor.Position.X,4,floor.Position.Z)
 and continuous.Visits==1,"Real continuous Garage entry no longer trains")
for i=1,3 do
 assert(not habit:observe(91,outsideX,4,floor.Position.Z))
 assert(habit:observe(91,floor.Position.X,4,floor.Position.Z))
end
assert(habit.Visits==3 and habit:dump().predictsGarage,"witnessed entry count failed")
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local c={X=0,Y=8,Z=0,RaycastParams=params}
local goalX,goalZ,why=habit:lead(c,30,0,nav,nil)
assert(goalX==x and goalZ==z and why=="witnessed-three-garage-entries",
 "Real road to authored Garage front isn't a safe clue-less candidate")
assert(nav:clear(c.X,c.Z,goalX,goalZ,params),"Garage front ray unexpectedly obstructed")
c.X,c.Z=goalX,goalZ
local interiorX,interiorZ,investigate=habit:lead(c,31,0,nav,nil)
assert(interiorX==floor.Position.X and interiorZ==floor.Position.Z
 and investigate=="physical-garage-investigation" and habit.PredictionMisses==0,
 "Exterior Garage visit falsely declared room empty")
assert(nav:clear(c.X,c.Z,interiorX,interiorZ,params),
 "User-owned Garage interior is not physically accessible from front")
c.X,c.Z=interiorX,interiorZ
local _,_,arrival=habit:lead(c,32,0,nav,nil)
assert(arrival=="arrived" and habit.PredictionMisses==1
 and habit:dump().effectiveEvidence==2,"Physical but unproductive visit did not reduce belief")
c.X,c.Z=0,0
local absent=habit:lead(c,32,1,nav,nil)
assert(absent==nil and not habit:dump().predictsGarage,"Empty prediction repeats every Night")
assert(not habit:observe(91,outsideX,4,floor.Position.Z))
assert(habit:observe(91,floor.Position.X,4,floor.Position.Z))
local renewedX=habit:lead(c,33,1,nav,nil)
assert(renewedX==goalX and habit:dump().effectiveEvidence==3,
 "New actual sighting did not restore Garage expectation")
local roof=workspace.Map.Structures.Millers_Garage.Roof
local roofCore={X=floor.Position.X,Y=roof.Position.Y+3,Z=floor.Position.Z,RaycastParams=params}
local blockedX,_,blockedReason=habit:lead(roofCore,34,2,nav,nil)
assert(blockedX==nil and blockedReason=="blocked" and habit.PredictionMisses==1
 and habit.CoreCeilingY<roof.Position.Y-roof.Size.Y/2,
 "Garage ROOF must not masquerade as a physical interior check")
return game:GetService("HttpService"):JSONEncode({ok=true,visits=habit.Visits,
 misses=habit.PredictionMisses,effective=habit:dump().effectiveEvidence,
 entry={goalX,goalZ},floor={floor.Position.X,floor.Position.Z,floor.Size.X,floor.Size.Z},
 source=brain:GetFullName()})
