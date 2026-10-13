-- M3 first witnessed Garage-habit priority, never hidden-player GPS.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1;print("PASS  "..msg)
 else SESSION.failed=SESSION.failed+1;print("FAIL  "..msg) end
end
local Habit=VitriolRequire("GarageHabit")
local cfg={WorkingCapacity=12,GarageVisitsForPrediction=3,GarageLeadArriveStuds=10}
local floor={Position={X=-90,Y=.42,Z=-56},Size={X=56,Z=46},
 IsA=function(_,name)return name=="BasePart" end}
local roof={Position={Y=19},Size={Y=1.4},IsA=function(_,name)return name=="BasePart" end}
local garage={FindFirstChild=function(_,name)
 if name=="Floor" then return floor end
 if name=="Roof" then return roof end
 return nil
end}
local nav={Garage=garage,Nodes={{-55,-56}},calls=0,
 hit=function()return nil end,
 clear=function(self)self.calls=self.calls+1;return true end}
local habit=Habit.new(cfg,nav,{ClueSeconds=25,StallSeconds=3})
check(not habit:observe(7,-90,4,-56) and habit.Visits==0,
 "first glimpse already inside does NOT invent a witnessed entry")
check(not habit:observe(7,-55,4,-56) and habit:observe(7,-90,4,-56)
 and habit.Visits==1,"witnessed outside to inside counts one actual Garage entry")
habit:observe(7,-90,4,-56)
check(habit.Visits==1,"seeing the same survivor each Think cannot inflate visits")
habit:observe(7,-90,18,-56)
check(habit.ObservedInside[7]==nil and habit.Visits==1,
 "roof-level survivor is neither an inside nor an outside ground-level witness")
check(not habit:observe(7,-90,4,-56) and habit.Visits==1,
 "falling from Garage roof into interior cannot invent an outside-to-inside entry")
habit:observe(7,-55,4,-56)
habit:observe(7,-90,4,-56)
habit:observe(7,-55,4,-56)
habit:observe(7,-90,4,-56)
check(habit.Visits==3 and habit:dump().predictsGarage,
 "three witnessed entries create a fourth-visit Garage expectation")
local discontinuous=Habit.new(cfg,nav,{})
discontinuous:observe(8,-55,4,-56)
discontinuous:markUnseenExcept(nil)
check(not discontinuous:observe(8,-90,4,-56) and discontinuous.Visits==0,
 "lost sensing between exterior and interior does NOT fabricate a visit")
discontinuous:observe(8,-55,4,-56)
discontinuous:markUnseenExcept(9) -- another player is now nearest
check(not discontinuous:observe(8,-90,4,-56) and discontinuous.Visits==0,
 "another sensed player interrupts the original survivor's witnessed path")
discontinuous:observe(8,-55,4,-56)
check(discontinuous:observe(8,-90,4,-56) and discontinuous.Visits==1,
 "new continuous ground-level outside-to-inside sensing still learns")
local c={X=0,Y=8,Z=0}
local x,z,why=habit:lead(c,3,0,nav,nil)
check(x==-55 and z==-56 and why=="witnessed-three-garage-entries" and nav.calls==1,
 "clue-less Night search prefers authored Garage front approach with ONE safety ray")
local prior=nav.calls
x,z=habit:lead(c,3.2,0,nav,nil)
check(x==-55 and nav.calls==prior,"cached habit goal spends zero extra rays each Think")
c.SearchClueAt=3.2
x,z=habit:lead(c,3.3,0,nav,nil)
check(x==nil and c.HabitState=="pending","fresh genuine clue interrupts habit goal")
c.SearchClueAt=nil
x,z=habit:lead(c,30,0,nav,nil)
check(x==-55 and nav.calls==prior+1,
 "resumed Garage approach is physically revalidated after a clue interruption")
c.X,c.Z=-55,-56
x,z,why=habit:lead(c,31,0,nav,nil)
check(x==-90 and z==-56 and why=="physical-garage-investigation"
 and c.HabitState=="inside" and habit.PredictionMisses==0 and nav.calls==prior+2,
 "front arrival is NOT negative evidence; Braid tests one ray then enters the real Garage")
local held=nav.calls
x,z=habit:lead(c,31.2,0,nav,nil)
check(x==-90 and nav.calls==held,"held interior leg uses no extra Think ray")
c.X,c.Z=-90,-56
x,z,why=habit:lead(c,32,0,nav,nil)
check(x==nil and why=="arrived" and c.HabitState=="arrived" and habit.PredictionMisses==1,
 "only an unproductive PHYSICAL interior visit lowers Garage confidence")
c.X,c.Z=0,0
x,z=habit:lead(c,32,0,nav,nil)
check(x==nil,"one prediction does not repeat in the same Night")
x,z=habit:lead(c,33,1,nav,nil)
check(x==nil and not habit:dump().predictsGarage and habit:dump().effectiveEvidence==2,
 "one unsupported Garage guess does not repeat every Night forever")
habit:observe(7,-55,4,-56)
check(habit:observe(7,-90,4,-56) and habit.Visits==4,
 "only new witnessed evidence restores confidence after a wrong guess")
x,z=habit:lead(c,34,1,nav,nil)
check(x==-55 and c.HabitNight==1 and habit:dump().effectiveEvidence==3,
 "new witnessed entry can revive a later Night's Garage preference")
local blocked={Garage=garage,Nodes={{-55,-56}},calls=0,
 clear=function(self)self.calls=self.calls+1;return false end}
local other=Habit.new(cfg,blocked,{StallSeconds=3})
other.Visits,other.Evidence=3,3
local b={X=0,Y=8,Z=0}
x,z,why=other:lead(b,0,0,blocked,nil)
check(x==nil and why=="blocked" and b.HabitState=="blocked",
 "solid obstruction rejects Garage prediction without wall phasing")
local rays=blocked.calls
x,z=other:lead(b,1,0,blocked,nil)
check(x==nil and blocked.calls==rays,"blocked Garage prediction does not raycast every Think")
local gated={Garage=garage,Nodes={{-55,-56}},calls=0,
 clear=function(self,_,_,tx)self.calls=self.calls+1;return tx~=-90 end}
local gatedHabit=Habit.new(cfg,gated,{StallSeconds=3})
gatedHabit.Evidence=3
local blockedInside={X=0,Y=8,Z=0}
local frontX,frontZ=gatedHabit:lead(blockedInside,0,0,gated,nil)
blockedInside.X,blockedInside.Z=frontX,frontZ
x,z,why=gatedHabit:lead(blockedInside,1,0,gated,nil)
check(x==nil and why=="blocked" and gated.calls==2
 and gatedHabit.PredictionMisses==0 and gatedHabit.Evidence==3,
 "solid Garage interior barrier stops entry, never invents absence from outside")
local onRoof=Habit.new(cfg,nav,{})
onRoof.Evidence=3
local roofBefore=nav.calls
x,z,why=onRoof:lead({X=-90,Y=21,Z=-56},0,0,nav,nil)
check(x==nil and why=="blocked" and onRoof.PredictionMisses==0
 and nav.calls==roofBefore and onRoof.CoreCeilingY<18,
 "garage roof projection is NOT a physical inside check or negative evidence")
local noSensor=Habit.new(cfg,nav,{})
noSensor.Evidence=3
x,z,why=noSensor:lead({X=0,Y=8,Z=0},0,0,nil,nil)
check(x==nil and why=="blocked" and noSensor.PredictionMisses==0,
 "missing navigation sensor cannot grant a prediction through a wall")
local corners={{-55,-56},{-55,-86},{-125,-86},{-125,-56},{-125,-26},{-55,-26}}
local flankNav={Garage=garage,Nodes=corners,calls=0,blocked=false,
 clear=function(self) self.calls=self.calls+1;return not self.blocked end}
local flankHabit=Habit.new(cfg,flankNav,{StallSeconds=3})
flankHabit.Evidence=3
local west={X=-130,Y=8,Z=-56}
x,z,why=flankHabit:lead(west,1,0,flankNav,nil)
check(x==-125 and z==-86 and why=="witnessed-garage-flank" and flankNav.calls==1
 and west.HabitState=="flankWest", "west-of-garage habit takes ONE ray toward authored north-west corner")
local heldFlank=flankNav.calls
x,z=flankHabit:lead(west,1.2,0,flankNav,nil)
check(x==-125 and z==-86 and flankNav.calls==heldFlank,
 "held exterior flank waypoint adds no per-Think safety ray")
west.X,west.Z=-125,-86
x,z,why=flankHabit:lead(west,2,0,flankNav,nil)
check(x==-55 and z==-86 and west.HabitState=="flankEast" and flankNav.calls==heldFlank+1,
 "west corner advances to existing east-north corner with one new ray")
west.X,west.Z=-55,-86
x,z=flankHabit:lead(west,3,0,flankNav,nil)
check(x==-55 and z==-56 and west.HabitState=="front" and flankNav.calls==heldFlank+2,
 "east corner then reaches the real front, not a wall shortcut")
west.X,west.Z=-55,-56
x,z,why=flankHabit:lead(west,4,0,flankNav,nil)
check(x==-90 and z==-56 and why=="physical-garage-investigation" and flankNav.calls==heldFlank+3,
 "flanked habit STILL physically checks interior before lowering confidence")
local southHabit=Habit.new(cfg,flankNav,{})
southHabit.Evidence=3
local south={X=-90,Y=8,Z=25}
local southBefore=flankNav.calls
x,z,why=southHabit:lead(south,1,0,flankNav,nil)
check(x==-55 and z==-26 and why=="witnessed-garage-flank" and flankNav.calls==southBefore+1,
 "south of authored wall first reaches east-south external corner with one ray")
south.X,south.Z=-55,-26
x,z=southHabit:lead(south,2,0,flankNav,nil)
check(x==-55 and z==-56 and flankNav.calls==southBefore+2,
 "south external corner proceeds to front without crossing the garage wall")
local northHabit=Habit.new(cfg,flankNav,{})
northHabit.Evidence=3
x,z=northHabit:lead({X=-90,Y=8,Z=-140},1,0,flankNav,nil)
check(x==-55 and z==-86 and flankNav.calls==southBefore+3,
 "north of authored wall approaches its external east-north corner")
local denyNav={Garage=garage,Nodes=corners,calls=0,
 clear=function(self) self.calls=self.calls+1;return false end}
local denied=Habit.new(cfg,denyNav,{})
denied.Evidence=3
x,z,why=denied:lead({X=-130,Y=8,Z=-56},1,0,denyNav,nil)
check(x==nil and why=="blocked" and denyNav.calls==1 and denied.PredictionMisses==0,
 "blocked flank spends one ray, does not phase or invent an empty Garage")
local flankInterrupted=Habit.new(cfg,flankNav,{StallSeconds=3,ClueSeconds=25})
flankInterrupted.Evidence=3
local reroute={X=-130,Y=8,Z=-56}
local beforeFlank=flankNav.calls
x,z=flankInterrupted:lead(reroute,10,1,flankNav,nil)
reroute.SearchClueAt=10
x,z=flankInterrupted:lead(reroute,10.2,1,flankNav,nil)
check(x==nil and reroute.HabitState=="pending" and flankNav.calls==beforeFlank+1,
 "fresh genuine clue interrupts flank without another ray")
reroute.SearchClueAt=nil
x,z=flankInterrupted:lead(reroute,40,1,flankNav,nil)
check(x==-125 and z==-86 and flankNav.calls==beforeFlank+2,
 "resumed west flank must revalidate the authored corner after clue")
local missingCorners=Habit.new(cfg,nav,{})
missingCorners.Evidence=3
local noCornerCalls=nav.calls
x,z,why=missingCorners:lead({X=-130,Y=8,Z=-56},0,0,nav,nil)
check(x==nil and why=="blocked" and nav.calls==noCornerCalls,
 "missing authored flank nodes fail closed rather than raycasting a made-up corner")
local cover={activeCount=1,intercept=function()return true end}
local defended=Habit.new(cfg,nav,{StallSeconds=3})
defended.Visits,defended.Evidence=3,3
x,z,why=defended:lead({X=0,Y=8,Z=0},0,0,nav,cover)
check(x==nil and why=="blocked","placed cover is not breached by a mere prediction")
local old=Habit.new(cfg,nav,{StallSeconds=3})
old.Visits,old.Evidence=3,3
local stuck={X=0,Y=8,Z=0}
x,z=old:lead(stuck,0,0,nav,nil)
x,z,why=old:lead(stuck,4,0,nav,nil)
check(x==nil and why=="blocked","no-progress lead safely gives up after three seconds")
habit:forget(7)
check(habit.ObservedInside[7]==nil and habit.Visits==4 and habit.PredictionMisses==1,
 "leaving player frees observed state without erasing run-local learned evidence")
local missing=Habit.new(cfg,nil,{})
check(not missing:observe(7,-90,4,-56) and missing:dump().predictsGarage==false,
 "missing authored Garage fails closed instead of fabricating a waypoint")
local saturated=Habit.new(cfg,nav,{})
for i=1,14 do
 saturated:observe(5,-55,4,-56)
 saturated:observe(5,-90,4,-56)
end
check(saturated.Visits==12 and saturated.Evidence==3,
 "long-run memory counters and actionable confidence are bounded")
local late={X=0,Y=8,Z=0}
x,z=saturated:lead(late,0,0,nav,nil)
late.X,late.Z=x,z
local centerX,centerZ=saturated:lead(late,1,0,nav,nil)
check(centerX==-90 and saturated.PredictionMisses==0,
 "exterior-only Garage check cannot reduce saturated confidence")
late.X,late.Z=centerX,centerZ
saturated:lead(late,2,0,nav,nil)
check(saturated:dump().effectiveEvidence==2,
 "a physically checked but unproductive interior can lower bounded confidence")
saturated:observe(5,-55,4,-56)
saturated:observe(5,-90,4,-56)
check(saturated.Visits==12 and saturated:dump().effectiveEvidence==3,
 "new genuine sighting restores confidence even AFTER visit counter saturates")
-- The service is the only authority allowed to pass an actually seen root.
local R=VitriolRequire("Bootstrap").ensure()
local p=R.Players:addPlayer("WitnessedGarageVisitor",9077)
local braid=R.Creature.creatures[R.Creature.order[1]]
braid.X,braid.Y,braid.Z=-40,8,-56
R.Time.phase="Night";R.DayPrep:onPhaseChanged("Night");R.Floodlight:onPhaseChanged("Night")
local root=p.Character:FindFirstChild("HumanoidRootPart")
R.Creature.Navigation=nav
R.Creature.GarageHabit=Habit.new(cfg,nav,R.Monster.InstinctSearch)
R.Creature.Noise=nil -- headless witness sequence; no fake sound
root.Position={X=-55,Y=4,Z=-56};R.Creature:think(.2)
root.Position={X=240,Y=4,Z=240};R.Creature:think(.2) -- genuinely NOT sensed
root.Position={X=-90,Y=4,Z=-56};R.Creature:think(.2)
check(R.Creature.GarageHabit.Visits==0,
 "real service breaks exterior evidence upon unseen travel, never counts reacquisition inside")
R.Creature.GarageHabit=Habit.new(cfg,nav,R.Monster.InstinctSearch)
-- Walk the actual entrance threshold in short visible steps, not a fixture
-- teleport from exterior approach directly into the room every Think.
local entrySteps={-55,-60,-62,-63,-64,-65,-70,-80,-90}
local exitSteps={-80,-70,-65,-64,-63,-62,-60,-55}
local thresholdStayedPhysical=true
for visit=1,3 do
 for _,px in ipairs(entrySteps) do
  root.Position={X=px,Y=4,Z=-56};R.Creature:think(.2)
  if px == -63 and R.Creature.GarageHabit.Visits ~= visit-1 then thresholdStayedPhysical=false end
  if px == -64 and R.Creature.GarageHabit.Visits ~= visit then thresholdStayedPhysical=false end
 end
 if visit < 3 then
  for _,px in ipairs(exitSteps) do root.Position={X=px,Y=4,Z=-56};R.Creature:think(.2) end
 end
end
check(thresholdStayedPhysical,
 "real service counts each entry at grounded floor threshold, not outside or repeated inside")
check(R.Creature.GarageHabit.Visits==3 and braid.DecisionReason=="genuinely-sensed-prey",
 "real service witnesses transitions but fresh prey still wins over remembered pattern")
check(braid.GarageExplainEvent=="witness-threshold"
 and not string.find(LOGSTRING,"Garage habit witnessed entries=3",1,true),
 "third real witness queues server-only explanation WITHOUT logging inside measured Think")
R.Cadence.onSample("Time:Publish",.1,1)
check(braid.GarageExplainEvent=="witness-threshold"
 and not string.find(LOGSTRING,"Garage habit witnessed entries=3",1,true),
 "unrelated cadence samples cannot flush a Garage witness")
R.Cadence.onSample("Creature:Think",.1,1) -- same callback Cadence uses AFTER slot timing
check(string.find(LOGSTRING,"Garage habit witnessed entries=3 evidence=3/3 misses=0 reason=observed-entry",1,true)
 and braid.GarageExplainEvent==nil,
 "third witness explanation appears once in server Output after measured Think")
local prep=R.Creature.DayPrep
local savedSignal=prep.signal
prep.signal=function()return {X=120,Y=4,Z=125},30,nil end
root.Position={X=180,Y=4,Z=180}
R.Time.elapsedTotal=R.Time.elapsedTotal+30
braid.LastKnownAt=nil;braid.SearchClueAt=nil
R.Creature:think(.2)
check(braid.DecisionReason=="authored-bell-lure" and braid.HabitState==nil,
 "real authored lure STILL preempts remembered Garage even after three visits")
prep.signal=savedSignal
-- Turn off authored lures ONLY in this isolated test: live garage/station
-- signals MUST keep their higher priority over the prediction.
R.Creature.DayPrep=nil;R.Creature.Floodlight=nil
root.Position={X=180,Y=4,Z=180} -- UNSENSED position is never passed to Habit
R.Time.elapsedTotal=R.Time.elapsedTotal+30
braid.LastKnownAt=nil;braid.SearchClueAt=nil
R.Creature:think(.2)
local dump=R.Creature:aiDump()
check(braid.DecisionReason=="witnessed-three-garage-entries" and braid.TargetX==-55
 and braid.TargetX~=root.Position.X,
 "service picks Garage FIRST when all higher-priority real clues have expired")
check(braid.GarageExplainEvent=="lead" and not string.find(LOGSTRING,"Garage habit chose",1,true),
 "first Garage lead queues explanation instead of printing inside Think")
R.Cadence.onSample("Creature:Think",.1,1)
check(string.find(LOGSTRING,"Garage habit chose entries=3 evidence=3/3 misses=0 reason=witnessed-three-garage-entries",1,true)
 and braid.GarageExplainEvent==nil,
 "deferred Garage lead explains evidence and decision in server Output")
local garageLine=string.match(LOGSTRING,"Garage habit chose[^\n]*") or ""
check(not string.find(garageLine,"9077",1,true)
 and not string.find(garageLine,"-55",1,true)
 and not string.find(garageLine,"240",1,true),
 "server Output summary omits seen/hidden player identity and coordinates")
local leadLogCount=select(2,string.gsub(LOGSTRING,"Garage habit chose",""))
R.Creature:think(.2)
R.Cadence.onSample("Creature:Think",.1,1)
check(select(2,string.gsub(LOGSTRING,"Garage habit chose",""))==leadLogCount,
 "Garage lead explanation is bounded to once per Night")
check(dump.garage.visits==3 and dump.creatures[1].reason=="witnessed-three-garage-entries"
 and dump.creatures[1].goalX==-55 and string.find(dump.priority,"recent genuine clue sweep",1,true)
 and string.find(dump.priority,"lure priority radius",1,true),
 "server-only AIDebugDump explains TRUE clue/lure priority and current route")
root.Position={X=240,Y=4,Z=240}
R.Creature:think(.2)
check(braid.TargetX==-55 and R.Creature.GarageHabit.Visits==3,
 "silent hidden player movement does not change memory or predicted destination")
braid.X,braid.Z=-55,-56;R.Creature:think(.2)
check(braid.TargetX==-90 and braid.HabitState=="inside"
 and braid.DecisionReason=="physical-garage-investigation"
 and R.Creature.GarageHabit.PredictionMisses==0,
 "service does not call prediction wrong at exterior; it walks into authored Garage")
root.Position={X=-55,Y=4,Z=-56};R.Creature:think(.2)
root.Position={X=-90,Y=4,Z=-56};R.Creature:think(.2)
check(R.Creature.GarageHabit.Visits==4 and braid.HabitState=="arrived"
 and R.Creature.GarageHabit.PredictionMisses==0
 and braid.DecisionReason=="genuinely-sensed-prey",
 "a newly witnessed entry confirms a lead; fresh prey wins and prediction is NOT called a miss")
R.Time.phase="Day";R.Creature:think(.2)
check(braid.Dormant and braid.TargetX==nil and braid.DecisionReason=="day-dawn-withdrawal"
 and R.Creature.GarageHabit.Visits==4,
 "Day withdraws as before, but current-run Garage evidence survives the cycle")
-- A physically blocked new lead uses one ray now; ordinary patrol may spend
-- its two rays only on the NEXT Think, never three candidate rays together.
local blockedServiceNav={Garage=garage,Nodes={{-55,-56}},calls=0,
 hit=function()return nil end,
 clear=function(self)self.calls=self.calls+1;return false end}
local blockedServiceHabit=Habit.new(cfg,blockedServiceNav,R.Monster.InstinctSearch)
blockedServiceHabit.Evidence=3
R.Creature.Navigation=blockedServiceNav
R.Creature.GarageHabit=blockedServiceHabit
braid.HabitNight,braid.HabitState=nil,nil
braid.LastKnownAt,braid.SearchClueAt=nil,nil
root.Position={X=240,Y=4,Z=240}
R.Time.phase="Night";R.Creature:think(.2)
check(blockedServiceNav.calls==1 and braid.DecisionReason=="blocked-garage-approach"
 and braid.TargetX==nil,
 "blocked Garage ray defers fallback rather than stacking three rays in one Think")
R.Creature:think(.2)
check(blockedServiceNav.calls<=3 and braid.DecisionReason=="bounded-local-patrol",
 "bounded local hunt resumes on next Think even when Garage remains blocked")
-- The service does not call lead() while a lure wins. It must explicitly
-- invalidate a held flank, then re-ray it after the lure has stopped.
R.Creature.Navigation=flankNav
R.Creature.GarageHabit=Habit.new(cfg,flankNav,R.Monster.InstinctSearch)
R.Creature.GarageHabit.Evidence=3
braid.X,braid.Y,braid.Z=-130,8,-56
braid.HabitNight,braid.HabitState=nil,nil
braid.LastKnownAt,braid.SearchClueAt=nil,nil
root.Position={X=240,Y=4,Z=240}
local raysBeforeLure=flankNav.calls
R.Creature:think(.2)
check(braid.HabitState=="flankWest" and braid.TargetX==-125
 and flankNav.calls==raysBeforeLure+1,
 "actual service selects existing west flank when remembered Garage is behind wall")
prep.signal=function()return {X=120,Y=4,Z=125},30,nil end
R.Creature.DayPrep=prep
R.Creature:think(.2)
check(braid.HabitState=="pending" and braid.DecisionReason=="authored-bell-lure"
 and flankNav.calls==raysBeforeLure+1,
 "service lure preemption invalidates cached flank without stacking a route ray")
R.Creature.DayPrep=nil
flankNav.blocked=true
R.Creature:think(.2)
check(braid.HabitState=="blocked" and braid.DecisionReason=="blocked-garage-approach"
 and braid.TargetX==nil and flankNav.calls==raysBeforeLure+2,
 "after lure, blocked flank is revalidated with ONE ray, never followed through a new wall")
check(Habit.new(cfg,nav,{}).Visits==0,
 "Garage observation history is service-local, never loaded from DataStore")
check(SIM.COUNTERS.runtimeInstanceNew==0,"habit and dump create no gameplay/UI Instances")
return SESSION
