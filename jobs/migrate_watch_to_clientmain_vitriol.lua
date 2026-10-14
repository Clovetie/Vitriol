-- Move the user's existing, edited preauthored wrist UI into the LocalScript
-- template so Roblox copies one authored GUI per PlayerScripts. Edit mode only.
-- This changes ONLY Parent: no Position/Size/text/color is reset or cloned.
assert(game.PlaceId == 92448193604950, "Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play/Run before watch migration")
local sp = game:GetService("StarterPlayer")
local root = sp:FindFirstChild("StarterPlayerScripts")
local vitriol = root and root:FindFirstChild("Vitriol")
local client = vitriol and vitriol:FindFirstChild("ClientMain")
assert(client and client:IsA("LocalScript"), "Missing authored ClientMain LocalScript")
local starterGui = game:GetService("StarterGui")
local source = starterGui:FindFirstChild("VitriolWatchOverlay")
local destination = client:FindFirstChild("VitriolWatchOverlay")
assert(not (source and destination), "Two wrist overlays; refuse ambiguous migration")
local overlay = source or destination
assert(overlay and overlay:IsA("ScreenGui"), "Missing authored wrist ScreenGui")
local view = overlay:FindFirstChild("WristViewmodel")
local readout = overlay:FindFirstChild("WatchReadout")
local fade = overlay:FindFirstChild("SharedFade")
assert(view and view:IsA("ViewportFrame") and readout and readout:IsA("TextLabel")
    and fade and fade:IsA("Frame"), "User watch UI has unexpected class/tree; preserve it")
assert(view:FindFirstChild("WristCamera") and view:FindFirstChild("WristModel"), "Missing preauthored 3D viewmodel")
local oldPosition, oldSize, oldReadoutPosition, oldReadoutSize = view.Position, view.Size, readout.Position, readout.Size
if source then source.Parent = client end
assert(view.Position == oldPosition and view.Size == oldSize
    and readout.Position == oldReadoutPosition and readout.Size == oldReadoutSize,
    "Refuse a migration that changes the user's wrist layout")
return game:GetService("HttpService"):JSONEncode({moved=source~=nil,reused=destination~=nil,
    parent=overlay.Parent:GetFullName(),layoutPreserved=true})
