-- Edit-mode-only: attach accepted bell audio/light to the USER'S existing bell
-- MeshPart. Never create/replace a visual bell, move rope or target in Edit.
assert(game.PlaceId == 92448193604950, "Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play first")
local i=workspace.Map.Interactions
local root=i:FindFirstChild("Bell")
assert(root and root.ClassName=="Model", "User Bell root model missing")
local target=root:FindFirstChild("HoistPos")
local rope=root:FindFirstChild("Rope")
local nested=root:FindFirstChild("Bell")
local mesh=nested and nested:FindFirstChild("Bell")
assert(target and target:IsA("Part") and target.Anchored
    and rope and rope:IsA("Part") and rope.Anchored
    and nested and nested.ClassName=="Model"
    and mesh and mesh:IsA("MeshPart") and mesh.Anchored,
    "User bell/target/rope structure differs from surveyed Edit-mode assembly")
assert((target.Position-Vector3.new(118.9629,35.4683,-204.9779)).Magnitude<0.6,
    "HoistPos was moved since survey; inspect before authoring")
assert((nested:GetPivot().Position-Vector3.new(119,5.4039,-205.0059)).Magnitude<0.6,
    "Ground bell was moved since survey; inspect before authoring")
assert((rope.Position-Vector3.new(118.9845,23.4742,-204.978)).Magnitude<0.6,
    "User rope was moved since survey; inspect before authoring")
local function ensure(class,name)
    local found,count=nil,0
    for _,child in ipairs(mesh:GetChildren()) do
        if child.Name==name then found,count=child,count+1 end
    end
    assert(count<=1 and (not found or found.ClassName==class),"duplicate/wrong-class "..name)
    if found then return found,false end
    local child=Instance.new(class) -- EDIT MODE ONLY
    child.Name,child.Parent=name,mesh
    return child,true
end
local sound,createdSound=ensure("Sound","BellRing")
sound.SoundId="rbxassetid://130139735590457" -- user-provided three strikes
sound.Volume,sound.Looped=1,false
sound.RollOffMinDistance,sound.RollOffMaxDistance=18,180
local pulse,createdPulse=ensure("PointLight","BellPulse")
pulse.Color=Color3.fromRGB(255,205,125)
pulse.Brightness,pulse.Range,pulse.Shadows,pulse.Enabled=4,80,false,false
mesh:SetAttribute("Ringing",false)
return game:GetService("HttpService"):JSONEncode({ok=true,created=(createdSound and 1 or 0)+(createdPulse and 1 or 0),reused=(createdSound and 0 or 1)+(createdPulse and 0 or 1),model=nested:GetFullName(),rope=rope:GetFullName(),target=target:GetFullName()})
