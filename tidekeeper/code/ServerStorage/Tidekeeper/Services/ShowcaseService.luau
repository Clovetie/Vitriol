--!nonstrict
-- ServerStorage/Tidekeeper/Services/ShowcaseService (ModuleScript)
--
-- Layer L3. The weekly Showcase (doc 02 section 8, doc 03 section 10).
--
-- WHY THIS IS NOT A LEADERBOARD
-- -----------------------------
-- A global top-100 in a game about a small quiet island would be a design
-- error, not just a taste one. It makes one number the point, it is
-- unreachable for everyone who is not already at the top, and it rewards
-- time spent rather than a post worth visiting.
--
-- The Showcase instead sorts players into BUCKETS by tier and season, and
-- publishes a small rotating sample from each bucket. Consequences:
--
--   * everybody is near the top of some bucket, so the reward for a good
--     week is visible to a new player in their first week;
--   * the sample rotates, so being featured is a thing that HAPPENS TO YOU
--     rather than a thing you grind for;
--   * being featured raises your Drifter's reach in the exchange, which is
--     the reward that actually matters -- more real strangers, not a number.
--
-- Cost: `bumpShowcase` is one MemoryStore-free DataStore UpdateAsync per
-- player per WEEK, folded into the `io` slot. The read is one GetAsync per
-- server per week, cached. This is a rounding error against the quota, which
-- is the only reason it is affordable at all.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local Tide = require(Tidekeeper.Lib.Tide)
local Hash = require(Tidekeeper.Lib.Hash)

local ShowcaseService = {}
ShowcaseService.__index = ShowcaseService

-- 27 epochs is just under seven days (26 * 22357 = 6.99 days, the same
-- arithmetic as MAX_CATCHUP_EPOCHS), so a "week" is 27 epochs and a player
-- who plays once a week is never skipped.
local EPOCHS_PER_WEEK = 27
local SAMPLE_SIZE = 12
local REFRESH_SECONDS = 900

local function newStats()
	return { bumps = 0, bumpFailures = 0, refreshes = 0, refreshFailures = 0 }
end

function ShowcaseService.new(options)
	local opts = options or {}
	local self = setmetatable({}, ShowcaseService)
	self.data = opts.data
	self.clock = opts.clock or os.time
	self.logger = opts.logger
	self.stats = newStats()
	self.cache = nil
	self.cachedAt = 0
	self.queue = {}
	return self
end

function ShowcaseService:log(message)
	if self.logger ~= nil then
		self.logger("ShowcaseService", message)
	end
end

function ShowcaseService:weekNumber(now)
	return math.floor(Tide.epoch(now or self.clock()) / EPOCHS_PER_WEEK)
end

-- Buckets are (tier, season). Small, stable, and meaningful: you are
-- compared with posts at your own stage, in the same season's goods.
function ShowcaseService:bucketFor(S)
	return S.tier * 16 + (S.season % 16)
end

-- Queued at logout, written on the `io` slot, at most once per player per
-- week. Renown, not coin: what the Showcase notices is that people came back
-- to you, which is the thing the whole game is about.
function ShowcaseService:queueBump(userId, S)
	local week = self:weekNumber()
	local existing = self.queue[userId]
	if existing ~= nil and existing.week == week then
		if S.renown <= existing.renown then
			return false
		end
	end
	self.queue[userId] = { week = week, bucket = self:bucketFor(S), renown = S.renown }
	return true
end

-- One write per call. The queue is drained in ascending userId order so the
-- request sequence is reproducible in the harness.
function ShowcaseService:flush()
	local ids = {}
	local n = 0
	for userId in pairs(self.queue) do
		n = n + 1
		ids[n] = userId
	end
	if n == 0 then
		return false
	end
	table.sort(ids)
	local userId = ids[1]
	local job = self.queue[userId]
	self.queue[userId] = nil
	local ok = self.data:bumpShowcase(job.week, job.bucket, userId, job.renown)
	if ok then
		self.stats.bumps = self.stats.bumps + 1
	else
		self.stats.bumpFailures = self.stats.bumpFailures + 1
	end
	return ok
end

-- The read side. Cached per server for REFRESH_SECONDS; the Showcase is a
-- weekly thing and does not need to be live.
function ShowcaseService:current()
	local now = self.clock()
	if self.cache ~= nil and now - self.cachedAt < REFRESH_SECONDS then
		return self.cache
	end
	local ok, meta = self.data:loadMeta()
	self.stats.refreshes = self.stats.refreshes + 1
	if not ok or meta == nil then
		self.stats.refreshFailures = self.stats.refreshFailures + 1
		-- A missing Showcase is a missing decoration, never a blocked join.
		return self.cache or { week = self:weekNumber(now), entries = {} }
	end
	self.cache = meta
	self.cachedAt = now
	return meta
end

-- Deterministic rotating sample: the same week and bucket always yield the
-- same faces, so two servers show the same Showcase, and nobody can reroll
-- it by rejoining.
function ShowcaseService:sample(bucket, candidates)
	local week = self:weekNumber()
	local out = {}
	local n = #candidates
	if n == 0 then
		return out
	end
	local taken = {}
	local wanted = math.min(SAMPLE_SIZE, n)
	local i = 0
	local guard = 0
	while i < wanted and guard < n * 4 do
		guard = guard + 1
		local pick = Hash.reduce(Hash.mix(week, bucket, guard), n) + 1
		if not taken[pick] then
			taken[pick] = true
			i = i + 1
			out[i] = candidates[pick]
		end
	end
	return out
end

function ShowcaseService:forget(userId)
	self.queue[userId] = nil
end

function ShowcaseService:resetStats()
	self.stats = newStats()
end

return ShowcaseService
