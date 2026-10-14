-- Read-only, Edit-mode barricade audit.
assert(game.PlaceId == 92448193604950, "Wrong place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play before verification")
local defects={}
local function one(parent,name,class)
    if not parent then defects[#defects+1]="missing parent "..name; return nil end
    local found,count=nil,0
    for _,child in ipairs(parent:GetChildren()) do if child.Name==name then found=child; count+=1 end end
    if count~=1 or found.ClassName~=class then defects[#defects+1]=name.." missing or wrong class"; return nil end
    return found
end
local map=one(workspace,"Map","Folder")
local interactions=one(map,"Interactions","Folder")
local gate=one(interactions,"Garage_BoardedGate","Part")
local latch=one(interactions,"Garage_BoardingLatch","Part")
local prompt=one(latch,"BoardGarage","ProximityPrompt")
if gate and (not gate.Anchored or gate.CanCollide or gate.CanQuery or gate.Transparency~=1
    or math.abs(gate.Position.X+61.8)>.01 or gate.Size.Z~=40 or gate:GetAttribute("Barricaded")~=false) then
    defects[#defects+1]="gate idle shape/state changed"
end
if prompt and (prompt.MaxActivationDistance~=9 or prompt.HoldDuration~=3) then defects[#defects+1]="prompt cost/range changed" end
return game:GetService("HttpService"):JSONEncode({ok=#defects==0, defects=defects, gate=gate and gate.Name, prompt=prompt and prompt.Name})
