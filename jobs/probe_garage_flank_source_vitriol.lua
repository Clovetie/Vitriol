-- READ ONLY Edit: exercise the exact Studio Source against actual authored
-- Garage wall/corner clearance. No Braid, Player, map or prop is changed.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local srv=game:GetService("ServerStorage").Vitriol
local cfg=assert(loadstring(game:GetService("ReplicatedStorage").Vitriol.Config.MonsterConfig.Source))()
local habitMake=assert(loadstring(srv.Creature.Brain.GarageHabit.Source))()
local nav=assert(assert(loadstring(srv.Creature.GarageNavigation.Source))().new(workspace.Map,workspace))
assert(loadstring(srv.Services.CreatureService.Source),"service Source failed compile")
local params=RaycastParams.new()
params.FilterType=Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances={workspace.Vitriol.Creatures.Braid_1}
local function newHabit() local h=habitMake.new(cfg.Memory,nav,cfg.InstinctSearch);h.Evidence=3;return h end
local checks=0
local function one(h,creature,x,z,now,reason)
 local before=checks
 local gx,gz,why=h:lead(creature,now,0,nav,nil)
 assert(gx==x and gz==z and why==reason,"Garage flank chose wrong/unsafe next leg")
 assert(nav:clear(creature.X,creature.Z,gx,gz,params),"authored flank ray has a real obstruction")
 checks=before+1
 creature.X,creature.Z=gx,gz
end
local west=newHabit();local w={X=-130,Y=8,Z=-56,RaycastParams=params}
assert(not nav:clear(w.X,w.Z,-55,-56,params),"west Garage origin no longer blocked; re-survey route")
one(west,w,-125,-86,1,"witnessed-garage-flank")
one(west,w,-55,-86,2,"witnessed-garage-flank")
one(west,w,-55,-56,3,"witnessed-three-garage-entries")
one(west,w,-90,-56,4,"physical-garage-investigation")
assert(west.PredictionMisses==0,"flank exterior incorrectly reduced Garage confidence")
local south=newHabit();local s={X=-90,Y=8,Z=25,RaycastParams=params}
assert(not nav:clear(s.X,s.Z,-55,-56,params),"south Garage origin no longer blocked; re-survey route")
one(south,s,-55,-26,1,"witnessed-garage-flank")
one(south,s,-55,-56,2,"witnessed-three-garage-entries")
one(south,s,-90,-56,3,"physical-garage-investigation")
local north=newHabit();local n={X=-90,Y=8,Z=-140,RaycastParams=params}
assert(not nav:clear(n.X,n.Z,-55,-56,params),"north Garage origin no longer blocked; re-survey route")
one(north,n,-55,-86,1,"witnessed-garage-flank")
one(north,n,-55,-56,2,"witnessed-three-garage-entries")
one(north,n,-90,-56,3,"physical-garage-investigation")
local woods=newHabit();local t={X=-161,Y=8,Z=-230,RaycastParams=params}
one(woods,t,-125,-86,1,"witnessed-garage-flank")
one(woods,t,-55,-86,2,"witnessed-garage-flank")
one(woods,t,-55,-56,3,"witnessed-three-garage-entries")
local house=newHabit();local h={X=-91,Y=8,Z=77,RaycastParams=params}
local gx,_,why=house:lead(h,1,0,nav,nil)
assert(gx==nil and why=="blocked" and house.PredictionMisses==0,
 "Garage memory must not grant a route THROUGH House_01's solid wall")
return game:GetService("HttpService"):JSONEncode({ok=true,physicalLegs=checks,
 west={-130,-56},south={-90,25},north={-90,-140},woods={-161,-230},
 wallDenied="House_01",interior={-90,-56},source=srv.Creature.Brain.GarageHabit:GetFullName()})
