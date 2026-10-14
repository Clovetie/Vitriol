-- Diagnostic, NOT a Roblox engine benchmark: count what the existing
-- blackout->reveal DayPrep slot publishes to the authored clock and clients.
-- A changed-attribute list does not measure SetAttribute's Play cost.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1; print("PASS  "..msg)
 else SESSION.failed=SESSION.failed+1; print("FAIL  "..msg) end
end
local r=VitriolRequire("Bootstrap").ensure()
local t=r.Time
local p=r.Players:addPlayer("CoverCommit",86601)
local closet=SIM.houseFurniture.House_01_Closet
p.Character:FindFirstChild("HumanoidRootPart").Position=closet.part.Position
closet.move.Triggered:Fire(p)
SIM.step(3.3)
check(r.Prep:snapshot() and r.Prep:snapshot().stage=="blackout"
 and not r.HouseCover.ByAction.CoverHouse01Closet.Placed,
 "paid original closet waits for full shared vote then visible blackout")
local events={}
local originalPublish=t.publish
local originalWrite=t.writeAttribute
t.writeAttribute=function(self,anchor,name,value)
 if anchor==t.anchor and anchor:GetAttribute(name)~=value and #events>0 then
  local e=events[#events]
  e.changed[#e.changed+1]=name
 end
 return originalWrite(self,anchor,name,value)
end
t.publish=function(self,measured)
 if measured then return originalPublish(self,measured) end -- scheduled slot is separate
 local e={stage=self.prepFade and self.prepFade.stage or "none",
  dayRemaining=self:dayRemaining(),changed={}}
 events[#events+1]=e
 return originalPublish(self,measured)
end
SIM.step(.55)
t.publish=originalPublish
t.writeAttribute=originalWrite
check(r.Prep:snapshot() and r.Prep:snapshot().stage=="reveal"
 and r.HouseCover.ByAction.CoverHouse01Closet.Placed,
 "original closet commits once during measured blackout->reveal")
check(#events==2 and events[1].stage=="blackout" and events[2].stage=="reveal",
 "commit currently causes TWO immediate snapshots: clock charge, then reveal fade")
local first={};for _,name in ipairs(events[1] and events[1].changed or {}) do first[name]=true end
check(first.ClockMinutes and first.PhaseProgress and first.DayBudgetRemaining
 and events[2] and #events[2].changed==0,
 "clock charge changed authored anchor values, second same-tick reveal publishes NO changed clock attributes")
check(events[1] and events[2] and events[1].dayRemaining==events[2].dayRemaining
 and r.Remotes.time.lastAll and r.Remotes.time.lastAll[9]
 and r.Remotes.time.lastAll[9].stage=="reveal",
 "both snapshots agree on charged Day time; clients receive the authoritative reveal")
check(t.Config.Budgets.SlowShares.DayPrep==.05 and t.Config.Budgets.SlowShares.TimePublish==.05,
 "DayPrep and scheduled Time:Publish budgets remain unchanged")
check(SIM.COUNTERS.runtimeInstanceNew==0,"instrumentation created no runtime gameplay/UI Instances")
VitriolRequire("Bootstrap").stop()
return SESSION
