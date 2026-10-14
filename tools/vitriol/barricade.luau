-- Standalone fixture: main session already nears Lua's local-variable cap.
SESSION = { passed = 0, failed = 0 }
function barricadeCheck(ok, message)
	if ok then SESSION.passed = SESSION.passed + 1; print("PASS  " .. message)
	else SESSION.failed = SESSION.failed + 1; print("FAIL  " .. message) end
end
BX = {}
BX.runtime = VitriolRequire("Bootstrap").ensure()
BX.time = BX.runtime.Time
BX.barrier = BX.runtime.Barricade
BX.players = game:GetService("Players")
BX.player = BX.players:addPlayer("Boarder")
BX.root = BX.player.Character:FindFirstChild("HumanoidRootPart")
BX.time.phase = "Day"
BX.root.Position = { X = -100, Y = 2, Z = -56 }
barricadeCheck(not BX.barrier:board(BX.player), "forged out-of-range board request is rejected")
BX.root.Position = { X = -66, Y = 2.4, Z = -56 }
barricadeCheck(BX.barrier:board(BX.player) and BX.barrier.Gate.CanCollide
	and BX.barrier.Gate.CanQuery and BX.barrier.Gate:GetAttribute("Barricaded"),
	"day boarding activates the preauthored solid garage gate")
BX.rival = BX.players:addPlayer("SecondBoarder")
BX.rival.Character:FindFirstChild("HumanoidRootPart").Position = { X = -66, Y = 2.4, Z = -56 }
barricadeCheck(not BX.barrier:board(BX.player) and not BX.barrier:board(BX.rival) and BX.barrier.spent,
	"duplicate and competing board requests cannot mint another plank set")
barricadeCheck(BX.barrier:crossing(-62.1,-56,-61.6,-56)
	and BX.barrier:crossing(-61.6,-56,-62.1,-56)
	and not BX.barrier:crossing(-62.1,-20,-61.6,-20),
	"only paths through the service-bay opening are obstructed")
barricadeCheck(BX.barrier:pressing(-60,-56,-64,-56)
	and BX.barrier:pressing(-64,-56,-60,-56)
	and not BX.barrier:pressing(-40,-56,-64,-56)
	and not BX.barrier:pressing(-60,-56,-59,-56)
	and not BX.barrier:pressing(-60,-14,-64,-14),
	"breach pressure needs a nearby opposite-side target through the actual gate")
BX.fakeGround = {Name = "Ground"}
barricadeCheck(BX.barrier:pressing(-51,-56,-68,-56,{BX.barrier.Gate},1)
	and BX.barrier:pressing(-72,-56,-55,-56,{BX.barrier.Gate},1)
	and not BX.barrier:pressing(-51,-56,-68,-56,{BX.fakeGround},1)
	and not BX.barrier:pressing(-51,-56,-68,-56,{BX.barrier.Gate},0)
	and not BX.barrier:pressing(-51,-56,-49,-56,{BX.barrier.Gate},1)
	and not BX.barrier:pressing(-51,-14,-68,-14,{BX.barrier.Gate},1),
	"farther core braces only through a real gate foothold and an across-bay target")
BX.probe = VitriolRequire("Locomotion").new({TendrilCount=8}, {
	Workspace = {Raycast = function()
		return {Instance=BX.barrier.Gate, Position={X=-61.2,Y=7,Z=-56},
			Normal={X=1,Y=0,Z=0}}
	end},
})
BX.probe.DirectionX[1], BX.probe.DirectionY[1], BX.probe.DirectionZ[1] = -1, 0, 0
barricadeCheck(BX.probe:_tryAnchor(1,-51,7,-56,14)
	and BX.probe.AnchorCount == 1 and BX.probe.AnchorPart[1] == BX.barrier.Gate,
	"actual Locomotion raycast caches the authored gate beneath an anchor")
BX.time.phase = "Night"
barricadeCheck(not BX.barrier:board(BX.player) and BX.barrier.Prompt.Enabled
	and BX.barrier.Prompt.ActionText == "Throw gate open (loud)",
	"night construction is rejected but the emergency exit remains usable")
BX.runtime.Creature:reconcile()
BX.creature = BX.runtime.Creature.creatures[1]
barricadeCheck(BX.creature ~= nil and BX.creature.Barricade == BX.barrier,
	"the authoritative creature is wired to the same barrier")
BX.creature.X, BX.creature.Z = -60, -56
BX.root.Position = { X = -64, Y = BX.creature.Y, Z = -56 }
BX.creature.canPrepareChomp = function() return true end
BX.runtime.Creature:think(0.2)
barricadeCheck(BX.creature.AttackPhase == nil,
	"the Braid cannot start a chomp through the boarded entry")
BX.creature.X, BX.creature.Z, BX.creature.TargetX = -62.1, -56, -60
BX.creature.Locomotion.step = function() return 1, 0, 0, 0, 1, 0 end
BX.creature:step(1/60)
barricadeCheck(BX.creature.X == -62.1 and BX.barrier.pressure > 0,
	"actual CreatureCore frame blocks forward translation and begins breach pressure")
-- Reproduce the Play symptom: anchored, foot-led Braid stops SHORT of the
-- board, so its root has no forward crossing delta on the next frame.
BX.creature.X, BX.creature.Z = -60, -56
BX.root.Position = { X = -64, Y = BX.creature.Y, Z = -56 }
BX.runtime.Creature:think(0.2)
BX.creature.Locomotion.step = function() return 0, 0, 0, 0, 1, 0 end
BX.creature:step(1/60)
barricadeCheck(BX.barrier.boarded and BX.barrier.pressure > 1/60,
	"nearby Braid braces on an idle foot-led frame without a crossing delta")
BX.pressureBeforeLosingPrey = BX.barrier.pressure
BX.creature:clearTarget()
BX.creature:step(1/60)
barricadeCheck(BX.barrier.pressure == BX.pressureBeforeLosingPrey,
	"no target means no invisible breach pressure on idle creature frames")
-- Simulate the exact failure: the tendril ray has hit the gate but the
-- foot-led core remains over ten studs away and has zero crossing delta.
BX.creature.X, BX.creature.Z = -51, -56
BX.root.Position = { X = -68, Y = BX.creature.Y, Z = -56 }
BX.runtime.Creature:think(0.2)
BX.creature.Locomotion.AnchorCount = 1
BX.creature.Locomotion.AnchorPart[1] = BX.barrier.Gate
BX.creature.Locomotion.AnchorTendril[1] = 1
BX.creature.Locomotion.AnchorX[1] = -61.2
BX.creature.Locomotion.AnchorY[1] = 7
BX.creature.Locomotion.AnchorZ[1] = -56
BX.pressureBeforeContact = BX.barrier.pressure
BX.creature:step(1/60)
barricadeCheck(BX.barrier.pressure > BX.pressureBeforeContact and BX.barrier.boarded,
	"real CreatureCore frame counts gate-foot contact with the core ten studs away")
BX.creature.Locomotion.AnchorPart[1] = BX.fakeGround
BX.pressureBeforeGround = BX.barrier.pressure
BX.creature:step(1/60)
barricadeCheck(BX.barrier.pressure == BX.pressureBeforeGround,
	"contact with an unrelated support does not breach remotely")
BX.creature.Locomotion.AnchorPart[1] = BX.barrier.Gate
for _ = 1, 150 do BX.creature:step(1/60) end
barricadeCheck(not BX.barrier.boarded and not BX.barrier.Gate.CanCollide
	and BX.barrier.Gate.Transparency == 1 and not BX.barrier:crossing(-62.1,-56,-61.6,-56),
	"sustained foot contact breaches without moving the core through the gate")
BX.braceLogMatches = select(2, string.gsub(LOGSTRING, "Braid bracing boarded garage gate", ""))
barricadeCheck(BX.braceLogMatches == 1,
	"one server diagnostic marks first gate contact without logging every frame")
barricadeCheck(not BX.barrier:board(BX.player), "a breached barricade cannot be rebuilt at night")
BX.creature.X, BX.creature.Z = -60, -56
BX.root.Position = { X = -64, Y = BX.creature.Y, Z = -56 }
BX.runtime.Creature:think(0.2)
barricadeCheck(BX.creature.AttackPhase == "CROUCH",
	"after breach the grounded chomp is restored rather than permanently disabled")
BX.time.phase = "Dawn"
BX.barrier:onPhaseChanged("Dawn")
barricadeCheck(not BX.barrier.spent and BX.barrier.Prompt.Enabled,
	"one plank set is replenished at the authoritative Dawn edge")
BX.time.phase = "Day"
barricadeCheck(BX.barrier:board(BX.player), "the next daytime board uses the restocked set")
BX.time.phase = "Night"
barricadeCheck(BX.barrier:unboard(BX.player) and not BX.barrier.Gate.CanCollide
	and not BX.barrier.Prompt.Enabled and not BX.barrier:board(BX.player),
	"a survivor can escape at night but cannot reuse the noisy spent boards")
barricadeCheck(SIM.COUNTERS.runtimeInstanceNew == 0,
	"boarding, breach and restock create no Vitriol gameplay/UI Instances")
return SESSION
