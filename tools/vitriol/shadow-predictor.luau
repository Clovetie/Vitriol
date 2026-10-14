-- Observation-only M3 location model: authored geometry, witnessed transitions,
-- no hidden-player GPS, new schedule, interception or posture inference.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1;print("PASS  "..msg)
 else SESSION.failed=SESSION.failed+1;print("FAIL  "..msg) end
end
local Shadow=VitriolRequire("ShadowPredictor")
local Markov=VitriolRequire("MarkovPredictor")
local cfg={LocationClasses={"Open","Road","House","Garage","Basement","Roof","Woods","Water"},MinObservations=12}
local function part(name,class,x,y,z,sx,sy,sz,rotate)
 return {Name=name,Position={X=x,Y=y,Z=z},Size={X=sx,Y=sy,Z=sz},
 Orientation={X=0,Y=rotate or 0,Z=0},
 IsA=function(_,type)return type=="BasePart" end,
 GetAttribute=function(_,key)if key=="ZoneClass" then return class end end}
end
local road=part("Zone_Road_Main","Road",0,10,0,44,50,600)
local garage=part("Zone_Garage","Garage",-161,10,-80,278,50,160)
local roof=part("Zone_Roof_Church","Roof",119,48,-205,20,16,20)
local ignored=part("Wrong","Nonexistent",0,0,0,10,10,10)
local rotated=part("Rotated","Woods",300,10,0,20,50,20,20)
local untagged=part("Untagged","Woods",330,10,0,20,50,20)
local folder={GetChildren=function()return {road,garage,roof,ignored,rotated,untagged} end}
local map={FindFirstChild=function(_,key)if key=="Zones" then return folder end end}
local tags={HasTag=function(_,v,key)return v~=untagged and key=="Vitriol_Zone" end}
local m=Shadow.new(cfg,map,Markov,tags)
check(#m.Zones==3 and m:classAt(-90,4,-56)==4 and m:classAt(0,4,-56)==2,
 "only valid authored axis-aligned ZoneClass regions classify sensed coordinates")
check(m:classAt(119,48,-205)==6 and m:classAt(119,4,-205)==nil
 and m:classAt(300,10,0)==nil and m:classAt(330,10,0)==nil and m:classAt(900,4,900)==nil,
 "roof height and off-map/rotated regions cannot fabricate a grounded zone")
check(not m:observe(1,-90,4,-56,0) and not m:observe(1,0,4,-56,.2)
 and m.Transitions==0,"at most one zone classification per second, not per Think")
check(m:observe(1,0,4,-56,1) and m.Transitions==1
 and m.Models[1]:count(4,2)==1,"a sensed Garage-to-Road crossing learns one real transition")
check(not m:observe(1,0,4,-56,2) and m.Transitions==1,
 "standing still for repeated samples never inflates the transition count")
local fast=Shadow.new(cfg,map,Markov,tags)
fast:observe(3,0,4,-56,0)
fast:markUnseenExcept(nil)
fast:observe(3,-90,4,-56,.5)
check(fast.Transitions==0 and fast:dump().players[1].currentlySensed
 and not fast:observe(3,-90,4,-56,1),
 "subsecond reacquisition reports genuine sight but cannot learn hidden crossing")
m:markUnseenExcept(nil)
check(not m:observe(1,-90,4,-56,3) and m.Transitions==1,
 "losing sight for even one Think forbids an unseen Road-to-Garage crossing")
check(m:observe(1,0,4,-56,4) and m.Models[1]:count(4,2)==2
 and m.Models[1]:count(2,4)==0,
 "continuously witnessed reacquisition can train a new crossing")
m:markUnseenExcept(nil)
check(not m:observe(1,-90,4,-56,10) and m.Transitions==2,
 "long unseen gap does not become a transition")
local low=m:dump()
check(low.mode=="observation-only" and not low.steers and not low.postureObserved
 and low.players[1].trusted==false and low.players[1].possibleNextClasses==nil,
 "debug report explains location-only model and withholds untrained guesses")
for n=1,12 do
 m:observe(1,0,4,-56,10+2*n-1)
 m:observe(1,-90,4,-56,10+2*n)
end
local high=m:dump().players[1]
check(high.trusted and high.observationsFromLastClass>=12
 and high.possibleNextClasses[1].class=="Road" and high.possibleNextClasses[1].probability==1
 and high.predictability==1 and high.lastSampleAt==34,
 "12 witnessed FROM-zone samples expose probabilities with explicit sample time")
m:markUnseenExcept(nil)
local hidden=m:dump().players[1]
check(hidden.observationsFromLastClass>=12 and not hidden.currentlySensed
 and not hidden.trusted and hidden.possibleNextClasses==nil and hidden.predictability==nil,
 "trained model is HISTORICAL; hidden player's next class is withheld")
m:observe(1,-90,4,-56,34.2)
check(m:dump().players[1].trusted and m.Transitions==26,
 "re-sensed player restores diagnostic eligibility without learning hidden travel")
local before=m.Transitions
m:observe(1,900,4,900,37)
m:observe(1,0,4,-56,38)
check(m.Transitions==before and m:dump().players[1].lastClass=="Road",
 "outside-authored-zone position breaks continuity; never fills a transition")
m:forget(1)
check(m.Models[1]==nil and m.Observed[1]==nil and m:dump().players[1]==nil,
 "disconnect removes player model; no DataStore or unbounded departed-player set")
local noZones=Shadow.new(cfg,nil,Markov)
check(not noZones:observe(2,0,4,0,0) and noZones:dump().authoredZoneCount==0,
 "missing authored zones fail closed without invented geography")
-- Exercise the real service branch: a root is handed to the model only AFTER
-- the existing bounded sight/thermal sensor has selected living prey.
local R=VitriolRequire("Bootstrap").ensure()
local player=R.Players:addPlayer("ShadowWitness",8421)
local root=player.Character:FindFirstChild("HumanoidRootPart")
local braid=R.Creature.creatures[R.Creature.order[1]]
braid.X,braid.Y,braid.Z=-40,8,-56
R.Time.phase="Night"
R.Creature.Shadow=Shadow.new(cfg,map,Markov,tags)
R.Creature.Navigation={hit=function()return nil end,clear=function()return true end,
 route=function(_,_,_,x,z)return x,z end}
R.Creature.Noise=nil
root.Position={X=-90,Y=4,Z=-56}
R.Creature:think(.2)
R.Time.elapsedTotal=R.Time.elapsedTotal+1
root.Position={X=0,Y=4,Z=-56}
R.Creature:think(.2)
check(R.Creature.Shadow.Transitions==1 and R.Creature.Shadow.Models[player.UserId]:count(4,2)==1,
 "real CreatureService supplies ONLY genuinely sensed prey to shadow location observer")
R.Time.elapsedTotal=R.Time.elapsedTotal+1
root.Position={X=900,Y=4,Z=900}
R.Creature:think(.2)
local beforeHidden=R.Creature.Shadow:dump()
check(beforeHidden.transitions==1 and beforeHidden.players[1].currentlySensed==false
 and beforeHidden.steers==false and R.Creature:aiDump().shadowPrediction.postureObserved==false,
 "hidden live root does not train shadow; server-only AI dump labels no steering/posture")
R.Time.elapsedTotal=R.Time.elapsedTotal+1
root.Position={X=-90,Y=4,Z=-56}
R.Creature:think(.2)
check(R.Creature.Shadow.Transitions==1,
 "reacquisition after hidden travel does not learn a fabricated crossing")
R.Players:removePlayer(player)
check(R.Creature.Shadow.Models[player.UserId]==nil,
 "service PlayerRemoving clears per-player shadow transition model")
check(SIM.COUNTERS.runtimeInstanceNew==0,"shadow observation creates zero runtime Instances")
return SESSION
