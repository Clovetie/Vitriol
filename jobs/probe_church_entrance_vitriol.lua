-- Guarded read-only rays across existing church front; do NOT change mesh.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Wrong place/mode")
local m=workspace.Map.Structures.Church_BellTower
local body=m:FindFirstChild("Body")
local lever=workspace.Map.Interactions.Church_BellLever
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local rays={}
for _,x in ipairs({103,109,113,116,119,122,125,129,135}) do
 local a=Vector3.new(x,4,-128)
 local b=Vector3.new(x,4,-202)
 local hit=workspace:Raycast(a,b-a,params)
 rays[#rays+1]={x=x,hit=hit and hit.Instance:GetFullName() or "clear",
  point=hit and tostring(hit.Position) or nil}
end
return game:GetService("HttpService"):JSONEncode({body=body and body.ClassName or "missing",
 collisionFidelity=body and body:IsA("MeshPart") and tostring(body.CollisionFidelity) or "n/a",
 mainDoor=lever.Position.Z,rays=rays})
