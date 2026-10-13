-- Guarded read-only direct execution of FINAL Studio source against actual map.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Wrong place/mode")
local src=game:GetService("ServerStorage").Vitriol.Creature.GarageNavigation.Source
local nav=assert(loadstring(src))().new(workspace.Map,workspace)
assert(nav,"Authored garage unavailable")
local target=workspace.Map.Interactions.Garage_Generator
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local x,z=nav:route(45.5,-137.4,target.Position.X,target.Position.Z,params,0,target)
assert(x==-55 and z==-56,"No safe route to actual garage feed")
return game:GetService("HttpService"):JSONEncode({ok=true,firstX=x,firstZ=z})
