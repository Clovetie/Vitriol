--!nonstrict
-- ServerStorage/Tidekeeper/Services/Bootstrap (ModuleScript)
--
-- Layer L3. THE COMPOSITION ROOT. Every `new()` call in the server tree
-- happens here and nowhere else, and every dependency is passed in rather
-- than reached for.
--
-- This is the module that makes the session harness possible. `Main` calls
-- `Bootstrap.start()` with no arguments and gets the real thing; the harness
-- calls `Bootstrap.start({ dataStoreService = fake, clock = virtualClock,
-- ... })` and gets the SAME SERVICES wired to fakes. There is no "test mode"
-- branch anywhere in the services, because a test mode branch is a code path
-- that ships untested by definition.
--
-- Read the `start` function top to bottom and you have the entire server
-- architecture: six adapters and services, one scheduler, and the order they
-- depend on each other in.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local ServerStorage = game:GetService("ServerStorage")
local Root = ServerStorage:WaitForChild("Tidekeeper")

local Remotes = require(Tidekeeper.Shared.Remotes)
local NetContract = require(Tidekeeper.Shared.NetContract)

local DataStoreAdapter = require(Root.Adapters.DataStoreAdapter)
local MemoryAdapter = require(Root.Adapters.MemoryAdapter)
local NotifyAdapter = require(Root.Adapters.NotifyAdapter)
local PolicyAdapter = require(Root.Adapters.PolicyAdapter)

local CadenceService = require(Root.Services.CadenceService)
local PostService = require(Root.Services.PostService)
local ExchangeService = require(Root.Services.ExchangeService)
local LedgerService = require(Root.Services.LedgerService)
local NotifyService = require(Root.Services.NotifyService)
local ShowcaseService = require(Root.Services.ShowcaseService)
local PlayerService = require(Root.Services.PlayerService)

local Bootstrap = {}

local function defaultLogger(scope, message)
	print("[Tidekeeper/" .. scope .. "] " .. message)
end

-- `opts` is empty in production. Every field exists so the harness can
-- substitute a fake without the services knowing.
function Bootstrap.start(opts)
	local o = opts or {}
	local logger = o.logger
	if logger == nil and o.silent ~= true then
		logger = defaultLogger
	end
	local clock = o.clock or os.time

	local app = {}
	app.logger = logger
	app.clock = clock

	-- L1 adapters. These are the only modules that touch the platform.
	app.memory = MemoryAdapter.new({
		service = o.memoryStoreService,
		clock = clock,
		logger = logger,
	})
	app.data = DataStoreAdapter.new({
		service = o.dataStoreService,
		memory = app.memory,
		waiter = o.waiter,
		clock = clock,
		logger = logger,
		seed = o.seed,
	})
	app.notifyAdapter = NotifyAdapter.new({
		sender = o.notificationSender,
		container = o.serverScriptService,
		experienceVisits = o.experienceVisits or 0,
		logger = logger,
	})
	app.policy = PolicyAdapter.new({
		service = o.policyService,
		logger = logger,
	})

	-- L2 transport. Built before any service so that a service can capture
	-- a handle at construction rather than looking one up per call.
	app.remotes = o.remotes
	if app.remotes == nil and o.headless ~= true then
		app.remotes = Remotes.build()
	end
	app.guard = NetContract.newGuard()

	-- L3 services, in dependency order.
	app.cadence = CadenceService.new({
		runService = o.runService,
		clock = o.monotonic or os.clock,
		logger = logger,
		profiler = o.profiler,
	})
	app.exchange = ExchangeService.new({
		data = app.data,
		memory = app.memory,
		clock = clock,
		logger = logger,
	})
	app.ledger = LedgerService.new({
		data = app.data,
		clock = clock,
		logger = logger,
	})
	app.notify = NotifyService.new({
		adapter = app.notifyAdapter,
		clock = clock,
		logger = logger,
	})
	app.showcase = ShowcaseService.new({
		data = app.data,
		clock = clock,
		logger = logger,
	})
	app.posts = PostService.new({
		data = app.data,
		memory = app.memory,
		exchange = app.exchange,
		ledger = app.ledger,
		cadence = app.cadence,
		clock = clock,
		jobId = o.jobId or game.JobId,
		logger = logger,
	})
	app.ledger.posts = app.posts
	app.players = PlayerService.new({
		players = o.players,
		posts = app.posts,
		exchange = app.exchange,
		ledger = app.ledger,
		notify = app.notify,
		showcase = app.showcase,
		policy = app.policy,
		remotes = app.remotes,
		clock = clock,
		logger = logger,
	})

	-- Cadence registrations. THIS IS THE ENTIRE SERVER TICK BUDGET, in one
	-- readable list. Anything not registered here does not run periodically,
	-- because there is no other way for it to.
	app.cadence:register(CadenceService.SLOT_SLOW, "posts.tick", function()
		app.posts:tick()
	end)
	app.cadence:register(CadenceService.SLOT_IO, "ledger.flush", function()
		app.ledger:flushPending()
	end)
	app.cadence:register(CadenceService.SLOT_IO, "showcase.flush", function()
		app.showcase:flush()
	end)
	app.cadence:register(CadenceService.SLOT_IO, "exchange.trim", function()
		app.exchange:trimDelivered(app.posts:epochNow())
	end)

	if o.autoStart ~= false then
		app.cadence:start()
	end
	if o.bindPlayers ~= false then
		app.players:bind()
	end

	function app.shutdown()
		app.cadence:flushResolves()
		app.players:shutdown()
		app.cadence:stop()
	end

	-- A single place to read every counter, which is what BudgetMeter
	-- prints and what the session harness asserts against.
	function app.stats()
		return {
			data = app.data.stats,
			memory = app.memory.stats,
			notify = app.notify.stats,
			notifyAdapter = app.notifyAdapter.stats,
			policy = app.policy.stats,
			posts = app.posts.stats,
			exchange = app.exchange.stats,
			ledger = app.ledger.stats,
			showcase = app.showcase.stats,
			players = app.players.stats,
			cadence = app.cadence:report(),
		}
	end

	return app
end

return Bootstrap
