-- Offline-only REAL planted-foot Core/Think against separately measured
-- Ground Y=0, Porch Y=1, Floor Y=.8 and the original House_01 roof underside.
-- Stored indoor clue + original closet, with no player currently visible.
-- Pure table proxies for support ray hits; no runtime gameplay Part is made.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1;print("PASS  "..msg)
 else SESSION.failed=SESSION.failed+1;print("FAIL  "..msg) end
end
local r=VitriolRequire("Bootstrap").ensure()
local time,cover=r.Time,r.HouseCover
local player=r.Players:addPlayer("FootedClue",86701)
local original=SIM.houseFurniture.House_01_Closet
local piece=cover.ByAction.CoverHouse01Closet
local table=SIM.houseFurniture.House_01_Table
local tablePiece=cover.ByAction.CoverHouse01Table
for _,item in ipairs({table,original}) do
 player.Character:FindFirstChild("HumanoidRootPart").Position=item.part.Position
 item.move.Triggered:Fire(player)
 SIM.step(3.3);SIM.step(.55);SIM.step(.55)
end
check(piece.Placed and tablePiece.Placed and cover.activeCount==2,
 "two paid Day moves install BOTH original House_01 pieces, as in the Play")
time.phase="Night";cover:onPhaseChanged("Night")
player.Character:FindFirstChild("HumanoidRootPart").Position={X=400,Y=2,Z=400}
local house=SIM.structures.House_01
local floor=house.Floor
local porch={Name="Porch",Position={X=floor.Position.X+29,Y=.5,Z=floor.Position.Z},Size={X=15,Y=1,Z=29}}
local ground={Name="Ground_QuarryFoundation",Position={X=floor.Position.X,Y=-.5,Z=floor.Position.Z},Size={X=300,Y=1,Z=300}}
local support={Raycast=function(_,origin,direction)
 if direction.Y==0 then return nil end
 local bestT,bestPart,bestY=nil,nil,nil
 local function consider(part,level)
  local t=(level-origin.Y)/direction.Y
  if t<0 or t>1 or (bestT and t>=bestT) then return end
  local x,z=origin.X+direction.X*t,origin.Z+direction.Z*t
  if math.abs(x-part.Position.X)<=part.Size.X*.5
   and math.abs(z-part.Position.Z)<=part.Size.Z*.5 then
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
r.Creature:reconcile()
local b=r.Creature.creatures[r.Creature.order[1]]
if b then
 b.Locomotion.Workspace=support
 b.Locomotion:_clearAnchors();b.Locomotion.AnchorAge=math.huge
 b.X,b.Y,b.Z=-72,8.6,78
 b.LastKnownPosition={X=-84.5,Y=2,Z=78}
 b.LastKnownAt=time.elapsedTotal or 0
 r.Creature:think(.2)
 check(b.CoverIngressIntent and b.CoverPreyX==nil and b.TargetX==-87,
  "real Think stages remembered House_01 clue through original closet")
 local sawPorch,sawGround,sawFoot,sawPressure,sawBreak=false,false,false,false,false
 local firstBreakFrame=nil
 for frame=1,480 do
  if (frame-1)%12==0 and frame>1 then
   time.elapsedTotal=time.elapsedTotal+.2
   r.Creature:think(.2)
  end
  b:step(1/60)
  for foot=1,b.Locomotion.AnchorCount do
   local part=b.Locomotion.AnchorPart[foot]
   if part==porch then sawPorch=true end
   if part==ground then sawGround=true end
  end
  if b.Locomotion:anchors()>0 then sawFoot=true end
  if piece.Pressure>0 then sawPressure=true end
  if piece.Broken then sawBreak=true;firstBreakFrame=frame;break end
 end
 check(sawFoot and sawPorch and sawGround,
  "real planted-foot body uses measured exterior Ground AND Porch, not a scripted -1 movement")
 check(sawPressure,"normal footed motion reaches near ORIGINAL closet bracing before clue expiry")
 check(sawBreak and firstBreakFrame<=480 and original.part.CFrame==original.home
  and tablePiece.Placed and not tablePiece.Broken and cover.activeCount==1,
  "real footed remembered-clue contact dislodges ONLY closet before expiry; original table stays")
 check(b.Y<12.5 and b.Locomotion:anchors()>0,
  "body remains foot-supported under original porch/roof instead of phasing above it")
else check(false,"authored Braid exists") end
check(SIM.COUNTERS.runtimeInstanceNew==0,"no runtime gameplay/UI Instances created")
VitriolRequire("Bootstrap").stop()
return SESSION
