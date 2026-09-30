--!nonstrict
-- ReplicatedStorage/Tidekeeper/Client/ClientBootstrap (ModuleScript)
--
-- The client's composition root -- the mirror of `Services/Bootstrap` (D13).
--
-- Layer: Client. It takes EVERY dependency as an argument: the remotes table,
-- a clock, a player id, a logger. It calls `game:GetService` exactly never.
-- `Main.client.luau` does that once, at the edge, and passes the results in.
--
-- WHY THE CLIENT GETS THE SAME TREATMENT AS THE SERVER
-- ----------------------------------------------------
-- Iteration 3 learned that the bugs live in the layer that talks to the
-- platform, and that the only way to test that layer is to be able to
-- substitute the platform underneath it. The same argument applies here: the
-- interesting client bugs are "the snapshot arrived before the player
-- object", "the remote timed out and the screen kept the old number", and
-- "template 250 has no prose". None of those need a GUI to reproduce, and
-- none of them are reachable if the client can only be constructed by
-- joining a real game.
--
-- So: one readable function, everything injected, no globals, and the session
-- suite builds one over the fake DataModel.

local Format = require(script.Parent.Format)
local LedgerView = require(script.Parent.LedgerView)
local TideView = require(script.Parent.TideView)
local PostView = require(script.Parent.PostView)
local OrdersView = require(script.Parent.OrdersView)
local DispatchView = require(script.Parent.DispatchView)
local NetContract = require(script.Parent.Parent.Shared.NetContract)

local ClientBootstrap = {}
ClientBootstrap.__index = ClientBootstrap

-- Screens. The client is a state machine over six of them and nothing else
-- (doc 08 section 1); anything that does not fit in one does not exist.
ClientBootstrap.SCREEN_WORLD = 1
ClientBootstrap.SCREEN_LEDGER = 2
ClientBootstrap.SCREEN_POST = 3
ClientBootstrap.SCREEN_ORDERS = 4
ClientBootstrap.SCREEN_CHART = 5
ClientBootstrap.SCREEN_ALMANAC = 6

--[[
	opts:
	  remotes    { [name] = RemoteFunction|RemoteEvent }   required
	  clock      () -> number, unix seconds                required
	  userId     number                                    required
	  logger     (scope, message) -> ()                    optional
	  names      { [actorId] = string }                    optional
	  renderer   an object with :draw(state) -> ()         optional
]]
function ClientBootstrap.start(opts)
	assert(type(opts) == "table", "ClientBootstrap.start: opts table required")
	assert(type(opts.clock) == "function", "ClientBootstrap.start: a clock function is required")

	local self = setmetatable({}, ClientBootstrap)
	self.remotes = opts.remotes or {}
	self.clock = opts.clock
	self.userId = opts.userId or 0
	self.logger = opts.logger or function() end
	self.names = opts.names or {}
	self.renderer = opts.renderer

	self.screen = ClientBootstrap.SCREEN_WORLD
	self.seq = 0
	self.snapshot = nil
	self.ledger = nil
	self.entries = {}
	self.dirty = true
	self.stats = {
		invokes = 0,
		failures = 0,
		snapshots = 0,
		ledgerBatches = 0,
		renders = 0,
	}

	self.views = {
		ledger = LedgerView,
		tide = TideView,
		post = PostView,
		orders = OrdersView,
		dispatch = DispatchView,
		format = Format,
	}

	return self
end

function ClientBootstrap:nextSeq()
	self.seq = self.seq + 1
	return self.seq
end

-- Every client -> server call goes through here, so retry policy, sequence
-- numbers and failure counting exist in ONE place. A handler that invokes a
-- remote directly is a handler whose failures nobody counts.
function ClientBootstrap:invoke(name, payload)
	local remote = self.remotes[name]
	if remote == nil then
		self.stats.failures = self.stats.failures + 1
		return nil, "no remote"
	end
	self.stats.invokes = self.stats.invokes + 1
	local ok, result = pcall(function()
		return remote:InvokeServer(payload)
	end)
	if not ok then
		self.stats.failures = self.stats.failures + 1
		self.logger("Client", "remote " .. name .. " failed: " .. tostring(result))
		return nil, tostring(result)
	end
	return result
end

-- Ask for the session. The reply is the post snapshot and the Ledger.
function ClientBootstrap:requestSession()
	local reply = self:invoke(NetContract.RF_SESSION, { seq = self:nextSeq() })
	if reply == nil then
		return nil, Format.label("ERR_OFFLINE")
	end
	if reply.status ~= 0 then
		return nil, self:statusText(reply.status)
	end
	self:applySnapshot(reply)
	return reply
end

function ClientBootstrap:statusText(status)
	if status == 1 then
		return Format.label("ERR_REJECTED")
	elseif status == 2 then
		return Format.label("ERR_NO_POST")
	end
	return Format.label("ERR_OFFLINE")
end

function ClientBootstrap:applySnapshot(snapshot)
	self.snapshot = snapshot
	self.stats.snapshots = self.stats.snapshots + 1
	self.dirty = true
end

-- RE_LedgerBatch arrives in pages. Accumulate, then build once -- building the
-- model per page would re-render the whole replay for every page of a
-- 27-epoch catch-up.
function ClientBootstrap:applyLedgerBatch(entries)
	for i = 1, #entries do
		self.entries[#self.entries + 1] = entries[i]
	end
	self.stats.ledgerBatches = self.stats.ledgerBatches + 1
	self.ledger = nil
	self.dirty = true
end

function ClientBootstrap:ledgerModel(withSilhouettes)
	if self.ledger == nil then
		self.ledger = LedgerView.build(self.entries, self.names, { withSilhouettes = withSilhouettes })
	end
	return self.ledger
end

function ClientBootstrap:setScreen(screen)
	if self.screen ~= screen then
		self.screen = screen
		self.dirty = true
	end
	return self.screen
end

-- The whole render model for the current screen. Pure: given the same
-- snapshot and the same `now`, it returns the same table every time, which is
-- what makes it assertable in a test with no GUI anywhere.
function ClientBootstrap:render(now)
	local t = now or self.clock()
	local model = {
		screen = self.screen,
		tide = TideView.header(t),
	}
	if self.screen == ClientBootstrap.SCREEN_LEDGER then
		model.ledger = self:ledgerModel(true)
		model.highlight = LedgerView.highlight(model.ledger)
	elseif self.screen == ClientBootstrap.SCREEN_POST and self.snapshot ~= nil then
		model.post = PostView.build(self.snapshot)
	elseif self.screen == ClientBootstrap.SCREEN_ORDERS and self.snapshot ~= nil then
		model.orders = OrdersView.build(self.snapshot.orders, self.snapshot.tier)
	end
	self.stats.renders = self.stats.renders + 1
	self.dirty = false
	return model
end

-- ONE tick, driven by the single connection in Main.client.luau. The client
-- redraws only when something changed: a Ledger that re-renders every frame
-- is 60 string builds a second on a phone, for a screen that changes once
-- every 1.6 seconds.
function ClientBootstrap:step(now)
	if not self.dirty then
		return nil
	end
	local model = self:render(now)
	if self.renderer ~= nil then
		self.renderer:draw(model)
	end
	return model
end

return ClientBootstrap
