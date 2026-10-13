-- Edit-mode-only, idempotent garage fuel/generator/lamp authoring.
assert(game.PlaceId == 92448193604950, "Refusing to edit a different place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play before authoring")
local HttpService = game:GetService("HttpService")
local map = workspace:FindFirstChild("Map")
assert(map and map:IsA("Folder") and map:GetAttribute("VitriolMapVersion") == 1, "Requires verified Map v1")
local interiors = map:FindFirstChild("Interiors")
assert(interiors and interiors:FindFirstChild("Garage_Workbench"), "Expected authored garage workbench")
local report = {created=0, reused=0}
local function ensure(parent, class, name)
    local found, count = nil, 0
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == name then found = child; count += 1 end
    end
    assert(count <= 1, "Duplicate " .. name)
    if found then
        assert(found.ClassName == class, "Wrong class for " .. name)
        report.reused += 1
        return found
    end
    local node = Instance.new(class)
    node.Name = name
    node.Parent = parent
    report.created += 1
    return node
end
local folder = ensure(map, "Folder", "Interactions")
local function part(name,x,y,z,w,h,d,material,color)
    local node = ensure(folder,"Part",name)
    node.Size = Vector3.new(w,h,d)
    node.CFrame = CFrame.new(x,y,z)
    node.Anchored = true
    node.CanCollide = false
    node.CanQuery = true
    node.CanTouch = false
    node.Material = material
    node.Color = color
    return node
end
local can = part("Garage_FuelCan",-111,4.05,-45,1.6,2,1.1,Enum.Material.Metal,Color3.fromRGB(148,54,37))
local take = ensure(can,"ProximityPrompt","TakeFuel")
take.ActionText = "Take fuel can"
take.ObjectText = "Garage supply"
take.MaxActivationDistance = 10
take.HoldDuration = 0.5
take.RequiresLineOfSight = false
take.Enabled = true
local gen = part("Garage_Generator",-112,2.8,-60,3.4,4.7,3.2,Enum.Material.CorrodedMetal,Color3.fromRGB(76,81,78))
gen:SetAttribute("Powered",false)
local power = ensure(gen,"ProximityPrompt","PowerLamp")
power.ActionText = "Use fuel: power lamp"
power.ObjectText = "Noisy garage generator"
power.MaxActivationDistance = 10
power.HoldDuration = 1.2
power.RequiresLineOfSight = false
power.Enabled = true
local bulb = part("Garage_GeneratorLamp",-91,16.8,-52,2,0.65,2,Enum.Material.Metal,Color3.fromRGB(75,82,83))
local light = ensure(bulb,"PointLight","PoweredLight")
light.Color = Color3.fromRGB(239,177,96)
light.Range = 36
light.Brightness = 2.6
light.Shadows = true
light.Enabled = false
return HttpService:JSONEncode(report)
