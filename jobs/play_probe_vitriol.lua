-- READ ONLY. Run through the bridge DURING Studio Play/Solo, on the server poller.
-- Never starts the runtime itself: failure to boot is a result, not a reason
-- for this probe to call Bootstrap.ensure() and hide the underlying defect.
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local result = { playing = RunService:IsRunning(), server = RunService:IsServer(), placeId = game.PlaceId }
if not result.playing or not result.server then
    result.error = "Start a fresh Play/Solo session; the bridge job must run on the server"
    return HttpService:JSONEncode(result)
end
local ok, runtime = pcall(function()
    return require(game:GetService("ServerStorage").Vitriol.Bootstrap).runtime()
end)
result.bootstrapLoaded = ok
if not ok then result.error = tostring(runtime) end
result.runtimeUp = ok and runtime ~= nil
local workspaceRoot = workspace:FindFirstChild("Vitriol")
local creatures = workspaceRoot and workspaceRoot:FindFirstChild("Creatures")
local braid = creatures and creatures:FindFirstChild("Braid_1")
local gore = workspaceRoot and workspaceRoot:FindFirstChild("Gore")
local shared = game:GetService("ReplicatedStorage"):FindFirstChild("Vitriol")
local comms = shared and shared:FindFirstChild("Comms")
result.remoteCount = comms and #comms:GetChildren() or -1
result.braidParts = braid and #braid:GetChildren() or -1
result.goreParts = gore and #gore:GetChildren() or -1
result.players = #game:GetService("Players"):GetPlayers()
if result.runtimeUp then
    local creature = runtime.Creature
    result.creatureCount = creature and #creature.order or -1
    result.phase = runtime.Time and runtime.Time.phase or "missing"
    result.clockMinutes = runtime.Time and runtime.Time.clockMinutes or -1
    result.cadenceRunning = runtime.Cadence and runtime.Cadence.running or false
    result.activeBraid = braid and braid:GetAttribute("Threatening") or false
end
result.staticTreeOK = result.remoteCount == 7 and result.braidParts == 211 and result.goreParts == 24
return HttpService:JSONEncode(result)
