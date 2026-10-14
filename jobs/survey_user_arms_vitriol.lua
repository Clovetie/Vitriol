-- Guarded read-only Edit-mode survey of the USER's Workspace.Arms viewmodel.
assert(game.PlaceId==92448193604950,"Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(),"Stop Play first")
local HttpService=game:GetService("HttpService")
local root=workspace:FindFirstChild("Arms")
local entries={}
local function v(q) return {x=q.X,y=q.Y,z=q.Z} end
local function survey(node,depth)
    local row={name=node.Name,class=node.ClassName,path=node:GetFullName(),depth=depth}
    if node:IsA("BasePart") then
        row.position=v(node.Position);row.size=v(node.Size)
        row.anchored=node.Anchored;row.transparency=node.Transparency
        row.canCollide=node.CanCollide;row.material=tostring(node.Material)
    elseif node:IsA("Model") then
        row.pivot=v(node:GetPivot().Position)
        row.primaryPart=node.PrimaryPart and node.PrimaryPart:GetFullName() or nil
    elseif node:IsA("Motor6D") or node:IsA("Weld") or node:IsA("WeldConstraint") then
        row.part0=node.Part0 and node.Part0:GetFullName() or nil
        row.part1=node.Part1 and node.Part1:GetFullName() or nil
    elseif node:IsA("Animation") then row.animationId=node.AnimationId
    elseif node:IsA("Shirt") then row.shirtTemplate=node.ShirtTemplate
    elseif node:IsA("SurfaceGui") then row.adornee=node.Adornee and node.Adornee:GetFullName() or nil;row.face=tostring(node.Face)
    elseif node:IsA("ScreenGui") then row.enabled=node.Enabled
    elseif node:IsA("ProximityPrompt") then row.enabled=node.Enabled end
    entries[#entries+1]=row
    if depth<7 then for _,child in ipairs(node:GetChildren()) do survey(child,depth+1) end end
end
if root then survey(root,0) end
local client=game:GetService("StarterPlayer").StarterPlayerScripts.Vitriol.ClientMain
local gui=client and client:FindFirstChild("VitriolWatchOverlay")
local watch={}
if gui then
    watch={path=gui:GetFullName(),class=gui.ClassName,enabled=gui.Enabled}
    for _,child in ipairs(gui:GetChildren()) do
        watch[child.Name]={class=child.ClassName,visible=child:IsA("GuiObject") and child.Visible or nil,
            position=child:IsA("GuiObject") and tostring(child.Position) or nil,
            size=child:IsA("GuiObject") and tostring(child.Size) or nil}
    end
end
return HttpService:JSONEncode({root=root and root.ClassName or nil,count=#entries,entries=entries,watch=watch})
