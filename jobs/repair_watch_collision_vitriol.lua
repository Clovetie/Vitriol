-- Guarded Edit-mode-only fix for viewmodel surfing. Do NOT touch player avatar
-- collisions or the user's archived source. The engine-copied template is visual.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Wrong place/mode")
local client=game:GetService("StarterPlayer").StarterPlayerScripts.Vitriol.ClientMain
local rig=client:FindFirstChild("Arms")
local archived=game:GetService("ServerStorage").Vitriol.AuthoringAssets:FindFirstChild("ArmsSource")
assert(rig and rig:IsA("Model") and archived and archived:IsA("Model")
    and not workspace:FindFirstChild("Arms"),"Original/template layout differs")
local humanoid=rig:FindFirstChildOfClass("Humanoid")
assert(humanoid and humanoid:FindFirstChildOfClass("Animator")
    and rig.PrimaryPart and rig.PrimaryPart.Name=="HumanoidRootPart", "Authored animation rig differs")
local count=0
for _,part in ipairs(rig:GetDescendants()) do
    if part:IsA("BasePart") then
        assert(not part.CanCollide,"Unexpected collidable watch part: "..part:GetFullName())
        -- Noncollidable alone did not prevent avatar floor/proximity queries
        -- against this camera-mounted rig. Make it entirely presentation-only.
        part.CanQuery=false
        part.CanTouch=false
        part.Massless=true
        count+=1
    end
end
assert(count==9,"Expected root, six limb meshes and two welded watch Parts")
-- This Humanoid exists to host the user's Animator, not to walk/stand on the
-- camera's geometry. Keep animations, suppress its physics state machine.
humanoid.EvaluateStateMachine=false
humanoid.PlatformStand=true
humanoid.AutoRotate=false
return game:GetService("HttpService"):JSONEncode({ok=true,parts=count,
    rootAnchored=rig.PrimaryPart.Anchored,avatarUntouched=true})
