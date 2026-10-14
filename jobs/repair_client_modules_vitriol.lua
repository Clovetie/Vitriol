-- Guarded, idempotent Edit-mode repair of a controller authored with the wrong class.
-- LightingDriver is required by ClientMain and therefore MUST be a ModuleScript.
-- This job does not create game objects in Play; it changes exactly one script
-- class in the verified Vitriol place, preserving its source for guarded sync.
assert(game.PlaceId == 92448193604950, "Refusing client-module repair in a different place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play before repairing client modules")
local HttpService = game:GetService("HttpService")
local parent = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
assert(parent, "StarterPlayerScripts is missing")
local root = parent:FindFirstChild("Vitriol")
assert(root and root.ClassName == "Folder", "StarterPlayerScripts.Vitriol folder is missing")
local controllers = root:FindFirstChild("Controllers")
assert(controllers and controllers.ClassName == "Folder", "Vitriol.Controllers folder is missing")
local client = root:FindFirstChild("ClientMain")
assert(client and client.ClassName == "LocalScript", "ClientMain must remain a LocalScript")
local count, old = 0, nil
for _, child in ipairs(controllers:GetChildren()) do
    if child.Name == "LightingDriver" then count += 1; old = child end
    assert(child.Name ~= "LightingDriver__Repair", "Clear unexpected repair temp before continuing")
end
assert(count == 1, "Expected exactly one LightingDriver")
if old.ClassName == "ModuleScript" then
    return HttpService:JSONEncode({ok=true, changed=false, className=old.ClassName})
end
assert(old.ClassName == "LocalScript", "Refusing unexpected LightingDriver class: " .. old.ClassName)
assert(old.Source:find("return LightingDriver", 1, true), "Unexpected LightingDriver source")
local replacement = Instance.new("ModuleScript")
replacement.Name = "LightingDriver__Repair"
replacement.Source = old.Source
replacement.Parent = controllers
assert(replacement.Source == old.Source, "LightingDriver source copy failed")
-- Keep the original until the replacement is safely populated and parented.
local ok, err = pcall(function()
    old.Name = "LightingDriver__FormerLocalScript"
    replacement.Name = "LightingDriver"
    old:Destroy()
end)
if not ok then
    replacement:Destroy()
    if old.Parent == controllers then old.Name = "LightingDriver" end
    error("LightingDriver class repair failed: " .. tostring(err))
end
return HttpService:JSONEncode({ok=true, changed=true, className=replacement.ClassName})
