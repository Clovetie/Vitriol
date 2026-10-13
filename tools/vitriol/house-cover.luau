-- Four real prompt paths, original furniture and independent run-long states.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1;print("PASS  "..msg)
 else SESSION.failed=SESSION.failed+1;print("FAIL  "..msg) end
end
local R=VitriolRequire("Bootstrap").ensure()
local t=R.Time
local p=R.Players:addPlayer("Builder",84001)
local h=R.Players:addPlayer("Helper",84002)
local cover=R.HouseCover
local f=SIM.houseFurniture
local function at(player,point)
 player.Character:FindFirstChild("HumanoidRootPart").Position=point.Position
end
local function complete()
 SIM.step(3.3) -- leave room for one 0.1-s Cadence tick after the real deadline
 check(R.Prep:snapshot() and R.Prep:snapshot().stage=="blackout", "the shared three-real-second vote ends before moving furniture")
 SIM.step(.55)
 check(R.Prep:snapshot() and R.Prep:snapshot().stage=="reveal", "authoritative charge and original-part movement occur during blackout")
 SIM.step(.55)
 check(R.Prep:snapshot()==nil, "all-client reveal clears on the existing clock")
end
check(#cover.Pieces==4 and cover.activeCount==0 and f.House_01_Table.move.Enabled
 and f.House_02_Closet.move.Enabled,"both houses start with two individually available original items")
local keys={"House_01_Table","House_01_Closet","House_02_Table","House_02_Closet"}
for i,key in ipairs(keys) do
 local item=f[key]
 local piece=cover.ByAction["Cover"..string.gsub(key,"_","")]
 check(piece~=nil and not piece.Placed and item.part.CFrame==item.home,"authored item "..key.." starts unchanged at home")
 at(p,item.part);at(h,item.part)
 local before,started=t:dayRemaining(),SIM.time()
 item.move.Triggered:Fire(p)
 check(R.Prep:snapshot() and R.Prep:snapshot().action==piece.Action
  and item.assist.Enabled and not piece.Placed,"action "..key.." offers helper vote, not a free move")
 if i==1 then item.assist.Triggered:Fire(h) end
 complete()
 local cost=(before-t:dayRemaining())-(SIM.time()-started)
 local expected=(i==1 or i==3) and 8 or 12
 if i==1 then expected=expected-1 end
 check(math.abs(cost-expected)<.02 and piece.Placed and not piece.Broken
  and item.part.Position==item.target.Position and not item.move.Enabled and cover.activeCount==i,
  key.." charges once, moves ONLY its original Part and disables repeat")
end
local first=cover.ByAction.CoverHouse01Table
local second=cover.ByAction.CoverHouse01Closet
local third=cover.ByAction.CoverHouse02Table
local fourth=cover.ByAction.CoverHouse02Closet
check(first.Part.Size.X==9 and second.Part.Size.X==6 and first.Part.Size.Y<2
 and first.Target.Position.Z+first.Width*.5 < second.Target.Position.Z-second.Width*.5,
 "table stays low, closet stays full-sized and their authored doorway gap remains open")
t.phase="Dawn";cover:onPhaseChanged("Dawn")
check(cover.activeCount==4 and first.Placed and fourth.Placed,
 "Dawn and death independent: no one-night reset of installed furniture")
t.phase="Night";cover:onPhaseChanged("Night")
check(not first.Prompt.Enabled and not first.Helper.Enabled and not cover:ready(first.Action,p),
 "Night disables building and retains the accepted shared Day-time cost contract")
local x,z=first.DoorX,first.Target.Position.Z
check(cover:intercept(x+7,z,x-8,z)==first and cover:bracing(x+7,z,x-9,z)==first,
 "a sensed player BEHIND the table leads a real doorway-crossing and close bracing contact")
check(cover:intercept(x+7,z+15,x-8,z+15)==nil and cover:bracing(x+7,z+15,x-9,z+15)==nil,
 "Braid can pass an uncovered doorway section instead of encountering a fake full-width wall")
check(cover:bracing(x+30,z,x-9,z)==nil,"a far Braid cannot damage furniture remotely")
R.Creature:reconcile()
local braid=R.Creature.creatures[R.Creature.order[1]]
if braid then
 -- Human Play: the original House_01 closet finally broke at an outside
 -- core(-72,8.6,78) after the survivor briefly revealed themself. A genuinely
 -- observed indoor point should keep a REAL near-cover push motivated even
 -- across a short loss of sight; an expired clue must not. No hidden root read.
 local px,pz=second.Target.Position.X,second.Target.Position.Z
 at(p,f.House_01_Table.part)
 p.Character:FindFirstChild("HumanoidRootPart").Position={X=400,Y=2,Z=400}
 h.Character:FindFirstChild("HumanoidRootPart").Position={X=450,Y=2,Z=450}
 braid.X,braid.Y,braid.Z=-72,8.6,78
 braid.LastKnownPosition={X=px-8,Y=2,Z=pz}
 braid.LastKnownAt=t.elapsedTotal or 0
 R.Creature:think(.2)
 check(braid.CoverPreyX==nil and braid.CoverIngressIntent==true and braid.TargetX<px
  and cover:bracing(braid.X,braid.Z,braid.TargetX,braid.TargetZ)==second,
  "recent genuinely seen indoor clue motivates near ORIGINAL closet contact without live hidden prey")
 braid.Locomotion.step=function() return -1,0,0,0,1,0 end
 for i=1,10 do braid:step(.1) end
 check(second.Placed and second.Pressure>.9 and braid.X>px,
  "recent-clue pressure builds only while outside body physically braces contacted closet")
 braid.LastKnownAt=(t.elapsedTotal or 0)-9
 R.Creature:think(.2)
 braid:step(.1)
 check(second.Placed and second.Pressure==0 and braid.CoverIngressIntent==false,
  "expired last-observed clue cannot keep pressing or release the closet")
 -- A last-seen exterior/Porch point does not grant indoor-cover pressure.
 braid.X,braid.Y,braid.Z=-72,8.6,78
 braid.LastKnownPosition={X=-72.1,Y=2,Z=67.2}
 braid.LastKnownAt=t.elapsedTotal or 0
 R.Creature:think(.2)
 check(not braid.CoverIngressIntent,
  "real outside Porch memory never authorizes an inside-cover breach")
 -- The other authored house uses the same short-clue rule, its OWN target
 -- plane, and a separately placed original closet.
 local h2x,h2z=fourth.Target.Position.X,fourth.Target.Position.Z
 braid.X,braid.Y,braid.Z=h2x+9.5,8.6,h2z
 braid.LastKnownPosition={X=h2x-8,Y=2,Z=h2z}
 braid.LastKnownAt=t.elapsedTotal or 0
 R.Creature:think(.2)
 check(braid.CoverIngressIntent and braid.TargetX<h2x
  and cover:bracing(braid.X,braid.Z,braid.TargetX,braid.TargetZ)==fourth,
  "House_02 recent indoor clue braces only its own near original closet")
 cover:loseContact()
 braid.LastKnownAt,braid.LastKnownPosition=nil,nil
 braid.X,braid.Y,braid.Z=x+7,8,z
 p.Character:FindFirstChild("HumanoidRootPart").Position={X=x-9,Y=2,Z=z}
 h.Character:FindFirstChild("HumanoidRootPart").Position={X=x+300,Y=2,Z=z+300}
 R.Creature:think(.2)
 check(braid.CoverPreyX==x-9 and braid.CoverPreyZ==z and braid.AttackPhase==nil,
  "real creature Think sees nearby prey but cannot initiate chomp through installed table")
 -- An inside survivor near the far side of a room is reached by the main
 -- doorway lane, not a straight segment THROUGH the solid east pier.
 p.Character:FindFirstChild("HumanoidRootPart").Position={X=x-14,Y=2,Z=first.DoorZ+12}
 braid.X,braid.Y,braid.Z=x+6,8,first.DoorZ+6
 R.Creature:think(.2)
 braid.Locomotion.step=function() return -1,0,0,0,1,0 end
 braid:step(.1)
 check(braid.TargetX==x-8 and braid.TargetZ==first.DoorZ+6
  and second.Pressure>0 and first.Pressure==0,
  "real route braces contacted CLOSET, not a missed direct ray to a deep-room player")
 cover:loseContact()
 p.Character:FindFirstChild("HumanoidRootPart").Position={X=x-9,Y=2,Z=z}
 braid.X,braid.Y,braid.Z=x+7,8,z
 R.Creature:think(.2)
else check(false,"real authored Braid exists for installed-cover Think test") end
if braid then
 -- Drive the REAL core's interception path with a deterministic approach;
 -- it still calls live TendrilRig/render code, but uses a fixed motion delta.
 braid.Locomotion.step=function() return -1,0,0,0,1,0 end
 braid.X=first.Target.Position.X+.5
 braid.CoverPreyX,braid.CoverPreyZ=nil,nil
 braid:step(.1)
 check(braid.X>first.Target.Position.X and first.Placed and first.Pressure==0,
  "last-known/lure movement cannot ghost through cover or dislodge it without sensed prey")
 local advance=braid._advanceChomp
 braid._advanceChomp=function() end
 braid.AttackPhase,braid.ChargeX,braid.ChargeZ,braid.ChargeTraveled="CHARGE",-1,0,0
 braid:step(.1)
 check(braid.X>first.Target.Position.X and first.Pressure==0,
  "a chomp charge started before cover is installed cannot tunnel through it")
 local originalKill=R.Health.beginCreatureKill
 local killAttempts,priorY=0,braid.Y
 R.Health.beginCreatureKill=function() killAttempts=killAttempts+1; return false end
 braid.Y=3 -- crouched Braid near a grounded survivor, rather than high core
 p.Character:FindFirstChild("HumanoidRootPart").Position={X=first.Target.Position.X-1.5,Y=2,Z=z}
 braid.AttackPlayer=p
 R.Creature:step(.1)
 check(killAttempts==0 and first.Placed,
  "frame-contact cannot kill through a low table when the high horizontal sight ray is clear")
 local openZ=first.DoorZ+1.5 -- actual one-stud opening between 9 + 6 widths
 braid.X,braid.Z,braid.ChargeTraveled=first.Target.Position.X+.5,openZ,0
 p.Character:FindFirstChild("HumanoidRootPart").Position={X=first.Target.Position.X-1.5,Y=2,Z=openZ}
 R.Creature:step(.1)
 check(killAttempts==1,
  "the genuine gap is NOT falsely protected as an invulnerable full-width doorway")
 R.Health.beginCreatureKill=originalKill
 braid.X,braid.Y,braid.Z=first.Target.Position.X+.5,priorY,z
 p.Character:FindFirstChild("HumanoidRootPart").Position={X=x-9,Y=2,Z=z}
 braid.AttackPhase,braid.AttackPlayer,braid.ChargeTraveled=nil,nil,0
 braid._advanceChomp=advance
 braid.CoverPreyX,braid.CoverPreyZ=x-9,z
 for i=1,10 do braid:step(.1) end
 check(first.Placed and first.Pressure>.9 and braid.X>first.Target.Position.X,
  "actual near-prey bracing builds pressure while the core remains outside")
 braid:setDormant(true)
 check(first.Pressure==0 and first.Placed,
  "the same Braid withdrawing cancels its unfinished attack, not the placed cover")
 braid:setDormant(false)
 braid:setTarget(x-9,2,z,.5)
 braid.CoverPreyX,braid.CoverPreyZ=x-9,z
 for i=1,10 do braid:step(.1) end
 braid.CoverPreyX,braid.CoverPreyZ=nil,nil
 braid:step(.1)
 check(first.Placed and first.Pressure==0 and braid.X>first.Target.Position.X,
  "losing contact resets an unfinished furniture breach without phasing")
 braid.CoverPreyX,braid.CoverPreyZ=x-9,z
 for i=1,23 do braid:step(.1) end
 check(first.Placed and braid.X>first.Target.Position.X,
  "23 fresh contacts remain below the full sustained breach threshold")
 braid:step(.1)
end
check(first.Broken and not first.Placed
 and first.Part.CFrame==f.House_01_Table.home and second.Placed and third.Placed and fourth.Placed
 and cover.activeCount==3,"core's sustained Night pressure dislodges ONLY contacted table")
check(not cover:press(first,2) and cover.activeCount==3,"repeat attack cannot duplicate damage")
t.phase="Day";cover:onPhaseChanged("Day")
check(first.Prompt.Enabled and not second.Prompt.Enabled and not cover:ready(second.Action,p),
 "next Day re-enables ONLY broken item; intact installed items cannot be re-bought")
at(p,first.Part);at(h,first.Part)
local before,started=t:dayRemaining(),SIM.time()
first.Prompt.Triggered:Fire(p)
at(h,f.House_01_Table.target) -- an occupant arrives DURING the vote
SIM.step(3.15)
check(not first.Placed and R.Prep:snapshot()==nil
 and math.abs((before-t:dayRemaining())-(SIM.time()-started))<.02,
 "doorway occupant during vote cancels move without an authoritative time charge")
at(h,first.Part)
before,started=t:dayRemaining(),SIM.time()
first.Prompt.Triggered:Fire(p)
complete()
check(math.abs((before-t:dayRemaining())-(SIM.time()-started)-8)<.02
 and cover.activeCount==4 and first.Placed and not first.Broken,
 "rebuilding damaged table costs Day time again without resetting other house")
-- The user's Night log placed the Braid INSIDE House_01 trying to reach an
-- OUTSIDE last-observed point: both straight paths cross the original closet.
t.phase="Night";cover:onPhaseChanged("Night")
local px,pz=second.Target.Position.X,second.Target.Position.Z
check(cover:intercept(-91.7,79.4,-57.5,78.9)==second
 and cover:intercept(-90.9,78.3,-63.9,77.9)==second
 and cover:bracing(-91.7,79.4,-57.5,78.9,true)==second,
 "BOTH real logged stalls are near-reach INSIDE-to-OUTSIDE closet contacts")
check(cover:bracing(px+7,pz,px-9,pz,true)==nil
 and cover:bracing(px-30,pz,-57.5,78.9,true)==nil,
 "memory/lure exit authority cannot attack from outside or at long range")
if braid then
 braid.X,braid.Y,braid.Z=px-.5,8,pz
 braid.Locomotion.step=function() return 1,0,0,0,1,0 end
 braid.CoverPreyX,braid.CoverPreyZ=nil,nil
 braid.CoverExitIntent=false
 braid:setTarget(-57.5,2,78.9,.2)
 braid:step(.1)
 check(braid.X<px and second.Placed and second.Pressure==0,
  "without a valid pursuit motive the body cannot ghost OUT or damage furniture")
 p.Character:FindFirstChild("HumanoidRootPart").Position={X=500,Y=2,Z=500}
 h.Character:FindFirstChild("HumanoidRootPart").Position={X=550,Y=2,Z=550}
 braid.X,braid.Y,braid.Z=-91.7,8,79.4
 braid.LastKnownPosition={X=-57.5,Y=2,Z=78.9}
 braid.LastKnownAt=(t.elapsedTotal or 0)-9
 R.Creature:think(.2)
 check(not braid.CoverExitIntent and braid.CoverPreyX==nil and second.Pressure==0,
  "expired last-known prey cannot authorize a closet breach even while Night search continues")
 braid.LastKnownAt=t.elapsedTotal or 0
 R.Creature:think(.2)
 check(braid.CoverExitIntent and braid.CoverPreyX==nil and braid.TargetX==-57.5,
  "real Think pursues only the valid LAST OBSERVED outside point, no hidden live GPS")
 local oldLog, breakLine=cover.Logger,nil
 cover.Logger=function(level,message)
  if string.find(message,"Braid dislodged House_01 Closet",1,true) then breakLine=message end
  if oldLog then oldLog(level,message) end
 end
 for i=1,23 do braid:step(.1) end
 check(second.Placed and second.Pressure>2 and braid.X<px,
  "inside Braid remains at the closet during its sustained bracing tell")
 braid:step(.1)
 check(second.Broken and not second.Placed and second.Part.CFrame==f.House_01_Closet.home
  and first.Placed and third.Placed and fourth.Placed and braid.X>px,
  "reverse egress dislodges ONLY the contacted original closet, then resumes outside")
 check(breakLine and string.find(breakLine,"paid Day move required",1,true)
  and string.find(breakLine,"core(",1,true)
  and string.find(breakLine,"nav(-57.5,",1,true)
  and string.find(breakLine,"reason=last-genuinely-observed-location",1,true)
  and string.find(breakLine,"feet=",1,true),
  "existing one-per-break Output includes the actual Braid contact pose, goal, decision and feet")
 cover.Logger=oldLog
 -- Crossing on the exact breach frame is not enough: the next REAL Think
 -- must still have a valid observed goal and not snap back to the doorway.
 local afterBreachX=braid.X
 R.Creature:think(.2)
 for i=1,3 do braid:step(.1) end
 check(braid.TargetX~=nil and braid.X>afterBreachX and second.Broken
  and first.Placed and third.Placed and fourth.Placed,
  "after dislodgement the next Think continues the Braid's outside pursuit without resetting other cover")
 -- House_02 has its own original closet/marker, not a reused House_01 ray.
 -- Repeat the REVERSE exit while House_01's closet is already broken: neither
 -- house's table should reset or silently pay for the other house's breach.
 local h2x,h2z=fourth.Target.Position.X,fourth.Target.Position.Z
 local h2Inside,h2Outside=h2x-10.2,h2x+23
 check(cover:intercept(h2Inside,h2z,h2Outside,h2z)==fourth
  and cover:bracing(h2Inside,h2z,h2Outside,h2z,true)==fourth,
  "House_02 original closet also intercepts a near inside-to-outside route")
 braid.X,braid.Y,braid.Z=h2Inside,8,h2z
 braid.LastKnownPosition={X=h2Outside,Y=2,Z=h2z}
 braid.LastKnownAt=t.elapsedTotal or 0
 R.Creature:think(.2)
 check(braid.CoverExitIntent and braid.CoverPreyX==nil and braid.TargetX==h2Outside,
  "House_02 exit follows a valid last OBSERVED outside goal, not a hidden live player")
 for i=1,23 do braid:step(.1) end
 check(fourth.Placed and fourth.Pressure>2 and braid.X<h2x,
  "House_02 closet remains in place during sustained reverse bracing")
 braid:step(.1)
 check(fourth.Broken and not fourth.Placed and fourth.Part.CFrame==f.House_02_Closet.home
  and braid.X>h2x and second.Broken and first.Placed and third.Placed
  and cover.activeCount==2,
  "House_02 exit dislodges ONLY its original closet without disturbing either table")
end
t.phase="Dawn";cover:onPhaseChanged("Dawn")
check(second.Prompt.Enabled and fourth.Prompt.Enabled and first.Placed and third.Placed
 and cover.activeCount==2,
 "both broken closets offer separate paid moves; tables remain run-long through Dawn")
check(SIM.COUNTERS.runtimeInstanceNew==0,"no UI, furniture, prompts or markers created in Play")
VitriolRequire("Bootstrap").stop()
return SESSION
