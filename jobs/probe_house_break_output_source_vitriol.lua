-- READ ONLY Vitriol/Edit: compile the exact current Studio Source and run
-- the break-log branch against Lua tables only. NEVER touch actual furniture.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local src=game:GetService("ServerStorage").Vitriol
local coverSrc=src.Services.HouseCoverService
local coreSrc=src.Creature.CreatureCore
assert(coverSrc:IsA("ModuleScript") and coreSrc:IsA("ModuleScript"),"script class drift")
local make,err=loadstring(coverSrc.Source)
assert(make,err or "HouseCover Source compile")
assert(loadstring(coreSrc.Source),"CreatureCore Source compile")
assert(string.find(coreSrc.Source,"cover:press(bracing, dt, self)",1,true),"actual Core omits contact context")
local module=make()
local logs={}
local service=setmetatable({running=true,Time={phase="Night"},activeCount=1,
 Logger=function(level,line) logs[#logs+1]={level,line} end},module)
service._publish=function() end -- Lua-only fixture, NEVER write a Studio Part
local home={x=-114,z=82}
local piece={Placed=true,Broken=false,Pressure=0,House="House_01",Kind="Closet",
 Part={CFrame={x=-81.5,z=77}},Home=home}
local creature={X=-81.7,Y=8,Z=77,TargetX=-57.5,TargetZ=78.9,
 DecisionReason="last-genuinely-observed-location",Locomotion={anchors=function() return 4 end}}
for i=1,23 do assert(service:press(piece,.1,creature)==false,"premature breach") end
assert(service:press(piece,.1,creature)==true,"expected bounded breach")
assert(piece.Broken and not piece.Placed and piece.Part.CFrame==home and service.activeCount==0,
 "dummy furniture state did not dislodge exactly once")
assert(#logs==1 and logs[1][1]=="info" and string.find(logs[1][2],"paid Day move required",1,true)
 and string.find(logs[1][2],"core(-81.7,8.0,77.0)",1,true)
 and string.find(logs[1][2],"nav(-57.5,78.9)",1,true)
 and string.find(logs[1][2],"reason=last-genuinely-observed-location feet=4",1,true),
 "actual Studio Source did not append the one-per-break Output context")
return game:GetService("HttpService"):JSONEncode({ok=true,editOnly=true,logs=#logs,
 line=logs[1][2],realFurnitureMutated=false})
