-- Real Think+Core replay of BOTH original House closets in the short genuine
-- last-seen window. Unlike the partial-contact regression, advance Think
-- repeatedly: the body must NOT discard a clue merely because its X/Z came
-- within 7 studs of a point it cannot yet physically reach past the cover.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1;print("PASS  "..msg)
 else SESSION.failed=SESSION.failed+1;print("FAIL  "..msg) end
end
local R=VitriolRequire("Bootstrap").ensure()
local t,cover=R.Time,R.HouseCover
local p=R.Players:addPlayer("OriginalClosetBuilder",86401)
local item=SIM.houseFurniture.House_01_Closet
local piece=cover.ByAction.CoverHouse01Closet
local otherItem=SIM.houseFurniture.House_02_Closet
local otherPiece=cover.ByAction.CoverHouse02Closet
for _,original in ipairs({item,otherItem}) do
 p.Character:FindFirstChild("HumanoidRootPart").Position=original.part.Position
 original.move.Triggered:Fire(p)
 SIM.step(3.3)
 SIM.step(.55)
 SIM.step(.55)
end
check(piece.Placed and otherPiece.Placed and cover.activeCount==2
 and item.part.Position==item.target.Position and otherItem.part.Position==otherItem.target.Position,
 "two independent paid Day actions move BOTH original house closets")
t.phase="Night";cover:onPhaseChanged("Night")
R.Creature:reconcile()
local b=R.Creature.creatures[R.Creature.order[1]]
if b then
 p.Character:FindFirstChild("HumanoidRootPart").Position={X=400,Y=2,Z=400}
 -- Stored real observation is indoors and only 3 studs beyond the original
 -- physical closet once the core reaches its outside crossing plane.
 b.X,b.Y,b.Z=-72,8.6,78
 b.LastKnownPosition={X=-84.5,Y=2,Z=78}
 b.LastKnownAt=t.elapsedTotal or 0
 b.Locomotion.step=function() return -1,0,0,0,1,0 end
 R.Creature:think(.2)
 check(b.CoverPreyX==nil and b.CoverIngressIntent==true and b.TargetX==-87
  and cover:intercept(b.X,b.Z,b.LastKnownPosition.X,b.LastKnownPosition.Z)==piece,
  "recent indoor clue stages through this original closet, with NO currently sensed prey")
 local kept=true
 for i=1,23 do
  b:step(.1)
  if i%2==0 then
   t.elapsedTotal = t.elapsedTotal + .2
   R.Creature:think(.2)
   if b.CoverIngressIntent~=true or b.DecisionReason~="last-genuinely-observed-location" then kept=false end
  end
 end
 check(kept and b.CoverIngressIntent==true,
  "repeated Think keeps an UNREACHED indoor clue while the installed closet blocks the last seven studs")
 check(piece.Placed and piece.Pressure>2 and b.X>piece.Target.Position.X,
  "contact accumulates a real 2.4-second tell from the outside without renewed visibility")
 b:step(.1)
 check(piece.Broken and not piece.Placed and otherPiece.Placed and not otherPiece.Broken
  and cover.activeCount==1 and item.part.CFrame==item.home,
  "24th sustained contact dislodges ONLY House_01's original closet, not House_02's")
 R.Creature:think(.2)
 check(b.LastKnownAt==nil or b.CoverIngressIntent==false,
  "once the physical blocker is gone a reached clue no longer licenses furniture damage")
 -- A separate genuine observed INSIDE point at the other original house:
 -- same near-cover mechanics, independent Part and charge, no stale House_01
 -- route and no fresh sight. Repeated Think must not clear a blocked memory.
 local plane,z=otherPiece.Target.Position.X,otherPiece.Target.Position.Z
 b.X,b.Y,b.Z=plane+9.5,8.6,z
 b.LastKnownPosition={X=plane-3,Y=2,Z=z}
 b.LastKnownAt=t.elapsedTotal or 0
 R.Creature:think(.2)
 check(b.CoverPreyX==nil and b.CoverIngressIntent==true
  and b.TargetX<plane and cover:intercept(b.X,b.Z,plane-3,z)==otherPiece,
  "House_02's own indoor clue stages toward only ITS original closet")
 local secondKept=true
 for i=1,23 do
  b:step(.1)
  if i%2==0 then
   t.elapsedTotal=t.elapsedTotal+.2
   R.Creature:think(.2)
   if b.CoverIngressIntent~=true or b.DecisionReason~="last-genuinely-observed-location" then secondKept=false end
  end
 end
 check(secondKept and otherPiece.Placed and otherPiece.Pressure>2 and b.X>plane,
  "House_02 original closet builds a full contact tell on a blocked recent clue")
 b:step(.1)
 check(otherPiece.Broken and not otherPiece.Placed and otherItem.part.CFrame==otherItem.home
  and piece.Broken and cover.activeCount==0,
  "House_02 independently dislodges after sustained contact; House_01 remains broken")
 R.Creature:think(.2)
 check(b.LastKnownAt==nil or b.CoverIngressIntent==false,
  "House_02 clue likewise becomes reached after its real blocker breaks")
else
 check(false,"authored Braid exists")
end
check(SIM.COUNTERS.runtimeInstanceNew==0,"breach replay created no runtime gameplay/UI Instances")
VitriolRequire("Bootstrap").stop()
return SESSION
