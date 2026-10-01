-- tools/tests/session-prelude.lua
--
-- The shared server-construction helpers for every suite that drives the
-- REAL server against tools/tests/fake-platform.lua.
--
-- These lived as locals inside session-tests.lua until iteration 7 needed
-- them from economy-sim.lua too. Copying them would have repeated the exact
-- mistake that had just been fixed in tidekeeper-smoke-test.js, where a
-- duplicated module list drifted the moment the real one changed. One
-- definition, imported twice.

local FakePlatform = TidekeeperRequire("FakePlatform")

local Prelude = {}

-- Build a server. Returns (app, env). `opts` is passed through to the fake.
function Prelude.newServer(opts)
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
function Prelude.settle(app, env, ticks)
	for _ = 1, (ticks or 64) do
		app.cadence:step(0.25)
		env:advance(0.25)
		if app.cadence:pendingResolves() == 0 then
			break
		end
	end
	app.cadence:flushResolves()
end


return Prelude
