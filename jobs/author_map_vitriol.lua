-- EDIT MODE ONLY. Authored, named and grouped first playable town slice.
-- Idempotent. Never invoked by game code; no runtime-created Vitriol objects.
local RunService = game:GetService("RunService")
assert(not RunService:IsRunning(), "Stop Play/Run before authoring the map")
assert(game.PlaceId == 92448193604950, "Refusing map edit: not the verified Vitriol place")
local HttpService = game:GetService("HttpService")
local Tags = game:GetService("CollectionService")
local report = {created = 0, reused = 0, moved = 0, removedPrototype = 0}
local function ensure(parent, class, name)
    assert(parent ~= nil, "missing parent for " .. name)
    local found
    for _, item in ipairs(parent:GetChildren()) do
        if item.Name == name then
            assert(not found, "duplicate authored map child " .. parent:GetFullName() .. "." .. name)
            assert(item.ClassName == class, "wrong class for " .. item:GetFullName())
            found = item
        end
    end
    if found then report.reused += 1; return found end
    local item = Instance.new(class)
    item.Name = name
    item.Parent = parent
    report.created += 1
    return item
end
local function rgb(r,g,b) return Color3.fromRGB(r,g,b) end
local P = {
    soil = rgb(43,45,41), asphalt = rgb(38,40,42), gravel = rgb(77,73,65),
    rust = rgb(95,66,55), brick = rgb(88,69,65), wood = rgb(92,79,68),
    pale = rgb(130,126,112), steel = rgb(75,82,83), moss = rgb(41,54,45),
    leaf = rgb(43,59,51), water = rgb(28,49,62), amber = rgb(239,177,96),
}
local map = ensure(workspace, "Folder", "Map")
local version = map:GetAttribute("VitriolMapVersion")
assert(version == nil or version == 1, "Unrecognised authored Map version: refuse overwrite")
map:SetAttribute("VitriolMapVersion", 1)
local ground = ensure(map,"Folder","Ground")
local roads = ensure(map,"Folder","Roads")
local structures = ensure(map,"Folder","Structures")
local interiors = ensure(map,"Folder","Interiors")
local nature = ensure(map,"Folder","Nature")
local waterway = ensure(map,"Folder","Waterways")
local lights = ensure(map,"Folder","Lighting_Anchors")
local hints = ensure(map,"Folder","NavHints")
local zones = ensure(map,"Folder","Zones")
local spawns = ensure(map,"Folder","Spawns")

-- Only the two surveyed stock prototypes are replaced. Never clear Terrain,
-- user-built geometry or unknown children. Preserve the actual SpawnLocation.
local foundation = ground:FindFirstChild("Ground_QuarryFoundation")
if foundation == nil then
    local stock = workspace:FindFirstChild("Baseplate")
    assert(stock and stock:IsA("Part") and stock.Size.X == 2048 and stock.Size.Z == 2048
        and math.abs(stock.Position.Y + 8) < .01, "Baseplate is not the surveyed prototype; edit by hand")
    foundation = stock
    foundation.Name = "Ground_QuarryFoundation"
    foundation.Parent = ground
    report.moved += 1
end
foundation.Size = Vector3.new(600,16,600)
foundation.CFrame = CFrame.new(0,-8,0)
foundation.Material = Enum.Material.Ground
foundation.Color = P.soil
foundation.Anchored = true
foundation.CanCollide = true
local oldTexture = foundation:FindFirstChild("Texture")
if oldTexture and oldTexture:IsA("Texture") then oldTexture:Destroy(); report.removedPrototype += 1 end
local spawn = spawns:FindFirstChild("Spawn_Garage")
if spawn == nil then
    local stock = workspace:FindFirstChild("SpawnLocation")
    assert(stock and stock:IsA("SpawnLocation"), "Missing stock SpawnLocation; refuse to invent a different player spawn")
    spawn = stock
    spawn.Name = "Spawn_Garage"
    spawn.Parent = spawns
    report.moved += 1
end
spawn.Size = Vector3.new(12,1,12)
spawn.CFrame = CFrame.new(-54,.9,-55)
spawn.Material = Enum.Material.Slate
spawn.Color = P.gravel
spawn.Anchored = true
spawn.CanCollide = true
spawn.Transparency = .25
spawn.Neutral = true
spawn.Duration = 0
local stockDecal = spawn:FindFirstChild("Decal")
if stockDecal and stockDecal:IsA("Decal") then stockDecal:Destroy(); report.removedPrototype += 1 end
local emptyBrush = workspace:FindFirstChild("TreeBrushFolder")
if emptyBrush and emptyBrush:IsA("Folder") and #emptyBrush:GetChildren() == 0 then
    emptyBrush:Destroy()
    report.removedPrototype += 1
end

local function part(parent,name,x,y,z,w,h,d,material,tint,solid,shape)
    local p=ensure(parent,"Part",name)
    p.Size=Vector3.new(w,h,d)
    p.CFrame=CFrame.new(x,y,z)
    p.Anchored=true
    p.Material=material
    p.Color=tint
    p.CanCollide=solid ~= false
    p.CanQuery=solid ~= false
    p.CanTouch=solid ~= false
    p.CastShadow=true
    p.Transparency=0
    if shape then p.Shape=shape end
    return p
end
local function paint(parent,name,x,y,z,w,h,d,material,tint)
    return part(parent,name,x,y,z,w,h,d,material,tint,false)
end
local function tagBuilding(model,material)
    Tags:AddTag(model,"Vitriol_Structure")
    local meta=ensure(model,"Configuration","Meta")
    meta:SetAttribute("MaterialClass",material)
    meta:SetAttribute("GameplayReady",false) -- integrity/destruction remains later work
end
local function structural(p,role)
    Tags:AddTag(p,"Vitriol_Joint")
    p:SetAttribute("IntegrityRole",role)
end

-- A winding road is the navigation spine. Materials deliberately contrast with
-- soft soil: later sound/vibration gameplay has recognizable surfaces to sample.
part(roads,"Road_Main",0,.12,0,36,.24,560,Enum.Material.Asphalt,P.asphalt)
part(roads,"Road_Crossing",0,.14,-86,250,.25,28,Enum.Material.Asphalt,P.asphalt)
for i=-5,5 do
    paint(roads,"FadedCenterLine_"..(i+6),0,.28,i*45,1,.08,17,Enum.Material.Concrete,P.pale)
end
for side=-1,1,2 do
    part(roads,"Shoulder_"..side,side*21,.09,0,6,.18,560,Enum.Material.Pebble,P.gravel)
end
part(roads,"Mill_Track",91,.12,108,170,.24,8,Enum.Material.Ground,P.gravel)
part(roads,"Church_Path",96,.15,-118,154,.3,7,Enum.Material.Concrete,P.pale)
part(roads,"House_Path",70,.13,76,138,.26,6,Enum.Material.Pebble,P.gravel)
for i=1,7 do
    paint(roads,"RoadCrack_"..i,(i%2==0 and 8 or -7),.27,-235+i*62,6,.05,.32,Enum.Material.Slate,P.soil)
end

-- Open-front service building: park/prepare here by day, three doorways give
-- the creature readable entries at night. Solid roofs make actual shelter.
local garage=ensure(structures,"Model","Millers_Garage")
tagBuilding(garage,"Metal")
structural(part(garage,"Floor",-90,.42,-56,56,.8,46,Enum.Material.Concrete,P.gravel),"Floor")
structural(part(garage,"RearWall",-118,9,-56,1.4,18,46,Enum.Material.CorrodedMetal,P.steel),"Wall")
for _,z in ipairs({-78,-34}) do
    structural(part(garage,"Corner_"..z,-62,9,z,2,18,2,Enum.Material.Metal,P.rust),"Post")
end
structural(part(garage,"BackNorth",-90,9,-79,56,18,1.4,Enum.Material.CorrodedMetal,P.steel),"Wall")
structural(part(garage,"BackSouth",-90,9,-33,56,18,1.4,Enum.Material.CorrodedMetal,P.steel),"Wall")
structural(part(garage,"DoorLintel",-62,16,-56,1.6,4,42,Enum.Material.Metal,P.rust),"Beam")
structural(part(garage,"Roof",-90,19,-56,62,1.4,52,Enum.Material.Metal,P.steel),"Roof")
part(interiors,"Garage_LiftDeck",-95,.95,-56,22,.9,15,Enum.Material.Metal,P.rust)
for i=1,2 do
    part(interiors,"Garage_LiftPost_"..i,-95,5.8,-56+(i==1 and -7 or 7),1,10,1,Enum.Material.Metal,P.steel)
end
for i=1,4 do
    part(interiors,"Garage_Barrel_"..i,-108,2,-72+i*8,3,4,3,Enum.Material.Metal,P.rust)
end
part(interiors,"Garage_Workbench",-111,2.4,-45,12,1,4,Enum.Material.Wood,P.wood)

local station=ensure(structures,"Model","Filling_Station")
tagBuilding(station,"Metal")
structural(part(station,"Canopy",-88,13,-125,64,1.4,34,Enum.Material.Metal,P.steel),"Roof")
for _,x in ipairs({-114,-62}) do
    for _,z in ipairs({-138,-112}) do
        structural(part(station,"CanopyPost_"..x.."_"..z,x,6.5,z,1.5,13,1.5,Enum.Material.Metal,P.rust),"Post")
    end
end
for i=1,2 do
    local pump=part(interiors,"FuelPump_"..i,-70,2.5,-135+(i-1)*18,3,5,3,Enum.Material.Metal,P.rust)
    pump:SetAttribute("GameplayReady",false)
end
part(station,"ConcreteApron",-88,.33,-125,73,.6,39,Enum.Material.Concrete,P.gravel)

local function house(name,x,z,wallTint)
    local m=ensure(structures,"Model",name)
    tagBuilding(m,"Wood")
    structural(part(m,"Floor",x,.4,z,42,.8,36,Enum.Material.Wood,P.wood),"Floor")
    structural(part(m,"NorthWall",x,8,z-18,42,16,1,Enum.Material.Wood,wallTint),"Wall")
    structural(part(m,"SouthWall",x,8,z+18,42,16,1,Enum.Material.Wood,wallTint),"Wall")
    structural(part(m,"WestWall",x-21,8,z,1,16,36,Enum.Material.Wood,wallTint),"Wall")
    -- East-facing door is eight studs wide; lintel/side piers are structural.
    for _,shift in ipairs({-13,13}) do
        structural(part(m,"EastPier_"..shift,x+21,8,z+shift,1,16,10,Enum.Material.Wood,wallTint),"Wall")
    end
    structural(part(m,"EastLintel",x+21,14,z,1,4,16,Enum.Material.Wood,wallTint),"Beam")
    structural(part(m,"Roof",x,17,z,47,1.4,42,Enum.Material.Slate,P.rust),"Roof")
    structural(part(m,"Porch",x+29,.5,z,15,1,29,Enum.Material.Wood,P.wood),"Floor")
    for _,shift in ipairs({-12,12}) do
        structural(part(m,"PorchPost_"..shift,x+35,6.5,z+shift,1.4,12,1.4,Enum.Material.Wood,P.wood),"Post")
    end
    structural(part(m,"PorchRoof",x+29,13,z,17,1,31,Enum.Material.Slate,P.rust),"Roof")
    local pane=paint(m,"NorthWindow",x,9,z-18.6,9,6,.3,Enum.Material.Glass,P.water)
    pane.Transparency=.55
    part(interiors,name.."_Table",x,2,z,9,1.3,5,Enum.Material.Wood,P.wood)
    part(interiors,name.."_Closet",x-14,4,z+10,6,8,5,Enum.Material.Wood,P.pale)
end
house("House_01",-100,72,P.pale)
house("House_02",93,62,P.brick)

local church=ensure(structures,"Model","Church_BellTower")
tagBuilding(church,"Masonry")
structural(part(church,"NaveFloor",119,.4,-179,48,.8,74,Enum.Material.Concrete,P.brick),"Floor")
for _,side in ipairs({-1,1}) do
    structural(part(church,"NaveSide_"..side,119+side*24,12,-179,1.5,24,74,Enum.Material.Brick,P.brick),"Wall")
end
structural(part(church,"RearWall",119,12,-216,48,24,1.5,Enum.Material.Brick,P.brick),"Wall")
for _,side in ipairs({-1,1}) do
    structural(part(church,"EntryPier_"..side,119+side*16,12,-142,16,24,1.5,Enum.Material.Brick,P.brick),"Wall")
end
structural(part(church,"NaveRoof",119,25,-179,52,2,80,Enum.Material.Slate,P.steel),"Roof")
local tower=part(church,"BellTower",119,37,-205,15,24,15,Enum.Material.Brick,P.brick)
structural(tower,"Tower")
part(church,"BellPlatform",119,49,-205,18,1,18,Enum.Material.Wood,P.wood)
-- Tower silhouette is authored now; stairs/climb interaction waits for asset pass.
for i=1,3 do
    part(interiors,"Church_Pew_"..i,119,2,-178+(i-2)*16,30,2,5,Enum.Material.Wood,P.wood)
end

local mill=ensure(structures,"Model","Riverside_Mill")
tagBuilding(mill,"Wood")
structural(part(mill,"Deck",96,.4,142,46,.8,46,Enum.Material.Wood,P.wood),"Floor")
for _,x in ipairs({73,119}) do
    structural(part(mill,"SideWall_"..x,x,8,142,1,16,46,Enum.Material.Wood,P.wood),"Wall")
end
structural(part(mill,"RearWall",96,8,165,46,16,1,Enum.Material.Wood,P.wood),"Wall")
structural(part(mill,"Roof",96,17,142,51,1,51,Enum.Material.Slate,P.rust),"Roof")
part(mill,"WaterWheel",122,7,137,2,13,13,Enum.Material.Wood,P.wood)
local channel=part(waterway,"Mill_Channel",154,.25,151,24,.25,185,Enum.Material.SmoothPlastic,P.water,false)
channel.Transparency=.25
for _,x in ipairs({141,167}) do
    part(waterway,"ChannelBank_"..x,x,.35,151,3,.7,188,Enum.Material.Rock,P.gravel)
end
part(waterway,"CrossingBridge",154,.65,70,36,1,12,Enum.Material.Wood,P.wood)

local field=ensure(structures,"Model","Field_WaterTower")
tagBuilding(field,"Metal")
for i=1,4 do
    local dx=(i<=2 and -8 or 8)
    local dz=(i%2==0 and -8 or 8)
    structural(part(field,"TowerLeg_"..i,185+dx,16,194+dz,1.5,32,1.5,Enum.Material.Metal,P.rust),"Post")
end
structural(part(field,"Tank",185,37,194,23,11,23,Enum.Material.Metal,P.steel),"Roof")
part(field,"TowerCap",185,43,194,26,1.2,26,Enum.Material.Metal,P.rust)

-- Fixed, deliberate clusters rather than a random forest. Space near the road
-- stays clear for the Braid's wide planted gait; trunks supply risky cover.
local trees={
    {-213,-230,13},{-177,-242,16},{-235,-180,15},{-147,-210,12},
    {-251,179,17},{-207,197,14},{-152,232,16},{-95,246,14},
    {88,236,13},{128,252,17},{235,247,18},{258,168,14},
    {215,-272,15},{270,-195,14},{-255,51,12},{-243,-82,15},
}
for i,s in ipairs(trees) do
    local x,z,h=s[1],s[2],s[3]
    local trunk=part(nature,"TreeTrunk_"..i,x,h/2,z,h,2.2,2.2,Enum.Material.Wood,P.wood,true,Enum.PartType.Cylinder)
    trunk.CFrame=CFrame.new(x,h/2,z)*CFrame.Angles(0,0,math.pi/2)
    part(nature,"TreeCanopy_"..i,x,h+4,z,12,11,12,Enum.Material.Grass,P.leaf,false,Enum.PartType.Ball)
end
for i=1,8 do
    local x=(i<=4 and -1 or 1)*(177+(i%4)*18)
    local z=-94+(i%4)*67
    part(nature,"StoneCover_"..i,x,1.3,z,6,2.6,4,Enum.Material.Rock,P.gravel)
end
part(nature,"Woods_Culvert",-212,2.7,153,12,5.4,16,Enum.Material.Concrete,P.gravel)
paint(nature,"CulvertMouth",-212,2.8,144.6,7,3,.2,Enum.Material.Slate,P.asphalt)

-- Authored fixtures, not live-generated effects. The bulbs provide a few warm
-- landmarks when LightingDriver makes the night blue-black.
local lamps={{-48,-95},{42,-95},{-40,88},{34,85},{105,-134}}
for i,pos in ipairs(lamps) do
    local m=ensure(lights,"Model","Streetlamp_"..i)
    part(m,"Pole",pos[1],8,pos[2],.65,16,.65,Enum.Material.Metal,P.steel)
    local bulb=paint(m,"AmberBulb",pos[1],16.4,pos[2],1.5,1.5,1.5,Enum.Material.Neon,P.amber)
    local light=ensure(bulb,"PointLight","WarmPool")
    light.Color=P.amber
    light.Range=30
    light.Brightness=1.5
    light.Shadows=true
end

-- These are metadata volumes, never raycast footholds or blocking geometry.
-- Rectangles tile the entire 600x600 walkable plane without horizontal gaps.
local zoneDefs={
    {"Zone_Road_Main","Road","Quarry Road",0,-0,44,600},
    {"Zone_Woods_South","Woods","Timberline",-161,-230,278,140},
    {"Zone_Garage","Garage","Miller's Garage",-161,-80,278,160},
    {"Zone_House_01","House","Old Row",-161,80,278,160},
    {"Zone_Woods_North","Woods","North Woods",-161,230,278,140},
    {"Zone_Open_South","Open","Far Field",161,-270,278,60},
    {"Zone_House_02","House","Church Crossroads",161,-120,278,240},
    {"Zone_Water_Mill","Water","Mill Channel",161,80,278,160},
    {"Zone_Open_Field","Open","Tower Field",161,230,278,140},
}
for _,v in ipairs(zoneDefs) do
    local z=paint(zones,v[1],v[4],10,v[5],v[6],50,v[7],Enum.Material.SmoothPlastic,P.soil)
    z.Transparency=1
    z.CanQuery=false
    z.CastShadow=false
    z:SetAttribute("ZoneClass",v[2]); z:SetAttribute("ZoneName",v[3])
    Tags:AddTag(z,"Vitriol_Zone")
end
-- Only the church tower is presently above the ground-zone volumes.
local roof=paint(zones,"Zone_Roof_Church",119,48,-205,20,16,20,Enum.Material.SmoothPlastic,P.soil)
roof.Transparency=1; roof.CanQuery=false; roof.CastShadow=false
roof:SetAttribute("ZoneClass","Roof"); roof:SetAttribute("ZoneName","Church Tower")
Tags:AddTag(roof,"Vitriol_Zone")
local nav=paint(hints,"Hint_Road_Paved",0,1,0,36,2,560,Enum.Material.SmoothPlastic,P.soil)
nav.Transparency=1; nav.CanQuery=false; nav.CastShadow=false
nav:SetAttribute("TravelCost",1)
local soft=paint(hints,"Hint_Woods_Soft",-215,1,223,155,2,120,Enum.Material.SmoothPlastic,P.soil)
soft.Transparency=1; soft.CanQuery=false; soft.CastShadow=false
soft:SetAttribute("TravelCost",3)

return HttpService:JSONEncode(report)
