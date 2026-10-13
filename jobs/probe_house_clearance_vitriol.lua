-- Read-only geometry probe. Never modifies houses or sources.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before Edit-mode geometry probe")
local m=assert(workspace:FindFirstChild("Map"))
local structures=assert(m:FindFirstChild("Structures"))
local res={}
for _,name in ipairs({"House_01","House_02"}) do
 local h=assert(structures:FindFirstChild(name))
 local floor=assert(h:FindFirstChild("Floor"))
 local lintel=assert(h:FindFirstChild("EastLintel"))
 local roof=assert(h:FindFirstChild("Roof"))
 local porchRoof=assert(h:FindFirstChild("PorchRoof"))
 local x,z=lintel.Position.X,floor.Position.Z
 local function p(part)
  return {path=part:GetFullName(),position={part.Position.X,part.Position.Y,part.Position.Z},size={part.Size.X,part.Size.Y,part.Size.Z},canQuery=part.CanQuery}
 end
 local rays={}
 for _,offset in ipairs({-9,-5,-1,1,5,9,16,25}) do
  local px=x+offset
  local up=workspace:Raycast(Vector3.new(px,2,z),Vector3.new(0,33,0))
  local down=workspace:Raycast(Vector3.new(px,38,z),Vector3.new(0,-37,0))
  local level=workspace:Raycast(Vector3.new(px,9,z),Vector3.new(-12,0,0))
  rays[#rays+1]={offset=offset,up=up and {part=up.Instance:GetFullName(),y=up.Position.Y} or nil,
   down=down and {part=down.Instance:GetFullName(),y=down.Position.Y} or nil,
   level=level and {part=level.Instance:GetFullName(),x=level.Position.X} or nil}
 end
 res[name]={floor=p(floor),lintel=p(lintel),roof=p(roof),porchRoof=p(porchRoof),rays=rays}
end
return game:GetService("HttpService"):JSONEncode({ok=true,houses=res})
