-- Guarded, idempotent Edit-mode helper prompts for future 3-second co-op votes.
-- Deliberately DISABLED until server-owned PrepCoordinator is integrated.
assert(game.PlaceId == 92448193604950, "Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play/Run before helper authoring")
local map = workspace:FindFirstChild("Map")
assert(map and map:IsA("Folder") and map:GetAttribute("VitriolMapVersion") == 1, "Requires Map v1")
local i = map:FindFirstChild("Interactions")
assert(i and i:IsA("Folder"), "Missing authored interactions")
local specs = {
    {"Garage_FuelCan", "TakeFuel", "Help carry fuel", -111, -45},
    {"Garage_Generator", "PowerLamp", "Help power lamp", -112, -60},
    {"Church_BellLever", "PrimeBell", "Help prime bell", 119, -199}, -- owner revised rest coordinate
    {"Garage_BoardingLatch", "BoardGarage", "Help board garage", -66, -56},
}
local report = {created=0,reused=0}
for _, spec in ipairs(specs) do
    local parent = i:FindFirstChild(spec[1])
    assert(parent and parent:IsA("Part") and math.abs(parent.Position.X-spec[4])<1
        and math.abs(parent.Position.Z-spec[5])<1, "Authored interaction moved: "..spec[1])
    local action = parent:FindFirstChild(spec[2])
    assert(action and action:IsA("ProximityPrompt"), "Missing existing action prompt "..spec[2])
    local found, count = nil, 0
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == "AssistPrep" then found, count = child, count + 1 end
    end
    assert(count <= 1 and (not found or found:IsA("ProximityPrompt")), "Duplicate/wrong AssistPrep on "..spec[1])
    if found then report.reused += 1 else
        found = Instance.new("ProximityPrompt") -- EDITOR JOB ONLY
        found.Name, found.Parent = "AssistPrep", parent
        report.created += 1
    end
    found.ActionText, found.ObjectText = "Volunteer to help", spec[3]
    found.MaxActivationDistance, found.HoldDuration = 12, 0.2
    found.RequiresLineOfSight, found.Enabled = false, false
end
local station = i:FindFirstChild("Station_FloodlightSwitch")
assert(station and station:IsA("Part") and (station.Position-Vector3.new(-62,4.2,-111)).Magnitude < 0.1,
    "User-approved station switch position changed")
local stationHelper = station:FindFirstChild("AssistFloodlight")
assert(stationHelper and stationHelper:IsA("ProximityPrompt") and not stationHelper.Enabled,
    "Station helper must already be authored and disabled")
return game:GetService("HttpService"):JSONEncode(report)
