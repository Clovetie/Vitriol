-- Read-only Edit-mode structural verification. Returns JSON with evidence.
local HttpService = game:GetService("HttpService")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play before verifying authored idle state")
local defects = {}
local function fail(msg) defects[#defects + 1] = msg end
local function unique(parent, className, name)
    if not parent then fail("missing parent for " .. name); return nil end
    local matched = {}
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == name then matched[#matched + 1] = child end
    end
    if #matched ~= 1 then fail("expected exactly one " .. name .. ", found " .. #matched); return nil end
    if matched[1].ClassName ~= className then fail(name .. " wrong class " .. matched[1].ClassName); return nil end
    return matched[1]
end
local rs = game:GetService("ReplicatedStorage")
local shared = unique(rs, "Folder", "Vitriol")
local comms = unique(shared, "Folder", "Comms")
local remotes = {RE_TimeSync="RemoteEvent",RE_SkeletonStream="RemoteEvent",RE_CreatureEvent="RemoteEvent",RE_SurvivalSync="RemoteEvent",RE_ClientIntent="RemoteEvent",RE_Destruction="RemoteEvent",RF_DebugQuery="RemoteFunction"}
for name, class in pairs(remotes) do unique(comms, class, name) end
if comms and #comms:GetChildren() ~= 7 then fail("Comms must contain exactly seven remotes") end
local root = unique(workspace, "Folder", "Vitriol")
local world = unique(root, "Folder", "World")
local anchor = unique(world, "Part", "TimeAnchor")
if anchor and (not anchor.Anchored or anchor.CanCollide or anchor.CanQuery or anchor.Transparency ~= 1) then fail("TimeAnchor not safe/invisible") end
local creatures = unique(root, "Folder", "Creatures")
local braid = unique(creatures, "Model", "Braid_1")
if braid then
    local core = unique(braid, "Part", "Core")
    if core and (core.CanQuery or core.Transparency ~= 1) then fail("idle Braid.Core must be hidden/non-queryable") end
    for i = 1, 14 do
        for j = 1, 15 do unique(braid, "Part", "Tendril_" .. i .. "_" .. j) end
    end
    if #braid:GetChildren() ~= 211 then fail("Braid_1 must have exactly 211 preauthored parts") end
end
local gore = unique(root, "Folder", "Gore")
if gore then
    for i = 1, 24 do unique(gore, "Part", "BloodDrop_" .. i) end
    if #gore:GetChildren() ~= 24 then fail("Gore pool must have exactly 24 authored parts") end
end
local sharedFolder = unique(shared, "Folder", "Shared")
local region = unique(sharedFolder, "ModuleScript", "RegionIntegrity")
if region and not region.Source:find("return RegionIntegrity",1,true) then fail("RegionIntegrity source is not complete") end
-- An executable LocalScript cannot be required. This class mismatch previously
-- stopped ClientMain before the RE_TimeSync listener could bind.
local playerScripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local clientFolder = unique(playerScripts, "Folder", "Vitriol")
local client = unique(clientFolder, "LocalScript", "ClientMain")
if client and not client.Enabled then fail("ClientMain must be enabled") end
local controllers = unique(clientFolder, "Folder", "Controllers")
unique(controllers, "ModuleScript", "VictimCamera")
unique(controllers, "ModuleScript", "LightingDriver")
local result = {ok=#defects==0, defects=defects, parts=braid and #braid:GetChildren() or 0, drops=gore and #gore:GetChildren() or 0, remoteCount=comms and #comms:GetChildren() or 0, place=game.Name, placeId=game.PlaceId}
return HttpService:JSONEncode(result)
