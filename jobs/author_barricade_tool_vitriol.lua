-- EDIT MODE ONLY: dormant Tool, 8 movable preauthored boards, and two house sockets.
assert(game.PlaceId == 92448193604950, "Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play before authoring")
local map = workspace:FindFirstChild("Map")
assert(map and map:GetAttribute("VitriolMapVersion") == 1, "Requires verified Map v1")
local structures = map:FindFirstChild("Structures")
assert(structures and structures:FindFirstChild("House_01") and structures:FindFirstChild("House_02"), "House entry geometry missing")
local server = game:GetService("ServerStorage"):FindFirstChild("Vitriol")
assert(server and server:IsA("Folder"), "ServerStorage.Vitriol missing")
local report={created=0,reused=0}
local function ensure(parent,class,name)
    local found,count=nil,0
    for _,child in ipairs(parent:GetChildren()) do
        if child.Name==name then found=child; count+=1 end
    end
    assert(count<=1,"duplicate "..name)
    if found then assert(found.ClassName==class,"wrong class for "..name); report.reused+=1; return found end
    local node=Instance.new(class); node.Name=name; node.Parent=parent; report.created+=1; return node
end
local tools=ensure(server,"Folder","Tools")
local tool=ensure(tools,"Tool","BarricadePlankTool")
tool.RequiresHandle=true
tool.CanBeDropped=false
tool.ToolTip="Place a plank set at an opening or on nearby ground (daytime)"
local handle=ensure(tool,"Part","Handle")
handle.Size=Vector3.new(.55,3,.28)
handle.Anchored=false
handle.CanCollide=false
handle.CanQuery=false
handle.CanTouch=false
handle.Massless=true
handle.Material=Enum.Material.Wood
handle.Color=Color3.fromRGB(91,67,48)
-- Socket volumes are EDIT-MODE metadata, not blocking walls or raycast hits.
local sockets=ensure(map,"Folder","BarricadeSockets")
for _,data in ipairs({{"House_01_Door",-79,72},{"House_02_Door",114,62}}) do
    local socket=ensure(sockets,"Part",data[1])
    socket.Size=Vector3.new(1,10,15.5)
    socket.CFrame=CFrame.new(data[2],5.4,data[3])
    socket.Anchored=true
    socket.CanCollide=false
    socket.CanQuery=false
    socket.CanTouch=false
    socket.Transparency=1
    socket:SetAttribute("BarricadeSocket",true)
end
local placed=ensure(map,"Folder","PlacedBarricades")
local pool=ensure(server,"Folder","BarricadePool")
for i=1,8 do
    local name=string.format("Board_%02d",i)
    local board=pool:FindFirstChild(name) or placed:FindFirstChild(name)
    if board then
        assert(board.ClassName=="Part" and (board.Parent==pool or board.Parent==placed),"unexpected pool slot "..name)
        report.reused+=1
    else
        board=ensure(pool,"Part",name)
    end
    -- Do not reset an in-use board if this job is reapplied after a Play edit.
    if board.Parent==pool then
        board.Size=Vector3.new(8,6,.7)
        board.CFrame=CFrame.new(0,-1000-i*8,0)
        board.Anchored=true
        board.Transparency=1
        board.CanCollide=false
        board.CanQuery=false
        board.CanTouch=false
    end
    board.Material=Enum.Material.Wood
    board.Color=Color3.fromRGB(91,67,48)
    local prompt=ensure(board,"ProximityPrompt","ReleaseBoard")
    prompt.ActionText="Remove boards (loud)"
    prompt.ObjectText="Plank barricade"
    prompt.HoldDuration=1
    prompt.MaxActivationDistance=9
    prompt.RequiresLineOfSight=false
    prompt.Enabled=board.Parent==placed
end
return game:GetService("HttpService"):JSONEncode(report)
