-- Pure route policy for user-owned church union with real front opening.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1;print("PASS "..msg)
 else SESSION.failed=SESSION.failed+1;print("FAIL "..msg) end
end
local Navigation=VitriolRequire("ChurchNavigation")
local church={}
local body={Name="Body",Position={X=119,Z=-178.625},Size={X=49.5,Z=74.75}}
function body:IsA(class) return class=="BasePart" end
function body:IsDescendantOf(parent) return parent==church end
function church:FindFirstChild(name) return name=="Body" and body or nil end
local buildings={FindFirstChild=function(_,name) return name=="Church_BellTower" and church or nil end}
local lever={Position={X=119,Y=2.5,Z=-199},
 IsA=function(_,kind)return kind=="Part" or kind=="BasePart" end,
 IsDescendantOf=function()return false end}
local interactions={FindFirstChild=function(_,name)
 return name=="Church_BellLever" and lever or nil
end}
local map={FindFirstChild=function(_,name)
 if name=="Structures" then return buildings end
 if name=="Interactions" then return interactions end
 return nil
end}
local bellModel={}
local bell={Name="Bell",IsDescendantOf=function(_,parent) return parent==bellModel end}
local world={calls=0}
local windows={}
local window={IsDescendantOf=function(_,parent) return parent==windows end}
function world:FindFirstChild(name) return name=="ChurchWindows" and windows or nil end
function world:Raycast(origin,dir)
 self.calls=self.calls+1
 local destX,destZ=origin.X+dir.X,origin.Z+dir.Z
 if math.abs(destX-119)<.1 and math.abs(destZ+199)<.1 then
  if origin.X < -30 then return {Instance=window} end
  return {Instance=(math.abs(origin.X-119)<.1 and origin.Z>-141) and lever or body}
 end
 return nil
end
local nav=Navigation.new(map,world)
check(nav~=nil and math.abs(nav.Left-86.25)<.01 and math.abs(nav.Front+130.25)<.01,
 "church corridor derives from user's union bounds, not a generated door")
local x,z=nav:route(-38.4,-48.1,119,-199,nil,bellModel)
check(x==119 and z==-130.25,"distant church window obstruction routes toward clear main entrance")
x,z=nav:route(83.8,-207.5,119,-199,nil,bellModel)
check(x==86.25 and z==-130.25,"west bell stall routes beside solid wall to south/front approach")
x,z=nav:route(86.25,-141.25,119,-199,nil,bellModel)
check(x==119 and z==-130.25,"planted-foot body can turn toward door before core touches side waypoint")
x,z=nav:route(86.25,-130.25,119,-199,nil,bellModel)
check(x==119 and z==-130.25,"once beside wall turn toward real main entrance")
x,z=nav:route(119,-130.25,119,-199,nil,bellModel)
check(x==119 and z==-199,"current authored lever itself may end the clear entrance ray")
local originalRay=world.Raycast
world.Raycast=function() return {Instance=lever} end
x,z=nav:route(119,-130.25,119,-199,nil,bellModel)
check(x==119 and z==-199,
 "the EXACT preauthored target lever may terminate a clear entrance ray")
x,z=nav:route(119,-130.25,119,-210,nil,bellModel)
check(x==nil and z==nil,
 "the current lever blocks a request for the old Z=-210 target")
world.Raycast=originalRay
check(Navigation.new(nil,world)==nil,"missing church does not fabricate a path")
local original=world.Raycast
world.Raycast=function() return {Instance={IsDescendantOf=function() return false end}} end
x,z=nav:route(83.8,-207.5,119,-199,nil,bellModel)
check(x==nil and z==nil,"unrelated blocking geometry fails closed")
world.Raycast=original
return SESSION
