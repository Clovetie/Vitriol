-- Guarded Edit-mode ONLY. Preserve the user's complete Workspace.Arms source
-- under ServerStorage; author ONE lean per-player copy beneath ClientMain.
-- Engine copies it with PlayerScripts. No runtime Clone/Instance.new.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play first")
local server=game:GetService("ServerStorage").Vitriol
local client=game:GetService("StarterPlayer").StarterPlayerScripts.Vitriol.ClientMain
assert(client and client:IsA("LocalScript"),"Missing accepted ClientMain")
local gui=client:FindFirstChild("VitriolWatchOverlay")
assert(gui and gui:IsA("ScreenGui") and gui:FindFirstChild("SharedFade")
    and gui:FindFirstChild("WatchReadout"),"Accepted watch GUI changed")
local assets=server:FindFirstChild("AuthoringAssets")
local source=workspace:FindFirstChild("Arms")
local existing=client:FindFirstChild("Arms")
if existing then
    assert(existing.ClassName=="Model" and assets and assets:FindFirstChild("ArmsSource")
        and not source, "Arms template/source differs; refuse blind re-authoring")
    local watch=existing:FindFirstChild("RightUpperArm")
    watch=watch and watch:FindFirstChild("WristWatch")
    assert(watch and watch:FindFirstChild("Screen") and existing:FindFirstChild("CheckWatch"),"Arms template incomplete")
    return game:GetService("HttpService"):JSONEncode({ok=true,reused=true,preservedUserSource=true})
end
assert(source and source.ClassName=="Model" and source.Archivable,"User Workspace.Arms missing/uncloneable")
assert(not assets or not assets:FindFirstChild("ArmsSource"),"Archived source already exists; resolve duplicate first")
local root=source:FindFirstChild("Primary")
local upper=source:FindFirstChild("RightUpperArm")
local wrist=upper and upper:FindFirstChild("WristWatch")
local band=wrist and wrist:FindFirstChild("Band")
local screen=wrist and wrist:FindFirstChild("Screen")
local human=source:FindFirstChild("Humanoid")
assert(root and root:IsA("BasePart") and root.Anchored and upper and upper:IsA("MeshPart")
    and wrist and wrist:IsA("Model") and band and band:IsA("Part")
    and screen and screen:IsA("Part") and human and human:IsA("Humanoid")
    and human:FindFirstChildOfClass("Animator"),"User Arms rig/watch differs from survey")
assert((root.Position-Vector3.new(8.97755,2,-176.54866)).Magnitude<.3
    and (screen.Position-Vector3.new(7.47755,2.4900,-173.51668)).Magnitude<.3,
    "User has moved Arms since survey; inspect before authoring")
local copy=source:Clone() -- EDIT MODE ONLY; user's original is preserved intact below
assert(copy and copy:IsA("Model"),"Failed to copy user's authored model")
copy.Name="Arms"
local saves=copy:FindFirstChild("AnimSaves")
if saves then saves:Destroy() end -- trim editor-only keyframes from per-player copy
local copyRoot=copy:FindFirstChild("Primary")
copyRoot.Name="HumanoidRootPart" -- animation pose root; original keeps name
copy.PrimaryPart=copyRoot
local copyUpper=copy:FindFirstChild("RightUpperArm")
local copyWatch=copyUpper:FindFirstChild("WristWatch")
local copyBand=copyWatch:FindFirstChild("Band")
local copyScreen=copyWatch:FindFirstChild("Screen")
local function weld(part,name)
    assert(not part:FindFirstChild(name),"Unexpected duplicate watch weld")
    local joint=Instance.new("WeldConstraint") -- EDIT MODE ONLY
    joint.Name=name; joint.Part0=copyUpper; joint.Part1=part; joint.Parent=part
    part.Anchored=false
    part.CanCollide,part.CanQuery,part.CanTouch=false,false,false
end
weld(copyBand,"ArmBandWeld")
weld(copyScreen,"ArmScreenWeld")
local surface=Instance.new("SurfaceGui") -- preauthored physical watch UI
surface.Name="WatchSurface";surface.Adornee=copyScreen;surface.Face=Enum.NormalId.Top
surface.CanvasSize=Vector2.new(300,130)
surface.SizingMode=Enum.SurfaceGuiSizingMode.FixedSize
surface.AlwaysOnTop=true;surface.LightInfluence=0;surface.Enabled=false
surface.Parent=copyScreen
local face=Instance.new("TextLabel")
face.Name="WatchFaceText";face.Size=UDim2.fromScale(1,1)
face.BackgroundTransparency=1;face.Text="DAY --:--";face.TextScaled=true
face.Font=gui.WatchReadout.Font;face.TextColor3=gui.WatchReadout.TextColor3
face.TextStrokeColor3=Color3.fromRGB(0,14,16);face.TextStrokeTransparency=.15
face.Parent=surface
local animation=Instance.new("Animation")
animation.Name="CheckWatch";animation.AnimationId="rbxassetid://119603256128899"
animation.Parent=copy
-- Visual-only camera-mounted rig. No physics, character floor queries or
-- touches can let an avatar surf on a limb when the check pose lowers.
for _,part in ipairs(copy:GetDescendants()) do
    if part:IsA("BasePart") then
        part.CanCollide,part.CanQuery,part.CanTouch=false,false,false
        part.Massless=true
    end
end
local copyHuman=copy:FindFirstChildOfClass("Humanoid")
copyHuman.EvaluateStateMachine=false
copyHuman.PlatformStand=true
copyHuman.AutoRotate=false
-- The accepted overlay and its user-adjusted layout are NOT touched.
copy.Parent=client
if not assets then
    assets=Instance.new("Folder") -- EDIT MODE ONLY
    assets.Name="AuthoringAssets";assets.Parent=server
end
source.Name="ArmsSource";source.Parent=assets -- archive exact original, no world artifact
return game:GetService("HttpService"):JSONEncode({ok=true,createdTemplate=true,removedEditorOnlyKeys=saves~=nil,archived=source:GetFullName(),perPlayer=copy:GetFullName()})
