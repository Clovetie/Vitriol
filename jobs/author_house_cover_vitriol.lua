-- Edit-only, guarded/idempotent author: four prompts on the EXISTING tables
-- and closets plus four invisible target poses. Never change user furniture.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before authoring")
local map=workspace:FindFirstChild("Map")
assert(map and map:IsA("Folder"),"Missing Map folder")
local structures=map:FindFirstChild("Structures")
local interiors=map:FindFirstChild("Interiors")
local interactions=map:FindFirstChild("Interactions")
assert(structures and interiors and interactions,"Missing authored house hierarchy")
local specifications={}
for _,id in ipairs({"House_01","House_02"}) do
 local house=structures:FindFirstChild(id)
 local floor=house and house:FindFirstChild("Floor")
 local negative=house and house:FindFirstChild("EastPier_-13")
 local positive=house and house:FindFirstChild("EastPier_13")
 local lintel=house and house:FindFirstChild("EastLintel")
 assert(floor and floor:IsA("Part") and negative and negative:IsA("Part")
  and positive and positive:IsA("Part") and lintel and lintel:IsA("Part"),"Incomplete house: "..id)
 local x,z=floor.Position.X,floor.Position.Z
 assert(math.abs(negative.Position.X-(x+21))<.05 and math.abs(negative.Position.Z-(z-13))<.05
  and math.abs(positive.Position.X-(x+21))<.05 and math.abs(positive.Position.Z-(z+13))<.05
  and math.abs(lintel.Position.X-(x+21))<.05 and math.abs(lintel.Position.Z-z)<.05
  and math.abs(floor.Size.X-42)<.05,"House doorway changed; re-survey before authoring: "..id)
 for _,kind in ipairs({"Table","Closet"}) do
  local furniture=interiors:FindFirstChild(id.."_"..kind)
  assert(furniture and furniture:IsA("Part") and furniture.Anchored,"Missing anchored furniture: "..id.."_"..kind)
  local y=kind=="Table" and 2 or 4
  local centerZ=kind=="Table" and z-3.5 or z+5
  local size=kind=="Table" and Vector3.new(9,1.3,5) or Vector3.new(6,8,5)
  assert((furniture.Size-size).Magnitude<.05 and math.abs(furniture.Position.Y-y)<.05
   and math.abs(furniture.Position.X-(x+(kind=="Table" and 0 or -14)))<.05
   and math.abs(furniture.Position.Z-(z+(kind=="Table" and 0 or 10)))<.05,
   "Furniture has changed; re-survey before authoring: "..furniture.Name)
  local target=CFrame.new(x+18.5,y,centerZ)*CFrame.Angles(0,math.pi/2,0)
  specifications[#specifications+1]={part=furniture,kind=kind,house=id,target=target}
 end
end
local created,reused=0,0
local targets=interactions:FindFirstChild("HouseCoverTargets")
if targets then assert(targets:IsA("Folder"),"HouseCoverTargets wrong class")
else targets=Instance.new("Folder");targets.Name="HouseCoverTargets";targets.Parent=interactions;created+=1 end
local rows={}
local function prompt(part,name,text,enabled)
 local node=part:FindFirstChild(name)
 if node then assert(node:IsA("ProximityPrompt"),"Wrong class: "..part.Name.."."..name);reused+=1
 else node=Instance.new("ProximityPrompt");node.Name=name;node.Parent=part;created+=1 end
 node.ActionText=text
 node.ObjectText=part.Name
 node.KeyboardKeyCode=Enum.KeyCode.E
 node.HoldDuration=0.7
 node.MaxActivationDistance=10
 node.RequiresLineOfSight=true
 node.Enabled=enabled
 return node
end
for _,entry in ipairs(specifications) do
 local name=entry.part.Name.."Target"
 local marker=targets:FindFirstChild(name)
 if marker then assert(marker:IsA("Part"),"Target wrong class: "..name);reused+=1
 else marker=Instance.new("Part");marker.Name=name;marker.Parent=targets;created+=1 end
 marker.Size=Vector3.new(.5,.5,.5)
 marker.CFrame=entry.target
 marker.Anchored=true
 marker.CanCollide=false;marker.CanTouch=false;marker.CanQuery=false
 marker.Transparency=1;marker.CastShadow=false;marker.Locked=true
 prompt(entry.part,"MoveToEntrance","Move "..string.lower(entry.kind).." to doorway",false)
 prompt(entry.part,"AssistHouseCover","Help move "..string.lower(entry.kind),false)
 rows[#rows+1]={part=entry.part:GetFullName(),home=tostring(entry.part.CFrame),target=tostring(marker.CFrame),
  dimensions={entry.part.Size.X,entry.part.Size.Y,entry.part.Size.Z},prompts=2}
end
return game:GetService("HttpService"):JSONEncode({ok=true,created=created,reused=reused,pieces=rows})
