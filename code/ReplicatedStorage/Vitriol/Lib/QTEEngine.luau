--!strict
-- QTEEngine.luau
-- Location: ReplicatedStorage > Vitriol > Lib > QTEEngine  (ModuleScript)
-- Purpose:  The QTE interpreter. A "task" (produced by Lib/QTECatalog and timed by
--           Lib/QTEDirector) is a plain data description of one quick-time event;
--           this module turns it into a deterministic state machine driven by frames:
--
--             local engine = QTEEngine.new(task, { human = QTEConfig.Human })
--             engine:tick({ dt = dt, keys = heldKeys, pointer = {x=,y=}, clicks = n })
--             local view = engine:view()   -- what the shell draws
--
--           WHY THIS EXISTS. The v5 manager was 50 hand-written Roblox coroutines, one
--           per QTE: untestable off-device, frame-rate dependent (drains and drifts
--           used per-frame constants), and capable of soft-locking the player forever
--           when a QTE had no deadline. Here the LOGIC is pure - no game:GetService,
--           no Instances, no task.*, no os.clock, no math.random - so the smoke harness
--           can execute every QTE on every difficulty and assert that perfect play
--           wins, idling cannot win, and nothing can hang (tools/vitriol/tests.luau).
--           Time comes in as `dt`; randomness comes from the task's own parameters.
--
--           THE SOLUTION CHANNEL. view.expect is the engine stating what a correct
--           player would do this frame. The shell never reads it. It exists so the
--           headless harness can solve any QTE without screen-scraping, and so a
--           future tutorial/"assist mode" has a single source of truth for the answer.
--
-- Requires: Config/QTEConfig
-- Used by:  Lib/QTEDirector, Controllers/QTEStruggle, tools/vitriol/tests.luau

local QTEConfig = require(script.Parent.Parent.Config.QTEConfig)

local QTEEngine = {}
QTEEngine.__index = QTEEngine

-- Widget primitives the shell knows how to draw. A definition may only emit these;
-- tests.luau asserts no mode invents a kind (a typo would otherwise be a silent
-- invisible widget).
QTEEngine.WIDGET_KINDS = {
	text = true, -- {kind, value, colour, scale}
	bar = true, -- {kind, value 0..1, colour, orientation, label}
	track = true, -- {kind, value 0..1, zone?, zones?, colour, orientation, label}
	target = true, -- {kind, x, y, radius, colour, alpha}
	path = true, -- {kind, points, index, colour}
	grid = true, -- {kind, cols, rows, originX, originY, cellW, cellH, cells}
	chips = true, -- {kind, items, index, colour, state}
}

QTEEngine.STATES = { Running = "running", Won = "won", Lost = "lost" }

-- Resolution reasons, so the game (and the tests) can distinguish "you pressed the
-- wrong key" from "you ran out of time" without parsing prompt text.
QTEEngine.REASONS = {
	Complete = "complete",
	Timeout = "timeout",
	WrongInput = "wrong_input",
	FalseStart = "false_start",
	OutOfBounds = "out_of_bounds",
	Drifted = "drifted",
	EarlyRelease = "early_release",
	ExtraInput = "extra_input",
	Missed = "missed",
	Aborted = "aborted",
	Unsupported = "unsupported",
}

-- ── Small pure helpers ───────────────────────────────────────────────────────
local function clamp(x: number, lo: number, hi: number): number
	if x < lo then
		return lo
	end
	if x > hi then
		return hi
	end
	return x
end

local function clamp01(x: number): number
	return clamp(x, 0, 1)
end

-- ── Token <-> character ──────────────────────────────────────────────────────
-- The engine speaks input TOKENS ("Four", "KeypadFour", "E"); typed answers are
-- characters ("4", "E"). Both translations live here so "press the digit you were
-- shown" cannot work in one mode and silently do nothing in another.
local function digitOf(token: string): string?
	if token == nil then
		return nil
	end
	local d = QTEConfig.DigitAliases[token]
	if d ~= nil then
		return d
	end
	if #token == 1 and token >= "0" and token <= "9" then
		return token
	end
	return nil
end

local function tokenForChar(ch: string): string
	return QTEConfig.DigitTokens[ch] or ch
end

-- maskText(state) -> string
-- "E__" style progress for typed answers: typed characters are revealed (if the
-- task allows it), the next one is revealed only when the task asks for it, and
-- everything else stays hidden.
local function maskText(s: any): string
	if not s.text then
		return ""
	end
	local shown = {}
	for i = 1, #s.text do
		if i < s.index then
			shown[i] = s.reveal and s.text:sub(i, i) or "_"
		elseif i == s.index and s.maskNext then
			shown[i] = s.text:sub(i, i)
		else
			shown[i] = "_"
		end
	end
	return table.concat(shown)
end

local function hasToken(list: any, token: string): boolean
	for i = 1, #list do
		if list[i] == token then
			return true
		end
	end
	return false
end

-- Triangle wave in [0, 1]: 0 at t=0, 1 at t=period/2, 0 at t=period.
local function pingpong(t: number, period: number): number
	if period <= 0 then
		return 0
	end
	local phase = (t % period) / period
	if phase <= 0.5 then
		return phase * 2
	end
	return (1 - phase) * 2
end

-- Deterministic organic motion for the widget layer: two out-of-phase sines. The
-- v5 manager used math.random per frame for drift, which is both untestable and
-- frame-rate dependent; a closed form is neither.
local function wobble(t: number, freqA: number, freqB: number, phase: number): number
	return (math.sin(t * freqA + phase) + 0.5 * math.sin(t * freqB * 1.618 + phase * 1.7)) / 1.5
end

local function length3(v: any): number
	return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

-- Portable atan2. Luau ships math.atan2; Lua 5.3 (the headless harness) folded it
-- into math.atan(y, x). Written out rather than feature-detected so the engine
-- behaves identically in Studio and in the smoke test - a divergence here would be a
-- rotation QTE that only works on one of them.
local function atan2(y: number, x: number): number
	if x > 0 then
		return math.atan(y / x)
	elseif x < 0 then
		return math.atan(y / x) + (y >= 0 and math.pi or -math.pi)
	elseif y > 0 then
		return math.pi / 2
	elseif y < 0 then
		return -math.pi / 2
	end
	return 0
end

-- ── Resolution ───────────────────────────────────────────────────────────────
-- Called by modes (and by the timeout path). First call wins; later calls are
-- ignored, which is what makes "resolve from the tick after an event resolved"
-- safe without an `if st.state ~= running` at every call site.
local function resolve(st: any, won: boolean, score: number, reason: string): ()
	if st.state ~= QTEEngine.STATES.Running then
		return
	end
	st.state = won and QTEEngine.STATES.Won or QTEEngine.STATES.Lost
	st.score = clamp01(score)
	st.reason = reason
end

-- A miss is any input that the QTE did not want. The catalogue decides how many a
-- QTE tolerates; the default is none, which is what makes "one extra press is a
-- fail" (ExactTaps) expressible without a special case.
local function miss(st: any, task: any, score: number?, reason: string?): ()
	st.misses += 1
	local allowed = task.params.maxMisses
	if allowed == nil then
		allowed = 0
	end
	if st.misses > allowed then
		resolve(st, false, score or 0, reason or QTEEngine.REASONS.WrongInput)
	end
end

-- ── Mode metadata ────────────────────────────────────────────────────────────
-- cost(task, human) -> {keys, pointer, read, think} in "player effort" units;
-- QTEEngine.cost turns it into seconds. `pointer` is measured in screens of travel
-- and `think` in seconds of deliberation, so a QTE that needs a sorting decision or
-- mental arithmetic pays for it here instead of pretending the reading is free.
local MODES = {}

-- ids() lists known modes (used by tests to prove the catalogue has no typos).
local modeOrder = {}

local function defineMode(id: string, mode: any): ()
	MODES[id] = mode
	modeOrder[#modeOrder + 1] = id
end

QTEEngine.MODES = MODES
QTEEngine.MODE_ORDER = modeOrder

-- ═════════════════════════════════════════════════════════════════════════════
--  MODES
--  Each mode implements any of: cost / init / onPress / onRelease / onClick /
--  tick / expect. Anything a mode does not implement is a no-op.
-- ═════════════════════════════════════════════════════════════════════════════

-- ── press: hit one key before the clock runs out ─────────────────────────────
defineMode("press", {
	cost = function()
		return { keys = 1, read = QTEConfig.Human.ReadSeconds }
	end,
	init = function(st, task)
		st.expectToken = task.params.key
	end,
	onPress = function(st, task, ctx, token)
		if token == task.params.key or task.params.anyKey then
			resolve(st, true, 0.55 + 0.45 * (ctx.remaining / ctx.limit), QTEEngine.REASONS.Complete)
		elseif task.params.strict ~= false then
			miss(st, task, 0, QTEEngine.REASONS.WrongInput)
		end
	end,
	expect = function(st)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "key", token = st.expectToken }
	end,
})

-- ── react: wait for the cue, then hit it. Early input is a false start ───────
defineMode("react", {
	cost = function(task)
		local p = task.params
		-- The budget must cover the SILENT WAIT before the cue plus the window
		-- after it. Without the wait the director can hand out a limit that ends
		-- before the cue even appears, which is how a react QTE becomes a coin toss.
		return { keys = 1, read = QTEConfig.Human.ReactionSeconds + p.cueAt, think = 0.3 + p.window }
	end,
	init = function(st, task)
		st.cueAt = task.params.cueAt
		st.cued = false
	end,
	onPress = function(st, task, ctx, token)
		if hasToken(task.params.keys, token) or task.params.anyKey then
			if st.cued then
				local over = st.elapsed - st.cueAt
				if over <= task.params.window then
					resolve(st, true, 1 - 0.4 * clamp01(over / task.params.window), QTEEngine.REASONS.Complete)
				else
					resolve(st, false, 0, QTEEngine.REASONS.Missed)
				end
			elseif task.params.falseStart ~= false then
				resolve(st, false, 0, QTEEngine.REASONS.FalseStart)
			end
		end
	end,
	tick = function(st, task, ctx)
		if not st.cued and st.elapsed >= st.cueAt then
			st.cued = true
			st.prompt = task.params.cueText or "NOW!"
			st.sub = task.params.cueSub or task.sub
		end
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running or not st.cued then
			return { kind = "none" }
		end
		-- Even a "press anything" QTE hands the solver one concrete key to press,
		-- otherwise the expect channel is unusable for automated play.
		local keys = task.params.keys
		local token = (keys and keys[1]) or task.params.expectToken or "E"
		return { kind = "key", token = token }
	end,
})

-- ── mash: fill a counter with repeated presses of one key ────────────────────
defineMode("mash", {
	cost = function(task)
		return { keys = task.params.count, read = QTEConfig.Human.ReadSeconds }
	end,
	init = function(st, task)
		st.required = task.params.count
		st.count = 0
		st.expectToken = task.params.key
		st.sub = task.params.sub or ("Press " .. tostring(task.params.count) .. " times")
	end,
	onPress = function(st, task, ctx, token)
		if token ~= task.params.key then
			if task.params.strict then
				miss(st, task, st.count / math.max(1, st.required), QTEEngine.REASONS.WrongInput)
			end
			return
		end
		st.count += 1
		st.progress = st.count / math.max(1, st.required)
		st.prompt = task.label .. "  " .. tostring(math.max(0, st.required - st.count))
		if st.count >= st.required then
			local speed = clamp01(ctx.remaining / math.max(0.001, ctx.limit))
			resolve(st, true, 0.7 + 0.3 * speed, QTEEngine.REASONS.Complete)
		end
	end,
	expect = function(st)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "key", token = st.expectToken }
	end,
})

-- ── alternate: two keys, strictly alternating ────────────────────────────────
defineMode("alternate", {
	cost = function(task)
		return { keys = task.params.count, read = QTEConfig.Human.ReadSeconds }
	end,
	-- params: {cycle = {"Q","E"} | a/b pair, count}
	init = function(st, task)
		st.required = task.params.count
		st.count = 0
		st.lastToken = nil
		st.cycle = task.params.cycle or { task.params.a, task.params.b }
		st.cycleIndex = 1
		st.expectToken = st.cycle[1]
	end,
	onPress = function(st, task, ctx, token)
		if not hasToken(st.cycle, token) then
			return
		end
		local want = st.expectToken
		if token ~= want then
			miss(st, task, st.count / math.max(1, st.required), QTEEngine.REASONS.WrongInput)
			return
		end
		st.count += 1
		st.lastToken = token
		st.cycleIndex = st.cycleIndex + 1
		if st.cycleIndex > #st.cycle then
			st.cycleIndex = 1
		end
		st.expectToken = st.cycle[st.cycleIndex]
		st.progress = st.count / math.max(1, st.required)
		st.prompt = task.label .. "  " .. tostring(math.max(0, st.required - st.count))
		if st.count >= st.required then
			resolve(st, true, 0.7 + 0.3 * clamp01(ctx.remaining / math.max(0.001, ctx.limit)), QTEEngine.REASONS.Complete)
		end
	end,
	expect = function(st)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "key", token = st.expectToken }
	end,
})

-- ── sequence: ordered keys, forward or reversed ──────────────────────────────
defineMode("sequence", {
	cost = function(task)
		local n = #task.params.keys
		local think = (task.params.order == "reverse") and n * 0.25 or 0
		return { keys = n, read = QTEConfig.Human.ReadSeconds, think = think }
	end,
	init = function(st, task)
		st.order = {}
		if task.params.order == "reverse" then
			for i = 1, #task.params.keys do
				st.order[i] = task.params.keys[#task.params.keys - i + 1]
			end
		else
			for i = 1, #task.params.keys do
				st.order[i] = task.params.keys[i]
			end
		end
		st.index = 1
		st.chips = task.params.keys
		st.expectToken = st.order[1]
	end,
	onPress = function(st, task, ctx, token)
		if not hasToken(task.params.keys, token) then
			return
		end
		if token == st.order[st.index] then
			st.index += 1
			st.progress = (st.index - 1) / #st.order
			if st.index > #st.order then
				resolve(st, true, 0.75 + 0.25 * clamp01(ctx.remaining / math.max(0.001, ctx.limit)), QTEEngine.REASONS.Complete)
				return
			end
			st.expectToken = st.order[st.index]
			st.prompt = task.label .. "  " .. tostring(#st.order - st.index + 1) .. " left"
		else
			miss(st, task, st.progress, QTEEngine.REASONS.WrongInput)
			if task.params.restartOnMiss and st.state == QTEEngine.STATES.Running then
				st.index = 1
				st.progress = 0
				st.expectToken = st.order[1]
			end
		end
	end,
	expect = function(st)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "key", token = st.expectToken }
	end,
})

-- ── hold: keep one key down for a duration ───────────────────────────────────
defineMode("hold", {
	cost = function(task)
		return { keys = 1, read = QTEConfig.Human.ReadSeconds, think = task.params.seconds }
	end,
	init = function(st, task)
		st.held = 0
		st.required = task.params.seconds
		st.expectToken = task.params.key
		st.sub = "Keep it down for " .. string.format("%.1f", task.params.seconds) .. "s"
	end,
	tick = function(st, task, ctx)
		local down = ctx.held(task.params.key)
		if down then
			st.held = math.min(st.required, st.held + ctx.dt)
			if st.held >= st.required then
				resolve(st, true, 1, QTEEngine.REASONS.Complete)
				return
			end
		end
		st.progress = st.held / st.required
		st.prompt = task.label .. "  " .. string.format("%.1f / %.1f", st.held, st.required)
	end,
	onRelease = function(st, task, ctx, token)
		if token ~= task.params.key or st.state ~= QTEEngine.STATES.Running then
			return
		end
		if st.held < st.required * 0.98 then
			if task.params.allowRestart == false then
				resolve(st, false, st.held / st.required, QTEEngine.REASONS.EarlyRelease)
			else
				miss(st, task, st.held / st.required, QTEEngine.REASONS.EarlyRelease)
				st.held = 0
				st.progress = 0
			end
		end
	end,
	expect = function(st)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "hold", token = st.expectToken }
	end,
})

-- ── holdAll: every key down at once, held for a duration ─────────────────────
defineMode("holdAll", {
	cost = function(task)
		return { keys = #task.params.keys, read = QTEConfig.Human.ReadSeconds, think = task.params.seconds }
	end,
	init = function(st, task)
		st.held = 0
		st.required = task.params.seconds
		st.sub = "Hold all " .. tostring(#task.params.keys) .. " together"
	end,
	tick = function(st, task, ctx)
		local all = true
		for i = 1, #task.params.keys do
			if not ctx.held(task.params.keys[i]) then
				all = false
				break
			end
		end
		if all then
			st.held = math.min(st.required, st.held + ctx.dt)
			if st.held >= st.required then
				resolve(st, true, 1, QTEEngine.REASONS.Complete)
				return
			end
		else
			st.held = 0
		end
		st.progress = st.held / st.required
		st.prompt = task.label .. "  " .. string.format("%.1f / %.1f", st.held, st.required)
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "hold", token = task.params.keys[1], alsoHold = task.params.keys }
	end,
})

-- ── timed: hit a beat, once or on a repeating rhythm ─────────────────────────
-- cueSource = "clock" cues itself; "beat" is driven by the world (a footstep
-- animation marker or a server event) arriving as sample.beat.
--
-- A cue OPENS `window` seconds early and closes `window` seconds late, so a press
-- that is slightly ahead of the beat is judged as "early but inside the window"
-- rather than as a false start. v5 compared a press against the single next cue and
-- would have failed a player who pressed 30 ms early.
defineMode("timed", {
	cost = function(task)
		local p = task.params
		-- The limit has to outlast the LAST cue, not the first: a four-beat rhythm
		-- whose window closes after the third beat is a QTE nobody can finish.
		local span
		if p.cueSource == "beat" then
			-- The first beat can be a whole interval away, then every beat after it,
			-- then the final window.
			span = p.beats * (p.beatAssumed or 0.55) + p.window
		else
			span = p.firstCue + (p.beats - 1) * p.interval + p.window
		end
		return { keys = p.beats, read = QTEConfig.Human.ReadSeconds + span, think = 0 }
	end,
	init = function(st, task)
		st.opened = 0
		st.hits = 0
		st.judged = {}
		st.expectToken = task.params.key
		st.sub = "Press on the beat"
	end,
	tick = function(st, task, ctx)
		local p = task.params
		if p.cueSource == "beat" then
			if ctx.sample.beat then
				st.opened += 1
				st.judged[st.opened] = false
				st.lastCue = { index = st.opened, at = st.elapsed, hit = false }
				st.prompt = task.label .. "  NOW"
			end
			local cue = st.lastCue
			if cue and not cue.hit and (st.elapsed - cue.at) > p.window then
				cue.hit = true
				miss(st, task, st.hits / math.max(1, p.beats), QTEEngine.REASONS.Missed)
			end
			return
		end
		-- Clock source: a cue opens at t_i - window and closes at t_i + window.
		while st.opened < p.beats and st.elapsed >= (p.firstCue + st.opened * p.interval) - p.window do
			st.opened += 1
			st.judged[st.opened] = false
			st.prompt = task.label .. "  NOW"
		end
		for i = 1, st.opened do
			local at = p.firstCue + (i - 1) * p.interval
			if st.judged[i] == false and st.elapsed > at + p.window then
				st.judged[i] = true
				miss(st, task, st.hits / math.max(1, p.beats), QTEEngine.REASONS.Missed)
			end
		end
	end,
	onPress = function(st, task, ctx, token)
		local p = task.params
		if token ~= p.key then
			if p.strict then
				miss(st, task, st.hits / math.max(1, p.beats), QTEEngine.REASONS.WrongInput)
			end
			return
		end
		if p.cueSource == "beat" then
			local cue = st.lastCue
			if cue == nil or cue.hit then
				miss(st, task, st.hits / math.max(1, p.beats), QTEEngine.REASONS.FalseStart)
				return
			end
			local offset = math.abs(st.elapsed - cue.at)
			cue.hit = true
			if offset <= p.window then
				st.hits += 1
				st.progress = st.hits / math.max(1, p.beats)
				if st.hits >= p.beats then
					resolve(st, true, 1, QTEEngine.REASONS.Complete)
				end
			else
				miss(st, task, st.hits / math.max(1, p.beats), QTEEngine.REASONS.Missed)
			end
			return
		end
		-- Judge against the nearest open, unjudged cue.
		local best, bestOffset = nil, math.huge
		for i = 1, st.opened do
			if st.judged[i] == false then
				local at = p.firstCue + (i - 1) * p.interval
				local offset = math.abs(st.elapsed - at)
				if offset < bestOffset then
					best, bestOffset = i, offset
				end
			end
		end
		if best == nil then
			miss(st, task, st.hits / math.max(1, p.beats), QTEEngine.REASONS.FalseStart)
			return
		end
		st.judged[best] = true
		if bestOffset <= p.window then
			st.hits += 1
			st.progress = st.hits / math.max(1, p.beats)
			if st.hits >= p.beats then
				resolve(st, true, 1, QTEEngine.REASONS.Complete)
			end
		else
			miss(st, task, st.hits / math.max(1, p.beats), QTEEngine.REASONS.Missed)
		end
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		local p = task.params
		if p.cueSource == "beat" then
			if st.lastCue and not st.lastCue.hit then
				return { kind = "key", token = p.key }
			end
			return { kind = "none" }
		end
		-- Aim the solver at the next unjudged cue; the bot presses when `now >= at`.
		-- `at` is the beat, `atEnd` the moment its window closes: a solver that
		-- reacts to the cue needs both to land inside it.
		for i = 1, p.beats do
			if st.judged[i] == false or st.judged[i] == nil then
				local at = p.firstCue + (i - 1) * p.interval
				return { kind = "key", token = p.key, at = at, atEnd = at + p.window }
			end
		end
		return { kind = "none" }
	end,
})

-- ── release: trigger while a sweeping marker is inside the zone ──────────────
-- trigger = "press"  -> a discrete press (SlideBar, FuseCut)
-- trigger = "release"-> hold first, then let go inside the zone (TimedRelease)
defineMode("release", {
	cost = function(task)
		local p = task.params
		local wait = 0.5
		if p.style ~= "sweep" then
			wait = (p.period or 2.0) * 0.5
		end
		return { keys = 1, read = QTEConfig.Human.ReadSeconds, think = wait }
	end,
	init = function(st, task)
		st.value = 0
		st.holding = false
		st.zone = task.params.zone
	end,
	marker = function(st, task, ctx)
		local p = task.params
		if p.style == "sweep" then
			return clamp01(ctx.now / math.max(0.001, ctx.limit))
		end
		return pingpong(ctx.now + (p.phaseOffset or 0), p.period or 2.0)
	end,
	tick = function(st, task, ctx)
		st.value = MODES.release.marker(st, task, ctx)
		if st.state ~= QTEEngine.STATES.Running then
			return
		end
		if st.holding then
			st.prompt = task.label .. "  release in the zone"
		end
	end,
	onPress = function(st, task, ctx, token)
		if token ~= task.params.key then
			return
		end
		st.holding = true
		if task.params.trigger == "release" then
			return
		end
		local v = MODES.release.marker(st, task, ctx)
		if v >= st.zone.from and v <= st.zone.to then
			resolve(st, true, 1, QTEEngine.REASONS.Complete)
		else
			miss(st, task, 0, QTEEngine.REASONS.Missed)
		end
	end,
	onRelease = function(st, task, ctx, token)
		if token ~= task.params.key or task.params.trigger ~= "release" or not st.holding then
			return
		end
		st.holding = false
		local v = MODES.release.marker(st, task, ctx)
		if v >= st.zone.from and v <= st.zone.to then
			resolve(st, true, 1, QTEEngine.REASONS.Complete)
		else
			miss(st, task, 0, QTEEngine.REASONS.Missed)
		end
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		local key = task.params.key
		if task.params.trigger ~= "release" then
			-- A precision press is only expected while the marker is in the zone.
			-- Asking for the press from frame one is the same trap for the solver
			-- that an unmarked bar is for the player.
			if st.value >= st.zone.from and st.value <= st.zone.to then
				return { kind = "key", token = key }
			end
			return { kind = "none" }
		end
		if not st.holding then
			return { kind = "hold", token = key }
		end
		if st.value >= st.zone.from and st.value <= st.zone.to then
			return { kind = "release", token = key }
		end
		return { kind = "hold", token = key }
	end,
})

-- ── exact: press exactly N times, then stop ──────────────────────────────────
defineMode("exact", {
	cost = function(task)
		return { keys = task.params.count + 1, read = QTEConfig.Human.ReadSeconds, think = task.params.settle }
	end,
	init = function(st, task)
		st.count = 0
		st.required = task.params.count
		st.overAt = nil
		st.sub = "One extra press is a fail"
	end,
	onPress = function(st, task, ctx, token)
		if token ~= task.params.key then
			return
		end
		st.count += 1
		if st.count > st.required then
			resolve(st, false, st.required / (st.count), QTEEngine.REASONS.ExtraInput)
			return
		end
		st.progress = st.count / st.required
		if st.count == st.required then
			st.overAt = st.elapsed
		end
	end,
	tick = function(st, task, ctx)
		if st.overAt and (st.elapsed - st.overAt) >= task.params.settle then
			resolve(st, true, 1, QTEEngine.REASONS.Complete)
		end
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running or st.count >= st.required then
			return { kind = "none" }
		end
		return { kind = "key", token = task.params.key }
	end,
})

-- ── type: enter a string of letter/digit tokens ──────────────────────────────
-- Covers WordType, WordRecall, MathCalc, FlashDigit, PhoneDial and CountFlash: the
-- difference between them is only whether the text was shown, masked, or heard.
defineMode("type", {
	cost = function(task)
		local p = task.params
		local read = QTEConfig.Human.ReadSeconds + (p.showSeconds or 0)
		local think = (p.thinkPerChar or 0) * #p.text
		if p.source == "arithmetic" then
			read = QTEConfig.Human.ReadLongSeconds
			think = QTEConfig.Human.ThinkPerDigit * #p.text
		end
		return { keys = #p.text, read = read, think = think }
	end,
	init = function(st, task)
		st.entered = {}
		st.index = 1
		st.text = task.params.text
		st.phase = task.params.showSeconds and "show" or "type"
		st.reveal = task.params.reveal
		st.maskNext = task.params.maskNext
		st.showClock = 0
		st.answerText = task.params.text
		st.answerVisible = task.params.showSeconds ~= nil
	end,
	tick = function(st, task, ctx)
		if st.phase ~= "show" then
			return
		end
		st.showClock += ctx.dt
		if st.showClock >= task.params.showSeconds then
			st.phase = "type"
			st.answerVisible = false
			st.prompt = task.params.recallPrompt or task.label
			st.sub = task.params.recallSub or task.sub
		end
	end,
	onPress = function(st, task, ctx, token)
		if st.phase == "show" then
			return
		end
		if token == "Backspace" and task.params.allowBackspace and st.index > 1 then
			st.index -= 1
			st.entered[st.index] = nil
			st.prompt = task.label .. "  " .. st:masked()
			return
		end
		if st.index > #st.text then
			return
		end
		local want = st.text:sub(st.index, st.index)
		if token == want or tokenForChar(want) == token then
			st.entered[st.index] = want
			st.index += 1
			st.progress = (st.index - 1) / #st.text
			st.prompt = task.label .. "  " .. st:masked()
			if st.index > #st.text then
				resolve(st, true, 0.8 + 0.2 * clamp01(ctx.remaining / math.max(0.001, ctx.limit)), QTEEngine.REASONS.Complete)
			end
		else
			miss(st, task, (st.index - 1) / #st.text, QTEEngine.REASONS.WrongInput)
		end
	end,
	expect = function(st)
		if st.state ~= QTEEngine.STATES.Running or st.index > #st.text or st.phase == "show" then
			return { kind = "none" }
		end
		-- Hand out the input token, not the character: "4" is pressed as Four.
		return { kind = "key", token = tokenForChar(st.text:sub(st.index, st.index)) }
	end,
})

-- ── sort: press the shown symbols in ascending order ─────────────────────────
-- kind = "alpha" (letters) or "numeric" (digits). The engine computes the answer
-- from the shown items, so the catalogue cannot ship a wrong "correct order".
defineMode("sort", {
	cost = function(task)
		local n = #task.params.items
		return { keys = n, read = QTEConfig.Human.ReadSeconds, think = 0.35 * n }
	end,
	init = function(st, task)
		st.sorted = {}
		for i = 1, #task.params.items do
			st.sorted[i] = task.params.items[i]
		end
		if task.params.kind == "numeric" then
			-- "Eight" < "Five" alphabetically, which is not "ascending". Compare the
			-- digits the tokens stand for, and keep the original order on ties.
			table.sort(st.sorted, function(a, b)
				return (tonumber(digitOf(a) or "") or 0) < (tonumber(digitOf(b) or "") or 0)
			end)
		else
			table.sort(st.sorted)
		end
		st.index = 1
		st.chips = task.params.items
		st.expectToken = st.sorted[1]
	end,
	onPress = function(st, task, ctx, token)
		if not hasToken(task.params.items, token) then
			return
		end
		if token == st.sorted[st.index] then
			st.index += 1
			st.progress = (st.index - 1) / #st.sorted
			if st.index > #st.sorted then
				resolve(st, true, 1, QTEEngine.REASONS.Complete)
				return
			end
			st.expectToken = st.sorted[st.index]
			st.prompt = task.label .. "  " .. tostring(#st.sorted - st.index + 1) .. " left"
		else
			miss(st, task, (st.index - 1) / #st.sorted, QTEEngine.REASONS.WrongInput)
		end
	end,
	expect = function(st)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "key", token = st.expectToken }
	end,
})

-- ── classify: answer a stream of questions, N in a row ───────────────────────
defineMode("classify", {
	cost = function(task)
		return { keys = task.params.needed, read = QTEConfig.Human.ReadSeconds, think = task.params.needed * 0.7 }
	end,
	init = function(st, task)
		st.item = 1
		st.correct = 0
		st.itemCorrect = 0
		st.shown = task.params.items[1]
	end,
	onPress = function(st, task, ctx, token)
		local p = task.params
		if not hasToken(p.keys, token) then
			return
		end
		local said = (token == st.shown.token)
		if said then
			st.correct += 1
			st.progress = st.correct / math.max(1, p.needed)
			if st.correct >= p.needed then
				resolve(st, true, 1, QTEEngine.REASONS.Complete)
				return
			end
			st.item += 1
			if st.item > #p.items then
				st.item = 1
			end
			st.shown = p.items[st.item]
		else
			miss(st, task, st.correct / math.max(1, p.needed), QTEEngine.REASONS.WrongInput)
			if st.state == QTEEngine.STATES.Running then
				st.item += 1
				if st.item > #p.items then
					st.item = 1
				end
				st.shown = p.items[st.item]
			end
		end
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "key", token = st.shown.token }
	end,
})

-- ── memorise: show a sequence, hide it, then require it back ─────────────────
-- entry = "forward" | "reverse" | "last". `colour` items (Stroop/colour sequences)
-- are tokens with a colour attached; the answer is always the token.
defineMode("memorise", {
	cost = function(task)
		local p = task.params
		local n = #p.items
		local flash = p.showAll and (p.flashSeconds or 1.5) or (n * (p.flashPerItem or 0.6))
		return { keys = n, read = QTEConfig.Human.ReadSeconds + flash, think = n * 0.3 }
	end,
	init = function(st, task)
		st.flashIndex = 0
		st.flashClock = 0
		st.phase = "flash"
		st.index = 1
		st.order = {}
		st.answerText = ""
		st.answerVisible = true
		st.flashDuration = task.params.showAll
				and (task.params.flashSeconds or 1.5)
			or (#task.params.items * task.params.flashPerItem)
		local items = task.params.items
		if task.params.entry == "last" then
			st.order[1] = items[#items].token or items[#items]
		elseif task.params.entry == "reverse" then
			for i = 1, #items do
				st.order[i] = (items[#items - i + 1].token or items[#items - i + 1])
			end
		else
			for i = 1, #items do
				st.order[i] = (items[i].token or items[i])
			end
		end
		for i = 1, #st.order do
			st.answerText = st.answerText .. st.order[i]
		end
	end,
	tick = function(st, task, ctx)
		local p = task.params
		if st.phase == "flash" then
			st.flashClock += ctx.dt
			-- showAll flashes the whole string at once and has no per-item beat.
			local idx = 1
			if not p.showAll then
				idx = math.floor(st.flashClock / (p.flashPerItem or 0.6)) + 1
			end
			if idx > #p.items + (p.gapAfter or 0) or st.flashClock >= st.flashDuration then
				st.phase = "recall"
				st.answerVisible = false
				st.prompt = task.params.recallPrompt or "REPEAT IT!"
				st.sub = task.params.recallSub or "In order"
			else
				st.flashIndex = math.min(idx, #p.items)
				st.prompt = task.params.flashPrompt or "MEMORISE"
			end
			return
		end
		st.answerVisible = false
	end,
	onPress = function(st, task, ctx, token)
		if st.phase == "flash" then
			return
		end
		if not hasToken(st.order, token) then
			return
		end
		if token == st.order[st.index] then
			st.index += 1
			st.progress = (st.index - 1) / #st.order
			if st.index > #st.order then
				resolve(st, true, 1, QTEEngine.REASONS.Complete)
				return
			end
			st.prompt = task.label .. "  " .. tostring(#st.order - st.index + 1) .. " left"
		else
			miss(st, task, (st.index - 1) / #st.order, QTEEngine.REASONS.WrongInput)
		end
	end,
	expect = function(st)
		if st.state ~= QTEEngine.STATES.Running or st.phase == "flash" then
			return { kind = "none" }
		end
		return { kind = "key", token = st.order[st.index] }
	end,
})

-- ── count: flash N shapes, then type how many there were ─────────────────────
defineMode("count", {
	cost = function(task)
		return { keys = 1, read = QTEConfig.Human.ReadSeconds + task.params.flashSeconds, think = 0.8 }
	end,
	init = function(st, task)
		st.phase = "flash"
		st.flashClock = 0
		st.typing = nil
		st.answerText = tostring(task.params.count)
		st.answerVisible = true
		st.answer = tostring(task.params.count)
	end,
	tick = function(st, task, ctx)
		if st.phase == "flash" then
			st.flashClock += ctx.dt
			if st.flashClock >= task.params.flashSeconds then
				st.phase = "answer"
				st.answerVisible = false
				st.prompt = task.label .. "  how many?"
			end
		end
	end,
	onPress = function(st, task, ctx, token)
		if st.phase ~= "answer" then
			return
		end
		local digit = digitOf(token)
		if digit == nil then
			if token == "E" or token == "Q" then
				miss(st, task, 0, QTEEngine.REASONS.WrongInput)
			end
			return
		end
		if digit == st.answer then
			resolve(st, true, 1, QTEEngine.REASONS.Complete)
		else
			miss(st, task, 0, QTEEngine.REASONS.WrongInput)
		end
	end,
	expect = function(st)
		if st.state ~= QTEEngine.STATES.Running or st.phase ~= "answer" then
			return { kind = "none" }
		end
		return { kind = "key", token = tokenForChar(st.answer) }
	end,
})

-- ── idle: hold nothing ───────────────────────────────────────────────────────
defineMode("idle", {
	cost = function(task)
		return { keys = 0, read = QTEConfig.Human.ReadSeconds, think = task.params.seconds }
	end,
	init = function(st, task)
		st.required = task.params.seconds
		st.sub = "Do not press anything"
	end,
	tick = function(st, task, ctx)
		st.progress = clamp01(st.elapsed / st.required)
		if st.elapsed >= st.required then
			resolve(st, true, 1, QTEEngine.REASONS.Complete)
			return
		end
		st.prompt = task.label .. "  " .. string.format("%.1f", st.required - st.elapsed)
	end,
	onPress = function(st, task, ctx, token)
		resolve(st, false, st.progress, QTEEngine.REASONS.FalseStart)
	end,
	onClick = function(st, task, ctx, point)
		resolve(st, false, st.progress, QTEEngine.REASONS.FalseStart)
	end,
	expect = function(st)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "none" }
	end,
})

-- ── steady: hold the pointer still, then click ───────────────────────────────
defineMode("steady", {
	cost = function(task)
		return { keys = 1, read = QTEConfig.Human.ReadSeconds, think = task.params.seconds + task.params.clickWindow }
	end,
	init = function(st, task)
		st.still = 0
		st.ready = false
		st.required = task.params.seconds
	end,
	tick = function(st, task, ctx)
		local speed = ctx.pointerSpeed
		if speed <= task.params.maxSpeed then
			st.still = math.min(st.required, st.still + ctx.dt)
		else
			st.still = 0
			st.ready = false
		end
		if st.still >= st.required and not st.ready then
			st.ready = true
			st.readyAt = st.elapsed
			st.prompt = task.label .. "  CLICK"
		end
		if st.ready and (st.elapsed - (st.readyAt or 0)) > task.params.clickWindow then
			resolve(st, false, st.still / st.required, QTEEngine.REASONS.Missed)
			return
		end
		st.progress = st.still / st.required
	end,
	onClick = function(st, task, ctx, point)
		if st.ready then
			resolve(st, true, 1, QTEEngine.REASONS.Complete)
		else
			resolve(st, false, st.still / st.required, QTEEngine.REASONS.FalseStart)
		end
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		if st.ready then
			return { kind = "click" }
		end
		return { kind = "pointer", x = task.params.centerX or 0.5, y = task.params.centerY or 0.5 }
	end,
})

-- ── track: keep the pointer inside a moving ring ─────────────────────────────
defineMode("track", {
	cost = function(task)
		local p = task.params
		local screens = p.radius * 2 * math.pi * p.speed * p.seconds
		return { keys = 0, read = QTEConfig.Human.ReadSeconds, think = p.seconds, pointer = screens }
	end,
	init = function(st, task)
		st.held = 0
		st.drift = 0
		st.required = task.params.seconds
	end,
	position = function(st, task, ctx)
		local p = task.params
		local x = 0.5 + math.cos(ctx.now * p.speed * math.pi * 2 + p.phase) * p.radius * p.ratioX
		local y = 0.5 + math.sin(ctx.now * p.speed * math.pi * 2 + p.phase) * p.radius
		return x, y
	end,
	tick = function(st, task, ctx)
		local x, y = MODES.track.position(st, task, ctx)
		st.markerX, st.markerY = x, y
		local dx = ctx.sample.pointer.x - x
		local dy = ctx.sample.pointer.y - y
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist <= task.params.tolerance then
			st.held = math.min(st.required, st.held + ctx.dt)
			st.drift = 0
			if st.held >= st.required then
				resolve(st, true, 0.7 + 0.3 * clamp01(ctx.remaining / math.max(0.001, ctx.limit)), QTEEngine.REASONS.Complete)
				return
			end
		else
			st.drift += ctx.dt
			if st.drift > task.params.maxDrift then
				resolve(st, false, st.held / st.required, QTEEngine.REASONS.Drifted)
				return
			end
		end
		st.progress = st.held / st.required
		st.prompt = task.label .. "  " .. string.format("%.1f", st.required - st.held)
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "pointer", x = st.markerX or 0.5, y = st.markerY or 0.5 }
	end,
})

-- ── hit: click a set of targets ─────────────────────────────────────────────
defineMode("hit", {
	cost = function(task)
		local p = task.params
		return { keys = #p.targets, read = QTEConfig.Human.ReadSeconds, pointer = #p.targets * 0.6 }
	end,
	init = function(st, task)
		st.remaining = {}
		for i = 1, #task.params.targets do
			st.remaining[i] = true
		end
		st.killed = 0
		st.required = #task.params.targets
	end,
	tick = function(st, task, ctx)
		st.pointer = ctx.sample.pointer
		st.positions = {}
		for i = 1, #task.params.targets do
			local t = task.params.targets[i]
			local x, y = t.x, t.y
			if t.speed then
				x = t.x + math.cos(ctx.now * t.speed * math.pi * 2 + (t.phase or 0)) * (t.travelX or 0.1)
				y = t.y + math.sin(ctx.now * t.speed * math.pi * 2 * 1.31 + (t.phase or 0)) * (t.travelY or 0.06)
			end
			st.positions[i] = { x = clamp01(x), y = clamp01(y) }
		end
	end,
	onClick = function(st, task, ctx, point)
		for i = 1, #task.params.targets do
			if st.remaining[i] then
				local pos = st.positions and st.positions[i]
				if pos then
					local dx = point.x - pos.x
					local dy = point.y - pos.y
					if math.sqrt(dx * dx + dy * dy) <= task.params.targets[i].radius then
						st.remaining[i] = false
						st.killed += 1
						st.progress = st.killed / st.required
						if st.killed >= st.required then
							resolve(st, true, 1, QTEEngine.REASONS.Complete)
						end
						return
					end
				end
			end
		end
		miss(st, task, st.killed / st.required, QTEEngine.REASONS.Missed)
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		for i = 1, #task.params.targets do
			if st.remaining[i] and st.positions and st.positions[i] then
				local pos = st.positions[i]
				-- Click only when the pointer is already inside the target. The old
				-- contract shipped click=true from frame one, so an obedient player
				-- clicked at the wrong moment and lost before the first tick.
				local inside = false
				local pointer = st.pointer
				if pointer then
					local dx = pointer.x - pos.x
					local dy = pointer.y - pos.y
					inside = math.sqrt(dx * dx + dy * dy) <= task.params.targets[i].radius
				end
				return { kind = "pointer", x = pos.x, y = pos.y, click = inside }
			end
		end
		return { kind = "none" }
	end,
})

-- ── aim: move the pointer onto a static target ───────────────────────────────
defineMode("aim", {
	cost = function(task)
		return { keys = 0, read = QTEConfig.Human.ReadSeconds, pointer = task.params.target.distance or 0.7 }
	end,
	init = function(st, task)
		st.target = task.params.target
	end,
	tick = function(st, task, ctx)
		local dx = ctx.sample.pointer.x - st.target.x
		local dy = ctx.sample.pointer.y - st.target.y
		local dist = math.sqrt(dx * dx + dy * dy)
		st.aimDistance = dist
		if dist <= st.target.radius then
			resolve(st, true, 0.6 + 0.4 * clamp01(ctx.remaining / math.max(0.001, ctx.limit)), QTEEngine.REASONS.Complete)
			return
		end
		st.progress = clamp01(1 - dist / math.max(0.001, st.target.distance or 1))
	end,
	expect = function(st)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "pointer", x = st.target.x, y = st.target.y }
	end,
})

-- ── trace: drag the pointer through waypoints in order ───────────────────────
defineMode("trace", {
	cost = function(task, human)
		local p = task.params
		local total = 0
		local prev = { x = 0.5, y = 0.5 }
		for i = 1, #p.points do
			local dx = p.points[i].x - prev.x
			local dy = p.points[i].y - prev.y
			total += math.sqrt(dx * dx + dy * dy)
			prev = p.points[i]
		end
		return { keys = 0, read = QTEConfig.Human.ReadSeconds, pointer = total * 1.2, think = p.showSeconds }
	end,
	init = function(st, task)
		st.index = 1
	end,
	tick = function(st, task, ctx)
		if st.elapsed < task.params.showSeconds then
			st.progress = 0
			return
		end
		local point = task.params.points[st.index]
		local dx = ctx.sample.pointer.x - point.x
		local dy = ctx.sample.pointer.y - point.y
		if math.sqrt(dx * dx + dy * dy) <= task.params.tolerance then
			st.index += 1
			st.progress = (st.index - 1) / #task.params.points
			if st.index > #task.params.points then
				resolve(st, true, 1, QTEEngine.REASONS.Complete)
				return
			end
		end
		st.prompt = task.label .. "  " .. tostring(#task.params.points - st.index + 1) .. " left"
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		local point = task.params.points[math.min(st.index, #task.params.points)]
		return { kind = "pointer", x = point.x, y = point.y }
	end,
})

-- ── shake: accumulate pointer travel, fast ───────────────────────────────────
defineMode("shake", {
	cost = function(task, human)
		local p = task.params
		local scale = QTEConfig.Human.PointerScreensPerSecond / p.speed
		return { keys = 0, read = QTEConfig.Human.ReadSeconds, pointer = p.requiredScreens * scale, think = 0 }
	end,
	init = function(st, task)
		st.travel = 0
		st.required = task.params.requiredScreens
		st.slow = 0
	end,
	tick = function(st, task, ctx)
		st.travel += ctx.pointerTravel
		st.progress = clamp01(st.travel / st.required)
		if st.travel >= st.required then
			resolve(st, true, 0.7 + 0.3 * clamp01(ctx.remaining / math.max(0.001, ctx.limit)), QTEEngine.REASONS.Complete)
			return
		end
		if ctx.pointerTravel / math.max(0.001, ctx.dt) < task.params.speed * 0.35 then
			st.slow += ctx.dt
		else
			st.slow = 0
		end
		st.prompt = task.label .. "  " .. tostring(math.floor(st.progress * 100)) .. "%"
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		-- Alternate hard left/right of the current pointer position.
		local side = (math.floor(st.elapsed * 12) % 2 == 0) and 0.05 or 0.95
		return { kind = "pointer", x = side, y = 0.5 }
	end,
})

-- ── spin: accumulate rotation about the centre, optionally by phase ──────────
defineMode("spin", {
	cost = function(task, human)
		local p = task.params
		local total = 0
		for i = 1, #p.turns do
			total += p.turns[i]
		end
		-- One full turn of the 0.3-radius ring is ~1.9 screens of pointer travel, so
		-- the old 0.55-per-turn price under-priced every spin by about 3.5x.
		return { keys = 0, read = QTEConfig.Human.ReadSeconds, pointer = total * 1.9, think = 0 }
	end,
	init = function(st, task)
		st.phase = 1
		st.accum = 0
		st.lastAngle = nil
		st.turns = task.params.turns
		st.directions = task.params.directions
	end,
	angle = function(st, ctx)
		local p = ctx.sample.pointer
		return atan2(p.y - 0.5, p.x - 0.5)
	end,
	tick = function(st, task, ctx)
		local a = MODES.spin.angle(st, ctx)
		if st.lastAngle == nil then
			st.lastAngle = a
			return
		end
		local d = a - (st.lastAngle :: number)
		if d > math.pi then
			d -= math.pi * 2
		elseif d < -math.pi then
			d += math.pi * 2
		end
		st.lastAngle = a
		local want = st.directions[st.phase]
		local movingRight = d > 0
		local wanted = (want == "cw") == movingRight
		if wanted then
			st.accum += math.abs(d) / (math.pi * 2)
		end
		st.turnsDone = st.accum
		st.direction = want
		local need = st.turns[st.phase]
		if st.accum >= need then
			st.phase += 1
			st.accum = 0
			if st.phase > #st.turns then
				resolve(st, true, 1, QTEEngine.REASONS.Complete)
				return
			end
		end
		st.progress = clamp01((st.turnsDone or 0) / math.max(0.001, need))
		st.prompt = task.label .. "  " .. string.format("%.1f / %d", st.turnsDone or 0, need)
	end,
	expect = function(st)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		local side = (st.lastAngle or 0) + (st.direction == "cw" and 0.45 or -0.45)
		return { kind = "pointer", x = 0.5 + math.cos(side) * 0.3, y = 0.5 + math.sin(side) * 0.3 }
	end,
})

-- ── balance: keep a drifting value inside the band with two keys ─────────────
defineMode("balance", {
	cost = function(task)
		local p = task.params
		return { keys = p.seconds * 2, read = QTEConfig.Human.ReadSeconds, think = p.seconds }
	end,
	init = function(st, task)
		st.value = task.params.start or 0
		st.required = task.params.seconds
		st.corrections = 0
	end,
	drift = function(st, task, ctx)
		local p = task.params
		return (wobble(ctx.now, p.freqA or 1.1, p.freqB or 2.3, p.phase or 0) * p.drift) + p.bias
	end,
	tick = function(st, task, ctx)
		local p = task.params
		st.value = st.value + MODES.balance.drift(st, task, ctx) * ctx.dt * p.driftRate
		if st.value < -1 or st.value > 1 then
			resolve(st, false, clamp01(st.elapsed / st.required), QTEEngine.REASONS.OutOfBounds)
			return
		end
		st.marker = st.value
		st.progress = clamp01(st.elapsed / st.required)
		if st.elapsed >= st.required then
			-- Ending inside the band is not enough: a balance nobody touched is a
			-- balance nobody played. At least one correction is required.
			local corrected = st.corrections >= (p.minCorrections or 1)
			if corrected then
				resolve(st, true, 1 - clamp01(math.abs(st.value)), QTEEngine.REASONS.Complete)
			else
				resolve(st, false, clamp01(st.elapsed / st.required), QTEEngine.REASONS.Timeout)
			end
		end
	end,
	onPress = function(st, task, ctx, token)
		local p = task.params
		if token == p.keys[1] or token == p.keys[2] then
			st.corrections += 1
		end
		if token == p.keys[1] then
			st.value = st.value - p.push
		elseif token == p.keys[2] then
			st.value = st.value + p.push
		end
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		local p = task.params
		if (st.value or 0) < -0.2 then
			return { kind = "key", token = p.keys[2] }
		elseif (st.value or 0) > 0.2 then
			return { kind = "key", token = p.keys[1] }
		end
		return { kind = "none" }
	end,
})

-- ── gauge: hold to fill, and be inside the zone when the clock stops ─────────
defineMode("gauge", {
	cost = function(task)
		local p = task.params
		return { keys = 2, read = QTEConfig.Human.ReadSeconds + p.seconds, think = 0.4 }
	end,
	init = function(st, task)
		st.value = 0
		st.required = task.params.seconds
		st.expectToken = task.params.key
	end,
	tick = function(st, task, ctx)
		local p = task.params
		if ctx.held(p.key) then
			st.value = math.min(1, st.value + p.fillRate * ctx.dt)
		else
			st.value = math.max(0, st.value - p.drainRate * ctx.dt)
		end
		st.progress = clamp01(st.elapsed / st.required)
		st.marker = st.value
		st.prompt = task.label .. "  " .. tostring(math.floor(st.value * 100)) .. "%"
		if st.elapsed >= st.required then
			if st.value >= p.zone.from and st.value <= p.zone.to then
				resolve(st, true, 1, QTEEngine.REASONS.Complete)
			else
				resolve(st, false, 0, QTEEngine.REASONS.Missed)
			end
		end
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		local p = task.params
		local target = (p.zone.from + p.zone.to) * 0.5
		if st.value < target - 0.02 then
			return { kind = "hold", token = p.key }
		end
		-- At or above the middle of the zone the correct move is to stop filling:
		-- holding forever walks the reading straight out of the top of the zone.
		return { kind = "release", token = p.key }
	end,
})

-- ── tug: mash against a steady drain; reach the goal before the clock ────────
defineMode("tug", {
	cost = function(task)
		local p = task.params
		-- Presses must beat the drain for the whole window, not just move the marker.
		local start = p.start or 0.5 * p.travel
		local presses = math.ceil((p.travel - start + p.drain * p.seconds) / p.push)
		return { keys = presses, read = QTEConfig.Human.ReadSeconds, think = p.seconds }
	end,
	init = function(st, task)
		st.value = task.params.start or (task.params.travel * 0.5)
		st.required = task.params.travel
	end,
	tick = function(st, task, ctx)
		local p = task.params
		-- The drain pulls the reading DOWN and the presses push it up: a tug the
		-- player can lose by doing nothing, which is what a tug is.
		st.value = st.value - p.drain * ctx.dt
		st.marker = clamp01(st.value / st.required)
		st.progress = clamp01(st.value / st.required)
		if st.value >= st.required then
			resolve(st, true, 0.7 + 0.3 * clamp01(ctx.remaining / math.max(0.001, ctx.limit)), QTEEngine.REASONS.Complete)
			return
		end
		if st.value <= 0 then
			resolve(st, false, 0, QTEEngine.REASONS.OutOfBounds)
			return
		end
		st.prompt = task.label .. "  " .. tostring(math.floor(st.progress * 100)) .. "%"
	end,
	onPress = function(st, task, ctx, token)
		if token ~= task.params.key then
			return
		end
		st.value = st.value + task.params.push
		st.progress = clamp01(st.value / task.params.travel)
		st.marker = st.progress
		if st.value >= task.params.travel then
			resolve(st, true, 0.7 + 0.3 * clamp01(ctx.remaining / math.max(0.001, ctx.limit)), QTEEngine.REASONS.Complete)
		end
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "key", token = task.params.key }
	end,
})

-- ── meter: keep a meter from emptying while the drain accelerates ────────────
defineMode("meter", {
	cost = function(task)
		local p = task.params
		local presses = math.ceil((p.drain0 * p.seconds + 0.5 * p.growth * p.seconds * p.seconds) / p.push)
		return { keys = presses, read = QTEConfig.Human.ReadSeconds, think = p.seconds }
	end,
	init = function(st, task)
		st.value = task.params.start or 0.7
		st.required = task.params.seconds
		st.joinAt = nil
	end,
	tick = function(st, task, ctx)
		local p = task.params
		local drain = p.drain0 + p.growth * st.elapsed
		st.value = st.value - drain * ctx.dt
		if st.value <= 0 then
			-- Emptying the meter is a loss, but the elapsed fraction still scores:
			-- the escape model reads progress, not just the verdict (docs/11 §5).
			resolve(st, false, clamp01(st.elapsed / st.required), QTEEngine.REASONS.OutOfBounds)
			return
		end
		if st.elapsed >= st.required then
			resolve(st, st.value >= (p.floorAtEnd or 0), clamp01(st.value), QTEEngine.REASONS.Complete)
			return
		end
		st.progress = clamp01(st.elapsed / st.required)
		st.marker = clamp01(st.value)
		st.prompt = task.label .. "  " .. tostring(math.floor(st.value * 100)) .. "%"
	end,
	onPress = function(st, task, ctx, token)
		if token ~= task.params.key then
			return
		end
		st.value = math.min(1, st.value + task.params.push)
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		if (st.value or 0) < (task.params.keepAbove or 0.45) then
			return { kind = "key", token = task.params.key }
		end
		return { kind = "none" }
	end,
})

-- ── align: turn the camera to face a direction ──────────────────────────────
defineMode("align", {
	cost = function(task)
		return { keys = 0, read = QTEConfig.Human.ReadSeconds, think = 0.9 }
	end,
	init = function(st, task)
		st.dir = task.params.dir
	end,
	tick = function(st, task, ctx)
		local look = ctx.sample.look
		if look == nil then
			return
		end
		local hx = look.x or 0
		local hz = look.z or 0
		local hlen = math.sqrt(hx * hx + hz * hz)
		if hlen < 1e-6 then
			-- Looking straight up or down has no facing; the v5 code produced a NaN
			-- here and made the QTE unwinnable. Treat it as "not aligned yet".
			st.progress = 0
			return
		end
		local dot = (hx / hlen) * st.dir.x + (hz / hlen) * st.dir.z
		st.progress = clamp01((dot + 1) * 0.5)
		st.alignment = dot
		if dot >= task.params.tolerance then
			resolve(st, true, 1, QTEEngine.REASONS.Complete)
		end
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "look", dir = task.params.dir }
	end,
})

-- ── counter: press against the character's own momentum ─────────────────────
-- The v5 MomentumStabilizer read the velocity ONCE at build time and, if the player
-- was standing still, told them to press D for no reason. This mode derives the
-- counter key every frame, and when there is no momentum it asks for a brace.
defineMode("counter", {
	cost = function()
		return { keys = 1, read = QTEConfig.Human.ReadSeconds, think = 0.5 }
	end,
	init = function(st, task)
		st.expectToken = nil
		st.motionDetected = false
	end,
	derive = function(st, task, ctx)
		local v = ctx.sample.velocity
		local deadzone = task.params.deadzone or 1.5
		if v == nil then
			return nil
		end
		local vx = v.x or 0
		local vz = v.z or 0
		if math.abs(vx) < deadzone and math.abs(vz) < deadzone then
			return nil
		end
		if math.abs(vx) >= math.abs(vz) then
			return (vx > 0) and task.params.xKey or task.params.xKeyFlip
		end
		return (vz > 0) and task.params.zKey or task.params.zKeyFlip
	end,
	tick = function(st, task, ctx)
		local key = MODES.counter.derive(st, task, ctx)
		st.motionDetected = key ~= nil
		st.expectToken = key or task.params.braceKey
		st.prompt = key and (task.label .. "  brace left/right/up/down") or (task.label .. "  BRACE (any direction)")
	end,
	onPress = function(st, task, ctx, token)
		local key = MODES.counter.derive(st, task, ctx)
		if key == nil then
			if hasToken(task.params.braceKeys, token) then
				resolve(st, true, 1, QTEEngine.REASONS.Complete)
			elseif hasToken(task.params.braceKeys, token) == false and task.params.strict then
				miss(st, task, 0, QTEEngine.REASONS.WrongInput)
			end
			return
		end
		if token == key then
			resolve(st, true, 1, QTEEngine.REASONS.Complete)
		elseif hasToken(task.params.braceKeys, token) or hasToken(task.params.allKeys, token) then
			miss(st, task, 0, QTEEngine.REASONS.WrongInput)
		end
	end,
	expect = function(st)
		if st.state ~= QTEEngine.STATES.Running or st.expectToken == nil then
			-- view() is called before the first tick, so a mode that derives its key
			-- from the world must be able to say "nothing yet" on frame zero.
			return { kind = "none" }
		end
		return { kind = "key", token = st.expectToken }
	end,
})

-- ── morse: send a letter as dots and dashes ─────────────────────────────────
defineMode("morse", {
	cost = function(task)
		local p = task.params
		-- Each dash is a real hold and each dot a short one, so the budget has to be
		-- the sum of the holds plus a gap between them - not a flat per-symbol guess.
		local longs, shorts = 0, 0
		for i = 1, #p.pattern do
			if p.pattern:sub(i, i) == "-" then
				longs += 1
			else
				shorts += 1
			end
		end
		return {
			keys = #p.pattern,
			read = QTEConfig.Human.ReadSeconds,
			think = longs * QTEConfig.Human.MorseLongSeconds + shorts * QTEConfig.Human.MorseShortSeconds + 0.15 * #p.pattern,
		}
	end,
	init = function(st, task)
		st.index = 1
		st.pattern = task.params.pattern
		st.answerText = task.params.letter
	end,
	onRelease = function(st, task, ctx, token)
		if token ~= task.params.key or st.index > #st.pattern then
			return
		end
		local held = (ctx.now - (st.pressAt or ctx.now))
		local isLong = held >= QTEConfig.Human.MorseLongSeconds
		local want = st.pattern:sub(st.index, st.index)
		if (want == "-") == isLong then
			st.index += 1
			st.progress = (st.index - 1) / #st.pattern
			if st.index > #st.pattern then
				resolve(st, true, 1, QTEEngine.REASONS.Complete)
			end
		else
			miss(st, task, (st.index - 1) / #st.pattern, QTEEngine.REASONS.WrongInput)
		end
	end,
	onPress = function(st, task, ctx, token)
		if token == task.params.key then
			st.pressAt = ctx.now
		end
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		local want = st.pattern:sub(math.min(st.index, #st.pattern), math.min(st.index, #st.pattern))
		if want == "-" then
			-- A dash only has to be longer than MorseLongSeconds; asking the player
			-- (or the solver) to overshoot by 100 ms per dash is dead time on the
			-- clock, and five of them are a tenth of the whole budget.
			return { kind = "hold", token = task.params.key, holdFor = QTEConfig.Human.MorseLongSeconds + 0.03 }
		end
		return { kind = "tap", token = task.params.key }
	end,
})

-- ── grid: memorise lit cells, then click them ───────────────────────────────
defineMode("grid", {
	cost = function(task)
		local p = task.params
		-- Each remembered cell costs a decision and roughly a cell-width of travel.
		return {
			keys = #p.lit,
			read = QTEConfig.Human.ReadSeconds + p.flashSeconds,
			pointer = #p.lit * (p.cellW + p.cellH),
			think = 0.4 + 0.2 * #p.lit,
		}
	end,
	init = function(st, task)
		st.phase = "flash"
		st.flashClock = 0
		st.found = 0
		st.required = #task.params.lit
		st.answerText = tostring(#task.params.lit)
	end,
	tick = function(st, task, ctx)
		if st.phase == "flash" then
			st.flashClock += ctx.dt
			if st.flashClock >= task.params.flashSeconds then
				st.phase = "recall"
				st.answerVisible = false
				st.prompt = task.label .. "  " .. tostring(st.required) .. " lit"
			end
		end
		st.progress = clamp01(st.found / math.max(1, st.required))
	end,
	onClick = function(st, task, ctx, point)
		if st.phase ~= "recall" then
			return
		end
		local p = task.params
		local col = math.floor((point.x - p.originX) / p.cellW) + 1
		local row = math.floor((point.y - p.originY) / p.cellH) + 1
		if col < 1 or col > p.cols or row < 1 or row > p.rows then
			return
		end
		local index = (row - 1) * p.cols + col
		if st.hit and st.hit[index] then
			return
		end
		st.hit = st.hit or {}
		if p.litSet[index] then
			st.hit[index] = true
			st.found += 1
			if st.found >= st.required then
				resolve(st, true, 1, QTEEngine.REASONS.Complete)
			end
		else
			resolve(st, false, st.found / st.required, QTEEngine.REASONS.WrongInput)
		end
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running or st.phase ~= "recall" then
			return { kind = "none" }
		end
		local p = task.params
		for i = 1, p.cols * p.rows do
			if p.litSet[i] and not (st.hit and st.hit[i]) then
				local col = (i - 1) % p.cols
				local row = math.floor((i - 1) / p.cols)
				return { kind = "pointer", x = p.originX + (col + 0.5) * p.cellW, y = p.originY + (row + 0.5) * p.cellH, click = true }
			end
		end
		return { kind = "none" }
	end,
})

-- ── quickdraw: react to an unannounced cue, no early draw ───────────────────
defineMode("quickdraw", {
	cost = function(task)
		local p = task.params
		return { keys = 1, read = QTEConfig.Human.ReactionSeconds + p.cueAt, think = 0.4 + p.window }
	end,
	init = function(st, task)
		st.cueAt = task.params.cueAt
		st.cued = false
	end,
	onPress = function(st, task, ctx, token)
		if token ~= task.params.key and not task.params.anyKey then
			return
		end
		if not st.cued then
			resolve(st, false, 0, QTEEngine.REASONS.FalseStart)
			return
		end
		local late = st.elapsed - st.cueAt
		if late <= task.params.window then
			resolve(st, true, 1 - 0.35 * clamp01(late / task.params.window), QTEEngine.REASONS.Complete)
		else
			resolve(st, false, 0, QTEEngine.REASONS.Missed)
		end
	end,
	tick = function(st, task, ctx)
		if not st.cued and st.elapsed >= st.cueAt then
			st.cued = true
			st.prompt = task.params.cueText or "DRAW!"
		end
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		if st.cued then
			return { kind = "key", token = task.params.key }
		end
		return { kind = "none" }
	end,
})

-- ── symbol: show one token, require a different one (mirror / opposite) ─────
-- The mapping lives in the parameters, so one mode covers "press the opposite
-- direction", "press the paired letter" and any future rule without new code. The
-- widget shows the SHOWN token, never the answer - v5's Mirror printed the rule and
-- the shown key in the same line, which made the QTE a reading test.
defineMode("symbol", {
	cost = function(task)
		local n = #task.params.items
		return { keys = n, read = QTEConfig.Human.ReadSeconds, think = 0.3 + 0.25 * n }
	end,
	init = function(st, task)
		st.index = 1
		st.shownToken = task.params.items[1].shown
		st.answerTokens = {}
		for i = 1, #task.params.items do
			st.answerTokens[i] = task.params.items[i].token
		end
	end,
	onPress = function(st, task, ctx, token)
		if not hasToken(st.answerTokens, token) then
			return
		end
		if token == task.params.items[st.index].token then
			st.index += 1
			st.progress = (st.index - 1) / #task.params.items
			if st.index > #task.params.items then
				resolve(st, true, 0.75 + 0.25 * clamp01(ctx.remaining / math.max(0.001, ctx.limit)), QTEEngine.REASONS.Complete)
				return
			end
			st.shownToken = task.params.items[st.index].shown
		else
			miss(st, task, (st.index - 1) / #task.params.items, QTEEngine.REASONS.WrongInput)
		end
	end,
	expect = function(st, task)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "key", token = task.params.items[st.index].token }
	end,
})

-- ── search: find a hidden target by proximity feedback (hot / cold) ──────────
defineMode("search", {
	cost = function(task)
		return { keys = 0, read = QTEConfig.Human.ReadSeconds, pointer = task.params.searchScreens or 3.0 }
	end,
	init = function(st, task)
		st.best = math.huge
		st.targetX = task.params.target.x
		st.targetY = task.params.target.y
	end,
	tick = function(st, task, ctx)
		local target = task.params.target
		local dx = ctx.sample.pointer.x - target.x
		local dy = ctx.sample.pointer.y - target.y
		local dist = math.sqrt(dx * dx + dy * dy)
		if dist < st.best then
			st.best = dist
		end
		st.distance = dist
		if dist <= task.params.radius then
			resolve(st, true, 0.6 + 0.4 * clamp01(ctx.remaining / math.max(0.001, ctx.limit)), QTEEngine.REASONS.Complete)
			return
		end
		-- Proximity, not direction: the player has to sweep to find it.
		st.progress = clamp01(1 - dist / 0.9)
		if dist <= task.params.hotRadius then
			st.heat = "hot"
		elseif dist <= task.params.warmRadius then
			st.heat = "warm"
		else
			st.heat = "cold"
		end
		st.prompt = task.label .. "  " .. st.heat
	end,
	expect = function(st)
		if st.state ~= QTEEngine.STATES.Running then
			return { kind = "none" }
		end
		return { kind = "pointer", x = st.targetX or 0.5, y = st.targetY or 0.5 }
	end,
})

-- ═════════════════════════════════════════════════════════════════════════════
--  WIDGETS
--  What the player SEES, per mode. Kept apart from the logic so "is this QTE
--  winnable" (the modes) and "does it read well" (this table) can be reviewed and
--  changed independently - and so a mode with no visual stays legal.
--
--  Concealment rule, which tests.luau enforces: a mode that shows an answer must
--  stop showing it the moment the recall phase starts. Displays here read
--  st.answerVisible / st.phase, never task.params directly, except where the whole
--  point is that the answer is on screen (press, sequence, sort).
-- ═════════════════════════════════════════════════════════════════════════════

local MODE_WIDGETS = {}

local function push(out: any, w: any): ()
	out[#out + 1] = w
end

local function bar(out: any, value: number, colour: any, label: string?): ()
	push(out, { kind = "bar", value = clamp01(value), colour = colour, label = label })
end

local function chips(out: any, items: any, index: number, colour: any, hidden: boolean?): ()
	local view = {}
	for i = 1, #items do
		if hidden and i >= index then
			view[i] = "?"
		else
			view[i] = tostring(items[i])
		end
	end
	push(out, { kind = "chips", items = view, index = index, colour = colour })
end

MODE_WIDGETS.press = function(st, task, out)
	push(out, { kind = "text", value = tostring(task.params.key), colour = task.accent, scale = 1.8 })
end

MODE_WIDGETS.react = function(st, task, out)
	if st.cued then
		push(out, { kind = "text", value = task.params.cueText or "NOW!", colour = task.accent, scale = 2.0 })
	else
		push(out, { kind = "text", value = "...", colour = { 170, 170, 170 }, scale = 1.2 })
	end
end

MODE_WIDGETS.mash = function(st, task, out)
	bar(out, st.count / math.max(1, st.required or 1), task.accent, tostring(st.count) .. "/" .. tostring(st.required or 1))
end

MODE_WIDGETS.alternate = MODE_WIDGETS.mash

MODE_WIDGETS.sequence = function(st, task, out)
	chips(out, st.chips or task.params.keys, st.index or 1, task.accent)
	bar(out, st.progress or 0, task.accent)
end

MODE_WIDGETS.sort = function(st, task, out)
	chips(out, st.chips or task.params.items, math.min(st.index or 1, #(st.sorted or task.params.items)), task.accent)
	bar(out, st.progress or 0, task.accent)
end

MODE_WIDGETS.hold = function(st, task, out)
	bar(out, (st.held or 0) / math.max(0.001, st.required or 1), task.accent)
end

MODE_WIDGETS.holdAll = MODE_WIDGETS.hold

MODE_WIDGETS.exact = function(st, task, out)
	bar(out, (st.count or 0) / math.max(1, st.required or 1), task.accent, tostring(st.count or 0) .. "/" .. tostring(st.required or 1))
end

MODE_WIDGETS.type = function(st, task, out)
	local shown
	if st.phase == "show" or (task.params.reveal and st.answerVisible ~= false) then
		shown = st.text or ""
	else
		shown = st:masked()
	end
	push(out, { kind = "text", value = shown, colour = task.accent, scale = 1.6 })
	bar(out, st.progress or 0, task.accent)
end

MODE_WIDGETS.count = function(st, task, out)
	if st.phase == "flash" then
		for i = 1, #task.params.spots do
			local spot = task.params.spots[i]
			push(out, { kind = "target", x = spot.x, y = spot.y, radius = task.params.spotRadius, colour = task.accent, alpha = 1 })
		end
	else
		push(out, { kind = "text", value = "?", colour = task.accent, scale = 1.6 })
	end
end

MODE_WIDGETS.classify = function(st, task, out)
	push(out, { kind = "text", value = tostring(st.shown.text), colour = st.shown.colour or task.accent, scale = 1.5 })
	bar(out, (st.correct or 0) / math.max(1, task.params.needed), task.accent, tostring(st.correct or 0) .. "/" .. tostring(task.params.needed))
end

MODE_WIDGETS.memorise = function(st, task, out)
	if st.phase == "flash" then
		local item = task.params.items[math.max(1, math.min(st.flashIndex or 1, #task.params.items))]
		local value = item.token or item
		local colour = item.colour or task.accent
		if task.params.showAll then
			local joined = {}
			local lastColour = colour
			for i = 1, #task.params.items do
				joined[i] = tostring(task.params.items[i].token or task.params.items[i])
				lastColour = task.params.items[i].colour or lastColour
			end
			push(out, { kind = "text", value = table.concat(joined), colour = lastColour, scale = 2.2 })
		else
			push(out, { kind = "text", value = tostring(value), colour = colour, scale = 2.2 })
		end
		local marks = {}
		for i = 1, #task.params.items do
			marks[i] = (i <= (st.flashIndex or 0)) and (task.params.items[i].token or task.params.items[i]) or "-"
		end
		push(out, { kind = "chips", items = marks, index = st.flashIndex or 1, colour = task.accent })
	else
		local order = st.order or {}
		chips(out, order, st.index or 1, task.accent, true)
	end
end

MODE_WIDGETS.timed = function(st, task, out)
	bar(out, (st.hits or 0) / math.max(1, task.params.beats), task.accent, tostring(st.hits or 0) .. "/" .. tostring(task.params.beats))
end

MODE_WIDGETS.release = function(st, task, out)
	push(out, {
		kind = "track",
		value = st.value or 0,
		zone = { from = task.params.zone.from, to = task.params.zone.to },
		colour = task.accent,
		label = task.params.trigger == "release" and "release in the zone" or "press in the zone",
	})
end

MODE_WIDGETS.tug = function(st, task, out)
	push(out, {
		kind = "track",
		value = st.marker or 0,
		zone = { from = 0.9, to = 1.0 },
		colour = task.accent,
		label = string.format("%d%%", math.floor((st.progress or 0) * 100)),
	})
end

MODE_WIDGETS.meter = function(st, task, out)
	push(out, {
		kind = "track",
		value = st.marker or 0,
		zone = { from = task.params.keepAbove or 0.45, to = 1.0 },
		colour = task.accent,
		label = string.format("%d%%", math.floor((st.marker or 0) * 100)),
	})
end

MODE_WIDGETS.gauge = function(st, task, out)
	push(out, {
		kind = "track",
		value = st.marker or 0,
		zone = { from = task.params.zone.from, to = task.params.zone.to },
		colour = task.accent,
		orientation = "v",
		label = string.format("%d%%", math.floor((st.marker or 0) * 100)),
	})
end

MODE_WIDGETS.balance = function(st, task, out)
	push(out, {
		kind = "track",
		value = clamp01(((st.value or 0) + 1) * 0.5),
		zone = { from = 0.35, to = 0.65 },
		colour = task.accent,
		label = string.format("%d%%", math.floor(clamp01(st.elapsed / math.max(0.001, st.required or 1)) * 100)),
	})
end

MODE_WIDGETS.idle = function(st, task, out)
	bar(out, st.progress or 0, task.accent)
end

MODE_WIDGETS.steady = function(st, task, out)
	bar(out, st.progress or 0, task.accent, st.ready and "CLICK" or "hold still")
end

MODE_WIDGETS.track = function(st, task, out)
	push(out, {
		kind = "target",
		x = st.markerX or 0.5,
		y = st.markerY or 0.5,
		radius = task.params.tolerance * 1.6,
		colour = task.accent,
		alpha = 1,
	})
	bar(out, st.progress or 0, task.accent)
end

MODE_WIDGETS.shake = function(st, task, out)
	bar(out, st.progress or 0, task.accent, string.format("%d%%", math.floor((st.progress or 0) * 100)))
end

MODE_WIDGETS.spin = function(st, task, out)
	push(out, { kind = "target", x = 0.5, y = 0.5, radius = 0.06, colour = task.accent, alpha = 0.5 })
	bar(out, st.progress or 0, task.accent, st.direction == "cw" and "clockwise" or "anticlockwise")
end

MODE_WIDGETS.hit = function(st, task, out)
	for i = 1, #task.params.targets do
		if st.remaining and st.remaining[i] then
			local pos = st.positions and st.positions[i]
			push(out, {
				kind = "target",
				x = pos and pos.x or task.params.targets[i].x,
				y = pos and pos.y or task.params.targets[i].y,
				radius = task.params.targets[i].radius,
				colour = task.accent,
				alpha = 1,
			})
		end
	end
end

MODE_WIDGETS.aim = function(st, task, out)
	push(out, { kind = "target", x = task.params.target.x, y = task.params.target.y, radius = task.params.target.radius, colour = task.accent, alpha = 1 })
end

MODE_WIDGETS.trace = function(st, task, out)
	push(out, { kind = "path", points = task.params.points, index = st.index or 1, colour = task.accent })
	bar(out, st.progress or 0, task.accent)
end

MODE_WIDGETS.grid = function(st, task, out)
	local cells = {}
	local p = task.params
	for i = 1, p.cols * p.rows do
		local state = "idle"
		if st.phase == "flash" and p.litSet[i] then
			state = "lit"
		elseif st.hit and st.hit[i] then
			state = "hit"
		end
		cells[i] = state
	end
	push(out, {
		kind = "grid",
		cols = p.cols,
		rows = p.rows,
		originX = p.originX,
		originY = p.originY,
		cellW = p.cellW,
		cellH = p.cellH,
		cells = cells,
		colour = task.accent,
	})
end

MODE_WIDGETS.morse = function(st, task, out)
	chips(out, task.params.pattern, st.index or 1, task.accent)
	push(out, { kind = "text", value = task.params.letter, colour = { 200, 200, 200 }, scale = 1.0 })
end

MODE_WIDGETS.symbol = function(st, task, out)
	push(out, { kind = "text", value = tostring(st.shownToken), colour = task.accent, scale = 2.4 })
	chips(out, st.answerTokens or {}, st.index or 1, task.accent, true)
end

MODE_WIDGETS.search = function(st, task, out)
	bar(out, st.progress or 0, task.accent, tostring(st.heat or ""))
end

MODE_WIDGETS.counter = function(st, task, out)
	bar(out, st.motionDetected and 0.0 or 0.5, task.accent, st.motionDetected and "" or "no momentum")
end

MODE_WIDGETS.align = function(st, task, out)
	bar(out, st.progress or 0, task.accent, string.format("%d%%", math.floor((st.progress or 0) * 100)))
end

MODE_WIDGETS.quickdraw = function(st, task, out)
	if st.cued then
		push(out, { kind = "text", value = task.params.cueText or "DRAW!", colour = task.accent, scale = 2.0 })
		bar(out, clamp01((st.elapsed - st.cueAt) / math.max(0.001, task.params.window)), task.accent)
	else
		-- A QTE with no visual is a QTE the player cannot tell apart from a crash.
		push(out, { kind = "text", value = "READY", colour = task.accent, scale = 1.6 })
		bar(out, 0, task.accent)
	end
end

-- ═════════════════════════════════════════════════════════════════════════════
--  Engine
-- ═════════════════════════════════════════════════════════════════════════════

-- cost(task, human) -> {time = seconds, keys, pointer, read, think}
-- The feasibility floor. QTEDirector will not hand out a limit shorter than
-- `time`, which is how "this QTE is possible at Insane with 30% health" becomes a
-- property of the code rather than a claim in a comment.
function QTEEngine.cost(task: any, human: any?): any
	local h = human or QTEConfig.Human
	local mode = MODES[task.mode]
	local raw = { keys = 0, pointer = 0, read = 0, think = 0 }
	if mode and mode.cost then
		raw = mode.cost(task, h)
	end
	local keys = raw.keys or 0
	local pointer = raw.pointer or 0
	local read = raw.read or 0
	local think = raw.think or 0
	-- `think` is the window the mode gives the player (a mash window, a hold, a
	-- flash sequence). Presses made inside that window are already paid for, so only
	-- the part of the input burst that does not fit adds to the price. Without this
	-- a mash QTE was priced as "hold still for four seconds AND mash thirty times",
	-- which pushed its required limit past the ceiling and made it unbeatable at
	-- Insane. `QTEDirector` still refuses to go below `time`.
	local burst = math.max(0, keys * h.KeySeconds - think)
	local seconds = read + think + burst + pointer / h.PointerScreensPerSecond
	return {
		time = seconds,
		keys = keys,
		pointer = pointer,
		read = read,
		think = think,
	}
end

-- new(task, opts) -> engine
function QTEEngine.new(task: any, opts: any?): any
	local o = opts or {}
	local mode = MODES[task.mode]
	assert(mode ~= nil, "QTEEngine: unknown mode '" .. tostring(task.mode) .. "'")
	local self = setmetatable({}, QTEEngine)
	self.task = task
	self.mode = mode
	self.human = o.human or QTEConfig.Human
	self.grace = o.grace or QTEConfig.Timing.GraceSeconds
	self.state = {
		elapsed = 0,
		state = QTEEngine.STATES.Running,
		score = 0,
		reason = nil,
		misses = 0,
		progress = 0,
		prompt = task.prompt,
		sub = task.sub,
		widgets = {},
		prevKeys = {},
		answerText = nil,
		answerVisible = true,
	}
	if mode.init then
		mode.init(self.state, task)
	end
	-- maskText is how the type mode renders progress without a Roblox string lib.
	local st = self.state
	st.masked = maskText
	return self
end

function QTEEngine:isDone(): boolean
	return self.state.state ~= QTEEngine.STATES.Running
end

function QTEEngine:result(): any
	local st = self.state
	return {
		state = st.state,
		score = st.score,
		reason = st.reason,
		elapsed = st.elapsed,
		misses = st.misses,
		id = self.task.id,
	}
end

-- tick(sample) -> view
--
-- sample = {
--   dt     = frame seconds (clamped by the caller),
--   keys   = {TOKEN = true} currently held,
--   pointer= {x, y} in 0..1 of the QTE surface,
--   clicks = number of clicks this frame (0 for none),
--   clickPoint = {x, y} where the click landed,
--   pointerTravel = pointer distance this frame in screens,
--   look   = {x, y, z} camera look vector,
--   velocity = {x, y, z} character velocity,
--   beat   = true on a world-provided cue frame (footstep marker, server event),
-- }
function QTEEngine:tick(sample: any): any
	local st = self.state
	local task = self.task
	local mode = self.mode
	local dt = sample.dt or 0
	if dt < 0 then
		dt = 0
	elseif dt > 0.25 then
		dt = 0.25
	end
	local ctx = {
		dt = dt,
		now = st.elapsed + dt,
		limit = task.timeLimit,
		remaining = math.max(0, task.timeLimit - (st.elapsed + dt)),
		sample = sample,
		held = function(token: string)
			return sample.keys ~= nil and sample.keys[token] == true
		end,
		pointerSpeed = sample.pointerTravel and (sample.pointerTravel / math.max(0.001, dt)) or 0,
		pointerTravel = sample.pointerTravel or 0,
	}

	-- Discrete events derived from key transitions, so a mode never has to care
	-- whether the platform sends InputBegan/InputEnded or a held-key table.
	local keys = sample.keys or {}
	local prev = st.prevKeys
	if st.state == QTEEngine.STATES.Running then
		if mode.tick then
			mode.tick(st, task, ctx)
		end
		for token in pairs(keys) do
			if keys[token] and not prev[token] and st.state == QTEEngine.STATES.Running then
				if mode.onPress then
					mode.onPress(st, task, ctx, token)
				end
			end
		end
		for token in pairs(prev) do
			if prev[token] and not keys[token] and st.state == QTEEngine.STATES.Running then
				if mode.onRelease then
					mode.onRelease(st, task, ctx, token)
				end
			end
		end
		if (sample.clicks or 0) > 0 and st.state == QTEEngine.STATES.Running then
			local point = sample.clickPoint or sample.pointer or { x = 0.5, y = 0.5 }
			if mode.onClick then
				mode.onClick(st, task, ctx, point)
			end
		end
	elseif mode.tick then
		-- Still tick after resolution: a resolved QTE may need one frame to settle
		-- its progress value (the shell reads it before tearing the widgets down).
		mode.tick(st, task, ctx)
	end

	st.elapsed += dt
	st.prevKeys = {}
	for token, down in pairs(keys) do
		st.prevKeys[token] = down
	end

	if st.state == QTEEngine.STATES.Running and st.elapsed > task.timeLimit + self.grace then
		local partial = st.progress or 0
		resolve(st, false, partial, QTEEngine.REASONS.Timeout)
	end

	return self:view()
end

-- view() -> the render model. Everything the shell draws comes from here; the shell
-- holds no QTE state of its own, which is why a mode cannot desync from the screen.
function QTEEngine:view(): any
	local st = self.state
	local task = self.task
	local mode = self.mode
	local widgets = {}
	local painter = MODE_WIDGETS[task.mode]
	if painter then
		painter(st, task, widgets)
	end
	local expect = { kind = "none" }
	if mode.expect then
		expect = mode.expect(st, task) or expect
	end
	return {
		id = task.id,
		label = task.label,
		state = st.state,
		reason = st.reason,
		score = st.score,
		elapsed = st.elapsed,
		remaining = math.max(0, task.timeLimit - st.elapsed),
		timeLimit = task.timeLimit,
		progress = clamp01(st.progress or 0),
		prompt = st.prompt or task.prompt,
		sub = st.sub or task.sub,
		widgets = widgets,
		expect = expect,
		accent = task.accent,
		answerVisible = st.answerVisible ~= false,
	}
end

-- renderedText(view) -> every string the shell will put on screen.
-- The harness uses this to prove a memorise QTE stops showing its answer once the
-- recall phase starts (the v5 SortPress printed the correct order, and the v5 grid
-- accepted clicks during the flash).
function QTEEngine.renderedText(view: any): string
	local parts = { tostring(view.prompt or ""), tostring(view.sub or "") }
	for i = 1, #view.widgets do
		local w = view.widgets[i]
		if w.kind == "text" then
			parts[#parts + 1] = tostring(w.value or "")
		elseif w.kind == "chips" then
			for j = 1, #(w.items or {}) do
				parts[#parts + 1] = tostring(w.items[j])
			end
		end
	end
	return table.concat(parts, " ")
end

return QTEEngine
