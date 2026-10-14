-- Guarded read-only survey at reported bell stall; user church untouched.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Wrong place/mode")
local church=workspace.Map.Structures:FindFirstChild("Church_BellTower")
local lever=workspace.Map.Interactions:FindFirstChild("Church_BellLever")
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local origin=Vector3.new(83.8,4,-207.5)
local goal=Vector3.new(lever.Position.X,4,lever.Position.Z)
local ray=workspace:Raycast(origin,goal-origin,params)
local buildings={}
for _,p in ipairs(church and church:GetDescendants() or {}) do
 if p:IsA("BasePart") and (p.Position-Vector3.new(119,4,-205)).Magnitude<120 then
  buildings[#buildings+1]={name=p.Name,pos=tostring(p.Position),size=tostring(p.Size),canCollide=p.CanCollide}
 end
end
return game:GetService("HttpService"):JSONEncode({origin=tostring(origin),goal=tostring(goal),
 hit=ray and ray.Instance:GetFullName() or "clear", hitPosition=ray and tostring(ray.Position) or nil,
 hitDistance=ray and (ray.Position-origin).Magnitude or nil,church=church and church:GetFullName() or nil,
 buildings=buildings})
