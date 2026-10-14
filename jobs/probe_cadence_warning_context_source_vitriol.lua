-- READ ONLY/Edit: fresh actual Studio Sources; no server boot, cadence pump,
-- game state or timing. This proves branch labeling, NOT Play performance.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local vitriol=game:GetService("ServerStorage").Vitriol
local bootstrap=vitriol.Bootstrap
local service=vitriol.Services.SessionService
assert(bootstrap:IsA("ModuleScript") and service:IsA("ModuleScript"),"module classes wrong")
assert(loadstring(bootstrap.Source),"Bootstrap Source failed to compile")
assert(string.find(bootstrap.Source,'name == "Session:Slow"',1,true)
 and string.find(bootstrap.Source,'name == "Creature:Think"',1,true),
 "exceptional warning contexts missing")
local make,err=loadstring(service.Source)
assert(make,err or "SessionService Source failed to compile")
local proto=make()
local s=setmetatable({state="Intermission",intermissionLeft=0.5,elapsed=0},proto)
s.beginRound=function(self)self.state="Running" end
s:tick(1)
assert(s.state=="Running" and s.lastSlowPath=="begin-round",
 "same-slot begin-round path lost")
s:tick(1)
assert(s.elapsed==1 and s.lastSlowPath=="running",
 "running path not distinct from round start")
s.state="Ended"
s:tick(1)
assert(s.lastSlowPath=="ended" and s.elapsed==1,
 "ended path advanced session time")
return game:GetService("HttpService"):JSONEncode({ok=true,
 paths={"begin-round","running","ended"},bootstrap=bootstrap:GetFullName(),
 session=service:GetFullName(),editOnly=true})
