-- Time:Publish measured section attribution; virtual timing tests LOGIC only.
-- Roblox SetAttribute/RemoteEvent engine costs require a fresh human Play sample.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1;print("PASS  "..msg)
 else SESSION.failed=SESSION.failed+1;print("FAIL  "..msg) end
end
local r=VitriolRequire("Bootstrap").ensure()
local t=r.Time
local anchor=t.anchor
local sync=r.Remotes.time
local p=t.publishCost
check(p and p.samples==0 and p.peakMs==0,"profiling starts empty before first scheduled slot")
local clockBefore=anchor:GetAttribute("ClockMinutes")
SIM.step(1.02)
check(p.samples>=1 and anchor:GetAttribute("ClockMinutes")~=clockBefore,
 "scheduled Time:Publish still updates the existing authoritative clock Part")
check(sync.lastAll and sync.lastAll[2]==t.phase and type(sync.lastAll[8])=="number"
 and math.abs(sync.lastAll[8]-t:dayRemaining())<.3 and sync.lastAll[9]==nil,
 "scheduled broadcast retains phase, Day allowance and optional ninth fade field")
local count=p.samples
t:publish()
check(p.samples==count,"immediate publication does not contaminate scheduled-slot timing")
local original=t.syncRemotes
t.syncRemotes=function(self,progress)
 SIM.burn(.24)
 return original(self,progress)
end
SIM.step(1.02)
check(p.samples>count and p.lastRemoteMs>=.239 and p.lastAttributesMs<.01,
 "deliberate remote-side overrun is attributed to the remote section")
check(p.overBudget>0 and p.peakMs>=.239 and p.peakSampleRemoteMs>=.239
 and p.peakSampleAttributesMs<.01 and r.Cadence:stats("Time:Publish").peakMs>=.239,
 "peak sample retains its own remote/attribute split and Cadence warning")
check(string.find(LOGSTRING,"warn|[vitriol] warn: cadence Time:Publish took",1,true)~=nil
 and string.find(LOGSTRING," ms budget (attributes ",1,true)~=nil
 and string.find(LOGSTRING," ms, remote ",1,true)~=nil,
 "rare real warning retains measured total AND carries same-sample breakdown")
t.syncRemotes=original
local originalWrite=t.writeAttribute
t.writeAttribute=function(self,instance,name,value)
 if name=="ClockMinutes" then SIM.burn(.09) end
 return originalWrite(self,instance,name,value)
end
SIM.step(1.02)
check(p.lastAttributesMs>=.089 and p.lastRemoteMs<.01,
 "deliberate anchor-side overrun is attributed to attribute publication")
t.writeAttribute=originalWrite
check(t.Config.Budgets.SlowShares.TimePublish==.05 and r.Cadence:stats("Time:Publish").budgetMs==.05,
 "no budget increase or warning suppression was used")
check(SIM.COUNTERS.runtimeInstanceNew==0,
 "sampling creates no gameplay or UI Instances")
return SESSION
