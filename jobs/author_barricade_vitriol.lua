-- Edit-mode-only, idempotent garage service-bay barricade authoring.
assert(game.PlaceId == 92448193604950, "Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play before authoring")
local map = workspace:FindFirstChild("Map")
assert(map and map:GetAttribute("VitriolMapVersion") == 1, "Requires verified Map v1")
local garage = map:FindFirstChild("Structures") and map.Structures:FindFirstChild("Millers_Garage")
assert(garage and garage:FindFirstChild("DoorLintel"), "Garage entry was modified; refuse blind barricade placement")
local interactions = map:FindFirstChild("Interactions")
assert(interactions and interactions:IsA("Folder"), "Author day-prep garage first")
local report = {created=0,reused=0}
local function ensure(parent,class,name)
    local match,count=nil,0
    for _,child in ipairs(parent:GetChildren()) do
        if child.Name==name then match=child; count+=1 end
    end
    assert(count<=1,"Duplicate "..name)
    if match then assert(match.ClassName==class,"Wrong class for "..name); report.reused+=1; return match end
    local node=Instance.new(class); node.Name=name; node.Parent=parent; report.created+=1; return node
end
-- The garage's eastern 40-stud opening lies under DoorLintel at x=-62.
-- The gate is invisible/nonblocking until the server boards it.
local gate=ensure(interactions,"Part","Garage_BoardedGate")
gate.Size=Vector3.new(1.2,12.6,40)
gate.CFrame=CFrame.new(-61.8,7,-56)
gate.Anchored=true
gate.Material=Enum.Material.Wood
gate.Color=Color3.fromRGB(91,67,48)
gate.Transparency=1
gate.CanCollide=false
gate.CanQuery=false
gate.CanTouch=false
gate:SetAttribute("Barricaded",false)
local latch=ensure(interactions,"Part","Garage_BoardingLatch")
latch.Size=Vector3.new(2,2,1)
latch.CFrame=CFrame.new(-66,2.4,-56)
latch.Anchored=true
latch.Material=Enum.Material.Metal
latch.Color=Color3.fromRGB(99,87,67)
latch.CanCollide=false
latch.CanTouch=false
local prompt=ensure(latch,"ProximityPrompt","BoardGarage")
prompt.ActionText="Board service bay (noisy)"
prompt.ObjectText="Garage barricade"
prompt.HoldDuration=3
prompt.MaxActivationDistance=9
prompt.RequiresLineOfSight=false
prompt.Enabled=true
return game:GetService("HttpService"):JSONEncode(report)
