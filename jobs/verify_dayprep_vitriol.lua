-- Read-only Edit-mode audit of the garage day-preparation objects.
assert(game.PlaceId == 92448193604950, "Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play before verification")
local failures = {}
local function find(parent, name, class)
    if not parent then failures[#failures+1] = "missing parent "..name; return nil end
    local count, found = 0, nil
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == name then count += 1; found = child end
    end
    if count ~= 1 or found.ClassName ~= class then
        failures[#failures+1] = name .. " expected exactly one " .. class
        return nil
    end
    return found
end
local map = find(workspace, "Map", "Folder")
local folder = find(map, "Interactions", "Folder")
local can = find(folder, "Garage_FuelCan", "Part")
local generator = find(folder, "Garage_Generator", "Part")
local bulb = find(folder, "Garage_GeneratorLamp", "Part")
local take = find(can, "TakeFuel", "ProximityPrompt")
local power = find(generator, "PowerLamp", "ProximityPrompt")
local light = find(bulb, "PoweredLight", "PointLight")
-- Barricade and later authored interactions can share this folder; the three
-- day-prep parts above must each exist exactly once, not be its only children.
for _, part in ipairs({can, generator, bulb}) do
    if part and (not part.Anchored or part.CanCollide) then failures[#failures+1] = part.Name.." unsafe collision" end
end
for _, prompt in ipairs({take, power}) do
    if prompt and prompt.MaxActivationDistance ~= 10 then failures[#failures+1] = prompt.Name.." wrong reach" end
end
if light and light.Enabled then failures[#failures+1] = "generator lamp must start off" end
return game:GetService("HttpService"):JSONEncode({ok=#failures==0, failures=failures, parts=folder and #folder:GetChildren() or 0, prompts=take and power and 2 or 0})
