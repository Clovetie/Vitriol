-- Read-only Edit-mode verifier for the inert, preauthored station blockout.
assert(not game:GetService("RunService"):IsRunning(), "Stop Play/Run before verifying")
assert(game.PlaceId == 92448193604950, "Wrong place")
local interactions = workspace.Map.Interactions
local defects = {}
local function one(parent, name, class)
    local found, count = nil, 0
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == name then count += 1; found = child end
    end
    if count ~= 1 or not found or found.ClassName ~= class then
        table.insert(defects, name .. " count/class " .. count .. "/" .. tostring(found and found.ClassName))
    end
    return found
end
local switch = one(interactions, "Station_FloodlightSwitch", "Part")
local fixture = one(interactions, "Station_Floodlight", "Part")
local repair = switch and one(switch, "RepairFloodlight", "ProximityPrompt")
local helper = switch and one(switch, "AssistFloodlight", "ProximityPrompt")
local light = fixture and one(fixture, "StationBeam", "PointLight")
if switch and (switch.Position - Vector3.new(-62, 4.2, -111)).Magnitude > 0.05 then table.insert(defects,"switch moved") end
if fixture and (fixture.Position - Vector3.new(-88, 11.8, -125)).Magnitude > 0.05 then table.insert(defects,"fixture moved") end
if switch and switch:GetAttribute("Repaired") ~= false then table.insert(defects,"unexpected repaired state") end
if fixture and fixture:GetAttribute("Powered") ~= false then table.insert(defects,"unexpected powered state") end
if repair and repair.Enabled then table.insert(defects,"unwired repair prompt enabled") end
if helper and helper.Enabled then table.insert(defects,"unwired help prompt enabled") end
if light and light.Enabled then table.insert(defects,"unwired light enabled") end
return game:GetService("HttpService"):JSONEncode({ok=#defects==0, authored=5, defects=defects})
