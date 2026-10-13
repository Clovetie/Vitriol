-- Real service/Bootstrap path for per-run repairs and deliberate Night sabotage.
SESSION={passed=0,failed=0}
local function check(ok,msg)
 if ok then SESSION.passed=SESSION.passed+1; print("PASS "..msg)
 else SESSION.failed=SESSION.failed+1; print("FAIL "..msg) end
end
local R=VitriolRequire("Bootstrap").ensure()
local t=R.Time
local player=R.Players:addPlayer("LightTech",71001)
local helper=R.Players:addPlayer("Helper",71002)
local function move(person,part)
 person.Character:FindFirstChild("HumanoidRootPart").Position=part.Position
end
local function finish()
 SIM.step(3.15);SIM.step(.55);SIM.step(.55)
 check(R.Prep:snapshot()==nil and R.Remotes.time.lastAll[9].stage=="clear",
  "shared vote, fade and Day charge complete before repair becomes visible")
end
local rules=VitriolRequire("PrepRules")
check(rules.cost("RepairGarageLight",0,210,210)==16
 and math.abs(rules.cost("RepairGarageLight",2,11,11)-14*11/210)<.001,
 "garage repair charges sixteen main seconds; helpers and fast Day scale net cost")
check(R.DayPrep.garageIntact and not R.DayPrep.powered and R.Floodlight.repaired==false,
 "new run starts with working unpowered garage and unprepared station")
move(player,SIM.stationSwitch)
SIM.repairPrompt.Triggered:Fire(player);finish()
check(R.Floodlight.repaired and not R.Floodlight.broken,"station repair succeeds once")
move(player,SIM.fuelCan);SIM.takeFuel.Triggered:Fire(player);finish()
move(player,SIM.generator);SIM.powerLamp.Triggered:Fire(player);finish()
check(R.DayPrep.powered and R.DayPrep.garageIntact and SIM.lampPart.PoweredLight.Enabled,
 "original garage fueling still works before Braid sabotage")
t.phase="Night";R.DayPrep:onPhaseChanged("Night");R.Floodlight:onPhaseChanged("Night")
check(R.Floodlight.repaired and SIM.stationBeam.Enabled,
 "repaired station illuminates at Night")
local braid=R.Creature.creatures[R.Creature.order[1]]
move(player,SIM.fuelCan);move(helper,SIM.fuelCan)
player.Character:FindFirstChild("HumanoidRootPart").Position={X=350,Y=2,Z=350}
helper.Character:FindFirstChild("HumanoidRootPart").Position={X=350,Y=2,Z=351}
-- Once the Braid reaches the bell, it must stop camping the same fixed point
-- and seek the next light (garage), without waiting for ring timeout.
R.DayPrep.bellRinging=true;R.DayPrep.bellStarted=999
braid.X,braid.Z=SIM.bellLever.Position.X,SIM.bellLever.Position.Z
R.Creature:think(.2)
check(braid.BellInvestigatedAt==999 and braid.TargetX==SIM.generator.Position.X,
 "bell investigation completes on arrival; Braid keeps moving to next lure")
R.DayPrep.bellRinging=false
braid.X,braid.Z=SIM.generator.Position.X+11,SIM.generator.Position.Z
R.Creature:think(.2)
check(braid.LightAttackKind=="GarageLight" and R.DayPrep.powered,
 "Night Braid deliberately targets powered garage feed when prey is distant")
-- Interruption by nearby prey clears progress; accepted close chase wins.
player.Character:FindFirstChild("HumanoidRootPart").Position={X=braid.X+2,Y=2,Z=braid.Z+2}
R.Creature:think(.2)
check(not braid.LightAttackKind and R.DayPrep.powered,
 "nearby player interrupts sabotage and retains chase priority")
player.Character:FindFirstChild("HumanoidRootPart").Position={X=350,Y=2,Z=350}
for _=1,11 do R.Creature:think(.2) end
check(not R.DayPrep.garageIntact and not R.DayPrep.powered
 and SIM.generator:GetAttribute("Broken") and not SIM.lampPart.PoweredLight.Enabled,
 "two-second deliberate garage attack breaks the lamp/feed exactly once")
check(not R.DayPrep:damageGarage(),"broken garage cannot be damaged repeatedly")
-- The garage lure is gone; the station is the next lit target.
braid.X,braid.Z=SIM.stationFixture.Position.X+11,SIM.stationFixture.Position.Z
for _=1,11 do R.Creature:think(.2) end
check(R.Floodlight.broken and not R.Floodlight.repaired and not SIM.stationBeam.Enabled,
 "separate dedicated station attack breaks station until another repair")
R.DayPrep:onPhaseChanged("Dawn");R.Floodlight:onPhaseChanged("Dawn")
check(not R.DayPrep.garageIntact and R.Floodlight.broken,
 "both breakages persist across Dawn, not DataStore")
t:seekToPhase("Day");R.DayPrep:onPhaseChanged("Day");R.Floodlight:onPhaseChanged("Day")
move(player,SIM.fuelCan);SIM.takeFuel.Triggered:Fire(player);finish()
move(player,SIM.generator)
check(not SIM.powerLamp.Enabled and SIM.repairGarage.Enabled and player:GetAttribute("CarryFuelCan"),
 "fuel pickup is allowed but powering a BROKEN garage lamp waits for repair")
check(not R.DayPrep:power(player) and player:GetAttribute("CarryFuelCan"),
 "broken feed cannot spend the player's can or bypass repair")
move(helper,SIM.generator)
local before=t:dayRemaining();local at=SIM.time()
SIM.repairGarage.Triggered:Fire(player);SIM.helpGarage.Triggered:Fire(helper)
check(R.Prep:snapshot() and R.Prep:snapshot().action=="RepairGarageLight"
 and SIM.helpGarage.Enabled and not R.DayPrep.garageIntact,
 "garage prompt starts co-op vote with no premature repair")
finish()
local paid=(before-t:dayRemaining())-(SIM.time()-at)
check(R.DayPrep.garageIntact and not SIM.repairGarage.Enabled
 and SIM.powerLamp.Enabled and math.abs(paid-15)<.02,
 "repair costs sixteen minus helper second and unlocks garage fueling")
SIM.powerLamp.Triggered:Fire(player);finish()
check(R.DayPrep.powered and not player:GetAttribute("CarryFuelCan"),
 "after repair, existing fuel can can power garage again")
move(player,SIM.stationSwitch);SIM.repairPrompt.Triggered:Fire(player);finish()
check(R.Floodlight.repaired and not R.Floodlight.broken,
 "station also becomes repairable again after Braid damage")
R.DayPrep:onPhaseChanged("Dawn");R.Floodlight:onPhaseChanged("Dawn")
check(R.DayPrep.garageIntact and R.Floodlight.repaired
 and not SIM.repairPrompt.Enabled and not SIM.repairGarage.Enabled,
 "both structural repairs outlast Dawn/death until new sabotage")
check(SIM.COUNTERS.runtimeInstanceNew==0,"entire loop reused preauthored instances only")
return SESSION
