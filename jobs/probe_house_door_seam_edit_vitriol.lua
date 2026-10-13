-- READ ONLY Vitriol/Edit: both actual authored pier/seam widths and one
-- ground-height physical ray per open original closet lane. No Studio write,
-- placement, Play state, runtime Instances, or claim the LOCAL service is synced.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local source=game:GetService("ServerStorage").Vitriol.Creature.HouseAccess
local navSource=game:GetService("ServerStorage").Vitriol.Creature.GarageNavigation
assert(source:IsA("ModuleScript") and navSource:IsA("ModuleScript"),"authored ModuleScripts missing")
local make,err=loadstring(source.Source);assert(make,err or "HouseAccess Source failed compile")
local makeNav,navErr=loadstring(navSource.Source);assert(makeNav,navErr or "Navigation Source failed compile")
local access=assert(make().new(workspace.Map))
local physical=assert(makeNav().new(workspace.Map,workspace))
local rayParams=RaycastParams.new()
rayParams.FilterType=Enum.RaycastFilterType.Exclude
rayParams.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local interiors=workspace.Map.Interiors
local markers=workspace.Map.Interactions.HouseCoverTargets
local rows={}
for _,spec in ipairs({{"House_01",77},{"House_02",67}}) do
    local name,lane=spec[1],spec[2]
    local h=nil
    for _,entry in ipairs(access.Houses) do if entry.Name==name then h=entry;break end end
    assert(h,name.." missing from actual Studio HouseAccess")
    local tablePart=assert(interiors:FindFirstChild(name.."_Table"))
    local closetPart=assert(interiors:FindFirstChild(name.."_Closet"))
    local tableMarker=assert(markers:FindFirstChild(name.."_TableTarget"))
    local closetMarker=assert(markers:FindFirstChild(name.."_ClosetTarget"))
    assert(math.abs(closetMarker.Position.Z-lane)<0.01 and tablePart:IsA("BasePart")
      and closetPart:IsA("BasePart"),"original furniture lane changed: "..name)
    local radius=1.5
    local low=h.DoorMinZ+radius+0.5
    local high=h.DoorMaxZ-radius-0.5
    local lowerY=math.min(h.LintelBottom,h.PorchBottom)-radius-1.5
    local safeTableZ=math.abs(lane-tableMarker.Position.Z)>tablePart.Size.X*0.5+radius
    assert(lane>=low and lane<=high and lowerY>h.FloorTop+radius
      and safeTableZ,"no safe lower-first full-core clearance: "..name)
    local cover={Pieces={{House=name,Placed=true,Width=tablePart.Size.X,
        Part=tablePart,Target=tableMarker},{House=name,Placed=false,
        Width=closetPart.Size.X,Part=closetPart,Target=closetMarker}},activeCount=1}
    local counted={calls=0,clear=function(self,...)
        self.calls+=1
        return physical:clear(...)
    end}
    local creature={X=h.DoorX-12,Y=lowerY+0.1,Z=lane,
      Stats={CoreRadius=radius},RaycastParams=rayParams}
    local gx,gy,gz,status=access:sweepExit(creature,1,counted,cover)
    assert(status=="physical-house-exit" and gx>h.DoorX+6 and gz==lane
      and gy<=lowerY+0.1 and counted.calls==1,"actual open lane ray failed: "..name)
    local seamX=h.DoorX+0.6
    local complete=h.PierEastX+radius+0.5
    assert(access:groundHouse(seamX,lowerY,lane)==nil and seamX<complete,
      "no core-overlap seam at the authored east pier: "..name)
    assert(physical:clear(seamX,lane,gx,gz,rayParams),
      "outward physical ray from narrow seam blocked: "..name)
    -- Ray straight down from the low core at the indoor face, center seam,
    -- full-radius clear point and outward target. This measures actual Edit
    -- support rather than inventing a continuous fixture floor outside.
    local supports={}
    for _,px in ipairs({h.DoorX-0.7,seamX,complete+0.1,gx}) do
        local hit=workspace:Raycast(Vector3.new(px,9,lane),Vector3.new(0,-40,0),rayParams)
        supports[#supports+1]={x=px,hitY=hit and hit.Position.Y or nil,
          distance=hit and 9-hit.Position.Y or nil,
          surface=hit and hit.Instance:GetFullName() or nil}
    end
    local porch=assert(workspace.Map.Structures[name]:FindFirstChild("Porch"))
    assert(porch:IsA("BasePart"),"original ground porch missing: "..name)
    rows[#rows+1]={name=name,doorX=h.DoorX,openClosetLaneZ=lane,
      doorBodyCenterZ={low,high},lowerY=lowerY,actualGoal={gx,gy,gz},
      centerOutsideGroundHouseX=seamX,fullCoreClearEastOfX=complete,
      extraCandidateRaysAtSeam=0,authorFurnitureMoved=false,
      physicalRayFromIndoorAndSeamClear=true,downwardSupportFromCoreY9=supports,
      floor={h.Floor.Position.X,h.Floor.Position.Y,h.Floor.Size.X,h.Floor.Size.Y,h.Floor.Size.Z},
      porch={porch.Position.X,porch.Position.Y,porch.Size.X,porch.Size.Y,porch.Size.Z},
      porchRoof={h.Porch.Position.X,h.Porch.Position.Y,h.Porch.Size.X,h.Porch.Size.Y,h.Porch.Size.Z}}
end
return game:GetService("HttpService"):JSONEncode({ok=true,editOnly=true,
   studioSource=source:GetFullName(),houses=rows,geometryOrSourceWritten=false,
   localCreatureServiceSyncClaim=false,livePlayClaim=false})
