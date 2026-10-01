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

-- Server construction lives in the shared prelude so economy-sim.lua can use
-- the identical setup; see tools/tests/session-prelude.lua.
local Prelude = TidekeeperRequire("SessionPrelude")
local newServer = Prelude.newServer
local settle = Prelude.settle

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

-- =========================================================================
do -- 15. CLIENT-SIDE LOCALISATION COVERAGE
	-- =====================================================================
	--
	-- The one test that closes the loop between the two halves of the game.
	--
	-- The server emits `(templateId, epoch, actorId, slots[])`. The client
	-- holds the prose. Those two lists live in different files, in different
	-- layers, edited at different times by different people -- and NOTHING
	-- else in the build checks that they agree. A template id with no prose
	-- does not crash, does not warn, and does not fail any other check: it
	-- renders a bland fallback line into a real player's history, forever,
	-- and the first person to notice is the player.
	--
	-- So: run a real month on a real server, take the entries it ACTUALLY
	-- produced, and render every one of them through the real client.

	local Strings = TidekeeperRequire("Strings")
	local Format = TidekeeperRequire("Format")
	local LedgerView = TidekeeperRequire("LedgerView")
	local DispatchView = TidekeeperRequire("DispatchView")
	local Ledger = TidekeeperRequire("Ledger")

	-- ---------------------------------------------- static coverage first
	-- Every template the DOMAIN declares must have prose. This does not need
	-- a server; it is a straight set comparison, and it is the check that
	-- catches a new template id the moment it is added.
	local missingProse = {}
	local totalVariants = 0
	for templateId in pairs(Ledger.SLOT_COUNT) do
		local variants = Strings.LEDGER[templateId]
		if variants == nil or #variants == 0 then
			missingProse[#missingProse + 1] = templateId
		else
			totalVariants = totalVariants + #variants
		end
	end
	eq("every Ledger template id has prose", #missingProse, 0)
	-- The v1 target from doc 07 section 5, reached in iteration 6. This was
	-- `>= 40` while the content was being written; leaving it there would
	-- have let the Ledger quietly rot back to a receipt printer, since
	-- deleting 140 phrasings would still have passed.
	ge("doc 07 section 5 wants 180 phrasings for v1", totalVariants, 180)

	-- ...and no prose for a template the domain does not declare. An orphan
	-- string is dead weight that a translator will nonetheless translate.
	local orphans = 0
	for templateId in pairs(Strings.LEDGER) do
		if Ledger.SLOT_COUNT[templateId] == nil then
			orphans = orphans + 1
		end
	end
	eq("no prose exists for a template the domain cannot emit", orphans, 0)

	-- Every find the economy can produce must have a NAME. Iteration 6 added
	-- 176 rows to FindsConfig and did not add them to Strings.FIND, so for a
	-- whole iteration every find above id 24 rendered as "something the sea
	-- left". The data shipped and the words did not, and because the sampled
	-- entries all used low ids, nothing noticed. This walks the real find
	-- table rather than a sample.
	local FindsConfig = TidekeeperRequire("FindsConfig")
	Format.resetMisses()
	local unnamed = {}
	for i = 1, #FindsConfig.FINDS do
		local id = FindsConfig.FINDS[i][1]
		if Format.findName(id) == Strings.FIND_FALLBACK then
			unnamed[#unnamed + 1] = id
		end
	end
	eq("every find in the content set has a display name", #unnamed, 0)

	-- Same for letters: an id that reaches a player with no words behind it
	-- is an envelope that opens on nothing.
	local LettersConfig = TidekeeperRequire("LettersConfig")
	local wordless = {}
	for i = 1, #LettersConfig.LETTERS do
		local id = LettersConfig.LETTERS[i][1]
		if Format.letterText(id) == Strings.LETTER_FALLBACK then
			wordless[#wordless + 1] = id
		end
	end
	eq("every letter in the content set has text", #wordless, 0)
	eq("no fallback fired while covering finds and letters", Format.totalMisses(), 0)

	-- Seed Drifters must render as PEOPLE. They are the majority of arrivals
	-- at a quiet post, they are never in the caller's names map because they
	-- are not players, and until iteration 7 every one of them rendered as
	-- "Someone" -- which made the Ledger, the surface carrying this game's
	-- whole emotional argument, mostly a list of anonymous Someones.
	local SeedsConfig = TidekeeperRequire("SeedsConfig")
	local anonymous = 0
	for i = 1, SeedsConfig.SEED_COUNT do
		local ownerId = SeedsConfig.SEED_OWNER_BASE + i - 1
		local name = Format.actorName(ownerId, nil)
		if name == nil or name == "Someone" then
			anonymous = anonymous + 1
		end
	end
	eq("every Seed Drifter renders as a named person", anonymous, 0)

	-- ...and a real player's name still wins over any seed mapping.
	eq("a real player name is used when supplied", Format.actorName(4242, { [4242] = "Ada" }), "Ada")
	eq("an unknown non-seed actor has no name", Format.actorName(4242, nil), nil)

	-- ------------------------------------------------- then the real thing
	local app, env = newServer({ seed = 77 })
	local userId = 5150
	env:addPlayer(userId)
	settle(app, env, 200)

	-- Drive a month so the resolver produces real entries of many kinds.
	-- `residentOf` is the server's own view of a post's Ledger, which is
	-- exactly what RE_LedgerBatch replicates, so this reads the real thing
	-- rather than a test-only accessor.
	local collected = {}
	local seenKey = {}
	for day = 1, 30 do
		env:advance(86400)
		settle(app, env, 40)
		local S = app.posts:get(userId)
		if S ~= nil then
			local resident = app.ledger:residentOf(S)
			if resident ~= nil then
				for i = 1, #resident do
					local e = resident[i]
					local key = tostring(e.templateId) .. ":" .. tostring(e.epoch) .. ":" .. tostring(e.actorId)
					if not seenKey[key] then
						seenKey[key] = true
						collected[#collected + 1] = e
					end
				end
			end
		end
	end

	local realEntries = #collected

	-- A month of one post does not necessarily emit all 21 templates -- a
	-- quiet player may never trigger NO_BERTH, and no single post produces
	-- both the visit range and the remote range. Relying on the simulation to
	-- happen to cover the content is exactly how a template goes unrendered
	-- until a player finds it, so the real entries are SUPPLEMENTED with one
	-- synthetic entry per template per variant.
	--
	-- The synthetic slots are semantically valid, not arbitrary integers. An
	-- earlier version filled them with `(k + variant) % 7 + 1` and produced
	-- tide code 6, which does not exist -- the check then failed for a reason
	-- that had nothing to do with the game. A fixture that is wrong in a
	-- different way from the code is not a test, it is a second bug.
	local SAMPLE = {
		-- templateId = { slot values, in the order the domain writes them }
		[1] = { 7, 18, 1 },
		[2] = { 3, 12, 1 },
		[3] = { 9, 110, 2, 80 },
		[4] = { 12, 240, 180 },
		[5] = { 1, 4, 1 },
		[6] = { 19, 80, 2, 3 },
		[7] = { 2, 4000 },
		[8] = { 1, 2 },
		[9] = { 5, 3 },
		[10] = { 1 },
		[11] = { 4 },
		[12] = { 6, 90, 12 },
		[100] = { 42, 60 },
		[101] = { -10 },
		[102] = { 2 },
		[103] = { 0 },
		[104] = { 75 },
		[105] = { 8 },
		[200] = { 4, 31, 3, 1 },
		[201] = { 5 },
		[250] = { 19, 40, 3 },
	}

	local uncovered = {}
	for templateId, arity in pairs(Ledger.SLOT_COUNT) do
		local sample = SAMPLE[templateId]
		if sample == nil then
			uncovered[#uncovered + 1] = templateId
		else
			eq("sample slots for template " .. templateId .. " match its arity", #sample, arity)
			for variant = 0, 3 do
				local entry = Ledger.entry(templateId, 100 + variant, 880000 + variant * 13, sample)
				if entry ~= nil then
					collected[#collected + 1] = entry
				end
			end
		end
	end
	eq("every template has a coverage sample", #uncovered, 0)
	ge("the coverage run produced entries to render", #collected, 80)
	REPORT.realLedgerEntries = realEntries

	Format.resetMisses()
	local model = LedgerView.build(collected, { [880000] = "Marren" }, { withSilhouettes = true })
	eq("every collected entry rendered", model.count, #collected)

	-- THE assertion: nothing fell back.
	eq("no template rendered a fallback", Format.misses.template, 0)
	eq("no find name was missing", Format.misses.find, 0)
	eq("no class name was missing", Format.misses.class, 0)
	eq("no tide name was missing", Format.misses.tide, 0)
	eq("no slot was missing or unknown", Format.misses.arity, 0)
	eq("total render misses", Format.totalMisses(), 0)

	-- No unexpanded directive reached the output, and nothing is blank.
	local braces, blanks, shortest = 0, 0, 9999
	for g = 1, #model.groups do
		local lines = model.groups[g].lines
		for i = 1, #lines do
			local text = lines[i].text
			if string.find(text, "{", 1, true) or string.find(text, "}", 1, true) then
				braces = braces + 1
			end
			if text == nil or #text == 0 then
				blanks = blanks + 1
			elseif #text < shortest then
				shortest = #text
			end
		end
	end
	eq("no rendered line contains an unexpanded directive", braces, 0)
	eq("no rendered line is empty", blanks, 0)
	ge("even the shortest line is a sentence", shortest, 12)

	-- Every group carries a real tide silhouette from the real tide curve.
	local badSilhouettes = 0
	for g = 1, #model.groups do
		local sil = model.groups[g].silhouette
		if sil == nil or #sil ~= LedgerView.SILHOUETTE_SAMPLES then
			badSilhouettes = badSilhouettes + 1
		end
	end
	eq("every epoch group has a tide silhouette", badSilhouettes, 0)

	-- DETERMINISM. The same entry must read the same way every time, or the
	-- replay is lying about itself. Render the whole thing twice and compare.
	local again = LedgerView.build(collected, { [880000] = "Marren" }, {})
	local drift = 0
	for g = 1, #model.groups do
		local a = model.groups[g].lines
		local b = again.groups[g].lines
		for i = 1, #a do
			if a[i].text ~= b[i].text then
				drift = drift + 1
			end
		end
	end
	eq("the Ledger renders identically on a second read", drift, 0)

	-- The highlight the first-60-seconds flow collapses to must exist.
	local highlight = LedgerView.highlight(model)
	ok("the Ledger produces a highlight line", highlight ~= nil)

	-- UI labels: every one expands, and none leaks a directive.
	local labelBraces, labelCount = 0, 0
	for key in pairs(Strings.UI) do
		local text = Format.label(key, { 1, 2 })
		labelCount = labelCount + 1
		if string.find(text, "{", 1, true) then
			labelBraces = labelBraces + 1
		end
	end
	ge("there are UI labels to check", labelCount, 20)
	eq("no UI label leaks an unexpanded directive", labelBraces, 0)
	eq("rendering labels introduced no new misses", Format.misses.template, 0)

	-- NO FREE TEXT, proved on the client side of the wire too. The server
	-- side is asserted by NetContract.hasNoStringFields in the smoke suite.
	local payload = DispatchView.payload(1, 2, 7, { { findId = 3, qty = 1 } })
	ok("a dispatch payload carries no strings", DispatchView.payloadHasNoStrings(payload))
	eq("the phrase crosses the wire as an index", type(payload.phrase), "number")
	ok("the phrase index names a real authored phrase", Strings.PHRASE[payload.phrase] ~= nil)

	REPORT.ledgerTemplates = 0
	for _ in pairs(Strings.LEDGER) do
		REPORT.ledgerTemplates = REPORT.ledgerTemplates + 1
	end
	REPORT.ledgerVariants = totalVariants
	REPORT.entriesRendered = #collected
	app.shutdown()
end

print("")
-- =========================================================================
-- SCENARIO 16 -- THE CLIENT, DRIVEN AGAINST THE REAL SERVER
--
-- Iteration 4 shipped a client layer and then admitted in the handoff that
-- "no Instance has ever been created ... this is the largest untested
-- surface in the project". Scenario 15 covered the PROSE. This covers the
-- MACHINE: ClientBootstrap talking to the actual remote handlers, over the
-- actual fake platform, with the actual server state behind it.
--
-- It needs no Roblox because the client is a presenter (D25). The only thing
-- faked here is the RemoteFunction object -- a table with an InvokeServer
-- method, which is the entire surface ClientBootstrap:invoke touches.
-- =========================================================================
do -- 16. THE CLIENT, DRIVEN AGAINST THE REAL SERVER
	local ClientBootstrap = TidekeeperRequire("ClientBootstrap")
	local NetContract = TidekeeperRequire("NetContract")
	local Format = TidekeeperRequire("Format")
	local LedgerView = TidekeeperRequire("LedgerView")
	local SessionHandler = TidekeeperRequire("SessionHandler")

	local app, env = newServer({ seed = 20260501 })
	local player = env:addPlayer(5150)
	settle(app, env)

	local function now()
		return env.clock.now
	end

	-- A fake RemoteFunction. Note it goes through the REAL handler with the
	-- REAL app, so a mistake in the payload contract fails here.
	local function remoteTo(handler)
		return {
			InvokeServer = function(_, payload)
				return handler(app, player, payload)
			end,
		}
	end

	local logged = {}
	local client = ClientBootstrap.start({
		clock = now,
		userId = 5150,
		logger = function(tag, msg) logged[#logged + 1] = tag .. ": " .. msg end,
		remotes = {
			[NetContract.RF_SESSION] = remoteTo(SessionHandler.handle),
		},
	})

	-- ---------------------------------------------------------------- session
	local reply, err = client:requestSession()
	ok("the client gets a session from the real handler: " .. tostring(err), reply ~= nil)
	eq("the session reported OK", reply ~= nil and reply.status or -1, 0)
	eq("one invoke was counted", client.stats.invokes, 1)
	eq("no invoke failed", client.stats.failures, 0)
	eq("the snapshot was applied", client.stats.snapshots, 1)
	ok("the client is dirty after a snapshot", client.dirty == true)

	-- ------------------------------------------------------------- every screen
	-- Each screen must render without erroring and must produce a tide
	-- header. A screen that silently returns an empty model is a black
	-- rectangle in the player's hands.
	local SCREENS = {
		{ ClientBootstrap.SCREEN_WORLD, "world" },
		{ ClientBootstrap.SCREEN_LEDGER, "ledger" },
		{ ClientBootstrap.SCREEN_POST, "post" },
		{ ClientBootstrap.SCREEN_ORDERS, "orders" },
		{ ClientBootstrap.SCREEN_CHART, "chart" },
		{ ClientBootstrap.SCREEN_ALMANAC, "almanac" },
	}
	Format.resetMisses()
	for i = 1, #SCREENS do
		local id, name = SCREENS[i][1], SCREENS[i][2]
		client:setScreen(id)
		local okRender, model = pcall(function()
			return client:render()
		end)
		ok("screen " .. name .. " renders without error", okRender == true)
		if okRender then
			eq("screen " .. name .. " reports its own id", model.screen, id)
			ok("screen " .. name .. " has a tide header", model.tide ~= nil)
			ok("screen " .. name .. " names the tide", type(model.tide.state) == "string")
		end
	end
	eq("rendering every screen produced no render misses", Format.totalMisses(), 0)

	-- The two data screens must actually carry their data, not just not
	-- crash. This is the assertion that would have caught a view wired to a
	-- field the snapshot does not have.
	client:setScreen(ClientBootstrap.SCREEN_POST)
	local postModel = client:render()
	ok("the post screen carries a post model", postModel.post ~= nil)
	-- One row per shelf slot the tier allows, empty slots included -- the
	-- player has to see the empty shelf to want to fill it.
	ge("the post screen renders a row per shelf slot", #postModel.post.rows, 6)
	ok("the post screen states its tier", (postModel.post.tierText or "") ~= "")
	ok("the post screen states its shelf usage", (postModel.post.shelfText or "") ~= "")
	ok("no post row leaks a directive", string.find(postModel.post.rows[1].name, "{", 1, true) == nil)

	client:setScreen(ClientBootstrap.SCREEN_ORDERS)
	local ordersModel = client:render()
	ok("the orders screen carries an orders model", ordersModel.orders ~= nil)

	-- --------------------------------------------------------------- redraw
	-- step() must redraw only when something changed. A Ledger that rebuilds
	-- every frame is 60 string builds a second on a phone.
	client:setScreen(ClientBootstrap.SCREEN_LEDGER)
	local before = client.stats.renders
	local first = client:step()
	ok("a dirty client redraws", first ~= nil)
	local second = client:step()
	eq("a clean client does not redraw", second, nil)
	eq("exactly one render happened", client.stats.renders, before + 1)

	client:applyLedgerBatch({})
	local third = client:step()
	ok("a ledger batch makes the client dirty again", third ~= nil)

	-- ------------------------------------------------------- the renderer seam
	-- Main.client.luau is the only file that builds Instances, and it does so
	-- behind this `draw` seam. Proving the seam is called with a well-formed
	-- model is as close to testing that file as is possible without an engine
	-- -- and it is the part worth testing, because the Instance code is
	-- mechanical and this is where the contract lives.
	local drawn = {}
	local recording = ClientBootstrap.start({
		clock = now,
		userId = 5150,
		renderer = {
			draw = function(_, model)
				drawn[#drawn + 1] = model
			end,
		},
		remotes = {
			[NetContract.RF_SESSION] = remoteTo(SessionHandler.handle),
		},
	})
	recording:requestSession()
	recording:setScreen(ClientBootstrap.SCREEN_LEDGER)
	recording:step()
	eq("the renderer seam was called exactly once", #drawn, 1)
	ok("the renderer received a model", drawn[1] ~= nil and drawn[1].screen ~= nil)

	-- ------------------------------------------------------------- failure
	-- A client whose remote is missing must degrade to a message, not throw.
	-- The player on a dropped connection is the most common "state" there is.
	local offline = ClientBootstrap.start({ clock = function() return 0 end })
	local noReply, offlineText = offline:requestSession()
	eq("an offline client gets no reply", noReply, nil)
	ok("an offline client gets a human message", type(offlineText) == "string" and #offlineText > 0)
	ok("the offline message is not a raw directive", string.find(offlineText, "{", 1, true) == nil)
	eq("the offline failure was counted", offline.stats.failures, 1)

	-- A remote that THROWS must be caught and counted, not propagated.
	local throwing = ClientBootstrap.start({
		clock = function() return 0 end,
		remotes = {
			[NetContract.RF_SESSION] = {
				InvokeServer = function()
					error("simulated network failure")
				end,
			},
		},
	})
	local threwReply = throwing:requestSession()
	eq("a throwing remote yields no reply", threwReply, nil)
	eq("a throwing remote is counted as a failure", throwing.stats.failures, 1)

	-- --------------------------------------------------------- sequence numbers
	-- NetContract rejects out-of-order sequence numbers, so the client must
	-- never reuse one. This is the client half of the replay defence.
	local seqs = {}
	local dupes = 0
	for _ = 1, 25 do
		local n = client:nextSeq()
		if seqs[n] then dupes = dupes + 1 end
		seqs[n] = true
	end
	eq("the client never reuses a sequence number", dupes, 0)

	REPORT.clientScreens = #SCREENS
end

do -- 17. THE DISPATCH PIPELINE ACTUALLY CARRIES WHAT THE PLAYER CHOSE
	-- Iteration 7 found RF_Dispatch was inert end to end. The handler wrote
	-- S.dispatchLetter and S.dispatchCargo; ExchangeService:buildDrifter read
	-- neither, recomputing cargo from the shelves and hard-coding
	-- letterId = 0. So the dispatch screen was decoration: your cargo choice
	-- was discarded and no letter ever reached another player, which also
	-- made Ledger template 105 unreachable.
	--
	-- Every check was green throughout, because each half is valid code on
	-- its own. This scenario asserts the two halves actually MEET.
	local Post = TidekeeperRequire("Post")
	local Tide = TidekeeperRequire("Tide")
	local app, env = newServer({ seed = 909 })
	local userId = 7321
	env:addPlayer(userId)
	settle(app, env, 200)

	local S = app.posts:get(userId)
	ok("the dispatching post exists", S ~= nil)

	-- Stock two finds so there is something legitimate to send. Stock and
	-- shelves are different things: `setShelf` prices a display slot,
	-- `addStock` is what the post actually holds, and cargo is validated
	-- against the latter.
	Post.addStock(S, 7, 3)
	Post.addStock(S, 3, 2)
	Post.setShelf(S, 1, 7, 18)
	Post.setShelf(S, 2, 3, 12)
	local epoch = Tide.epoch(env:now())

	-- What the player chose, as RF_Dispatch would have recorded it.
	S.dispatchedAt = epoch
	S.dispatchLetter = 41
	S.dispatchCargo = { 3 }

	local d = app.exchange:buildDrifter(S, epoch)
	eq("the drifter carries the letter the player attached", d.letterId, 41)
	eq("the drifter carries exactly the cargo the player chose", #d.cargo, 1)
	eq("...and it is the right find", d.cargo[1], 3)

	-- A letter id beyond the content set must be dropped, not carried. The
	-- field is server-set, but a value persisted before a content change
	-- would otherwise address a phrase that no longer exists.
	S.dispatchLetter = 99999
	local d2 = app.exchange:buildDrifter(S, epoch)
	eq("an out-of-range letter id is dropped", d2.letterId, 0)

	-- A stale choice must be re-validated against CURRENT stock, not trusted.
	S.dispatchLetter = 7
	S.dispatchCargo = { 199 }
	local d3 = app.exchange:buildDrifter(S, epoch)
	local carriedUnstocked = false
	for i = 1, #d3.cargo do
		if d3.cargo[i] == 199 then carriedUnstocked = true end
	end
	ok("cargo the post no longer holds is not shipped", not carriedUnstocked)
	ok("the shelf fallback still fills the hold", #d3.cargo > 0)

	-- And a post that never opened the dispatch screen still trades.
	S.dispatchLetter = nil
	S.dispatchCargo = nil
	local d4 = app.exchange:buildDrifter(S, epoch)
	eq("a post that never dispatched carries no letter", d4.letterId, 0)
	ok("...but still carries cargo off its shelves", #d4.cargo > 0)
end

do -- 18. TIER PROMOTION, THROUGH THE REAL HANDLER
	-- Until iteration 7 a post's tier was set to 1 at creation and nothing
	-- ever changed it, so 24-shelf tier-4 posts, the currents behind
	-- CURRENT_MIN_TIER and the whole of doc 06's progression table described
	-- a game that could not be played. There was no remote to buy a tier.
	--
	-- This drives PostHandler.upgrade, which is the real server path,
	-- including the NetContract rate guard.
	local Post = TidekeeperRequire("Post")
	local EconomyConfig = TidekeeperRequire("EconomyConfig")
	local PostHandler = TidekeeperRequire("PostHandler")

	local app, env = newServer({ seed = 4242 })
	local userId = 8800
	env:addPlayer(userId)
	settle(app, env, 200)

	local player = { UserId = userId }
	local S = app.posts:get(userId)
	ok("the upgrading post exists", S ~= nil)
	eq("a new post starts at tier 1", S.tier, 1)

	-- Too poor: refused, and nothing changes.
	S.coin = 0
	local res = PostHandler.upgrade(app, player, { seq = 1 })
	eq("a post that cannot pay is refused", res.status, PostHandler.E_ILLEGAL)
	eq("...and is still tier 1", S.tier, 1)

	-- Rich enough: promoted, and the coin is really gone.
	-- RF_Upgrade is deliberately throttled to 1 burst / 3 per minute, so the
	-- clock has to move between attempts. That the refused attempt above
	-- consumed the burst is correct behaviour, not a test artefact.
	env:advance(60)
	settle(app, env, 20)
	S = app.posts:get(userId)
	S.coin = EconomyConfig.TIER_COST[2] + 5
	local res2 = PostHandler.upgrade(app, player, { seq = 2 })
	eq("a post that can pay is promoted", res2.status, PostHandler.OK)
	eq("the handler reports the new tier", res2.tier, 2)
	eq("the coin was spent", S.coin, 5)
	eq("the handler quotes the next price", res2.nextCost, EconomyConfig.TIER_COST[3])

	-- The extra shelves are genuinely usable, which is the entire point of
	-- paying: tier 1 caps at 6, so slot 7 must have been impossible before.
	for i = 1, 7 do
		Post.addStock(S, i, 1)
	end
	local placed = 0
	for i = 1, 7 do
		if Post.setShelf(S, i, i, 5) then
			placed = placed + 1
		end
	end
	eq("a tier-2 post can fill seven shelves", placed, 7)
	ok("the promoted post is still structurally valid", Post.checkInvariants(S))

	-- And the promotion survives a save/load round trip, or it is worth
	-- nothing: tier is persisted in PostCodec as a u8.
	local PostCodec = TidekeeperRequire("PostCodec")
	local blob = PostCodec.encode(S)
	local back = PostCodec.decode(blob)
	eq("the tier survives the codec round trip", back.tier, 2)
end

print(string.format(
	"measured: %.2f DataStore and %.2f MemoryStore requests per session over %d sessions across %d posts and %d days",
	REPORT.dataPerSession or 0,
	REPORT.memoryPerSession or 0,
	REPORT.sessions or 0,
	REPORT.posts or 0,
	REPORT.days or 0
))
