-- Read-only fresh compilation of the EXACT synced Studio source against the
-- authored foundation. No ModuleScript require cache, prompt/property mutation,
-- world Instance or Play object is created by this Edit-mode probe.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before source probe")
local storage=game:GetService("ServerStorage")
local source=storage.Vitriol.Creature.Brain:FindFirstChild("InstinctSearch")
assert(source and source:IsA("ModuleScript"),"InstinctSearch wrong class/missing")
local make,err=loadstring(source.Source)
assert(make,err or "Fresh InstinctSearch compile failed")
local policy=make().new({SweepRadiusStuds=10,PatrolRadiusStuds=24},workspace.Map)
assert(policy.Bounds and policy.Bounds.minX<-280 and policy.Bounds.maxX>280,
 "Authored foundation is missing or no longer covers patrol")
local c={X=0,Y=8,Z=0}
local navigation={clear=function() return true end}
local x,y,z=policy:next(c,0,navigation,nil)
assert(x==24 and y==8 and z==0 and c.SearchMode=="patrol","No-clue Night patrol")
policy:note(c,8,8,0,1)
c.X=8
x,y,z=policy:next(c,1,navigation,nil)
assert(c.SearchMode=="sweep" and x==18 and z==0,"Real clue sweep")
policy:reset(c)
c.X,c.Z=0,0
local cover={activeCount=1,intercept=function(_,_,_,tx) return tx==24 end}
x,y,z=policy:next(c,2,navigation,cover)
assert(x==0 and z==24,"Placed furniture blocks patrol route")
local edge={X=policy.Bounds.maxX-3,Y=8,Z=0}
x,y,z=policy:next(edge,3,navigation,nil)
assert(x and x<=policy.Bounds.maxX and math.abs(z)<=24,
 "Patrol goal beyond the existing foundation")
return game:GetService("HttpService"):JSONEncode({ok=true,
 source=source:GetFullName(),patrol={0,24},sweep={18,0},
 bounds={policy.Bounds.minX,policy.Bounds.maxX,policy.Bounds.minZ,policy.Bounds.maxZ}})
