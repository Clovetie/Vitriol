-- Read-only, Edit-mode verifier of two run-persistent light repair surfaces.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Wrong place/mode")
local failures={}
local function check(v,message) if not v then failures[#failures+1]=message end end
local i=workspace.Map.Interactions
local generator=i:FindFirstChild("Garage_Generator")
local lamp=i:FindFirstChild("Garage_GeneratorLamp")
local station=i:FindFirstChild("Station_FloodlightSwitch")
check(generator and generator:IsA("Part") and generator:FindFirstChild("PowerLamp")
    and generator:FindFirstChild("AssistPrep"),"accepted garage prep missing")
check(lamp and lamp:IsA("Part") and lamp:FindFirstChild("PoweredLight"),"garage lamp missing")
for _,spec in ipairs({{"RepairGarageLight",10,2},{"AssistGarageLight",12,.2}}) do
    local count,found=0,nil
    if generator then for _,child in ipairs(generator:GetChildren()) do
        if child.Name==spec[1] then count+=1;found=child end
    end end
    check(count==1 and found and found:IsA("ProximityPrompt") and not found.Enabled
        and found.MaxActivationDistance==spec[2]
        and math.abs(found.HoldDuration-spec[3])<.01,"garage prompt "..spec[1].." invalid")
end
check(station and station:IsA("Part") and station:FindFirstChild("RepairFloodlight")
    and station:FindFirstChild("AssistFloodlight"),"station repair missing")
return game:GetService("HttpService"):JSONEncode({ok=#failures==0,failures=failures})
