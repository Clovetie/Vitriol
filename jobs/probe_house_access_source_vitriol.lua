-- Read-only compiled Studio module plus actual authored two-house geometry.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before source/geometry probe")
local source=game:GetService("ServerStorage").Vitriol.Creature.HouseAccess
assert(source:IsA("ModuleScript"),"HouseAccess wrong class")
local fresh,compileError=loadstring(source.Source)
assert(fresh,compileError or "Fresh HouseAccess compilation failed")
local nav=assert(fresh().new(workspace.Map),"Live house geometry incomplete")
local rows={}
for _,h in ipairs(nav.Houses) do
 local door,z=h.DoorX,h.DoorZ
 assert(nav:houseForPrey(door-1,2,z)==h,h.Name.." near-inside-door prey")
 local cap=nav:heightCap(door+5,9,z,1.5)
 assert(math.abs(cap-10)<.05,h.Name.." entry clearance")
 local roof,ex,ey,ez=nav:escape(door-10,29,z,1.5)
 assert(roof==h and math.abs(ex-(door+25))<.05 and ey==29,h.Name.." roof exit")
 local outside,_,downY,downZ=nav:escape(ex,29,z,1.5)
 assert(outside==h and downY<9 and downZ==z,h.Name.." open-sky descent")
 local approach,approachY,approachZ=nav:route(ex,9,z,door-12,2,z,1.5)
 assert(approach==door+6 and approachY>=8 and approachZ==z,h.Name.." entry approach")
 local entry,entryY,entryZ=nav:route(door+6,9,z,door-12,2,z,1.5)
 assert(entry==door-8 and entryY>=8 and entryZ==z,h.Name.." interior doorway")
 assert(nav:roofOccludes(door-10,29,z,door-12,2,z),h.Name.." roof sight shielding")
 rows[#rows+1]={name=h.Name,clearance=cap,roofExit=ex,descentY=downY,porch=approach,inside=entry}
end
return game:GetService("HttpService"):JSONEncode({ok=true,houses=rows})
