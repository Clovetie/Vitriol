-- Server-only READ-ONLY M3 diagnostic during Play; no public RF_DebugQuery
-- extension, no created Instances, no mutation of a live target or memory.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
local run=game:GetService("RunService")
local out={playing=run:IsRunning(),server=run:IsServer()}
if not out.playing or not out.server then
 out.error="Start Play/Solo for live AIDebugDump"
 return game:GetService("HttpService"):JSONEncode(out)
end
local ok,runtime=pcall(function()
 return require(game:GetService("ServerStorage").Vitriol.Bootstrap).runtime()
end)
out.runtimeUp=ok and runtime~=nil
if out.runtimeUp then out.ai=runtime.Creature:aiDump() end
return game:GetService("HttpService"):JSONEncode(out)
