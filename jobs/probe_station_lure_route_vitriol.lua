-- Guarded read-only test of the SECOND reported stall: inside garage to station.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Wrong place/mode")
local src=game:GetService("ServerStorage").Vitriol.Creature.GarageNavigation.Source
local nav=assert(loadstring(src))().new(workspace.Map,workspace)
local station=workspace.Map.Interactions.Station_Floodlight
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local x,z=nav:route(-86.1,-71.4,station.Position.X,station.Position.Z,params,0)
local hit=nav:hit(-86.1,-71.4,station.Position.X,station.Position.Z,params)
return game:GetService("HttpService"):JSONEncode({ok=x~=nil,firstX=x,firstZ=z,
    block=hit and hit.Instance:GetFullName() or "clear"})
