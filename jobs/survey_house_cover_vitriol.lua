-- Guarded read-only survey of the USER's two houses and furniture.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before surveying")
local map=workspace:FindFirstChild("Map")
assert(map and map:IsA("Folder"),"Missing map")
local structures=map:FindFirstChild("Structures")
local interiors=map:FindFirstChild("Interiors")
local interactions=map:FindFirstChild("Interactions")
local report={}
local function row(node)
 if not node then return nil end
 local entry={name=node.Name,class=node.ClassName,path=node:GetFullName()}
 if node:IsA("BasePart") then
  entry.position={node.Position.X,node.Position.Y,node.Position.Z}
  entry.size={node.Size.X,node.Size.Y,node.Size.Z}
  entry.anchored=node.Anchored;entry.collide=node.CanCollide;entry.query=node.CanQuery
  entry.cframe=tostring(node.CFrame);entry.color=tostring(node.Color)
 end
 return entry
end
for _,name in ipairs({"House_01","House_02"}) do
 local house=structures and structures:FindFirstChild(name)
 local furniture={}
 for _,suffix in ipairs({"Table","Closet"}) do
  furniture[suffix]=row(interiors and interiors:FindFirstChild(name.."_"..suffix))
 end
 local parts={}
 if house then for _,part in ipairs(house:GetChildren()) do
  if part:IsA("BasePart") and (part.Name=="Floor" or part.Name=="EastLintel"
   or string.sub(part.Name,1,9)=="EastPier_") then parts[#parts+1]=row(part) end
 end end
 local authored={}
 if interactions then for _,part in ipairs(interactions:GetChildren()) do
  if string.find(part.Name,name,1,true) then authored[#authored+1]=row(part) end
 end end
 report[name]={house=row(house),furniture=furniture,parts=parts,interactions=authored}
end
return game:GetService("HttpService"):JSONEncode(report)
