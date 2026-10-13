-- READ ONLY Edit: actual House_02 original closet + table, marker and
-- doorway. Simulate PLACED only in Lua state; never move a Studio Part.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local src=game:GetService("ServerStorage").Vitriol.Services.HouseCoverService
assert(src:IsA("ModuleScript"),"HouseCoverService must be authored ModuleScript")
local make,err=loadstring(src.Source)
assert(make,err or "HouseCoverService Source failed compile")
local cover=setmetatable({},make())
cover:init({Workspace=workspace,Players=game:GetService("Players"),Health={states={}},
 Time={phase="Night"},Session={state="Running"}})
local closet=assert(cover.ByAction.CoverHouse02Closet)
local tablePiece=assert(cover.ByAction.CoverHouse02Table)
local x,z=closet.Target.Position.X,closet.Target.Position.Z
local tx,tz=tablePiece.Target.Position.X,tablePiece.Target.Position.Z
assert(x==111.5 and z==67 and tx==x and tz==58.5,
 "House_02 markers changed; re-survey before relying on this egress")
assert(closet.Part.Position.X==79 and closet.Part.Position.Z==72
 and tablePiece.Part.Position.X==93 and tablePiece.Part.Position.Z==62,
 "House_02 original pieces moved in Edit; do not overwrite user geometry")
closet.Placed=true;tablePiece.Placed=true -- Lua flags ONLY, actual Parts remain home
cover.activeCount=2
local inside,outside=x-10.2,x+23
assert(cover:intercept(inside,z,outside,z)==closet
 and cover:bracing(inside,z,outside,z,true)==closet,
 "physical House_02 inside→outside closet contact/bracing failed")
assert(cover:bracing(outside,z,inside,z,true)==nil,
 "outside-to-inside lure must not be an authorized reverse breach")
assert(cover:intercept(inside,tz,outside,tz)==tablePiece,
 "House_02 table crossing did not select its own original Part")
assert(cover:intercept(inside,63.5,outside,63.5)==nil,
 "genuine one-stud gap between the original pieces was fictitiously sealed")
local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local hit=workspace:Raycast(Vector3.new(inside,4,z),Vector3.new(outside-inside,0,0),params)
assert(hit==nil,"House_02 original east door/closet lane is structurally obstructed")
return game:GetService("HttpService"):JSONEncode({ok=true,
 closet=closet.Part:GetFullName(),tablePiece=tablePiece.Part:GetFullName(),
 doorway={x,z},reverse={inside,z,outside,z},tableLane=tz,uncoveredGapZ=63.5,
 originalCloset={closet.Part.Position.X,closet.Part.Position.Z},
 originalTable={tablePiece.Part.Position.X,tablePiece.Part.Position.Z},ray="clear"})
