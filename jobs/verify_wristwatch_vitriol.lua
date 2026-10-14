-- Read-only verifier. Inert until client controller/fade integration.
assert(game.PlaceId == 92448193604950 and not game:GetService("RunService"):IsRunning(), "Wrong place/mode")
local defects = {}
local function one(parent, name, class)
    if not parent then table.insert(defects, "missing parent for " .. name); return nil end
    local found, count = nil, 0
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == name then found, count = child, count + 1 end
    end
    if count ~= 1 or not found or found.ClassName ~= class then
        table.insert(defects, name .. " count/class " .. count .. "/" .. tostring(found and found.ClassName))
    end
    return found
end
local scripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
local root = scripts and scripts:FindFirstChild("Vitriol")
local client = root and root:FindFirstChild("ClientMain")
local gui = one(client, "VitriolWatchOverlay", "ScreenGui")
if game:GetService("StarterGui"):FindFirstChild("VitriolWatchOverlay") then
    table.insert(defects, "legacy StarterGui copy can obscure the per-player template")
end
local viewport = gui and one(gui, "WristViewmodel", "ViewportFrame")
local readout = gui and one(gui, "WatchReadout", "TextLabel")
local fade = gui and one(gui, "SharedFade", "Frame")
local camera = viewport and one(viewport, "WristCamera", "Camera")
local world = viewport and one(viewport, "WristModel", "WorldModel")
if world then
    for _, name in ipairs({"Forearm","Hand","Strap","Case","Dial"}) do one(world,name,"Part") end
end
if gui and gui.Enabled then table.insert(defects,"unwired watch GUI enabled") end
if viewport and viewport.Visible then table.insert(defects,"unwired viewmodel visible") end
if viewport and viewport.CurrentCamera ~= camera then table.insert(defects,"viewmodel camera not bound") end
if readout and readout.Visible then table.insert(defects,"unwired readout visible") end
if fade and (fade.Visible or fade.BackgroundTransparency ~= 1) then table.insert(defects,"unwired fade visible") end
return game:GetService("HttpService"):JSONEncode({ok=#defects==0,authored=11,defects=defects})
