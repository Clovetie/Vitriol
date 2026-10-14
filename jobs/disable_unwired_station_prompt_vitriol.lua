-- One narrowly scoped Edit-mode fix: don't advertise an unwired repair action.
-- Preserves the user's switch layout, color, and all existing authored content.
assert(game.PlaceId == 92448193604950, "Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play/Run before editing station")
local map = workspace:FindFirstChild("Map")
assert(map and map:GetAttribute("VitriolMapVersion") == 1, "Wrong map")
local i = map:FindFirstChild("Interactions")
local switch = i and i:FindFirstChild("Station_FloodlightSwitch")
assert(switch and switch:IsA("Part") and (switch.Position-Vector3.new(-62,4.2,-111)).Magnitude < 0.1,
    "Switch moved again; refuse blind prompt edit")
local prompt = switch:FindFirstChild("RepairFloodlight")
assert(prompt and prompt:IsA("ProximityPrompt"), "Missing authored repair prompt")
local wasEnabled = prompt.Enabled
prompt.Enabled = false
return game:GetService("HttpService"):JSONEncode({disabled=wasEnabled,position=tostring(switch.Position),preservedLayout=true})
