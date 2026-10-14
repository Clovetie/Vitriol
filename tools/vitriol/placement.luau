-- Future crafting Tool remains in ServerStorage in the authored place. This
-- fixture deliberately moves that ONE existing Tool into a test character.
SESSION = { passed = 0, failed = 0 }
function placementCheck(ok, msg)
	if ok then SESSION.passed = SESSION.passed + 1; print("PASS  " .. msg)
	else SESSION.failed = SESSION.failed + 1; print("FAIL  " .. msg) end
end
PX = {}
PX.runtime = VitriolRequire("Bootstrap").ensure()
PX.placement = PX.runtime.Placement
PX.time = PX.runtime.Time
PX.player = game:GetService("Players"):addPlayer("FutureCrafter")
PX.root = PX.player.Character:FindFirstChild("HumanoidRootPart")
PX.time.phase = "Day"
PX.root.Position = { X = -86, Y = 5, Z = 72 }
PX.root.CFrame = { LookVector = { X = 1, Y = 0, Z = 0 } }
PX.creature = PX.runtime.Creature.creatures[1]
PX.interceptCalls = 0
PX.originalIntercept = PX.placement.intercept
PX.placement.intercept = function(self, ...)
	PX.interceptCalls = PX.interceptCalls + 1
	return PX.originalIntercept(self, ...)
end
PX.creature.TargetX = PX.root.Position.X
PX.creature:step(1/60)
placementCheck(PX.interceptCalls == 0, "no placed boards means no 60 Hz interception work")
placementCheck(PX.placement.Tool.Parent == PX.placement.Tool.Parent.Parent.Tools
	and not PX.placement:place(PX.player),
	"stored Tool cannot place anything in normal Play")
PX.placement.Tool.Parent = PX.player.Character -- test-only equip, no Clone
PX.placement.Tool.Activated:Fire()
PX.board = PX.placement.Active[1]
placementCheck(PX.board ~= nil and PX.board.Parent == PX.placement.Placed
	and PX.board:GetAttribute("SocketName") == "House_01_Door"
	and PX.board.CanCollide and PX.board.ReleaseBoard.Enabled,
	"server Tool activation boards the authored opening using an existing slot")
PX.creature.X, PX.creature.Z, PX.creature.TargetX = -78, 72, -80
PX.creature.Locomotion.step = function() return -2, 0, 0, 0, 1, 0 end
PX.creature:step(1/60)
placementCheck(PX.creature.X == -78 and PX.interceptCalls > 0 and PX.placement.Pressures[PX.board] > 0,
	"active board still blocks an actual creature frame and starts breach pressure")
placementCheck(not PX.placement:place(PX.player) and #PX.placement.Active == 1,
	"a claimed socket cannot receive a duplicate board without a valid free surface")
placementCheck(PX.placement:intercept(-78,72,-80,72) == PX.board,
	"the Braid cannot walk through a manually boarded door")
PX.root.Position = { X = -120, Y = 5, Z = 72 }
placementCheck(not PX.placement:release(PX.player,PX.board), "distant forged removal is rejected")
PX.root.Position = { X = -86, Y = 5, Z = 72 }
PX.board.ReleaseBoard.Triggered:Fire(PX.player)
placementCheck(PX.board.Parent == PX.placement.Pool and #PX.placement.Active == 0
	and PX.placement.SocketOwners.House_01_Door == nil,
	"manual release returns the same part to the finite pool")
-- A nearby free placement requires a queryable map surface, not a random object.
PX.root.Position = { X = 0, Y = 3, Z = 0 }
PX.root.CFrame = { LookVector = { X = 0, Y = 0, Z = -1 } }
PX.ground = SIM.newNode("Part", "TestGround")
SIM.map:AddChild(PX.ground)
PX.runtime.Workspace.Raycast = function(_, origin)
	return { Instance = SIM.gate, Position = { X = origin.X, Y = 0, Z = origin.Z }, Normal = { Y = 1 } }
end
placementCheck(not PX.placement:place(PX.player), "free placement rejects interactive/barricade surfaces")
PX.runtime.Workspace.Raycast = function(_, origin)
	return { Instance = PX.ground, Position = { X = origin.X, Y = 0, Z = origin.Z }, Normal = { Y = 1 } }
end
placementCheck(PX.placement:place(PX.player) and #PX.placement.Active == 1
	and PX.placement.Active[1]:GetAttribute("SocketName") == nil,
	"free placement grounds a pooled board seven studs ahead of the player")
PX.free = PX.placement.Active[1]
placementCheck(PX.placement:intercept(0,-6,0,-8) == PX.free,
	"the free-standing board also interrupts a Braid crossing")
for _ = 1, 25 do PX.placement:press(PX.free,0.1) end
placementCheck(PX.free.Parent == PX.placement.Pool and #PX.placement.Active == 0,
	"bounded Braid pressure breaches free boards and reuses their slot")
PX.root.Position = { X = -86, Y = 5, Z = 72 }
PX.root.CFrame = { LookVector = { X = 1, Y = 0, Z = 0 } }
placementCheck(PX.placement:place(PX.player), "the authored house socket remains reusable")
PX.placement:onPhaseChanged("Dawn")
placementCheck(#PX.placement.Active == 0 and PX.placement.Tool.Parent == PX.player.Character,
	"Dawn resets boards without creating or granting a Tool")
PX.disposable = SIM.newNode("Tool", "DisposableSupply")
PX.player:FindFirstChild("Backpack"):AddChild(PX.disposable)
PX.runtime.Health:onDeath(PX.runtime.Health.states[PX.player.UserId])
placementCheck(PX.placement.Tool.Parent == PX.placement.Tools
	and PX.disposable.Parent == nil and PX.runtime.Health.states[PX.player.UserId].dead,
	"death loses the unique Tool to storage before destroying ordinary inventory")
PX.placement.Tool.Parent = PX.player:FindFirstChild("Backpack") -- test-only handoff
PX.players = game:GetService("Players")
PX.players:removePlayer(PX.player)
placementCheck(PX.placement.Tool.Parent == PX.placement.Tools,
	"disconnect reclaims an authored Tool even from a Backpack")
placementCheck(SIM.COUNTERS.runtimeInstanceNew == 0, "Tool use and recovery create no Vitriol Instances")
return SESSION
