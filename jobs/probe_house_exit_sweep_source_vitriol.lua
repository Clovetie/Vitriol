-- READ ONLY Vitriol/Edit: fresh actual Studio Sources + actual authored door.
-- No live Play claim, no Part relocation, no new Instances.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local src=game:GetService("ServerStorage").Vitriol
local accessSource=src.Creature.HouseAccess
local coreSource=src.Creature.CreatureCore
local serviceSource=src.Services.CreatureService
assert(accessSource:IsA("ModuleScript") and coreSource:IsA("ModuleScript")
 and serviceSource:IsA("ModuleScript"),"ModuleScript class drift")
local make,err=loadstring(accessSource.Source);assert(make,err or "HouseAccess Source compile")
assert(loadstring(coreSource.Source),"CreatureCore Source compile")
assert(loadstring(serviceSource.Source),"CreatureService Source compile")
assert(string.find(coreSource.Source,"self.Locomotion:setCrouch(self.ExitSweepCrouch)",1,true),
 "actual Studio core lacks the idle supported doorway descent")
assert(string.find(serviceSource.Source,"access:sweepExit(creature,now,self.Navigation,self.HouseCover)",1,true)
 and string.find(serviceSource.Source,"creature.SearchMode==\"transit\"",1,true),
 "service does not restrict radial sweep to clue-less region transit")
local access=assert(make().new(workspace.Map))
local makeNav=assert(loadstring(src.Creature.GarageNavigation.Source))
local physical=assert(makeNav().new(workspace.Map,workspace))
local p=RaycastParams.new();p.FilterType=Enum.RaycastFilterType.Exclude
p.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local nav={calls=0,clear=function(self,...)
 self.calls+=1;return physical:clear(...)
end}
local pieces=workspace.Map.Interiors
local markers=workspace.Map.Interactions.HouseCoverTargets
local tablePiece={House="House_01",Placed=true,Part=pieces.House_01_Table,
 Width=pieces.House_01_Table.Size.X,Target=markers.House_01_TableTarget}
local closetPiece={House="House_01",Placed=false,Part=pieces.House_01_Closet,
 Width=pieces.House_01_Closet.Size.X,Target=markers.House_01_ClosetTarget}
local cover={Pieces={tablePiece,closetPiece},activeCount=1}
local c={X=-91,Y=8,Z=77,Stats={CoreRadius=1.5},RaycastParams=p}
local x,_,z,why=access:sweepExit(c,1,nav,cover)
assert(x==-67 and z==77 and why=="physical-house-exit" and nav.calls==1,
 "fresh Studio Source failed actual open-closet doorway ray")
local high={X=-91,Y=14,Z=77,Stats={CoreRadius=1.5},RaycastParams=p}
local beforeLower=nav.calls
local highX,highY,highZ,highStatus=access:sweepExit(high,1,nav,cover)
assert(highX==high.X and highZ==high.Z and highY<10
 and highStatus=="physical-house-exit-lowering" and nav.calls==beforeLower,
 "raised indoor core must lower here, not target outside while above lintel")
high.Y=9.2
highX,highY,highZ,highStatus=access:sweepExit(high,1.2,nav,cover)
assert(highX==x and highZ==z and highStatus=="physical-house-exit"
 and nav.calls==beforeLower+1,"lowered core failed actual door ray")
-- One-stud-deep authored pier; angled centerline passes door PLANE but
-- radius 1.5 would clip the expanded west face of the south pier.
local corner={X=-84,Y=8,Z=64,Stats={CoreRadius=1.5},RaycastParams=p}
local beforeCorner=nav.calls
local _,_,_,c1=access:sweepExit(corner,4,nav,nil)
local cx,_,_,c2=access:sweepExit(corner,4.2,nav,nil)
assert(c1=="scanning" and cx==nil and c2=="scanning"
 and nav.calls==beforeCorner,"angled pier corner was not rejected before ray")
local tableEdge={X=-90,Y=8,Z=71,Stats={CoreRadius=1.5},RaycastParams=p}
local beforeTable=nav.calls
local _,_,_,t1=access:sweepExit(tableEdge,5,nav,cover)
local tableX,_,_,t2=access:sweepExit(tableEdge,5.2,nav,cover)
assert(t1=="scanning" and tableX==nil and t2=="scanning" and nav.calls==beforeTable,
 "angled original table corner was not rejected before ray")
access:resetExitSweep(c)
closetPiece.Placed=true;cover.activeCount=2
local denied=false
for i=1,19 do
 local rays=nav.calls
 local gx,_,gz,status=access:sweepExit(c,i+1,nav,cover)
 assert(gx==nil and gz==nil and nav.calls-rays<=1,"installed furniture granted a full-body route")
 if status=="blocked" then denied=true;break end
end
assert(denied,"two real-sized furniture footprints leave no Braid-sized gap")
closetPiece.Placed=false;cover.activeCount=1
local edge={X=-90,Y=8,Z=65,Stats={CoreRadius=1.5},RaycastParams=p}
local sx,sz=nil,nil
for i=1,18 do
 local rays=nav.calls
 local wx,_,wz,status=access:sweepExit(edge,i+40,nav,cover)
 assert(nav.calls-rays<=1,"more than one radial ray in one Think")
 if status=="physical-house-exit-stage" then sx,sz=wx,wz;break end
end
assert(sx==-87 and sz==77,"real-map corner did not stage to open lane")
return game:GetService("HttpService"):JSONEncode({ok=true,editOnly=true,
 source=accessSource:GetFullName(),service=serviceSource:GetFullName(),
 openGoal={x,z},fullyCoveredFailsClosed=denied,stagedCorner={sx,sz},
 angledPierRejectedBeforeRay=true,angledTableRejectedBeforeRay=true,
 door={access.Houses[1].DoorX,access.Houses[1].DoorZ},
 opening={access.Houses[1].DoorMinZ,access.Houses[1].DoorMaxZ},
 furnitureOrMapMutated=false,rayCount=nav.calls})
