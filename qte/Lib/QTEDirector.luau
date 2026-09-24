--!strict
-- QTEDirector.luau
-- Location: ReplicatedStorage > QTE > Lib > QTEDirector  (ModuleScript)
-- Purpose:  Decides WHICH QTE runs, HOW LONG the player gets, and WHAT a result
--           means. It is the piece the game talks to; Lib/QTEEngine runs the one
--           that was chosen and Lib/QTECatalog is the list it chooses from.
--
--           It owns the four policy layers the v5 manager's 2 500-line body held
--           inline and untestable:
--
--             1. FEASIBILITY  limit = clamp(base * preset * adaptive * pressure,
--                             cost, MaxLimit). The lower clamp is the QTE's own
--                             measured cost (QTEEngine.cost), so no combination of
--                             difficulty, low health and a win streak can produce a
--                             limit shorter than the QTE's inputs require. The v5
--                             code clamped to a flat `minTimeLimit` and shipped
--                             "Insane + low HP" limits that no human could answer.
--             2. FRESHNESS    appearance-weighted picking, so the pool stays varied.
--             3. CAPABILITY   a QTE is only offered if the device can answer it.
--             4. GRADING      score -> grade -> the numbers the game reacts to
--                             (GoreConfig.Escape's weights live in QTEConfig.Grades).
--
--           Pure: no services, no Instances, no yields, no os.clock. Every random
--           draw comes from an injected RNG, so a session is reproducible.
--
-- Requires: Config/QTEConfig, Lib/QTECatalog, Lib/QTEEngine, Lib/RNG
-- Used by:  Controllers/QTEStruggle, tools/vitriol/tests.luau

local QTEConfig = require(script.Parent.Parent.Config.QTEConfig)
local QTECatalog = require(script.Parent.QTECatalog)
local QTEEngine = require(script.Parent.QTEEngine)
local RNG = require(script.Parent.RNG)

local QTEDirector = {}
QTEDirector.__index = QTEDirector

-- ── Construction ─────────────────────────────────────────────────────────────
-- opts = {
--   seed = number,                 -- determinism: same seed, same session
--   preset = "Normal",             -- QTEConfig.Presets key
--   capabilities = {Key=true,...}, -- QTEConfig.Devices.KeyboardMouse etc.
--   human = QTEConfig.Human,       -- override for tests/tuning
-- }
function QTEDirector.new(opts: any?): any
	local o = opts or {}
	local self = setmetatable({}, QTEDirector)
	self.rng = o.rng or RNG.new(o.seed or 1)
	self.preset = o.preset or QTEConfig.DefaultPreset
	self.capabilities = o.capabilities or QTEConfig.Devices.KeyboardMouse
	self.human = o.human or QTEConfig.Human
	self.appearances = {}
	self.wins = 0
	self.losses = 0
	self.streak = 0
	self.bestStreak = 0
	self.adaptive = QTEConfig.Adaptive.Start
	self.runs = 0
	self.lastResult = nil
	self.history = {}
	self.historyCount = 0
	self.custom = {}
	local problems = QTECatalog.validate(QTEEngine)
	if #problems > 0 then
		-- A broken definition is a content bug: say so once, loudly, at construction.
		for i = 1, #problems do
			warn(QTEConfig.Diagnostics.Prefix .. " catalog: " .. problems[i])
		end
	end
	return self
end

-- ── Capability filtering ─────────────────────────────────────────────────────
function QTEDirector:supports(def: any): boolean
	for cap in pairs(def.caps) do
		if not self.capabilities[cap] then
			return false
		end
	end
	return true
end

-- ── Feasibility ──────────────────────────────────────────────────────────────
-- pressureFraction is health/maxHealth (nil = healthy). winsThisSession drives the
-- second pressure term. Both are inputs, never read from the world here.
function QTEDirector:pressure(healthFraction: number?): number
	local p = QTEConfig.Pressure
	local health = 1
	if healthFraction ~= nil then
		health = math.clamp(healthFraction, 0, 1)
	end
	local healthMult = p.HealthFloor + p.HealthWeight * health
	local winMult = math.max(p.WinCap, 1 - math.min(self.wins, p.WinsForCap) * p.WinPenalty)
	return healthMult * winMult
end

-- limitFor(task, healthFraction) -> seconds
-- The single place a time limit is invented. Every caller goes through it.
function QTEDirector:limitFor(task: any, healthFraction: number?): number
	local preset = QTEConfig.Presets[self.preset] or QTEConfig.Presets[QTEConfig.DefaultPreset]
	local cost = QTEEngine.cost(task, self.human)
	local scaled = task.baseTime * preset.timeMult * self.adaptive * self:pressure(healthFraction)
	local floor = math.max(cost.time, QTEConfig.Timing.MinLimit)
	local ceiling = math.max(floor, math.min(QTEConfig.Timing.MaxLimit, task.baseTime * preset.timeMult))
	return math.clamp(scaled, floor, ceiling)
end

-- ── Picking ──────────────────────────────────────────────────────────────────
function QTEDirector:pool(): any
	local out = {}
	for i = 1, #QTECatalog.list do
		local def = QTECatalog.list[i]
		if self:supports(def) then
			out[#out + 1] = def
		end
	end
	for i = 1, #self.custom do
		local def = self.custom[i]
		if self:supports(def) then
			out[#out + 1] = def
		end
	end
	return out
end

-- effectiveWeight(def) = weight / (1 + appearances * penalty)
function QTEDirector:effectiveWeight(def: any): number
	local apps = self.appearances[def.id] or 0
	local preset = QTEConfig.Presets[self.preset] or QTEConfig.Presets[QTEConfig.DefaultPreset]
	return (def.weight * (preset.weightBias or 1)) / (1 + apps * QTEConfig.Freshness.AppearancePenalty)
end

function QTEDirector:pick(): any
	local candidates = self:pool()
	local total = 0
	for i = 1, #candidates do
		total += self:effectiveWeight(candidates[i])
	end
	if total <= 0 then
		return candidates[1]
	end
	local roll = self.rng:next() * total
	local acc = 0
	for i = 1, #candidates do
		acc += self:effectiveWeight(candidates[i])
		if roll <= acc then
			return candidates[i]
		end
	end
	return candidates[#candidates]
end

-- ── Building ─────────────────────────────────────────────────────────────────
-- makeTask(def, healthFraction) -> task
function QTEDirector:makeTask(def: any, healthFraction: number?): any
	local built = def.build(self.rng, { preset = self.preset })
	local task = {
		id = def.id,
		label = def.label,
		category = def.category,
		mode = def.mode,
		accent = def.accent,
		baseTime = def.baseTime,
		prompt = built.prompt or def.label,
		sub = built.sub,
		params = built.params or {},
		timeLimit = 0,
	}
	task.timeLimit = self:limitFor(task, healthFraction)
	return task
end

-- begin(healthFraction?) -> task
-- Picks, builds, timestamps and counts the appearance. The caller owns the engine.
function QTEDirector:begin(healthFraction: number?): any
	local def = self:pick()
	self.appearances[def.id] = (self.appearances[def.id] or 0) + 1
	self.runs += 1
	local task = self:makeTask(def, healthFraction)
	return task, def
end

-- beginNamed(id, healthFraction?) -> task?
-- Used by scripted scenes (a specific QTE for a specific kill beat) and by tests.
function QTEDirector:beginNamed(id: string, healthFraction: number?): any
	local def = QTECatalog.byId[id]
	if def == nil then
		return nil
	end
	self.appearances[def.id] = (self.appearances[def.id] or 0) + 1
	self.runs += 1
	return self:makeTask(def, healthFraction)
end

-- ── Grading ──────────────────────────────────────────────────────────────────
-- grade(result) -> {name, score, escapeWeight, damage, heal}
-- A loss is always "fail" whatever partial score it carries: the score is still
-- reported (the escape model reads progress), but "you were eliminated with 60%
-- progress" must not read as a clean escape anywhere downstream.
function QTEDirector.grade(result: any): any
	local score = math.clamp(result.score or 0, 0, 1)
	if result.state ~= QTEEngine.STATES.Won then
		return { name = "fail", score = score, escapeWeight = 0, damage = QTEConfig.Grades[#QTEConfig.Grades].damage, heal = 0 }
	end
	local chosen = QTEConfig.Grades[#QTEConfig.Grades]
	for i = 1, #QTEConfig.Grades do
		if score >= QTEConfig.Grades[i].minScore then
			chosen = QTEConfig.Grades[i]
			break
		end
	end
	return { name = chosen.name, score = score, escapeWeight = chosen.escapeWeight, damage = chosen.damage, heal = chosen.heal }
end

-- record(result) -> {grade, streak, bestStreak, wins, losses, adaptive}
-- The caller decides what damage/heal MEAN; in a game with a single health owner that is
-- the health service's business, which is why this module never touches a Humanoid.
function QTEDirector:record(result: any): any
	local grade = QTEDirector.grade(result)
	if result.state == QTEEngine.STATES.Won then
		self.wins += 1
		self.streak += 1
		if self.streak > self.bestStreak then
			self.bestStreak = self.streak
		end
		self.adaptive = math.max(QTEConfig.Adaptive.Floor, self.adaptive - QTEConfig.Adaptive.StepPerWin)
	else
		self.losses += 1
		self.streak = 0
		self.adaptive = QTEConfig.Adaptive.OnLoss
	end
	self.historyCount += 1
	local slot = ((self.historyCount - 1) % 32) + 1
	self.history[slot] = { id = result.id, grade = grade.name, reason = result.reason, score = grade.score }
	self.lastResult = { id = result.id, grade = grade, reason = result.reason, elapsed = result.elapsed, misses = result.misses }
	return {
		grade = grade,
		streak = self.streak,
		bestStreak = self.bestStreak,
		wins = self.wins,
		losses = self.losses,
		adaptive = self.adaptive,
	}
end

-- ── Introspection ────────────────────────────────────────────────────────────
function QTEDirector:stats(): any
	return {
		preset = self.preset,
		adaptive = self.adaptive,
		wins = self.wins,
		losses = self.losses,
		streak = self.streak,
		bestStreak = self.bestStreak,
		runs = self.runs,
		appearances = self.appearances,
		available = #self:pool(),
	}
end

function QTEDirector:setPreset(preset: string): boolean
	if QTEConfig.Presets[preset] == nil then
		return false
	end
	self.preset = preset
	return true
end

function QTEDirector:setCapabilities(caps: any): ()
	self.capabilities = caps
end

function QTEDirector:reset(): ()
	self.appearances = {}
	self.wins = 0
	self.losses = 0
	self.streak = 0
	self.bestStreak = 0
	self.adaptive = QTEConfig.Adaptive.Start
	self.runs = 0
	self.history = {}
	self.historyCount = 0
	self.lastResult = nil
end

function QTEDirector:resetAppearances(): ()
	self.appearances = {}
end

-- registerCustom(def) -> boolean
-- Runtime extensions must look like catalogue entries: same fields, same engine
-- modes. A custom QTE that names a mode that does not exist is rejected here rather
-- than failing when it is first picked.
function QTEDirector:registerCustom(def: any): boolean
	if def == nil or type(def.id) ~= "string" or type(def.build) ~= "function" then
		return false
	end
	if QTEEngine.MODES[def.mode] == nil then
		return false
	end
	if QTECatalog.byId[def.id] ~= nil then
		return false
	end
	local entry = {
		id = def.id,
		label = def.label or def.id,
		mode = def.mode,
		category = def.category or "Custom",
		weight = def.weight or 5,
		baseTime = def.baseTime or 3,
		caps = def.caps or { Key = true },
		accent = def.accent or { 200, 200, 200 },
		build = def.build,
	}
	self.custom[#self.custom + 1] = entry
	QTECatalog.byId[entry.id] = entry
	QTECatalog.list[#QTECatalog.list + 1] = entry
	return true
end

-- lastN(count) -> ordered recent results (oldest first)
function QTEDirector:lastN(count: number): any
	local out = {}
	local total = math.min(count, self.historyCount)
	for i = 1, total do
		local index = self.historyCount - total + i
		local slot = ((index - 1) % 32) + 1
		out[i] = self.history[slot]
	end
	return out
end

return QTEDirector
