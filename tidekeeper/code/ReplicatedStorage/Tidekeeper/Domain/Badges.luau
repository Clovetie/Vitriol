--!strict
-- ReplicatedStorage/Tidekeeper/Domain/Badges (ModuleScript)
--
-- Awarding the 40 achievements in BadgesConfig. Iteration 7 wrote the data
-- and said awarding was iteration 8's job; this is that job.
--
-- Pure: no clock, no services, no yielding. `evaluate` takes the post state
-- and returns the ids that have just been earned, having set their bits. The
-- caller decides what to do about it (a Ledger line, a Roblox badge, a toast)
-- so that none of that policy leaks into the domain.
--
-- THE TWO RULES THAT SHAPE EVERYTHING HERE
-- ----------------------------------------
-- 1. A badge is never revoked (doc 06 section 2). Therefore a badge may only
--    read a quantity that CANNOT GO DOWN. Every stat below is either a
--    lifetime counter or a monotone property of the post (tier, shelves,
--    almanac entries). `S.coin` is deliberately NOT readable: a "fifty coin"
--    badge on a balance would un-earn itself the moment the player spent it.
-- 2. A badge tests one stat against one threshold, and nothing else. The
--    moment badges can express arbitrary conditions they become a second
--    progression system with its own balance and its own exploits.
--
-- DERIVED VS COUNTED
-- ------------------
-- Six of the twelve stats are DERIVED from state the post already keeps, so
-- they cost no bytes and can never drift out of sync with the thing they
-- describe. The other six had to be counted, and are persisted in
-- `S.stats` as of schema v3. When adding a stat, prefer derived: a counter
-- that is incremented in one place and read in another is exactly the shape
-- of bug the dead-write and orphan scans exist to catch.
--
-- Layer: Domain (pure).

local BadgesConfig = require(script.Parent.Parent.Config.BadgesConfig)
local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local Almanac = require(script.Parent.Almanac)
local Post = require(script.Parent.Post)

local Badges = {}

local BADGE_BYTES = 5
local BADGE_COUNT = #BadgesConfig.BADGES

Badges.BADGE_BYTES = BADGE_BYTES
Badges.BADGE_COUNT = BADGE_COUNT

-- Index into STAT_NAMES, resolved once rather than by string compare per
-- badge per evaluate.
local STAT = {}
for i = 1, #BadgesConfig.STAT_NAMES do
	STAT[BadgesConfig.STAT_NAMES[i]] = i
end
Badges.STAT = STAT

-- ------------------------------------------------------------- the bitmask

local function ensureMask(S)
	local mask = S.badges
	if mask == nil then
		mask = { 0, 0, 0, 0, 0 }
		S.badges = mask
	end
	for i = 1, BADGE_BYTES do
		if mask[i] == nil then
			mask[i] = 0
		end
	end
	return mask
end

-- Badge id 1 is byte 1 bit 0. Ids are persisted bit indices (BadgesConfig),
-- so this mapping is a format and must never change.
local function locate(id)
	local zero = id - 1
	return math.floor(zero / 8) + 1, 2 ^ (zero % 8)
end

function Badges.has(S, id)
	if type(id) ~= "number" or id < 1 or id > BADGE_COUNT then
		return false
	end
	local mask = S.badges
	if mask == nil then
		return false
	end
	local byte, bit = locate(id)
	local value = mask[byte] or 0
	return math.floor(value / bit) % 2 == 1
end

-- Returns true if this call is what earned it, false if it was already held.
function Badges.award(S, id)
	if type(id) ~= "number" or id < 1 or id > BADGE_COUNT then
		return false
	end
	if Badges.has(S, id) then
		return false
	end
	local mask = ensureMask(S)
	local byte, bit = locate(id)
	mask[byte] = (mask[byte] or 0) + bit
	return true
end

function Badges.count(S)
	local n = 0
	for id = 1, BADGE_COUNT do
		if Badges.has(S, id) then
			n = n + 1
		end
	end
	return n
end

-- ---------------------------------------------------------------- the stats

-- How many Currents this post's tier has unlocked. Derived, because the
-- unlock rule already lives in EconomyConfig and a second copy of it as a
-- counter would be free to disagree.
local function currentsUnlocked(S)
	local n = 0
	local minTier = EconomyConfig.CURRENT_MIN_TIER
	for i = 1, #minTier do
		if (S.tier or 1) >= minTier[i] then
			n = n + 1
		end
	end
	return n
end

local function bitsSet(value)
	local n = 0
	local v = math.floor(value or 0)
	while v > 0 do
		if v % 2 == 1 then
			n = n + 1
		end
		v = math.floor(v / 2)
	end
	return n
end

-- The twelve values BadgesConfig.STAT_NAMES names, in that order.
function Badges.statsOf(S)
	local st = S.stats or {}
	local out = {}
	out[STAT.visitorsServed] = st.served or 0
	out[STAT.coinEarnedLifetime] = st.coinEarned or 0
	out[STAT.shelvesUnlocked] = Post.maxShelves(S.tier or 1)
	out[STAT.tierReached] = S.tier or 1
	out[STAT.almanacEntries] = Almanac.count(S.almanac)
	out[STAT.lettersSent] = st.lettersSent or 0
	out[STAT.lettersReceived] = st.lettersReceived or 0
	out[STAT.giftsGiven] = st.giftsGiven or 0
	out[STAT.driftersDispatched] = st.driftersDispatched or 0
	out[STAT.currentsUnlocked] = currentsUnlocked(S)
	-- Stored as a mask so that seeing LOW twice is not seeing two states.
	out[STAT.tideStatesSeen] = bitsSet(st.tideStatesSeen)
	out[STAT.tidesElapsed] = st.tidesElapsed or 0
	return out
end

-- ------------------------------------------------------------- recording

-- Record that this post has now observed a given tide state. Idempotent, and
-- that is the point: the stat is "how many of the five have you seen", which
-- only a set can answer.
function Badges.noteTideState(S, code)
	if type(code) ~= "number" or code < 1 or code > 5 then
		return false
	end
	local st = S.stats
	if st == nil then
		return false
	end
	local bit = 2 ^ (code - 1)
	local seen = st.tideStatesSeen or 0
	if math.floor(seen / bit) % 2 == 1 then
		return false
	end
	st.tideStatesSeen = seen + bit
	return true
end

-- ------------------------------------------------------------- evaluation

-- One pass over the 40 rows. Returns the newly earned ids in ascending order,
-- which is also the order they were defined in, so a player who crosses three
-- thresholds at once is told about them in a stable sequence rather than
-- whatever order a hash table happened to produce.
function Badges.evaluate(S)
	ensureMask(S)
	local stats = Badges.statsOf(S)
	local earned = {}
	local n = 0
	local rows = BadgesConfig.BADGES
	for i = 1, #rows do
		local row = rows[i]
		local id, statIndex, threshold = row[1], row[4], row[5]
		if not Badges.has(S, id) then
			local value = stats[statIndex]
			if value ~= nil and value >= threshold then
				if Badges.award(S, id) then
					n = n + 1
					earned[n] = id
				end
			end
		end
	end
	return earned
end

return Badges
