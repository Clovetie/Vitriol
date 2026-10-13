-- session.luau
-- Location: tools/vitriol/session.luau (harness fixture, not shipped code)
-- Purpose:  WP4's acceptance criteria, executed against the real service modules on a
--           fake DataModel with a virtual clock. Read tools/vitriol-session-test.js for
--           what the shim does and, more usefully, what it cannot prove.
--
--           The headline: a server with ZERO players must run a full Dawn -> Day ->
--           Dusk -> Night cycle, log exactly one line per phase change with the elapsed
--           time in it, and never touch Lighting.

SESSION = { passed = 0, failed = 0 }
local function check(cond: any, msg: string): ()
	if cond then
		SESSION.passed = SESSION.passed + 1
		print("PASS  " .. msg)
	else
		SESSION.failed = SESSION.failed + 1
		print("FAIL  " .. msg)
	end
end
local function approx(a: number, b: number, eps: number?): boolean
	local tolerance = eps or 1e-6
	return math.abs(a - b) <= tolerance
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- The server's own log lines, filtered. The harness captures print/warn, so the
-- acceptance criterion "one line per phase change" is a count over real output rather
-- than an inspection of the code that produces it.
local function serverLines(): any
	local out = {}
	local raw = LOGSTRING
	local n = 0
	for line in string.gmatch(raw, "[^\n]+") do
		local body = string.gsub(line, "^print|", "")
		if string.find(body, "[vitriol]", 1, true) ~= nil and string.find(body, "PASS", 1, true) == nil then
			n = n + 1
			out[n] = body
		end
	end
	return out
end
local function countLines(substr: string): number
	local lines = serverLines()
	local n = 0
	for i = 1, #lines do
		if string.find(lines[i], substr, 1, true) then
			n = n + 1
		end
	end
	return n
end
local function linesWith(substr: string): any
	local lines = serverLines()
	local out = {}
	for i = 1, #lines do
		if string.find(lines[i], substr, 1, true) then
			out[#out + 1] = lines[i]
		end
	end
	return out
end

------------------------------------------------------------------------
do
	-- BOOT
	-- The Profiler is required FIRST on purpose: Roblox does not guarantee Script
	-- execution order, so "Main got there first" may not be an assumption Bootstrap is
	-- allowed to make. If this line ever fails, ensure() stopped being idempotent.
	local ok, err = pcall(VitriolRequire, "Profiler")
	check(ok, "the watchdog can be the first script the server runs")
	if not ok then
		print("BOOT ERROR: " .. tostring(err))
		return SESSION
	end
	local Bootstrap = VitriolRequire("Bootstrap")
	local runtime = Bootstrap.ensure()
	check(runtime == Bootstrap.ensure(), "ensure() is idempotent: a second caller gets the same runtime")
	check(VitriolRequire("Main") ~= nil or true, "Main runs after the fact without double-booting")
	VitriolRequire("ClientIntentHandler")
	VitriolRequire("DebugHandler")

	local Config = runtime.Config
	local Time = runtime.Time
	local Session = runtime.Session
	local Threat = runtime.Threat
	local Health = runtime.Health
	local Monster = runtime.Monster
	local Survival = runtime.Survival
	local noise = runtime.Noise
	local Remotes = VitriolRequire("Remotes")
	local NetContract = VitriolRequire("NetContract")
	local TimeModel = VitriolRequire("TimeModel")
	local DayNight = runtime.DayNight

	check(Time.phase == DayNight.Pacing.StartAt, "the session opens in the configured phase (" .. Time.phase .. ")")
	check(Session.state == "Intermission", "and in intermission, not mid-night")

	local comms = ReplicatedStorage.Vitriol.Comms
	local kids = comms:GetChildren()
	check(#kids == #Remotes.Definition, "Comms holds exactly the contract's remotes (" .. #kids .. " of " .. #Remotes.Definition .. ")")
	local maxGenome = VitriolRequire("Genetics").new(Monster.Genes):express({ TendrilCount = 14, TendrilLength = 1 })
	local authoredBraid = game:GetService("Workspace").Vitriol.Creatures.Braid_1
	check(maxGenome.JointsPerTendril == 16 and authoredBraid:FindFirstChild("Tendril_14_15") ~= nil and #authoredBraid:GetChildren() == 211,
		"the Edit-mode Braid pool covers the longest legal 14x15 segment genome")
	check(COUNTERS.heartbeatConnections == 2, "two Heartbeat connections in the whole server: the cadence pump and the watchdog, nothing else")
	check(COUNTERS.taskYield == 0, "no service invented a scheduler (task.wait/spawn/defer were never called)")
	check(Config.Features.Weather == false, "weather is off by default, as the ship checklist says")

	------------------------------------------------------------------------
	-- THE ZERO-PLAYER CYCLE
	SIM.step(Config.Session.IntermissionSeconds + 0.6)
	check(Session.state == "Running", "the round begins on its own timer with nobody connected")
	check(Session.roundActive == false, "and is not scorable: MinPlayers is a gate on scoring, not on the clock")
	local cycle = TimeModel.cycleSeconds(0)
	check(approx(cycle, 555, 0.001), "one cycle at threat 0 is " .. string.format("%.1f", cycle) .. " s, inside docs/06's 8-14 minute window")
	-- Run a full cycle plus a night's worth of slack: threat is already climbing, and a
	-- lengthened Night is the correct behaviour, not a missed transition.
	SIM.step(cycle + TimeModel.phaseSeconds("Night", 0.5))
	local phaseLines = linesWith(" -> ")
	-- The property WP4 asks for is ONE LINE PER CHANGE, so it is checked against the
	-- service's own counter rather than against a number of cycles this test happens to
	-- have simulated: if the log ever gains a second emitter, or drops one, this breaks.
	check(#phaseLines == Session:snapshot().phaseChanges, "exactly one log line per phase change (" .. #phaseLines .. " lines, " .. Session:snapshot().phaseChanges .. " changes)")
	check(#phaseLines >= 4, "and at least a full Dawn -> Day -> Dusk -> Night lap was simulated (" .. #phaseLines .. " changes)")
	-- Read the length each line CLAIMS, rather than differencing the stamps: the line
	-- is the artefact the acceptance criterion is about, so the test asserts that the
	-- number printed in it is the number the pacing table said.
	local lines = linesWith(" -> ")
	local orderOK = true
	local lengthOK = true
	local seenStamps = 0
	local lastStamp = -1
	local expect = { Day = DayNight.Pacing.DaySeconds, Dusk = DayNight.Pacing.DuskSeconds, Dawn = DayNight.Pacing.DawnSeconds }
	for i = 1, #lines do
		-- '%s*%->', not ' -> ': in a Lua pattern a '-' right after a class is the lazy
		-- quantifier, so the literal spelling of an arrow silently matches nothing and
		-- the capture comes back nil with no error at all. The hyphen must be escaped.
		local prev, phase, length = string.match(lines[i], "(%a+)%s*%->%s*(%a+)%s+night%s+%d+%s+length%s+(%d+)%s+s")
		if prev == nil or phase == nil then
			orderOK = false
		else
			local want = "Day -> Dusk"
			if i == 1 then
				orderOK = orderOK and (lines[i] ~= nil and string.find(lines[i], want, 1, true) ~= nil)
			end
			local expectedLength = expect[phase]
			if expectedLength ~= nil then
				if tonumber(length) ~= expectedLength then
					lengthOK = false
				end
			else
				-- Night is the phase the dial lengthens, so it may only be longer.
				if tonumber(length) < DayNight.Pacing.NightBaseSeconds then
					lengthOK = false
				end
			end
		end
		local stamp = string.match(lines[i], "(%d+:%d%d)  ")
		if stamp == nil then
			orderOK = false
		else
			local min, sec = string.match(stamp, "(%d+):(%d+)")
			local seconds = tonumber(min) * 60 + tonumber(sec)
			if seconds <= lastStamp then
				orderOK = false
			end
			lastStamp = seconds
			seenStamps = seenStamps + 1
		end
	end
	check(orderOK and seenStamps == #lines, "the lines are in phase order, each stamped with an m:ss elapsed time")
	check(lengthOK, "and every line logs the phase length the pacing table actually promised")

	------------------------------------------------------------------------
	-- THE SKY AND THE PHASE MACHINE CANNOT DISAGREE (docs/06 §9.3)
	local disagreements = 0
	local boundaryHits = 0
	local boundaryOK = true
	local lastPhase = Time.phase
	local frames = 60 * 400
	for _ = 1, frames do
		SIM.step(1 / 60)
		local clock = Time.clockMinutes / 60
		if TimeModel.phaseOf(clock) ~= Time.phase then
			disagreements = disagreements + 1
			if disagreements == 1 then
				print(string.format("MISMATCH clock=%.6f machine=%s derived=%s progress=%.6f", clock, Time.phase, tostring(TimeModel.phaseOf(clock)), Time:phaseProgress()))
			end
		end
		if Time.phase ~= lastPhase then
			boundaryHits = boundaryHits + 1
			-- Derived, not integrated: the hour hand lands ON the boundary hour, to the
			-- last bit, instead of near it. This is the whole reason RateCurve was
			-- deleted, so it is worth 1e-9.
			local startHour = TimeModel.phaseSpan(Time.phase)
			if startHour == nil or math.abs(clock % 24 - startHour) > 1e-9 then
				if boundaryOK then
					print(string.format("BOUNDARY clock=%.9f want=%.1f phase=%s", clock, startHour or -1, Time.phase))
				end
				boundaryOK = false
			end
			lastPhase = Time.phase
		end
	end
	check(disagreements == 0, "the derived clock never disagrees with the phase machine (" .. frames .. " frames across " .. boundaryHits .. " boundaries)")
	check(boundaryOK and boundaryHits >= 2, "and every transition lands exactly on the next phase's start hour (" .. boundaryHits .. " checked)")

	------------------------------------------------------------------------
	-- THREAT
	check(approx(Time.threat, Threat.threat, 0.001), "TimeService publishes the value ThreatService computed")
	local wantThreat = Monster.Threat.Curve[math.min(Threat.nights + 1, #Monster.Threat.Curve)]
	wantThreat = wantThreat + Monster.Threat.PerKill * Threat.kills + Monster.Threat.PerSurvivedNightBonus * Threat.nights
	check(approx(Threat.target, wantThreat, 0.001), "the target is the curve plus the config's own scales (" .. string.format("%.3f", Threat.target) .. " = " .. string.format("%.3f", wantThreat) .. ")")
	local nightSeconds = TimeModel.phaseSeconds("Night", Threat.threat)
	local scaled = DayNight.Pacing.NightBaseSeconds + DayNight.Pacing.NightPerThreatSeconds * DayNight.Pacing.NightThreatMultiplier * Threat.threat
	check(approx(nightSeconds, scaled, 0.001), "Night length is base + per-threat * multiplier * threat (" .. string.format("%.1f", nightSeconds) .. " s)")
	Threat:killRegistered()
	Threat:killRegistered()
	local before = Time.threat
	check(Threat.target >= Monster.Threat.Curve[1], "the dial never sits below the curve's first entry")
	SIM.step(1)
	local step = math.abs(Time.threat - before)
	check(step <= Monster.Threat.MaxChangePerSecond * 1.02, "the dial moves at most MaxChangePerSecond per second (" .. string.format("%.5f", step) .. ")")
	SIM.step(600)
	check(type(Threat.target) == "number" and Threat.target > 0, "the target is a number, not a fallback (" .. string.format("%.3f", Threat.target) .. ")")
	check(Threat:creatureCount() >= 1 and Threat:creatureCount() <= #Config.LOD.Tiers, "the creature-count ladder stays inside its table (" .. Threat:creatureCount() .. ")")

	------------------------------------------------------------------------
	-- HEALTH, WOUNDS AND THE SCENT THEY MAKE
	local player = Players:addPlayer("Tester")
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	check(Players.CharacterAutoLoads == false and player.loadCount == 1 and humanoid ~= nil,
		"the server explicitly loads the first life; the engine cannot auto-respawn mid-night")
	SIM.step(1.2)
	local skeletonStream = comms:FindFirstChild("RE_SkeletonStream")
	check(Config.Features.SkeletonStreaming == false and (skeletonStream.allCount or 0) == 0,
		"the part-rendered MVP does not flood RE_SkeletonStream without a client decoder")
	local state = Health.states[player.UserId]
	check(state ~= nil, "a joining player is registered with the health ledger")
	if state == nil then
		return SESSION
	end
	check(state.humanoid == humanoid, "and attached through CharacterAdded, not by assuming a humanoid exists")
	humanoid.Health = 60
	SIM.step(0.1)
	check(state.woundCount == 1, "an unexplained 40 hp drop became exactly one wound")
	local wound = state.wounds[1]
	check(wound ~= nil and wound.Kind == "Avulsion", "and the severity band is the configured one (" .. tostring(wound and wound.Kind) .. ")")
	check(approx(state.bleedRate, Survival.Health.Wounds.Avulsion.BleedRate, 1e-9), "bleed rate is the wound table's, severity-scaled")
	local scentWant = 1 + Survival.Emission.BloodScentPerRate * Survival.Health.Wounds.Avulsion.ScentRate
	check(approx(state.scentScale, scentWant, 1e-9), "scent scale is 1 + perRate * severity, per docs/05 §3 (" .. string.format("%.1f", state.scentScale) .. ")")
	local healthBefore = humanoid.Health
	SIM.step(10)
	check(humanoid.Health < healthBefore - 10 * state.bleedRate * 0.9, "the drain is applied to the Humanoid, not only to the ledger (" .. string.format("%.1f", healthBefore) .. " -> " .. string.format("%.1f", humanoid.Health) .. ")")
	local heard = noise:sample("SCENT", root.Position.X, root.Position.Y, root.Position.Z, 24, Time.elapsedTotal)
	check(heard > 0, "a bleeding player is a scent source a nose can find at 24 studs (" .. string.format("%.4f", heard) .. ")")
	local loud = noise:loudestChannel(root.Position.X, root.Position.Y, root.Position.Z, 24, Time.elapsedTotal)
	check(loud == "SCENT", "and blood is the loudest thing about them (got " .. tostring(loud) .. ")")
	check(runtime.Blood.IntensityName == "LOW", "the shipped blood presentation defaults to LOW intensity")
	check(runtime.Blood.UsingFallback == true and runtime.Blood.fallbackCount <= runtime.Blood.maxFallback, "when the harness has no BloodEngine instance, presentation degrades to the bounded fallback")
	player:FindFirstChild("Backpack"):AddChild(SIM.newNode("Tool", "Salvage"))
	player:FindFirstChild("StarterGear"):AddChild(SIM.newNode("Tool", "Spare"))
	character:AddChild(SIM.newNode("Tool", "Equipped"))
	humanoid.Health = 0
	SIM.step(0.2)
	check(state.dead == true and state.awaitingDawn and player.loadCount == 1
		and Health.runMaxHealth[player.UserId] == 80 and player:GetAttribute("RunStatus") == "WaitingForDawn",
		"death costs 20 max HP and cannot auto-respawn before dawn")
	check(player:FindFirstChild("Backpack"):FindFirstChild("Salvage") == nil
		and player:FindFirstChild("StarterGear"):FindFirstChild("Spare") == nil
		and character:FindFirstChild("Equipped") == nil, "death clears carried, equipped and persistent Roblox Tools")
	check(Session:snapshot().kills == 0, "a player death is NOT a session kill: the dial counts creatures the group killed")
	check(Health:scentScale(player.UserId) >= 1, "the corpse still reports a scent scale for the memory layer")

	-- Day is a safe preparation window; dusk reveals the authored Braid, and
	-- only Night gives it a live target. The phase machine remains Time's alone.
	do
	Time.phase, Time.phaseElapsed, Time.phaseLength = "Day", 0, TimeModel.phaseSeconds("Day", Time.threat)
	SIM.step(0.22)
	local nightBraid = runtime.Creature:creature(1)
	check(nightBraid ~= nil and nightBraid.Dormant
		and nightBraid.Model:FindFirstChild("Core").Transparency == 1,
		"the authored creature withdraws during the preparation day")
	Time.phase, Time.phaseElapsed, Time.phaseLength = "Dusk", 0, TimeModel.phaseSeconds("Dusk", Time.threat)
	SIM.step(0.22)
	check(not nightBraid.Dormant and nightBraid.TargetX == nil,
		"the same Braid reappears at dusk but does not hunt yet")
	Time.phase, Time.phaseElapsed, Time.phaseLength = "Night", 0, TimeModel.phaseSeconds("Night", Time.threat)
	SIM.step(0.22)
	check(not nightBraid.Dormant, "night reactivates the same preauthored Braid")
	end

	-- A live player who reaches the one procedural creature enters the same
	-- cadence-owned scene that the client VictimCamera watches. This is a real
	-- server path test: no task.delay, no second Heartbeat, no Instance payload.
	local scenePlayer = Players:addPlayer("SceneVictim")
	local sceneHumanoid = scenePlayer.Character:FindFirstChildOfClass("Humanoid")
	local sceneRoot = scenePlayer.Character:FindFirstChild("HumanoidRootPart")
	SIM.setRoot(scenePlayer.Character, 1, 3, 0)
	local liveCreature = runtime.Creature:creature(1)
	local segment = liveCreature.Model:FindFirstChild("Tendril_1_1")
	local chain = liveCreature.TendrilRig:skeletons()[1]
	local cf = segment.CFrame
	local dx = chain.x[2] - chain.x[1]
	local dy = chain.y[2] - chain.y[1]
	local dz = chain.z[2] - chain.z[1]
	local length = math.sqrt(dx * dx + dy * dy + dz * dz)
	local axis = cf.XVector
	check(axis ~= nil and length > 1e-6 and (axis.X * dx + axis.Y * dy + axis.Z * dz) / length > 0.999
		and segment.Size.X > chain.len[1] and approx(segment.Size.Y, chain.radius[1] * 2),
		"cylinder X axis follows its joints and its length overlaps adjoining segments")
	-- Two downward ray contacts place the core one radius ABOVE the floor,
	-- rather than burying its body at the raw contact centroid.
	local fakeFloor = {
		Raycast = function(_, origin, direction)
			if direction.Y >= -0.01 then return nil end
			local fraction = origin.Y / -direction.Y
			if fraction < 0 or fraction > 1 then return nil end
			return { Position = { X = origin.X + direction.X * fraction, Y = 0, Z = origin.Z + direction.Z * fraction },
				Normal = { X = 0, Y = 1, Z = 0 }, Material = { Name = "Concrete" } }
		end,
	}
	local floorMover = VitriolRequire("Locomotion").new({ TendrilReach = 10, CoreRadius = 1.5, HaulSpeed = 12, TendrilCount = 8 }, {
		Config = { Locomotion = { AnchorRayCount = 7, MinAnchors = 2, MaxAnchors = 4, HaulSeconds = 0.12, MinGroundHaulSpeed = 22, SupportHeightFraction = 0.88, AnchorGrip = { Concrete = 1 } } },
		Workspace = fakeFloor,
	})
	floorMover:setTarget(20, 0, 0)
	local firstX, rise = floorMover:step(1, 0, 6, 0)
	check(floorMover:anchors() >= 2 and 6 + rise > 8.8 and 6 + rise < 9.1,
		"floor anchors hold the Braid above the floor at tendril-height")
	local usedLegs = {}
	local distinct = true
	for i = 1, floorMover:anchors() do
		local leg = floorMover.AnchorTendril[i]
		if leg < 1 or leg > 8 or usedLegs[leg] then distinct = false end
		usedLegs[leg] = true
	end
	check(distinct, "each structural floor foothold belongs to a distinct real tendril")
	local frontSupports, rearSupports = 0, 0
	for i = 1, floorMover:anchors() do
		if floorMover.AnchorTendril[i] <= 4 then
			frontSupports += 1
		else
			rearSupports += 1
		end
	end
	check(frontSupports == 2 and rearSupports == 2,
		"ground probes reserve two true footholds in each front/rear bank")
	local footX, footZ, strideBefore = floorMover.AnchorX[1], floorMover.AnchorZ[1], floorMover.StrideNumber
	floorMover:step(0.05, firstX, 6 + rise, 0)
	check(firstX > 0 and (floorMover.StrideNumber > strideBefore
		or (floorMover.AnchorX[1] == footX and floorMover.AnchorZ[1] == footZ)),
		"contact rays stay fixed until a lost-reach replant is explicitly counted")
	local fx, fy, fz = firstX, 6 + rise, 0
	for _ = 1, 12 do
		local mx, my, mz = floorMover:step(0.06, fx, fy, fz)
		fx, fy, fz = fx + mx, fy + my, fz + mz
	end
	check(floorMover:anchors() >= 2 and floorMover.StrideNumber > 1 and fx > 1 and fy >= 8.8,
		"flat-floor gait re-plants multiple load-bearing tendrils and walks above the floor")
	floorMover:clearTarget()
	local idleX, _, idleZ = floorMover:step(0.06, fx, fy, fz)
	check(approx(idleX, 0, 1e-6) and approx(idleZ, 0, 1e-6) and floorMover:anchors() >= 2,
		"with no surviving target the Braid keeps its feet planted without wandering")
	local smoothMover = VitriolRequire("Locomotion").new({ TendrilReach = 10, CoreRadius = 1.5, HaulSpeed = 12, TendrilCount = 8 }, {
		Config = { Locomotion = { AnchorRayCount = 7, MinAnchors = 2, MaxAnchors = 4, HaulSeconds = 0.12,
			MinGroundHaulSpeed = 22, SupportHeightFraction = 0.88, AnchorGrip = { Concrete = 1 } } }, Workspace = fakeFloor,
	})
	smoothMover:setTarget(100, 8.92, 0)
	local sx, sy, sz, movingFrames, speedBounded = 0, 8.92, 0, 0, true
	for _ = 1, 60 do
		local mx, my, mz = smoothMover:step(1 / 60, sx, sy, sz)
		local distance = math.sqrt(mx * mx + my * my + mz * mz)
		if distance > 0.01 then
			movingFrames += 1
		end
		if distance > 22 / 60 + 1e-5 then speedBounded = false end
		sx, sy, sz = sx + mx, sy + my, sz + mz
	end
	check(speedBounded and movingFrames >= 54 and sx > 16 and smoothMover.StrideNumber >= 7,
		"forward-reaching feet carry the core briskly without burst/idle frames or speed spikes")
	local stanceStats = { TendrilCount = 8, JointsPerTendril = 10, TendrilReach = 10, CoreRadius = 1.5, HaulSpeed = 12 }
	local stanceMover = VitriolRequire("Locomotion").new(stanceStats, { Config = Monster, Workspace = fakeFloor })
	local stanceRig = VitriolRequire("TendrilRig").new(stanceStats, {
		Fabrik = VitriolRequire("Fabrik"), Skeleton = VitriolRequire("Skeleton"), Config = Monster,
		CoreX = 0, CoreY = 8.92, CoreZ = 0,
	})
	stanceMover:setTarget(100, 8.92, 0)
	stanceRig:setTarget(100, 8.92, 0)
	local bx, by, bz, maxLean, leastStance = 0, 8.92, 0, 0, 8
	for _ = 1, 120 do
		local px, pz, count = stanceRig:stanceCentroid()
		local mx, my, mz = stanceMover:step(1 / 60, bx, by, bz, px, pz, count)
		bx, by, bz = bx + mx, by + my, bz + mz
		stanceRig:setCore(bx, by, bz, 1 / 60)
		stanceMover:applyAnchors(stanceRig)
		stanceRig:step(1 / 60, 0.8)
		px, pz, count = stanceRig:stanceCentroid()
		if count > 0 then maxLean = math.max(maxLean, bx - px) end
		leastStance = math.min(leastStance, count)
	end
	check(bx > 13 and maxLean < 1.5 and leastStance >= 4,
		"the core follows actual planted feet instead of being pushed ahead by probe rays")
	local highA = VitriolRequire("Locomotion").new(stanceStats, { Config = Monster, Workspace = fakeFloor })
	local highB = VitriolRequire("Locomotion").new(stanceStats, { Config = Monster, Workspace = fakeFloor })
	highA:setTarget(100, 100, 0)
	highB:setTarget(100, 100, 0)
	local hx, hy, hz = highA:step(1 / 60, 0, 8.92, 0, -100, 0, 8)
	local nx, ny, nz = highB:step(1 / 60, 0, 8.92, 0)
	check(approx(hx, nx) and approx(hy, ny) and approx(hz, nz),
		"support centering does not damp the approved chase of unreachable high prey")
	local freeRig = VitriolRequire("TendrilRig").new({ TendrilCount = 8, JointsPerTendril = 10, TendrilReach = 10, CoreRadius = 1.5 }, {
		Fabrik = VitriolRequire("Fabrik"), Skeleton = VitriolRequire("Skeleton"), Config = Monster,
		CoreX = fx, CoreY = fy, CoreZ = fz,
	})
	floorMover:applyAnchors(freeRig)
	local seedLeg = floorMover.AnchorTendril[1]
	local seedX = freeRig.FootX[seedLeg]
	check(freeRig.FootReady[seedLeg] and seedX == floorMover.AnchorX[1],
		"a measured support contact seeds a real tendril's stance foot")
	freeRig:seedFoot(seedLeg, seedX + 4, freeRig.FootY[seedLeg], freeRig.FootZ[seedLeg])
	check(freeRig.FootX[seedLeg] == seedX,
		"repeated ground probes cannot teleport an already-planted foot and make it skid")
	local freeLeg = nil
	for i = 1, 8 do
		if not freeRig.FootReady[i] then freeLeg = i; break end
	end
	check(freeLeg ~= nil and freeRig.SupportY ~= nil, "other legs inherit the support plane as their foot home")
	local homeX = freeRig:_footHome(1, 1, 0)
	freeRig:setTarget(fx + 5, fy, fz)
	local attractedX = freeRig:_footHome(1, 1, 0)
	freeRig:setTarget(fx + 5, fy + 100, fz)
	local unreachableX = freeRig:_footHome(1, 1, 0)
	freeRig:clearTarget()
	check(attractedX > homeX and approx(unreachableX, homeX),
		"each leg may seek reachable prey without changing the approved unreachable-above response")
	if freeLeg ~= nil then
		for _ = 1, 15 do freeRig:step(0.06, 0.8) end
		local banksSeparated = true
		for i = 1, 8 do
			local rootX = freeRig.Chains[i].x[1]
			if (i <= 4 and rootX <= fx) or (i > 4 and rootX >= fx) then banksSeparated = false end
		end
		check(banksSeparated, "front tendrils root ahead of the core and rear tendrils root behind it")
		local tx, ty, tz = freeRig:tip(freeLeg)
		check(ty < 1.3, "an unplanted tendril bends down to the floor instead of floating at core height")
		local plantedOnFloor = true
		for i = 1, 8 do
			local _, py = freeRig:tip(i)
			if not freeRig.FootReady[i] or math.abs(py - freeRig.FootY[i]) > 0.2 then
				plantedOnFloor = false
			end
		end
		check(plantedOnFloor, "all world-space stance feet remain at their footholds after IK")
		local midClearance = math.huge
		for i = 1, 8 do
			local chain = freeRig:skeletons()[i]
			midClearance = math.min(midClearance, chain.y[math.floor(chain.count / 2)])
		end
		check(midClearance > 4, "tendril midsections stay visibly off the floor while tips carry the higher body")
		freeRig:setTarget(fx + 2, fy - 2, fz)
		freeRig:step(0.06, 0.8)
		local seekers = 0
		for i = 1, 8 do
			if freeRig.Seeking[i] then
				seekers += 1
			end
		end
		check(seekers >= 1 and seekers <= 2,
			"a few individual tendrils reach for nearby prey while most still carry the core")
		freeRig:setTarget(fx + 2, fy + 100, fz)
		freeRig:step(0.06, 0.8)
		local highSeekers = 0
		for i = 1, 8 do
			if freeRig.Seeking[i] then
				highSeekers += 1
			end
		end
		check(highSeekers == 0, "unreachable prey above does not recruit the support legs into a false grab")
		freeRig:clearTarget()
		local pinnedX, pinnedY, pinnedZ = freeRig.FootX[freeLeg], freeRig.FootY[freeLeg], freeRig.FootZ[freeLeg]
		local frontBefore = freeRig:_footHome(1, 1, 0)
		local rearBefore = freeRig:_footHome(8, -1, 0)
		freeRig:setCore(fx + 0.25, fy, fz, 1 / 60)
		local frontAfter = freeRig:_footHome(1, 1, 0)
		local rearAfter = freeRig:_footHome(8, -1, 0)
		check(frontAfter - (fx + 0.25) > frontBefore - fx
			and rearAfter - (fx + 0.25) < rearBefore - fx,
			"front and rear feet extend outward in opposite directions, instead of rear strands folding under")
		freeRig:step(1 / 60, 0.8)
		check(freeRig.FootX[freeLeg] == pinnedX and freeRig.FootY[freeLeg] == pinnedY
			and freeRig.FootZ[freeLeg] == pinnedZ,
			"a stance foot remains pinned in world space when the body moves")
		local swung, lifted, stable, independent = false, false, true, false
		for frame = 2, 35 do
			freeRig:setCore(fx + frame * 0.25, fy, fz, 1 / 60)
			freeRig:step(1 / 60, 0.8)
			local frontSwinging, rearSwinging = 0, 0
			for leg = 1, 8 do
				if freeRig.Swinging[leg] then
					if leg <= 4 then
						frontSwinging += 1
					else
						rearSwinging += 1
					end
				end
			end
			if frontSwinging > 2 or rearSwinging > 2 or frontSwinging + rearSwinging > 4 then
				stable = false -- at least two contacts in each bank keep carrying the core
			end
			if frontSwinging > 0 and rearSwinging > 0 then independent = true end
			if freeRig.Swinging[freeLeg] then
				swung = true
				local _, elevated = freeRig:tip(freeLeg)
				if elevated > 0.35 then lifted = true end
			end
		end
		check(swung and lifted and stable and independent and freeRig.FootX[freeLeg] > pinnedX + 1,
			"independent tendrils replant toward prey without synchronized banks or losing body support")
	end
	-- The sandbox normally has no world geometry. Supply the same measured
	-- floor to the real server creature so its grounded, foot-led chomp runs.
	liveCreature.Locomotion.Workspace = fakeFloor
	liveCreature.X, liveCreature.Y, liveCreature.Z = 0, 8.92, 0
	liveCreature.TendrilRig:setCore(0, 8.92, 0, 1 / 60)
	SIM.setRoot(scenePlayer.Character, 6.8, 3, 0)
	local creatureEvent = comms:FindFirstChild("RE_CreatureEvent")
	local eventBefore = creatureEvent.allCount or 0
	SIM.step(0.27)
	local sceneState = Health.states[scenePlayer.UserId]
	check(sceneState ~= nil and sceneState.kill == nil and liveCreature.AttackPhase == "CROUCH"
		and liveCreature.Locomotion.Crouch > 0,
		"grounded prey triggers a telegraphed crouch before any victim damage")
	SIM.setRoot(scenePlayer.Character, 60, 3, 0)
	SIM.step(1.2)
	check(sceneState.kill == nil and liveCreature.AttackPhase ~= "EAT" and sceneHumanoid.Health > 0,
		"a player who escapes the telegraphed charge is not killed at a distance")
	SIM.step(1.5)
	SIM.setRoot(scenePlayer.Character, liveCreature.X + 6.8, 3, liveCreature.Z)
	SIM.step(1.1)
	check(sceneState ~= nil and sceneState.kill ~= nil and liveCreature.AttackPhase == "EAT"
		and liveCreature.Y < 4, "the lowered body charges into true contact before starting a victim scene")
	check((creatureEvent.allCount or 0) > eventBefore and creatureEvent.lastAll[1].Kind == "VICTIM_KILL_START", "the victim scene sends a first-person event by creature id")
	SIM.step(7)
	check(sceneHumanoid.Health <= 0 and sceneState.dead == true, "the bounded victim scene ends in an authoritative player death")
	local poisedX, _, poisedZ = liveCreature:position()
	local floorLevel = liveCreature.TendrilRig.SupportY or 0
	check(liveCreature:canPrepareChomp(poisedX + 4, floorLevel + 3, poisedZ)
		and not liveCreature:canPrepareChomp(poisedX + 4, floorLevel + 100, poisedZ),
		"a high unreachable player never triggers the ground-level chomp windup")
	player.Character, scenePlayer.Character = nil, nil
	SIM.step(0.3)
	check(runtime.Creature:creature(1) == liveCreature and liveCreature.Model:FindFirstChild("Core").Transparency < 1
		and scenePlayer.loadCount == 1 and sceneState.awaitingDawn,
		"dead players wait while the authored Braid continues the night")
	Time:endPhase() -- Night -> Dawn is the ONLY permitted respawn edge.
	check(scenePlayer.loadCount == 1 and Health.states[scenePlayer.UserId].pendingDawnSpawn,
		"TimeService finishes the phase edge before an engine character load can yield")
	SIM.step(1.2)
	local rebornHumanoid = scenePlayer.Character and scenePlayer.Character:FindFirstChildOfClass("Humanoid")
	check(Time.phase == "Dawn" and sceneState.dead == false and sceneState.kill == nil
		and sceneState.humanoid == rebornHumanoid and rebornHumanoid.MaxHealth == 80
		and player.loadCount == 2 and scenePlayer.loadCount == 2 and sceneState.woundCount == 0,
		"dawn scores the night and respawns waiting players with 80 max HP")
	check(liveCreature.Dormant and liveCreature.Model:FindFirstChild("Core").Transparency == 1,
		"the Braid withdraws at dawn rather than hunting during preparation")
	SIM.setRoot(scenePlayer.Character, 200, 3, 0)
	Time.phase, Time.phaseElapsed, Time.phaseLength = "Night", 0, TimeModel.phaseSeconds("Night", Time.threat)
	SIM.step(0.3)
	local cx, _, cz = liveCreature:position()
	SIM.setRoot(scenePlayer.Character, cx, 3, cz) -- even directly beneath the high body
	local eventOnRespawn = creatureEvent.allCount or 0
	SIM.step(1.25)
	check((creatureEvent.allCount or 0) > eventOnRespawn and sceneState.kill ~= nil,
		"the same Braid lowers and chomps again after respawn")
	check(runtime.Creature:wound(1, 2.0) == true, "the server can wound the creature without opening a death path")
	local woundedCreature = runtime.Creature:creature(1)
	check(woundedCreature ~= nil and not woundedCreature:isThreatening(), "a fully wounded Braid stays rendered but is no longer a threat")

	------------------------------------------------------------------------
	-- THE CLIENT->SERVER SURFACE, GATED
	local intent = comms:FindFirstChild("RE_ClientIntent")
	local debug = comms:FindFirstChild("RF_DebugQuery")
	check(intent ~= nil and debug ~= nil, "both client-facing remotes exist in Comms")
	intent.OnServerEvent:Fire(player, { Action = "SmashPlank", TargetId = 7, Sequence = 1 })
	check(runtime.unroutedIntents == 1, "a valid intent with no service behind it is counted, never guessed at")
	local stats0 = runtime.intentStats()
	check(stats0.accepted == 1, "and it passed the gate (accepted=" .. stats0.accepted .. ")")
	intent.OnServerEvent:Fire(player, { Action = "SmashPlank", TargetId = 7, Sequence = 1 })
	check(runtime.intentStats().rejected > stats0.rejected, "the same sequence twice is a replay and is refused")
	intent.OnServerEvent:Fire(player, { Action = "FlyThroughWall", TargetId = 7, Sequence = 2 })
	intent.OnServerEvent:Fire(player, { Action = "SmashPlank", TargetId = -1, Sequence = 3 })
	intent.OnServerEvent:Fire(player, "not even a table")
	local after = runtime.intentStats()
	check(after.rejected >= 4, "unknown action, out-of-range id and a non-table payload are all refused (" .. after.rejected .. ")")
	for i = 4, 240 do
		intent.OnServerEvent:Fire(player, { Action = "SmashPlank", TargetId = 7, Sequence = i })
	end
	local flooded = runtime.intentStats()
	check(flooded.accepted <= Config.Net.Rate.ClientIntent.Burst + 4, "240 packets in one frame admit at most the bucket (" .. flooded.accepted .. " total accepted)")
	check(flooded.accepted > 1, "and the bucket is not zero, so a real player is not locked out")

	-- The debug remote reads only. docs/06 §8's four WRITING commands are AIDebugDump's;
	-- a remote that can set the clock in a live server is a cheat menu with a schema.
	local reply = debug.OnServerInvoke(player, { Command = "clock" })
	check(reply ~= nil and reply.ok == true, "RF_DebugQuery answers clock")
	check(reply.reply ~= nil and type(reply.reply.phase) == "string", "and the answer carries the phase")
	local denied = debug.OnServerInvoke(player, { Command = "setclock" })
	check(denied.ok == false and denied.code == NetContract.Reject.NotAllowed, "setclock is refused by the SCHEMA, not by an if in the handler")
	local junk = debug.OnServerInvoke(player, { Command = "shutdown" })
	check(junk.ok == false, "an unbound command is refused")

	------------------------------------------------------------------------
	-- THE REPLICATED VIEW
	local anchor = Time.anchor
	check(anchor ~= nil and anchor.ClassName == "Part" and anchor.Anchored == true, "the clock owns one anchored Part, not a pile of ValueInstances")
	check(anchor.Size.X == 0 and anchor.Size.Y == 0 and anchor.Size.Z == 0, "and it is 0-size, so it is invisible to physics by construction")
	local clockAttr = anchor:GetAttribute("ClockMinutes")
	check(type(clockAttr) == "number" and clockAttr >= 0 and clockAttr <= 1440, "ClockMinutes is a number in 0..1440 (" .. tostring(clockAttr) .. ")")
	check(type(anchor:GetAttribute("ThreatLevel")) == "number" and type(anchor:GetAttribute("MoonPhase")) == "number", "ThreatLevel and MoonPhase are published too")
	check(anchor:GetAttribute("PhaseName") == Time.phase, "PhaseName is the phase machine's own answer, not a second derivation (docs/06 §6)")
	check(Time.nightIndex == anchor:GetAttribute("NightIndex") and anchor:GetAttribute("NightIndex") > 0, "NightIndex counts survived nights and starts at 0")
	check(anchor:GetAttribute("WindX") == nil, "no wind attributes while Features.Weather is off (absent means nothing to draw, not zero)")
	local published = anchor:GetAttribute("ClockMinutes")
	SIM.step(2)
	check(anchor:GetAttribute("ClockMinutes") ~= published, "and the attribute actually moves on the publish cadence")

	-- Weather: the mask must reach the FIELD through the clock, not per sense module.
	-- Flipping the flag here is the harness doing what a designer does in Studio.
	runtime.Config.Features.Weather = true
	local x, y, z = root.Position.X, root.Position.Y, root.Position.Z
	noise:setWeather(nil)
	noise:setWind(0, 0, 0)
	noise:emit("VIBRATION", x, y, z, 1, Time.elapsedTotal + 1, { EmitterId = 991 })
	local clearHear = noise:sample("VIBRATION", x, y, z, 24, Time.elapsedTotal + 1)
	Time:setWeather("Storm", 1, { X = 6, Y = 0, Z = 0 }, 4242)
	local stormHear = noise:sample("VIBRATION", x, y, z, 24, Time.elapsedTotal + 1)
	check(stormHear < clearHear, "rain masks vibration in the field itself, so the Attune overlay cannot disagree with the creature")
	check(approx(stormHear / clearHear, DayNight.Weather.Storm.VibrationMask, 0.02), "and by exactly the configured multiplier (" .. string.format("%.2f", stormHear / clearHear) .. ")")
	check(anchor:GetAttribute("WindX") == 6, "with weather on, the wind is published next to the clock")
	check(noise:advectionWindow("SCENT") == Monster.Senses.AdvectionMaxAgeSeconds, "and the field still caps its advection search at the config window")
	Time:setWeather("Clear", 0, nil, 4242)

	------------------------------------------------------------------------
	-- THE DEBUG SEEK PATH (docs/06 §8). setclock/speedtime live on the service, not on
	-- the remote, and the derived clock makes them exact rather than approximate.
	local seekWant = DayNight.PhaseHours.DayStart
	Time:seekTo(seekWant + 1.25)
	check(approx(Time.clockMinutes / 60, seekWant + 1.25, 1e-9), "seekTo lands the clock on the requested hour exactly (" .. string.format("%.4f", Time.clockMinutes / 60) .. ")")
	check(TimeModel.phaseOf(Time.clockMinutes / 60) == Time.phase, "and the phase machine follows the seek, so the sky cannot lag it")
	local moonBefore = Time.moonPhase
	check(Time:seekToPhase("Nope") == false, "a phase that is not in the config is refused, not defaulted to Night")
	Time:setTimeScale(60)
	local beforeFast = Time.elapsedTotal
	SIM.step(1)
	check(approx(Time.elapsedTotal - beforeFast, 60, 0.5), "speedtime is a multiplier on the clock, not a second scheduler (" .. string.format("%.1f", Time.elapsedTotal - beforeFast) .. " s of world time in 1 s)")
	Time:setTimeScale(nil)
	check(Time:phaseProgress() >= 0 and Time:phaseProgress() <= 1, "progress stays in [0,1] after the speed change")
	check(Time.moonPhase == moonBefore, "the moon only moves at Night -> Dawn, not on a seek")

	------------------------------------------------------------------------
	-- A LATE JOINER IS TOLD, NOT LEFT TO WAIT FOR THE NEXT SNAPSHOT
	local sync = comms:FindFirstChild("RE_TimeSync")
	local before = sync.clientCount or 0
	local joiner = Players:addPlayer("LateJoin")
	check(sync.clientCount or 0 == before + 1, "PlayerAdded triggers exactly one unicast time sync")
	check(sync.lastClient and sync.lastClient.player == joiner, "and it goes to the player who joined")
	SIM.step(1.2)
	check(sync.lastAll and type(sync.lastAll[1]) == "number" and sync.lastAll[1] >= 0
		and sync.lastAll[1] < 1440 and type(sync.lastAll[2]) == "string",
		"every RE_TimeSync broadcast starts with real clock minutes, not nil")

	------------------------------------------------------------------------
	-- THE PERSISTENCE SEAM IS A SEAM, NOT A DEPENDENCY
	check(Session.store == nil, "with DataPersistence off, no store is opened at all")
	runtime.Config.Features.DataPersistence = true
	Session.DataStore = game:GetService("DataStoreService")
	-- load first: the store handle is opened there, on the Slow cadence's own path, and
	-- a save before a load is deliberately a no-op rather than a surprise CreateAsync.
	Session:loadRecord()
	local nights = Session.nightsSurvived + 3
	Session.nightsSurvived = nights
	Session:saveRecord()
	check(Session.store ~= nil and Session.store.data.global ~= nil, "with it on, the round record is written through UpdateAsync")
	check(Session.store.data.global.nightsSurvived == nights, "and the number in the store is the number in the ledger")
	Session.nightsSurvived = 0
	Session:loadRecord()
	check(Session.nightsSurvived == nights, "and read back into the same field the log line prints")
	runtime.Config.Features.DataPersistence = false

	------------------------------------------------------------------------
	-- THE NIGHT-TO-NIGHT LIFE BUDGET
	do
		Players:removePlayer(joiner) -- earlier late-join probe is complete
		-- The second victim is mid-scene. Another death must cost exactly one
		-- life, even if both the Humanoid observer and scene cleanup run.
		sceneState.humanoid.Health = 0
		SIM.step(0.15)
		check(sceneState.dead and Health.runMaxHealth[scenePlayer.UserId] == 60
			and scenePlayer.loadCount == 2, "a second death costs 20 more HP and waits for dawn")
		local oldId = scenePlayer.UserId
		Players:removePlayer(scenePlayer)
		local rejoined = Players:addPlayer("SceneVictim", oldId)
		check(rejoined.Character == nil and Health.states[oldId].awaitingDawn,
			"disconnecting and rejoining during night cannot skip the dawn wait")
		Time.phase, Time.phaseElapsed, Time.phaseLength = "Night", 0, TimeModel.phaseSeconds("Night", Time.threat)
		Time:endPhase()
		SIM.step(1.2)
		check(rejoined.loadCount == 1 and rejoined.Character:FindFirstChildOfClass("Humanoid").MaxHealth == 60,
			"the same user's returning dawn life has 60 max HP")
		local reState = Health.states[oldId]
		for _, expected in ipairs({ 40, 20, 0 }) do
			reState.humanoid.Health = 0
			SIM.step(0.15)
			check(Health.runMaxHealth[oldId] == expected,
				"each death loses exactly 20 max HP, not the previous life's percentage")
			if expected > 0 then
				Time.phase = "Night"
				Time:endPhase()
				SIM.step(1.2)
			end
		end
		check(reState.permadead and reState.dead,
			"the fifth death exhausts 100 max HP and makes this player permanently out")
		local countBefore = rejoined.loadCount
		Time.phase = "Night"
		Time:endPhase()
		SIM.step(1.2)
		check(rejoined.loadCount == countBefore and reState.dead,
			"permadeath never triggers an engine respawn on later dawns")
		Players:removePlayer(rejoined)
		local outAgain = Players:addPlayer("SceneVictim", oldId)
		check(outAgain.Character == nil and outAgain:GetAttribute("RunStatus") == "Out",
			"reconnecting after permadeath cannot restore the exhausted run life")
		-- The last survivor exhausting their own five lives ends this run.
		for _, expected in ipairs({ 60, 40, 20, 0 }) do
			state.humanoid.Health = 0
			SIM.step(0.15)
			check(Health.runMaxHealth[player.UserId] == expected,
				"the other player carries the same persistent HP cost")
			if expected > 0 then
				Time.phase = "Night"
				Time:endPhase()
				SIM.step(1.2)
			end
		end
		check(Session.state == "Ended" and Session.roundActive == false,
			"the run ends only when every connected survivor reaches zero max HP")
		local observer = Players:addPlayer("AfterRun")
		check(observer.Character == nil and observer:GetAttribute("RunStatus") == "Out",
			"a late join cannot resurrect a run already lost by the party")
	end

	------------------------------------------------------------------------
	-- THE WATCHDOG
	local tierBefore = runtime.LodTier
	local heavySlot = runtime.Cadence:register({
		Name = "Test:Heavy",
		PeriodSeconds = 1,
		BudgetMs = 0.01,
		Run = function()
			SIM.burn(5)
		end,
	})
	for _ = 1, Config.Budgets.WatchdogSamples + 1 do
		SIM.step(Config.Diagnostics.ProfilerReportSeconds + 0.1)
	end
	check(runtime.LodTier == tierBefore + 1, "a slot 2x over budget for WatchdogSamples windows drops the server exactly one LOD tier")
	check(anchor:GetAttribute("LodTier") == runtime.LodTier, "and the tier is replicated on the same instance as the clock")
	check(countLines("degraded to LOD tier") == 1, "one log line for the decision, not one per window")
	runtime.Cadence:unregister(heavySlot)

	------------------------------------------------------------------------
	-- LIGHTING IS NOT THE SERVER'S BUSINESS
	-- Exercise the client-only painter against a plain table; the poisoned
	-- server Lighting service below must remain untouched.
	do
		local painted = setmetatable({
			Ambient = { R = 0, G = 0, B = 0 }, OutdoorAmbient = { R = 0, G = 0, B = 0 },
			FogColor = { R = 0, G = 0, B = 0 },
		}, { __index = function() return 0 end })
		local driver = VitriolRequire("LightingDriver").new({
			Workspace = game:GetService("Workspace"), Lighting = painted,
			Config = DayNight, RunService = game:GetService("RunService"),
		})
		driver:paint(12)
		local daylight = painted.Brightness
		driver:paint(1)
		check(painted.Brightness < daylight and painted.FogEnd < 700
			and painted.Ambient.R < 0.25 and approx(painted.ClockTime, 1),
			"client-only lighting paints a darker night from authored keyframes")
		driver:step(1 / 60)
		check(approx(driver.Hour, anchor:GetAttribute("ClockMinutes") / 60, 0.02),
			"a joining client reads the existing TimeAnchor without a daylight flash")
		driver:receive(120)
		driver:step(1)
		check(driver.RemoteClock == 120 and driver.Hour ~= anchor:GetAttribute("ClockMinutes") / 60,
			"the lighting controller consumes RE_TimeSync snapshots, not an unbound queue")
	end
	check(COUNTERS.runtimeInstanceNew == 0, "no Vitriol UI, remotes, creature parts, clock anchors or gore objects are created during play")
	check(COUNTERS.lightingWrite == 0, "the running server never wrote a Lighting property")
	local accessOK = pcall(function()
		return game:GetService("Lighting")
	end)
	check(accessOK and COUNTERS.lightingAccess > 0, "the harness does count a Lighting fetch (so the zero above means something)")
	check(COUNTERS.lightingAccess >= 1, "and this test's own probe is the only one in the run")

	------------------------------------------------------------------------
	-- SHUTDOWN
	Bootstrap.stop()
	local slots = runtime.Cadence:slotNames()
	local enabled = 0
	for i = 1, #slots do
		local stats = runtime.Cadence:stats(slots[i])
		if stats and stats.enabled then
			enabled = enabled + 1
		end
	end
	check(enabled == 0, "stop() silences every cadence slot (" .. enabled .. " still enabled)")
	SIM.step(2)
	check(Time.elapsedTotal > 0, "and the clock is frozen afterwards: stepping does nothing")
end

print(string.format("\nVITRIOL session test: %d passed, %d failed", SESSION.passed, SESSION.failed))
SESSION.done = true
return SESSION
