-- Headless garage route regression: analytic authored walls, no runtime Instances.
SESSION = {passed = 0, failed = 0}
local function check(ok, message)
	if ok then SESSION.passed = SESSION.passed + 1; print("PASS  " .. message)
	else SESSION.failed = SESSION.failed + 1; print("FAIL  " .. message) end
end
local Navigation = VitriolRequire("GarageNavigation")
local garage = {}
local walls = {}
for _, name in ipairs({"RearWall", "BackNorth", "BackSouth"}) do
	walls[name] = { Name = name, IsDescendantOf = function(_, parent) return parent == garage end }
end
local floor = {Position = {X = -90, Z = -56}, Size = {X = 56, Z = 46}}
function garage:FindFirstChild(name)
	return name == "Floor" and floor or walls[name]
end
local structures = {FindFirstChild = function(_, name) return name == "Millers_Garage" and garage or nil end}
local interiors = {}
local barrel = {Name = "Garage_Barrel_2", Parent = interiors,
	IsDescendantOf = function() return false end}
local map = {FindFirstChild = function(_, name)
	if name == "Structures" then return structures end
	if name == "Interiors" then return interiors end
	return nil
end}
local workspace = {calls = 0}
local function cross(ax, az, dx, dz, fixed, minValue, maxValue, vertical)
	local delta, origin = vertical and dx or dz, vertical and ax or az
	if math.abs(delta) < 1e-8 then return nil end
	local t = (fixed - origin) / delta
	if t < 0.001 or t > 1 then return nil end
	local other = vertical and (az + dz * t) or (ax + dx * t)
	if other >= minValue and other <= maxValue then return t end
	return nil
end
function workspace:Raycast(origin, direction)
	self.calls = self.calls + 1
	local ax, az, dx, dz = origin.X, origin.Z, direction.X, direction.Z
	local rear = cross(ax, az, dx, dz, -118, -79, -33, true)
	local north = cross(ax, az, dx, dz, -79, -118, -62, false)
	local south = cross(ax, az, dx, dz, -33, -118, -62, false)
	local t, hit = nil, nil
	for _, pair in ipairs({{rear, walls.RearWall}, {north, walls.BackNorth}, {south, walls.BackSouth}}) do
		if pair[1] and (not t or pair[1] < t) then t, hit = pair[1], pair[2] end
	end
	return hit and {Instance = hit} or nil
end
local nav = Navigation.new(map, workspace)
check(nav ~= nil, "garage route uses authored floor and rear wall, not a generated Path")
check(not nav:clear(-90, -56, -145, -56, nil), "garage rear wall blocks a direct chase/chomp")
local coldBefore=workspace.calls
local x, z = nav:route(-90, -56, -145, -56, nil, 0)
check(x == -55 and z == -56, "inside Braid first seeks the open front instead of rear wall")
check(workspace.calls-coldBefore==11,
 "cold garage detour uses 11 physical rays, but real Think budget remains open")
nav.Cache=nil
local seenWall=nav:hit(-90,-56,-145,-56,nil)
local sensedBefore=workspace.calls
x,z=nav:route(-90,-56,-145,-56,nil,0,nil,seenWall)
check(x==-55 and z==-56 and workspace.calls-sensedBefore==10,
 "same-segment known hit saves the initial ray; exact-cost pruning saves two more")
nav.Cache=nil
local missingBefore=workspace.calls
x,z=nav:route(-90,-56,-145,-56,nil,0,nil,{Instance=nil})
check(x==-55 and z==-56 and workspace.calls-missingBefore==11,
 "missing hit evidence still takes the original start safety ray")
local structuralRaycast = workspace.Raycast
workspace.Raycast = function(self, origin, direction)
	if origin.X == -90 and origin.Z == -56 and direction.X < 0 then
		return {Instance = barrel} -- real Studio ray hits Barrel_2 before RearWall
	end
	return structuralRaycast(self, origin, direction)
end
nav.Cache = nil
x, z = nav:route(-90, -56, -145, -56, nil, 0)
check(x == -55 and z == -56, "garage barrel as the first hit still triggers the wall detour")
barrel.Name = "FuelPump_1"
nav.Cache = nil
x, z = nav:route(-90, -56, -145, -56, nil, 0)
check(x == -145 and z == -56, "unrelated interior cover does not trigger garage-only routing")
barrel.Name = "Garage_Barrel_2"
workspace.Raycast = structuralRaycast
nav.Cache = nil
nav:route(-90, -56, -145, -56, nil, 0)
local calls = workspace.calls
x, z = nav:route(-88, -56, -145, -56, nil, 0.2)
check(x == -55 and z == -56 and workspace.calls - calls <= 2,
	"half-second cached waypoint avoids a full ray fan on every think tick")
x, z = nav:route(-55, -56, -145, -56, nil, 1)
check(x == -55 and (z == -86 or z == -26), "at open front Braid turns toward a garage side")
x, z = nav:route(-55, -86, -145, -56, nil, 2)
check(x == -125 and z == -86, "north detour proceeds beyond the back corner")
x, z = nav:route(-125, -86, -145, -56, nil, 3)
check(x == -145 and z == -56, "after rounding the corner direct pursuit resumes")
check(nav:clear(-125, -86, -145, -56, nil), "outside path is visible at contact height")
local directX, directZ = nav:route(-55, -56, 15, -56, nil, 4)
check(directX == 15 and directZ == -56, "unobstructed prey keeps the approved direct chase")
-- Differential safety oracle: original exhaustive 6+6 physical rays and
-- strict < pair enumeration. Cache is deliberately cleared for every case.
local function exhaustive(cx,cz,tx,tz)
 local obstacle=nav:hit(cx,cz,tx,tz,nil)
 if obstacle==nil then return tx,tz end
 local part=obstacle.Instance
 local garageProp=part and nav.Interiors and part.Parent==nav.Interiors
  and string.sub(part.Name,1,7)=="Garage_"
 if not (part and (part:IsDescendantOf(nav.Garage) or garageProp)) then
  return tx,tz
 end
 local from,to={},{}
 for i=1,6 do
  from[i]=nav:routeClear(cx,cz,nav.Nodes[i][1],nav.Nodes[i][2],nil)
  to[i]=nav:routeClear(nav.Nodes[i][1],nav.Nodes[i][2],tx,tz,nil)
 end
 local best,chosen=math.huge,nil
 for i=1,6 do
  if from[i] then
   for j=1,6 do
    if to[j] then
     local cost=math.sqrt((nav.Nodes[i][1]-cx)^2+(nav.Nodes[i][2]-cz)^2)
      +nav.Cost[i][j]
      +math.sqrt((nav.Nodes[j][1]-tx)^2+(nav.Nodes[j][2]-tz)^2)
     if cost<best then
      best=cost
      local near=(nav.Nodes[i][1]-cx)^2+(nav.Nodes[i][2]-cz)^2<=16
      chosen=near and (nav.Next[i][j] or j) or i
     end
    end
   end
  end
 end
 return chosen and nav.Nodes[chosen][1] or nil,
  chosen and nav.Nodes[chosen][2] or nil
end
local mismatches,changed,worse,samples,oldRays,newRays=0,0,0,0,0,0
for _,cx in ipairs({-145,-125,-112,-90,-75,-60,-45,0}) do
 for _,cz in ipairs({-96,-86,-56,-26,-16}) do
  for _,tx in ipairs({-145,-125,-112,-90,-75,-45}) do
   for _,tz in ipairs({-86,-56,-26}) do
    local before=workspace.calls
    local bx,bz=exhaustive(cx,cz,tx,tz)
    local exhaustiveRays=workspace.calls-before
    nav.Cache=nil
    before=workspace.calls
    local rx,rz=nav:route(cx,cz,tx,tz,nil,100)
    local optimizedRays=workspace.calls-before
    samples=samples+1
    if rx~=bx or rz~=bz then mismatches=mismatches+1 end
    if optimizedRays<exhaustiveRays then changed=changed+1 end
    if optimizedRays>exhaustiveRays then worse=worse+1 end
    oldRays=oldRays+exhaustiveRays
    newRays=newRays+optimizedRays
   end
  end
 end
end
check(samples==720 and mismatches==0,
 "720 cold map-side pairs choose EXACTLY the original exhaustive safe waypoint")
check(changed>0 and worse==0 and newRays<oldRays,
 "cold Garage rays fall versus exhaustive oracle, never increase for any tested pair")
print("Garage detour differential rays: "..tostring(oldRays).." exhaustive vs "
 ..tostring(newRays).." exact-cost lazy; "..tostring(changed).." reduced of "..tostring(samples))
-- Actual Studio probe: from (45.5,-137.4), rear/north wall blocks the
-- generator, while the east entrance (-55,-56) can see the target Part itself.
-- An endpoint hit is NOT an obstruction, but a wall en route still is.
local generator = {Name = "Garage_Generator"}
local stableRaycast = workspace.Raycast
workspace.Raycast = function(self, origin, direction)
	local wall = stableRaycast(self, origin, direction)
	if wall then return wall end
	local x,z = origin.X+direction.X, origin.Z+direction.Z
	if math.abs(x+112)<.1 and math.abs(z+60)<.1 then return {Instance=generator} end
	return nil
end
nav.Cache=nil
x,z=nav:route(45.5,-137.4,-112,-60,nil,7)
check(x==nil and z==nil,"generator's own queryable Part previously masked ALL garage approach nodes")
nav.Cache=nil
x,z=nav:route(45.5,-137.4,-112,-60,nil,7,generator)
check(x==-55 and z==-56,"explicit endpoint hit restores safe visible entrance waypoint")
workspace.Raycast=stableRaycast
nav.Cache=nil
x,z=nav:route(-86.1,-71.4,-88,-125,nil,8)
check(x==-55 and z==-56,"station lure across garage north wall exits through open front")
local gate = {Name = "Garage_BoardedGate"}
local original = workspace.Raycast
workspace.Raycast = function(self, origin, direction)
	-- A boarded front entry is routed THROUGH, not around: Core must press/breach it.
	local structural = original(self, origin, direction)
	if structural then return structural end
	if direction.X > 0 and origin.X < -61.8 and origin.X + direction.X > -61.8
		and origin.Z >= -76 and origin.Z <= -36 then
		return {Instance = gate}
	end
	return nil
end
x, z = nav:route(-90, -56, -145, -56, nil, 5)
check(x == -55 and z == -56, "boarded gate remains on the route so existing breach authority applies (" .. tostring(x) .. ", " .. tostring(z) .. ")")
workspace.Raycast = function() return {Instance = walls.RearWall} end
x, z = nav:route(-90, -56, -145, -56, nil, 6)
check(x == nil and z == nil, "no safe visible waypoint fails closed instead of wall-running")
check(Navigation.new(nil, workspace) == nil, "missing authored garage cannot fabricate a route")
workspace.Raycast = original
local root = {Position = {X = -145, Y = 3, Z = -56}}
local player = {UserId = 17, Character = {FindFirstChild = function(_, name)
	return name == "HumanoidRootPart" and root or nil
end}}
local creature = {X = -90, Y = 8, Z = -56, AttackPhase = nil, Dormant = false, prepared = false}
function creature:setDormant(value) self.Dormant = value end
function creature:excludeCharacters() end
function creature:position() return self.X, self.Y, self.Z end
function creature:isThreatening() return true end
function creature:setTarget(x, y, z) self.TargetX, self.TargetY, self.TargetZ = x, y, z end
function creature:clearTarget() self.TargetX, self.TargetY, self.TargetZ = nil, nil, nil end
function creature:canPrepareChomp() return true end -- force distance edge to test wall guard
function creature:prepareChomp() self.prepared = true end
local service = setmetatable({
	running = false, order = {1}, creatures = {[1] = creature}, Navigation = nav,
	Search = VitriolRequire("InstinctSearch").new({},nil), -- manual service bypasses init()
	Players = {GetPlayers = function() return {player} end},
	Time = {phase = "Night", elapsedTotal = 10}, Session = {state = "Running"},
	Health = {states = {[17] = {dead = false}}}, lastCharacters = {}, presentedDeaths = {},
}, VitriolRequire("CreatureService"))
-- Route policy fixture injects a PREVIOUSLY detected target. Separate senses
-- regression proves a hidden far player is not newly detected through a wall.
service._nearestTarget=function(_,braid)
 local p=root.Position;local dx,dz=p.X-braid.X,p.Z-braid.Z
 return root,player,dx*dx+dz*dz
end
service:think(1/6)
check(creature.TargetX == -55 and creature.TargetZ == -56 and not creature.prepared,
	"real CreatureService think feeds a detour and refuses a through-wall crouch")
creature.X, creature.Z = -125, -86
service.Time.elapsedTotal = 12
service:think(1/6)
check(creature.TargetX == -145 and creature.TargetZ == -56 and creature.prepared,
	"CreatureService returns to direct pursuit and permits reachable prey")
-- Lure policy has ALREADY measured the exact blocked target segment. Reuse
-- that hit in the cold detour without changing the authored route or priority.
creature.X,creature.Y,creature.Z=-90,8,-56
creature.prepared=false
nav.Cache=nil
service.Time.elapsedTotal=13
service.DayPrep={Generator=generator,
 signal=function()return {X=-145,Y=4,Z=-56},30,"GarageLight" end}
local lureBefore=workspace.calls
service:think(1/6)
check(creature.DecisionReason=="GarageLight" and creature.TargetX==-55
 and creature.TargetZ==-56 and workspace.calls-lureBefore==11,
 "real service reuses lure hit: one policy ray plus 10 tested detour rays")
return SESSION
