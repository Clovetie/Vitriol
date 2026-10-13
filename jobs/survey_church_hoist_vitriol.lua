-- Read-only, guarded Edit-mode survey of user-provided church bell assembly.
assert(game.PlaceId == 92448193604950, "Wrong Vitriol place")
assert(not game:GetService("RunService"):IsRunning(), "Stop Play first")
local interactions = workspace.Map.Interactions
local HttpService = game:GetService("HttpService")
local function vector(v) return {x=v.X,y=v.Y,z=v.Z} end
local entries = {}
local function add(node,depth)
    local record={name=node.Name,class=node.ClassName,path=node:GetFullName(),depth=depth}
    if node:IsA("BasePart") then
        record.position=vector(node.Position)
        record.size=vector(node.Size)
        record.anchored=node.Anchored
        record.transparency=node.Transparency
        record.canCollide=node.CanCollide
    elseif node:IsA("Model") then
        record.pivot=vector(node:GetPivot().Position)
        record.primaryPart=node.PrimaryPart and node.PrimaryPart.Name or nil
    elseif node:IsA("RopeConstraint") then
        record.length=node.Length
        record.visible=node.Visible
        record.attachment0=node.Attachment0 and node.Attachment0:GetFullName() or nil
        record.attachment1=node.Attachment1 and node.Attachment1:GetFullName() or nil
    end
    table.insert(entries,record)
    if depth<4 then for _,child in ipairs(node:GetChildren()) do add(child,depth+1) end end
end
for _,node in ipairs(interactions:GetChildren()) do
    local n=node.Name:lower()
    if n:find("bell") or n:find("hoist") or n:find("rope") then add(node,0) end
end
return HttpService:JSONEncode({count=#entries,entries=entries})
