-- Dormant server transaction engine: no live prompt or remote wiring in this fixture.
SESSION = {passed=0,failed=0}
local function check(ok, message)
    if ok then SESSION.passed=SESSION.passed+1; print("PASS  "..message)
    else SESSION.failed=SESSION.failed+1; print("FAIL  "..message) end
end
local R=VitriolRequire("Bootstrap").ensure()
local Engine=VitriolRequire("PrepCoordinator")
local Rules=VitriolRequire("PrepRules")
local time,players=R.Time,R.Players
local owner=players:addPlayer("Owner",72101)
local help1=players:addPlayer("Help1",72102)
local help2=players:addPlayer("Help2",72103)
local help3=players:addPlayer("Help3",72104)
local outsider=players:addPlayer("Away",72105)
local function move(player,x)
    player.Character:FindFirstChild("HumanoidRootPart").Position={X=x,Y=0,Z=0}
end
for _,p in ipairs({owner,help1,help2,help3,outsider}) do move(p,0) end
move(outsider,30)
local gate={ready=true, commits=0, succeed=true}
local messages={}
local actions={TakeFuel={Part=SIM.fuelCan,
    Ready=function() return gate.ready end,
    Commit=function() gate.commits=gate.commits+1; return gate.succeed end}}
local coordinator=Engine.new({Time=time,Health=R.Health,Players=players,Rules=Rules,Actions=actions,
    Fade=function(serial,stage,seconds) messages[#messages+1]={serial,stage,seconds} end})
local day=time.Model.phaseSeconds("Day",time.threat)
local function reset()
    time:seekToPhase("Day")
    gate.ready=true; gate.succeed=true; gate.commits=0
    move(owner,0); move(help1,0); move(help2,0); move(help3,0)
end
check(not coordinator:begin("Nonexistent",owner) and not coordinator:begin("TakeFuel",outsider),
    "unregistered action and distant initiator cannot start")
check(coordinator:begin("TakeFuel",owner) and not coordinator:begin("TakeFuel",owner),
    "one serialized transaction blocks contention")
check(not coordinator:volunteer("TakeFuel",owner) and not coordinator:volunteer("TakeFuel",outsider),
    "initiator and distant player cannot volunteer")
check(coordinator:volunteer("TakeFuel",help1) and coordinator:volunteer("TakeFuel",help2)
    and not coordinator:volunteer("TakeFuel",help3) and not coordinator:volunteer("TakeFuel",help1),
    "two distinct nearby helpers maximum; duplicate blocked")
coordinator:tick(2.99)
check(time:dayRemaining()==day and gate.commits==0 and coordinator:snapshot().stage=="vote",
    "full three REAL seconds must elapse before a shared blackout or commit")
coordinator:tick(0.01)
check(time:dayRemaining()==day and gate.commits==0 and coordinator:snapshot().stage=="blackout",
    "fade begins before the server changes the clock or world")
coordinator:tick(0.35)
check(time:dayRemaining()==day-2 and gate.commits==1 and coordinator:snapshot().stage=="reveal",
    "two helpers save two seconds; cost and effect happen once at blackout")
coordinator:tick(0.4)
check(coordinator:snapshot()==nil and messages[1][2]=="vote" and messages[2][2]=="blackout"
    and messages[3][2]=="reveal" and messages[4][2]=="clear" and messages[1][1]==messages[4][1],
    "fade stage order and serial remain stable through reveal")
reset()
check(coordinator:begin("TakeFuel",owner) and coordinator:volunteer("TakeFuel",help1),
    "a second transaction can begin after clear")
move(help1,40)
coordinator:tick(3); coordinator:tick(0.35)
check(time:dayRemaining()==day-4 and gate.commits==1,
    "moving out of helper radius at commit removes discount")
coordinator:tick(0.4)
reset()
check(coordinator:begin("TakeFuel",owner),"near-Dusk transaction starts while time remains")
time.phaseElapsed=day-1
coordinator:tick(3); coordinator:tick(0.35)
check(time.phase=="Dusk" and gate.commits==1 and coordinator:snapshot().stage=="reveal",
    "charge clamps to remaining one second, crosses Dusk without spilling")
coordinator:tick(0.4)
check(coordinator:snapshot()==nil and messages[#messages][2]=="clear"
    and not coordinator:begin("TakeFuel",owner),"reveal clears even after paid transition to Dusk")
reset()
coordinator:begin("TakeFuel",owner)
time:seekToPhase("Dusk")
coordinator:tick(0.1)
check(coordinator:snapshot()==nil and gate.commits==0 and messages[#messages][2]=="cancel",
    "phase leaves Day during vote: cancel without free effect or cost")
reset()
coordinator:begin("TakeFuel",owner)
gate.ready=false
coordinator:tick(3)
check(coordinator:snapshot()==nil and gate.commits==0,
    "action that is no longer available is cancelled at vote close")
reset()
coordinator:begin("TakeFuel",owner)
gate.succeed=false
coordinator:tick(3); coordinator:tick(0.35)
check(coordinator:snapshot()==nil and time:dayRemaining()==day and gate.commits==1,
    "failed synchronous effect never pays Day time")
reset()
coordinator:begin("TakeFuel",owner)
players:removePlayer(owner)
coordinator:tick(3); coordinator:tick(0.35)
check(coordinator:snapshot()==nil and gate.commits==0,
    "disconnected initiator cannot complete pending transaction")
reset()
coordinator:begin("TakeFuel",owner) -- owner is disconnected; rejected
check(coordinator:snapshot()==nil,"a stale disconnected player cannot restart a vote")
check(coordinator:begin("TakeFuel",help2) and coordinator:volunteer("TakeFuel",help1)
    and coordinator:volunteer("TakeFuel",help3),"two helpers can volunteer for a new initiator")
R.Health.states[help1.UserId].dead=true
coordinator:tick(3); coordinator:tick(0.35)
check(time:dayRemaining()==day-3 and gate.commits==1,
    "helper dying before commit loses only their one-second discount")
coordinator:tick(0.4)
R.Health.states[help1.UserId].dead=false
reset()
local noTransport=Engine.new({Time=time,Health=R.Health,Players=players,Rules=Rules,Actions=actions})
check(not noTransport:begin("TakeFuel",help2) and noTransport:snapshot()==nil,
    "missing fade transport fails closed rather than granting a silent preparation")
local broken=Engine.new({Time=time,Health=R.Health,Players=players,Rules=Rules,Actions=actions,
    Fade=function() error("transport down") end})
check(not broken:begin("TakeFuel",help2) and broken:snapshot()==nil,
    "failed fade broadcast cannot start a clock-changing action")
local phaseEngine=Engine.new({Time=time,Health=R.Health,Players=players,Rules=Rules,Actions=actions,
    Fade=function(serial,stage,seconds) messages[#messages+1]={serial,stage,seconds} end})
reset()
check(phaseEngine:begin("TakeFuel",help2),"transaction can begin from another living player")
phaseEngine:tick(3)
time:seekToPhase("Dusk")
phaseEngine:tick(0.35)
check(phaseEngine:snapshot()==nil and gate.commits==0 and messages[#messages][2]=="cancel",
    "Dusk during fade-in unblacks clients without any action or charge")
time:seekToPhase("Dawn")
local dawnLength=time.Model.phaseSeconds("Dawn",time.threat)
check(phaseEngine:begin("TakeFuel",help2),"Dawn offers a Day-budget transaction")
phaseEngine:tick(3); phaseEngine:tick(0.35)
check(time.phase=="Dawn" and time.phaseElapsed==0 and time:dayRemaining()==day-4,
    "Dawn charge reserves four seconds against next Day and preserves Dawn")
phaseEngine:tick(0.4)
time:_advanceSeconds(dawnLength)
check(time.phase=="Day" and time.phaseElapsed==4,
    "Dawn transaction's reservation is debited exactly once at Day start")
reset()
local wall=100
R.Workspace.GetServerTimeNow=function() return wall end
local wallEngine=Engine.new({Time=time,Health=R.Health,Players=players,Rules=Rules,Actions=actions,
    Now=function() return wall end,
    Fade=function(serial,stage,seconds) return time:setPrepFade(serial,stage,seconds) end})
check(wallEngine:begin("TakeFuel",help2) and R.Remotes.time.lastAll[9].startedAt==wall,
    "real transport stamps a vote in the existing authoritative time snapshot")
wall=102.9;wallEngine:tick(.25)
check(wallEngine:snapshot().stage=="vote" and not wallEngine:volunteer("TakeFuel",outsider),
    "delayed Cadence callback has not shortened the three-real-second window")
wall=103.01
check(not wallEngine:volunteer("TakeFuel",help1),
    "volunteer after absolute three-second deadline is rejected before tick")
wallEngine:tick(.25)
check(wallEngine:snapshot().stage=="blackout" and gate.commits==0
    and R.Remotes.time.lastAll[9].stage=="blackout", "absolute deadline advances to broadcast blackout")
wall=103.37;wallEngine:tick(.25)
check(gate.commits==1 and time:dayRemaining()==day-4 and R.Remotes.time.lastAll[9].stage=="reveal",
    "wall-clock blackout commits once and reveals through actual TimeSync")
wall=103.8;wallEngine:tick(.25)
check(wallEngine:snapshot()==nil and R.Remotes.time.lastAll[9].stage=="clear",
    "authoritative wall-clock fade state clears for future/late clients")
local fastPaid=0
local fast={phase="Day",threat=0,Model={phaseSeconds=function() return 11 end},
    dayRemaining=function() return 11-fastPaid end,
    spendPrepDay=function(_,seconds) fastPaid=fastPaid+seconds; return seconds end}
local fastPlayer=help2
local fastCoordinator=Engine.new({Time=fast,Health=R.Health,Players=players,Rules=Rules,Actions=actions,
    Fade=function() end})
check(fastCoordinator:begin("TakeFuel",fastPlayer) and fastCoordinator:volunteer("TakeFuel",help3),
    "test-Day action and eligible helper use the same real-time vote")
fastCoordinator:tick(3); fastCoordinator:tick(0.35)
check(math.abs(fastPaid-3*11/210)<1e-8,"main cost and helper discount scale to an 11-second Studio Day")
fastCoordinator:stop()
reset()
local burst=Engine.new({Time=time,Health=R.Health,Players=players,Rules=Rules,Actions=actions,
    Fade=function(serial,stage,seconds) messages[#messages+1]={serial,stage,seconds} end})
check(burst:begin("TakeFuel",help2),"spike test begins an otherwise valid transaction")
burst:tick(30)
check(burst:snapshot().stage=="blackout" and gate.commits==0 and time:dayRemaining()==day,
    "one long frame cannot skip the client-visible blackout before charging")
burst:tick(30)
check(burst:snapshot().stage=="reveal" and gate.commits==1 and time:dayRemaining()==day-4,
    "next cadence callback performs precisely one server-owned charge")
burst:tick(30)
check(burst:snapshot()==nil and messages[#messages][2]=="clear",
    "long frame still clears fade only after reveal stage")
check(not fastCoordinator:begin("TakeFuel",fastPlayer) and SIM.COUNTERS.runtimeInstanceNew==0,
    "stopped coordinator fails closed without runtime Instances")
return SESSION
