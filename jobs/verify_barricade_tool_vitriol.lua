-- Read-only Edit-mode audit: dormant Tool, finite board pool, two socket volumes.
assert(game.PlaceId == 92448193604950, "Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play before verification")
local defects={}
local function one(parent,name,class)
    if not parent then defects[#defects+1]="missing parent for "..name; return nil end
    local count,found=0,nil
    for _,child in ipairs(parent:GetChildren()) do if child.Name==name then count+=1;found=child end end
    if count~=1 or found.ClassName~=class then defects[#defects+1]=name.." missing/duplicate/wrong class"; return nil end
    return found
end
local server=one(game:GetService("ServerStorage"),"Vitriol","Folder")
local tools=one(server,"Tools","Folder")
local tool=one(tools,"BarricadePlankTool","Tool")
local handle=one(tool,"Handle","Part")
if tool and (not tool.RequiresHandle or tool.CanBeDropped) then defects[#defects+1]="Tool policy changed" end
if handle and (handle.Anchored or handle.CanCollide) then defects[#defects+1]="Tool handle unsafe" end
if tools and #tools:GetChildren()~=1 then defects[#defects+1]="unexpected stored tool" end
local starterPack=game:GetService("StarterPack")
if starterPack:FindFirstChild("BarricadePlankTool") or workspace:FindFirstChild("BarricadePlankTool") then
    defects[#defects+1]="Tool was distributed before crafting"
end
local pool=one(server,"BarricadePool","Folder")
local map=one(workspace,"Map","Folder")
local sockets=one(map,"BarricadeSockets","Folder")
local placed=one(map,"PlacedBarricades","Folder")
for _,name in ipairs({"House_01_Door","House_02_Door"}) do
    local socket=one(sockets,name,"Part")
    if socket and (socket:GetAttribute("BarricadeSocket")~=true or socket.CanCollide or socket.CanQuery or socket.Transparency~=1) then
        defects[#defects+1]=name.." is not metadata only"
    end
end
if sockets and #sockets:GetChildren()~=2 then defects[#defects+1]="unexpected socket count" end
if placed and #placed:GetChildren()~=0 then defects[#defects+1]="placed boards should be returned to storage in Edit mode" end
for i=1,8 do
    local board=one(pool,string.format("Board_%02d",i),"Part")
    local prompt=one(board,"ReleaseBoard","ProximityPrompt")
    if board and (board.CanCollide or board.CanQuery or board.Transparency~=1 or not board.Anchored) then
        defects[#defects+1]=board.Name.." not idle in storage"
    end
    if prompt and prompt.Enabled then defects[#defects+1]=prompt.Name.." enabled in storage" end
end
if pool and #pool:GetChildren()~=8 then defects[#defects+1]="pool must have exactly eight slots" end
return game:GetService("HttpService"):JSONEncode({ok=#defects==0,defects=defects,storedTool=tool and tool.Name,boards=pool and #pool:GetChildren() or 0,sockets=sockets and #sockets:GetChildren() or 0})
