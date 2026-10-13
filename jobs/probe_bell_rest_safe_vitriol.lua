-- Read-only preflight: report each Church_BellLever guard separately.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local l=assert(workspace.Map.Interactions:FindFirstChild("Church_BellLever"))
local p=l.Position
return game:GetService("HttpService"):JSONEncode({ok=true,position={p.X,p.Y,p.Z},anchored=l.Anchored,
 collides=l.CanCollide,armed=l:GetAttribute("Armed"),class=l.ClassName})
