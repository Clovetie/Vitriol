-- READ ONLY/Edit: are thin, clear road rays from grounded House_01 interiors
-- actually passing the author's east doorway? No furniture or Source edits.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local map=workspace.Map
local house=map.Structures.House_01
local navMake=assert(loadstring(game:GetService("ServerStorage").Vitriol.Creature.GarageNavigation.Source))
local searchMake=assert(loadstring(game:GetService("ServerStorage").Vitriol.Creature.Brain.InstinctSearch.Source))
local nav=navMake().new(map,workspace)
local search=searchMake().new({RegionArriveStuds=12,StallSeconds=3},map)
local p=RaycastParams.new();p.FilterType=Enum.RaycastFilterType.Exclude
p.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local sides={}
for _,name in ipairs({"EastPier_-13","EastPier_13","EastLintel","Floor","Roof","PorchRoof"}) do
 local part=house:FindFirstChild(name)
 if part then sides[#sides+1]={name,part.Position.X,part.Position.Y,part.Position.Z,
  part.Size.X,part.Size.Y,part.Size.Z} end
end
local rows={}
for _,x in ipairs({-103,-91,-84}) do
 for _,z in ipairs({65,72,77,79,84}) do
  local c={X=x,Y=8,Z=z,RaycastParams=p,SearchMode="transit",SearchIndex=5}
  local tx,_,tz=search:next(c,30,nav,nil)
  local crossed=nil
  if tx and tx>x then
   local t=(house:FindFirstChild("EastPier_-13").Position.X-x)/(tx-x)
   crossed=z+(tz-z)*t
  end
  rows[#rows+1]={x,z,tx,tz,crossed,c.SearchMode}
 end
end
return game:GetService("HttpService"):JSONEncode({ok=true,editOnly=true,
 geometry=sides,samples=rows})
