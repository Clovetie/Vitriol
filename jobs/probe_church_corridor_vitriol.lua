-- Guarded read-only rays for west wall -> south/front opening -> bell.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Wrong place/mode")
local body=workspace.Map.Structures.Church_BellTower.Body
local b=body.Position
local west=b.X-body.Size.X*.5-8
local east=b.X+body.Size.X*.5+8
local front=b.Z+body.Size.Z*.5+11
local a=Vector3.new(83.8,4,-207.5)
local w=Vector3.new(west,4,front)
local e=Vector3.new(east,4,front)
local door=Vector3.new(b.X,4,front)
local lever=assert(workspace.Map.Interactions:FindFirstChild("Church_BellLever"))
assert(lever:IsA("BasePart"),"authored lever missing")
local bell=Vector3.new(lever.Position.X,4,lever.Position.Z)
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local function hit(x,y)
 local r=workspace:Raycast(x,y-x,params)
 return r and r.Instance:GetFullName() or "clear"
end
return game:GetService("HttpService"):JSONEncode({west=west,east=east,front=front,
 fromWest=hit(a,w),sideToDoor=hit(w,door),doorToBell=hit(door,bell),
 eastToDoor=hit(e,door)})
