-- READ ONLY Vitriol/Edit: target-lever endpoint ray with lever excluded,
-- adjacent Braid-radius lanes and ground support. No geometry/Source writes.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local map=workspace.Map
local lever=assert(map.Interactions:FindFirstChild("Church_BellLever"))
local body=assert(map.Structures.Church_BellTower:FindFirstChild("Body"))
local braid=assert(workspace.Vitriol.Creatures:FindFirstChild("Braid_1"))
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={braid,lever}
local frontX,frontZ=119,-130.25
local targetZ=lever.Position.Z
local function horizontal(ax,az,bx,bz,y)
 local origin=Vector3.new(ax,y,az)
 local hit=workspace:Raycast(origin,Vector3.new(bx,y,bz)-origin,params)
 return hit and {path=hit.Instance:GetFullName(),point={hit.Position.X,hit.Position.Y,hit.Position.Z}}
   or {path="clear"}
end
local offsets={-2,-1.5,-1,0,1,1.5,2}
local rays={}
local corridorClear=true
for _,offset in ipairs(offsets) do
 local lower=horizontal(frontX+offset,frontZ,lever.Position.X+offset,targetZ,4)
 local upper=horizontal(frontX+offset,frontZ,lever.Position.X+offset,targetZ,9)
 if lower.path~="clear" or upper.path~="clear" then corridorClear=false end
 rays[#rays+1]={offsetX=offset,atY4=lower,atY9=upper}
end
local support={}
for _,z in ipairs({frontZ,-190,targetZ-2,targetZ,targetZ+2,-210}) do
 local down=workspace:Raycast(Vector3.new(119,9,z),Vector3.new(0,-40,0),params)
 support[#support+1]={z=z,ground=down and down.Instance:GetFullName() or "none",
   topY=down and down.Position.Y or nil}
end
local targetSupport=support[4]
local supported=targetSupport and targetSupport.ground==map.Structures.Church_BellTower.NaveFloor:GetFullName()
return game:GetService("HttpService"):JSONEncode({ok=corridorClear and supported or false,
 editOnly=true,sevenOffsetRaysAtTwoHeightsClear=corridorClear,targetOnOriginalNaveFloor=supported,
 currentLever={lever.Position.X,lever.Position.Y,targetZ},
 previousApprovedLever={119,2.5,-210},body={body:GetFullName(),body.CanCollide,body.CanQuery},
 entrance={frontX,frontZ},leverExcludedBodyWidthRayCandidates=rays,
 downwardSupport=support,sourceOrGeometryWritten=false,noPlayClaim=true})
