-- READ ONLY: fresh-compile exact Studio InstinctSearch Source and walk one
-- whole local circuit to a REAL road-derived second region; never move Parts.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play for Edit source probe")
local source=game:GetService("ServerStorage").Vitriol.Creature.Brain.InstinctSearch
assert(source:IsA("ModuleScript"),"InstinctSearch class mismatch")
local make,err=loadstring(source.Source)
assert(make,err or "InstinctSearch compile failed")
local search=make().new({PatrolRadiusStuds=24,RegionArriveStuds=12},workspace.Map)
local road=workspace.Map.Roads.Road_Main
assert(search.RoadStops and #search.RoadStops==4 and road.Size.Z>580,
 "Real user-extended road not used as region source")
local navSource=game:GetService("ServerStorage").Vitriol.Creature.GarageNavigation
local loadNav,navError=loadstring(navSource.Source)
assert(loadNav,navError or "GarageNavigation compile failed")
local nav=loadNav().new(workspace.Map,workspace)
local ray=RaycastParams.new()
ray.FilterType=Enum.RaycastFilterType.Exclude
ray.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local b={X=road.Position.X,Y=8,Z=road.Position.Z,RaycastParams=ray}
local x,y,z=search:next(b,0,nav,nil)
assert(x and b.SearchMode=="patrol","No-clue local patrol missing")
for i=1,4 do
 b.X,b.Z=x,z
 x,y,z=search:next(b,i,nav,nil)
end
assert(x and b.SearchMode=="transit" and math.abs(x-road.Position.X)<.1,
 "Did not change region after one complete local circuit")
local destination=z
b.X,b.Z=x,z
x,y,z=search:next(b,5,nav,nil)
assert(x and b.SearchMode=="patrol","New region did not resume local search")
for i=1,4 do b.X,b.Z=x,z;x,y,z=search:next(b,5+i,nav,nil) end
assert(x and b.SearchMode=="transit" and math.abs(z-destination)>20,
 "Next circuit repeated same region")
return game:GetService("HttpService"):JSONEncode({ok=true,roadLength=road.Size.Z,
 roadCenter=road.Position.Z,firstRegion=destination,nextRegion=z,
 source=source:GetFullName()})
