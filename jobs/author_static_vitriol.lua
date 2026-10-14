-- EDIT MODE ONLY: pre-author all Vitriol runtime-visible Instances. Idempotent.
-- This script is sent via run_luau to the Studio plugin. Nothing here runs in Play mode.
local RunService = game:GetService("RunService")
assert(not RunService:IsRunning(), "Stop Play/Run before authoring Vitriol Instances")
local HttpService = game:GetService("HttpService")
local counts = { created = 0, reused = 0, removedBrokenDuplicate = 0 }
local function ensure(parent, class, name)
    local found = nil
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == name then
            assert(found == nil, "duplicate authored child: " .. parent:GetFullName() .. "." .. name)
            assert(child.ClassName == class, "wrong class: " .. child:GetFullName() .. " (expected " .. class .. ")")
            found = child
        end
    end
    if found then counts.reused += 1; return found end
    local inst = Instance.new(class)
    inst.Name = name
    inst.Parent = parent
    counts.created += 1
    return inst
end
local storage = game:GetService("ReplicatedStorage")
local shared = storage:FindFirstChild("Vitriol")
assert(shared and shared:IsA("Folder"), "Vitriol code must already be installed before authoring objects")
local comms = ensure(shared, "Folder", "Comms")
for _, name in ipairs({"RE_TimeSync", "RE_SkeletonStream", "RE_CreatureEvent", "RE_SurvivalSync", "RE_ClientIntent", "RE_Destruction"}) do
    ensure(comms, "RemoteEvent", name)
end
ensure(comms, "RemoteFunction", "RF_DebugQuery")
local root = ensure(workspace, "Folder", "Vitriol")
local world = ensure(root, "Folder", "World")
local anchor = ensure(world, "Part", "TimeAnchor")
anchor.Size = Vector3.new(0.05, 0.05, 0.05)
anchor.CFrame = CFrame.new(0, -2000, 0)
anchor.Anchored = true
anchor.Transparency = 1
anchor.CanCollide = false
anchor.CanTouch = false
anchor.CanQuery = false
local creatures = ensure(root, "Folder", "Creatures")
local model = ensure(creatures, "Model", "Braid_1")
local function part(name, shape)
    local p = ensure(model, "Part", name)
    p.Shape = shape
    p.Size = Vector3.new(0.2, 0.2, 0.2)
    p.CFrame = CFrame.new(0, -1990, 0)
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false -- enabled only while the authored model is active
    p.Transparency = 1
    p.CastShadow = false
    return p
end
part("Core", Enum.PartType.Ball)
-- MonsterConfig.Genes.TendrilCount.max = 14; Genetics:express => 8..16 joints,
-- hence up to 15 segments per tendril. Raise these bounds TOGETHER if genome changes.
for i = 1, 14 do
    for j = 1, 15 do
        part("Tendril_" .. i .. "_" .. j, Enum.PartType.Cylinder)
    end
end
model:SetAttribute("Archetype", "Braid")
model:SetAttribute("Threatening", false)
local gore = ensure(root, "Folder", "Gore")
for i = 1, 24 do
    local p = ensure(gore, "Part", "BloodDrop_" .. i)
    p.Shape = Enum.PartType.Ball
    p.Size = Vector3.new(0.1, 0.1, 0.1)
    p.CFrame = CFrame.new(0, -1980, 0)
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.Transparency = 1
    p.CastShadow = false
end
-- An earlier integration left two modules named RegionIntegrity; one is
-- truncated and returns nil. Delete ONLY the unmistakably broken copy.
local vitriol = shared:FindFirstChild("Shared")
local good = 0
if vitriol then
    for _, node in ipairs(vitriol:GetChildren()) do
        if node.Name == "RegionIntegrity" and node:IsA("ModuleScript") then
            if node.Source:match("return%s*$") or node.Source:match("return%s*\n%s*$") then
                node:Destroy()
                counts.removedBrokenDuplicate += 1
            else
                good += 1
            end
        end
    end
end
assert(good == 1, "Expected exactly one valid RegionIntegrity ModuleScript after repair; found " .. good)
return HttpService:JSONEncode(counts)
