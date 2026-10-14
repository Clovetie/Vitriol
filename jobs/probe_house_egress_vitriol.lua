-- Read-only reconstruction of user's two LastKnown stall lines against authored markers.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play before house egress probe")
local map=assert(workspace:FindFirstChild("Map"))
local house=assert(map.Structures:FindFirstChild("House_01"))
local floor=assert(house:FindFirstChild("Floor"))
local marker=assert(map.Interactions.HouseCoverTargets:FindFirstChild("House_01_ClosetTarget"))
local closet=assert(map.Interiors:FindFirstChild("House_01_Closet"))
local logs={{-91.7,79.4,-57.5,78.9},{-90.9,78.3,-63.9,77.9}}
local rows={}
for _,p in ipairs(logs) do
 local x,z,tx,tz=p[1],p[2],p[3],p[4]
 local plane=marker.Position.X
 local t=(plane-x)/(tx-x)
 local at=z+(tz-z)*t
 local inside=x<plane and x>floor.Position.X-floor.Size.X*0.5 and math.abs(z-floor.Position.Z)<floor.Size.Z*0.5
 local crosses=t>0 and t<1 and math.abs(at-marker.Position.Z)<=closet.Size.X*0.5
 rows[#rows+1]={coreInside=inside,footprintCrossesCloset=crosses,crossingZ=at,doorPlane=plane,closetCenterZ=marker.Position.Z,coreDistance=math.abs(x-plane)}
 assert(inside and crosses and math.abs(x-plane)<12,"Stall is NOT a nearby reverse closet encounter")
end
return game:GetService("HttpService"):JSONEncode({ok=true,rows=rows})
