assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Wrong place/mode")
local i=workspace.Map.Interactions
local rows={}
for _,name in ipairs({"Garage_Generator","Garage_GeneratorLamp","Station_FloodlightSwitch","Station_Floodlight"}) do
 local p=i:FindFirstChild(name)
 local children={}
 if p then for _,child in ipairs(p:GetChildren()) do
  children[#children+1]={name=child.Name,class=child.ClassName}
 end end
 rows[name]={class=p and p.ClassName or nil,position=p and tostring(p.Position) or nil,children=children}
end
return game:GetService("HttpService"):JSONEncode(rows)
