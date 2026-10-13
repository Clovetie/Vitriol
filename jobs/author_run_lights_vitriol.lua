-- Guarded, idempotent EDIT-MODE only: garage repair and co-op helper prompts.
-- Reuse the player's existing station and garage geometry/illumination.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before authoring")
local interactions=workspace.Map.Interactions
local generator=interactions:FindFirstChild("Garage_Generator")
local lamp=interactions:FindFirstChild("Garage_GeneratorLamp")
local station=interactions:FindFirstChild("Station_FloodlightSwitch")
assert(generator and generator:IsA("Part") and (generator.Position-Vector3.new(-112,2.8,-60)).Magnitude<.2,
    "Garage generator moved; survey before changing")
assert(lamp and lamp:IsA("Part") and (lamp.Position-Vector3.new(-91,16.8,-52)).Magnitude<.2
    and lamp:FindFirstChild("PoweredLight"),"Garage lamp moved/missing")
-- Survey readback found the station switch at Z=-111 although the earlier
-- accepted coordinate is Z=-110. Preserve the user's live geometry; this job
-- only adds garage prompts and adjusts the station prompt's wording.
assert(station and station:IsA("Part") and station:FindFirstChild("RepairFloodlight"),
    "Station switch/repair prompt missing")
assert(generator:FindFirstChild("PowerLamp") and generator:FindFirstChild("AssistPrep"),
    "Accepted garage prep not authored")
local report={created=0,reused=0}
local function prompt(name, action, object, distance, hold)
    local found,count=nil,0
    for _,child in ipairs(generator:GetChildren()) do
        if child.Name==name then count+=1;found=child end
    end
    assert(count<=1 and (not found or found:IsA("ProximityPrompt")),"Conflicting prompt "..name)
    if found then report.reused+=1 else
        found=Instance.new("ProximityPrompt") -- EDIT MODE ONLY
        found.Name=name;found.Parent=generator;report.created+=1
    end
    found.ActionText,found.ObjectText=action,object
    found.MaxActivationDistance,found.HoldDuration=distance,hold
    found.RequiresLineOfSight,found.Enabled=false,false
end
prompt("RepairGarageLight","Repair broken light","Garage generator",10,2)
prompt("AssistGarageLight","Volunteer to help","Garage light repair",12,.2)
-- Keep the accepted station prompt, but its description must no longer imply
-- an automatic dawn reset. Do not move or replace the user's switch.
station.RepairFloodlight.ActionText="Repair floodlight"
return game:GetService("HttpService"):JSONEncode({ok=true,created=report.created,reused=report.reused})
