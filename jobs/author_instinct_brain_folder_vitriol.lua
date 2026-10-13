-- Guarded, idempotent EDIT-MODE folder for the local-only WP6 InstinctSearch.
-- Do not run in Play; no gameplay Instances are made at runtime.
assert(game.PlaceId == 92448193604950, "Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play before authoring")
local storage=game:GetService("ServerStorage")
local vitriol=storage:FindFirstChild("Vitriol")
local creature=vitriol and vitriol:FindFirstChild("Creature")
assert(vitriol and vitriol:IsA("Folder") and creature and creature:IsA("Folder"),
 "Missing authored ServerStorage.Vitriol.Creature")
local brain,count=nil,0
for _,child in ipairs(creature:GetChildren()) do
 if child.Name=="Brain" then brain,count=child,count+1 end
end
assert(count<=1 and (not brain or brain:IsA("Folder")),
 "Duplicate or wrong-class Creature.Brain; inspect before authoring")
local created=0
if not brain then
 brain=Instance.new("Folder") -- Edit mode ONLY
 brain.Name="Brain"
 brain.Parent=creature
 created=1
end
return game:GetService("HttpService"):JSONEncode({ok=true,created=created,
 reused=1-created,path=brain:GetFullName()})
