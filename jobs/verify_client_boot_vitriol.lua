-- Read-only Edit-mode probe for ClientMain's pre-bind dependency chain.
-- Requiring these modules runs their top-level code, not the client LocalScript;
-- no gameplay is started and no UI/game objects are authored by this job.
assert(game.PlaceId == 92448193604950, "Refusing client boot probe in a different place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play before verifying client boot")
local HttpService = game:GetService("HttpService")
local failures = {}
local loaded = {}
local function check(parent, name, className, requiredFields)
    if not parent then failures[#failures+1] = "missing parent of " .. name; return nil end
    local found, count = nil, 0
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == name then found = child; count += 1 end
    end
    if count ~= 1 or found.ClassName ~= className then
        failures[#failures+1] = name .. " expected one " .. className .. ", found " .. tostring(count) .. " / " .. (found and found.ClassName or "nil")
        return nil
    end
    if className == "ModuleScript" then
        -- Edit-mode require() may return a cached, older controller after a
        -- guarded source sync. Compile these dependency-free modules fresh.
        local fresh = name == "WatchController" or name == "PrepFadeController"
        local ok, result
        if fresh then
            local loader = loadstring(found.Source)
            ok, result = pcall(loader)
        else
            ok, result = pcall(require, found)
        end
        if not ok then
            failures[#failures+1] = name .. " require failed: " .. tostring(result)
        else
            loaded[#loaded+1] = name
            for _, field in ipairs(requiredFields or {}) do
                if result[field] == nil then failures[#failures+1] = name .. " missing " .. field end
            end
        end
    end
    return found
end
local rs = game:GetService("ReplicatedStorage")
local shared = check(rs, "Vitriol", "Folder")
local config = check(shared, "Config", "Folder")
local sharedModules = check(shared, "Shared", "Folder")
local comms = check(shared, "Comms", "Folder")
check(comms, "RE_TimeSync", "RemoteEvent")
check(comms, "RE_CreatureEvent", "RemoteEvent")
check(config, "DayNightConfig", "ModuleScript", {"Keyframes", "Pacing"})
check(sharedModules, "Remotes", "ModuleScript", {"await", "FolderName"})
local playerScripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local playerRoot = check(playerScripts, "Vitriol", "Folder")
local client = check(playerRoot, "ClientMain", "LocalScript")
if client and not client.Enabled then failures[#failures+1] = "ClientMain disabled" end
local controllers = check(playerRoot, "Controllers", "Folder")
check(controllers, "VictimCamera", "ModuleScript", {"new"})
check(controllers, "LightingDriver", "ModuleScript", {"new", "receive", "start"})
check(controllers, "WatchController", "ModuleScript", {"new", "start", "receive"})
check(controllers, "PrepFadeController", "ModuleScript", {"new", "receive"})
return HttpService:JSONEncode({ok=#failures==0, failures=failures, loaded=loaded, clientEnabled=client and client.Enabled or false})
