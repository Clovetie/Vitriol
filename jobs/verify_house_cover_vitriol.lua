-- Read-only Edit-mode verification of four existing furniture Parts and markers.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before verifying")
local map=workspace:FindFirstChild("Map")
local items=assert(map and map:FindFirstChild("Interiors"))
local structures=assert(map:FindFirstChild("Structures"))
local markers=assert(map.Interactions:FindFirstChild("HouseCoverTargets"))
local faults,rows={},{}
local function fail(msg) faults[#faults+1]=msg end
for _,name in ipairs({"House_01","House_02"}) do
 local house=assert(structures:FindFirstChild(name))
 local floor=assert(house:FindFirstChild("Floor"))
 local door=assert(house:FindFirstChild("EastPier_-13")).Position.X
 local center=floor.Position.Z
 for _,kind in ipairs({"Table","Closet"}) do
  local label=name.."_"..kind
  local part=assert(items:FindFirstChild(label))
  local target=assert(markers:FindFirstChild(label.."Target"))
  local action=part:FindFirstChild("MoveToEntrance")
  local helper=part:FindFirstChild("AssistHouseCover")
  if not part:IsA("Part") or not part.Anchored or not part.CanCollide or not part.CanQuery then fail(label.." original Part properties") end
  if not action or not action:IsA("ProximityPrompt") or action.Enabled then fail(label.." move prompt") end
  if not helper or not helper:IsA("ProximityPrompt") or helper.Enabled then fail(label.." helper prompt") end
  if not target:IsA("Part") or target.Transparency~=1 or target.CanQuery or target.CanCollide or target.CanTouch
   or not target.Anchored then fail(label.." marker properties") end
  local expectedWidth=kind=="Table" and 9 or 6
  local z=kind=="Table" and center-3.5 or center+5
  local homeX=floor.Position.X+(kind=="Table" and 0 or -14)
  local homeZ=center+(kind=="Table" and 0 or 10)
  if math.abs(part.Position.X-homeX)>.05 or math.abs(part.Position.Z-homeZ)>.05 or math.abs(part.Size.X-expectedWidth)>.05
   or math.abs(target.Position.X-(door-2.5))>.05 or math.abs(target.Position.Z-z)>.05
   or math.abs(target.CFrame.RightVector.Z)<.99 then fail(label.." furniture or target pose changed") end
  local ray=workspace:Raycast(Vector3.new(door+8,4,z),Vector3.new(-20,0,0))
  if ray then fail(label.." direct doorway approach blocked by "..ray.Instance:GetFullName()) end
  rows[#rows+1]={name=label,home={part.Position.X,part.Position.Y,part.Position.Z},
   target={target.Position.X,target.Position.Y,target.Position.Z},width=part.Size.X,
   directDoorwayRay=ray and ray.Instance:GetFullName() or "clear"}
 end
end
return game:GetService("HttpService"):JSONEncode({ok=#faults==0,faults=faults,pieces=rows})
