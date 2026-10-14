-- UNSUPPORTED BY CURRENT STUDIO BRIDGE: user confirmed the bridge does NOT
-- support live Play. Retained only as a read-only server-context template;
-- do not ask the user to keep Play running for a bridge call, and never
-- treat an Edit-mode result as active Play evidence. No Bootstrap.ensure,
-- no cleared peaks or changed budgets.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
local run=game:GetService("RunService")
local out={playing=run:IsRunning(),server=run:IsServer()}
if not out.playing or not out.server then
 out.error="Start fresh Play/Solo before measuring cadence"
 return game:GetService("HttpService"):JSONEncode(out)
end
local ok,runtime=pcall(function()
 return require(game:GetService("ServerStorage").Vitriol.Bootstrap).runtime()
end)
out.runtimeUp=ok and runtime~=nil
if out.runtimeUp then
 local cadence=runtime.Cadence
 out.phase=runtime.Time and runtime.Time.phase
 out.creatureThink=cadence:stats("Creature:Think")
 out.sessionSlow=cadence:stats("Session:Slow")
 out.timePublish=cadence:stats("Time:Publish")
 -- The section costs measure scheduled TimeService code only; compare against
 -- Cadence's whole-slot peak, not against an Edit-mode microbenchmark.
 out.timeSections=runtime.Time and runtime.Time.publishCost
 out.droppedBeats=cadence.droppedBeats
 out.lastFrameMs=cadence.lastFrameMs
end
return game:GetService("HttpService"):JSONEncode(out)
