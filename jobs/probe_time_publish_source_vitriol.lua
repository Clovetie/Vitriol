-- READ ONLY Edit probe: fresh-compile current Studio Source. Only Lua tables
-- stand in for anchor/remote, so no live Workspace attributes or Instances change.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local script=game:GetService("ServerStorage").Vitriol.Services.TimeService
assert(script:IsA("ModuleScript"),"TimeService must remain a ModuleScript")
local make,err=loadstring(script.Source)
assert(make,err or "Studio TimeService Source compile failed")
local model=make()
local anchor={attrs={}}
function anchor:GetAttribute(name)return self.attrs[name] end
function anchor:SetAttribute(name,value)self.attrs[name]=value end
local sent=0
local sync={FireAllClients=function(_,clock,phase,progress,_,_,_,_,budget)
 sent+=1;assert(clock==120 and phase=="Day" and progress==.5 and budget==10)
end}
local profile={samples=0,overBudget=0,peakMs=0,peakAttributesMs=0,peakRemoteMs=0,
 lastMs=0,lastAttributesMs=0,lastRemoteMs=0,peakSampleAttributesMs=0,
 peakSampleRemoteMs=0,peakPhase=""}
local t=setmetatable({Config={Features={Weather=false},Budgets={SlowShares={TimePublish=.05}}},
 anchor=anchor,Remotes={sync=sync},Model={cycleSeconds=function()return 100 end},
 phase="Day",phaseLength=20,phaseElapsed=10,clockMinutes=120,nightIndex=0,
 threat=0,moonPhase="New",weather="Clear",weatherSeed=0,
 publishCost=profile},model)
t:publish(true)
assert(sent==1 and profile.samples==1 and profile.lastMs>=0 and profile.peakPhase=="Day",
 "Budgeted publication profile missing")
assert(anchor:GetAttribute("PhaseName")=="Day" and anchor:GetAttribute("ClockMinutes")==120,
 "Clock snapshot stopped publishing")
t:publish() -- immediate fade/Day prep is NOT a scheduled slot
assert(profile.samples==1 and sent==2,"Immediate snapshot counted as scheduled")
return game:GetService("HttpService"):JSONEncode({ok=true,samples=profile.samples,
 source=script:GetFullName(),clock=anchor:GetAttribute("ClockMinutes")})
