-- Edit-mode-only station floodlight blockout. Inert until the shared prep
-- transaction, vote and fade/clock slice is integrated. Never run in Play.
local RunService = game:GetService("RunService")
assert(not RunService:IsRunning(), "Stop Play/Run before authoring station")
assert(game.PlaceId == 92448193604950, "Wrong Vitriol place")
local map = workspace:FindFirstChild("Map")
assert(map and map:IsA("Folder") and map:GetAttribute("VitriolMapVersion") == 1, "Requires verified Map v1")
local structures = map:FindFirstChild("Structures")
local station = structures and structures:FindFirstChild("Filling_Station")
local canopy = station and station:FindFirstChild("Canopy")
assert(canopy and canopy:IsA("BasePart") and (canopy.Position - Vector3.new(-88, 13, -125)).Magnitude < 0.05
    and (canopy.Size - Vector3.new(64, 1.4, 34)).Magnitude < 0.05,
    "Station canopy differs from surveyed map; refuse blind authoring")
local interiors = map:FindFirstChild("Interiors")
local pump = interiors and interiors:FindFirstChild("FuelPump_1")
assert(pump and pump:IsA("BasePart") and (pump.Position - Vector3.new(-70, 2.5, -135)).Magnitude < 0.05,
    "Station pump differs from surveyed map")
local interactions = map:FindFirstChild("Interactions")
assert(interactions and interactions:IsA("Folder"), "Missing authored Map.Interactions")
local report = {created=0, reused=0}
local function ensure(parent, class, name)
    local found, count = nil, 0
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == name then found, count = child, count + 1 end
    end
    assert(count <= 1, "Duplicate " .. parent:GetFullName() .. "." .. name)
    if found then
        assert(found.ClassName == class, "Wrong class for " .. found:GetFullName())
        report.reused += 1
        return found
    end
    local object = Instance.new(class) -- EDITOR ONLY; no runtime game objects
    object.Name, object.Parent = name, parent
    report.created += 1
    return object
end
local existingSwitch = interactions:FindFirstChild("Station_FloodlightSwitch")
local switch = ensure(interactions, "Part", "Station_FloodlightSwitch")
switch.Size = Vector3.new(1.4, 2.5, 0.8)
-- User reapproved the LIVE switch at -111. Preserve existing position; only
-- choose that default if the author creates an entirely missing switch.
if not existingSwitch then switch.CFrame = CFrame.new(-62, 4.2, -111) end
switch.Anchored, switch.CanCollide, switch.CanQuery, switch.CanTouch = true, false, true, false
switch.Material, switch.Color = Enum.Material.Metal, Color3.fromRGB(68, 82, 89)
switch:SetAttribute("Repaired", false)
local prompt = ensure(switch, "ProximityPrompt", "RepairFloodlight")
prompt.ActionText, prompt.ObjectText = "Repair floodlight", "Station floodlight"
prompt.MaxActivationDistance, prompt.HoldDuration = 10, 2
prompt.RequiresLineOfSight, prompt.Enabled = false, false -- no live handler yet
local helper = ensure(switch, "ProximityPrompt", "AssistFloodlight")
helper.ActionText, helper.ObjectText = "Volunteer to help", "Station repair"
helper.MaxActivationDistance, helper.HoldDuration = 12, 0.2
helper.RequiresLineOfSight, helper.Enabled = false, false -- transaction activates later
local fixture = ensure(interactions, "Part", "Station_Floodlight")
fixture.Size = Vector3.new(5, 1, 1.4)
fixture.CFrame = CFrame.new(-88, 11.8, -125)
fixture.Anchored, fixture.CanCollide, fixture.CanQuery, fixture.CanTouch = true, false, false, false
fixture.Material, fixture.Color = Enum.Material.Metal, Color3.fromRGB(78, 89, 92)
fixture:SetAttribute("Powered", false)
local light = ensure(fixture, "PointLight", "StationBeam")
light.Color = Color3.fromRGB(202, 230, 238)
light.Range, light.Brightness, light.Shadows, light.Enabled = 44, 2.8, true, false
return game:GetService("HttpService"):JSONEncode(report)
