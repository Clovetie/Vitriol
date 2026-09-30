--!nonstrict
-- ReplicatedStorage/Tidekeeper/Domain/Drifter (ModuleScript)
--
-- Layer L2: pure. No services, no Instances, no yields, no time reads.
--
-- The visitor record and everything that can be asked of it without touching
-- the post: which tides admit it, what it wants, how well a find suits it.
--
-- A Drifter is a SNAPSHOT OF A REAL PLAYER (doc 03). It is built on the server
-- when that player logs out, and it is read hours later by someone else. That
-- is why it is a plain table with integer fields and no behaviour: it has to
-- survive a round trip through a DataStore and a week of schema drift.

local DrifterConfig = require(script.Parent.Parent.Config.DrifterConfig)
local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local GameConfig = require(script.Parent.Parent.Config.GameConfig)
local MathExt = require(script.Parent.Parent.Lib.MathExt)
local Schema = require(script.Parent.Parent.Lib.Schema)
local DrifterCodec = require(script.Parent.Parent.Shared.DrifterCodec)

local Drifter = {}

local floor = math.floor

local CLASSES = DrifterConfig.CLASSES
local CLASS_TIDES = DrifterConfig.CLASS_TIDES
local AXES = DrifterConfig.TASTE_AXES

-- Column indices into a CLASSES row, named once so the rest of the file reads
-- like prose instead of like array arithmetic.
local COL_NAME = 1
local COL_ID = 2
local COL_MIN_TIER = 3
local COL_VALUE_PER_MILLE = 4
local COL_WEIGHT = 5
local COL_MAX_ITEMS = 6

-- class id (0..3) -> row index (1..4)
local ROW_BY_ID = {}
local ROW_BY_NAME = {}
-- class id -> { [tideStateName] = true }
local TIDE_SET = {}
for i = 1, #CLASSES do
	local row = CLASSES[i]
	ROW_BY_ID[row[COL_ID]] = i
	ROW_BY_NAME[row[COL_NAME]] = i
	local set = {}
	local names = CLASS_TIDES[i]
	for j = 1, #names do
		set[names[j]] = true
	end
	TIDE_SET[row[COL_ID]] = set
end

Drifter.SKIFF = 0
Drifter.LAUNCH = 1
Drifter.LUGGER = 2
Drifter.DEEPWATER = 3
Drifter.CLASS_COUNT = #CLASSES

function Drifter.className(class)
	local row = ROW_BY_ID[class]
	if row == nil then
		return "UNKNOWN"
	end
	return CLASSES[row][COL_NAME]
end

function Drifter.classFromName(name)
	local row = ROW_BY_NAME[name]
	if row == nil then
		return nil
	end
	return CLASSES[row][COL_ID]
end

function Drifter.classMinTier(class)
	local row = ROW_BY_ID[class]
	if row == nil then
		return GameConfig.MAX_TIER + 1
	end
	return CLASSES[row][COL_MIN_TIER]
end

function Drifter.classMaxItems(class)
	local row = ROW_BY_ID[class]
	if row == nil then
		return 0
	end
	return CLASSES[row][COL_MAX_ITEMS]
end

function Drifter.classWeight(class)
	local row = ROW_BY_ID[class]
	if row == nil then
		return 0
	end
	return CLASSES[row][COL_WEIGHT]
end

-- The class value multiplier, as an integer per-mille so budget maths stays in
-- the integers (doc 03 section 4: 1x / 2.2x / 5x / 14x).
function Drifter.classValuePerMille(class)
	local row = ROW_BY_ID[class]
	if row == nil then
		return 0
	end
	return CLASSES[row][COL_VALUE_PER_MILLE]
end

-- Stage 1 of Visit.resolve. `tideState` is a Tide.state() string; the tide
-- itself is never passed as a number, so there is no rounding to disagree on.
function Drifter.admitsTide(class, tideState)
	local set = TIDE_SET[class]
	if set == nil then
		return false
	end
	return set[tideState] == true
end

function Drifter.wantsFind(d, findId)
	local wants = d.wants
	if wants == nil then
		return false
	end
	for i = 1, #wants do
		if wants[i] == findId then
			return true
		end
	end
	return false
end

function Drifter.carries(d, findId)
	local cargo = d.cargo
	if cargo == nil then
		return false
	end
	for i = 1, #cargo do
		if cargo[i] == findId then
			return true
		end
	end
	return false
end

-- Affinity of a find's taste vector for this Drifter, in [-1, 1].
function Drifter.affinity(d, tasteVec)
	return MathExt.cosine(tasteVec, d.taste, AXES)
end

function Drifter.dearTaste(d)
	return d.taste[DrifterConfig.AXIS_DEAR]
end

-- What this Drifter will actually spend today. Budget on the record is the
-- baseline; Standing with the host raises it, because a regular trusts you.
function Drifter.effectiveBudget(d)
	local bonus = floor(d.standing / 256)
	if bonus > 100 then
		bonus = 100
	end
	return floor(d.budget * (100 + bonus) / 100)
end

-- Deterministic synthesis. Used for Seed Drifters and for Echoes (doc 03
-- section 7) and, heavily, by the harness -- a fixture generator that is part
-- of the shipped code cannot drift away from the shipped shape.
function Drifter.synthesize(rng, owner, epoch, current, tier)
	local weights = {}
	for i = 1, #CLASSES do
		if CLASSES[i][COL_MIN_TIER] <= tier then
			weights[i] = CLASSES[i][COL_WEIGHT]
		else
			weights[i] = 0
		end
	end
	local pickedRow = rng:weightedIndex(weights, #CLASSES)
	if pickedRow == 0 then
		pickedRow = 1
	end
	local row = CLASSES[pickedRow]
	local class = row[COL_ID]

	local taste = {}
	local bias = EconomyConfig.CURRENT_TASTE_BIAS[current + 1]
	for i = 1, AXES do
		local v = rng:range(DrifterConfig.TASTE_MIN, DrifterConfig.TASTE_MAX)
		taste[i] = MathExt.clampInt((v + bias[i]) / 2 + bias[i] / 2, DrifterConfig.TASTE_MIN, DrifterConfig.TASTE_MAX)
	end

	local bandRow = DrifterConfig.BUDGET_BANDS[pickedRow]
	local d = {
		v = 1,
		id = DrifterCodec.makeId(owner, epoch),
		owner = owner,
		epoch = epoch,
		current = current,
		class = class,
		tier = tier,
		standing = rng:range(0, 4000),
		renown = rng:range(0, 500),
		budget = rng:range(bandRow[1], bandRow[2]),
		taste = taste,
		wants = {},
		cargo = {},
		letterId = 0,
		beacons = rng:range(0, 3),
		look = rng:nextUInt(),
	}
	return d
end

local DRIFTER_SPEC = Schema.map({
	v = Schema.int(1, 255),
	id = Schema.int(0, 9007199254740992),
	owner = Schema.int(0, GameConfig.OWNER_ID_MAX),
	epoch = Schema.int(-2147483648, 2147483647),
	current = Schema.int(0, EconomyConfig.CURRENT_COUNT - 1),
	class = Schema.int(0, #CLASSES - 1),
	tier = Schema.int(1, GameConfig.MAX_TIER),
	standing = Schema.int(0, EconomyConfig.STANDING_MAX),
	renown = Schema.int(0, 65535),
	budget = Schema.int(0, 4294967295),
	taste = Schema.array(Schema.int(DrifterConfig.TASTE_MIN, DrifterConfig.TASTE_MAX), AXES, AXES),
	wants = Schema.array(Schema.int(1, 65535), 0, DrifterConfig.MAX_WANTS),
	cargo = Schema.array(Schema.int(1, 65535), 0, DrifterConfig.MAX_CARGO),
	letterId = Schema.int(0, 65535),
	beacons = Schema.int(0, DrifterConfig.MAX_BEACONS),
	look = Schema.int(0, 4294967295),
}, true)

Drifter.SPEC = DRIFTER_SPEC

-- Returns (true) or (false, message). Also checks the cross-field invariants
-- the schema cannot express.
function Drifter.validate(d)
	local ok, message = Schema.validate(d, DRIFTER_SPEC)
	if not ok then
		return false, message
	end
	if d.tier < Drifter.classMinTier(d.class) then
		return false, string.format("class %s requires tier %d, drifter is tier %d", Drifter.className(d.class), Drifter.classMinTier(d.class), d.tier)
	end
	if d.id ~= DrifterCodec.makeId(d.owner, d.epoch) then
		return false, "id does not match (owner, epoch)"
	end
	return true
end

return Drifter
