-- tests-qte.luau
-- Location: tools/vitriol/tests-qte.luau  (executed by tools/vitriol-smoke-test.js)
-- Purpose:  The QTE package's own suite. It loads the REAL modules from qte/ - not
--           a copy and not a reimplementation - and plays every QTE with a bot
--           that obeys human input limits, so "this QTE is winnable" is a fact
--           about the shipped timing budget rather than a claim in a document.
--
-- Run it with:
--   node tools/vitriol-smoke-test.js \
--        --modules tools/vitriol/modules-qte.js \
--        --tests   tools/vitriol/tests-qte.luau
--
-- (or `node tools/vitriol-quality-gate.js`, which runs it as the "qte" check.)

local QTEConfig = VitriolRequire("QTEConfig")
local QTEEngine = VitriolRequire("QTEEngine")
local QTECatalog = VitriolRequire("QTECatalog")
local QTEDirector = VitriolRequire("QTEDirector")

TESTS = { passed = 0, failed = 0 }

local function check(cond, msg)
	if cond then
		TESTS.passed = TESTS.passed + 1
		print("PASS  " .. msg)
	else
		TESTS.failed = TESTS.failed + 1
		warn("FAIL  " .. msg)
	end
end

print("=== QTE stack ===")

-- ── The pilot ────────────────────────────────────────────────────────────────
-- One driver for every QTE: it reads the engine's expect channel and nothing else,
-- and it obeys human limits (a press rate, a pointer speed, a reaction delay), so
-- "the bot wins at Insane" is a statement about the timing budget, not about APM.
local Pilot = {}
Pilot.__index = Pilot

local PILOT = {
	solve = { rate = 7.5, pointerSpeed = 2.2, reaction = 0.16, lookSpeed = 3.0, beatEvery = 0.55 },
	idle = {},
	spam = { rate = 20, pointerSpeed = 2.0 },
}

function Pilot.new(profile)
	local bot = {
		profile = profile,
		limits = PILOT[profile] or {},
		keys = {},
		pointer = { x = 0.5, y = 0.5 },
		look = { x = 0, y = 0, z = -1 },
		velocity = { x = 0, y = 0, z = 0 },
		cooldown = 0,
		clock = 0,
		beatClock = 0,
		releaseNext = nil,
		holdKey = nil,
		holdFor = 0,
		gap = 0,
	}
	return setmetatable(bot, Pilot)
end

function Pilot:sample(view, dt)
	local limits = self.limits
	local rate = limits.rate or 7.5
	self.clock += dt
	self.cooldown = math.max(0, self.cooldown - dt)

	-- Consume one frame of the post-release gap. It must happen before the press
	-- logic AND before a new release is scheduled, otherwise the gap is spent in the
	-- same frame it was created and the key never visibly comes up.
	if self.gap > 0 then
		self.gap -= 1
	end

	-- Release whatever was pressed last frame: a press is a key-down edge.
	if self.releaseNext then
		self.keys[self.releaseNext] = nil
		self.releaseNext = nil
		self.gap = 1
	end
	if self.holdKey and self.holdFor > 0 then
		self.holdFor -= dt
		if self.holdFor <= 0 then
			self.keys[self.holdKey] = nil
			self.holdKey = nil
			self.gap = 1
		end
	end


	self.beatClock += dt
	local beat = false
	if self.beatClock >= (limits.beatEvery or 0.55) then
		self.beatClock = 0
		beat = true
	end

	local travel = 0
	local want = view.expect or { kind = "none" }
	local mayPress = self.cooldown <= 0

	if self.profile == "idle" then
		-- deliberately touches nothing
	elseif self.profile == "spam" then
		local pool = { "E", "R", "F", "Q", "W", "A", "S", "D", "G", "H", "1", "2", "3", "Space" }
		if mayPress then
			local token = pool[(math.floor(self.clock * 41) % #pool) + 1]
			self.keys[token] = true
			self.releaseNext = token
			self.cooldown = 1 / rate
		end
		self.pointer.x = 0.5 + math.sin(self.clock * 4.3) * 0.45
		self.pointer.y = 0.5 + math.cos(self.clock * 3.7) * 0.35
	else
		if want.kind == "key" or want.kind == "tap" then
			local ready = self.gap <= 0
			-- Press ON the beat (or inside the window), not ahead of it: a cue that
			-- opens `window` early is still judged against the beat, so a press placed
			-- a reaction early lands outside a tight window as a false start.
			if want.at and self.clock < want.at then
				ready = false
			end
			if want.atEnd and self.clock > want.atEnd then
				ready = false
			end
			if want.token and ready and mayPress then
				self.keys[want.token] = true
				self.releaseNext = want.token
				self.cooldown = 1 / rate
			end
		elseif want.kind == "hold" then
			if self.gap > 0 then
				-- still letting the previous press come up
			elseif want.alsoHold then
				for i = 1, #want.alsoHold do
					self.keys[want.alsoHold[i]] = true
				end
			end
			if want.token and self.gap <= 0 then
				if want.holdFor then
					if not self.holdKey then
						self.keys[want.token] = true
						self.holdKey = want.token
						self.holdFor = want.holdFor
					end
				else
					self.keys[want.token] = true
				end
			end
		elseif want.kind == "release" then
			if want.token then
				self.keys[want.token] = nil
				if self.holdKey == want.token then
					self.holdKey = nil
					self.holdFor = 0
				end
			end
		elseif want.kind == "click" then
			self.clicks = 1
		elseif want.kind == "pointer" then
			local dx = want.x - self.pointer.x
			local dy = want.y - self.pointer.y
			local dist = math.sqrt(dx * dx + dy * dy)
			local step = limits.pointerSpeed * dt
			if dist <= step then
				travel = dist
				self.pointer.x = want.x
				self.pointer.y = want.y
			else
				travel = step
				self.pointer.x = self.pointer.x + dx / dist * step
				self.pointer.y = self.pointer.y + dy / dist * step
			end
			-- Click where the cursor actually is, never mid-flight.
			if want.click and dist <= 0.03 then
				self.clicks = 1
			end
		elseif want.kind == "look" then
			local dir = want.dir
			if dir then
				local step = math.min(1, limits.lookSpeed * dt)
				self.look.x = self.look.x + (dir.x - self.look.x) * step
				self.look.y = self.look.y + (dir.y - self.look.y) * step
				self.look.z = self.look.z + (dir.z - self.look.z) * step
			end
		end
	end

	local sample = {
		dt = dt,
		keys = {},
		pointer = { x = self.pointer.x, y = self.pointer.y },
		clicks = self.clicks or 0,
		pointerTravel = travel,
		velocity = self.velocity,
		look = { x = self.look.x, y = self.look.y, z = self.look.z },
		beat = beat,
	}
	for token, down in pairs(self.keys) do
		if down and token ~= nil then
			sample.keys[token] = true
		end
	end
	self.clicks = 0
	return sample
end

-- run(task, profile, opts) -> result, elapsed, widgetKinds
function Pilot.run(task, profile, opts)
	local o = opts or {}
	local engine = QTEEngine.new(task, o.engine or {})
	local pilot = Pilot.new(profile)
	local dt = o.dt or (1 / 60)
	local clock = 0
	local cap = task.timeLimit + 2
	local kinds = {}
	while not engine:isDone() and clock < cap do
		local view = engine:view()
		for i = 1, #(view.widgets or {}) do
			kinds[view.widgets[i].kind] = true
		end
		engine:tick(pilot:sample(view, dt))
		clock += dt
	end
	return engine:result(), clock, kinds
end

local function taskFor(id, preset, seed, health)
	local director = QTEDirector.new({ seed = seed or 7, preset = preset or "Normal" })
	local task = director:beginNamed(id, health or 1)
	return task, director
end

-- ── 1. Catalogue shape ───────────────────────────────────────────────────────
local problems = QTECatalog.validate(QTEEngine)
check(#problems == 0, "catalogue validates against the engine (" .. #problems .. " problems)")
for i = 1, math.min(#problems, 6) do
	warn("  catalogue: " .. problems[i])
end
check(#QTECatalog.list >= 60, "the catalogue ships " .. #QTECatalog.list .. " QTEs (v5 shipped 55)")

local usedModes = {}
local badCaps, badAccent, badTime, dupes = 0, 0, 0, 0
local seenIds = {}
for i = 1, #QTECatalog.list do
	local def = QTECatalog.list[i]
	usedModes[def.mode] = true
	if type(def.caps) ~= "table" then
		badCaps += 1
	end
	local a = def.accent
	if a == nil or a[1] == nil or a[1] < 0 or a[1] > 255 or a[2] < 0 or a[2] > 255 or a[3] < 0 or a[3] > 255 then
		badAccent += 1
	end
	if type(def.baseTime) ~= "number" or def.baseTime < QTEConfig.Timing.MinLimit or def.baseTime > QTEConfig.Timing.MaxLimit then
		badTime += 1
	end
	if seenIds[def.id] then
		dupes += 1
	end
	seenIds[def.id] = true
end
local noInputModes = { idle = true }
local badCaps2 = 0
for i = 1, #QTECatalog.list do
	local def = QTECatalog.list[i]
	local declared = next(def.caps or {}) ~= nil
	-- A QTE answered by doing nothing legitimately needs no device; every other QTE
	-- must say what it needs, or a touch player is offered something unplayable.
	if declared == (noInputModes[def.mode] == true) then
		badCaps2 += 1
	end
end
check(badCaps2 == 0, "capabilities are declared exactly where input is required (" .. badCaps2 .. " wrong)")
check(badAccent == 0, "every QTE has a valid rgb accent")
check(badTime == 0, "every QTE baseTime is inside the configured limit window")
check(dupes == 0, "no duplicate ids in the catalogue")
check(seenIds["NoPress"] ~= nil and seenIds["MathCalc"] ~= nil, "the v5 classics are still in the list")

local deadModes = {}
for i = 1, #QTEEngine.MODE_ORDER do
	if not usedModes[QTEEngine.MODE_ORDER[i]] then
		deadModes[#deadModes + 1] = QTEEngine.MODE_ORDER[i]
	end
end
check(#deadModes == 0, "every engine mode is reachable from the catalogue (" .. #deadModes .. " unused)")

local categorySet = {}
local cats = 0
for i = 1, #QTECatalog.list do
	local c = QTECatalog.list[i].category
	if not categorySet[c] then
		categorySet[c] = true
		cats += 1
	end
end
check(cats >= 6, "the QTEs are spread over " .. cats .. " categories")

-- ── 2. Feasibility: the limit always covers the price of playing the QTE ─────
local presets = { "Easy", "Normal", "Hard", "Insane" }
local infeasible = 0
local overLimit = 0
local worst = { slack = math.huge, id = "?" }
for i = 1, #QTECatalog.list do
	local def = QTECatalog.list[i]
	for p = 1, #presets do
		for seed = 1, 6 do
			local task = taskFor(def.id, presets[p], seed, 0)
			local cost = QTEEngine.cost(task, QTEConfig.Human)
			local slack = task.timeLimit - cost.time
			if slack < -1e-9 then
				infeasible += 1
			end
			if task.timeLimit > QTEConfig.Timing.MaxLimit + 1e-9 then
				overLimit += 1
			end
			if slack < worst.slack then
				worst = { slack = slack, id = def.id .. "@" .. presets[p] }
			end
		end
	end
end
check(infeasible == 0, "no preset (at zero health, hardest pressure) cuts a limit below its cost (" .. worst.id .. " slack " .. string.format("%.3f", worst.slack) .. ")")
check(overLimit == 0, "no limit exceeds the configured ceiling")

-- ── 3. Perfect play wins everywhere ─────────────────────────────────────────
local solveFail = {}
local solveRuns = 0
for i = 1, #QTECatalog.list do
	local def = QTECatalog.list[i]
	for p = 1, #presets do
		local task = taskFor(def.id, presets[p], 7, 1)
		local result, clock = Pilot.run(task, "solve")
		solveRuns += 1
		if result.state ~= "won" then
			solveFail[#solveFail + 1] = string.format(
				"%s@%s (%s, t=%.2f/%.2f)", def.id, presets[p], tostring(result.reason), clock, task.timeLimit)
		end
	end
end
check(#solveFail == 0, "perfect play wins all " .. solveRuns .. " preset runs (" .. #solveFail .. " failures)")
for i = 1, math.min(#solveFail, 8) do
	warn("  unsolved: " .. solveFail[i])
end

-- Harder presets must ship SHORTER limits, not longer ones.
local monotonic = true
for i = 1, #QTECatalog.list do
	local def = QTECatalog.list[i]
	local easy = select(1, taskFor(def.id, "Easy", 7, 1))
	local insane = select(1, taskFor(def.id, "Insane", 7, 1))
	if easy.timeLimit < insane.timeLimit - 1e-9 then
		monotonic = false
	end
end
check(monotonic, "difficulty only ever takes time away")

-- ── 4. Doing nothing must not win ───────────────────────────────────────────
local idleWins = {}
for i = 1, #QTECatalog.list do
	local def = QTECatalog.list[i]
	local task = taskFor(def.id, "Normal", 7, 1)
	local result = Pilot.run(task, "idle")
	if def.mode == "idle" then
		if result.state ~= "won" then
			idleWins[#idleWins + 1] = def.id .. " (idle mode should win when ignored)"
		end
	elseif result.state == "won" then
		idleWins[#idleWins + 1] = def.id .. " (won by doing nothing)"
	end
end
check(#idleWins == 0, "no QTE can be won by waiting (" .. #idleWins .. " can)")
for i = 1, math.min(#idleWins, 8) do
	warn("  free win: " .. idleWins[i])
end

-- ── 5. Spam terminates, never wedges, and never breaks the engine ───────────
local spamBad = 0
local kindsSeen = {}
local widgetKindSet = {}
for kind in pairs(QTEEngine.WIDGET_KINDS) do
	widgetKindSet[kind] = true
end
local noWidgets = {}
for i = 1, #QTECatalog.list do
	local def = QTECatalog.list[i]
	local ok, result, clock, kinds = pcall(Pilot.run, taskFor(def.id, "Normal", 7, 1), "spam")
	if not ok then
		spamBad += 1
		warn("  spam error " .. def.id .. ": " .. tostring(result))
	else
		if result.state ~= "won" and result.state ~= "lost" then
			spamBad += 1
		end
		local any = false
		for k in pairs(kinds) do
			any = true
			kindsSeen[k] = true
			if not widgetKindSet[k] then
				warn("  undeclared widget kind '" .. tostring(k) .. "' from " .. def.id)
				spamBad += 1
			end
		end
		if not any then
			noWidgets[#noWidgets + 1] = def.id
		end
	end
end
check(spamBad == 0, "random input never crashes, wedges or emits an undeclared widget")
check(#noWidgets == 0, "every QTE draws at least one widget (" .. #noWidgets .. " drew nothing: " .. table.concat(noWidgets, ", ") .. ")")

-- ── 6. The expect channel is a working solver interface ─────────────────────
local expectKinds = {}
for i = 1, #QTEEngine.WIDGET_KINDS do
	expectKinds[QTEEngine.WIDGET_KINDS[i]] = true
end
local badExpect = 0
for i = 1, #QTECatalog.list do
	local def = QTECatalog.list[i]
	local task = taskFor(def.id, "Normal", 11, 1)
	local engine = QTEEngine.new(task, {})
	local pilot = Pilot.new("solve")
	for frame = 1, 40 do
		local view = engine:view()
		local want = view.expect
		if want == nil or want.kind == nil then
			badExpect += 1
			warn("  expect: " .. def.id .. " has no kind")
			break
		end
		if (want.kind == "key" or want.kind == "hold" or want.kind == "tap" or want.kind == "release") and want.token == nil then
			badExpect += 1
			warn("  expect: " .. def.id .. " asks for a " .. want.kind .. " with no token")
			break
		end
		if want.kind == "pointer" and want.x == nil then
			badExpect += 1
			warn("  expect: " .. def.id .. " points the solver at nothing")
			break
		end
		if want.kind == "look" and want.dir == nil then
			badExpect += 1
			warn("  expect: " .. def.id .. " asks for a look with no direction")
			break
		end
		engine:tick(pilot:sample(view, 1 / 60))
		if engine:isDone() then
			break
		end
	end
end
check(badExpect == 0, "every view carries a well-formed expect hint")

-- ── 7. Determinism and freshness ────────────────────────────────────────────
local function valueSignature(v)
	if type(v) ~= "table" then
		return tostring(v)
	end
	local parts = {}
	for k, inner in pairs(v) do
		parts[#parts + 1] = tostring(k) .. ":" .. valueSignature(inner)
	end
	table.sort(parts)
	return "{" .. table.concat(parts, ",") .. "}"
end

local function paramsSignature(id, seed)
	local task = taskFor(id, "Normal", seed, 1)
	return valueSignature(task.params)
end

local deterministic = true
local varying = 0
for i = 1, #QTECatalog.list do
	local def = QTECatalog.list[i]
	if paramsSignature(def.id, 3) ~= paramsSignature(def.id, 3) then
		deterministic = false
	end
	if paramsSignature(def.id, 3) ~= paramsSignature(def.id, 4) then
		varying += 1
	end
end
check(deterministic, "the same seed generates byte-identical parameters")
check(varying >= #QTECatalog.list * 0.5, "different seeds really do change the task (" .. varying .. " of " .. #QTECatalog.list .. " vary)")

-- ── 8. Director behaviour ───────────────────────────────────────────────────
local director = QTEDirector.new({ seed = 21, preset = "Normal" })
local picks = {}
local appearances = {}
for i = 1, 400 do
	local task = director:begin(1)
	if task == nil then
		break
	end
	picks[task.id] = (picks[task.id] or 0) + 1
	appearances[#appearances + 1] = task.id
end
local distinct = 0
for _ in pairs(picks) do
	distinct += 1
end
check(distinct >= 55, "weighted picking reaches " .. distinct .. " different QTEs in 400 draws")
local unreachable = {}
for i = 1, #QTECatalog.list do
	if picks[QTECatalog.list[i].id] == nil then
		unreachable[#unreachable + 1] = QTECatalog.list[i].id
	end
end
check(#unreachable == 0, "every catalogue entry is reachable (" .. #unreachable .. " starved)")

-- Freshness: a QTE just played should be less likely than an unseen one.
local fresh = QTEDirector.new({ seed = 3, preset = "Normal" })
local first = QTECatalog.list[1]
fresh.appearances[first.id] = 0
local w0 = fresh:effectiveWeight(first)
fresh.appearances[first.id] = 5
local w5 = fresh:effectiveWeight(first)
check(w5 < w0, "appearance weight decays with repetition (" .. string.format("%.3f -> %.3f", w0, w5) .. ")")

-- Capabilities gate the pool.
local touchOnly = QTEDirector.new({ seed = 4, preset = "Normal", capabilities = { Touch = true, Pointer = true } })
local badPool = 0
for i = 1, #touchOnly:pool() do
	local def = touchOnly:pool()[i]
	if def.caps.Key then
		badPool += 1
	end
end
check(badPool == 0, "a touch-only device is never offered a keyboard QTE")

-- Presets change the budget; health and streaks squeeze it further.
local function limitOf(preset, health, wins)
	local d = QTEDirector.new({ seed = 9, preset = preset })
	d.wins = wins or 0
	local task = select(1, d:beginNamed("Press", health))
	return task.timeLimit
end
local easyL, insaneL = limitOf("Easy", 1), limitOf("Insane", 1)
check(easyL > insaneL, "Easy gives more time than Insane (" .. string.format("%.2f > %.2f", easyL, insaneL) .. ")")
local healthyL, hurtL = limitOf("Normal", 1), limitOf("Normal", 0.05)
check(hurtL <= healthyL, "being nearly dead does not grant extra time")
local freshL, veteranL = limitOf("Normal", 1, 0), limitOf("Normal", 1, 40)
check(veteranL <= freshL, "a long win streak does not grant extra time")
check(veteranL >= QTEEngine.cost(taskFor("Press", "Normal", 9, 1), QTEConfig.Human).time,
	"even a 40-win streak cannot cut below the cost of the QTE")

-- Stats and grading.
local stats = QTEDirector.new({ seed = 5, preset = "Normal" })
local win = { state = "won", score = 0.95, id = "Press", reason = "complete", elapsed = 0.4, misses = 0 }
local loss = { state = "lost", score = 0.3, id = "Press", reason = "timeout", elapsed = 3, misses = 1 }
local r1 = stats:record(win)
check(r1.grade.name ~= "fail" and r1.streak == 1 and stats.bestStreak == 1, "a win grades, streaks and counts")
local r2 = stats:record(win)
check(r2.streak == 2, "streaks accumulate")
check(stats:record(loss).streak == 0, "a loss resets the streak")
check(stats.wins == 2 and stats.losses == 1, "wins and losses are counted separately")
check(QTEDirector.grade(loss).name == "fail", "a loss is never graded as a success whatever its score")
check(QTEDirector.grade(loss).escapeWeight == 0, "a failed QTE contributes nothing to escape progress")
check(QTEDirector.grade(win).escapeWeight > 0, "a won QTE contributes to escape progress")
local perfect = QTEDirector.grade({ state = "won", score = 1 })
local rough = QTEDirector.grade({ state = "won", score = 0.35 })
check(perfect.escapeWeight >= rough.escapeWeight, "a perfect QTE escapes better than a rough one")
check(stats:stats().runs == stats.runs, "stats report what was actually run")
stats:reset()
check(stats.wins == 0 and stats.losses == 0 and #stats:lastN(10) == 0, "reset clears stats and history")
-- lastN keeps order and length.
for i = 1, 5 do
	stats:record({ state = "won", score = 0.8, id = "Press" .. tostring(i), reason = "complete", elapsed = 0.3, misses = 0 })
end
local recent = stats:lastN(3)
check(#recent == 3 and recent[1].id == "Press3" and recent[3].id == "Press5", "history returns the newest results in order")

-- Custom QTE registration guards the mode namespace.
local custom = QTEDirector.new({ seed = 6, preset = "Normal" })
local okBad = custom:registerCustom({ id = "Bogus", mode = "not_a_mode", build = function()
	return { params = {} }
end })
check(okBad == false, "a custom QTE naming an unknown mode is refused")
local okGood = custom:registerCustom({
	id = "CustomPress",
	mode = "press",
	category = "Reflex",
	baseTime = 2.4,
	build = function(rng, ctx)
		return { prompt = "CUSTOM", params = { key = "E" } }
	end,
})
check(okGood == true, "a well-formed custom QTE registers")
local customTask = custom:beginNamed("CustomPress", 1)
check(customTask ~= nil and customTask.mode == "press", "and it can be started by id")
check(custom:registerCustom({ id = "CustomPress", mode = "press", build = function()
	return { params = { key = "E" } }
end }) == false, "registering the same id twice is refused")

-- ── 9. Concealment: answers leave the screen when the recall starts ─────────
local function taskHasShow(id)
	local probe = taskFor(id, "Normal", 13, 1)
	return probe.params.showSeconds ~= nil
end

local leaks = {}
local checkedLeak = 0
for i = 1, #QTECatalog.list do
	local def = QTECatalog.list[i]
	-- `type` only conceals when it shows the text first (WordRecall): WordType and
	-- friends are meant to have the word on screen the whole time.
	local typeConceals = (def.mode == "type") and taskHasShow(def.id)
	local conceal = (def.mode == "memorise") or (def.mode == "count") or (def.mode == "grid") or typeConceals
	if conceal then
		local task = taskFor(def.id, "Normal", 13, 1)
		local answer = ""
		if def.mode == "count" then
			answer = tostring(task.params.count)
		elseif def.mode == "type" then
			answer = tostring(task.params.text)
		elseif def.mode == "memorise" then
			for k = 1, #task.params.items do
				local item = task.params.items[k]
				answer = answer .. tostring(item.token or item)
			end
		else
			answer = "lit"
		end
		local engine = QTEEngine.new(task, {})
		local pilot = Pilot.new("idle")
		local seen = false
		for frame = 1, 600 do
			local view = engine:view()
			if def.mode ~= "grid" and #answer >= 2 then
				local text = QTEEngine.renderedText(view)
				local visible = view.answerVisible
				if visible then
					seen = true
				elseif string.find(text, answer, 1, true) then
					leaks[#leaks + 1] = def.id .. " shows " .. answer .. " after concealment"
					break
				end
			end
			engine:tick(pilot:sample(view, 1 / 60))
			if engine:isDone() then
				break
			end
		end
		if def.mode ~= "grid" and #answer >= 2 and not seen then
			leaks[#leaks + 1] = def.id .. " never showed its answer during the flash"
		end
		checkedLeak += 1
	end
end
check(checkedLeak >= 10, "concealment checked on " .. checkedLeak .. " memory QTEs")
check(#leaks == 0, "no memory QTE leaves its answer on screen during recall")
for i = 1, math.min(#leaks, 6) do
	warn("  leak: " .. leaks[i])
end

-- ── 10. Config surface used by the stack ────────────────────────────────────
check(type(QTEConfig.Human.KeySeconds) == "number" and QTEConfig.Human.KeySeconds > 0, "the human input model is present")
check(type(QTEConfig.Timing.GraceSeconds) == "number", "the input grace window is configured")
check(type(QTEConfig.Presets.Insane.timeMult) == "number" and QTEConfig.Presets.Insane.timeMult < QTEConfig.Presets.Easy.timeMult, "presets scale time in the right direction")
check(QTEConfig.DefaultPreset ~= nil and QTEConfig.Presets[QTEConfig.DefaultPreset] ~= nil, "the default preset exists")
check(type(QTEConfig.Pressure.HealthFloor) == "number" and QTEConfig.Pressure.HealthFloor > 0, "pressure has a floor (a dying player is still allowed to play)")
check(type(QTEConfig.Grades) == "table" and #QTEConfig.Grades >= 3, "grades are configured")
local gradeOk = true
for i = 1, #QTEConfig.Grades do
	local g = QTEConfig.Grades[i]
	if type(g.name) ~= "string" or type(g.minScore) ~= "number" or type(g.escapeWeight) ~= "number" or type(g.damage) ~= "number" or type(g.heal) ~= "number" then
		gradeOk = false
	end
end
check(gradeOk, "every grade carries a name, a score floor and the consequences the game reads")

-- ── 11. Sustained input has to be humanly possible, and cues must be seeable ──
local sustainBad, cueBad, pureBad = {}, {}, 0
for i = 1, #QTECatalog.list do
	local def = QTECatalog.list[i]
	for p = 1, #presets do
		local task = taskFor(def.id, presets[p], 2, 1)
		local cost = QTEEngine.cost(task, QTEConfig.Human)
		-- A mode that hands out a window (think) pays for the presses inside it; a
		-- rate above what the human model allows is a QTE nobody can hold.
		-- Only modes that hand out a SUSTAINED window (a mash, a hold, a track) can be
		-- judged by rate: a burst of taps in a short QTE is already priced by the total.
		if cost.think >= 1.0 and cost.keys > 0 then
			local rate = cost.keys / cost.think
			if rate > (1 / QTEConfig.Human.KeySeconds) + 1e-9 then
				sustainBad[#sustainBad + 1] = string.format("%s@%s needs %.1f presses/s", def.id, presets[p], rate)
			end
		end
		-- An unpredictable cue must stay up for at least a human reaction, or the QTE
		-- is a coin toss dressed up as a skill check. A regular beat is different: the
		-- player anticipates it, so a rhythm may use a tighter window - but never one
		-- so tight that it is judged by frame timing alone.
		local w = task.params.window
		if w ~= nil then
			local unpredictable = (def.mode == "react" or def.mode == "quickdraw")
			local floor = unpredictable and QTEConfig.Human.ReactionSeconds or 0.10
			if w < floor then
				cueBad[#cueBad + 1] = string.format("%s@%s window %.2fs", def.id, presets[p], w)
			end
		end
		-- cost() must be a pure read of the task: calling it twice cannot change it.
		local before = valueSignature(task.params)
		QTEEngine.cost(task, QTEConfig.Human)
		QTEEngine.cost(task, QTEConfig.Human)
		if valueSignature(task.params) ~= before then
			pureBad += 1
		end
	end
end
check(#sustainBad == 0, "no QTE asks for a sustained rate above the human input model (" .. #sustainBad .. " do)")
for i = 1, math.min(#sustainBad, 5) do
	warn("  too fast: " .. sustainBad[i])
end
check(#cueBad == 0, "every reaction window is longer than a human reaction time (" .. #cueBad .. " are not)")
for i = 1, math.min(#cueBad, 6) do
	warn("  tight window: " .. cueBad[i])
end
check(pureBad == 0, "measuring a QTE never changes it")

-- Device coverage: the catalogue must have content for each device it claims.
local keyCount, pointerCount = 0, 0
for i = 1, #QTECatalog.list do
	local caps = QTECatalog.list[i].caps
	if caps.Key then
		keyCount += 1
	end
	if caps.Pointer then
		pointerCount += 1
	end
end
check(keyCount >= 30, keyCount .. " QTEs are keyboard/gamepad playable")
check(pointerCount >= 10, pointerCount .. " QTEs need a pointer (mouse or touch)")

-- Weighted picking actually uses the weights.
local weighted = QTEDirector.new({ seed = 99, preset = "Normal" })
local heavy, light = nil, nil
for i = 1, #QTECatalog.list do
	local def = QTECatalog.list[i]
	if heavy == nil or def.weight > heavy.weight then
		heavy = def
	end
	if light == nil or def.weight < light.weight then
		light = def
	end
end
local counts = {}
for i = 1, 3000 do
	local task = select(1, weighted:begin(1))
	counts[task.id] = (counts[task.id] or 0) + 1
end
check((counts[heavy.id] or 0) > (counts[light.id] or 0),
	"the heaviest QTE (" .. heavy.id .. ") is drawn more often than the lightest (" .. light.id .. ")")

-- A custom QTE joins the pool, not just the id table.
local poolDirector = QTEDirector.new({ seed = 8, preset = "Normal" })
poolDirector:registerCustom({
	id = "CustomPool",
	mode = "press",
	category = "Reflex",
	baseTime = 2.0,
	build = function()
		return { prompt = "CUSTOM POOL", params = { key = "E" } }
	end,
})
local poolHas = false
for i = 1, #poolDirector:pool() do
	if poolDirector:pool()[i].id == "CustomPool" then
		poolHas = true
	end
end
check(poolHas, "a registered custom QTE is offered like any other")

print("=== QTE stack done ===")

return TESTS
