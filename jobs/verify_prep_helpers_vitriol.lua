-- Read-only Edit-mode verifier: all future co-op vote prompts preauthored,
-- distinct, disabled, and near the intended completed-prep interactions.
assert(game.PlaceId == 92448193604950, "Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play before verifying")
local i = workspace.Map.Interactions
local defects = {}
for _, spec in ipairs({
    {"Garage_FuelCan", "AssistPrep"},
    {"Garage_Generator", "AssistPrep"},
    {"Church_BellLever", "AssistPrep"},
    {"Garage_BoardingLatch", "AssistPrep"},
    {"Station_FloodlightSwitch", "AssistFloodlight"},
}) do
    local part = i:FindFirstChild(spec[1])
    if not part or not part:IsA("Part") then
        table.insert(defects, "missing part "..spec[1])
    else
        local prompt, count = nil, 0
        for _, ch in ipairs(part:GetChildren()) do
            if ch.Name == spec[2] then prompt, count = ch, count + 1 end
        end
        if count ~= 1 or not prompt:IsA("ProximityPrompt") or prompt.Enabled
            or prompt.MaxActivationDistance ~= 12 or math.abs(prompt.HoldDuration - 0.2) > 0.01 then
            table.insert(defects, "invalid/in-use helper "..spec[1])
        end
    end
end
return game:GetService("HttpService"):JSONEncode({ok=#defects==0,authored=5,defects=defects})
