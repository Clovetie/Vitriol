-- READ ONLY/Edit: compile exact CreatureService Source and ray-check the
-- actual authored Garage door. Full service ray reuse is tested headlessly;
-- this source/geometry probe does not run server Bootstrap or spawn prey.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local ss=game:GetService("ServerStorage").Vitriol
local source=ss.Services.CreatureService
assert(source:IsA("ModuleScript"),"CreatureService class wrong")
local make,err=loadstring(source.Source)
assert(make,err or "CreatureService Source did not compile")
assert(string.find(source.Source,"best, bestPlayer, bestSq, bestClear = root, player, distanceSq, clear",1,true)
 and string.find(source.Source,"if sensedClear == nil then",1,true),
 "actual Studio Source lacks the sensor-result / legacy-fallback guard")
local nav=assert(assert(loadstring(ss.Creature.GarageNavigation.Source))().new(workspace.Map,workspace))
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local hit=nav:hit(-55,-56,-65,-56,params)
assert(hit==nil,"actual authored Garage entrance no longer permits the real sight ray")
return game:GetService("HttpService"):JSONEncode({ok=true,
 source=source:GetFullName(),realDoorSight={-55,-56,-65,-56},
 physicalRay="clear",safetyFallback="present",editOnly=true})
