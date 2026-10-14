-- Geometry-only Edit probe of existing house approach; no mutating Instances.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before house route probe")
local structures=assert(workspace.Map:FindFirstChild("Structures"))
local results={}
for _,name in ipairs({"House_01","House_02"}) do
 local h=assert(structures:FindFirstChild(name))
 local floor=assert(h:FindFirstChild("Floor"))
 local roof=assert(h:FindFirstChild("Roof"))
 local porch=assert(h:FindFirstChild("PorchRoof"))
 local door=assert(h:FindFirstChild("EastPier_-13")).Position.X
 local z=floor.Position.Z
 local side=z+(roof.Size.Z/2+5)
 local west=floor.Position.X-floor.Size.X/2-6
 local exit=porch.Position.X+porch.Size.X/2+1.5+1+6
 local legs={
  {"roof-to-open",floor.Position.X,29,z,exit,29,z},
  {"open-to-porch",exit,4,z,door+6,4,z},
  {"porch-to-interior",door+6,4,z,door-8,4,z},
  {"west-flank",west,4,z,west,4,side},
  {"side-to-open",west,4,side,exit,4,side},
  {"side-to-entrance",exit,4,side,exit,4,z},
 }
 local rays={}
 for _,p in ipairs(legs) do
  local hit=workspace:Raycast(Vector3.new(p[2],p[3],p[4]),Vector3.new(p[5]-p[2],p[6]-p[3],p[7]-p[4]))
  rays[#rays+1]={name=p[1],hit=hit and hit.Instance:GetFullName() or "clear"}
 end
 local descend=workspace:Raycast(Vector3.new(exit,29,z),Vector3.new(0,-17,0))
 results[name]={door=door,z=z,exteriorX=exit,westX=west,sideZ=side,legs=rays,
  verticalDescent=descend and descend.Instance:GetFullName() or "clear"}
end
return game:GetService("HttpService"):JSONEncode({ok=true,houses=results})
