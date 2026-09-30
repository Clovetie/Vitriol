--!nonstrict
-- ServerScriptService/Tidekeeper/RemoteHandlers/DebugHandler (ModuleScript)
--
-- Studio-only diagnostics. `bind` returns immediately in a live server, so
-- there is no remote to find and nothing to call.
--
-- This is not a "cheat menu behind a flag". There is NO REMOTE CREATED at
-- all outside Studio -- the check happens before the binding, not inside the
-- handler -- because a debug remote that exists in production is a debug
-- remote somebody will invoke, and `RunService:IsStudio()` returning false
-- on the client is not something the server can rely on.
--
-- What it does expose, in Studio, is the numbers that the documentation
-- claims: requests per session, slot timings, resident counts. Being able to
-- check a claim in ten seconds is the difference between documentation that
-- stays true and documentation that rots.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local Tide = require(Tidekeeper.Lib.Tide)

local DebugHandler = {}

function DebugHandler.bind(app)
	-- determinism-scan: allow runservice IsStudio only, no connection is made; the Studio check must happen before the remote is created
	local runService = game:GetService("RunService")
	if not runService:IsStudio() then
		return false
	end
	-- The dump is printed server-side rather than returned to a client, so
	-- even in Studio there is no data path from the server to a player here.
	app.debugDump = function()
		return DebugHandler.snapshot(app)
	end
	return true
end

function DebugHandler.snapshot(app)
	local stats = app.stats()
	local now = app.clock()
	return {
		epoch = Tide.epoch(now),
		tide = Tide.state(now),
		resident = app.posts:residentCount(),
		pendingResolves = app.cadence:pendingResolves(),
		dataRequests = app.data:totalRequests(),
		stats = stats,
	}
end

-- Prints the one table anybody actually wants at 2am: how many platform
-- requests this server has made, and per session.
function DebugHandler.print(app)
	local snap = DebugHandler.snapshot(app)
	local sessions = math.max(1, snap.stats.players.joins)
	print(string.format(
		"[Tidekeeper/Debug] epoch %d tide %s resident %d | DataStore %d (%.2f/session) | pending %d",
		snap.epoch,
		tostring(snap.tide),
		snap.resident,
		snap.dataRequests,
		snap.dataRequests / sessions,
		snap.pendingResolves
	))
	return snap
end

return DebugHandler
