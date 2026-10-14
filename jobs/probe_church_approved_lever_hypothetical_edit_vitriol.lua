-- READ ONLY Vitriol/Edit: test the PREVIOUSLY approved lever coordinate as a
-- HYPOTHETICAL endpoint. The real lever remains at its current Z=-199.
-- Excluding that exact Part from a ray is NOT equivalent to moving it in Play.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local map=assert(workspace:FindFirstChild("Map"))
local lever=assert(map.Interactions:FindFirstChild("Church_BellLever"))
local floor=assert(map.Structures.Church_BellTower:FindFirstChild("NaveFloor"))
local braid=assert(workspace.Vitriol.Creatures:FindFirstChild("Braid_1"))
assert(lever:IsA("BasePart") and floor:IsA("BasePart") and math.abs(lever.Position.X-119)<.01
 and math.abs(lever.Position.Y-2.5)<.01 and math.abs(lever.Position.Z+199)<.01,
 "actual authored lever changed: abort -199 hypothetical comparison")
local startX,startZ,targetX,targetZ=119,-130.25,119,-210
local function params(excludeLever)
 local p=RaycastParams.new()
 p.FilterType=Enum.RaycastFilterType.Exclude
 p.FilterDescendantsInstances=excludeLever and {braid,lever} or {braid}
 return p
end
local raw,filtered=params(false),params(true)
local function result(hit)
 return hit and {path=hit.Instance:GetFullName(),point={hit.Position.X,hit.Position.Y,hit.Position.Z}}
   or {path="clear"}
end
local function horizontal(ax,az,bx,bz,y,p)
 local a,b=Vector3.new(ax,y,az),Vector3.new(bx,y,bz)
 return result(workspace:Raycast(a,b-a,p))
end
local rawEndpoint=horizontal(startX,startZ,targetX,targetZ,4,raw)
local filteredHit=workspace:Raycast(Vector3.new(startX,4,startZ),
 Vector3.new(targetX-startX,0,targetZ-startZ),filtered)
local source=game:GetService("ServerStorage").Vitriol.Creature.ChurchNavigation
assert(source:IsA("ModuleScript"),"installed church Source missing")
local make,err=loadstring(source.Source)
assert(make,err or "installed church Source failed compile")
local nav=assert(make().new(map,workspace))
local bellModel=assert(map.Interactions.Bell:FindFirstChild("Bell"))
local routeX,routeZ=nav:route(startX,startZ,targetX,targetZ,filtered,bellModel)
local offsets={-2,-1.5,-1,0,1,1.5,2}
local rays={}
local clear=true
for _,offset in ipairs(offsets) do
 local low=horizontal(startX+offset,startZ,targetX+offset,targetZ,4,filtered)
 local high=horizontal(startX+offset,startZ,targetX+offset,targetZ,9,filtered)
 if low.path~="clear" or high.path~="clear" then clear=false end
 rays[#rays+1]={offsetX=offset,atY4=low,atY9=high}
end
local support={}
local targetSupported=false
for _,z in ipairs({startZ,-190,-199,-203,-207,targetZ}) do
 local hit=workspace:Raycast(Vector3.new(targetX,9,z),Vector3.new(0,-40,0),filtered)
 support[#support+1]={z=z,ground=hit and hit.Instance:GetFullName() or "none",
  topY=hit and hit.Position.Y or nil}
 if z==targetZ then targetSupported=hit and hit.Instance==floor or false end
end
return game:GetService("HttpService"):JSONEncode({ok=clear and targetSupported,
 editOnly=true,actualLever={lever.Position.X,lever.Position.Y,lever.Position.Z},
 hypotheticalApprovedTarget={targetX,2.5,targetZ},
 originalRayAtY4=rawEndpoint,leverExcluded=true,all14HypotheticalRaysClear=clear,
 firstNonLeverHit=filteredHit and filteredHit.Instance:GetFullName() or "clear",
 firstNonLeverHitCollides=filteredHit and filteredHit.Instance.CanCollide or false,
 installedSourceHypotheticalWaypoint=routeX and {routeX,routeZ} or nil,
 policyReturnsTargetDespiteCollidableBell=(routeX==targetX and routeZ==targetZ
  and filteredHit and filteredHit.Instance:IsDescendantOf(bellModel)
  and filteredHit.Instance.CanCollide) or false,
 targetOnOriginalNaveFloor=targetSupported,
 rays=rays,downwardSupport=support,
 sourceOrGeometryWritten=false,noLeverMove=true,noPlayClaim=true})
