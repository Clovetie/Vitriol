-- Compile the EXACT current Studio module fresh and reproduce BOTH user's stalls.
-- Lua table flags only; NEVER moves furniture or enables a prompt in Edit mode.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play for Edit probe")
local src=game:GetService("ServerStorage").Vitriol.Services.HouseCoverService
assert(src:IsA("ModuleScript"),"HouseCoverService class mismatch")
local compile,err=loadstring(src.Source)
assert(compile,err or "HouseCoverService compile failed")
local service=setmetatable({},compile())
service:init({Workspace=workspace,Players=game:GetService("Players"),Health={states={}},
 Time={phase="Night"},Session={state="Running"}})
local closet=assert(service.ByAction.CoverHouse01Closet)
closet.Placed=true -- ONLY Lua state, original Part and Editor prompts untouched
service.activeCount=1
for _,p in ipairs({{-91.7,79.4,-57.5,78.9},{-90.9,78.3,-63.9,77.9}}) do
 assert(service:intercept(p[1],p[2],p[3],p[4])==closet,"logged reverse interception failed")
 assert(service:bracing(p[1],p[2],p[3],p[4],true)==closet,"logged close egress bracing failed")
end
assert(service:bracing(-74.5,77,-90,77,true)==nil,"wrong-side lure may not break cover")
return game:GetService("HttpService"):JSONEncode({ok=true,closet=closet.Part:GetFullName(),
 target={closet.Target.Position.X,closet.Target.Position.Y,closet.Target.Position.Z},
 original={closet.Part.Position.X,closet.Part.Position.Y,closet.Part.Position.Z}})
