-- READ ONLY: fresh Studio navigation + search Sources against real authored
-- walls/road/house doorways. No world property is written in Edit mode.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before geometry probe")
local src=game:GetService("ServerStorage").Vitriol
local function fresh(module)
 assert(module and module:IsA("ModuleScript"),"Missing/wrong class module")
 local make,err=loadstring(module.Source)
 assert(make,err or "Source compilation failed")
 return make()
end
local nav=fresh(src.Creature.GarageNavigation).new(workspace.Map,workspace)
local search=fresh(src.Creature.Brain.InstinctSearch).new({PatrolRadiusStuds=24},workspace.Map)
assert(nav and search and search.Bounds,"Missing authored map navigation/foundation")
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local rows={}
for _,spec in ipairs({{"Road",0,0},{"GarageInside",-90,-56},
 {"House01Inside",-91,77},{"House02Inside",101,67}}) do
 local name,x,z=spec[1],spec[2],spec[3]
 local body={X=x,Y=8,Z=z,RaycastParams=params}
 local tx,_,tz=search:next(body,0,nav,nil)
 rows[#rows+1]={name=name,origin={x,z},mode=body.SearchMode,
  goal=tx and {tx,tz} or nil,firstBlocked=not nav:clear(x,z,x+24,z,params)}
end
return game:GetService("HttpService"):JSONEncode({ok=true,rows=rows})
