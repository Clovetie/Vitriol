-- READ ONLY. Survey authored road-derived regional targets before changing
-- patrol routing. Does not move Braid, Players, props or Studio geometry.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before survey")
local map=workspace:FindFirstChild("Map")
local roads=map and map:FindFirstChild("Roads")
local road=roads and roads:FindFirstChild("Road_Main")
assert(road and road:IsA("BasePart"),"User Road_Main missing")
local navSource=game:GetService("ServerStorage").Vitriol.Creature.GarageNavigation
local make,err=loadstring(navSource.Source)
assert(make,err or "GarageNavigation compile failed")
local nav=assert(make().new(map,workspace),"Authored garage navigation unavailable")
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local stops={}
for _,fraction in ipairs({-.33,-.12,.12,.33}) do
 stops[#stops+1]={road.Position.X,road.Position.Z+road.Size.Z*fraction}
end
local rows={}
for _,p in ipairs({{"Road",0,0},{"GarageInside",-90,-56},
 {"House01Inside",-91,77},{"House02Inside",101,67},
 {"ChurchExterior",75,-120}}) do
 local row={name=p[1],origin={p[2],p[3]},visible={}}
 for i,node in ipairs(stops) do
  row.visible[i]=nav:clear(p[2],p[3],node[1],node[2],params)
 end
 rows[#rows+1]=row
end
return game:GetService("HttpService"):JSONEncode({ok=true,
 road={road.Position.X,road.Position.Z,road.Size.Z},stops=stops,rows=rows})
