--!nonstrict
-- ServerScriptService/Tidekeeper/Main (Script)
--
-- THE ONLY SERVER SCRIPT IN THE GAME. Everything else is a ModuleScript,
-- which means everything else is requireable from the test harness, and the
-- harness is the only reason this game can claim any of the numbers in its
-- documentation.
--
-- This file is deliberately almost empty. It composes, it binds, it closes.
-- If you find yourself adding game logic here, the logic belongs in a
-- service and the service belongs in Bootstrap.

local ServerStorage = game:GetService("ServerStorage")
local Root = ServerStorage:WaitForChild("Tidekeeper")

local Bootstrap = require(Root.Services.Bootstrap)
local Profiler = require(Root.Diagnostics.Profiler)
local BudgetMeter = require(Root.Diagnostics.BudgetMeter)
local SessionHandler = require(Root.RemoteHandlers.SessionHandler)
local HistoryHandler = require(Root.RemoteHandlers.HistoryHandler)
local PostHandler = require(Root.RemoteHandlers.PostHandler)
local DispatchHandler = require(Root.RemoteHandlers.DispatchHandler)
local DebugHandler = require(Root.RemoteHandlers.DebugHandler)

local profiler = Profiler.new()

local app = Bootstrap.start({
	profiler = profiler,
})
app.profiler = profiler
app.meter = BudgetMeter.new(app)

SessionHandler.bind(app)
HistoryHandler.bind(app)
PostHandler.bind(app)
DispatchHandler.bind(app)
DebugHandler.bind(app)

-- The BudgetMeter is the thing that tells us, in production, whether the
-- five-requests-per-session claim survived contact with real players. It
-- prints on the `slow` slot at a low rate; the numbers it prints are the
-- same ones the session harness asserts against.
app.cadence:register("slow", "budget.report", function()
	app.meter:maybeReport()
end)

-- 30 seconds, and a full server is 50 saves. The adapter's budget waiter and
-- the per-server request queue (30 deep) are what keep this from turning
-- into a burst of throttle errors, so DO NOT "optimise" this into a parallel
-- loop of task.spawn.
game:BindToClose(function()
	app.shutdown()
	app.meter:report("shutdown")
end)

print("[Tidekeeper] server up")
