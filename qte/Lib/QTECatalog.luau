--!strict
-- QTECatalog.luau
-- Location: ReplicatedStorage > QTE > Lib > QTECatalog  (ModuleScript)
-- Purpose:  Every QTE the game can ask for, as DATA. A definition names an engine
--           mode and supplies a generator that turns an RNG into that QTE's task
--           parameters, so "what QTEs exist" is one readable list and "what a QTE
--           does" is one tested state machine per mode (Lib/QTEEngine).
--
--           WHY DATA AND NOT 60 FUNCTIONS. The v5 manager held ~50 hand-written
--           coroutines; two of them were the same QTE registered twice, one printed
--           its own answer, one could hang the player forever, and none could be
--           executed off-device. A definition here cannot do any of that: it can
--           only choose a mode, set parameters, and be picked.
--
--           The list is grouped by family (README.md §5) and each entry records the
--           device capabilities it needs, so a phone is never asked to press Q.
--
-- Requires: Config/QTEConfig
-- Used by:  Lib/QTEDirector, Lib/QTEEngine (honours the params), tools/vitriol/tests-qte.luau

local QTEConfig = require(script.Parent.Parent.Config.QTEConfig)

local QTECatalog = {}

QTECatalog.list = {}
QTECatalog.byId = {}

-- ── Generator helpers ────────────────────────────────────────────────────────
-- Digit answers are TOKENS, never raw characters: the engine, the shell and the
-- catalogue all speak the token space defined by QTEConfig.InputMap/DigitTokens.
local function digitToken(ch: string): string
	return QTEConfig.DigitTokens[ch] or ch
end

local function pick(rng: any, pool: any): string
	return rng:pick(pool)
end

local function int(rng: any, lo: number, hi: number): number
	return rng:int(lo, hi)
end

-- Unique selection without repeats (the QTE must never show "E E E E").
local function unique(rng: any, pool: any, n: number): any
	local copy = {}
	for i = 1, #pool do
		copy[i] = pool[i]
	end
	local out = {}
	for i = 1, math.min(n, #copy) do
		local j = int(rng, i, #copy)
		copy[i], copy[j] = copy[j], copy[i]
		out[i] = copy[i]
	end
	return out
end

local function sequenceOf(rng: any, pool: any, n: number): any
	local out = {}
	for i = 1, n do
		out[i] = pick(rng, pool)
	end
	return out
end

local function words(tiers: any): any
	local out = {}
	for t = 1, #tiers do
		local bank = QTEConfig.Words[tiers[t]]
		for i = 1, #bank do
			out[#out + 1] = bank[i]
		end
	end
	return out
end

local function digits(rng: any, n: number): string
	local out = {}
	for i = 1, n do
		out[i] = tostring(int(rng, 1, 9))
	end
	return table.concat(out)
end

local DIR_SYMBOL = { W = "↑", A = "←", S = "↓", D = "→" }
local DIR_OPPOSITE = { W = "S", S = "W", A = "D", D = "A" }
local LETTER_OPPOSITE = { Q = "E", E = "Q", R = "F", F = "R" }

-- A structured arithmetic claim: the bank stores operands and the result the player
-- is SHOWN, so a false statement is provably false rather than hand-typed.
local function arithmeticStatement(rng: any): any
	local roll = int(rng, 1, 5)
	local text, value
	if roll == 1 then
		local a = int(rng, QTEConfig.TrueFalse.Add.min, QTEConfig.TrueFalse.Add.max)
		local b = int(rng, QTEConfig.TrueFalse.Add.min, QTEConfig.TrueFalse.Add.max)
		text = a .. " + " .. b
		value = a + b
	elseif roll == 2 then
		local a = int(rng, QTEConfig.TrueFalse.Sub.min, QTEConfig.TrueFalse.Sub.max)
		local b = int(rng, 1, a - 1)
		text = a .. " − " .. b
		value = a - b
	elseif roll == 3 then
		local a = int(rng, QTEConfig.TrueFalse.Mul.min, QTEConfig.TrueFalse.Mul.max)
		local b = int(rng, QTEConfig.TrueFalse.Mul.min, QTEConfig.TrueFalse.Mul.max)
		text = a .. " × " .. b
		value = a * b
	elseif roll == 4 then
		local a = int(rng, QTEConfig.TrueFalse.Square.min, QTEConfig.TrueFalse.Square.max)
		text = a .. "²"
		value = a * a
	else
		local a = int(rng, QTEConfig.TrueFalse.Root.min, QTEConfig.TrueFalse.Root.max)
		text = "√" .. tostring(a * a)
		value = a
	end
	local truthful = rng:chance(0.5)
	local shown = value
	if not truthful then
		local offset = QTEConfig.TrueFalse.FalseOffsets[int(rng, 1, #QTEConfig.TrueFalse.FalseOffsets)]
		shown = value + offset
		if shown == value then
			shown = value + 1
		end
	end
	return {
		text = text .. " = " .. tostring(shown),
		truthful = truthful,
	}
end

-- Only combinations whose NEXT TERM is a single digit: the player answers by
-- pressing a number key, so a two-digit answer would be unanswerable. The candidate
-- list is built once, so this cannot drift back into an impossible question.
local SERIES_COMBOS = {}
for step = 1, 4 do
	for first = 1, 5 do
		for count = 2, 3 do
			if first + count * step <= 9 then
				SERIES_COMBOS[#SERIES_COMBOS + 1] = { step = step, first = first, count = count }
			end
		end
	end
end

local function seriesItem(rng: any): any
	local combo = pick(rng, SERIES_COMBOS)
	local parts = {}
	for i = 1, combo.count do
		parts[i] = tostring(combo.first + (i - 1) * combo.step)
	end
	return {
		text = table.concat(parts, ", ") .. ", ?",
		token = digitToken(tostring(combo.first + combo.count * combo.step)),
	}
end

local function tallyItem(rng: any): any
	local pair = unique(rng, QTEConfig.Pools.Core, 2)
	local first = pair[1]
	local second = pair[2]
	local length = 5
	local parts = {}
	local count = 0
	for i = 1, length do
		if rng:chance(0.45) then
			parts[i] = second
			count += 1
		else
			parts[i] = first
		end
	end
	if count == 0 then
		parts[length] = second
		count = 1
	end
	return {
		text = table.concat(parts, " ") .. "  →  how many " .. second .. "?",
		token = digitToken(tostring(count)),
	}
end

local function stroopItems(rng: any, count: number, byInk: boolean): any
	local items = {}
	for _ = 1, count do
		local word = pick(rng, QTEConfig.Colours)
		local ink = pick(rng, QTEConfig.Colours)
		while ink.name == word.name do
			ink = pick(rng, QTEConfig.Colours)
		end
		items[#items + 1] = {
			text = word.name,
			colour = ink.rgb,
			token = byInk and ink.token or word.token,
		}
	end
	return items
end

local function colourSequenceItems(rng: any, count: number): any
	local items = {}
	for _ = 1, count do
		local colour = pick(rng, QTEConfig.Colours)
		items[#items + 1] = { token = colour.token, colour = colour.rgb }
	end
	return items
end

local function gridParams(rng: any, cols: number, rows: number, litCount: number): any
	local size = 0.46
	local cellW = size / cols
	local cellH = size / rows
	local originX = 0.5 - size * 0.5
	local originY = 0.44 - size * 0.5
	local order = {}
	for i = 1, cols * rows do
		order[i] = i
	end
	for i = #order, 2, -1 do
		local j = int(rng, 1, i)
		order[i], order[j] = order[j], order[i]
	end
	local lit = {}
	local litSet = {}
	for i = 1, litCount do
		lit[i] = order[i]
		litSet[order[i]] = true
	end
	return {
		cols = cols,
		rows = rows,
		lit = lit,
		litSet = litSet,
		originX = originX,
		originY = originY,
		cellW = cellW,
		cellH = cellH,
		flashSeconds = 1.4 + 0.2 * litCount,
	}
end

local function symbolItems(rng: any, count: number, mapping: any, symbols: any): any
	local keys = {}
	for k in pairs(mapping) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local items = {}
	for _ = 1, count do
		local shown = pick(rng, keys)
		items[#items + 1] = {
			shown = symbols and symbols[shown] or shown,
			token = mapping[shown],
		}
	end
	return items
end

-- ── Registration ─────────────────────────────────────────────────────────────
local function define(def: any): ()
	assert(type(def.id) == "string" and def.id ~= "", "QTE id must be a string")
	assert(QTECatalog.byId[def.id] == nil, "duplicate QTE id: " .. def.id)
	assert(type(def.build) == "function", "QTE " .. def.id .. " needs a build()")
	assert(type(def.weight) == "number" and def.weight > 0, "QTE " .. def.id .. " needs weight > 0")
	QTECatalog.byId[def.id] = def
	QTECatalog.list[#QTECatalog.list + 1] = def
end

-- ── Family A: Reflex — one discrete input, speed is the whole test ───────────
define({
	id = "Press",
	label = "Press",
	mode = "press",
	category = "Reflex",
	weight = 10,
	baseTime = 2.2,
	caps = { Key = true },
	accent = { 80, 200, 255 },
	build = function(rng)
		local key = pick(rng, QTEConfig.Pools.Wide)
		return { prompt = "PRESS  ► " .. key, params = { key = key, strict = false } }
	end,
})

define({
	id = "React",
	label = "React",
	mode = "react",
	category = "Reflex",
	weight = 10,
	baseTime = 2.6,
	caps = { Key = true },
	accent = { 60, 255, 140 },
	build = function(rng)
		local keys = {}
		for i = 1, #QTEConfig.Pools.Wide do
			keys[i] = QTEConfig.Pools.Wide[i]
		end
		keys[#keys + 1] = "Space"
		return {
			prompt = "WAIT FOR IT...",
			sub = "Press anything the instant it changes",
			params = {
				keys = keys,
				cueAt = int(rng, 8, 22) / 10,
				window = 0.9,
				falseStart = true,
				cueText = "NOW!",
			},
		}
	end,
})

define({
	id = "Dodge",
	label = "Dodge",
	mode = "react",
	category = "Reflex",
	weight = 9,
	baseTime = 2.2,
	caps = { Key = true },
	accent = { 255, 90, 90 },
	build = function(rng)
		return {
			prompt = "!!! DANGER !!!",
			sub = "Dodge on the cue",
			params = {
				keys = { "Space" },
				cueAt = int(rng, 8, 20) / 10,
				window = 0.8,
				falseStart = true,
				cueText = "SPACE  —  DODGE!",
			},
		}
	end,
})

define({
	id = "Snap",
	label = "Snap",
	mode = "react",
	category = "Reflex",
	weight = 7,
	baseTime = 1.9,
	caps = { Key = true },
	accent = { 255, 200, 60 },
	build = function(rng)
		return {
			prompt = "STEADY...",
			sub = "One exact input, no others",
			params = {
				keys = { "Space" },
				cueAt = int(rng, 7, 18) / 10,
				window = 0.55,
				falseStart = true,
				cueText = "SNAP!",
			},
		}
	end,
})

define({
	id = "QuickDraw",
	label = "Quick Draw",
	mode = "quickdraw",
	category = "Reflex",
	weight = 7,
	baseTime = 2.4,
	caps = { Key = true },
	accent = { 255, 70, 70 },
	build = function(rng)
		local key = pick(rng, QTEConfig.Pools.Core)
		return {
			prompt = "QUICK  DRAW!",
			sub = "Do not draw before the signal",
			params = {
				key = key,
				cueAt = int(rng, 9, 24) / 10,
				window = 0.45,
				cueText = "DRAW!  ► " .. key .. " ◄",
			},
		}
	end,
})

define({
	id = "DoubleTap",
	label = "Double Tap",
	mode = "exact",
	category = "Reflex",
	weight = 7,
	baseTime = 2.4,
	caps = { Key = true },
	accent = { 0, 210, 255 },
	build = function(rng)
		local key = pick(rng, QTEConfig.Pools.Core)
		return {
			prompt = "TAP  " .. key .. "  EXACTLY  TWICE",
			sub = "One extra tap fails it",
			params = { key = key, count = 2, settle = 0.7 },
		}
	end,
})

define({
	id = "Ambush",
	label = "Ambush",
	mode = "react",
	category = "Reflex",
	weight = 6,
	baseTime = 1.8,
	caps = { Key = true },
	accent = { 220, 60, 220 },
	build = function(rng)
		return {
			prompt = "SOMETHING MOVED",
			sub = "Very short window",
			params = {
				keys = { "Space", "E", "R", "F", "Q" },
				cueAt = int(rng, 5, 14) / 10,
				window = 0.45,
				falseStart = true,
				cueText = "!! NOW !!",
			},
		}
	end,
})

define({
	id = "ReflexMulti",
	label = "Reflex Multi",
	mode = "hit",
	category = "Reflex",
	weight = 6,
	baseTime = 3.2,
	caps = { Pointer = true, Click = true },
	accent = { 255, 110, 110 },
	build = function(rng)
		local count = int(rng, 3, 5)
		local targets = {}
		for i = 1, count do
			targets[i] = {
				x = int(rng, 18, 82) / 100,
				y = int(rng, 22, 78) / 100,
				radius = 0.055,
			}
		end
		return {
			prompt = "CLICK  ALL  " .. tostring(count) .. "  TARGETS",
			params = { targets = targets, maxMisses = 1 },
		}
	end,
})

-- ── Family B: Motor — repetition, endurance, rhythm of effort ────────────────
define({
	id = "Spam",
	label = "Mash",
	mode = "mash",
	category = "Motor",
	weight = 10,
	baseTime = 2.8,
	caps = { Key = true },
	accent = { 255, 150, 40 },
	build = function(rng)
		local key = pick(rng, QTEConfig.Pools.Core)
		local count = int(rng, 5, 9)
		return {
			prompt = "MASH  " .. key .. "  (" .. tostring(count) .. ")",
			params = { key = key, count = count, strict = false },
		}
	end,
})

define({
	id = "MultiSpam",
	label = "Alternate",
	mode = "alternate",
	category = "Motor",
	weight = 8,
	baseTime = 3.2,
	caps = { Key = true },
	accent = { 255, 120, 20 },
	build = function(rng)
		local pair = pick(rng, QTEConfig.Pairs)
		local count = int(rng, 6, 10)
		return {
			prompt = "ALTERNATE  " .. pair[1] .. "  ⟷  " .. pair[2],
			params = { cycle = { pair[1], pair[2] }, count = count },
		}
	end,
})

define({
	id = "TripleThreat",
	label = "Triple Threat",
	mode = "alternate",
	category = "Motor",
	weight = 6,
	baseTime = 3.6,
	caps = { Key = true },
	accent = { 255, 90, 160 },
	build = function(rng)
		local cycle = sequenceOf(rng, QTEConfig.Pools.Core, 3)
		local count = int(rng, 6, 9)
		return {
			prompt = "CYCLE  " .. table.concat(cycle, "  →  "),
			params = { cycle = cycle, count = count },
		}
	end,
})

define({
	id = "Survive",
	label = "Survive",
	mode = "meter",
	category = "Motor",
	weight = 6,
	baseTime = 4.0,
	caps = { Key = true },
	accent = { 255, 80, 80 },
	build = function(rng)
		local key = pick(rng, QTEConfig.Pools.Core)
		local seconds = int(rng, 30, 45) / 10
		return {
			prompt = "MASH  " .. key .. "  —  STAY  ALIVE",
			sub = "The drain accelerates",
			params = {
				key = key,
				seconds = seconds,
				start = 0.75,
				drain0 = 0.5,
				growth = 0.05,
				push = 0.18,
				keepAbove = 0.4,
				floorAtEnd = 0.05,
			},
		}
	end,
})

define({
	id = "Crescendo",
	label = "Crescendo",
	mode = "meter",
	category = "Motor",
	weight = 5,
	baseTime = 4.5,
	caps = { Key = true },
	accent = { 120, 200, 255 },
	build = function(rng)
		local key = pick(rng, QTEConfig.Pools.Core)
		local seconds = int(rng, 40, 55) / 10
		return {
			prompt = "CRESCENDO  —  MASH  " .. key,
			sub = "Speeding up: end above 45%",
			params = {
				key = key,
				seconds = seconds,
				start = 0.8,
				drain0 = 0.55,
				growth = 0.09,
				push = 0.2,
				keepAbove = 0.5,
				floorAtEnd = 0.45,
			},
		}
	end,
})

define({
	id = "TugOfWar",
	label = "Tug of War",
	mode = "tug",
	category = "Motor",
	weight = 5,
	baseTime = 4.5,
	caps = { Key = true },
	accent = { 255, 60, 60 },
	build = function(rng)
		local key = pick(rng, QTEConfig.Pools.Core)
		local seconds = int(rng, 40, 55) / 10
		return {
			prompt = "TUG  OF  WAR  —  MASH  " .. key,
			params = {
				key = key,
				seconds = seconds,
				travel = 1,
				start = 0.5,
				drain = 0.16,
				push = 0.09,
			},
		}
	end,
})

define({
	id = "ExactTaps",
	label = "Exact Taps",
	mode = "exact",
	category = "Motor",
	weight = 6,
	baseTime = 3.2,
	caps = { Key = true },
	accent = { 200, 110, 255 },
	build = function(rng)
		local key = pick(rng, QTEConfig.Pools.Core)
		local count = int(rng, 3, 7)
		return {
			prompt = "TAP  " .. key .. "  EXACTLY  " .. tostring(count) .. "  TIMES",
			sub = "Then stop — one extra fails it",
			params = { key = key, count = count, settle = 0.8 },
		}
	end,
})

define({
	id = "Endure",
	label = "Endure",
	mode = "hold",
	category = "Motor",
	weight = 6,
	baseTime = 3.6,
	caps = { Key = true },
	accent = { 90, 180, 255 },
	build = function(rng)
		local key = pick(rng, QTEConfig.Pools.Core)
		local seconds = int(rng, 20, 32) / 10
		return {
			prompt = "HOLD  ►  " .. key,
			sub = "Do not let go",
			params = { key = key, seconds = seconds, allowRestart = true, maxMisses = 1 },
		}
	end,
})

define({
	id = "Brace",
	label = "Brace",
	mode = "holdAll",
	category = "Motor",
	weight = 5,
	baseTime = 3.4,
	caps = { Key = true },
	accent = { 0, 170, 255 },
	build = function(rng)
		local pair = pick(rng, QTEConfig.Pairs)
		local keys = { pair[1], pair[2] }
		if rng:chance(0.35) then
			for i = 1, #QTEConfig.Pools.Core do
				local extra = QTEConfig.Pools.Core[i]
				if extra ~= keys[1] and extra ~= keys[2] then
					keys[3] = extra
					break
				end
			end
		end
		local seconds = int(rng, 15, 24) / 10
		return {
			prompt = "HOLD  ALL:  " .. table.concat(keys, "  +  "),
			params = { keys = keys, seconds = seconds },
		}
	end,
})

-- ── Family C: Precision — the pointer is the instrument ─────────────────────
define({
	id = "Aim",
	label = "Aim",
	mode = "aim",
	category = "Precision",
	weight = 7,
	baseTime = 2.6,
	caps = { Pointer = true },
	accent = { 255, 120, 120 },
	build = function(rng)
		local x = int(rng, 16, 84) / 100
		local y = int(rng, 20, 78) / 100
		return {
			prompt = "MOVE  ONTO  THE  TARGET",
			params = {
				target = { x = x, y = y, radius = 0.05, distance = 0.7 },
			},
		}
	end,
})

define({
	id = "ClickTarget",
	label = "Click Target",
	mode = "hit",
	category = "Precision",
	weight = 7,
	baseTime = 2.8,
	caps = { Pointer = true, Click = true },
	accent = { 255, 100, 0 },
	build = function(rng)
		return {
			prompt = "CLICK  THE  MOVING  TARGET",
			params = {
				targets = {
					{
						x = 0.5,
						y = 0.5,
						radius = 0.05,
						speed = int(rng, 20, 35) / 100,
						phase = int(rng, 0, 60) / 10,
						travelX = 0.26,
						travelY = 0.16,
					},
				},
				maxMisses = 1,
			},
		}
	end,
})

define({
	id = "Skeet",
	label = "Skeet",
	mode = "hit",
	category = "Precision",
	weight = 4,
	baseTime = 3.2,
	caps = { Pointer = true, Click = true },
	accent = { 255, 180, 60 },
	build = function(rng)
		local targets = {}
		for i = 1, 2 do
			targets[i] = {
				x = 0.3 + 0.4 * i / 2,
				y = 0.5,
				radius = 0.055,
				speed = int(rng, 25, 40) / 100,
				phase = int(rng, 0, 60) / 10,
				travelX = 0.18,
				travelY = 0.22,
			}
		end
		return {
			prompt = "CLICK  BOTH  TARGETS",
			params = { targets = targets, maxMisses = 2 },
		}
	end,
})

define({
	id = "Shake",
	label = "Shake",
	mode = "shake",
	category = "Precision",
	weight = 5,
	baseTime = 3.4,
	caps = { Pointer = true },
	accent = { 255, 210, 0 },
	build = function(rng)
		return {
			prompt = "SHAKE  FREE!",
			sub = "Move the pointer hard, left and right",
			params = {
				requiredScreens = int(rng, 40, 60) / 10,
				speed = 2.2,
			},
		}
	end,
})

define({
	id = "Spin",
	label = "Spin",
	mode = "spin",
	category = "Precision",
	weight = 5,
	baseTime = 2.8,
	caps = { Pointer = true },
	accent = { 170, 80, 255 },
	build = function(rng)
		local turns = int(rng, 1, 2)
		local cw = rng:chance(0.5)
		return {
			prompt = "SPIN  THE  POINTER  " .. (cw and "CLOCKWISE" or "ANTICLOCKWISE"),
			sub = tostring(turns) .. " full turn(s)",
			params = {
				turns = { turns },
				directions = { cw and "cw" or "ccw" },
				speed = 2.4,
			},
		}
	end,
})

define({
	id = "SafeCracker",
	label = "Safe Cracker",
	mode = "spin",
	category = "Precision",
	weight = 3,
	baseTime = 3.6,
	caps = { Pointer = true },
	accent = { 200, 180, 60 },
	build = function(rng)
		local first = int(rng, 1, 2)
		local second = int(rng, 1, 2)
		return {
			prompt = "PICK  THE  LOCK",
			sub = tostring(first) .. " turns one way, then " .. tostring(second) .. " back",
			params = {
				turns = { first, second },
				directions = { "cw", "ccw" },
				speed = 2.4,
			},
		}
	end,
})

define({
	id = "Track",
	label = "Track",
	mode = "track",
	category = "Precision",
	weight = 4,
	baseTime = 3.4,
	caps = { Pointer = true },
	accent = { 255, 220, 0 },
	build = function(rng)
		local seconds = int(rng, 22, 34) / 10
		return {
			prompt = "STAY  ON  THE  TARGET",
			sub = "It is moving — keep the pointer on it",
			params = {
				seconds = seconds,
				radius = 0.16,
				ratioX = 1.6,
				speed = int(rng, 20, 32) / 100,
				phase = int(rng, 0, 60) / 10,
				tolerance = 0.075,
				maxDrift = 0.5,
			},
		}
	end,
})

define({
	id = "Trace",
	label = "Trace",
	mode = "trace",
	category = "Precision",
	weight = 4,
	baseTime = 3.8,
	caps = { Pointer = true },
	accent = { 150, 150, 255 },
	build = function(rng)
		local points = {}
		local count = 5
		local cx = int(rng, 42, 58) / 100
		local cy = int(rng, 42, 58) / 100
		for i = 1, count do
			points[i] = {
				x = math.clamp(cx + math.cos(i * 1.9) * 0.26, 0.08, 0.92),
				y = math.clamp(cy + math.sin(i * 1.9) * 0.2, 0.1, 0.86),
			}
		end
		return {
			prompt = "TRACE  THE  PATH",
			sub = "Watch it once, then follow the dots",
			params = {
				points = points,
				tolerance = 0.055,
				showSeconds = 1.5,
			},
		}
	end,
})

define({
	id = "Steady",
	label = "Steady",
	mode = "steady",
	category = "Precision",
	weight = 4,
	baseTime = 3.6,
	caps = { Pointer = true, Click = true },
	accent = { 120, 255, 140 },
	build = function(rng)
		local seconds = int(rng, 11, 17) / 10
		return {
			prompt = "HOLD  YOUR  BREATH",
			sub = "Keep still, then click the instant it says CLICK",
			params = {
				seconds = seconds,
				maxSpeed = 0.05,
				clickWindow = 1.1,
				centerX = 0.5,
				centerY = 0.5,
			},
		}
	end,
})

define({
	id = "HotCold",
	label = "Hot / Cold",
	mode = "search",
	category = "Precision",
	weight = 4,
	baseTime = 3.4,
	caps = { Pointer = true },
	accent = { 255, 120, 0 },
	build = function(rng)
		return {
			prompt = "FIND  IT  (HOT / COLD)",
			sub = "Sweep the pointer until it reads hot",
			params = {
				target = { x = int(rng, 18, 82) / 100, y = int(rng, 22, 78) / 100 },
				radius = 0.05,
				hotRadius = 0.14,
				warmRadius = 0.3,
				searchScreens = 3,
			},
		}
	end,
})

-- ── Family D: Timing — the deadline is not "when", it is "at" ───────────────
define({
	id = "StepTiming",
	label = "On the Beat",
	mode = "timed",
	category = "Timing",
	weight = 7,
	baseTime = 2.6,
	caps = { Key = true },
	accent = { 60, 230, 180 },
	build = function(rng)
		local key = pick(rng, QTEConfig.Pools.Core)
		return {
			prompt = "ON  THE  BEAT  [ " .. key .. " ]",
			sub = "One cue — press exactly on it",
			params = {
				key = key,
				beats = 1,
				firstCue = int(rng, 9, 20) / 10,
				interval = 0.7,
				window = 0.3,
			},
		}
	end,
})

define({
	id = "Metronome",
	label = "Metronome",
	mode = "timed",
	category = "Timing",
	weight = 6,
	baseTime = 3.8,
	caps = { Key = true },
	accent = { 120, 235, 120 },
	build = function(rng)
		local key = pick(rng, QTEConfig.Pools.Core)
		local beats = int(rng, 3, 4)
		return {
			prompt = "KEEP  THE  BEAT  [ " .. key .. " ]",
			params = {
				key = key,
				beats = beats,
				firstCue = int(rng, 10, 16) / 10,
				interval = int(rng, 64, 82) / 100,
				window = 0.22,
				maxMisses = 1,
			},
		}
	end,
})

define({
	id = "Rhythm",
	label = "Rhythm",
	mode = "timed",
	category = "Timing",
	weight = 5,
	baseTime = 3.6,
	caps = { Key = true },
	accent = { 255, 160, 40 },
	build = function(rng)
		local key = pick(rng, QTEConfig.Pools.Core)
		local beats = int(rng, 4, 6)
		return {
			prompt = "HOLD  THE  RHYTHM  [ " .. key .. " ]",
			params = {
				key = key,
				beats = beats,
				firstCue = int(rng, 8, 13) / 10,
				interval = int(rng, 42, 55) / 100,
				window = 0.17,
				maxMisses = 1,
			},
		}
	end,
})

define({
	id = "SlideBar",
	label = "Slide Bar",
	mode = "release",
	category = "Timing",
	weight = 7,
	baseTime = 3.0,
	caps = { Key = true },
	accent = { 80, 220, 120 },
	build = function(rng)
		local width = 0.16
		local centre = int(rng, 30, 70) / 100
		return {
			prompt = "STOP  IN  THE  ZONE  [ SPACE ]",
			params = {
				key = "Space",
				trigger = "press",
				style = "pingpong",
				period = int(rng, 16, 22) / 10,
				phaseOffset = int(rng, 0, 40) / 10,
				zone = { from = centre - width * 0.5, to = centre + width * 0.5 },
			},
		}
	end,
})

define({
	id = "FuseCut",
	label = "Fuse Cut",
	mode = "release",
	category = "Timing",
	weight = 5,
	baseTime = 2.8,
	caps = { Key = true },
	accent = { 255, 90, 0 },
	build = function(rng)
		local centre = int(rng, 35, 75) / 100
		return {
			prompt = "CUT  THE  FUSE  IN  THE  ZONE",
			sub = "The spark sweeps once — time it",
			params = {
				key = "Space",
				trigger = "press",
				style = "sweep",
				zone = { from = centre - 0.07, to = centre + 0.07 },
			},
		}
	end,
})

define({
	id = "TimedRelease",
	label = "Timed Release",
	mode = "release",
	category = "Timing",
	weight = 6,
	baseTime = 3.4,
	caps = { Key = true },
	accent = { 80, 200, 180 },
	build = function(rng)
		local key = pick(rng, QTEConfig.Pools.Core)
		local centre = int(rng, 35, 70) / 100
		return {
			prompt = "HOLD  " .. key .. "  —  RELEASE  IN  THE  ZONE",
			params = {
				key = key,
				trigger = "release",
				style = "pingpong",
				period = int(rng, 20, 28) / 10,
				phaseOffset = int(rng, 0, 40) / 10,
				zone = { from = centre - 0.09, to = centre + 0.09 },
			},
		}
	end,
})

define({
	id = "PressureGauge",
	label = "Pressure Gauge",
	mode = "gauge",
	category = "Timing",
	weight = 4,
	baseTime = 4.2,
	caps = { Key = true },
	accent = { 100, 200, 140 },
	build = function(rng)
		local seconds = int(rng, 30, 45) / 10
		local centre = int(rng, 55, 70) / 100
		return {
			prompt = "HOLD  SPACE  —  FILL  INTO  THE  ZONE",
			sub = "The reading at the end must be inside",
			params = {
				key = "Space",
				seconds = seconds,
				fillRate = 0.55,
				drainRate = 0.35,
				zone = { from = centre - 0.1, to = centre + 0.1 },
			},
		}
	end,
})

-- ── Family E: Memory — hold it, then give it back ───────────────────────────
define({
	id = "Simon",
	label = "Simon",
	mode = "memorise",
	category = "Memory",
	weight = 6,
	baseTime = 4.2,
	caps = { Key = true },
	accent = { 100, 180, 255 },
	build = function(rng)
		local items = sequenceOf(rng, QTEConfig.Pools.Core, int(rng, 3, 5))
		return {
			prompt = "MEMORISE  THE  SEQUENCE",
			params = {
				items = items,
				entry = "forward",
				flashPerItem = 0.6,
				gapAfter = 1,
				flashPrompt = "MEMORISE",
				recallPrompt = "REPEAT  IT  —  IN  ORDER",
			},
		}
	end,
})

define({
	id = "ReverseSeq",
	label = "Reverse",
	mode = "memorise",
	category = "Memory",
	weight = 5,
	baseTime = 4.4,
	caps = { Key = true },
	accent = { 255, 80, 200 },
	build = function(rng)
		local items = sequenceOf(rng, QTEConfig.Pools.Core, int(rng, 3, 4))
		return {
			prompt = "MEMORISE  —  THEN  REVERSE  IT",
			params = {
				items = items,
				entry = "reverse",
				flashPerItem = 0.62,
				gapAfter = 1,
				recallPrompt = "NOW  REVERSE  ORDER  (last one first)",
			},
		}
	end,
})

define({
	id = "LastKeyFlash",
	label = "Last Key",
	mode = "memorise",
	category = "Memory",
	weight = 6,
	baseTime = 3.6,
	caps = { Key = true },
	accent = { 255, 130, 0 },
	build = function(rng)
		local items = sequenceOf(rng, QTEConfig.Pools.Wide, int(rng, 4, 6))
		return {
			prompt = "WATCH  CLOSELY",
			params = {
				items = items,
				entry = "last",
				flashPerItem = 0.42,
				gapAfter = 1,
				recallPrompt = "PRESS  ONLY  THE  LAST  KEY",
			},
		}
	end,
})

define({
	id = "PatternMemoryBurst",
	label = "Memory Burst",
	mode = "memorise",
	category = "Memory",
	weight = 5,
	baseTime = 3.4,
	caps = { Key = true },
	accent = { 255, 120, 255 },
	build = function(rng)
		local items = sequenceOf(rng, QTEConfig.Pools.Core, int(rng, 3, 4))
		return {
			prompt = "MEMORISE  FAST",
			params = {
				items = items,
				entry = "forward",
				flashPerItem = int(rng, 28, 36) / 100,
				gapAfter = 1,
				recallPrompt = "REPLAY  THE  BURST",
			},
		}
	end,
})

define({
	id = "ColourSequence",
	label = "Colour Sequence",
	mode = "memorise",
	category = "Memory",
	weight = 5,
	baseTime = 4.0,
	caps = { Key = true },
	accent = { 200, 100, 255 },
	build = function(rng)
		local items = colourSequenceItems(rng, int(rng, 3, 4))
		return {
			prompt = "MEMORISE  THE  COLOURS",
			params = {
				items = items,
				entry = "forward",
				flashPerItem = 0.7,
				gapAfter = 1,
				recallPrompt = "REPEAT  THE  COLOURS",
				recallSub = "R = red, G = green, B = blue, T = gold",
			},
		}
	end,
})

define({
	id = "MemoryGrid",
	label = "Memory Grid",
	mode = "grid",
	category = "Memory",
	weight = 4,
	baseTime = 4.0,
	caps = { Pointer = true, Click = true },
	accent = { 255, 220, 0 },
	build = function(rng)
		local litCount = int(rng, QTEConfig.Perception.MemoryGrid.lit[1], QTEConfig.Perception.MemoryGrid.lit[2])
		local params = gridParams(rng, QTEConfig.Perception.MemoryGrid.size, QTEConfig.Perception.MemoryGrid.size, litCount)
		return {
			prompt = "MEMORISE  THE  LIT  CELLS",
			sub = "Then click exactly those",
			params = params,
		}
	end,
})

define({
	id = "FlashDigit",
	label = "Flash Digit",
	mode = "memorise",
	category = "Memory",
	weight = 5,
	baseTime = 3.8,
	caps = { Key = true },
	accent = { 255, 220, 0 },
	build = function(rng)
		local count = int(rng, 2, 4)
		local items = {}
		local text = digits(rng, count)
		for i = 1, count do
			items[i] = text:sub(i, i)
		end
		return {
			prompt = "MEMORISE  THE  NUMBER",
			params = {
				items = items,
				entry = "forward",
				showAll = true,
				flashSeconds = 1.1,
				recallPrompt = "TYPE  WHAT  YOU  SAW",
				recallSub = tostring(count) .. " digits",
			},
		}
	end,
})

define({
	id = "PhoneDial",
	label = "Phone Dial",
	mode = "memorise",
	category = "Memory",
	weight = 5,
	baseTime = 4.4,
	caps = { Key = true },
	accent = { 255, 180, 0 },
	build = function(rng)
		local code = digits(rng, 4)
		local items = {}
		for i = 1, 4 do
			items[i] = code:sub(i, i)
		end
		return {
			prompt = "REMEMBER  THE  CODE",
			params = {
				items = items,
				entry = "forward",
				showAll = true,
				flashSeconds = 1.8,
				recallPrompt = "DIAL  IT  BACK",
				recallSub = "Four digits, in order",
			},
		}
	end,
})

define({
	id = "MemoryPalace",
	label = "Memory Palace",
	mode = "memorise",
	category = "Memory",
	weight = 3,
	baseTime = 5.2,
	caps = { Key = true },
	accent = { 255, 90, 140 },
	build = function(rng)
		local items = sequenceOf(rng, QTEConfig.Pools.Wide, 6)
		return {
			prompt = "MEMORISE  SIX",
			params = {
				items = items,
				entry = "reverse",
				flashPerItem = 0.5,
				gapAfter = 1,
				recallPrompt = "REVERSE  ALL  SIX",
			},
		}
	end,
})

define({
	id = "WordRecall",
	label = "Word Recall",
	mode = "type",
	category = "Memory",
	weight = 6,
	baseTime = 4.2,
	caps = { Key = true },
	accent = { 255, 200, 80 },
	build = function(rng)
		local word = pick(rng, words({ "Short", "Medium" }))
		return {
			prompt = "MEMORISE  THE  WORD",
			params = {
				text = word,
				reveal = false,
				conceal = true,
				showSeconds = int(rng, 13, 18) / 10,
				allowBackspace = true,
				maxMisses = 0,
				recallPrompt = "TYPE  IT  FROM  MEMORY",
			},
		}
	end,
})

-- ── Family E2: Typing (the words themselves are the test) ───────────────────
define({
	id = "WordType",
	label = "Type It",
	mode = "type",
	category = "Memory",
	weight = 6,
	baseTime = 3.8,
	caps = { Key = true },
	accent = { 255, 245, 120 },
	build = function(rng)
		local word = pick(rng, words({ "Short" }))
		return {
			prompt = "TYPE  IT",
			params = {
				text = word,
				reveal = true,
				allowBackspace = true,
				maxMisses = 0,
			},
		}
	end,
})

define({
	id = "Spelling",
	label = "Spelling",
	mode = "type",
	category = "Memory",
	weight = 4,
	baseTime = 4.8,
	caps = { Key = true },
	accent = { 200, 255, 140 },
	build = function(rng)
		local word = pick(rng, words({ "Hard", "VeryHard" }))
		return {
			prompt = "TYPE  IT  EXACTLY",
			sub = "Long word — take your time",
			params = {
				text = word,
				reveal = true,
				allowBackspace = true,
				maxMisses = 1,
			},
		}
	end,
})

define({
	id = "RapidTyping",
	label = "Rapid Typing",
	mode = "type",
	category = "Memory",
	weight = 5,
	baseTime = 4.2,
	caps = { Key = true },
	accent = { 255, 160, 220 },
	build = function(rng)
		local length = int(rng, 5, 7)
		local text = {}
		for i = 1, length do
			text[i] = pick(rng, QTEConfig.Pools.Wide)
		end
		return {
			prompt = "TYPE  THE  STREAM",
			sub = "Two mistakes allowed",
			params = {
				text = table.concat(text),
				reveal = true,
				allowBackspace = true,
				maxMisses = 2,
			},
		}
	end,
})

define({
	id = "MorseCode",
	label = "Morse Code",
	mode = "morse",
	category = "Memory",
	weight = 3,
	baseTime = 4.0,
	caps = { Key = true },
	accent = { 255, 200, 50 },
	build = function(rng)
		local letter = pick(rng, QTEConfig.Morse.Letters)
		local key = pick(rng, QTEConfig.Pools.Core)
		return {
			prompt = "SEND  " .. letter.char .. "  IN  MORSE  [ " .. key .. " ]",
			sub = ". = tap   — = hold (about 0.4s)",
			params = {
				key = key,
				letter = letter.char,
				pattern = letter.pattern,
			},
		}
	end,
})

-- ── Family F: Cognition — the answer has to be worked out ───────────────────
define({
	id = "MathCalc",
	label = "Calculate",
	mode = "type",
	category = "Cognition",
	weight = 8,
	baseTime = 4.2,
	caps = { Key = true },
	accent = { 255, 220, 60 },
	build = function(rng)
		local roll = int(rng, 1, 3)
		local a, b, value, symbol
		if roll == 1 then
			a = int(rng, QTEConfig.MathCalc.Add.min, QTEConfig.MathCalc.Add.max)
			b = int(rng, QTEConfig.MathCalc.Add.min, QTEConfig.MathCalc.Add.max)
			value = a + b
			symbol = "+"
		elseif roll == 2 then
			a = int(rng, QTEConfig.MathCalc.Sub.min, QTEConfig.MathCalc.Sub.max)
			b = int(rng, 2, a - 2)
			value = a - b
			symbol = "−"
		else
			a = int(rng, QTEConfig.MathCalc.Mul.min, QTEConfig.MathCalc.Mul.max)
			b = int(rng, 2, 9)
			value = a * b
			symbol = "×"
		end
		return {
			prompt = "WORK  IT  OUT",
			sub = a .. " " .. symbol .. " " .. b .. " = ?   (type the answer)",
			params = {
				text = tostring(value),
				reveal = false,
				source = "arithmetic",
				allowBackspace = true,
				maxMisses = 0,
			},
		}
	end,
})

define({
	id = "TrueFalse",
	label = "True / False",
	mode = "classify",
	category = "Cognition",
	weight = 8,
	baseTime = 3.6,
	caps = { Key = true },
	accent = { 80, 200, 255 },
	build = function(rng)
		local items = {}
		for i = 1, 8 do
			local statement = arithmeticStatement(rng)
			items[i] = {
				text = statement.text,
				token = statement.truthful and "E" or "Q",
			}
		end
		local needed = int(rng, 3, 4)
		return {
			prompt = "TRUE  OR  FALSE  ?",
			sub = "E = true    Q = false    (" .. tostring(needed) .. " correct)",
			params = {
				items = items,
				keys = { "E", "Q" },
				needed = needed,
				maxMisses = 0,
			},
		}
	end,
})

define({
	id = "EvenOdd",
	label = "Even / Odd",
	mode = "classify",
	category = "Cognition",
	weight = 7,
	baseTime = 3.6,
	caps = { Key = true },
	accent = { 100, 200, 255 },
	build = function(rng)
		local lo = QTEConfig.Perception.EvenOddRange[1]
		local hi = QTEConfig.Perception.EvenOddRange[2]
		local items = {}
		for i = 1, 6 do
			local value = int(rng, lo, hi)
			items[i] = {
				text = tostring(value),
				token = (value % 2 == 0) and "E" or "Q",
			}
		end
		local needed = QTEConfig.Perception.EvenOddNeeded
		return {
			prompt = "EVEN  OR  ODD  ?",
			sub = "E = even    Q = odd    (" .. tostring(needed) .. " correct)",
			params = {
				items = items,
				keys = { "E", "Q" },
				needed = needed,
				maxMisses = 0,
			},
		}
	end,
})

define({
	id = "NumberOrder",
	label = "Number Order",
	mode = "sort",
	category = "Cognition",
	weight = 6,
	baseTime = 3.8,
	caps = { Key = true },
	accent = { 100, 255, 200 },
	build = function(rng)
		local count = int(rng, QTEConfig.Perception.NumberOrder.count[1], QTEConfig.Perception.NumberOrder.count[2])
		local items = unique(rng, QTEConfig.Pools.Digits, count)
		return {
			prompt = "PRESS  LOW  →  HIGH",
			sub = "In ascending order",
			params = { items = items, kind = "numeric" },
		}
	end,
})

define({
	id = "SortPress",
	label = "Alphabetise",
	mode = "sort",
	category = "Cognition",
	weight = 5,
	baseTime = 3.6,
	caps = { Key = true },
	accent = { 180, 255, 100 },
	build = function(rng)
		local count = QTEConfig.Perception.SortPress.count
		local items = unique(rng, QTEConfig.SortAlphabet, count)
		return {
			prompt = "PRESS  A  →  Z",
			params = { items = items },
		}
	end,
})

define({
	id = "StroopWord",
	label = "Stroop Word",
	mode = "classify",
	category = "Cognition",
	weight = 7,
	baseTime = 3.6,
	caps = { Key = true },
	accent = { 230, 120, 255 },
	build = function(rng)
		local needed = int(rng, 3, 4)
		local items = stroopItems(rng, 6, false)
		local tokens = {}
		for i = 1, #QTEConfig.Colours do
			tokens[i] = QTEConfig.Colours[i].token
		end
		return {
			prompt = "PRESS  THE  KEY  FOR  THE  WORD",
			sub = "Ignore the ink colour    R / G / B / T",
			params = {
				items = items,
				keys = tokens,
				needed = needed,
				maxMisses = 0,
			},
		}
	end,
})

define({
	id = "StroopInk",
	label = "Stroop Ink",
	mode = "classify",
	category = "Cognition",
	weight = 6,
	baseTime = 3.6,
	caps = { Key = true },
	accent = { 200, 100, 255 },
	build = function(rng)
		local needed = int(rng, 3, 4)
		local items = stroopItems(rng, 6, true)
		local tokens = {}
		for i = 1, #QTEConfig.Colours do
			tokens[i] = QTEConfig.Colours[i].token
		end
		return {
			prompt = "PRESS  THE  KEY  FOR  THE  INK",
			sub = "Ignore what the word says    R / G / B / T",
			params = {
				items = items,
				keys = tokens,
				needed = needed,
				maxMisses = 0,
			},
		}
	end,
})

define({
	id = "BiggerOf",
	label = "Bigger",
	mode = "classify",
	category = "Cognition",
	weight = 5,
	baseTime = 3.4,
	caps = { Key = true },
	accent = { 255, 200, 120 },
	build = function(rng)
		local items = {}
		for i = 1, 6 do
			local a = int(rng, 1, 9)
			local b = int(rng, 1, 9)
			while b == a do
				b = int(rng, 1, 9)
			end
			local bigger = math.max(a, b)
			items[i] = {
				text = tostring(a) .. "   or   " .. tostring(b),
				token = digitToken(tostring(bigger)),
			}
		end
		return {
			prompt = "PRESS  THE  BIGGER  NUMBER",
			params = {
				items = items,
				keys = QTEConfig.Pools.Digits,
				needed = int(rng, 3, 4),
				maxMisses = 0,
			},
		}
	end,
})

define({
	id = "NextInSeries",
	label = "Next In Series",
	mode = "classify",
	category = "Cognition",
	weight = 4,
	baseTime = 3.8,
	caps = { Key = true },
	accent = { 255, 230, 90 },
	build = function(rng)
		local items = {}
		for i = 1, 5 do
			items[i] = seriesItem(rng)
		end
		return {
			prompt = "WHAT  COMES  NEXT  ?",
			params = {
				items = items,
				keys = QTEConfig.Pools.Digits,
				needed = int(rng, 2, 3),
				maxMisses = 0,
			},
		}
	end,
})

define({
	id = "Tally",
	label = "Tally",
	mode = "classify",
	category = "Cognition",
	weight = 5,
	baseTime = 3.6,
	caps = { Key = true },
	accent = { 160, 255, 220 },
	build = function(rng)
		local items = {}
		for i = 1, 5 do
			items[i] = tallyItem(rng)
		end
		return {
			prompt = "COUNT  THE  MATCHES",
			params = {
				items = items,
				keys = QTEConfig.Pools.Digits,
				needed = int(rng, 3, 4),
				maxMisses = 0,
			},
		}
	end,
})

define({
	id = "Mirror",
	label = "Mirror",
	mode = "symbol",
	category = "Cognition",
	weight = 6,
	baseTime = 3.0,
	caps = { Key = true },
	accent = { 220, 0, 220 },
	build = function(rng)
		local items = symbolItems(rng, int(rng, 3, 5), DIR_OPPOSITE, DIR_SYMBOL)
		return {
			prompt = "PRESS  THE  OPPOSITE  DIRECTION",
			sub = "W A S D",
			params = { items = items },
		}
	end,
})

define({
	id = "Opposite",
	label = "Opposite",
	mode = "symbol",
	category = "Cognition",
	weight = 6,
	baseTime = 3.0,
	caps = { Key = true },
	accent = { 255, 100, 180 },
	build = function(rng)
		local items = symbolItems(rng, int(rng, 3, 5), LETTER_OPPOSITE, nil)
		return {
			prompt = "PRESS  THE  OPPOSITE  KEY",
			sub = "Q ↔ E    R ↔ F",
			params = { items = items },
		}
	end,
})

-- ── Family G: Interoception — your own body and the camera are the input ────
define({
	id = "BalanceCorrection",
	label = "Balance",
	mode = "balance",
	category = "Interoception",
	weight = 6,
	baseTime = 4.0,
	caps = { Key = true },
	accent = { 0, 180, 255 },
	build = function(rng)
		local seconds = int(rng, 30, 45) / 10
		return {
			prompt = "KEEP  YOUR  BALANCE",
			sub = "A / D against the drift",
			params = {
				keys = { "A", "D" },
				seconds = seconds,
				push = 0.34,
				drift = 1,
				driftRate = int(rng, 35, 55) / 100,
				freqA = int(rng, 60, 110) / 100,
				freqB = int(rng, 140, 220) / 100,
				phase = int(rng, 0, 60) / 10,
				bias = 0,
			},
		}
	end,
})

define({
	id = "MomentumStabilizer",
	label = "Stabilise",
	mode = "counter",
	category = "Interoception",
	weight = 6,
	baseTime = 2.4,
	caps = { Key = true, Motion = true },
	accent = { 255, 80, 0 },
	build = function(rng)
		return {
			prompt = "COUNTER  YOUR  MOMENTUM",
			sub = "Press against the way you are moving",
			params = {
				xKey = "A",
				xKeyFlip = "D",
				zKey = "W",
				zKeyFlip = "S",
				braceKey = "Space",
				braceKeys = { "W", "A", "S", "D", "Space" },
				allKeys = { "W", "A", "S", "D" },
				deadzone = 1.5,
				strict = false,
			},
		}
	end,
})

define({
	id = "CameraAlignment",
	label = "Orient",
	mode = "align",
	category = "Interoception",
	weight = 4,
	baseTime = 3.4,
	caps = { Look = true },
	accent = { 100, 220, 255 },
	build = function(rng)
		local directions = {
			{ label = "NORTH  (Z−)", dir = { x = 0, y = 0, z = -1 } },
			{ label = "SOUTH  (Z+)", dir = { x = 0, y = 0, z = 1 } },
			{ label = "EAST  (X+)", dir = { x = 1, y = 0, z = 0 } },
			{ label = "WEST  (X−)", dir = { x = -1, y = 0, z = 0 } },
		}
		local target = pick(rng, directions)
		return {
			prompt = "FACE  " .. target.label,
			sub = "Turn the camera until it lines up",
			params = { dir = target.dir, tolerance = 0.9 },
		}
	end,
})

define({
	id = "FootstepSync",
	label = "Footstep Sync",
	mode = "timed",
	category = "Interoception",
	weight = 4,
	baseTime = 3.8,
	caps = { Key = true },
	accent = { 150, 255, 150 },
	build = function(rng)
		local key = pick(rng, QTEConfig.Pools.Core)
		return {
			prompt = "PRESS  ON  YOUR  FOOTSTEP  [ " .. key .. " ]",
			sub = "Match the beat of your own feet",
			params = {
				key = key,
				cueSource = "beat",
				beats = 3,
				window = 0.24,
				beatAssumed = 0.55,
				maxMisses = 1,
			},
		}
	end,
})

define({
	id = "NoPress",
	label = "No Press",
	mode = "idle",
	category = "Interoception",
	weight = 5,
	baseTime = 3.2,
	caps = {},
	accent = { 150, 255, 150 },
	build = function(rng)
		local seconds = int(rng, 20, 32) / 10
		return {
			prompt = "DO  NOT  MOVE  —  DO  NOT  PRESS",
			sub = "Anything will give you away",
			params = { seconds = seconds },
		}
	end,
})

define({
	id = "Sequence",
	label = "Sequence",
	mode = "sequence",
	category = "Reflex",
	weight = 8,
	baseTime = 3.6,
	caps = { Key = true },
	accent = { 255, 210, 90 },
	build = function(rng)
		local keys = sequenceOf(rng, QTEConfig.Pools.Core, int(rng, 3, 4))
		return {
			prompt = "PRESS  IN  ORDER",
			sub = table.concat(keys, "  ->  "),
			params = { keys = keys, order = "forward", maxMisses = 1 },
		}
	end,
})

define({
	id = "CountFlash",
	label = "Count Flash",
	mode = "count",
	category = "Memory",
	weight = 5,
	baseTime = 3.4,
	caps = { Key = true },
	accent = { 255, 150, 220 },
	build = function(rng)
		local count = int(rng, 3, 6)
		local spots = {}
		for i = 1, count do
			spots[#spots + 1] = { x = int(rng, 18, 82) / 100, y = int(rng, 20, 78) / 100 }
		end
		return {
			prompt = "COUNT  THE  FLASHES",
			sub = "Type how many you saw",
			params = {
				count = count,
				spots = spots,
				spotRadius = 0.045,
				flashSeconds = 0.9 + 0.18 * count,
			},
		}
	end,
})

define({
	id = "HoldBreath",
	label = "Hold Breath",
	mode = "idle",
	category = "Interoception",
	weight = 4,
	baseTime = 3.6,
	caps = {},
	accent = { 120, 200, 255 },
	build = function(rng)
		local seconds = int(rng, 24, 36) / 10
		return {
			prompt = "HOLD  YOUR  BREATH",
			sub = "Still and silent",
			params = { seconds = seconds },
		}
	end,
})

-- ── API ──────────────────────────────────────────────────────────────────────
function QTECatalog.get(id: string): any
	return QTECatalog.byId[id]
end

function QTECatalog.ids(): any
	local out = {}
	for i = 1, #QTECatalog.list do
		out[i] = QTECatalog.list[i].id
	end
	return out
end

-- validate(engine) -> problems
-- Called by the director at construction and by the smoke test. It is the reason a
-- typo in a mode name or an unknown category fails loudly at boot instead of
-- silently removing a QTE from the pool (or worse, running a mode nobody tested).
function QTECatalog.validate(engine: any): any
	local problems = {}
	local seenLabel = {}
	for i = 1, #QTECatalog.list do
		local def = QTECatalog.list[i]
		if engine.MODES[def.mode] == nil then
			problems[#problems + 1] = def.id .. ": unknown mode '" .. tostring(def.mode) .. "'"
		end
		if seenLabel[def.label] then
			problems[#problems + 1] = def.id .. ": duplicate label '" .. def.label .. "'"
		end
		seenLabel[def.label] = true
		if def.category == nil then
			problems[#problems + 1] = def.id .. ": missing category"
		end
		if def.caps == nil then
			problems[#problems + 1] = def.id .. ": missing caps"
		end
	end
	return problems
end

return QTECatalog
