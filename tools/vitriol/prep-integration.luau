-- Full server prompt path in the headless authored-tree fixture. No new UI/Parts.
SESSION={passed=0,failed=0}
local function check(ok,msg)
    if ok then SESSION.passed=SESSION.passed+1; print("PASS  "..msg)
    else SESSION.failed=SESSION.failed+1; print("FAIL  "..msg) end
end
local R=VitriolRequire("Bootstrap").ensure()
local p=R.Players:addPlayer("Initiator",83001)
local h1=R.Players:addPlayer("HelperOne",83002)
local h2=R.Players:addPlayer("HelperTwo",83003)
local function move(player,part)
    player.Character:FindFirstChild("HumanoidRootPart").Position=part.Position
end
local function settle(seconds)
    SIM.step(seconds)
end
local function finish()
    settle(3.15) -- vote: server clock, not Day clock
    check(R.Prep:snapshot() and R.Prep:snapshot().stage=="blackout",
        "live Cadence completes vote and starts shared blackout without early effect")
    settle(.55)
    check(R.Prep:snapshot() and R.Prep:snapshot().stage=="reveal",
        "server committed once after visible blackout began")
    settle(.55)
    check(R.Prep:snapshot()==nil and R.Remotes.time.lastAll[9].stage=="clear",
        "all-client fade state clears after reveal")
end
local t=R.Time
local day=t.Model.phaseSeconds("Day",t.threat)
check(R.Prep.started and R.Floodlight.running and SIM.repairPrompt.Enabled
    and not SIM.stationHelper.Enabled and not SIM.fuelCan.AssistPrep.Enabled,
    "five helper prompts start inert, repair enabled only with wired server handler")
move(p,SIM.fuelCan);move(h1,SIM.fuelCan);move(h2,SIM.fuelCan)
local before=t:dayRemaining();local at=SIM.time()
SIM.takeFuel.Triggered:Fire(p)
check(R.Prep:snapshot().action=="TakeFuel" and SIM.fuelCan.AssistPrep.Enabled
    and not p:GetAttribute("CarryFuelCan") and R.Remotes.time.lastAll[9].stage=="vote",
    "fuel prompt opens a vote rather than handing out a free can")
SIM.fuelCan.AssistPrep.Triggered:Fire(h1)
SIM.takeFuel.Triggered:Fire(h2)
check(R.Prep:snapshot().action=="TakeFuel" and not h2:GetAttribute("CarryFuelCan"),
    "simultaneous trigger cannot mint a second can")
finish()
local paid=(before-t:dayRemaining())-(SIM.time()-at)
check(math.abs(paid-3)<.02 and p:GetAttribute("CarryFuelCan") and not SIM.fuelCan.AssistPrep.Enabled,
    "one helper saves one scaled second on fuel PICKUP, charged to shared Day")
move(p,SIM.generator);move(h1,SIM.generator);move(h2,SIM.generator)
before=t:dayRemaining();at=SIM.time()
SIM.powerLamp.Triggered:Fire(p)
SIM.generator.AssistPrep.Triggered:Fire(h1)
SIM.generator.AssistPrep.Triggered:Fire(h2)
check(SIM.generator.AssistPrep.Enabled and not R.DayPrep.powered,
    "generator waits through vote and accepts two distinct volunteers")
finish()
paid=(before-t:dayRemaining())-(SIM.time()-at)
check(math.abs(paid-10)<.02 and R.DayPrep.powered and not p:GetAttribute("CarryFuelCan"),
    "generator consumes the only carried can and pays twelve minus two seconds")
move(p,SIM.bellLever);move(h1,SIM.bellLever)
local bellGround=SIM.bellModel:GetPivot().Position.Y
local ropeGround=SIM.bellRope.Position.Y
local hoistTarget=SIM.bellHoistPos.Position.Y
before=t:dayRemaining();at=SIM.time()
SIM.primeBell.Triggered:Fire(p)
SIM.bellLever.AssistPrep.Triggered:Fire(h1)
check(not R.DayPrep.bellArmed and SIM.bellLever.AssistPrep.Enabled
    and SIM.bellModel:GetPivot().Position.Y==bellGround,
    "user's bell stays on the ground through its helper vote")
settle(3.15)
check(R.Prep:snapshot().stage=="blackout" and SIM.bellModel:GetPivot().Position.Y==bellGround,
    "hoist does not start before blackout")
settle(.55)
check(R.Prep:snapshot().stage=="reveal" and SIM.bellModel:GetPivot().Position.Y==bellGround,
    "bell prep charges once at blackout but model waits through reveal")
settle(.55)
check(R.Prep:snapshot()==nil and R.DayPrep.hoistActive,
    "bell and rope begin hoisting only after server's fade-clear stage")
paid=(before-t:dayRemaining())-(SIM.time()-at)
check(math.abs(paid-7)<.02 and R.DayPrep.bellArmed,
    "accepted bell remains one-use, seven seconds with helper")
settle(2.6)
local lifted=hoistTarget-bellGround
check(R.DayPrep.bellHoisted and not R.DayPrep.hoistActive
    and math.abs(SIM.bellModel:GetPivot().Position.Y-hoistTarget)<.02
    and math.abs(SIM.bellRope.Position.Y-(ropeGround+lifted))<.02
    and SIM.bellHoistPos.Position.Y==hoistTarget,
    "USER bell and rope rise together to stationary HoistPos without moving marker")
check(SIM.bellSound.Parent==SIM.bellPart and SIM.bellLight.Parent==SIM.bellPart,
    "original three-strike sound and pulse now follow user's bell MeshPart")
move(p,SIM.latch);move(h1,SIM.latch);move(h2,SIM.latch)
before=t:dayRemaining();at=SIM.time()
SIM.boardPrompt.Triggered:Fire(p)
SIM.latch.AssistPrep.Triggered:Fire(h1)
SIM.latch.AssistPrep.Triggered:Fire(h2)
check(not R.Barricade.boarded and SIM.latch.AssistPrep.Enabled,
    "garage planks cannot materialize before the boarding vote")
finish()
paid=(before-t:dayRemaining())-(SIM.time()-at)
check(math.abs(paid-18)<.02 and R.Barricade.boarded and R.Barricade.Gate.CanCollide,
    "garage boards once and pays main-pacing twenty minus two seconds")
move(p,SIM.stationSwitch);move(h1,SIM.stationSwitch)
before=t:dayRemaining();at=SIM.time()
SIM.repairPrompt.Triggered:Fire(p)
SIM.stationHelper.Triggered:Fire(h1)
check(not R.Floodlight.repaired and SIM.stationHelper.Enabled,
    "station uses the same helper vote, not an instant unwired switch")
finish()
paid=(before-t:dayRemaining())-(SIM.time()-at)
check(math.abs(paid-15)<.02 and R.Floodlight.repaired
    and SIM.stationSwitch:GetAttribute("Repaired") and not SIM.stationBeam.Enabled,
    "floodlight repair pays sixteen minus one and waits for Night to illuminate")
check(not SIM.repairPrompt.Enabled and not SIM.stationHelper.Enabled,
    "run-lasting station repair and helper cannot be repeated until Braid breaks it")
t.phase="Night"
R.DayPrep:onPhaseChanged("Night");R.Floodlight:onPhaseChanged("Night")
check(SIM.stationBeam.Enabled and SIM.stationFixture:GetAttribute("Powered")
    and R.Floodlight:signal()==SIM.stationFixture.Position,
    "at Night the authored station beam lights a real route and emits a lure")
local beforeNoise=R.Noise:sample("EM",SIM.stationFixture.Position.X,
    SIM.stationFixture.Position.Y,SIM.stationFixture.Position.Z,8,t.elapsedTotal or 0)
R.Floodlight:tick()
local afterNoise=R.Noise:sample("EM",SIM.stationFixture.Position.X,
    SIM.stationFixture.Position.Y,SIM.stationFixture.Position.Z,8,t.elapsedTotal or 0)
check(afterNoise>beforeNoise,"lit fixture emits bounded EM detectable to Braid")
-- The already-approved bell and generator outrank the stationary station lure.
check(R.DayPrep:signal()==SIM.generator.Position,
    "accepted powered-garage lure retains precedence over floodlight")
R.DayPrep.powered=false;R.DayPrep:_publish()
local lure,priority=R.Floodlight:signal()
check(lure==SIM.stationFixture.Position and priority==32,
    "station is a weaker fallback: nearby prey wins within thirty-two studs")
R.Creature:reconcile()
local braid=R.Creature.creatures[1]
for _,survivor in ipairs({p,h1,h2}) do
    survivor.Character:FindFirstChild("HumanoidRootPart").Position={X=braid.X+200,Y=braid.Y,Z=braid.Z+200}
end
R.Creature:think(.2)
check(braid.TargetX==SIM.stationFixture.Position.X and braid.TargetZ==SIM.stationFixture.Position.Z,
    "when prey is distant, lit station actually diverts the Night Braid")
p.Character:FindFirstChild("HumanoidRootPart").Position={X=braid.X+3,Y=braid.Y,Z=braid.Z+3}
R.Creature:think(.2)
check(braid.TargetX~=SIM.stationFixture.Position.X or braid.TargetZ~=SIM.stationFixture.Position.Z,
    "nearby living prey overrides station lure and preserves the approved chase")
-- Deliberate Night sabotage extinguishes the light; damage, not Dawn, resets
-- the repair contract. This also makes a fresh Day repair prompt available.
check(R.Floodlight:damage() and R.Floodlight.broken and not R.Floodlight.repaired
    and not SIM.stationBeam.Enabled and SIM.stationFixture:GetAttribute("Broken"),
    "Braid's dedicated attack breaks the previously repaired station")
move(p,SIM.latch)
local noCharge=t.elapsedTotal
SIM.boardPrompt.Triggered:Fire(p)
check(not R.Barricade.boarded and t.elapsedTotal==noCharge and R.Prep:snapshot()==nil,
    "Night garage emergency exit stays immediate and costs no Day budget")
R.DayPrep:onPhaseChanged("Dawn")
check(math.abs(SIM.bellModel:GetPivot().Position.Y-bellGround)<.02
    and math.abs(SIM.bellRope.Position.Y-ropeGround)<.02 and not R.DayPrep.bellHoisted,
    "Dawn lowers the user's bell and rope together back to their grounded authored pose")
R.Floodlight:onPhaseChanged("Dawn")
check(not R.Floodlight.repaired and R.Floodlight.broken and not SIM.stationBeam.Enabled,
    "Braid damage persists through Dawn; Dawn itself never repairs/breaks it")
t:seekToPhase("Day");R.Floodlight:onPhaseChanged("Day")
move(p,SIM.stationSwitch)
local original=t:dayRemaining();local started=SIM.time()
SIM.repairPrompt.Triggered:Fire(p)
check(R.Prep:snapshot() and SIM.stationHelper.Enabled,
    "a second day's station prompt starts a fresh serialised transaction")
p.Character:FindFirstChild("HumanoidRootPart").Position={X=300,Y=0,Z=300}
settle(3.2)
check(R.Prep:snapshot()==nil and not R.Floodlight.repaired
    and math.abs((original-t:dayRemaining())-(SIM.time()-started))<.02
    and not SIM.stationHelper.Enabled and R.Remotes.time.lastAll[9].stage=="cancel",
    "walking away before commit cancels visible helper vote and charges no shared Day time")
check(SIM.COUNTERS.runtimeInstanceNew==0,"full prep path creates no runtime Vitriol objects")
return SESSION
