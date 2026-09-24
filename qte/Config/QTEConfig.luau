--!strict
-- QTEConfig.luau
-- Location: ReplicatedStorage > QTE > Config > QTEConfig  (ModuleScript)
-- Purpose:  Data for the quick-time-event system (README.md is the manual): the human
--           input model the feasibility floor is derived from, difficulty presets,
--           dynamic time pressure, the grading table, device capability sets, the
--           abstract-input -> KeyCode maps and every word / question / symbol bank
--           the catalogue draws from.
--
--           PURE DATA. No services, no Instances, no yields, no functions: a
--           generator belongs in Lib (that is what makes Lib/QTECatalog testable in
--           the headless harness, which cannot construct a Color3 or a Vector2).
--           Colours are {r, g, b} integer triples and directions are plain
--           {x, y, z} numbers for exactly that reason - the client shell owns the
--           only conversion to Color3/Vector3 in the system.
--
-- Requires: (none)
-- Used by:  Lib/QTECatalog, Lib/QTEDirector, Client/QTEStruggle,
--           tools/vitriol/tests-qte.luau

local QTEConfig = {}

QTEConfig.Version = 6

-- ── The human model ──────────────────────────────────────────────────────────
-- Every time limit in the system is derived from this table rather than typed in
-- per QTE. A QTE declares HOW MANY inputs it needs and HOW LONG the player must
-- read; QTEEngine.cost() converts that into seconds, and QTEDirector refuses to
-- ship a limit below it at any difficulty (README.md §4). Numbers are deliberately
-- conservative: they describe a competent player on a good device, not a pro.
QTEConfig.Human = {
	ReactionSeconds = 0.22, -- see it, decide, begin moving
	KeySeconds = 0.20, -- one discrete key/click (5 inputs per second sustained)
	PointerScreensPerSecond = 1.6, -- deliberate pointer travel, screen-widths/s
	ReadSeconds = 0.55, -- read a short instruction
	ReadLongSeconds = 0.95, -- read an equation or a multi-line instruction
	ThinkPerDigit = 0.22, -- mental arithmetic, per answer digit
	MemoryFlashSeconds = 0.42, -- per item shown in a memorise phase (display only)
	MorseLongSeconds = 0.35, -- press longer than this to send a dash
	MorseShortSeconds = 0.12, -- the shortest press that still registers as a dot
	MorseGapSeconds = 0.15, -- the quiet between two symbols the game is willing to read
}

-- ── Limits ───────────────────────────────────────────────────────────────────
QTEConfig.Timing = {
	MinLimit = 0.9, -- hard floor for any shipped time limit
	MaxLimit = 6.5, -- hard ceiling (a QTE must never outstay its welcome)
	GraceSeconds = 0.12, -- input arriving this late still counts (frame jitter)
	FailureHoldSeconds = 0.5, -- how long a verdict stays on screen before cleanup
}

-- Difficulty presets. timeMult multiplies the QTE's base time; lower = harder.
QTEConfig.Presets = {
	Easy = { timeMult = 1.5, weightBias = 0.85 },
	Normal = { timeMult = 1.0, weightBias = 1.0 },
	Hard = { timeMult = 0.75, weightBias = 1.1 },
	Insane = { timeMult = 0.55, weightBias = 1.15 },
}
QTEConfig.DefaultPreset = "Normal"

-- Adaptive difficulty: the system tightens as the player wins and snaps back on a
-- loss, so a good player keeps being challenged and a struggling one is not
-- buried. This is a MULTIPLIER, so Floor is the hardest the system may become.
QTEConfig.Adaptive = {
	Start = 1.0,
	StepPerWin = 0.06,
	Floor = 0.6,
	OnLoss = 1.0,
}

-- Dynamic pressure: less time when hurt and when the player has already won a lot
-- this session. Both terms are clamped, so the worst case is the product of the
-- two floors - and QTEDirector still cannot go below the QTE's feasibility floor.
QTEConfig.Pressure = {
	HealthFloor = 0.7, -- multiplier at zero health
	HealthWeight = 0.3, -- 0.7 + 0.3 * healthFraction
	WinPenalty = 0.015, -- time lost per win
	WinCap = 0.55, -- multiplier floor from wins alone
	WinsForCap = 30, -- wins needed to reach WinCap
}

-- Appearance-weighted picking: a QTE that has already run keeps its weight divided
-- by (1 + appearances * AppearancePenalty), so the pool stays fresh.
QTEConfig.Freshness = { AppearancePenalty = 0.45 }

-- Rate limiting: back-to-back QTEs with no gap read as a bug, not a challenge.
QTEConfig.Pacing = {
	CooldownSeconds = 0.4, -- minimum gap between two runs
	SettleSeconds = 0.25, -- prompt visible before input is accepted
	MaxPerMinute = 40, -- client-side rate limit (a stuck caller cannot spam)
	MaxWatchdogSeconds = 9.0, -- absolute ceiling; a run past this is force-failed
}

-- ── Grading ──────────────────────────────────────────────────────────────────
-- score is the fraction of the requirement met at resolution time. The grade is
-- what the game reacts to - GoreConfig.Escape consumes EscapeWeight, not the raw
-- score, so tuning the feel never requires touching the catalogue.
QTEConfig.Grades = {
	{ name = "perfect", minScore = 1.0, escapeWeight = 1.0, damage = 0, heal = 2 },
	{ name = "clean", minScore = 0.8, escapeWeight = 0.7, damage = 0, heal = 1 },
	{ name = "sloppy", minScore = 0.45, escapeWeight = 0.35, damage = 1, heal = 0 },
	{ name = "fail", minScore = 0.0, escapeWeight = 0.0, damage = 3, heal = 0 },
}

-- ── Capabilities ─────────────────────────────────────────────────────────────
-- A QTE declares which of these it needs; the director only serves QTEs the device
-- can actually answer. This is what stops a phone player being asked to "press Q"
-- (they cannot, and the v5 manager would have failed them for it).
QTEConfig.Capability = {
	Key = "Key", -- a discrete button: keyboard key, gamepad button, on-screen button
	Pointer = "Pointer", -- absolute/relative pointer motion (mouse, stick cursor, finger)
	Click = "Click", -- a confirm press at the pointer's location
	Look = "Look", -- camera yaw control (mouse look or right stick)
	Motion = "Motion", -- the character is moving; velocity-derived QTEs need this
}

QTEConfig.Devices = {
	KeyboardMouse = { Key = true, Pointer = true, Click = true, Look = true, Motion = true },
	Gamepad = { Key = true, Look = true, Motion = true },
	Touch = { Pointer = true, Click = true, Motion = true },
}

-- Abstract input tokens -> Enum.KeyCode names, per device. The engine and the
-- catalogue only ever speak the TOKEN ("E", "Space", "Up"); the shell resolves it
-- through here, which is why one definition works on every platform.
QTEConfig.InputMap = {
	Keyboard = {
		Space = "Space",
		Backspace = "Backspace",
		Return = "Return",
		Up = "Up",
		Down = "Down",
		Left = "Left",
		Right = "Right",
		A = "A", B = "B", C = "C", D = "D", E = "E", F = "F", G = "G", H = "H",
		I = "I", J = "J", K = "K", L = "L", M = "M", N = "N", O = "O", P = "P",
		Q = "Q", R = "R", S = "S", T = "T", U = "U", V = "V", W = "W", X = "X",
		Y = "Y", Z = "Z",
		Zero = "Zero", One = "One", Two = "Two", Three = "Three", Four = "Four",
		Five = "Five", Six = "Six", Seven = "Seven", Eight = "Eight", Nine = "Nine",
		KeypadZero = "KeypadZero", KeypadOne = "KeypadOne", KeypadTwo = "KeypadTwo",
		KeypadThree = "KeypadThree", KeypadFour = "KeypadFour", KeypadFive = "KeypadFive",
		KeypadSix = "KeypadSix", KeypadSeven = "KeypadSeven", KeypadEight = "KeypadEight",
		KeypadNine = "KeypadNine",
	},
	Gamepad = {
		Up = "DPadUp", Down = "DPadDown", Left = "DPadLeft", Right = "DPadRight",
		Q = "ButtonX", E = "ButtonY", R = "ButtonB", F = "ButtonA",
		Space = "ButtonA", A = "ButtonX", S = "ButtonB", D = "ButtonY",
		One = "DPadUp", Two = "DPadRight", Three = "DPadDown", Four = "DPadLeft",
	},
}

-- Digit tokens may arrive as the top row or the numpad; both mean the same digit.
-- Raw characters are accepted too, so a shell that sends "4" (or a test that does)
-- is not silently ignored - which is exactly how the v5 dial pad shipped broken.
QTEConfig.DigitAliases = {
	Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
	Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
	KeypadZero = "0", KeypadOne = "1", KeypadTwo = "2", KeypadThree = "3",
	KeypadFour = "4", KeypadFive = "5", KeypadSix = "6", KeypadSeven = "7",
	KeypadEight = "8", KeypadNine = "9",
	["0"] = "0", ["1"] = "1", ["2"] = "2", ["3"] = "3", ["4"] = "4",
	["5"] = "5", ["6"] = "6", ["7"] = "7", ["8"] = "8", ["9"] = "9",
}

-- Character -> token, for the modes that SHOW an answer ("47") and need to accept
-- the keys that spell it. Letters map to themselves.
QTEConfig.DigitTokens = {
	["0"] = "Zero", ["1"] = "One", ["2"] = "Two", ["3"] = "Three", ["4"] = "Four",
	["5"] = "Five", ["6"] = "Six", ["7"] = "Seven", ["8"] = "Eight", ["9"] = "Nine",
}

-- ── Input pools ──────────────────────────────────────────────────────────────
QTEConfig.Pools = {
	-- Letter tokens that all three devices can answer through InputMap.
	Core = { "E", "R", "F", "Q" },
	Wide = { "E", "R", "F", "Q", "N", "B", "H", "G", "T" },
	Direction = { "W", "A", "S", "D" },
	Adjacent = { "Q", "E", "R", "F" },
	Vertical = { "Q", "E" },
	Horizontal = { "R", "F" },
	-- Digit TOKENS, matching InputMap: the engine never speaks raw characters, so
	-- "press 4" is the token Four and a shell can resolve it to Four or KeypadFour.
	Digits = { "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine" },
}

-- Pairs used by alternation / dual-input QTEs (each pair shares a hand).
QTEConfig.Pairs = {
	{ "Q", "E" },
	{ "Q", "R" },
	{ "Q", "F" },
	{ "E", "R" },
	{ "E", "F" },
	{ "R", "F" },
	{ "A", "D" },
}

-- ── Word bank ────────────────────────────────────────────────────────────────
-- Spelling matters: every letter must exist as a token in InputMap.Keyboard or the
-- QTE is unanswerable. The test suite asserts that for every word (README.md §11).
QTEConfig.Words = {
	Short = {
		"FIRE", "JUMP", "RUN", "STOP", "HELP", "DODGE", "RUSH", "SAFE",
		"BRACE", "EVADE", "BLOCK", "SHIFT", "GUARD", "PRESS", "FLASH", "SMASH",
		"GRASP", "PARRY", "RALLY", "BURST", "BLITZ", "CRISP", "FROST", "SWIFT",
	},
	Medium = {
		"GRAVEL", "CLINCH", "FLINCH", "LAUNCH", "STAPLE", "MIRROR", "HAZARD",
		"JUNGLE", "COMBAT", "DANGER", "BATTLE", "FORAGE", "RESCUE", "SPRINT",
	},
	Hard = {
		"RHYTHM", "NYMPH", "GLYPH", "CRYPT", "TRYST", "LYMPH", "PYGMY",
		"FJORD", "SPHINX", "PHLEGM", "SQUAWK", "PSYCH", "WRATH", "GNASH",
		"KNEEL", "WRECK", "THRESH", "SCRUFF", "STENCH", "CLENCH", "DRENCH",
		"QUENCH", "TWITCH", "GLITCH", "SNATCH", "CLUTCH", "SKETCH", "BLANCH",
		"NOTCH", "BOTCH", "TRENCH", "GRUDGE", "SLUDGE", "PLEDGE", "PLUNGE",
	},
	VeryHard = {
		"STRENGTH", "ABSTRACT", "INSTINCT", "DISTINCT", "GLIMPSED",
		"SCRAWLED", "STRAIGHT", "DRIFTWOOD", "TWILIGHT", "OUTBREAK",
		"THRESHOLD", "WRISTBAND", "TWITCHING", "CRUMBLING", "STRETCHING",
	},
}

-- ── Arithmetic bank ──────────────────────────────────────────────────────────
-- Structured, not pre-rendered: a claim of the form "2 + 2 = 4" is stored as its
-- operands and the RESULT THE PLAYER IS SHOWN, and tests.luau recomputes every entry
-- and asserts the bank's truth flag matches the arithmetic. A hand-typed question
-- bank is exactly the kind of content that silently rots.
QTEConfig.TrueFalse = {
	Add = { min = 2, max = 60 },
	Sub = { min = 10, max = 90 },
	Mul = { min = 2, max = 12 },
	Square = { min = 2, max = 12 },
	Root = { min = 2, max = 12 },
	-- A false statement is generated by offsetting the shown result by one of these.
	FalseOffsets = { -2, -1, 1, 2 },
}

QTEConfig.MathCalc = {
	-- Op weights: addition is the bread and butter, multiplication the pressure.
	Add = { weight = 3, min = 4, max = 45 },
	Sub = { weight = 3, min = 10, max = 60 },
	Mul = { weight = 2, min = 2, max = 12 },
}

-- ── Symbol banks ─────────────────────────────────────────────────────────────
QTEConfig.SortAlphabet = { "A", "B", "C", "D", "E", "F", "G", "H", "J", "K", "L", "M", "N", "P", "R", "S", "T", "W" }

QTEConfig.Morse = {
	-- Real ITU letters, so the QTE teaches something rather than inventing a code.
	Letters = {
		{ char = "E", pattern = "." },
		{ char = "T", pattern = "-" },
		{ char = "A", pattern = ".-" },
		{ char = "N", pattern = "-." },
		{ char = "I", pattern = ".." },
		{ char = "M", pattern = "--" },
		{ char = "S", pattern = "..." },
		{ char = "R", pattern = ".-." },
		{ char = "U", pattern = "..-" },
		{ char = "K", pattern = "-.-" },
		{ char = "H", pattern = "...." },
		{ char = "F", pattern = "..-." },
	},
}

QTEConfig.Colours = {
	{ name = "RED", token = "R", rgb = { 255, 60, 60 } },
	{ name = "GREEN", token = "G", rgb = { 60, 220, 90 } },
	{ name = "BLUE", token = "B", rgb = { 80, 130, 255 } },
	{ name = "GOLD", token = "T", rgb = { 255, 220, 0 } },
}

-- ── Perception banks ─────────────────────────────────────────────────────────
QTEConfig.Perception = {
	EvenOddRange = { 10, 99 }, -- two digits only: the parity must be the only read
	EvenOddNeeded = 3,
	CountFlash = { min = 3, max = 9, spread = { 0.12, 0.8 } },
	MemoryGrid = { size = 3, lit = { 3, 4 } },
	NumberOrder = { count = { 4, 6 } },
	SortPress = { count = 4 },
	-- Arithmetic progressions for the "what comes next" QTE.
	Series = { steps = { 2, 3, 4, 5, 6, 7, 8, 9, 11 }, length = { 4, 4 } },
	BiggerOf = { min = 1, max = 12 },
}

-- ── Feedback lines ───────────────────────────────────────────────────────────
-- One place for the words the player reads, so tone stays consistent (and a future
-- localisation pass has a single list to walk).
QTEConfig.Copy = {
	Miss = { "MISSED", "TOO SLOW", "WRONG", "FAILED" },
	Perfect = { "PERFECT", "FLAWLESS", "CLEAN", "TIGHT" },
	Clean = { "GOOD", "HANDLED", "STEADY" },
	Sloppy = { "BARELY", "SLOPPY", "MESSY" },
	Late = { "TOO SLOW" },
	FalseStart = { "FALSE START", "TOO EARLY" },
	WrongKey = { "WRONG INPUT", "NOT THAT ONE" },
}

-- ── Diagnostics ──────────────────────────────────────────────────────────────
QTEConfig.Diagnostics = { Prefix = "[vitriol.qte]", Enabled = false }

return QTEConfig
