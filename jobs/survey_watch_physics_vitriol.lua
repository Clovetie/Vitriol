-- Guarded read-only physics/rig audit of the per-player watch template.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Wrong place/mode")
local rig=game:GetService("StarterPlayer").StarterPlayerScripts.Vitriol.ClientMain:FindFirstChild("Arms")
local rows={}
for _,x in ipairs(rig and rig:GetDescendants() or {}) do
 if x:IsA("BasePart") then
  rows[#rows+1]={path=x:GetFullName(),class=x.ClassName,anchored=x.Anchored,
   collide=x.CanCollide,touch=x.CanTouch,query=x.CanQuery,massless=x.Massless,
   collisionGroup=x.CollisionGroup,transparency=x.Transparency,
   localTransparency=x.LocalTransparencyModifier}
 elseif x:IsA("Humanoid") then
  rows[#rows+1]={path=x:GetFullName(),class=x.ClassName,hipHeight=x.HipHeight,
   platformStand=x.PlatformStand,autoRotate=x.AutoRotate,evaluate=x.EvaluateStateMachine}
 elseif x:IsA("Animator") or x:IsA("AnimationController") then
  rows[#rows+1]={path=x:GetFullName(),class=x.ClassName}
 end
end
return game:GetService("HttpService"):JSONEncode({ok=rig~=nil,parts=rows})
