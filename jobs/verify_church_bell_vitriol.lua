-- Read-only Edit-mode verifier for the USER'S bell model and hoist assembly.
assert(game.PlaceId == 92448193604950 and not game:GetService("RunService"):IsRunning(),"Wrong place/mode")
local defects={}
local function one(parent,name,class)
    local found,count=nil,0
    if parent then
        for _,child in ipairs(parent:GetChildren()) do
            if child.Name==name then found,count=child,count+1 end
        end
    end
    if count~=1 or not found or found.ClassName~=class then
        defects[#defects+1]=name.." expected one "..class..", got "..tostring(count)
        return nil
    end
    return found
end
local map=one(workspace,"Map","Folder")
if map and map:GetAttribute("VitriolMapVersion")~=1 then defects[#defects+1]="map version" end
local structures=one(map,"Structures","Folder")
local church=one(structures,"Church_BellTower","Model")
local tower=one(church,"BellTowerBody","UnionOperation")
local interactions=one(map,"Interactions","Folder")
local lever=one(interactions,"Church_BellLever","Part")
local prompt=one(lever,"PrimeBell","ProximityPrompt")
local bellRoot=one(interactions,"Bell","Model")
local target=one(bellRoot,"HoistPos","Part")
local rope=one(bellRoot,"Rope","Part")
local bellModel=one(bellRoot,"Bell","Model")
local bell=one(bellModel,"Bell","MeshPart")
local bering=one(bellModel,"bering","Part")
local pulse=one(bell,"BellPulse","PointLight")
local sound=one(bell,"BellRing","Sound")
if interactions and interactions:FindFirstChild("Church_Bell") then
    defects[#defects+1]="obsolete generated bell would obscure user's model"
end
if tower and (math.abs(tower.Position.X-119)>0.01 or math.abs(tower.Position.Z+205)>0.01) then defects[#defects+1]="tower moved" end
-- The owner revised the approved Edit/rest coordinate to the already-authored
-- (119,2.5,-199) after a read-only check of the solid Bell at the old Z=-210.
if lever and (not lever.Anchored or lever.CanCollide or math.abs(lever.Position.X-119)>0.01
    or math.abs(lever.Position.Y-2.5)>0.01 or math.abs(lever.Position.Z+199)>0.01
    or lever:GetAttribute("Armed")~=false) then
    defects[#defects+1]="lever changed at rest"
end
if prompt and (prompt.MaxActivationDistance~=10 or math.abs(prompt.HoldDuration-2)>.01 or not prompt.Enabled) then defects[#defects+1]="bell prompt timing/reach" end
if not (bell and bell.Anchored and bering and bering.Anchored and bell:GetAttribute("Ringing")==false) then defects[#defects+1]="user bell not anchored/idle" end
if bellModel and (bellModel:GetPivot().Position-Vector3.new(119,5.4039,-205.0059)).Magnitude>.6 then defects[#defects+1]="bell not grounded at Edit rest" end
if rope and (not rope.Anchored or (rope.Position-Vector3.new(118.9845,23.4742,-204.978)).Magnitude>.6) then defects[#defects+1]="rope not at user's grounded pose" end
if target and (not target.Anchored or (target.Position-Vector3.new(118.9629,35.4683,-204.9779)).Magnitude>.6) then defects[#defects+1]="HoistPos changed" end
if pulse and (pulse.Enabled or pulse.Range~=80) then defects[#defects+1]="pulse should start off" end
if sound and (sound.SoundId~="rbxassetid://130139735590457" or sound.Looped or sound.Volume~=1) then defects[#defects+1]="user-provided sound changed" end
return game:GetService("HttpService"):JSONEncode({ok=#defects==0,defects=defects,authored=7,model=bellModel and bellModel:GetFullName() or nil})
