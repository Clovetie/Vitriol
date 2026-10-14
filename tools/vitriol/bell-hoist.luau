-- Post-fade hoist, no early ringing, and mid-lift Dawn cancellation.
SESSION={passed=0,failed=0}
local function check(ok,msg)
    if ok then SESSION.passed=SESSION.passed+1; print("PASS  "..msg)
    else SESSION.failed=SESSION.failed+1; print("FAIL  "..msg) end
end
local R=VitriolRequire("Bootstrap").ensure()
local owner=R.Players:addPlayer("BellHoister",92001)
owner.Character:FindFirstChild("HumanoidRootPart").Position=SIM.bellLever.Position
local t=R.Time
local prep=R.DayPrep
local ground=SIM.bellModel:GetPivot().Position.Y
local ropeGround=SIM.bellRope.Position.Y
SIM.primeBell.Triggered:Fire(owner)
SIM.step(3.15)
check(R.Prep:snapshot().stage=="blackout" and SIM.bellModel:GetPivot().Position.Y==ground,
    "bell stays grounded through helper vote")
SIM.step(.55)
check(R.Prep:snapshot().stage=="reveal" and prep.hoistPending
    and SIM.bellModel:GetPivot().Position.Y==ground,
    "prime committed at blackout but did not start hoist through fade reveal")
-- Simulate a very late Day prime; Night arrives before the hoist finishes.
t.phase="Night";t.phaseLength=t.Model.phaseSeconds("Night",t.threat);t.phaseElapsed=0
prep:onPhaseChanged("Night")
SIM.step(.55)
check(R.Prep:snapshot()==nil and prep.hoistActive and not prep.bellHoisted,
    "reveal clear starts lifting even across Day/Night phase change")
prep.bellAt=t.elapsedTotal+.1 -- stress: night bell would ring before hoist ends
SIM.step(.5)
check(not prep.bellRang and (SIM.bellSound.playCount or 0)==0
    and SIM.bellModel:GetPivot().Position.Y>ground
    and SIM.bellRope.Position.Y>ropeGround,
    "sound waits while user's bell and rope are still rising")
prep:onPhaseChanged("Dawn")
check(not prep.hoistActive and not prep.bellHoisted and prep.hoistSlot==nil
    and math.abs(SIM.bellModel:GetPivot().Position.Y-ground)<.02
    and math.abs(SIM.bellRope.Position.Y-ropeGround)<.02,
    "Dawn cancels in-flight hoist and lowers both original objects without a clone")
SIM.step(.5)
check(not prep.bellRang and (SIM.bellSound.playCount or 0)==0,
    "canceled Night cannot ring a grounded bell")
t.phase="Day";t.phaseLength=t.Model.phaseSeconds("Day",t.threat);t.phaseElapsed=0
prep:onPhaseChanged("Day")
SIM.primeBell.Triggered:Fire(owner)
SIM.step(3.15);SIM.step(.55);SIM.step(.55)
check(prep.hoistActive and SIM.bellSound.playCount==nil,
    "next Day restocks one ground-bell preparation without early ring")
t.phase="Night";t.phaseLength=t.Model.phaseSeconds("Night",t.threat);t.phaseElapsed=0
prep:onPhaseChanged("Night")
prep.bellAt=t.elapsedTotal+.1
SIM.step(2.8)
check(prep.bellHoisted and not prep.hoistActive and prep.bellRang
    and SIM.bellSound.playCount==1 and math.abs(SIM.bellModel:GetPivot().Position.Y-SIM.bellHoistPos.Position.Y)<.02,
    "after hoist completes, original user clip rings once from raised MeshPart")
check(SIM.COUNTERS.runtimeInstanceNew==0,"all hoist stages created zero runtime UI/game objects")
return SESSION
