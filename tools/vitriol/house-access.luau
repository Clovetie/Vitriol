-- Roof escape, doorway staging and vertical clearance against authored houses.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1; print("PASS  "..msg)
 else SESSION.failed=SESSION.failed+1; print("FAIL  "..msg) end
end
local R=VitriolRequire("Bootstrap").ensure()
local nav=R.Creature.HouseAccess
local p=R.Players:addPlayer("GroundPrey",85101)
local other=R.Players:addPlayer("DistantHelper",85102)
local root=p.Character:FindFirstChild("HumanoidRootPart")
local otherRoot=other.Character:FindFirstChild("HumanoidRootPart")
local houses=SIM.structures
local capTable={}
check(nav~=nil and #nav.Houses==2,"both authored house footprints, lintels and roofs feed one pure access router")
for _,spec in ipairs({{"House_01",-79,72},{"House_02",114,62}}) do
 local name,door,z=spec[1],spec[2],spec[3]
 local x=door-12
 local h=nav:houseForPrey(x,2,z)
 check(h and h.Name==name and nav:houseForPrey(door-1,2,z)==h
  and not nav:houseForPrey(door+1,2,z) and not nav:houseForPrey(x,19,z),
  name.." treats even a survivor just INSIDE the real doorway as grounded prey")
 local radius=1.5
 local cap,floor=nav:heightCap(door+5,9,z,radius)
 check(cap and math.abs(cap-10)<.01 and math.abs(floor-2.4)<.01,
  name.." measured porch underside and lintel limit the core center to 10 studs")
 local indoorCap=nav:heightCap(door-8,9,z,radius)
 check(indoorCap and indoorCap>13 and indoorCap<15,
  name.." main room permits its NORMAL high body after clearing the lintel")
 check(nav:heightCap(door-8,28,z,radius)==nil,
  name.." never clamps a roof-bound body THROUGH the solid roof")
 check(nav:roofOccludes(door-10,29,z,door-12,2,z)
  and nav:roofOccludes(door+25,29,z,door-12,2,z)
  and not nav:roofOccludes(door+6,9,z,door-12,2,z)
  and not nav:roofOccludes(door-10,29,z,door-12,20,z),
  name.." solid roof blocks high-to-low perception, not sight through the actual door or rooftop prey")
 local house,ex,ey,ez,descending=nav:escape(door-10,29,z,radius)
 check(house==h and ex>door+24 and ey==29 and ez==z and not descending,
  name.." roof route first moves out beyond the eave at the existing height")
 house,ex,ey,ez,descending=nav:escape(door+25,29,z,radius)
 check(house==h and descending and ey<9 and ex>=door+25,
  name.." DESCENDS only in clear sky beyond the porch roof plus core radius")
 local sx,sy,sz=nav:constrain(door+25,29,z,-8,1,0,radius,.1,true)
 check(door+25+sx>=door+19 and sy<0 and sz==0,
  name.." outside recovery cannot slide back under the eave while still high")
 local _,roofDrop=nav:constrain(door-8,29,z,0,-20,0,radius,.1,false)
 local _,porchDrop=nav:constrain(door+8,20,z,0,-15,0,radius,.1,false)
 check(29+roofDrop>=h.Roof.Position.Y+h.Roof.Size.Y/2+radius
  and 20+porchDrop>=h.Porch.Position.Y+h.Porch.Size.Y/2+radius,
  name.." an airborne Braid cannot glide THROUGH either solid roof slab")
 local nx,ny,nz,limit=nav:route(door+25,9,z,x,2,z,radius)
 check(nx==door+6 and ny>=8 and nz==z and math.abs(limit-10)<.01,
  name.." low approach aims for the REAL main entry with reachable foot target Y")
 nx,ny,nz=nav:route(door+6,9,z,x,2,z,radius)
 check(nx==door-8 and nz==z, name.." next stage crosses beneath the lintel")
 nx,ny,nz,limit=nav:route(door-9,9,z,x,2,z,radius)
 check(nx==x and ny==2 and nz==z and limit>13,
  name.." after entry returns to sensed prey and normal indoor height")
 local west=h.Floor.Position.X-h.Floor.Size.X/2-7
 nx,ny,nz=nav:route(west,9,z,x,2,z,radius)
 check(nx<west+3 and math.abs(nz-z)>22,
  name.." ground approach from behind uses outside wall/roof flank, not wall tunneling")
 capTable[name]=cap
end
local Locomotion=VitriolRequire("Locomotion")
local support={Raycast=function(_,origin,direction)
 if direction.Y>0 then
  local t=(12.5-origin.Y)/direction.Y
  if t>=0 and t<=1 then return {Position={X=origin.X+direction.X*t,Y=12.5,Z=origin.Z+direction.Z*t},
   Normal={X=0,Y=-1,Z=0},Material={Name="Wood"},Instance=houses.House_01.PorchRoof} end
 elseif direction.Y<0 then
  local t=(.8-origin.Y)/direction.Y
  if t>=0 and t<=1 then return {Position={X=origin.X+direction.X*t,Y=.8,Z=origin.Z+direction.Z*t},
   Normal={X=0,Y=1,Z=0},Material={Name="Wood"},Instance=houses.House_01.Floor} end
 end
 return nil
end}
local loc=Locomotion.new({TendrilReach=14,TendrilCount=8,CoreRadius=1.5,HaulSpeed=22},
 {Config={Locomotion={MinAnchors=2,MaxAnchors=4,AnchorRayCount=7,SupportHeightFraction=.88,
  HaulSeconds=.12,ProbeReachMultiplier=1.15},Kill={ChompClearance=.55}},Workspace=support})
loc:setTarget(-85,9,72,.5)
loc:setPassageHeight(10,2.4)
local _,dy=loc:step(.1,-73,9.8,72,nil,nil,0)
local highContact=false
for i=1,loc.AnchorCount do if loc.AnchorY[i]>10.1 then highContact=true end end
check(loc.AnchorCount>=2 and not highContact and 9.8+dy<=10,
 "under the porch existing ray fan REJECTS ceiling footholds and stays supported on floor")
loc:setPassageHeight(nil,nil)
loc:_buildDirections(-73,9.8,72)
loc:_clearAnchors()
local foundCeiling=loc:_tryAnchor(3,-73,9.8,72,16.1)
check(foundCeiling and math.abs(loc.AnchorY[1]-12.38)<.01,
 "outside passage the original upward ceiling probe remains available")
-- Now use the REAL Think/Frame owners against the same authored fixture.
R.Time.phase="Night"
R.Creature:reconcile()
local b=R.Creature.creatures[R.Creature.order[1]]
local door,z=-79,72
root.Position={X=door-12,Y=2,Z=z}
otherRoot.Position={X=400,Y=2,Z=400}
b.X,b.Y,b.Z=door-10,29,z
local hiddenRoot=R.Creature:_nearestTarget(b)
check(hiddenRoot==nil,"roof-mounted Braid cannot get a hidden indoor player's live GPS through the roof")
R.Creature:think(.2)
check(b.HouseRecovery and b.TargetX>door+24 and b.TargetY==29,
 "real roof-bound Braid escapes outward without acquiring hidden prey BEFORE lowering")
b.X,b.Y,b.Z=door+25,29,z
R.Creature:think(.2)
local oldY=b.Y
b:step(.1)
check(b.HouseRecovery and b.TargetY<9 and b.Y<oldY and b.X>=door+19,
 "real body descends outside the eave instead of sticking to its rooftop feet")
b.X,b.Y,b.Z=door+25,9,z
R.Creature:think(.2)
check(not b.HouseRecovery and b.TargetX==door+6 and b.TargetY>=8,
 "real Think resumes toward the east entrance once the body fits")
b.X,b.Y,b.Z=door+6,9,z
R.Creature:think(.2)
b:step(.1)
check(b.TargetX==door-8 and b.Locomotion.PassageMaxY~=nil,
 "real Think and frame route through the existing opening with low-ceiling posture")
b.X,b.Y,b.Z=door-9,9,z
R.Creature:think(.2)
check(b.TargetX==root.Position.X,"inside house the sensed player's location replaces the doorway waypoint")
b.X,b.Y,b.Z=door-10,29,z
root.Position={X=door-12,Y=20,Z=z}
R.Creature:think(.2)
check(not b.HouseRecovery and b.TargetX==root.Position.X,
 "a living rooftop player keeps the previously accepted high-prey response")
-- New human Play: at X=-54.5,Z=72.2 the Braid spasmed on the ground
-- outside House_01 while an actual LAST-SEEN player position was inside.
-- This is deliberately a memory sample, not a hidden-player root read.
SAVED_MEMORY_NAVIGATION=R.Creature.Navigation
MEMORY_NAVIGATION={calls=0}
function MEMORY_NAVIGATION:clear()
 self.calls+=1
 return true -- the Edit Y=4 ray through the open door was clear
end
function MEMORY_NAVIGATION:hit() return nil end
R.Creature.Navigation=MEMORY_NAVIGATION
root.Position={X=400,Y=2,Z=400}
otherRoot.Position={X=400,Y=2,Z=400}
b.X,b.Y,b.Z=-54.5,8,72.2
b.LastKnownPosition={X=-84.5,Y=2,Z=73.5}
b.LastKnownAt=R.Time.elapsedTotal
R.Creature:think(.2)
check(b.DecisionReason=="last-genuinely-observed-location"
 and b.TargetX==-73 and b.TargetZ==73.5 and b.TargetY>=8
 and MEMORY_NAVIGATION.calls==1,
 "genuine indoor LAST-SEEN clue uses the real House_01 doorway stage, not a direct porch-to-room pull")
b.LastKnownPosition={X=-72.1,Y=2,Z=67.2} -- outside porch prey remains outside
R.Creature:think(.2)
check(b.TargetX==-72.1 and b.TargetZ==67.2 and MEMORY_NAVIGATION.calls==2,
 "genuine outside last-seen point is not falsely classified as indoor House prey")
b.X,b.Y,b.Z=138.5,8,62.2
b.LastKnownPosition={X=109.5,Y=2,Z=63.5}
R.Creature:think(.2)
check(b.DecisionReason=="last-genuinely-observed-location"
 and b.TargetX==120 and b.TargetZ==63.5 and MEMORY_NAVIGATION.calls==3,
 "House_02 last genuine indoor clue stages through its OWN east doorway")
b.LastKnownAt,b.LastKnownPosition=nil,nil
R.Creature.Navigation=SAVED_MEMORY_NAVIGATION
MEMORY_NAVIGATION,SAVED_MEMORY_NAVIGATION=nil,nil
check(SIM.COUNTERS.runtimeInstanceNew==0,"all roof/height adaptation uses only original authored Parts")
-- The user's newer Play: after House_01 contact, the closet can be broken
-- while its original TABLE still covers the other lane. Search may leave
-- the region only after one completed circuit; it must find a full body-
-- width doorway, not a thin clear ray through the one-stud furniture gap.
local exitNav={calls=0}
function exitNav:clear() self.calls=self.calls+1;return true end
local tablePiece={House="House_01",Placed=true,Width=9,Part={Size={Z=5}},
 Target={Position={X=-81.5,Z=68.5}}}
local closetPiece={House="House_01",Placed=false,Width=6,Part={Size={Z=5}},
 Target={Position={X=-81.5,Z=77}}}
local exitCover={Pieces={tablePiece,closetPiece},activeCount=1}
local c={X=-91,Y=8,Z=77,SearchMode="transit",Stats={CoreRadius=1.5}}
local ex,ey,ez,why=nav:sweepExit(c,50,exitNav,exitCover)
check(ex==-67 and ez==77 and why=="physical-house-exit" and exitNav.calls==1,
 "clue-less House_01 search finds the OPEN closet lane with one circular spoke")
local high={X=-91,Y=14,Z=77,Stats={CoreRadius=1.5}}
local raysBeforeLower=exitNav.calls
local highX,highY,highZ,highStatus=nav:sweepExit(high,50,exitNav,exitCover)
check(highX==high.X and highZ==high.Z and highY<=9
 and highStatus=="physical-house-exit-lowering" and exitNav.calls==raysBeforeLower
 and not nav:groundHouse(-91,29,77),
 "high indoor core gets ONLY a downward command; no exit ray or roof-level ground exit")
high.Y=13.2 -- genuine descent refreshes its three-second progress watchdog
highX,highY,highZ,highStatus=nav:sweepExit(high,52.8,exitNav,exitCover)
check(highX==high.X and highZ==high.Z and highY<=9
 and highStatus=="physical-house-exit-lowering" and exitNav.calls==raysBeforeLower,
 "progressing downward remains indoors with no horizontal exit target/ray")
high.Y=9.2
highX,highY,highZ,highStatus=nav:sweepExit(high,53,exitNav,exitCover)
check(highX==-67 and highZ==77 and highY<=9
 and highStatus=="physical-house-exit" and exitNav.calls==raysBeforeLower+1,
 "only after the core fits below lintel does the first physical spoke lead outside")
local stuck={X=-91,Y=14,Z=77,Stats={CoreRadius=1.5}}
local stuckRays=exitNav.calls
nav:sweepExit(stuck,60,exitNav,exitCover)
local _,_,_,stuckStatus=nav:sweepExit(stuck,63.1,exitNav,exitCover)
check(stuckStatus=="blocked" and stuck.ExitSweepHouse==nil and exitNav.calls==stuckRays,
 "unlowerable indoor core gives control back to local hunt after three seconds, without a ray")
local high2={X=102,Y=14,Z=62,Stats={CoreRadius=1.5}}
local house2Rays=exitNav.calls
local h2x,h2y,h2z,h2status=nav:sweepExit(high2,64,exitNav,exitCover)
check(h2x==102 and h2z==62 and h2y<capTable.House_02
 and h2status=="physical-house-exit-lowering" and exitNav.calls==house2Rays,
 "House_02 likewise lowers inside before starting any new doorway ray")
high2.Y=9.2
h2x,h2y,h2z,h2status=nav:sweepExit(high2,64.2,exitNav,exitCover)
check(h2x>114 and h2z==62 and h2status=="physical-house-exit"
 and exitNav.calls==house2Rays+1,
 "House_02 begins its doorway sweep only after physical lowering")
c.TargetX,c.TargetZ=ex,ez
local before=exitNav.calls
local hx,_,hz=nav:sweepExit(c,50.2,exitNav,exitCover)
check(hx==ex and hz==ez and exitNav.calls==before,
 "held exit goal never repeats its clearance ray on each Think")
nav:resetExitSweep(c)
closetPiece.Placed=true;exitCover.activeCount=2
local blocked=nil
for i=1,19 do
 local rays=exitNav.calls
 local x,_,z,status=nav:sweepExit(c,50+i*.2,exitNav,exitCover)
 if status=="blocked" then blocked=true;break end
 if x or z or exitNav.calls-rays>1 then blocked=false;break end
end
check(blocked and c.ExitSweepGoalX==nil,
 "two ORIGINAL installed pieces leave only a one-stud gap; Braid fails closed")
closetPiece.Placed=false;exitCover.activeCount=1
c={X=-90,Y=8,Z=65,SearchMode="transit",Stats={CoreRadius=1.5}}
local stageX,stageZ,stageStatus=nil,nil,nil
local bounded=true
for i=1,18 do
 local rays=exitNav.calls
 local sx,_,sz,status=nav:sweepExit(c,60+i*.2,exitNav,exitCover)
 if exitNav.calls-rays>1 then bounded=false end
 if status=="physical-house-exit-stage" then stageX,stageZ,stageStatus=sx,sz,status;break end
end
check(bounded and stageStatus=="physical-house-exit-stage" and stageX==-87 and stageZ==77,
 "corner graze is not an exit: staged ray moves INSIDE to cleared closet lane, ≤1 ray/Think")
c.X,c.Z,c.TargetX,c.TargetZ=-87,77,stageX,stageZ
local sx,_,sz,status=nav:sweepExit(c,70,exitNav,exitCover)
check(sx and sx>-79 and sz==77 and status=="physical-house-exit",
 "after physically reaching its indoor stage, fresh radial ray leads OUT the main door")
-- The rotated original table is five studs DEEP in X. From (-90,71), the
-- +pi/8 spoke crosses its CENTER plane X=-81.5 at Z=74.52 (just clear of
-- width+core-radius 74.5), yet its west face X=-85.5 crosses at Z=72.86.
-- The thin physical ray can miss while the 1.5-radius body clips the table.
local tableEdge={X=-90,Y=8,Z=71,Stats={CoreRadius=1.5}}
local tableRays=exitNav.calls
local _,_,_,tableFirst=nav:sweepExit(tableEdge,90,exitNav,exitCover)
local tableX,_,_,tableSecond=nav:sweepExit(tableEdge,90.2,exitNav,exitCover)
check(tableFirst=="scanning" and tableX==nil and tableSecond=="scanning"
 and exitNav.calls==tableRays,
 "angled spoke clears cover CENTER plane but clips original table corner: reject before ray")
tablePiece.Placed=false;exitCover.activeCount=0
local released={X=-90,Y=8,Z=71,Stats={CoreRadius=1.5}}
local angledNav={calls=0,clear=function(self)self.calls=self.calls+1;return self.calls==2 end}
local _,_,_,held=nav:sweepExit(released,91,angledNav,exitCover)
local openX,_,openZ,openStatus=nav:sweepExit(released,91.2,angledNav,exitCover)
check(held=="scanning" and openX>-79 and openZ>74.5
 and openStatus=="physical-house-exit" and angledNav.calls==2,
 "dislodging THAT table independently restores its angled lane: one physical ray per Think")
tablePiece.Placed=true;exitCover.activeCount=1
-- Real authored piers are one stud deep (X=-79 ±0.5), with the opening
-- Z=64..80. A centerline from (-84,64) along the second spoke crosses the
-- plane at Z=66.07, but at expanded west face X=-81 its body CENTER is
-- Z=65.24: less than 1.5 studs from the solid south pier's Z=64 edge.
-- A single thin ray misses the pier; a body-radius guard must reject it.
local pierEdge={X=-84,Y=8,Z=64,Stats={CoreRadius=1.5}}
local pierRays=exitNav.calls
local _,_,_,firstStatus=nav:sweepExit(pierEdge,100,exitNav,nil)
local secondX,_,_,secondStatus=nav:sweepExit(pierEdge,100.2,exitNav,nil)
check(firstStatus=="scanning" and secondX==nil and secondStatus=="scanning"
 and exitNav.calls==pierRays,
 "angled spoke grazes real pier corner: reject before ray even though door-plane Z passes")
local cornerX,_,cornerZ,cornerStatus=nil,nil,nil,nil
for i=3,5 do
 cornerX,_,cornerZ,cornerStatus=nav:sweepExit(pierEdge,100+i*.2,exitNav,nil)
 if cornerX then break end
end
check(cornerX and cornerX>-79 and cornerZ>64 and cornerStatus=="physical-house-exit"
 and exitNav.calls-pierRays==1,
 "later body-safe spoke still clears the real doorway with at most one ray per Think")
local northEdge={X=109,Y=8,Z=70,Stats={CoreRadius=1.5}}
local northRays=exitNav.calls
local nearNorth=nil
for i=1,3 do
 nearNorth=nav:sweepExit(northEdge,110+i*.2,exitNav,nil)
end
check(nearNorth==nil and exitNav.calls==northRays,
 "House_02 opposite pier also rejects a clear but body-clipping angled centerline")
local safeNorth=nil
for i=4,5 do
 safeNorth=nav:sweepExit(northEdge,110+i*.2,exitNav,nil)
 if safeNorth then break end
end
check(safeNorth and safeNorth>114 and exitNav.calls==northRays+1,
 "House_02 still finds its body-safe doorway spoke without extra physical rays")
local farFace={X=-84,Y=8,Z=75.9,Stats={CoreRadius=1.5}}
local firstBlocked={calls=0,clear=function(self)self.calls=self.calls+1;return false end}
nav:sweepExit(farFace,120,firstBlocked,nil) -- center spoke is physically blocked
local farX,_,_,farStatus=nav:sweepExit(farFace,120.2,firstBlocked,nil)
check(farX==nil and farStatus=="scanning" and firstBlocked.calls==1,
 "door-plane Z=77.97 is not enough: angled core also clears FAR pier face at X=-77")
local oldNavigation,oldCover=R.Creature.Navigation,R.Creature.HouseCover
R.Creature.Navigation,R.Creature.HouseCover=exitNav,exitCover
b.X,b.Y,b.Z=-91,14,77
b.SearchMode,b.SearchClueAt,b.ExitSweepHouse="transit",nil,nil
nav:resetExitSweep(b)
local serviceRays=exitNav.calls
R.Creature:_search(b,79.8)
check(b.DecisionReason=="physical-house-exit-lowering" and b.TargetX==b.X
 and b.TargetZ==b.Z and b.TargetY<capTable.House_01 and exitNav.calls==serviceRays,
 "actual search service commands an elevated indoor Braid DOWN before any outward goal")
b.X,b.Y,b.Z=-91,8,77
R.Creature:_search(b,80)
check(b.DecisionReason=="physical-house-exit" and b.TargetX==-67 and b.TargetZ==77,
 "real no-prey search service uses the bounded house-exit sweep after local circuit")
-- The previous fixture assigned Y=9.2 by hand. Drive REAL planted feet
-- against the two separately measured authored surfaces. Each Floor ends
-- at DoorX and its ground Porch starts 0.5 stud later at top Y=1, leaving
-- a narrow unsupported gap. The Porch is a Lua TABLE proxy for offline
-- ray hits, not a runtime-created Roblox Part.
local function measuredHouseSupport(name)
 local house=houses[name]
 local floor=house.Floor
 local porch={Name="Porch",Position={X=floor.Position.X+29,Y=.5,Z=floor.Position.Z},
  Size={X=15,Y=1,Z=29}}
 -- Read-only Edit sampled the actual Ground_QuarryFoundation top at Y=0
 -- under the reported X=-54.5 / -53.6 exterior core positions. Model that
 -- support in the offline replay; older exit replays began indoors only.
 local ground={Name="Ground_QuarryFoundation",Position={X=floor.Position.X,Y=-.5,Z=floor.Position.Z},
  Size={X=300,Y=1,Z=300}}
 local support={Raycast=function(_,origin,direction)
  if direction.Y==0 then return nil end
  local bestT,bestPart,bestY=nil,nil,nil
  local function consider(part,level)
   local t=(level-origin.Y)/direction.Y
   if t<0 or t>1 or (bestT and t>=bestT) then return end
   local hitX,hitZ=origin.X+direction.X*t,origin.Z+direction.Z*t
   if math.abs(hitX-part.Position.X)<=part.Size.X*.5
    and math.abs(hitZ-part.Position.Z)<=part.Size.Z*.5 then
    bestT,bestPart,bestY=t,part,level
   end
  end
  if direction.Y<0 then
   consider(ground,0)
   consider(floor,floor.Position.Y+floor.Size.Y*.5)
   consider(porch,porch.Position.Y+porch.Size.Y*.5)
  else
   consider(house.Roof,house.Roof.Position.Y-house.Roof.Size.Y*.5)
   consider(house.PorchRoof,house.PorchRoof.Position.Y-house.PorchRoof.Size.Y*.5)
  end
  if not bestPart then return nil end
  return {Position={X=origin.X+direction.X*bestT,Y=bestY,Z=origin.Z+direction.Z*bestT},
   Normal={X=0,Y=direction.Y<0 and 1 or -1,Z=0},Material={Name="Wood"},Instance=bestPart}
 end}
 return support,porch
end
local floorSupport,porch1=measuredHouseSupport("House_01")
local originalSupport=b.Locomotion.Workspace
b.Locomotion.Workspace=floorSupport
-- New Play: the visible ground-level Braid spasmed near X=-54.5 while its
-- sensed target was on the House_01 Porch. Continue the approved planted-
-- foot gait over sampled exterior ground Y=0 → original Porch top Y=1.
-- No monster/game Part is fabricated: ground/porch are pure harness tables.
b.X,b.Y,b.Z=-54.5,9,72.2
b.AttackPhase,b.HouseRecovery=nil,false
b.DecisionReason="genuinely-sensed-prey"
b.Locomotion:_clearAnchors();b.Locomotion.AnchorAge=math.huge
b:setTarget(-72.1,2,67.2,.5)
INGRESS_REPLAY={ground=false,porch=false,passedEave=false}
for i=1,300 do
 b:step(1/60)
 for foot=1,b.Locomotion.AnchorCount do
  local part=b.Locomotion.AnchorPart[foot]
  if part and part.Name=="Ground_QuarryFoundation" then INGRESS_REPLAY.ground=true end
  if part==porch1 then INGRESS_REPLAY.porch=true end
 end
 if b.X < -62.5 then INGRESS_REPLAY.passedEave=true end
 if b.X < -70 then break end
end
check(b.X < -70 and INGRESS_REPLAY.ground and INGRESS_REPLAY.porch
 and INGRESS_REPLAY.passedEave,
 "real footed body crosses the reported exterior Ground-to-Porch approach with stable sensed prey")
INGRESS_REPLAY=nil
b.Locomotion:_clearAnchors();b.Locomotion.AnchorAge=math.huge
b.X,b.Y,b.Z=-91,14,77
b.SearchMode,b.SearchClueAt,b.LastKnownAt="transit",nil,nil
nav:resetExitSweep(b)
local descendedAt,outwardAt,earlyRay=nil,nil,false
local frameStartRays=exitNav.calls
local limit=300 -- <5 simulated seconds, includes the bounded 16-spoke scan/stage
for i=1,limit do
 if (i-1)%12==0 then
  R.Creature:_search(b,200+(i-1)/60)
  if exitNav.calls>frameStartRays and not descendedAt then earlyRay=true end
  if b.DecisionReason=="physical-house-exit" then outwardAt=i;break end
 end
 b:step(1/60)
 if b.Y<=9.55 and not descendedAt then descendedAt=i end
end
check(descendedAt and outwardAt and descendedAt<outwardAt and not earlyRay
 and exitNav.calls>frameStartRays and b.Locomotion.Crouch>0,
 "actual anchored feet lower below lintel BEFORE outward ray; no hand-assigned core Y")
local exited,bodyClear,porchFoot1,seamSeen1,seamHeld1=nil,true,false,false,true
local h1=nav.Houses[1]
local seamEnd1=h1.PierEastX+b.Stats.CoreRadius+.5
for i=1,120 do
 -- Continue the same clock through the full body-radius seam. Once clear,
 -- this headless stub has no authored regional road nodes to resume.
 if (i-1)%12==0 and b.X<=seamEnd1 then
  local inSeam=b.X>h1.DoorX-.75
  local beforeRay=exitNav.calls
  R.Creature:_search(b,200+(outwardAt+i-1)/60)
  if inSeam then
   seamSeen1=true
   if b.DecisionReason~="physical-house-exit" or exitNav.calls~=beforeRay then
    seamHeld1=false
   end
  end
 end
 b:step(1/60)
 for foot=1,b.Locomotion.AnchorCount do
  if b.Locomotion.AnchorPart[foot]==porch1 then porchFoot1=true end
 end
 if b.X>=-85.5 and b.X<=-77.5 and b.Z<=74.5 then bodyClear=false end
 if b.X>=h1.PierWestX-b.Stats.CoreRadius and b.X<=h1.PierEastX+b.Stats.CoreRadius
  and (b.Z<h1.DoorMinZ+b.Stats.CoreRadius+.5
   or b.Z>h1.DoorMaxZ-b.Stats.CoreRadius-.5
   or b.Y>math.min(h1.LintelBottom,h1.PorchBottom)-b.Stats.CoreRadius-.5) then
  bodyClear=false
 end
 if b.X>door+b.Stats.CoreRadius+.5 then exited=i;break end
end
check(exited and bodyClear and porchFoot1 and seamSeen1 and seamHeld1,
 "House_01 footed core grips the measured Porch, holds its seam and clears the pier/table")
-- Independent House_02 real-foot replay: the numeric House_02 check above
-- hand-assigned Y, so it could miss the original stuck-high-core regression.
-- Keep its ORIGINAL low table installed and closet dislodged: the ray must
-- choose the open closet lane, without treating the low table as empty.
local table2Piece={House="House_02",Placed=true,Width=9,Part={Size={Z=5}},
 Target={Position={X=111.5,Z=58.5}}}
local closet2Piece={House="House_02",Placed=true,Width=6,Part={Size={Z=5}},
 Target={Position={X=111.5,Z=67}}}
exitCover.Pieces[#exitCover.Pieces+1]=table2Piece
exitCover.Pieces[#exitCover.Pieces+1]=closet2Piece
exitCover.activeCount=3
local closed2={X=102,Y=8,Z=62,Stats={CoreRadius=1.5}}
local closedStatus2=nil
for i=1,19 do
 local beforeRay=exitNav.calls
 local gx,_,gz,status=nav:sweepExit(closed2,290+i*.2,exitNav,exitCover)
 if exitNav.calls-beforeRay>1 or gx or gz then closedStatus2="unsafe";break end
 closedStatus2=status
 if status=="blocked" then break end
end
check(closedStatus2=="blocked" and closed2.ExitSweepGoalX==nil,
 "both placed House_02 originals block a full-core exit; no ray slips through their gap")
-- Simulate contact dislodging only the original closet, not a free Night
-- release or a change to either original piece's shape.
closet2Piece.Placed=false
exitCover.activeCount=2
-- Same measured Floor→Porch discontinuity, but House_02's own Parts.
local floor2Support,porch2=measuredHouseSupport("House_02")
b.Locomotion.Workspace=floor2Support
b.Locomotion:_clearAnchors();b.Locomotion.AnchorAge=math.huge
b.X,b.Y,b.Z=102,14,62
b.SearchMode,b.SearchClueAt,b.LastKnownAt="transit",nil,nil
nav:resetExitSweep(b)
local rays2=exitNav.calls
local descended2,outward2,early2,staged2=nil,nil,false,false
local tableClear2=true
local tableHalfX=table2Piece.Part.Size.Z*.5+b.Stats.CoreRadius
local tableHalfZ=table2Piece.Width*.5+b.Stats.CoreRadius
local function clearsHouse2Table()
 return not (math.abs(b.X-table2Piece.Target.Position.X)<=tableHalfX
  and math.abs(b.Z-table2Piece.Target.Position.Z)<=tableHalfZ)
end
for i=1,540 do
 if (i-1)%12==0 then
  local beforeRay=exitNav.calls
  R.Creature:_search(b,300+(i-1)/60)
  if exitNav.calls-beforeRay>1 or (exitNav.calls>rays2 and not descended2) then early2=true end
  if b.DecisionReason=="physical-house-exit-stage" then staged2=true end
  -- A held STAGE goal currently reports the generic physical-exit reason;
  -- its actual ExitSweepKind must be exit before counting an outward ray.
  if b.DecisionReason=="physical-house-exit" and b.ExitSweepKind=="exit" then
   outward2=i;break
  end
 end
 b:step(1/60)
 if not clearsHouse2Table() then tableClear2=false end
 if b.Y<=9.55 and not descended2 then descended2=i end
end
check(descended2 and staged2 and outward2 and descended2<outward2 and not early2
 and exitNav.calls>rays2 and b.Locomotion.Crouch>0,
 "House_02 actual planted feet stage around its table, lower, then cast a bounded outward ray")
local h2=nav.Houses[2]
local crossed2,clear2,porchFoot2=nil,true,false
for i=1,120 do
 if (i-1)%12==0 and nav:groundHouse(b.X,b.Y,b.Z) then
  local beforeRay=exitNav.calls
  -- Continue the same simulated clock; jumping >3s here would falsely
  -- trip the physical-ray stall watchdog without any intervening frames.
  R.Creature:_search(b,300+(outward2+i-1)/60)
  if exitNav.calls-beforeRay>1 then clear2=false end
 end
 b:step(1/60)
 for foot=1,b.Locomotion.AnchorCount do
  if b.Locomotion.AnchorPart[foot]==porch2 then porchFoot2=true end
 end
 if not clearsHouse2Table() then tableClear2=false end
 if b.X>=h2.PierWestX-b.Stats.CoreRadius and b.X<=h2.PierEastX+b.Stats.CoreRadius
  and (b.Z<h2.DoorMinZ+b.Stats.CoreRadius+.5
   or b.Z>h2.DoorMaxZ-b.Stats.CoreRadius-.5
   or b.Y>math.min(h2.LintelBottom,h2.PorchBottom)-b.Stats.CoreRadius-.5) then
  clear2=false
 end
 if b.X>h2.DoorX+b.Stats.CoreRadius+.5 then crossed2=i;break end
end
check(crossed2 and clear2 and tableClear2 and porchFoot2
 and table2Piece.Placed and not closet2Piece.Placed,
 "House_02 body grips the real-height porch across the floor gap, avoids the table and exits")
check(SIM.COUNTERS.runtimeInstanceNew==0,
 "two-house planted-foot exit replay creates no gameplay Instances")
b.DecisionReason="genuinely-sensed-prey" -- fresh prey must immediately own high stance
b:step(1/60)
check(b.Locomotion.Crouch==0,
 "fresh genuinely sensed prey restores the original elevated planted-foot stance")
b.AttackPhase,b.AttackAge,b.DecisionReason="CROUCH",0,"physical-house-exit-lowering"
b:step(.1)
check(b.AttackPhase=="CROUCH" and b.Locomotion.Crouch>0
 and math.abs(b.Locomotion.Crouch-.1/R.Monster.Kill.CrouchSeconds)<.001,
 "a real chomp's lower-then-charge CROUCH overrides the idle exit posture")
b.AttackPhase=nil
nav:resetExitSweep(b)
check(b.ExitSweepCrouch==nil and b.ExitSweepHouse==nil,
 "leaving/canceling the exit sweep clears its temporary supported posture")
-- A witnessed Garage habit is not a license to skip the physical door.
-- After one completed local House circuit, exit first; keep run-local Garage
-- evidence so the habit can be re-ray-checked once the core is outside.
local savedHabit=R.Creature.GarageHabit
local garageFloor={Position={X=-90,Y=.42,Z=-56},Size={X=56,Z=46},
 IsA=function(_,kind)return kind=="BasePart" end}
exitNav.Garage={FindFirstChild=function(_,name)
 if name=="Floor" then return garageFloor end
 return nil
end}
exitNav.Nodes={{-55,-56}}
-- This stub claims a Garage ray is clear even from indoors; the House must
-- still stage out of its own door before spending that optimistic lead.
exitCover.intercept=function() return false end
local activeHabit=VitriolRequire("GarageHabit").new(
 {GarageVisitsForPrediction=3},exitNav,R.Monster.InstinctSearch)
activeHabit.Evidence=3
R.Creature.GarageHabit=activeHabit
b.HabitNight,b.HabitState=(R.Time and R.Time.nightIndex) or 0,"front"
b.HabitGoalX,b.HabitGoalZ=-55,-56 -- cached outdoor ray MUST be invalidated
b.X,b.Y,b.Z=102,9.2,67
b.SearchMode,b.SearchClueAt,b.LastKnownAt="patrol",nil,nil
nav:resetExitSweep(b)
local savedSearch=R.Creature.Search
R.Creature.Search={next=function(_,c)return 103,c.Y,67 end}
local patrolRays=exitNav.calls
R.Creature:_search(b,499)
check(b.DecisionReason=="bounded-local-patrol" and b.TargetX==103
 and b.HabitState=="pending" and exitNav.calls==patrolRays,
 "inside House_02 finishes its local patrol before an old Garage ray may resume")
R.Creature.Search=savedSearch
b.SearchMode="transit" -- this local circuit just completed
local houseHabitRays=exitNav.calls
R.Creature:_search(b,500)
check(b.DecisionReason=="physical-house-exit" and b.ExitSweepKind=="exit" and b.TargetX>114
 and exitNav.calls==houseHabitRays+1 and activeHabit.Evidence==3,
 "witnessed Garage memory cannot take the one House_02 doorway ray or skip its exit")
-- The CENTER has left groundHouse() before the whole radius-1.5 core clears
-- the one-stud pier. A Garage lead here would pull it back through the wall.
b.X,b.Y,b.Z=114.6,9,67
local seamRays=exitNav.calls
R.Creature:_search(b,500.2)
check(b.DecisionReason=="physical-house-exit" and b.ExitSweepKind=="exit"
 and b.TargetX>114 and exitNav.calls==seamRays and activeHabit.Evidence==3,
 "House_02 exit remains owned until its full core clears the east pier")
-- Step the actual planted-foot core across the leftover pier-radius seam;
-- an optimistic Garage ray must not interrupt the low doorway posture.
b.Locomotion:_clearAnchors();b.Locomotion.AnchorAge=math.huge
local seamCrossed,seamSafe,seamPorchFoot=nil,true,false
local seamEnd=h2.PierEastX+b.Stats.CoreRadius+.5
for i=1,150 do
 if (i-1)%12==0 and b.X<=seamEnd then
  local beforeRay=exitNav.calls
  R.Creature:_search(b,500.2+(i-1)/60)
  if exitNav.calls~=beforeRay or b.DecisionReason~="physical-house-exit" then seamSafe=false end
 end
 b:step(1/60)
 for foot=1,b.Locomotion.AnchorCount do
  if b.Locomotion.AnchorPart[foot]==porch2 then seamPorchFoot=true end
 end
 if b.X>=h2.PierWestX-b.Stats.CoreRadius and b.X<=seamEnd
  and (b.Z<h2.DoorMinZ+b.Stats.CoreRadius+.5
   or b.Z>h2.DoorMaxZ-b.Stats.CoreRadius-.5
   or b.Y>math.min(h2.LintelBottom,h2.PorchBottom)-b.Stats.CoreRadius-.5) then
  seamSafe=false
 end
 if b.X>seamEnd then seamCrossed=i;break end
end
check(seamCrossed and seamSafe and seamPorchFoot and b.Locomotion.Crouch>0,
 "House_02 seam grips the real-height porch, stays low and clears the full pier")
local savedCover=R.Creature.HouseCover
R.Creature.HouseCover=nil -- no fake fixture cover:intercept for the exterior
local exteriorRays=exitNav.calls
R.Creature:_search(b,503)
check(b.DecisionReason=="witnessed-three-garage-entries"
 and b.TargetX and b.TargetX<0 and exitNav.calls==exteriorRays+1
 and activeHabit.Evidence==3,
 "outside the House the unchanged witnessed Garage preference resumes on one fresh ray")
-- A planted foot can fail to advance. The held seam must not persist forever
-- or repeatedly spend a Garage ray when the body is motionless at the pier.
b.X,b.Y,b.Z=102,9,67
b.SearchMode,b.SearchClueAt="transit",nil
nav:resetExitSweep(b)
R.Creature:_search(b,600) -- one newly verified outward candidate
b.X,b.Y,b.Z=114.6,9,67
R.Creature:_search(b,600.2) -- real progress, then NO frames of progress
local stalledRays=exitNav.calls
R.Creature:_search(b,603.3)
check(b.DecisionReason=="blocked-house-exit" and b.SearchMode=="patrol"
 and b.TargetX==nil and b.ExitSweepHouse==nil and b.HabitState=="blocked"
 and b.HabitNight==((R.Time and R.Time.nightIndex) or 0)
 and activeHabit.Evidence==3 and exitNav.calls==stalledRays,
 "motionless doorway seam aborts after three seconds and blocks an unsafe Garage retry")
local searchAfterStall=R.Creature.Search
R.Creature.Search={next=function(_,c)return 115.2,c.Y,67 end}
R.Creature:_search(b,603.5)
check(b.DecisionReason=="bounded-local-patrol" and b.TargetX==115.2
 and b.HabitState=="blocked" and exitNav.calls==stalledRays,
 "stalled seam resumes local search, not a fresh Garage ray through its still-overlapping pier")
R.Creature.Search=searchAfterStall
R.Creature.HouseCover=savedCover
R.Creature.GarageHabit=savedHabit
exitNav.Garage,exitNav.Nodes,exitCover.intercept=nil,nil,nil
b.Locomotion.Workspace=originalSupport
R.Creature.Navigation,R.Creature.HouseCover=oldNavigation,oldCover
check(SIM.COUNTERS.runtimeInstanceNew==0,"house-exit sweep creates only numeric goals, no new gameplay Instances")
VitriolRequire("Bootstrap").stop()
return SESSION
