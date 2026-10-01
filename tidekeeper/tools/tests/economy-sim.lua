-- economy-sim.lua
--
-- Measures the COIN CURVE of an average player across many seeds, so that
-- tier upgrade costs can be chosen from data instead of invented.
--
-- WHY THIS EXISTS
-- ---------------
-- doc 06 section 7 states pacing targets -- tier 2 by day 3, tier 3 by day
-- 16, tier 4 by day 52 -- and marks them "to be validated against real
-- data". Iteration 7 found there was no data and, worse, no mechanism: a
-- post's tier is set to 1 when it is created and NOTHING in the game ever
-- changes it. Every tier-gated system (24 shelves at tier 4, the four
-- currents behind CURRENT_MIN_TIER, PASSIVE_CAP_BY_TIER, the 6/10/16/24
-- order-rule limits) was therefore unreachable.
--
-- Before inventing three numbers, measure what a player actually earns.
--
-- THE PLAYER MODEL, STATED PLAINLY
-- --------------------------------
-- This is a MODEL, not a player. It assumes a diligent-but-not-optimal
-- player who, per session: restocks two finds and prices them at base
-- value, then logs off and lets the tide run. It does not haggle, does not
-- write standing orders, and does not chase the Almanac. Real players will
-- spread either side of it. Treating its output as truth would be the
-- "simulation says so" trap; it is a floor to calibrate against, and the
-- numbers it produces are reported with spread, never as a single value.
--
-- Run: node tidekeeper/tools/tidekeeper-session-test.js --tests tools/tests/economy-sim.lua

local Prelude = TidekeeperRequire("SessionPrelude")
local newServer = Prelude.newServer
local settle = Prelude.settle

local Post = TidekeeperRequire("Post")
local FindsConfig = TidekeeperRequire("FindsConfig")

TESTS = { passed = 0, failed = 0, failures = {} }
REPORT = {}

local function ok(name, cond)
	if cond then
		TESTS.passed = TESTS.passed + 1
	else
		TESTS.failed = TESTS.failed + 1
		TESTS.failures[#TESTS.failures + 1] = name
		print("FAIL  " .. name)
	end
end

-- Sample days. These are doc 06's milestones plus a few in between so the
-- shape of the curve is visible, not just three points on it.
local SAMPLE_DAYS = { 1, 3, 7, 16, 30, 52, 70 }
local SEEDS = 12
-- 70, not 52: the tier-4 target IS day 52, so a 52-day horizon can only
-- ever report "some seeds did not get there" and never a median. Measure
-- past the target you are calibrating against.
local DAYS = 70
local SESSIONS_PER_DAY = 2 -- doc 06 says 2.4; 2 is the conservative floor

-- coin[dayIndex] = { per-seed values }
local coin = {}
for i = 1, #SAMPLE_DAYS do
	coin[i] = {}
end

-- reachedDay[tier] = { day each seed first reached that tier }
local reachedDay = { [2] = {}, [3] = {}, [4] = {} }
local reachedCount = {}

local function percentile(values, p)
	table.sort(values)
	local n = #values
	if n == 0 then
		return 0
	end
	local idx = math.floor((n - 1) * p) + 1
	if idx < 1 then
		idx = 1
	end
	if idx > n then
		idx = n
	end
	return values[idx]
end

for s = 1, SEEDS do
	local app, env = newServer({ seed = 1000 + s * 37 })
	local userId = 60000 + s
	env:addPlayer(userId)
	settle(app, env, 200)

	local sampleAt = 1
	local tierDay = {}
	local secondsPerSession = 86400 / SESSIONS_PER_DAY

	for day = 1, DAYS do
		for sess = 1, SESSIONS_PER_DAY do
			env:addPlayer(userId)
			settle(app, env, 30)
			local S = app.posts:get(userId)
			if S ~= nil then
				-- Comb: two finds, weighted toward the low zones because a
				-- tier-1 post cannot reach the outer bar. Deterministic in
				-- (seed, day, session) so a re-run reproduces exactly.
				local pick = 1 + ((s * 7919 + day * 131 + sess * 17) % 60)
				local pick2 = 1 + ((s * 104729 + day * 31 + sess * 7) % 60)
				Post.addStock(S, pick, 2)
				Post.addStock(S, pick2, 2)
				-- Shelve them at base value, which is the naive pricing a
				-- new player uses before they learn pricePressure.
				-- Shelf slots must stay DENSE (Post.setShelf enforces it as of
				-- iteration 7). Fill up to the tier limit, then cycle within
				-- what is already occupied, which is also what a real player
				-- does once the shelves are full.
				local limit = Post.maxShelves(S.tier)
				local function place(findId)
					local n = #S.shelves
					local slot
					if n < limit then
						slot = n + 1
					else
						slot = 1 + ((day + sess) % limit)
					end
					Post.setShelf(S, slot, findId, math.max(1, Post.baseValue(findId)))
				end
				place(pick)
				place(pick2)
				-- Buy the next tier as soon as it is affordable. A real
				-- player will not be this prompt, so this is the FAST end of
				-- the distribution; the slow end is someone who saves for
				-- decor instead, which is why the targets are a range.
				while Post.canPromote(S) do
					Post.promote(S)
					if tierDay[S.tier] == nil then
						tierDay[S.tier] = day
					end
				end
				app.posts:markDirty(userId)
			end
			env:removePlayer(userId)
			env:advance(secondsPerSession)
			settle(app, env, 30)
		end

		if sampleAt <= #SAMPLE_DAYS and day == SAMPLE_DAYS[sampleAt] then
			env:addPlayer(userId)
			settle(app, env, 60)
			local S = app.posts:get(userId)
			local c = 0
			if S ~= nil then
				-- Lifetime earnings, not the balance: the balance is what is
				-- left after spending, and nothing spends yet. `coin` is the
				-- running total here, which is exactly what an upgrade cost
				-- is measured against.
				c = S.coin
			end
			coin[sampleAt][#coin[sampleAt] + 1] = c
			env:removePlayer(userId)
			sampleAt = sampleAt + 1
		end
	end
	for t = 2, 4 do
		if tierDay[t] ~= nil then
			reachedDay[t][#reachedDay[t] + 1] = tierDay[t]
		end
		reachedCount[t] = (reachedCount[t] or 0) + ((tierDay[t] ~= nil) and 1 or 0)
	end
end

print("")
print("--- coin accumulated by an average player (" .. SEEDS .. " seeds, " .. SESSIONS_PER_DAY .. " sessions/day) ---")
print(string.format("  %-6s %10s %10s %10s %10s", "day", "p10", "median", "p90", "min"))
local medians = {}
for i = 1, #SAMPLE_DAYS do
	local v = coin[i]
	local copy = {}
	for k = 1, #v do
		copy[k] = v[k]
	end
	local med = percentile(copy, 0.5)
	medians[SAMPLE_DAYS[i]] = med
	print(string.format(
		"  %-6d %10d %10d %10d %10d",
		SAMPLE_DAYS[i],
		percentile(copy, 0.10),
		med,
		percentile(copy, 0.90),
		percentile(copy, 0.0)
	))
end

print("")
print("--- day the post reached each tier (promotion bought as soon as affordable) ---")
print(string.format("  %-6s %8s %10s %8s %10s", "tier", "p10", "median", "p90", "seeds"))
local TARGET = { [2] = 3, [3] = 16, [4] = 52 }
for t = 2, 4 do
	local v = reachedDay[t]
	local copy = {}
	for k = 1, #v do
		copy[k] = v[k]
	end
	if #copy > 0 then
		print(string.format(
			"  %-6d %8d %10d %8d %10d   (doc 06 target: day %d)",
			t,
			percentile(copy, 0.10),
			percentile(copy, 0.5),
			percentile(copy, 0.90),
			#copy,
			TARGET[t]
		))
		REPORT["tier" .. t .. "Day"] = percentile(copy, 0.5)
	else
		print(string.format("  %-6d %8s %10s %8s %10d   (doc 06 target: day %d)", t, "-", "never", "-", 0, TARGET[t]))
		REPORT["tier" .. t .. "Day"] = 0
	end
end

REPORT.econSeeds = SEEDS
REPORT.econDay3 = medians[3] or 0
REPORT.econDay16 = medians[16] or 0
REPORT.econDay52 = medians[52] or 0

-- The economy must actually produce income, and it must keep producing it.
-- A curve that flattens is a game that stops paying, which is the failure
-- mode this whole exercise exists to detect.
ok("the economy pays something in the first three days", (medians[3] or 0) > 0)
ok("day 16 earns more than day 3", (medians[16] or 0) > (medians[3] or 0))
ok("day 52 earns more than day 16", (medians[52] or 0) > (medians[16] or 0))

print("")
print(string.format(
	"ECON median coin: day3=%d day16=%d day52=%d",
	medians[3] or 0,
	medians[16] or 0,
	medians[52] or 0
))
