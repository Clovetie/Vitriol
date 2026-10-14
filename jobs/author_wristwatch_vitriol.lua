-- Guarded Edit-mode-only, preauthored first-person wristwatch/viewmodel blockout.
-- Inert and disabled until a client controller and shared fade are integrated.
assert(not game:GetService("RunService"):IsRunning(), "Stop Play/Run before authoring UI")
assert(game.PlaceId == 92448193604950, "Wrong Vitriol place")
-- PlayerScripts always receives the LocalScript with its authored descendants.
-- Do not rely on StarterGui auto-population when CharacterAutoLoads is false.
local scripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local root = scripts and scripts:FindFirstChild("Vitriol")
local guiRoot = root and root:FindFirstChild("ClientMain")
assert(guiRoot and guiRoot:IsA("LocalScript"), "Missing authored ClientMain")
assert(not game:GetService("StarterGui"):FindFirstChild("VitriolWatchOverlay"),
    "Legacy StarterGui watch exists; first run migrate_watch_to_clientmain_vitriol.lua")
local report = {created=0, reused=0}
local existing = guiRoot:FindFirstChild("VitriolWatchOverlay")
if existing then
    -- A user has hand-adjusted this UI in Studio. Never reset Size/Position,
    -- face alignment, text or colors when re-running the author job.
    assert(existing:IsA("ScreenGui") and existing:FindFirstChild("WristViewmodel")
        and existing:FindFirstChild("WatchReadout") and existing:FindFirstChild("SharedFade"),
        "Existing watch must pass the read-only verifier before reuse")
    return game:GetService("HttpService"):JSONEncode({created=0,reused=11,preservedUserLayout=true})
end
local function ensure(parent, class, name)
    local found, count = nil, 0
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == name then count += 1; found = child end
    end
    assert(count <= 1, "Duplicate " .. parent:GetFullName() .. "." .. name)
    if found then
        assert(found.ClassName == class, "Wrong class for " .. found:GetFullName())
        report.reused += 1
        return found
    end
    local object = Instance.new(class) -- EDITOR ONLY
    object.Name, object.Parent = name, parent
    report.created += 1
    return object
end
local gui = ensure(guiRoot, "ScreenGui", "VitriolWatchOverlay")
gui.Enabled, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = false, false, true, 70
local viewport = ensure(gui, "ViewportFrame", "WristViewmodel")
viewport.Size = UDim2.fromScale(0.30, 0.38)
viewport.Position = UDim2.fromScale(0.66, 0.60)
viewport.BackgroundTransparency = 1
viewport.BorderSizePixel, viewport.Visible = 0, false
viewport.Ambient = Color3.fromRGB(160, 169, 176)
viewport.LightColor, viewport.LightDirection = Color3.fromRGB(245, 241, 218), Vector3.new(-0.7, -1, -1)
local camera = ensure(viewport, "Camera", "WristCamera")
camera.CFrame = CFrame.new(Vector3.new(0, 0.2, 7), Vector3.new(0, 0, 0))
camera.FieldOfView = 38
viewport.CurrentCamera = camera
local world = ensure(viewport, "WorldModel", "WristModel")
local function part(name, size, cframe, color, material, shape)
    local p = ensure(world, "Part", name)
    p.Size, p.CFrame = size, cframe
    p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
    p.Color, p.Material = color, material
    p.Shape = shape or Enum.PartType.Block
    return p
end
part("Forearm", Vector3.new(1.0, 3.2, 1.0), CFrame.new(0.46, -1.0, -0.2)*CFrame.Angles(0,0,-0.34), Color3.fromRGB(142, 109, 82), Enum.Material.Fabric, Enum.PartType.Cylinder)
part("Hand", Vector3.new(0.83, 1.12, 0.65), CFrame.new(-0.25, 0.76, -0.15)*CFrame.Angles(0,0,-0.34), Color3.fromRGB(181, 138, 104), Enum.Material.SmoothPlastic)
part("Strap", Vector3.new(1.18, 0.92, 1.12), CFrame.new(0, 0.05, 0), Color3.fromRGB(28, 37, 42), Enum.Material.Fabric)
part("Case", Vector3.new(1.10, 0.86, 0.30), CFrame.new(0, 0.05, 0.62), Color3.fromRGB(107, 115, 110), Enum.Material.Metal)
part("Dial", Vector3.new(0.93, 0.67, 0.045), CFrame.new(0, 0.05, 0.80), Color3.fromRGB(18, 35, 35), Enum.Material.SmoothPlastic)
-- Face-aligned 2D readout overlays the preauthored 3D wrist viewmodel. No
-- floating full-screen timer HUD; hidden unless the player raises their wrist.
local display = ensure(gui, "TextLabel", "WatchReadout")
display.Size, display.Position = UDim2.fromScale(0.095,0.045), UDim2.fromScale(0.764,0.774)
display.BackgroundTransparency, display.BorderSizePixel = 1, 0
display.Text = "DAY 03:30"
display.TextScaled, display.Font = true, Enum.Font.Code
display.TextColor3 = Color3.fromRGB(140, 240, 200)
display.Visible = false
local fade = ensure(gui, "Frame", "SharedFade")
fade.Size, fade.Position = UDim2.fromScale(1,1), UDim2.fromScale(0,0)
fade.BackgroundColor3, fade.BackgroundTransparency = Color3.new(0,0,0), 1
fade.BorderSizePixel, fade.Visible, fade.ZIndex = 0, false, 10
return game:GetService("HttpService"):JSONEncode(report)
