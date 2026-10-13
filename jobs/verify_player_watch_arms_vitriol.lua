-- Guarded read-only verification of the user's original and engine-copied template.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Wrong place/mode")
local failures={}
local function check(test,message) if not test then failures[#failures+1]=message end end
local client=game:GetService("StarterPlayer").StarterPlayerScripts.Vitriol.ClientMain
local gui=client:FindFirstChild("VitriolWatchOverlay")
local assets=game:GetService("ServerStorage").Vitriol:FindFirstChild("AuthoringAssets")
local source=assets and assets:FindFirstChild("ArmsSource")
local rig=client:FindFirstChild("Arms")
check(not workspace:FindFirstChild("Arms"),"source left in playable Workspace")
check(source and source:IsA("Model") and source:FindFirstChild("AnimSaves"),"unaltered user's source/keyframes not archived")
check(rig and rig:IsA("Model") and not rig:FindFirstChild("AnimSaves"),"lean per-player rig missing or keyframe baggage copied")
check(rig and rig.PrimaryPart and rig.PrimaryPart.Name=="HumanoidRootPart","animation root/primary part mismatch")
check(rig and rig:FindFirstChild("Clothing") and rig.Clothing:IsA("Shirt"),"authored Shirt missing")
local humanoid=rig and rig:FindFirstChild("Humanoid")
check(humanoid and humanoid:FindFirstChildOfClass("Animator"),"Animator missing")
check(humanoid and not humanoid.EvaluateStateMachine and humanoid.PlatformStand
    and not humanoid.AutoRotate,"camera viewmodel Humanoid must never simulate walking")
local visualCount=0
if rig then for _,part in ipairs(rig:GetDescendants()) do
    if part:IsA("BasePart") then
        visualCount+=1
        check(not part.CanCollide and not part.CanQuery and not part.CanTouch and part.Massless,
            "camera viewmodel Part is not fully visual: "..part.Name)
    end
end end
check(visualCount==9,"unexpected count of visual watch parts")
local anim=rig and rig:FindFirstChild("CheckWatch")
check(anim and anim:IsA("Animation") and anim.AnimationId=="rbxassetid://119603256128899","CheckWatch ID mismatch")
local upper=rig and rig:FindFirstChild("RightUpperArm")
local wrist=upper and upper:FindFirstChild("WristWatch")
for _, name in ipairs({"Band","Screen"}) do
    local part=wrist and wrist:FindFirstChild(name)
    local weld=part and part:FindFirstChild("Arm"..name.."Weld")
    check(part and part:IsA("BasePart") and not part.Anchored and not part.CanCollide
        and weld and weld:IsA("WeldConstraint") and weld.Part0==upper and weld.Part1==part,
        "watch "..name.." does not follow upper arm via authored weld")
end
local screen=wrist and wrist:FindFirstChild("Screen")
local surface=screen and screen:FindFirstChild("WatchSurface")
check(surface and surface:IsA("SurfaceGui") and surface.Adornee==screen
    and surface.Face==Enum.NormalId.Top and surface:FindFirstChild("WatchFaceText")
    and not surface.Enabled,"physical screen text/face/initial visibility mismatch")
check(gui and gui:FindFirstChild("SharedFade") and gui:FindFirstChild("WristViewmodel")
    and gui:FindFirstChild("WatchReadout"),"accepted overlay/fade changed")
local nodeCount=rig and #rig:GetDescendants() or 0
check(nodeCount<80,"template still contains editor animation keyframes")
return game:GetService("HttpService"):JSONEncode({ok=#failures==0,failures=failures,
    nodeCount=nodeCount,source=source and source:GetFullName() or nil,
    template=rig and rig:GetFullName() or nil})
