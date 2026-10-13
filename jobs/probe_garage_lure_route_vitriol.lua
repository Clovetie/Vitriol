-- Guarded read-only horizontal geometry probe at the player's stall coords.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Wrong place/mode")
local f=workspace.Map.Structures.Millers_Garage.Floor
local gen=workspace.Map.Interactions.Garage_Generator
local cx,cz=f.Position.X,f.Position.Z
local east=cx+f.Size.X*.5+7
local west=cx-f.Size.X*.5-7
local north=cz-f.Size.Z*.5-7
local south=cz+f.Size.Z*.5+7
local nodes={{east,cz},{east,north},{west,north},{west,cz},{west,south},{east,south}}
local origin=Vector3.new(45.5,4,-137.4)
local target=Vector3.new(gen.Position.X,4,gen.Position.Z)
local params=RaycastParams.new() -- read-only temporary query value, no Instance
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local function ray(a,b)
 local hit=workspace:Raycast(a,b-a,params)
 return hit and hit.Instance:GetFullName() or "clear"
end
local result={coreToGenerator=ray(origin,target), nodes={},generator=gen:GetFullName()}
for index,node in ipairs(nodes) do
 local p=Vector3.new(node[1],4,node[2])
 result.nodes[index]={x=node[1],z=node[2],fromCore=ray(origin,p),toGenerator=ray(p,target)}
end
return game:GetService("HttpService"):JSONEncode(result)
