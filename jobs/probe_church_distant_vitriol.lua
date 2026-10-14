-- Guarded read-only second church stall: remote Braid ray hits a window union.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Wrong place/mode")
local src=game:GetService("ServerStorage").Vitriol.Creature.ChurchNavigation.Source
local nav=assert(loadstring(src))().new(workspace.Map,workspace)
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local a=Vector3.new(-38.4,4,-48.1)
local lever=assert(workspace.Map.Interactions:FindFirstChild("Church_BellLever"))
assert(lever:IsA("BasePart"),"authored lever missing")
local target=Vector3.new(lever.Position.X,4,lever.Position.Z)
local west=Vector3.new(nav.Left,4,nav.Front)
local east=Vector3.new(nav.Right,4,nav.Front)
local door=Vector3.new(nav.Middle,4,nav.Front)
local function ray(x,y)
 local h=workspace:Raycast(x,y-x,params)
 return h and h.Instance:GetFullName() or "clear"
end
local windows=workspace:FindFirstChild("ChurchWindows")
return game:GetService("HttpService"):JSONEncode({windows=windows and windows.ClassName or "missing",
 direct=ray(a,target),towardDoor=ray(a,door),towardWest=ray(a,west),towardEast=ray(a,east),
 westToDoor=ray(west,door),eastToDoor=ray(east,door),
 route={nav:route(a.X,a.Z,target.X,target.Z,params,workspace.Map.Interactions.Bell.Bell)}})
