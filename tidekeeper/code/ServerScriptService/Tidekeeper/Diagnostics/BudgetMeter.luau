--!nonstrict
-- ServerScriptService/Tidekeeper/Diagnostics/BudgetMeter (ModuleScript)
--
-- Watches the two quotas that can actually kill this game and says so, in
-- production, before they do.
--
-- THE NUMBERS, RE-VERIFIED 2026-10-01 (doc 10 section 6.2)
-- --------------------------------------------------------
-- DataStore, per server, per minute:
--     Read / Write / Remove   60 + numPlayers * 40
--     List                     5 + numPlayers * 2
-- DataStore, per experience, per minute (SHARED WITH OPEN CLOUD):
--     Read   300 + CCU * 40      Write  300 + CCU * 20
--     List   300 + CCU * 2       Remove 300 + CCU * 40
-- MemoryStore:
--     memory   64 KB + 1.2 KB * users      (universe-wide, hard)
--     requests 1000 + 120 * CCU per minute (universe-wide)
--
-- Two of those were WRONG in our own iteration-1 documentation -- doc 05
-- said MemoryStore scaled at 100 * CCU and that DataStore was a flat
-- ~60/min/server. Both are corrected, and this meter exists so the next
-- wrong number is caught by a running server rather than by a re-read of
-- the docs a year later.
--
-- `UpdateAsync` DECREMENTS BOTH the read and the write quota. Every one of
-- our writes is an UpdateAsync (we never blind-set), so the write budget is
-- the binding constraint and the read budget drains at the same rate.
--
-- THE CLAIM THIS MEASURES: five platform requests per session. If that
-- number drifts up, this prints it, and the session harness fails the build.

local BudgetMeter = {}
BudgetMeter.__index = BudgetMeter

local REPORT_INTERVAL = 300
local WARN_UTILISATION = 0.6

function BudgetMeter.new(app)
	local self = setmetatable({}, BudgetMeter)
	self.app = app
	self.lastReport = 0
	self.lastRequests = 0
	self.lastSessions = 0
	self.peakPerSession = 0
	self.warned = {}
	return self
end

function BudgetMeter:playerCount()
	return self.app.posts:residentCount()
end

-- Per-server, per-minute write allowance at the current headcount.
function BudgetMeter:serverWriteBudget()
	return 60 + self:playerCount() * 40
end

-- Universe-wide MemoryStore allowance. CCU is not knowable from one server,
-- so this uses the local headcount as a floor and reports it as such -- an
-- underestimate of the budget, which is the safe direction.
function BudgetMeter:memoryRequestFloor()
	return 1000 + 120 * self:playerCount()
end

function BudgetMeter:memoryQuotaFloor()
	return 65536 + 1229 * self:playerCount()
end

function BudgetMeter:maybeReport()
	local now = self.app.clock()
	if now - self.lastReport < REPORT_INTERVAL then
		return false
	end
	self.lastReport = now
	return self:report("periodic")
end

function BudgetMeter:report(reason)
	local app = self.app
	local requests = app.data:totalRequests()
	local sessions = app.players.stats.joins
	local perSession = 0
	if sessions > 0 then
		perSession = requests / sessions
	end
	if perSession > self.peakPerSession then
		self.peakPerSession = perSession
	end

	local windowRequests = requests - self.lastRequests
	local windowMinutes = REPORT_INTERVAL / 60
	local perMinute = windowRequests / windowMinutes
	self.lastRequests = requests
	self.lastSessions = sessions

	local budget = self:serverWriteBudget()
	local utilisation = 0
	if budget > 0 then
		utilisation = perMinute / budget
	end

	print(string.format(
		"[Tidekeeper/Budget] %s | players %d | DataStore %d total, %.1f/min (%.0f%% of %d) | %.2f per session | MemoryStore est %d B of %d",
		reason,
		self:playerCount(),
		requests,
		perMinute,
		utilisation * 100,
		budget,
		perSession,
		app.memory.stats.estimatedBytes or 0,
		self:memoryQuotaFloor()
	))

	-- Warnings fire once each. A meter that prints the same warning every
	-- five minutes is a meter people filter out of the log.
	if utilisation > WARN_UTILISATION and not self.warned.requests then
		self.warned.requests = true
		warn("[Tidekeeper/Budget] DataStore request rate is over 60% of the per-server allowance; the write path needs attention before CCU grows")
	end
	local memoryUsed = app.memory.stats.estimatedBytes or 0
	if memoryUsed > self:memoryQuotaFloor() * WARN_UTILISATION and not self.warned.memory then
		self.warned.memory = true
		warn("[Tidekeeper/Budget] MemoryStore estimate is over 60% of the universe-wide quota floor; the exchange index is the only thing in there and it should never get close")
	end
	if perSession > 8 and not self.warned.session then
		self.warned.session = true
		warn(string.format(
			"[Tidekeeper/Budget] %.2f DataStore requests per session, against a design target of 5; doc 03 section 6.3 is now wrong",
			perSession
		))
	end

	return {
		requests = requests,
		perSession = perSession,
		perMinute = perMinute,
		utilisation = utilisation,
		players = self:playerCount(),
	}
end

return BudgetMeter
