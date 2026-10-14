-- READ ONLY Vitriol/Edit: sample existing HouseAccess Source on real authored
-- floor/door geometry with HYPOTHETICAL furniture flags in Lua-only tables.
-- This is not Play, not foot simulation, and makes NO Studio Instance/write.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local modules=game:GetService("ServerStorage").Vitriol.Creature
local accessSource=assert(modules:FindFirstChild("HouseAccess"))
local garageSource=assert(modules:FindFirstChild("GarageNavigation"))
assert(accessSource:IsA("ModuleScript") and garageSource:IsA("ModuleScript"),"Module class changed")
local access=assert(assert(loadstring(accessSource.Source))().new(workspace.Map))
local physical=assert(assert(loadstring(garageSource.Source))().new(workspace.Map,workspace))
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local nav={calls=0,clear=function(self,...)
 self.calls+=1
 return physical:clear(...)
end}
local interiors=workspace.Map.Interiors
local markers=workspace.Map.Interactions.HouseCoverTargets
local function coverFor(name,tablePlaced,closetPlaced)
 local pieces={}
 for _,kind in ipairs({"Table","Closet"}) do
  local part=assert(interiors:FindFirstChild(name.."_"..kind))
  local marker=assert(markers:FindFirstChild(name.."_"..kind.."Target"))
  assert(part:IsA("BasePart") and marker:IsA("BasePart"),"authored furniture missing")
  pieces[#pieces+1]={House=name,Placed=kind=="Table" and tablePlaced or closetPlaced,
   Part=part,Width=part.Size.X,Target=marker}
 end
 return {Pieces=pieces,activeCount=(tablePlaced and 1 or 0)+(closetPlaced and 1 or 0)}
end
local patterns={{name="none",table=false,closet=false},
 {name="table",table=true,closet=false},
 {name="closet",table=false,closet=true},
 {name="both",table=true,closet=true}}
local cases={}
local totals={}
local bounded=true
for _,h in ipairs(access.Houses) do
 local floor=h.Floor
 local x0,z0=floor.Position.X,floor.Position.Z
 totals[h.Name]={}
 for _,scenario in ipairs(patterns) do
  local count={exit=0,stage=0,blocked=0,other=0,stageThenExit=0,stageNotResolved=0}
  totals[h.Name][scenario.name]=count
  for _,dx in ipairs({-12,0,12}) do
   for _,dz in ipairs({-12,-6,0,6,12}) do
    local c={X=x0+dx,Y=8,Z=z0+dz,Stats={CoreRadius=1.5},RaycastParams=params}
    assert(access:groundHouse(c.X,c.Y,c.Z)==h,"grid seed not grounded inside this house")
    local cover=coverFor(h.Name,scenario.table,scenario.closet)
    local start=nav.calls
    local status="other"
    local goal=nil
    for think=1,19 do
     local old=nav.calls
     local x,_,z,why=access:sweepExit(c,think*0.2,nav,cover)
     if nav.calls-old>1 then bounded=false end
     if x then
      status=why=="physical-house-exit-stage" and "stage" or "exit"
      goal={x,z}
      break
     elseif why=="blocked" then status="blocked";break end
    end
    local seed={c.X,c.Z}
    local stageFollow=nil
    if status=="stage" then
     -- An IDEALIZED arrival at the already ray-tested indoor stage. The
     -- Braid is not animated here; this only checks the next real-map ray.
     c.TargetX,c.TargetZ=goal[1],goal[2]
     c.X,c.Z=goal[1],goal[2]
     stageFollow="unresolved"
     for think=20,38 do
      local old=nav.calls
      local x,_,z,why=access:sweepExit(c,think*0.2,nav,cover)
      if nav.calls-old>1 then bounded=false end
      if x then stageFollow=why=="physical-house-exit" and "exit" or "stage";break end
      if why=="blocked" then stageFollow="blocked";break end
     end
     if stageFollow=="exit" then count.stageThenExit+=1
     else count.stageNotResolved+=1 end
    end
    count[status]+=1
    cases[#cases+1]={house=h.Name,scenario=scenario.name,seed=seed,
     result=status,goal=goal,stageFollow=stageFollow,rays=nav.calls-start}
   end
  end
 end
end
local profile=true
for _,counts in pairs(totals) do
 profile=profile and counts.none.exit==15 and counts.none.stage==0
  and counts.table.exit==4 and counts.table.stage==11
  and counts.table.stageThenExit==11 and counts.table.stageNotResolved==0
  and counts.closet.blocked==15 and counts.both.blocked==15
end
return game:GetService("HttpService"):JSONEncode({ok=bounded and profile and #cases==120,
 editOnly=true,installedSource=accessSource:GetFullName(),
 outcomes=totals,cases=cases,expectedAuthorMapProfile=profile,
 maxOneNewCandidateRayPerThink=bounded,
 syntheticFurnitureFlagsOnly=true,studioWritten=false,playCaptured=false,
 caveat="ray/waypoint preflight only; does not advance a planted-foot Braid"})
