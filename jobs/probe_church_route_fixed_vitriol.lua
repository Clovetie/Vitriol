-- Guarded read-only FRESH compiled Studio source against user's UnionOperation.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Wrong place/mode")
local src=game:GetService("ServerStorage").Vitriol.Creature.ChurchNavigation.Source
local nav=assert(loadstring(src))().new(workspace.Map,workspace)
assert(nav,"Church Body missing")
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local p=workspace.Map.Interactions.Church_BellLever.Position
local bell=workspace.Map.Interactions.Bell.Bell
local a,b=nav:route(83.8,-207.5,p.X,p.Z,params,bell)
local c,d=nil,nil
if a and b then c,d=nav:route(a,b,p.X,p.Z,params,bell) end
local e,f=nil,nil
if c and d then e,f=nav:route(c,d,p.X,p.Z,params,bell) end
local ok=a and b and c and d and e and f and math.abs(a-86.25)<.1 and math.abs(b+130.25)<.1
    and math.abs(c-119)<.1 and math.abs(d+130.25)<.1
    and math.abs(e-p.X)<.1 and math.abs(f-p.Z)<.1
local sideDirect=a and nav:hit(a,b,p.X,p.Z,params)
local sideDoor=a and nav:hit(a,b,nav.Middle,nav.Front,params)
return game:GetService("HttpService"):JSONEncode({ok=ok==true,side={a,b},door={c,d},bell={e,f},
 sideDirect=sideDirect and sideDirect.Instance:GetFullName() or "clear",
 sideDoor=sideDoor and sideDoor.Instance:GetFullName() or "clear"})
