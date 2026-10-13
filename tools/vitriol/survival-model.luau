-- Pure M6 survival math; deliberately NOT connected to game Bootstrap.
TESTS={passed=0,failed=0}
local function check(ok,msg)
 if ok then TESTS.passed=TESTS.passed+1;print("PASS  "..msg)
 else TESTS.failed=TESTS.failed+1;warn("FAIL  "..msg) end
end
local function approx(a,b,tol)return math.abs(a-b)<(tol or 1e-8) end
local config=VitriolRequire("SurvivalConfig")
local Model=VitriolRequire("SurvivalModel")
local s=Model.new(config)
check(s.state.thirst==0 and s.state.hunger==0 and s.state.stamina==config.Stamina.Max,
 "new server-owned ledger starts sated with full stamina, no UI or health write")
local thirst,hunger=s:rates("Walking")
check(approx(thirst,.8) and approx(hunger,.42),"walking rates use authored real-minute config")
check(s:rates("Teleporting")==nil,"unknown client-claimed activity cannot receive a drain rate")
local original=s.state.thirst
for _,bad in ipairs({0/0,math.huge,-1,3601}) do
 local result,err=s:step(bad,"Walking")
 check(result==nil and err=="invalid-dt" and s.state.thirst==original,
  "invalid/non-finite/too-large dt is refused without changing the ledger")
end
local result,err=s:step(1,"Teleporting")
check(result==nil and err=="invalid-activity" and s.state.thirst==original,
 "unrecognized activity cannot mutate server meters")
result=s:step(60,"Walking")
check(result and approx(result.thirst,.8) and approx(result.hunger,.42),
 "sixty real seconds add exactly one authored walking minute")
local many=Model.new(config)
local one=Model.new(config)
many:step(60,"Walking")
for i=1,60 do one:step(1,"Walking") end
check(approx(one.state.thirst,many.state.thirst) and approx(one.state.hunger,many.state.hunger),
 "large but valid dt is integrated in bounded one-second segments")
local nine=Model.new(config)
for minute=1,9 do nine:step(60,"Walking") end
check(approx(nine.state.thirst,7.2,1e-6) and approx(nine.state.hunger,3.78,1e-6),
 "pacing mismatch is visible: current config reaches only 7.2 thirst, NOT Parched, after 9 walking minutes")
local sixteen=Model.new(config)
for minute=1,16 do sixteen:step(60,"Sprinting") end
check(approx(sixteen.state.thirst,33.6,1e-6) and approx(sixteen.state.hunger,15.2,1e-6)
 and not sixteen:collapseCandidate(100),
 "even sixteen continuous baseline sprinting minutes cannot approach the documented collapse time")
local couple=Model.new(config)
couple.state.hunger=66
local dry0=couple:rates("Walking")
couple.state.hunger=70
local dryMid=couple:rates("Walking")
couple.state.hunger=74
local dryMax=couple:rates("Walking")
check(approx(dry0,.8) and approx(dryMid,.88) and approx(dryMax,.96),
 "hunger smoothly raises thirst once, 0→10→20%; mirrored Modifier is NOT multiplied twice")
couple.state.hunger=0
couple.state.thirst=70
local _,hunMid=couple:rates("Walking")
couple.state.thirst=74
local _,hunHigh=couple:rates("Walking")
check(approx(hunMid,.42*1.075) and approx(hunHigh,.42*1.15),
 "thirst smoothly raises hunger once to the authored 15% maximum")
local wet=Model.new(config)
local tw,hw=wet:rates("Walking",{bleeding=true,hot=true,cold=true,immersed=true})
check(approx(tw,.8*1.35*1.25*1.10*.90)
 and approx(hw,.42*1.10*1.05*1.25),
 "environmental and wound multipliers compose, water affects thirst only")
local timed=Model.new(config)
check(not timed:applyTimed("Dry") and not timed:applyTimed("Unknown")
 and timed:applyTimed("Sick") and timed.state.timed.Sick==90,
 "only declared timed debuffs can be activated by a future server owner")
local sickT,sickH=timed:rates("Resting")
check(approx(sickT,.55*1.5) and approx(sickH,.30*1.5),
 "Sick's authored data scales both need rates, no special-case service branch")
timed:step(90,"Resting")
check(timed.state.timed.Sick==nil and approx(timed:rates("Resting"),.55),
 "Sick expires on its declared timer without a new scheduler")
local expiring=Model.new(config)
expiring.state.timed.Sick=.25 -- natural remaining time near the end of a 90s effect
expiring:step(1,"Resting")
check(approx(expiring.state.thirst,.55*(.25*1.5+.75)/60,1e-9)
 and approx(expiring.state.hunger,.30*(.25*1.5+.75)/60,1e-9)
 and expiring.state.timed.Sick==nil,
 "mid-tick expiry charges Sick drain for .25s only, not the whole second")
local layered=Model.new(config)
layered.state.thirst=100;layered.state.hunger=80
local effects,active=layered:effects({bleeding=true})
local seen={}
for _,name in ipairs(active) do seen[name]=true end
local mouth=0
for _,cue in ipairs(effects.AudioCues) do if cue=="dry_mouth" then mouth=mouth+1 end end
check(seen.Dry and seen.Parched and seen.Desiccated and seen.Peckish and seen.Starved and seen.Bleeding
 and approx(effects.WalkSpeed,.97*.88*.70*.98*.85)
 and approx(effects.ScentScale,1.5*2)
 and mouth==1,
 "data debuffs compose multiplicatively; duplicate cues only play once")
check(layered:collapseCandidate(100) and not Model.new(config):collapseCandidate(100),
 "compound collapse threshold is evaluated from BOTH needs; never auto-applied as a health write")
layered.state.thirst=60;layered.state.hunger=60
check(layered:collapseCandidate(14.9) and not layered:collapseCandidate(15),
 "low health requires both meters at 60 and strictly below the authored health threshold")
local flexibleConfig={}
for k,v in pairs(config) do flexibleConfig[k]=v end
flexibleConfig.Debuffs={}
for k,v in pairs(config.Debuffs) do flexibleConfig.Debuffs[k]=v end
flexibleConfig.Debuffs.Custom={Trigger={meter="thirst",at=30},WalkSpeed=.5,AudioCues={"dry_mouth","new_cue"},Priority=55}
local flexible=Model.new(flexibleConfig)
flexible.state.thirst=40
local changed,names=flexible:effects()
check(approx(changed.WalkSpeed,.5) and names[1]=="Custom"
 and changed.AudioCues[1]=="dry_mouth" and changed.AudioCues[2]=="new_cue",
 "a NEW configured debuff takes effect without an if-chain")
flexibleConfig.Debuffs.Custom=nil
changed,names=flexible:effects()
check(approx(changed.WalkSpeed,1) and #names==0,
 "removing that debuff data removes its effects without changing model code")
local eater=Model.new(config)
eater.state.thirst=80;eater.state.hunger=90
local checked,checkedErr=eater:consumableDefinition("CleanWater")
check(checked and checkedErr==nil and checked.seconds==2 and eater.state.thirst==80,
 "pre-commit item inspection returns authored metadata without mutating the need ledger")
for _,item in ipairs({"MadeUp","Bandage","Medkit"}) do
 local denied,why=eater:applyVerifiedConsumable(item,.1)
 check(denied==nil and why==(item=="MadeUp" and "invalid-item" or "health-managed")
  and eater.state.thirst==80 and eater.state.hunger==90,
  "unknown/health-managed item cannot mutate needs or heal through the pure model")
end
for _,roll in ipairs({-0.01,1,math.huge,0/0}) do
 local denied,why=eater:applyVerifiedConsumable("DirtyWater",roll)
 check(denied==nil and why=="invalid-roll" and eater.state.thirst==80,
  "invalid/non-finite server sick roll cannot consume or mutate need meters")
end
local denied,why=eater:applyVerifiedConsumable("DirtyWater")
check(denied==nil and why=="invalid-roll" and eater.state.thirst==80,
 "probabilistic item requires an explicit server-owned roll")
local drink=eater:applyVerifiedConsumable("CleanWater")
check(drink and drink.thirst==45 and drink.hunger==90 and not drink.sick
 and drink.seconds==2 and drink.noiseAir==.15,
 "verified clean water restores thirst only; timing/noise are metadata, not side effects")
local dirty=eater:applyVerifiedConsumable("DirtyWater",.35)
check(dirty and dirty.thirst==20 and not dirty.sick and eater.state.timed.Sick==nil,
 "at the 35 percent boundary dirty water does NOT secretly add Sick")
local poisoned=eater:applyVerifiedConsumable("DirtyWater",.349)
check(poisoned and poisoned.thirst==0 and poisoned.sick and eater.state.timed.Sick==90,
 "below the boundary dirty water restores and starts authored Sick timer")
local meal=eater:applyVerifiedConsumable("CannedFood")
check(meal and meal.hunger==50 and not meal.sick and eater.state.timed.Sick==90,
 "food restores hunger only; a safe meal does not erase an existing Sick timer")
local fresh=Model.new(config)
local raw=fresh:applyVerifiedConsumable("RawMeat",.5)
check(raw and not raw.sick and fresh.state.hunger==0,
 "raw meat at its 50 percent boundary does not cause Sick")
local spoiled=fresh:applyVerifiedConsumable("SpoiledFood",.999)
check(spoiled and spoiled.sick and fresh.state.timed.Sick==90,
 "spoiled food always causes Sick under a valid server roll")
local consumptionConfig={}
for key,value in pairs(config) do consumptionConfig[key]=value end
consumptionConfig.Consumables={}
for key,value in pairs(config.Consumables) do consumptionConfig.Consumables[key]=value end
consumptionConfig.Consumables.TestSnack={hunger=-9,sickChance=0,seconds=1,noiseAir=.1}
local newSnack=Model.new(consumptionConfig)
newSnack.state.hunger=20
check(newSnack:applyVerifiedConsumable("TestSnack").hunger==11,
 "new consumable data is handled without adding a named model branch")
consumptionConfig.Consumables.TestSnack=nil
local removed= newSnack:applyVerifiedConsumable("TestSnack")
check(removed==nil and newSnack.state.hunger==11,
 "removing consumable data prevents further application")
consumptionConfig.Consumables.BadDrink={thirst=-4,sickChance=0,seconds=0,noiseAir=.1}
local invalidEntry,invalidWhy=newSnack:consumableDefinition("BadDrink")
check(invalidEntry==nil and invalidWhy=="invalid-consumable"
 and newSnack:applyVerifiedConsumable("BadDrink")==nil and newSnack.state.hunger==11,
 "invalid action metadata fails before a timed inventory commit or meter mutation")
local divergent={}
for key,value in pairs(config) do divergent[key]=value end
divergent.Stamina={}
for key,value in pairs(config.Stamina) do divergent.Stamina[key]=value end
divergent.Stamina.ExhaustionDuration=7
local isConsistent=pcall(function() Model.new(divergent) end)
check(not isConsistent,
 "duplicate Exhausted durations fail closed instead of silently choosing 6 or 7 seconds")
local exhaustion=Model.new(config)
exhaustion.state.stamina=14 -- exactly one second of sprint remains
exhaustion:step(4,"Sprinting")
check(exhaustion.state.stamina==0 and approx(exhaustion.state.emptyStaminaSeconds,3)
 and exhaustion.state.timed.Exhausted==nil,
 "exactly three seconds empty does not yet trigger the strictly >3s debuff")
local exhaustionSplit=Model.new(config)
exhaustionSplit.state.stamina=14
for i=1,8 do exhaustionSplit:step(.5,"Sprinting") end
check(approx(exhaustionSplit.state.emptyStaminaSeconds,exhaustion.state.emptyStaminaSeconds)
 and exhaustionSplit.state.timed.Exhausted==nil,
 "stamina depletion counts only actual zero-time regardless of tick partition")
exhaustion:step(.01,"Sprinting");exhaustionSplit:step(.01,"Sprinting")
local tiredEffects,tiredNames=exhaustion:effects()
check(approx(exhaustion.state.timed.Exhausted,config.Stamina.ExhaustionDuration)
 and approx(exhaustionSplit.state.timed.Exhausted,config.Stamina.ExhaustionDuration)
 and approx(tiredEffects.WalkSpeed,.75) and tiredNames[1]=="Exhausted",
 "past three seconds at zero starts the declared six-second exhausted effect")
exhaustion:step(6,"Sprinting")
check(exhaustion.state.stamina==0 and exhaustion.state.timed.Exhausted==6,
 "still demanding sprint at zero cannot recover or silently drop exhausted on expiry")
exhaustion:step(6,"Resting")
check(exhaustion.state.stamina>0 and exhaustion.state.emptyStaminaSeconds==0
 and exhaustion.state.timed.Exhausted==nil,
 "rest resets zero-stamina counter and timed exhaustion eventually clears")
flexibleConfig.Debuffs.Exhausted=nil
flexible.state.stamina=0
flexible:step(4,"Sprinting")
check(flexible.state.timed.Exhausted==nil,
 "removing Exhausted from debuff data disables its effect without model edits")
local runner=Model.new(config)
runner:step(20,"Sprinting")
check(runner.state.stamina==0 and runner.state.sinceSprint==0,
 "continuous sprint cannot drive stamina below zero or regenerate at zero")
runner:step(1,"Resting")
check(runner.state.stamina==0,"stamina does not regenerate before authored post-sprint delay")
runner:step(1,"Resting")
check(runner.state.stamina>0 and runner.state.stamina<9,
 "a delay ending MID-tick regenerates only the eligible fraction, not a whole second")
local half=Model.new(config)
half.state.stamina=0;half.state.sinceSprint=1
half:step(1,"Resting")
local split=Model.new(config)
split.state.stamina=0;split.state.sinceSprint=1
split:step(.5,"Resting");split:step(.5,"Resting")
check(half.state.stamina>0 and half.state.stamina<4.5
 and approx(half.state.stamina,split.state.stamina,1e-4),
 "post-sprint delay credits only the second half-second independent of dt partition")
local recovery=Model.new(config)
recovery.state.stamina=0;recovery.state.sinceSprint=2
recovery:step(1,"Resting")
local healthyRegen=recovery.state.stamina
local needy=Model.new(config)
needy.state.thirst=100;needy.state.hunger=100
needy.state.stamina=0;needy.state.sinceSprint=2
needy:step(1,"Resting")
check(needy.state.stamina>0 and needy.state.stamina<healthyRegen,
 "both needs and data debuffs slow stamina recovery without a client authority path")
print("Survival model: "..TESTS.passed.." passed, "..TESTS.failed.." failed")
return TESTS
