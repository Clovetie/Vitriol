-- Simulate the Studio fast-test Day inside the same real server boot path.
SESSION={passed=0,failed=0}
local function check(ok,msg)
    if ok then SESSION.passed=SESSION.passed+1; print("PASS  "..msg)
    else SESSION.failed=SESSION.failed+1; print("FAIL  "..msg) end
end
local cfg=VitriolRequire("DayNightConfig")
cfg.Pacing.DaySeconds=11 -- local per-scenario mutation; main source remains 210
local R=VitriolRequire("Bootstrap").ensure()
local t=R.Time
local owner=R.Players:addPlayer("QuickBoarder",90001)
local helper=R.Players:addPlayer("QuickHelper",90002)
owner.Character:FindFirstChild("HumanoidRootPart").Position=SIM.latch.Position
helper.Character:FindFirstChild("HumanoidRootPart").Position=SIM.latch.Position
check(t.Model.phaseSeconds("Day",0)==11 and t:dayRemaining()==11,
    "headless boot actually uses current Studio-like eleven-second Day")
local before=t:dayRemaining();local at=SIM.time()
SIM.boardPrompt.Triggered:Fire(owner)
SIM.latch.AssistPrep.Triggered:Fire(helper)
SIM.step(3.15)
check(R.Prep:snapshot().stage=="blackout" and not R.Barricade.boarded,
    "three-real-second vote is not scaled down with test Day")
SIM.step(.55)
check(R.Barricade.boarded and R.Prep:snapshot().stage=="reveal",
    "boarding commits once during short-Day blackout")
SIM.step(.55)
local charged=(before-t:dayRemaining())-(SIM.time()-at)
check(math.abs(charged-(19*11/210))<.02 and t.phase=="Day",
    "nineteen main seconds scales after helper discount, not before vote")
-- Hold the Day near its end. Natural time advances almost zero, so one fuel
-- pickup has only a sliver left and must not spill a charge into Dusk/Night.
t:setTimeScale(.0001)
t.phase="Day";t.phaseLength=11;t.phaseElapsed=10.95
t:publish()
owner.Character:FindFirstChild("HumanoidRootPart").Position=SIM.fuelCan.Position
helper.Character:FindFirstChild("HumanoidRootPart").Position=SIM.fuelCan.Position
local left=t:dayRemaining()
SIM.takeFuel.Triggered:Fire(owner)
SIM.step(3.15)
check(R.Prep:snapshot().stage=="blackout" and not owner:GetAttribute("CarryFuelCan"),
    "near-Dusk fuel waits for blackout rather than committing at trigger")
SIM.step(.55)
check(owner:GetAttribute("CarryFuelCan") and t.phase=="Dusk" and t.phaseElapsed<.01,
    "near-Dusk pickup charges at most the remaining Day, never Night")
SIM.step(.55)
check(R.Prep:snapshot()==nil and not SIM.fuelCan.AssistPrep.Enabled,
    "short-Day reveal clears without leaving a helper prompt active")
check(left>0 and SIM.COUNTERS.runtimeInstanceNew==0,
    "short Day, near-Dusk clamp and vote created no runtime UI/game objects")
return SESSION
