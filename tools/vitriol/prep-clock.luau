-- Server-authoritative Day budget, including Dawn debt and near-Dusk clamp.
SESSION = {passed=0,failed=0}
local function check(ok, message)
    if ok then SESSION.passed = SESSION.passed + 1; print("PASS  "..message)
    else SESSION.failed = SESSION.failed + 1; print("FAIL  "..message) end
end
local R = VitriolRequire("Bootstrap").ensure()
local t = R.Time
local anchor = t.anchor
local day = t.Model.phaseSeconds("Day",t.threat)
check(t.phase == "Day" and t:dayRemaining() == day,"initial Day allowance comes from phase model")
check(t:spendPrepDay(20) == 20 and t.phase == "Day" and t.phaseElapsed == 20,
    "server prep charge advances phase elapsed only once")
check(anchor:GetAttribute("DayBudgetRemaining") == day-20,
    "Day budget is immediately published to replicated anchor")
check(t:spendPrepDay(10000) == day-20 and t.phase == "Dusk" and t.phaseElapsed == 0,
    "near-Dusk cost clamps at boundary without spilling into Night")
check(t:spendPrepDay(10) == 0 and t:dayRemaining() == nil,
    "Dusk cannot consume any Day budget")
t.phase = "Dawn"; t.phaseElapsed = 0; t.phaseLength = t.Model.phaseSeconds("Dawn",t.threat)
t.pendingDayPrep = 0
local dawnBefore = t.elapsedTotal
check(t:spendPrepDay(20) == 20 and t.phase == "Dawn" and t.phaseElapsed == 0,
    "Dawn prep reserves the coming Day without shortening Dawn")
check(t:dayRemaining() == day-20 and anchor:GetAttribute("DayBudgetRemaining") == day-20,
    "the watch can show next Day's reduced allowance at Dawn")
t:_advanceSeconds(t.phaseLength)
check(t.phase == "Day" and t.phaseElapsed == 20 and t.pendingDayPrep == 0,
    "Day begins with reserved Dawn cost exactly once")
check(t.elapsedTotal == dawnBefore + t.Model.phaseSeconds("Dawn",t.threat) + 20,
    "global elapsed time includes Dawn's eventual Day skip")
t.phase = "Dawn"; t.phaseElapsed = 0; t.phaseLength = t.Model.phaseSeconds("Dawn",t.threat)
t.pendingDayPrep = 0
check(t:spendPrepDay(day+100) == day and t:dayRemaining() == 0,
    "Dawn reservations cannot exceed the entire next Day")
t:_advanceSeconds(t.phaseLength)
check(t.phase == "Dusk" and t.pendingDayPrep == 0,
    "fully spent upcoming Day crosses its normal phase callbacks to Dusk")
check(t:spendPrepDay(-1) == 0 and t:spendPrepDay(0/0) == 0,
    "negative and NaN requests fail closed")
t.phase = "Dawn"; t.phaseElapsed = 0; t.phaseLength = t.Model.phaseSeconds("Dawn",t.threat)
t.pendingDayPrep = 0
t:spendPrepDay(7)
t:seekTo(9)
check(t.phase == "Day" and t.pendingDayPrep == 0,
    "designer setclock cannot leak a stale Dawn reservation into the new phase")
local sync=R.Remotes.time
check(not t:setPrepFade(1,"blackout",.35) and t:setPrepFade(1,"vote",3),
    "new fade serial begins at vote, not an unsolicited blackout")
local stamp=sync.lastAll[9] and sync.lastAll[9].startedAt
t:publish()
check(sync.lastAll[9].stage=="vote" and sync.lastAll[9].startedAt==stamp,
    "repeat clock snapshots retain original fade start timestamp")
check(t:setPrepFade(1,"blackout",.35) and sync.lastAll[9].stage=="blackout",
    "blackout stage broadcasts immediately through existing TimeSync")
t:onPlayerAdded({UserId=9999})
check(sync.lastClient[9].serial==1 and sync.lastClient[9].stage=="blackout",
    "late join catches up to the authoritative in-progress stage")
check(not t:setPrepFade(1,"vote",3) and not t:setPrepFade(0,"vote",3)
    and not t:setPrepFade(1,"reveal",-1), "reordered and malformed stages fail closed")
check(t:setPrepFade(1,"reveal",.4) and t:setPrepFade(1,"clear",0)
    and t:setPrepFade(2,"vote",3),"one serial clears before next vote")
check(SIM.COUNTERS.runtimeInstanceNew == 0,"time spending and fade state create no Vitriol Instances")
return SESSION
