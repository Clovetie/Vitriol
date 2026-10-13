-- Separate scenario: the main session fixture is at Lua's 200-local limit.
SESSION = { passed = 0, failed = 0 }
function prepCheck(ok, message)
	if ok then SESSION.passed = SESSION.passed + 1; print("PASS  " .. message)
	else SESSION.failed = SESSION.failed + 1; print("FAIL  " .. message) end
end
DP = {}
DP.runtime = VitriolRequire("Bootstrap").ensure()
DP.time = DP.runtime.Time
DP.health = DP.runtime.Health
DP.prep = DP.runtime.DayPrep
DP.players = game:GetService("Players")
DP.player = DP.players:addPlayer("FuelOwner")
DP.rival = DP.players:addPlayer("FuelRival")
DP.ownerRoot = DP.player.Character:FindFirstChild("HumanoidRootPart")
DP.rivalRoot = DP.rival.Character:FindFirstChild("HumanoidRootPart")
DP.time.phase = "Day"
DP.ownerRoot.Position = { X = 0, Y = 0, Z = 0 }
DP.rivalRoot.Position = { X = 0, Y = 0, Z = 0 }
prepCheck(DP.prep:pickup(DP.player) and DP.player:GetAttribute("CarryFuelCan") == true,
	"one authored fuel can becomes server-owned inventory")
prepCheck(not DP.prep:pickup(DP.player) and not DP.prep:pickup(DP.rival)
	and DP.rival:GetAttribute("CarryFuelCan") == false,
	"duplicate pickup and two-player contention cannot mint another can")
prepCheck(not DP.prep:power(DP.rival) and DP.prep:power(DP.player)
	and DP.prep.Lamp.Enabled and DP.player:GetAttribute("CarryFuelCan") == false,
	"only the owner can spend the can to power the preauthored lamp")
prepCheck(not DP.prep:power(DP.player), "one can cannot power the lamp twice")
DP.time.phase = "Night"
prepCheck(DP.prep:signal() ~= nil and not DP.prep:pickup(DP.rival) and not DP.prep:power(DP.rival),
	"night exposes a generator lure but rejects pickups/interaction")
DP.runtime.Creature:reconcile()
DP.creature = DP.runtime.Creature.creatures[1]
DP.ownerRoot.Position = { X = 200, Y = 0, Z = 0 }
DP.rivalRoot.Position = { X = 210, Y = 0, Z = 0 }
DP.runtime.Creature:think(0.2)
prepCheck(DP.creature ~= nil and DP.creature.TargetX == DP.prep.Generator.Position.X,
	"generator lure diverts a distant Braid during night")
DP.ownerRoot.Position = { X = DP.creature.X + 3, Y = DP.creature.Y, Z = DP.creature.Z + 3 }
DP.runtime.Creature:think(0.2)
prepCheck(DP.creature.TargetX == DP.ownerRoot.Position.X,
	"nearby prey overrides the lure and retains the approved chase")
DP.time.phase = "Dawn"
DP.prep:onPhaseChanged("Dawn")
prepCheck(not DP.prep.Lamp.Enabled and DP.prep.available and DP.prep.CanPrompt.Enabled,
	"the lamp goes out and the authored can restocks on dawn")
DP.time.phase = "Day"
DP.rivalRoot.Position = { X = 0, Y = 0, Z = 0 }
prepCheck(DP.prep:pickup(DP.rival), "the second player may claim the restocked can")
DP.health:onDeath(DP.health.states[DP.rival.UserId])
prepCheck(DP.prep.available and DP.prep.owner == nil and not DP.rival:GetAttribute("CarryFuelCan"),
	"death clears the inventory and returns the single pickup")
DP.ownerRoot.Position = { X = 40, Y = 0, Z = 0 }
prepCheck(not DP.prep:pickup(DP.player), "forged distant interaction fails server range check")
DP.ownerRoot.Position = { X = 0, Y = 0, Z = 0 }
prepCheck(DP.prep:pickup(DP.player), "the recovered can can be claimed again")
DP.players:removePlayer(DP.player)
prepCheck(DP.prep.available and DP.prep.owner == nil,
	"disconnect returns the only unspent can to the authored pickup")
prepCheck(SIM.COUNTERS.runtimeInstanceNew == 0, "no Vitriol UI or gameplay Instances were created during Play")
return SESSION
