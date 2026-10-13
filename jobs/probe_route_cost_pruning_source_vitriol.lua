-- Vitriol/Edit READ ONLY. Differential old exhaustive route against the
-- currently authored Studio Source on actual Garage geometry and lure parts.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local navSrc=game:GetService("ServerStorage").Vitriol.Creature.GarageNavigation
assert(navSrc:IsA("ModuleScript"),"navigation class drift")
local factory,err=loadstring(navSrc.Source)
assert(factory,err or "Studio navigation Source will not compile")
local nav=assert(factory().new(workspace.Map,workspace),"authored garage unavailable")
local p=RaycastParams.new()
p.FilterType=Enum.RaycastFilterType.Exclude
p.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local function dist(ax,az,bx,bz)
 local dx,dz=bx-ax,bz-az
 return math.sqrt(dx*dx+dz*dz)
end
local function original(cx,cz,tx,tz,endpoint)
 local obstacle=nav:hit(cx,cz,tx,tz,p)
 if obstacle==nil then return tx,tz end
 local part=obstacle.Instance
 local garageProp=part and nav.Interiors and part.Parent==nav.Interiors
  and string.sub(part.Name,1,7)=="Garage_"
 if not (part and (part:IsDescendantOf(nav.Garage) or garageProp)) then return tx,tz end
 local from,to={},{}
 for i=1,6 do
  local node=nav.Nodes[i]
  from[i]=nav:routeClear(cx,cz,node[1],node[2],p)
  to[i]=nav:routeClear(node[1],node[2],tx,tz,p,endpoint)
 end
 local best,chosen=math.huge,nil
 for i=1,6 do
  if from[i] then
   for j=1,6 do
    if to[j] then
     local cost=dist(cx,cz,nav.Nodes[i][1],nav.Nodes[i][2])
      +nav.Cost[i][j]+dist(nav.Nodes[j][1],nav.Nodes[j][2],tx,tz)
     if cost<best then
      best=cost
      chosen=dist(cx,cz,nav.Nodes[i][1],nav.Nodes[i][2])<=4
       and (nav.Next[i][j] or j) or i
     end
    end
   end
  end
 end
 return chosen and nav.Nodes[chosen][1] or nil,
  chosen and nav.Nodes[chosen][2] or nil
end
local generator=workspace.Map.Interactions:FindFirstChild("Garage_Generator")
assert(generator,"authored generator missing")
local cases={
 {-90,-56,-145,-56}, {-55,-56,-145,-56}, {-55,-86,-145,-56},
 {-125,-86,-145,-56}, {-86.1,-71.4,-88,-125},
 {45.5,-137.4,-112,-60,generator},
 {-90,-56,-55,-56}, {-125,-26,-90,-56},
}
local routeSamples={}
for i,c in ipairs(cases) do
 local ox,oz=original(c[1],c[2],c[3],c[4],c[5])
 nav.Cache=nil
 local x,z=nav:route(c[1],c[2],c[3],c[4],p,i,c[5])
 assert(ox==x and oz==z,"real Garage waypoint drift in case "..i)
 routeSamples[i]={x,z}
end
assert(routeSamples[1][1]==-55 and routeSamples[1][2]==-56,
 "real Garage barrel case no longer chooses original front detour")
local hit=nav:hit(-90,-56,-145,-56,p)
assert(hit and hit.Instance,"physical garage rear ray missing")
nav.Cache=nil
local knownX,knownZ=nav:route(-90,-56,-145,-56,p,15,nil,hit)
assert(knownX==routeSamples[1][1] and knownZ==routeSamples[1][2],
 "known measured obstruction changed the real front waypoint")
return game:GetService("HttpService"):JSONEncode({ok=true,editOnly=true,
 source=navSrc:GetFullName(),cases=#cases,firstBlocker=hit.Instance:GetFullName(),
 front={knownX,knownZ},exactWaypointParity=true})
