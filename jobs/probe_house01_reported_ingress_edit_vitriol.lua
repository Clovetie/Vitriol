-- READ ONLY Vitriol/Edit: evaluate exactly the reported X/Z stalls against
-- existing HouseAccess Source and authored House_01 geometry. Logged Y was
-- NOT supplied; sample explicit hypothetical Y values, never claim Play pose.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local src=game:GetService("ServerStorage").Vitriol.Creature
local houseSource=assert(src:FindFirstChild("HouseAccess"))
local garageSource=assert(src:FindFirstChild("GarageNavigation"))
assert(houseSource:IsA("ModuleScript") and garageSource:IsA("ModuleScript"),"Source class mismatch")
local house=assert(assert(loadstring(houseSource.Source))().new(workspace.Map))
local nav=assert(assert(loadstring(garageSource.Source))().new(workspace.Map,workspace))
local h=house.Houses[1]
assert(h.Name=="House_01" and math.abs(h.DoorX+79)<.01,"authored House_01 door changed")
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local function ray(ax,az,bx,bz)
 local hit=nav:hit(ax,az,bx,bz,params)
 return hit and hit.Instance:GetFullName() or "clear"
end
local function sample(kind,cx,cz,tx,tz)
 local rows={}
 for _,y in ipairs({8,10,14,20}) do
  local inside=house:houseForPrey(tx,3,tz)
  local hx,hy,hz,cap=house:route(cx,y,cz,tx,3,tz,1.5)
  rows[#rows+1]={hypotheticalCoreY=y,goalInsideHouse=inside and inside.Name or "none",
   route= hx and {hx,hy,hz} or nil,waypointRay=hx and ray(cx,cz,hx,hz) or nil,
   heightCap=cap}
 end
 return {kind=kind,reportedCore={cx,cz},reportedGoal={tx,tz},
  directGroundRay=ray(cx,cz,tx,tz),samples=rows}
end
local old=sample("LastKnown",-54.5,72.2,-84.5,73.5)
local prey=sample("Prey",-53.6,72.2,-72.1,67.2)
return game:GetService("HttpService"):JSONEncode({ok=true,editOnly=true,
 door={h.DoorX,h.DoorZ},porch={h.Porch.Position.X,h.Porch.Position.Z,h.Porch.Size.X,h.PorchBottom},
 lowerRoof={h.LintelBottom,h.PorchBottom},sampled={old,prey},
 sourceOrGeometryWritten=false,playCaptured=false,
 warning="Output contains X/Z only; these Y values are hypothetical and cannot identify the live blocker"})
