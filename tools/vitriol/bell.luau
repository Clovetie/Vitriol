-- Focused one-use church-bell day preparation; the main session is at Lua's local limit.
SESSION = {passed=0, failed=0}
function bellCheck(ok, message)
	if ok then SESSION.passed = SESSION.passed + 1; print("PASS  " .. message)
	else SESSION.failed = SESSION.failed + 1; print("FAIL  " .. message) end
end
BE = {}
BE.runtime = VitriolRequire("Bootstrap").ensure()
BE.time, BE.prep = BE.runtime.Time, BE.runtime.DayPrep
BE.players = game:GetService("Players")
BE.player = BE.players:addPlayer("BellKeeper")
BE.rival = BE.players:addPlayer("BellRival")
BE.root = BE.player.Character:FindFirstChild("HumanoidRootPart")
BE.rivalRoot = BE.rival.Character:FindFirstChild("HumanoidRootPart")
BE.time.phase, BE.time.elapsedTotal = "Day", 100
BE.root.Position = {X=0,Y=3,Z=0}
BE.rivalRoot.Position = {X=119,Y=3,Z=-136}
bellCheck(not BE.prep:primeBell(BE.player), "a forged distant church-bell activation is rejected")
BE.root.Position = {X=119,Y=3,Z=-136}
bellCheck(BE.prep:primeBell(BE.player) and BE.prep.bellArmed
	and BE.prep.BellLever:GetAttribute("Armed") and not BE.prep.BellPrompt.Enabled,
	"one living player primes the preauthored bell by day")
bellCheck(not BE.prep:primeBell(BE.player) and not BE.prep:primeBell(BE.rival),
	"duplicate/two-player priming cannot mint another Night signal")
bellCheck(not BE.prep.bellRang and not BE.prep.BellLight.Enabled
	and (SIM.bellSound.playCount or 0) == 0,
	"Day priming does not prematurely ring or light the bell")
-- The bell is a world preparation, not a carried Tool: death does not erase it.
BE.prep:drop(BE.player)
bellCheck(BE.prep.bellArmed, "losing carried inventory does not disarm the world bell")
BE.root.Position = {X=0,Y=3,Z=0}
bellCheck(BE.prep:pickup(BE.player) and BE.prep:power(BE.player),
	"the previously accepted fuel/lamp can coexist with the bell choice")
BE.time.phase = "Night"
BE.prep:onPhaseChanged("Night")
bellCheck(BE.prep.bellAt == 103 and not BE.prep.BellPrompt.Enabled
	and not BE.prep:primeBell(BE.rival), "Night schedules one delayed ring and refuses re-priming")
BE.time.elapsedTotal = 102.9
BE.prep:_tickBell()
bellCheck(not BE.prep.bellRang and (SIM.bellSound.playCount or 0) == 0
	and BE.prep:signal() == BE.prep.Generator.Position,
	"before the ring, the existing generator lure keeps its behavior")
BE.time.elapsedTotal = 103
BE.prep:_tickBell()
BE.bellLure, BE.priority = BE.prep:signal()
bellCheck(BE.prep.bellRang and BE.prep.bellRinging
	and BE.prep.BellLight.Enabled and BE.prep.BellPart:GetAttribute("Ringing")
	and SIM.bellSound.playCount == 1 and BE.bellLure == BE.prep.BellLever.Position
	and BE.priority == 30,
	"one Sound:Play plays the user-supplied three-strike clip and starts a visible lure")
BE.prep:_tickBell()
bellCheck(SIM.bellSound.playCount == 1, "think/slow cadence cannot replay the three-strike clip")
BE.time.elapsedTotal = 103.5
BE.prep:_tickBell()
BE.off1 = not BE.prep.BellLight.Enabled
BE.time.elapsedTotal = 104
BE.prep:_tickBell()
BE.on2 = BE.prep.BellLight.Enabled
BE.time.elapsedTotal = 104.5
BE.prep:_tickBell()
BE.off2 = not BE.prep.BellLight.Enabled
BE.time.elapsedTotal = 105
BE.prep:_tickBell()
BE.on3 = BE.prep.BellLight.Enabled
BE.time.elapsedTotal = 105.5
BE.prep:_tickBell()
bellCheck(BE.off1 and BE.on2 and BE.off2 and BE.on3 and not BE.prep.BellLight.Enabled,
	"three authored light pulses match the single three-strike audio clip")
BE.runtime.Creature:reconcile()
BE.creature = BE.runtime.Creature.creatures[1]
BE.creature.X, BE.creature.Z = 0, 0
BE.root.Position = {X=-100,Y=3,Z=-56}
BE.rivalRoot.Position = {X=-110,Y=3,Z=-56}
BE.runtime.Creature:think(0.2)
bellCheck(BE.creature.TargetX == BE.prep.BellLever.Position.X
	and BE.creature.TargetZ == BE.prep.BellLever.Position.Z,
	"distant Braid follows the church lure over the powered garage")
BE.root.Position = {X=BE.creature.X+5,Y=BE.creature.Y,Z=BE.creature.Z+5}
BE.runtime.Creature:think(0.2)
bellCheck(BE.creature.TargetX == BE.root.Position.X,
	"a nearby living player overrides the decoy without changing chase pace")
BE.root.Position = {X=-100,Y=3,Z=-56}
BE.time.elapsedTotal = 115
BE.prep:_tickBell()
BE.returnLure, BE.returnPriority = BE.prep:signal()
bellCheck(not BE.prep.bellRinging and not BE.prep.BellLight.Enabled
	and BE.returnLure == BE.prep.Generator.Position and BE.returnPriority == 70,
	"after twelve seconds the bell stops luring and the old garage choice resumes")
BE.runtime.Creature:think(0.2)
bellCheck(BE.creature.TargetX == BE.prep.Generator.Position.X,
	"post-bell distant Braid still responds to the previously accepted generator")
BE.time.phase = "Dawn"
BE.prep:onPhaseChanged("Dawn")
bellCheck(not BE.prep.bellArmed and not BE.prep.bellRang and BE.prep.BellPrompt.Enabled
	and not BE.prep.BellLight.Enabled and SIM.bellSound.playCount == 1
	and (SIM.bellSound.stopCount or 0) == 1,
	"Dawn resets exactly one authored use without replaying audio")
BE.rivalRoot.Position = {X=119,Y=3,Z=-136}
BE.runtime.Health.states[BE.rival.UserId].dead = true
bellCheck(not BE.prep:primeBell(BE.rival), "a dead player cannot forge a nearby bell prime")
BE.runtime.Health.states[BE.rival.UserId].dead = false
bellCheck(BE.prep:primeBell(BE.rival), "another living player can prime the restocked bell next day")
bellCheck(SIM.COUNTERS.runtimeInstanceNew == 0,
	"bell cue and lure create no runtime Vitriol UI/game Instances")
return SESSION
