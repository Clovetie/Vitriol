-- READ ONLY / Edit: estimate relative attribute-read and pure-model costs.
-- Not a Play replication/RemoteEvent benchmark, never a budget verdict.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Edit Vitriol only")
local anchor=workspace.Vitriol.World.TimeAnchor
local model=require(game:GetService("ReplicatedStorage").Vitriol.Shared.TimeModel)
local n=10000
local function measure(f)
 local start=os.clock();for i=1,n do f(i) end
 return (os.clock()-start)*1e3/n
end
local sink
local getMs=measure(function(i)sink=anchor:GetAttribute(i%2==0 and "MoonPhase" or "ClockMinutes")end)
local mathMs=measure(function(i)sink=model.cycleSeconds(i%2)end)
return game:GetService("HttpService"):JSONEncode({getAttributeMs=getMs,cycleSecondsMs=mathMs,
 anchor=anchor:GetFullName(),n=n,note="read-only Edit microbenchmark, excludes SetAttribute and FireAllClients"})
