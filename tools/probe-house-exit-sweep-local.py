#!/usr/bin/env python3
"""Read-only Vitriol/Edit preflight of local HouseAccess Source on actual map.

Uses the legacy Studio bridge ONLY for Edit geometry; NEVER claims Play.
Credentials are read from BRIDGE_URL/BRIDGE_TOKEN by studio_bridge, not saved.
"""
import json
from pathlib import Path
from studio_bridge import request

source = Path("code/ServerStorage/Vitriol/Creature/HouseAccess.luau").read_text()
assert "]==]" not in source
code = r'''assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local make,err=loadstring([==[__SOURCE__]==]);assert(make,err or "local HouseAccess will not compile")
local access=assert(make().new(workspace.Map))
local navSrc=game:GetService("ServerStorage").Vitriol.Creature.GarageNavigation.Source
local navMake=assert(loadstring(navSrc))
local physical=assert(navMake().new(workspace.Map,workspace))
local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local nav={calls=0,clear=function(self,...)
 self.calls+=1;return physical:clear(...)
end}
local markers=workspace.Map.Interactions.HouseCoverTargets
local tablePart=workspace.Map.Interiors.House_01_Table
local closetPart=workspace.Map.Interiors.House_01_Closet
local tablePiece={House="House_01",Placed=true,Part=tablePart,Width=tablePart.Size.X,
 Target=markers.House_01_TableTarget}
local closetPiece={House="House_01",Placed=false,Part=closetPart,Width=closetPart.Size.X,
 Target=markers.House_01_ClosetTarget}
local cover={Pieces={tablePiece,closetPiece},activeCount=1}
local c={X=-91,Y=8,Z=77,Stats={CoreRadius=1.5},RaycastParams=params}
local x,_,z,why=access:sweepExit(c,1,nav,cover)
assert(x==-67 and z==77 and why=="physical-house-exit" and nav.calls==1,
 "real authored east door ray not open after closet dislodgement")
local high={X=-91,Y=14,Z=77,Stats={CoreRadius=1.5},RaycastParams=params}
local beforeLower=nav.calls
local highX,highY,highZ,highStatus=access:sweepExit(high,1,nav,cover)
assert(highX==high.X and highZ==high.Z and highY<10 and
 highStatus=="physical-house-exit-lowering" and nav.calls==beforeLower,
 "elevated indoor Braid must command downward, not outward, BEFORE raycasting")
high.Y=9.2
highX,highY,highZ,highStatus=access:sweepExit(high,1.2,nav,cover)
assert(highX==x and highZ==z and highStatus=="physical-house-exit"
 and nav.calls==beforeLower+1,"lowered core must pass through real door")
-- The actual piers have one-stud X depth. At (-84,64) the +pi/8
-- centerline crosses X=-79 at Z=66.07, but at expanded X=-81 the
-- 1.5-stud core would clip the south pier. Do NOT spend a thin ray on it.
local corner={X=-84,Y=8,Z=64,Stats={CoreRadius=1.5},RaycastParams=params}
local beforeCorner=nav.calls
local _,_,_,c1=access:sweepExit(corner,4,nav,nil)
local cx,_,_,c2=access:sweepExit(corner,4.2,nav,nil)
assert(c1=="scanning" and cx==nil and c2=="scanning"
 and nav.calls==beforeCorner,"angled pier-corner spoke was not rejected before ray")
local tableEdge={X=-90,Y=8,Z=71,Stats={CoreRadius=1.5},RaycastParams=params}
local beforeTable=nav.calls
local _,_,_,t1=access:sweepExit(tableEdge,5,nav,cover)
local tableX,_,_,t2=access:sweepExit(tableEdge,5.2,nav,cover)
assert(t1=="scanning" and tableX==nil and t2=="scanning" and nav.calls==beforeTable,
 "angled original table corner was not rejected before ray")
access:resetExitSweep(c)
closetPiece.Placed=true;cover.activeCount=2
local denied=false
for i=1,19 do
 local old=nav.calls
 local gx,_,gz,status=access:sweepExit(c,i+1,nav,cover)
 assert(gx==nil and gz==nil and nav.calls-old<=1,"enclosed full-body gap granted a route")
 if status=="blocked" then denied=true;break end
end
assert(denied,"both full-sized installed pieces must fail closed")
closetPiece.Placed=false;cover.activeCount=1
local atEdge={X=-90,Y=8,Z=65,Stats={CoreRadius=1.5},RaycastParams=params}
local stageX,stageZ=nil,nil
for i=1,18 do
 local old=nav.calls
 local sx,_,sz,status=access:sweepExit(atEdge,i+40,nav,cover)
 assert(nav.calls-old<=1,"new ray count exceeded one per Think")
 if status=="physical-house-exit-stage" then stageX,stageZ=sx,sz;break end
end
assert(stageX==-87 and stageZ==77,"real corner did not stage inside toward open closet lane")
return game:GetService("HttpService"):JSONEncode({ok=true,editOnly=true,
 door={access.Houses[1].DoorX,access.Houses[1].DoorZ},
 actualOpening={access.Houses[1].DoorMinZ,access.Houses[1].DoorMaxZ},
 openGoal={x,z},fullCoverDenied=denied,insideStage={stageX,stageZ},
 cornerRejectedBeforeRay=true,tableCornerRejectedBeforeRay=true,
 testedPhysicalRays=nav.calls,realFurnitureMutated=false})'''.replace("__SOURCE__", source)
result = request("/api/jobs", {"type": "run_luau", "payload": {"code": code},
                              "note": "Read-only local House exit sweep real Edit geometry", "wait": 90})
Path("tools/reports/house-exit-sweep-local-edit.json").write_text(json.dumps(result, indent=2))
print(result.get("status"), result.get("error"), result.get("result", {}).get("returned"))
assert result.get("status") == "done" and json.loads(result["result"]["returned"])["ok"]
