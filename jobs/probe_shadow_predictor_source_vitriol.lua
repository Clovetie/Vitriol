-- READ ONLY Edit: compile actual Studio Sources; classify existing tagged zone
-- volumes without moving Parts, introducing a player, or changing the map.
assert(game.PlaceId==92448193604950 and not game:GetService("RunService"):IsRunning(),"Vitriol Edit only")
local http=game:GetService("HttpService")
local vitriol=game:GetService("ServerStorage").Vitriol
local brain=vitriol.Creature.Brain.ShadowPredictor
assert(brain:IsA("ModuleScript"),"ShadowPredictor must be an authored ModuleScript")
local make,err=loadstring(brain.Source)
assert(make,err or "ShadowPredictor Source failed to compile")
local lib,libErr=loadstring(game:GetService("ReplicatedStorage").Vitriol.Lib.MarkovPredictor.Source)
assert(lib,libErr or "MarkovPredictor Source failed to compile")
local conf,confErr=loadstring(game:GetService("ReplicatedStorage").Vitriol.Config.MonsterConfig.Source)
assert(conf,confErr or "MonsterConfig Source failed to compile")
local service,serviceErr=loadstring(vitriol.Services.CreatureService.Source)
assert(service,serviceErr or "CreatureService Source failed to compile")
local shadow=make().new(conf().Prediction,workspace.Map,lib())
assert(#shadow.Zones==10,"expected 10 existing tagged authored map zones")
local garage=shadow:classAt(-90,4,-56)
local road=shadow:classAt(0,4,-56)
local roof=shadow:classAt(119,48,-205)
assert(shadow.Classes[garage]=="Garage" and shadow.Classes[road]=="Road" and shadow.Classes[roof]=="Roof",
 "actual authored zone attributes/geometries do not classify as surveyed")
assert(shadow:classAt(900,4,900)==nil,"off-map coordinates must fail closed")
assert(not shadow:observe(77,-90,4,-56,0))
assert(shadow:observe(77,0,4,-56,1))
assert(shadow.Transitions==1 and shadow.Models[77]:count(garage,road)==1,
 "only witnessed crossing creates one coarse location transition")
shadow:markUnseenExcept(nil)
assert(not shadow:observe(77,-90,4,-56,2) and shadow.Transitions==1,
 "an unseen crossing cannot enter Markov counts")
local dump=shadow:dump()
assert(not dump.steers and not dump.postureObserved and dump.authoredZoneCount==10
 and not dump.players[1].trusted and dump.players[1].possibleNextClasses==nil,
 "debug must withhold undertrained probabilities and never offer a target")
local trained=make().new(conf().Prediction,workspace.Map,lib())
for i=1,12 do
 trained:observe(78,-90,4,-56,i*2)
 trained:observe(78,0,4,-56,i*2+1)
end
trained:observe(78,-90,4,-56,26)
local exposed=trained:dump().players[1]
assert(exposed.trusted and exposed.lastClass=="Garage"
 and exposed.possibleNextClasses[1].class=="Road" and exposed.lastSampleAt==26,
 "trained, sensed sample did not show historical distribution")
trained:markUnseenExcept(nil)
local hidden=trained:dump().players[1]
assert(hidden.observationsFromLastClass>=12 and not hidden.currentlySensed
 and not hidden.trusted and hidden.possibleNextClasses==nil,
 "trained but HIDDEN player must not get a current next-class guess")
return http:JSONEncode({ok=true,authoredZoneCount=#shadow.Zones,
 garage=shadow.Classes[garage],road=shadow.Classes[road],roof=shadow.Classes[roof],
 transitions=shadow.Transitions,steers=dump.steers,postureObserved=dump.postureObserved})
