-- Exceptional warning context for the two *measured* one-off cadence warnings.
-- Virtual time proves attribution labels, NEVER real Play cost or its cause.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1;print("PASS  "..msg)
 else SESSION.failed=SESSION.failed+1;print("FAIL  "..msg) end
end
local r=VitriolRequire("Bootstrap").ensure()
local session=r.Session
local originalBegin=session.beginRound
session.intermissionLeft=.5
session.beginRound=function(self)
 SIM.burn(.21)
 return originalBegin(self)
end
SIM.step(1.02)
check(session.state=="Running" and session.lastSlowPath=="begin-round",
 "measured Session slot identifies one-off begin-round transition")
check(string.find(LOGSTRING,"warn|[vitriol] warn: cadence Session:Slow took",1,true)
 and string.find(LOGSTRING," ms budget (path begin-round, state Running, phase ",1,true),
 "rare Session warning adds same-slot path and state AFTER original measured cost")
session.beginRound=originalBegin
local originalTick=session.tick
session.tick=function(self,dt)
 originalTick(self,dt)
 SIM.burn(.21)
end
SIM.step(1.02)
check(session.lastSlowPath=="running"
 and string.find(LOGSTRING," ms budget (path running, state Running, phase ",1,true),
 "regular running tick is distinguished from expensive round boundary")
session.tick=originalTick
local owner=r.Creature
local originalThink=owner.think
owner.think=function(self,dt)
 originalThink(self,dt)
 SIM.burn(5)
end
SIM.step(.4)
check(string.find(LOGSTRING,"warn|[vitriol] warn: cadence Creature:Think took",1,true)
 and string.find(LOGSTRING," ms budget (phase ",1,true)
 and string.find(LOGSTRING,", decision no-creature, attack none)",1,true),
 "rare Think warning includes only server phase/decision/attack, never a target coordinate")
owner.think=originalThink
check(r.Cadence:stats("Session:Slow").peakMs>=.209
 and r.Cadence:stats("Creature:Think").peakMs>=4.999,
 "Cadence measured peaks remain intact rather than being hidden or reset")
check(r.Config.Budgets.SlowShares.Session==.05
 and r.Cadence:stats("Session:Slow").budgetMs==.05
 and r.Cadence:stats("Creature:Think").budgetMs==1,
 "Session and Think watchdog shares stay exactly at the original limits")
check(SIM.COUNTERS.runtimeInstanceNew==0,
 "exceptional budget diagnostics create no gameplay or UI Instances")
-- Same-slot DayPrep warning: a real furniture commit is blackout->reveal,
-- not an ordinary idle pulse. Burned time is synthetic, NOT a Play profile.
local prep=r.Prep
local originalPrepTick=prep.tick
prep.current={Action="CoverHouse01Closet",Stage="blackout"}
prep.tick=function(self,_dt)
 SIM.burn(.42)
 self.current.Stage="reveal"
end
SIM.step(.26)
check(r.DayPrep.lastPulseAction=="CoverHouse01Closet"
 and r.DayPrep.lastPulseFrom=="blackout" and r.DayPrep.lastPulseTo=="reveal"
 and string.find(LOGSTRING,"cadence DayPrep:Pulse took",1,true)
 and string.find(LOGSTRING,"prep CoverHouse01Closet blackout->reveal",1,true),
 "exceptional DayPrep warning names the same-slot furniture action and paid commit transition")
prep.tick=originalPrepTick;prep.current=nil
local previousPhase=r.Time.phase
local oldNoise=r.DayPrep._noise
local previousPower,previousHum=r.DayPrep.powered,r.DayPrep.nextGeneratorHum
r.Time.phase="Night";r.DayPrep.powered=true
r.DayPrep.nextGeneratorHum=r.Time.elapsedTotal or 0
r.DayPrep._noise=function() SIM.burn(.225) end
SIM.step(.26)
check(r.DayPrep.lastPulseAction=="none" and r.DayPrep.lastPulseFrom=="none"
 and r.DayPrep.lastPulseTo=="none" and r.DayPrep.lastPulseHum
 and string.find(LOGSTRING,"prep none none->none, bell false, hum true)",1,true),
 "exceptional Night hum pulse is distinguishable from a shared-Day furniture commit")
r.DayPrep._noise=oldNoise;r.DayPrep.powered=previousPower
r.DayPrep.nextGeneratorHum=previousHum;r.Time.phase=previousPhase
check(r.Cadence:stats("DayPrep:Pulse").budgetMs==.05
 and r.Cadence:stats("DayPrep:Pulse").peakMs>=.418
 and SIM.COUNTERS.runtimeInstanceNew==0,
 "DayPrep diagnostic preserves real budget/peak and runtime-object policy")
return SESSION
