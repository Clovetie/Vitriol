-- Vitriol/Edit READ ONLY: diagnose user's inside-after-closet-break report.
-- Load current Studio Source; never relocate furniture or run a Play simulation.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local src=game:GetService("ServerStorage").Vitriol
local searchMake=assert(loadstring(src.Creature.Brain.InstinctSearch.Source))
local houseMake=assert(loadstring(src.Creature.HouseAccess.Source))
local navMake=assert(loadstring(src.Creature.GarageNavigation.Source))
local map=workspace.Map
local search=searchMake().new({RegionArriveStuds=12,StallSeconds=3},map)
local house=houseMake().new(map)
local nav=navMake().new(map,workspace)
local p=RaycastParams.new();p.FilterType=Enum.RaycastFilterType.Exclude
p.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local creature={X=-91,Y=8,Z=77,RaycastParams=p,SearchMode="transit",SearchIndex=5}
local tx,ty,tz=search:next(creature,30,nav,nil)
local hx,hy,hz=house:route(-91,8,77,-57.5,2,78.9,1.5)
local marker=map.Interactions.HouseCoverTargets:FindFirstChild("House_01_ClosetTarget")
assert(marker and marker.Position.X==-81.5 and marker.Position.Z==77,"House_01 doorway moved")
local door=house.Houses[1]
assert(door.Name=="House_01","House_01 missing")
local hit=nav:hit(-91,77,0,77,p)
return game:GetService("HttpService"):JSONEncode({ok=true,editOnly=true,
 inside={-91,8,77},door={door.DoorX,door.DoorZ},closetMarker={marker.Position.X,marker.Position.Z},
 outsidePreyHouseRoute={hx,hy,hz},postCircuitGoal={tx,ty,tz},
 mode=creature.SearchMode,searchIndex=creature.SearchIndex,
 roadLineBlock=hit and hit.Instance:GetFullName() or nil})
