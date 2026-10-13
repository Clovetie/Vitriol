-- Edit-mode-only, idempotent church-bell day-prep authoring. Never run in Play.
local RunService = game:GetService("RunService")
assert(not RunService:IsRunning(), "Stop Play/Run before authoring the bell")
assert(game.PlaceId == 92448193604950, "Wrong Vitriol place")
local map = workspace:FindFirstChild("Map")
assert(map and map:IsA("Folder") and map:GetAttribute("VitriolMapVersion") == 1, "Requires verified Map v1")
local structures = map:FindFirstChild("Structures")
local church = structures and structures:FindFirstChild("Church_BellTower")
local tower = church and church:FindFirstChild("BellTower")
assert(tower and tower:IsA("BasePart") and math.abs(tower.Position.X - 119) < 0.01
    and math.abs(tower.Position.Z + 205) < 0.01, "Church tower differs from surveyed map; refuse blind authoring")
local interactions = map:FindFirstChild("Interactions")
assert(interactions and interactions:IsA("Folder"), "Author the existing garage interactions first")
assert(not interactions:FindFirstChild("Bell"),
    "User's Bell model supersedes this prototype author job; use author_user_bell_hoist_vitriol.lua")
local report = {created = 0, reused = 0}
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
    local object = Instance.new(class) -- Editor job ONLY; never a game-code allocation
    object.Name, object.Parent = name, parent
    report.created += 1
    return object
end
local lever = ensure(interactions, "Part", "Church_BellLever")
lever.Size = Vector3.new(2, 3, 1)
-- Historical prototype job is blocked by the existing user Bell model. If
-- ever reused in a different safe authoring context, respect the owner's
-- newer approval of the already-authored rest position; do not move this Part.
lever.CFrame = CFrame.new(119, 2.5, -199)
lever.Anchored, lever.CanCollide, lever.CanQuery, lever.CanTouch = true, false, true, false
lever.Material = Enum.Material.Metal
lever.Color = Color3.fromRGB(88, 83, 73)
lever:SetAttribute("Armed", false)
local prompt = ensure(lever, "ProximityPrompt", "PrimeBell")
prompt.ActionText = "Prime for next night"
prompt.ObjectText = "Church bell signal"
prompt.HoldDuration = 2
prompt.MaxActivationDistance = 10
prompt.RequiresLineOfSight = false
prompt.Enabled = true
local bell = ensure(interactions, "Part", "Church_Bell")
bell.Size = Vector3.new(3.5, 5, 5)
bell.CFrame = CFrame.new(119, 51.4, -205) * CFrame.Angles(0, 0, math.pi/2)
bell.Shape = Enum.PartType.Cylinder
bell.Anchored, bell.CanCollide, bell.CanQuery, bell.CanTouch = true, false, false, false
bell.Material = Enum.Material.Metal
bell.Color = Color3.fromRGB(155, 111, 54)
bell:SetAttribute("Ringing", false)
local pulse = ensure(bell, "PointLight", "BellPulse")
pulse.Color = Color3.fromRGB(255, 205, 125)
pulse.Brightness, pulse.Range, pulse.Shadows, pulse.Enabled = 4, 80, false, false
local sound = ensure(bell, "Sound", "BellRing")
-- Provided by the user: the clip itself contains three strikes. Play ONCE.
sound.SoundId = "rbxassetid://130139735590457"
sound.Volume, sound.Looped = 1, false
sound.RollOffMinDistance, sound.RollOffMaxDistance = 18, 180
return game:GetService("HttpService"):JSONEncode(report)
