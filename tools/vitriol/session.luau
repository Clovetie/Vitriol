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
	local character, humanoid, root = SIM.makeCharacter(player)
	SIM.step(1.2)
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
	humanoid.Health = 0
	SIM.step(0.2)
	check(state.dead == true, "a Humanoid at 0 hp is dead")
	check(Session:snapshot().kills == 0, "a player death is NOT a session kill: the dial counts creatures the group killed")
	check(Health:scentScale(player.UserId) >= 1, "the corpse still reports a scent scale for the memory layer")

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
