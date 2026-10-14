-- WP6 Night search: actual source policy, no created Path/Part or hidden GPS.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1;print("PASS  "..msg)
 else SESSION.failed=SESSION.failed+1;print("FAIL  "..msg) end
end
local Search=VitriolRequire("InstinctSearch")
local policy=Search.new({ClueSeconds=25,ClueReachStuds=32,SweepRadiusStuds=10,
 PatrolRadiusStuds=24,ArriveStuds=5,StallSeconds=3},nil)
local b={X=0,Y=8,Z=0}
local calls=0
local nav={clear=function() calls=calls+1;return true end}
local x,y,z=policy:next(b,0,nav,nil)
check(b.SearchMode=="patrol" and x==24 and y==8 and z==0,
 "without a clue the Night Braid picks a bounded local patrol, not a player location")
local prevCalls=calls
x,y,z=policy:next(b,1,nav,nil)
check(x==24 and z==0 and calls==prevCalls,
 "holding a reachable waypoint does not rescan world rays every Think")
b.X=24
x,y,z=policy:next(b,1.2,nav,nil)
check(x==0 and z==24 and b.SearchMode=="patrol",
 "reaching the first point advances to a distinct patrol waypoint")
local goalX,goalZ=x,z
for _=1,4 do b.X,b.Z=goalX,goalZ;goalX,_,goalZ=policy:next(b,2,nav,nil) end
check(goalX~=nil and b.SearchMode=="patrol" and math.abs(goalX)<=24
 and math.abs(goalZ)<=24,"patrol loops within its fixed 24-stud region instead of walking out of the map")
policy:note(b,30,8,0,3)
b.X,b.Z=30,0
x,y,z=policy:next(b,3,nav,nil)
check(b.SearchMode=="sweep" and x==40 and z==0,
 "a genuinely noted clue replaces patrol with a short local sweep")
local firstSweep=x
for _=1,4 do b.X,b.Z=x,z;x,y,z=policy:next(b,4,nav,nil) end
check(b.SearchMode=="patrol" and x~=nil and x~=firstSweep,
 "four bounded clue checks hand back to patrol without persistent exact-prey GPS")
policy:note(b,100,8,0,5)
b.X,b.Z=0,0
x,y,z=policy:next(b,5,nav,nil)
check(b.SearchMode=="patrol" and x==24,
 "far-away old clue cannot teleport the patrol toward a hidden survivor")
policy:note(b,5,8,0,6)
b.X,b.Z=0,0
x,y,z=policy:next(b,32,nav,nil)
check(b.SearchMode=="patrol" and x==24,
 "expired sensory clue does not remain a lifelong tracking target")
policy:reset(b)
check(b.SearchMode==nil and b.SearchClueAt==nil and b.SearchGoalX==nil,
 "Dawn reset clears both clue and selected search goal")
local blocked={clear=function(_,_,_,tx,tz) calls=calls+1;return tx~=24 end}
b.X,b.Z=0,0
x,y,z=policy:next(b,0,blocked,nil)
check(x==0 and z==24,
 "a blocked first waypoint is skipped for another reachable patrol direction")
policy:reset(b)
local cover={activeCount=1,intercept=function(_,_,_,tx,tz) return tx==24 end}
x,y,z=policy:next(b,0,nav,cover)
check(x==0 and z==24,
 "search cannot cross installed furniture without valid break authority")
policy:reset(b)
local none={clear=function() calls=calls+1;return false end}
x,y,z=policy:next(b,0,none,nil)
check(x==nil and b.SearchIndex==3,
 "inaccessible area degrades safely after at most two ray candidates per Think")
x,y,z=policy:next(b,.2,none,nil)
check(x==nil and b.SearchIndex==5,
 "next Think tries the other directions instead of phasing through walls")
policy:reset(b)
b.X,b.Z=0,0
x,y,z=policy:next(b,0,nav,nil)
x,y,z=policy:next(b,3.1,nav,nil)
check(x==0 and z==24,
 "after three seconds without physical progress the Braid tries another patrol direction")
local floor={Position={X=0,Z=0},Size={X=100,Z=100},IsA=function(_,class) return class=="BasePart" end}
local ground={FindFirstChild=function(_,name) return name=="Ground_QuarryFoundation" and floor end}
local map={FindFirstChild=function(_,name) return name=="Ground" and ground end}
local bounded=Search.new({},map)
local edge={X=40,Y=8,Z=0}
x,y,z=bounded:next(edge,0,nav,nil)
check(x~=nil and math.abs(x)<=42 and math.abs(z)<=42,
 "authored foundation bounds prevent a local patrol goal beyond the map edge")
local R=VitriolRequire("Bootstrap").ensure()
local p=R.Players:addPlayer("DistantSurvivor",94001)
local live=R.Creature.creatures[R.Creature.order[1]]
local root=p.Character:FindFirstChild("HumanoidRootPart")
root.Position={X=live.X+300,Y=live.Y,Z=live.Z+300}
R.Time.phase="Night";R.Creature:think(.2)
check(live.TargetX~=nil and live.SearchMode=="patrol"
 and live.TargetX~=root.Position.X and not live.CoverExitIntent,
 "real Night CreatureService keeps hunting without an omniscient prey target")
R.Time.phase="Day";R.Creature:think(.2)
check(live.Dormant and live.TargetX==nil and live.SearchMode==nil,
 "Day prep still withdraws the Braid and clears its Night search state")
R.Time.phase="Night";R.Creature:think(.2)
check(not live.Dormant and live.SearchMode=="patrol" and live.TargetX~=nil,
 "same authored Braid resumes an independent hunt on the following Night")
check(SIM.COUNTERS.runtimeInstanceNew==0,
 "patrol creates no runtime UI, world Part, Path or extra authored object")
VitriolRequire("Bootstrap").stop()
return SESSION
