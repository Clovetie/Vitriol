-- READ ONLY/Edit: compile exact Studio navigation + service Sources and
-- compare known-obstruction detour with the original independently checked
-- detour on the real Garage. No world mutation, no Play-cost claim.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local vitriol=game:GetService("ServerStorage").Vitriol
local navSrc=vitriol.Creature.GarageNavigation
local service=vitriol.Services.CreatureService
assert(navSrc:IsA("ModuleScript") and service:IsA("ModuleScript"),"wrong script class")
local navMake,err=loadstring(navSrc.Source)
assert(navMake,err or "nav Source cannot compile")
assert(loadstring(service.Source),"CreatureService Source cannot compile")
assert(string.find(service.Source,"now, endpoint, hit",1,true)
 and string.find(service.Source,"now, nil, sensedHit",1,true),
 "service no longer hands the measured obstruction to exact same-segment route")
local nav=assert(navMake().new(workspace.Map,workspace))
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local hit=nav:hit(-90,-56,-145,-56,params)
assert(hit and hit.Instance,"real Garage rear ray did not see a physical blocker")
local x,z=nav:route(-90,-56,-145,-56,params,1,nil,hit)
assert(x==-55 and z==-56,"known real obstruction did not select the authored front detour")
nav.Cache=nil
local oldX,oldZ=nav:route(-90,-56,-145,-56,params,1)
assert(oldX==x and oldZ==z,"reused actual hit changed the established waypoint")
return game:GetService("HttpService"):JSONEncode({ok=true,
 blocker=hit.Instance:GetFullName(),waypoint={x,z},sameAsOriginal=true,
 service=service:GetFullName(),navigation=navSrc:GetFullName(),editOnly=true})
