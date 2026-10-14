-- Read only: one road dimension preflight; never move/resize user geometry.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local map=assert(workspace:FindFirstChild("Map"))
local roads=assert(map:FindFirstChild("Roads"))
local road=assert(roads:FindFirstChild("Road_Main"))
local spawn=assert(map.Spawns:FindFirstChild("Spawn_Garage"))
local p,s=road.Position,road.Size
return game:GetService("HttpService"):JSONEncode({ok=true,editOnly=true,
 roadPosition={p.X,p.Y,p.Z},roadSize={s.X,s.Y,s.Z},
 anchored=road.Anchored,collide=road.CanCollide,query=road.CanQuery,
 spawnPosition={spawn.Position.X,spawn.Position.Y,spawn.Position.Z}})
