-- READ ONLY Vitriol/Edit: compare ACTUAL lever route with previously approved
-- coordinate as a hypothetical target. Never move lever, bell, rope or Union.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local src=game:GetService("ServerStorage").Vitriol.Creature.ChurchNavigation
assert(src:IsA("ModuleScript"),"ChurchNavigation must be existing ModuleScript")
local make,err=loadstring(src.Source)
assert(make,err or "Studio ChurchNavigation Source failed compile")
local nav=assert(make().new(workspace.Map,workspace))
local lever=assert(workspace.Map.Interactions:FindFirstChild("Church_BellLever"))
local bell=assert(workspace.Map.Interactions.Bell:FindFirstChild("Bell"))
local prompt=assert(lever:FindFirstChild("PrimeBell"))
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local function ray(ax,az,bx,bz)
    local hit=nav:hit(ax,az,bx,bz,params)
    return hit and {path=hit.Instance:GetFullName(),position={hit.Position.X,hit.Position.Y,hit.Position.Z}}
      or {path="clear"}
end
local function routeTo(z)
    local x,y=83.8,-207.5
    local legs={}
    for i=1,3 do
        local nx,nz=nav:route(x,y,119,z,params,bell)
        legs[#legs+1]={start={x,y},waypoint=nx and {nx,nz} or nil,
          directRay=ray(x,y,119,z),
          legRay=nx and ray(x,y,nx,nz) or nil}
        if nx==nil then break end
        x,y=nx,nz
    end
    return {target={119,z},legs=legs,
      reachedTarget=x==119 and y==z,
      frontToTarget=ray(nav.Middle,nav.Front,119,z)}
end
local pos,size=lever.Position,lever.Size
local actual=routeTo(pos.Z)
local approved=routeTo(-210) -- HYPOTHETICAL target only; no Studio Part moved
return game:GetService("HttpService"):JSONEncode({ok=true,editOnly=true,
  actualLever={position={pos.X,pos.Y,pos.Z},size={size.X,size.Y,size.Z},
    anchored=lever.Anchored,collides=lever.CanCollide,query=lever.CanQuery,
    promptReach=prompt.MaxActivationDistance,promptEnabled=prompt.Enabled},
  previousApprovedLever={119,2.5,-210},
  entrance={nav.Middle,nav.Front},
  actualRoute=actual,approvedCoordinateOnlyRoute=approved,
  source=src:GetFullName(),sourceOrGeometryWritten=false,
  noPlayerReachabilityClaim=true,noPlayClaim=true})
