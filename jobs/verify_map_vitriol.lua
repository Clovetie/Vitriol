-- Read-only Studio Edit-mode audit of the authored playable town slice.
assert(not game:GetService("RunService"):IsRunning(), "Stop Play before verifying map")
local HttpService = game:GetService("HttpService")
local Tags = game:GetService("CollectionService")
local defects = {}
local function fail(message) defects[#defects+1] = message end
local function node(parent,name,class)
    if parent == nil then fail("missing parent " .. name); return nil end
    local found, count = nil, 0
    for _, child in ipairs(parent:GetChildren()) do
        if child.Name == name then found = child; count += 1 end
    end
    if count ~= 1 then fail("expected exactly one "..name..", got "..count); return nil end
    if found.ClassName ~= class then fail(name.." wrong class "..found.ClassName); return nil end
    return found
end
local map = node(workspace,"Map","Folder")
if map and map:GetAttribute("VitriolMapVersion") ~= 1 then fail("map version must be 1") end
local ground = node(map,"Ground","Folder")
local floor = node(ground,"Ground_QuarryFoundation","Part")
if floor and (not floor.Anchored or not floor.CanCollide or floor.Size.X ~= 600 or floor.Size.Z ~= 600
    or math.abs(floor.Position.Y + 8) > 0.01) then fail("playable foundation dimensions/collision changed") end
local spawnFolder = node(map,"Spawns","Folder")
local spawn = node(spawnFolder,"Spawn_Garage","SpawnLocation")
if spawn and (not spawn.Enabled or not spawn.Anchored or not spawn.CanCollide
    or math.abs(spawn.Position.X + 54) > .01 or math.abs(spawn.Position.Z + 55) > .01) then
    fail("Spawn_Garage not at the authored safe start")
end
for _,name in ipairs({"Roads","Structures","Interiors","Nature","Waterways","Lighting_Anchors","NavHints"}) do
    node(map,name,"Folder")
end
local roads = map and map:FindFirstChild("Roads")
local road = node(roads,"Road_Main","Part")
-- Preserve user-extended Road_Main. Check the original safe corridor is
-- still covered, not that the Part is exactly the old 560-stud length.
if road then
    local p,s=road.Position,road.Size
    if not road.CanCollide or not road.Anchored
        or p.X-s.X*0.5 > -17.99 or p.X+s.X*0.5 < 17.99
        or p.Z-s.Z*0.5 > -279.99 or p.Z+s.Z*0.5 < 279.99 then
        fail("road missing safe traversal")
    end
end
local structures = map and map:FindFirstChild("Structures")
for _,name in ipairs({"Millers_Garage","Filling_Station","House_01","House_02","Church_BellTower","Riverside_Mill","Field_WaterTower"}) do
    local model = node(structures,name,"Model")
    if model and not Tags:HasTag(model,"Vitriol_Structure") then fail(name.." missing authored structure tag") end
    if model then node(model,"Meta","Configuration") end
end
local zones = node(map,"Zones","Folder")
local classes = {}
local count = 0
if zones then
    for _,volume in ipairs(zones:GetChildren()) do
        count += 1
        if volume.ClassName ~= "Part" or not Tags:HasTag(volume,"Vitriol_Zone")
            or not volume.Anchored or volume.CanCollide or volume.CanQuery or volume.Transparency ~= 1 then
            fail(volume.Name.." is not a safe tagged metadata volume")
        end
        local class = volume:GetAttribute("ZoneClass")
        if class then classes[class] = true else fail(volume.Name.." missing ZoneClass") end
        if not volume:GetAttribute("ZoneName") then fail(volume.Name.." missing ZoneName") end
    end
end
if count ~= 10 then fail("expected nine ground tiles plus one roof zone, got "..count) end
for _,class in ipairs({"Road","Garage","House","Woods","Open","Water","Roof"}) do
    if not classes[class] then fail("missing "..class.." location class") end
end
local lights = map and map:FindFirstChild("Lighting_Anchors")
if lights and #lights:GetChildren() ~= 5 then fail("expected five authored light landmarks") end
if workspace:FindFirstChild("Baseplate") or workspace:FindFirstChild("SpawnLocation") then
    fail("obsolete top-level prototype pieces were not relocated under Map")
end
local result = {ok=#defects==0,defects=defects,placeId=game.PlaceId,version=map and map:GetAttribute("VitriolMapVersion"),zoneCount=count,structures=structures and #structures:GetChildren() or 0,lamps=lights and #lights:GetChildren() or 0}
return HttpService:JSONEncode(result)
