-- A real-road-derived destination AFTER one completed bounded Night circuit.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1;print("PASS  "..msg)
 else SESSION.failed=SESSION.failed+1;print("FAIL  "..msg) end
end
local Search=VitriolRequire("InstinctSearch")
-- Model the user's extended (not old 560-stud) Road_Main geometry.
local road={Position={X=0,Z=-16.5},Size={X=36,Z=593},
 IsA=function(_,name)return name=="BasePart" end}
local roads={FindFirstChild=function(_,name)return name=="Road_Main" and road end}
local map={FindFirstChild=function(_,name)return name=="Roads" and roads end}
local cfg={SweepRadiusStuds=10,PatrolRadiusStuds=24,ArriveStuds=5,
 RegionArriveStuds=12,StallSeconds=3}
local p=Search.new(cfg,map)
check(p.RoadStops and #p.RoadStops==4 and math.abs(p.RoadStops[2][2]+87.66)<.001,
 "regional goals derive from user's actual extended road, not a frozen old length")
local nav={calls=0,clear=function(self)self.calls=self.calls+1;return true end}
local b={X=0,Y=8,Z=0}
local x,y,z=p:next(b,0,nav,nil)
check(b.SearchMode=="patrol" and x==24 and z==0,
 "without a clue Night search starts with the local bounded patrol")
for i=1,4 do
 b.X,b.Z=x,z
 x,y,z=p:next(b,i,nav,nil)
end
check(b.SearchMode=="transit" and x==0 and math.abs(z+87.66)<.001,
 "AFTER one local circuit Braid heads toward another authored road region")
local before=nav.calls
x,y,z=p:next(b,4.2,nav,nil)
check(nav.calls==before and b.SearchMode=="transit" and x==0,
 "held inter-region route does not repeat expensive raycasts every Think")
b.X,b.Z=x,z
x,y,z=p:next(b,5,nav,nil)
check(b.SearchMode=="patrol" and b.SearchAnchorZ==b.Z and x==24,
 "arriving in new region starts a fresh short local hunt there")
for i=1,4 do b.X,b.Z=x,z;x,y,z=p:next(b,5+i,nav,nil) end
check(b.SearchMode=="transit" and x==0 and math.abs(z-54.66)<.001,
 "next completed circuit advances to another region instead of bouncing in place")
p:reset(b)
b.X,b.Z=0,0
x,y,z=p:next(b,0,nav,nil)
for i=1,3 do b.X,b.Z=x,z;x,y,z=p:next(b,i,nav,nil) end
-- First road target is blocked by an actual defense, second visible route wins.
local target=p.RoadStops[2][2]
local cover={activeCount=1,intercept=function(_,_,_,_,tz)return math.abs(tz-target)<.01 end}
b.X,b.Z=x,z
x,y,z=p:next(b,4,nav,cover)
check(b.SearchMode=="transit" and z~=target and x==0,
 "region change never ghosts through the contacted installed cover")
p:reset(b)
b.X,b.Z=0,0
x,y,z=p:next(b,0,nav,nil)
for i=1,3 do b.X,b.Z=x,z;x,y,z=p:next(b,i,nav,nil) end
local rays=0
local blocked={clear=function()rays=rays+1;return false end}
b.X,b.Z=x,z
x,y,z=p:next(b,4,blocked,nil)
check(x==nil and rays==2 and b.SearchMode=="transit",
 "blocked road approach tries at most two new physical rays in one Think")
x,y,z=p:next(b,4.2,blocked,nil)
check(x==nil and rays==4 and b.SearchMode=="patrol",
 "after all four real road routes fail it safely returns to local search")
x,y,z=p:next(b,4.4,nav,nil)
check(x~=nil and b.SearchMode=="patrol" and b.SearchAnchorZ==b.Z,
 "inaccessible road does not freeze Night hunting or teleport through walls")
-- Priorities reset destination: newly sensed prey immediately interrupts transit.
p:reset(b)
b.X,b.Z=0,0
x,y,z=p:next(b,0,nav,nil)
for i=1,4 do b.X,b.Z=x,z;x,y,z=p:next(b,i,nav,nil) end
p:note(b,b.X+8,b.Y,b.Z,5)
x,y,z=p:next(b,5,nav,nil)
check(b.SearchMode=="sweep" and x~=0,
 "fresh genuine sensory clue preempts a long-distance regional destination")
check(SIM.COUNTERS.runtimeInstanceNew==0,"no patrol road Parts or Paths made during Play")
return SESSION
