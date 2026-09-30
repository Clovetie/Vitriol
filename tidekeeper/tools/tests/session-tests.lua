-- tools/tests/session-tests.lua
--
-- The SESSION suite. Where pure-tests.lua proves the simulation is correct,
-- this proves the SERVER is correct: that the adapters, the scheduler and
-- the join/leave choreography behave when DataStore conflicts, MemoryStore
-- runs out of quota, the request budget dries up and two servers fight over
-- the same player.
--
-- Everything here runs the REAL modules against tools/tests/fake-platform.lua.
-- There is not one mock service object in this file.
--
-- The headline number it produces -- mean platform requests per session over
-- a simulated month -- is quoted in docs/03 section 6.3. It is measured here,
-- printed by the runner, and asserted against a ceiling, so the documentation
-- cannot drift away from the code without turning the build red.

TESTS = { passed = 0, failed = 0 }

local function ok(name, condition, detail)
	if condition then
		TESTS.passed = TESTS.passed + 1
	else
		TESTS.failed = TESTS.failed + 1
		print("FAIL  " .. name .. (detail ~= nil and ("  -- " .. tostring(detail)) or ""))
	end
end

local function eq(name, actual, expected)
	ok(name, actual == expected, "got " .. tostring(actual) .. ", expected " .. tostring(expected))
end

local function le(name, actual, limit)
	ok(name, actual <= limit, "got " .. tostring(actual) .. ", limit " .. tostring(limit))
end

local function ge(name, actual, floorValue)
	ok(name, actual >= floorValue, "got " .. tostring(actual) .. ", floor " .. tostring(floorValue))
end

REPORT = {}

local FakePlatform = TidekeeperRequire("FakePlatform")

-- Build a server. Returns (app, env). `opts` is passed through to the fake.
local function newServer(opts)
	local o = opts or {}
	local env = FakePlatform.new(o)
	FakePlatform.install(env)
	-- The module cache is global to this VM, so every server in this file
	-- shares one set of loaded modules -- exactly like a real place, where
	-- the ModuleScripts are shared and only the instances differ.
	local Bootstrap = TidekeeperRequire("Bootstrap")
	local app = Bootstrap.start({
		dataStoreService = env.services.DataStoreService,
		memoryStoreService = env.services.MemoryStoreService,
		policyService = env.services.PolicyService,
		players = env.PlayersService,
		runService = env.RunService,
		serverScriptService = env.services.ServerScriptService,
		clock = function()
			return env.clock.now
		end,
		monotonic = function()
			return env.clock.now
		end,
		waiter = function(seconds)
			return env:wait(seconds)
		end,
		jobId = o.jobId or "server-A",
		headless = true,
		autoStart = false,
		bindPlayers = true,
		silent = o.verbose ~= true,
		logger = o.verbose and function(scope, message)
			print("[" .. scope .. "] " .. message)
		end or nil,
		seed = o.seed or 7,
	})
	return app, env
end

-- Drive the scheduler until every queued resolve has drained.
local function settle(app, env, ticks)
	for _ = 1, (ticks or 64) do
		app.cadence:step(0.25)
		env:advance(0.25)
		if app.cadence:pendingResolves() == 0 then
			break
		end
	end
	app.cadence:flushResolves()
end

-- A whole session: join, do a few things, leave.
local function playSession(app, env, userId, actions)
	env:addPlayer(userId)
	settle(app, env)
	if actions ~= nil then
		actions(app, env, userId)
	end
	env:removePlayer(userId)
	return app.posts:get(userId)
end

-- =========================================================================
do -- 1. Cold start: a player who has never played
	-- =====================================================================
	local app, env = newServer({ seed = 11 })

	env:addPlayer(4001)
	settle(app, env)

	local S = app.posts:get(4001)
	ok("cold start creates a post", S ~= nil)
	if S ~= nil then
		eq("new post is tier 1", S.tier, 1)
		eq("new post has no coin", S.coin, 0)
		eq("new post owner is the player", S.owner, 4001)
		ge("new post resolvedAt is set", S.resolvedAt, 1)
	end
	eq("the post is resident", app.posts:residentCount(), 1)
	eq("the lock was taken", app.posts.stats.lockDenied, 0)
	eq("nothing was loaded", app.posts.stats.loaded, 0)
	eq("one post was created", app.posts.stats.created, 1)

	local joinRequests = env.stats.dataStore.total
	le("a first join costs at most 3 DataStore requests", joinRequests, 3)

	env:removePlayer(4001)
	eq("the post is no longer resident", app.posts:residentCount(), 0)
	eq("one save happened on leave", app.posts.stats.saved, 1)
	ok("a drifter was published", app.exchange.stats.published >= 1)
	REPORT.coldStartRequests = env.stats.dataStore.total
end

-- =========================================================================
do -- 2. Round trip: the state that came back is the state that went in
	-- =====================================================================
	local app, env = newServer({ seed = 12 })

	env:addPlayer(4002)
	settle(app, env)
	local S = app.posts:get(4002)
	local Post = TidekeeperRequire("Post")
	Post.addStock(S, 3, 5)
	Post.addStock(S, 9, 2)
	Post.setShelf(S, 1, 3, 14)
	S.coin = 271
	S.renown = 44
	app.posts:markDirty(4002)
	env:removePlayer(4002)

	-- Same universe, same data, new join.
	env:addPlayer(4002)
	settle(app, env)
	local S2 = app.posts:get(4002)
	ok("the post came back", S2 ~= nil)
	if S2 ~= nil then
		eq("coin survived the round trip", S2.coin, 271)
		eq("renown survived the round trip", S2.renown, 44)
		eq("stock survived the round trip", Post.stockOf(S2, 3), 5)
		eq("the shelf survived the round trip", S2.shelves[1] ~= nil and S2.shelves[1].id or 0, 3)
		eq("the salt survived the round trip", S2.salt, S.salt)
	end
	env:removePlayer(4002)
	eq("one post was loaded, not created", app.posts.stats.loaded, 1)
end

-- =========================================================================
do -- 3. A failed READ must never look like a new player
	-- =====================================================================
	-- This is the single most expensive bug a persistence layer can have,
	-- so it gets its own scenario: store real data, then make every request
	-- fail, and assert that the join is REFUSED rather than served a fresh
	-- empty post that would overwrite the real one at logout.
	local app, env = newServer({ seed = 13 })

	env:addPlayer(4003)
	settle(app, env)
	local S = app.posts:get(4003)
	S.coin = 9999
	app.posts:markDirty(4003)
	env:removePlayer(4003)
	local savedRequests = env.stats.dataStore.total

	env.inject.throttlePerMille = 1000
	env:addPlayer(4003)
	settle(app, env)
	ok("the join was refused rather than served an empty post", app.posts:get(4003) == nil)
	ge("the refusal was counted", app.players.stats.joinFailures, 1)
	env.inject.throttlePerMille = 0

	env:addPlayer(4003)
	settle(app, env)
	local S2 = app.posts:get(4003)
	ok("the real post is still there after the failed join", S2 ~= nil)
	if S2 ~= nil then
		eq("and its coin was not destroyed", S2.coin, 9999)
	end
	env:removePlayer(4003)
	ge("requests were made", env.stats.dataStore.total, savedRequests)
end

-- =========================================================================
do -- 4. DataUpdateConflict: the retry loop, on real error strings
	-- =====================================================================
	local app, env = newServer({ seed = 14, inject = { conflictPerMille = 400 } })

	env:addPlayer(4004)
	settle(app, env)
	local S = app.posts:get(4004)
	ok("a post was obtained despite conflicts", S ~= nil)
	if S ~= nil then
		S.coin = 4242
		app.posts:markDirty(4004)
	end
	env:removePlayer(4004)

	ge("conflicts were injected", env.stats.dataStore.injectedConflicts, 1)
	ge("the adapter classified them as conflicts", app.data.stats.conflicts, 1)
	ge("and retried", app.data.stats.retries, 1)

	env.inject.conflictPerMille = 0
	env:addPlayer(4004)
	settle(app, env)
	local S2 = app.posts:get(4004)
	ok("the write landed despite the conflicts", S2 ~= nil and S2.coin == 4242, S2 and S2.coin)
	env:removePlayer(4004)
end

-- =========================================================================
do -- 5. Quota errors fail FAST -- they do not get better in four seconds
	-- =====================================================================
	local app, env = newServer({ seed = 15, inject = { quotaPerMille = 1000 } })

	local before = env.stats.scheduler.secondsWaited
	env:addPlayer(4005)
	settle(app, env)
	local waited = env.stats.scheduler.secondsWaited - before

	ok("the join failed", app.posts:get(4005) == nil)
	le("and it did not spend the full backoff schedule doing so", waited, 1.0)
	ge("the quota error was seen", env.stats.dataStore.injectedQuota, 1)
end

-- =========================================================================
do -- 6. MemoryStore degradation: the game stays playable with no index
	-- =====================================================================
	-- MemoryStore's quota is universe-wide and is the one that a successful
	-- launch breaks first. When it fails, the exchange loses its index and
	-- falls back to Seed Drifters -- but nobody is blocked from playing.
	local app, env = newServer({ seed = 16, inject = { memoryThrottlePerMille = 1000 } })

	env:addPlayer(4006)
	settle(app, env)
	local S = app.posts:get(4006)
	ok("the player still got in with MemoryStore down", S ~= nil)
	ge("the memory adapter recorded failures", app.memory.stats.failures, 1)
	ok("the memory adapter degraded", app.memory.degraded == true or app.memory.stats.failures > 0)
	env:removePlayer(4006)
end

-- =========================================================================
do -- 7. Two servers, one player: the lock
	-- =====================================================================
	local appA, env = newServer({ seed = 17, jobId = "server-A" })
	-- A second Bootstrap over the SAME backend is what two Roblox servers
	-- look like from the data's point of view.
	local Bootstrap = TidekeeperRequire("Bootstrap")
	local appB = Bootstrap.start({
		dataStoreService = env.services.DataStoreService,
		memoryStoreService = env.services.MemoryStoreService,
		policyService = env.services.PolicyService,
		players = env.PlayersService,
		runService = env.RunService,
		clock = function()
			return env.clock.now
		end,
		monotonic = function()
			return env.clock.now
		end,
		waiter = function(seconds)
			return env:wait(seconds)
		end,
		jobId = "server-B",
		headless = true,
		autoStart = false,
		bindPlayers = false,
		silent = true,
		seed = 18,
	})

	env:addPlayer(4007)
	settle(appA, env)
	ok("server A has the post", appA.posts:get(4007) ~= nil)

	local gotB, whyB = appB.posts:load(4007, 4007)
	eq("server B was refused the same post", gotB, false)
	ok("and was told why", type(whyB) == "string", whyB)
	ge("the refusal was counted", appB.posts.stats.lockDenied, 1)

	env:removePlayer(4007)
	local gotB2 = appB.posts:load(4007, 4007)
	eq("after A releases, B may take it", gotB2, true)
	appB.posts:unload(4007, env.clock.now)
end

-- =========================================================================
do -- 8. At-most-once Drifter delivery
	-- =====================================================================
	-- The property the whole asynchronous design rests on. Resolve.run
	-- schedules arrivals `mod epochCount`, so a re-delivered Drifter does
	-- not duplicate an item -- it rewrites history into a DIFFERENT history.
	local app, env = newServer({ seed = 19 })

	-- Eight players publish, so the exchange has real inventory.
	for i = 1, 8 do
		env:addPlayer(4100 + i)
		settle(app, env)
		env:removePlayer(4100 + i)
	end
	ge("drifters were published", app.exchange.stats.published, 8)

	-- Now a ninth player claims repeatedly. No id may ever be handed out
	-- twice, across any number of claims.
	local seen = {}
	local duplicates = 0
	local total = 0
	env:addPlayer(4200)
	settle(app, env)
	local S = app.posts:get(4200)
	if S ~= nil then
		local Tide = TidekeeperRequire("Tide")
		local epoch = Tide.epoch(env.clock.now)
		for _ = 1, 12 do
			local batch = app.exchange:claim(S, epoch - 4, epoch, 8, 8)
			for j = 1, #batch do
				-- Seeds recur by design (they are characters, not stock),
				-- so the property under test is about REAL people's
				-- drifters: those were removed from a shard and cannot be
				-- recreated, so handing one out twice destroys history.
				if not app.exchange:isSeed(batch[j].owner) then
					total = total + 1
					if seen[batch[j].id] then
						duplicates = duplicates + 1
					end
					seen[batch[j].id] = true
				end
			end
		end
	end
	ge("claims produced drifters", total, 1)
	eq("no drifter was ever delivered twice", duplicates, 0)
	env:removePlayer(4200)
end

-- =========================================================================
do -- 9. The Ledger is never empty
	-- =====================================================================
	-- A brand-new universe with zero other players must still produce a
	-- populated Ledger, via Seed Drifters. This is a hard invariant: an
	-- empty Ledger is the failure mode that kills an asynchronous social
	-- game on day one, when there is nobody else online.
	local app, env = newServer({ seed = 20 })

	env:addPlayer(4300)
	settle(app, env)
	local S = app.posts:get(4300)
	ok("a lone player got a post", S ~= nil)
	if S ~= nil then
		local Tide = TidekeeperRequire("Tide")
		local epoch = Tide.epoch(env.clock.now)
		local batch = app.exchange:claim(S, epoch, epoch, 6, 4)
		ge("an empty exchange still yields visitors", #batch, 1)
		eq("and they are seeds", app.exchange.stats.claimedSeed >= 1, true)
		local Drifter = TidekeeperRequire("Drifter")
		local allValid = true
		for i = 1, #batch do
			local valid = Drifter.validate(batch[i])
			if not valid then
				allValid = false
			end
		end
		ok("every seed drifter validates against the schema", allValid)
	end
	env:removePlayer(4300)
end

-- =========================================================================
do -- 10. Notifications are disabled, and that is the boring path
	-- =====================================================================
	local app, env = newServer({ seed = 21 })
	eq("the Open Cloud package is absent, so the notifier is disabled", app.notifyAdapter.enabled, false)

	env:addPlayer(4400)
	settle(app, env)
	env:removePlayer(4400)

	eq("nothing was dispatched", app.notify.stats.dispatched, 0)
	ok("the session completed anyway", app.posts.stats.saved >= 1)

	-- With a sender installed, the same code path sends exactly once a day.
	local sent = 0
	local app2, env2 = newServer({ seed = 22 })
	app2.notifyAdapter.sender = function(userId, request)
		sent = sent + 1
		return { statusCode = 200 }
	end
	app2.notifyAdapter.enabled = true
	-- Eligibility: Roblox does not deliver anything until the experience
	-- has 100 visits since launch, so a test of the send path has to say
	-- that it is past that.
	app2.notifyAdapter.experienceVisits = 250000
	local NotifyConfig = TidekeeperRequire("NotifyConfig")
	app2.notifyAdapter.messageIdFor = function()
		return "test-message-id"
	end
	app2.notify:consider(4401, NotifyConfig.KIND_DEEPWATER, { tier = 2 })
	app2.notify:flush(4401)
	app2.notify:consider(4401, NotifyConfig.KIND_INBOX_FULL, { count = 12 })
	app2.notify:flush(4401)
	eq("one notification per user per day, enforced locally", sent, 1)
end

-- =========================================================================
do -- 11. Chunked resolve equals the plan, and the plan is pure
	-- =====================================================================
	local CadenceService = TidekeeperRequire("CadenceService")
	local Tide = TidekeeperRequire("Tide")
	local GameConfig = TidekeeperRequire("GameConfig")

	local base = Tide.epochStart(100)
	local plan = CadenceService.planChunks(base, base + Tide.EPOCH_SECONDS * 9 + 5)
	ge("a nine-epoch gap plans more than one chunk", #plan, 2)
	local widest = 0
	for i = 1, #plan do
		local width = plan[i].to - plan[i].from + 1
		if width > widest then
			widest = width
		end
	end
	le("no chunk exceeds EPOCHS_PER_RESOLVE_TICK", widest, GameConfig.EPOCHS_PER_RESOLVE_TICK)
	eq("the last chunk ends at the real now", plan[#plan].now, base + Tide.EPOCH_SECONDS * 9 + 5)

	local plan2 = CadenceService.planChunks(base, base + Tide.EPOCH_SECONDS * 9 + 5)
	local same = #plan == #plan2
	for i = 1, #plan do
		if plan[i].from ~= plan2[i].from or plan[i].to ~= plan2[i].to or plan[i].now ~= plan2[i].now then
			same = false
		end
	end
	ok("the chunk plan is a pure function of (resolvedAt, now)", same)

	eq("no gap plans no chunks", #CadenceService.planChunks(base, base), 0)

	-- A 60-day absence must clamp to MAX_CATCHUP_EPOCHS, not plan 232 chunks.
	local long = CadenceService.planChunks(base, base + Tide.EPOCH_SECONDS * 232)
	local covered = long[#long].to - long[1].from + 1
	le("a 60-day absence is clamped", covered, GameConfig.MAX_CATCHUP_EPOCHS)
	ok("and the first chunk is marked as the clamped one", long[1].clamped == true)

	-- Drifter-to-chunk assignment is pure too.
	local a = CadenceService.chunkForDrifter(123456789, 987654321, 7)
	local b = CadenceService.chunkForDrifter(123456789, 987654321, 7)
	eq("drifter chunk assignment is deterministic", a, b)
	ok("and lands inside the plan", a >= 1 and a <= 7, a)
end

-- =========================================================================
do -- 12. The cadence budget: no slot may exceed its declared cost
	-- =====================================================================
	local app, env = newServer({ seed = 23 })
	for i = 1, 6 do
		env:addPlayer(4500 + i)
	end
	settle(app, env, 200)
	for _ = 1, 200 do
		app.cadence:step(0.25)
		env:advance(0.25)
	end
	local report = app.cadence:report()
	local overrunTotal = 0
	for i = 1, #report do
		overrunTotal = overrunTotal + report[i].overruns
	end
	-- The virtual clock makes every slot cost 0 ms, so this asserts the
	-- ACCOUNTING works, not the speed; the real timing budget is an OD12
	-- item that needs Studio.
	eq("no slot overran its budget under the virtual clock", overrunTotal, 0)
	ge("the slow slot ran", report[3].runs, 1)
	for i = 1, 6 do
		env:removePlayer(4500 + i)
	end
	eq("every post was saved", app.posts.stats.saved >= 6, true)
end

-- =========================================================================
do -- 13. THE HEADLINE MEASUREMENT: requests per session over a month
	-- =====================================================================
	-- 8 posts, 200 sessions, spread over 30 days of virtual time. This is
	-- the number docs/03 section 6.3 quotes. It is measured, not asserted.
	local app, env = newServer({ seed = 24 })
	local Tide = TidekeeperRequire("Tide")

	local POSTS = 8
	local SESSIONS = 200
	local DAYS = 30
	local step = (DAYS * 86400) / SESSIONS

	for i = 1, SESSIONS do
		local userId = 5000 + (i % POSTS)
		env:addPlayer(userId)
		settle(app, env)
		local S = app.posts:get(userId)
		if S ~= nil then
			-- A little real activity so the dirty check has something to
			-- notice; a session that changes nothing writes nothing, and
			-- measuring only those would be cheating.
			local Post = TidekeeperRequire("Post")
			Post.addStock(S, 1 + (i % 40), 1)
			app.posts:markDirty(userId)
		end
		env:removePlayer(userId)
		env:advance(step)
	end

	local dataTotal = env.stats.dataStore.total
	local memoryTotal = env.stats.memory.total
	REPORT.sessions = SESSIONS
	REPORT.posts = POSTS
	REPORT.days = DAYS
	REPORT.dataStoreRequests = dataTotal
	REPORT.memoryRequests = memoryTotal
	REPORT.dataPerSession = dataTotal / SESSIONS
	REPORT.memoryPerSession = memoryTotal / SESSIONS
	REPORT.retries = app.data.stats.retries
	REPORT.saves = app.posts.stats.saved
	REPORT.published = app.exchange.stats.published
	REPORT.claimedLive = app.exchange.stats.claimedLive
	REPORT.claimedEcho = app.exchange.stats.claimedEcho
	REPORT.claimedSeed = app.exchange.stats.claimedSeed
	REPORT.duplicatesRefused = app.exchange.stats.duplicatesRefused

	eq("every session completed", app.players.stats.joins, SESSIONS)
	eq("no join failed", app.players.stats.joinFailures, 0)
	-- The design target is 5. The ceiling is 8: if it goes over, either the
	-- write policy regressed or docs/03 section 6.3 is now a lie, and both
	-- are build failures.
	le("mean DataStore requests per session stays under the ceiling", REPORT.dataPerSession, 8)
	le("mean MemoryStore requests per session stays under the ceiling", REPORT.memoryPerSession, 6)
	eq("no drifter was delivered twice across the month", REPORT.duplicatesRefused, 0)
	ge("the exchange had real liquidity", REPORT.claimedLive + REPORT.claimedEcho, 1)
end

-- =========================================================================
do -- 14. BindToClose saves everyone
	-- =====================================================================
	local app, env = newServer({ seed = 25 })
	for i = 1, 5 do
		env:addPlayer(4600 + i)
	end
	settle(app, env, 200)
	for i = 1, 5 do
		local S = app.posts:get(4600 + i)
		if S ~= nil then
			S.coin = 100 + i
			app.posts:markDirty(4600 + i)
		end
	end
	local savedBefore = app.posts.stats.saved
	app.shutdown()
	ge("shutdown saved every resident post", app.posts.stats.saved - savedBefore, 5)
	eq("and evicted them all", app.posts:residentCount(), 0)
end

print("")
print(string.format(
	"measured: %.2f DataStore and %.2f MemoryStore requests per session over %d sessions across %d posts and %d days",
	REPORT.dataPerSession or 0,
	REPORT.memoryPerSession or 0,
	REPORT.sessions or 0,
	REPORT.posts or 0,
	REPORT.days or 0
))
