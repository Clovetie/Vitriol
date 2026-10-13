-- READ ONLY Vitriol/Edit: ground/overhead surface samples around reported
-- House_01 ingress stalls. NO active Braid pose, movement or Y was captured.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local h=assert(workspace.Map.Structures:FindFirstChild("House_01"))
local roof=assert(h:FindFirstChild("PorchRoof"))
local floor=assert(h:FindFirstChild("Floor"))
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local function hit(origin,delta)
 local r=workspace:Raycast(origin,delta,params)
 return r and {path=r.Instance:GetFullName(),y=r.Position.Y} or {path="clear"}
end
local samples={}
for _,pos in ipairs({{-54.5,72.2},{-53.6,72.2},{-60,72},{-65,72},{-73,72},{-79,72},{-84.5,73.5},{-72.1,67.2}}) do
 local x,z=pos[1],pos[2]
 samples[#samples+1]={x=x,z=z,
  belowY9=hit(Vector3.new(x,9,z),Vector3.new(0,-30,0)),
  belowY14=hit(Vector3.new(x,14,z),Vector3.new(0,-35,0)),
  overheadFromY4=hit(Vector3.new(x,4,z),Vector3.new(0,16,0))}
end
local p,s=roof.Position,roof.Size
local fp,fs=floor.Position,floor.Size
return game:GetService("HttpService"):JSONEncode({ok=true,editOnly=true,
 originalPorchRoof={p.X,p.Y,p.Z,s.X,s.Y,s.Z},
 originalFloor={fp.X,fp.Y,fp.Z,fs.X,fs.Y,fs.Z},
 samples=samples,studioWritten=false,playCaptured=false,
 caveat="X/Z supplied by Output only; cannot identify live core Y, foot anchors or cause of spasming"})
