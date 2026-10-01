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
local LetterView = require(script.Parent.LetterView)
local ChartView = require(script.Parent.ChartView)
local AlmanacView = require(script.Parent.AlmanacView)
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
	-- One action at a time; see :act.
	self.inFlight = false
	-- Archive pager state (OD22).
	self.historyCursor = nil
	self.historyMore = false
	self.historyPages = 0
	self.almanacPage = 1
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
		busy = 0,
		historyPages = 0,
	}

	self.views = {
		ledger = LedgerView,
		tide = TideView,
		post = PostView,
		orders = OrdersView,
		dispatch = DispatchView,
		letter = LetterView,
		chart = ChartView,
		almanac = AlmanacView,
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

-- ---------------------------------------------------------------- actions
--
-- THE CLIENT COULD NOT DO ANYTHING UNTIL ITERATION 9.
--
-- Six client -> server remotes existed. All six were bound on the server,
-- rate limited, schema checked and covered by session tests. The client
-- called exactly ONE of them, `RF_Session`, and then listened. Arranging a
-- shelf, combing the beach, setting orders, dispatching a drifter and buying
-- a tier -- every verb in the game -- had no path from a player's hands to
-- the server at all.
--
-- Nothing caught it because each half was complete and correct on its own:
-- the handlers are real and tested, the payload builders are real and
-- tested, and no check asked whether anybody ever CALLED one.
-- `tidekeeper-remote-scan.js` now asks exactly that.
--
-- Every action returns (reply, errorText). The error text is already
-- localised, so a caller can put it straight on the screen.

-- The scalar fields an action reply may carry back. `nextCost` is here
-- because the upgrade reply is the only place the new price appears, and a
-- stale price on the button is a lie the player can see.
ClientBootstrap.AUTHORITATIVE_FIELDS = { "tier", "coin", "renown", "nextCost", "shelfCount", "maxShelves", "stock" }

-- Shared tail: an action is a sequence number, an invoke, and a status that
-- is either zero or a sentence the player can read. Writing it five times
-- would be five chances to forget the status check.
function ClientBootstrap:act(remoteName, payload)
	-- ONE ACTION AT A TIME. `invoke` yields on a RemoteFunction, so a second
	-- tap while the first is still in flight would spend a second sequence
	-- number and race the first reply into the snapshot. The server's rate
	-- limiter would eventually refuse it, but it would refuse it as
	-- "rejected" -- a confusing word for "you tapped twice".
	if self.inFlight then
		self.stats.busy = self.stats.busy + 1
		return nil, Format.label("ERR_BUSY")
	end
	self.inFlight = true
	local reply = self:invoke(remoteName, payload)
	self.inFlight = false
	if reply == nil then
		return nil, Format.label("ERR_OFFLINE")
	end
	if reply.status ~= 0 then
		return nil, self:statusText(reply.status)
	end
	-- Fold whatever authoritative values came back into the snapshot, so the
	-- screen can never drift from the server's idea of the post. Only fields
	-- the reply actually carries are touched: an action that returns just a
	-- status leaves the snapshot alone rather than blanking it.
	local snap = self.snapshot
	if snap ~= nil then
		for _, key in ipairs(ClientBootstrap.AUTHORITATIVE_FIELDS) do
			if reply[key] ~= nil then
				snap[key] = reply[key]
			end
		end
	end
	self.dirty = true
	return reply
end

-- Put a find on a shelf, change its price, or clear the shelf with findId 0.
function ClientBootstrap:arrange(slot, findId, price)
	return self:act(NetContract.RF_ARRANGE, PostView.arrangePayload(self:nextSeq(), slot, findId, price))
end

-- Comb a node for finds.
function ClientBootstrap:comb(zoneId, nodeId)
	return self:act(NetContract.RF_COMB, {
		seq = self:nextSeq(),
		zoneId = math.floor(zoneId or 0),
		nodeId = math.floor(nodeId or 0),
	})
end

-- Replace the standing orders with a compiled program.
function ClientBootstrap:setOrders(program)
	return self:act(NetContract.RF_SET_ORDERS, OrdersView.setOrdersPayload(self:nextSeq(), program))
end

-- Send a drifter out, optionally carrying one of the 120 letters.
function ClientBootstrap:dispatch(targets, letterId, cargo)
	return self:act(NetContract.RF_DISPATCH, DispatchView.payload(self:nextSeq(), targets, letterId, cargo or {}))
end

-- Buy the next tier. The payload carries no arguments on purpose: the server
-- knows the post, the post knows its tier, and the cost is server-side
-- config. A payload naming a target tier or a price would be worth forging.
function ClientBootstrap:upgrade()
	local reply, why = self:act(NetContract.RF_UPGRADE, { seq = self:nextSeq() })
	if reply == nil then
		return nil, why
	end
	-- The tier changes now; the BUILDING arrives on the next low water. Say
	-- so, or the player presses the button, sees the coin leave and nothing
	-- else happen, and files it as a bug.
	return reply, nil, Format.label("UPGRADE_DONE")
end

-- What the upgrade button should say, and whether it can be pressed. Read
-- from the snapshot the server sent, never computed from a local copy of the
-- cost table -- the client showing a different price from the one charged is
-- how a cozy game gets a reputation for lying.
function ClientBootstrap:upgradeOffer()
	local snap = self.snapshot
	if snap == nil then
		return nil
	end
	local cost = snap.nextCost
	local tier = snap.tier or 1
	if cost == nil or cost <= 0 then
		return { tier = tier, affordable = false, maxed = true, text = Format.label("UPGRADE_MAXED") }
	end
	local coin = snap.coin or 0
	return {
		tier = tier,
		cost = cost,
		maxed = false,
		affordable = coin >= cost,
		text = Format.label("UPGRADE_OFFER", { tier + 1, cost }),
		shortfall = (coin < cost) and (cost - coin) or 0,
		-- Say how far short, not just "no". A number is a plan; a disabled
		-- button is a wall.
		shortText = (coin < cost) and Format.label("UPGRADE_SHORT", { cost - coin }) or nil,
	}
end

-- Read one page of archived Ledger entries (OD22). `cursor` counts back from
-- the newest archived page: 0 is the most recent, and nil/absent means
-- "start at the beginning of the archive".
--
-- The client never guesses how many pages there are. The server reports
-- `more`, and the pager stops when it is false -- which is also how the
-- screen knows to show the end-of-history line rather than an empty list
-- that looks like a loading bug.
function ClientBootstrap:history(cursor)
	local reply, why = self:act(NetContract.RF_HISTORY, {
		seq = self:nextSeq(),
		cursor = math.floor(cursor or 0),
	})
	if reply == nil then
		return nil, why
	end
	self.historyPages = reply.pages or 0
	self.historyMore = reply.more == true
	self.historyCursor = reply.more and reply.nextCursor or nil
	self.stats.historyPages = self.stats.historyPages + 1
	return reply
end

-- Turn a handler status code into a sentence. A pure mapping, as it should
-- always have been.
--
-- TWO THINGS WERE WRONG HERE BEFORE ITERATION 10.
--
-- First it LIED: only codes 1 and 2 were mapped and everything else fell
-- through to ERR_OFFLINE -- "Can't reach the post right now". So a comb
-- refused because the tide was wrong, or a node still regrowing, told the
-- player their connection had dropped. Nothing noticed, because until
-- iteration 9 no client code could reach a remote that returns those codes.
--
-- Then it needed the REMOTE NAME to disambiguate, because code 4 meant
-- E_COOLDOWN in PostHandler and E_ALREADY_OUT in DispatchHandler. That
-- worked, and it was the client carrying a workaround for an ambiguity in
-- the contract. OD23 fixed the contract instead: NetContract owns one status
-- enum with non-overlapping codes, E_ALREADY_OUT moved to 5, and this is a
-- mapping again with nothing to disambiguate.
--
-- An unknown code still reads as ERR_OFFLINE, which is the right default for
-- a client talking to a server newer than itself: say the post is
-- unreachable, never invent a reason.
local STATUS_LABEL = {
	[NetContract.E_REJECTED] = "ERR_REJECTED",
	[NetContract.E_NO_POST] = "ERR_NO_POST",
	[NetContract.E_ILLEGAL] = "ERR_ILLEGAL",
	[NetContract.E_COOLDOWN] = "ERR_COOLDOWN",
	[NetContract.E_ALREADY_OUT] = "DISPATCH_ALREADY",
}

function ClientBootstrap:statusText(status)
	return Format.label(STATUS_LABEL[status] or "ERR_OFFLINE")
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

-- THE NAVIGATION BAR.
--
-- Four tabs. TAB_WORLD, TAB_POST, TAB_CHART and TAB_ALMANAC were written in
-- iteration 5 and no code displayed any of them, which is to say the client
-- had six screens and no way to move between them. The dead-content scan
-- found the whole bar at once.
--
-- The Ledger and Orders are deliberately NOT tabs: the Ledger is pushed in
-- front of you when you arrive (doc 08 section 3) and Orders is reached from
-- the Post, because it is a thing you do to your post rather than a place.
ClientBootstrap.TABS = {
	{ screen = 1, label = "TAB_WORLD" },
	{ screen = 3, label = "TAB_POST" },
	{ screen = 5, label = "TAB_CHART" },
	{ screen = 6, label = "TAB_ALMANAC" },
}

function ClientBootstrap:tabs()
	local out = {}
	for i = 1, #ClientBootstrap.TABS do
		local tab = ClientBootstrap.TABS[i]
		out[i] = {
			screen = tab.screen,
			text = Format.label(tab.label),
			active = self.screen == tab.screen,
		}
	end
	return out
end

-- The whole render model for the current screen. Pure: given the same
-- snapshot and the same `now`, it returns the same table every time, which is
-- what makes it assertable in a test with no GUI anywhere.
function ClientBootstrap:render(now)
	local t = now or self.clock()
	local model = {
		screen = self.screen,
		tide = TideView.header(t),
		tabs = self:tabs(),
	}
	if self.screen == ClientBootstrap.SCREEN_LEDGER then
		model.ledger = self:ledgerModel(true)
		model.highlight = LedgerView.highlight(model.ledger)
	elseif self.screen == ClientBootstrap.SCREEN_POST and self.snapshot ~= nil then
		model.post = PostView.build(self.snapshot)
	elseif self.screen == ClientBootstrap.SCREEN_ORDERS and self.snapshot ~= nil then
		model.orders = OrdersView.build(self.snapshot.orders, self.snapshot.tier)
	elseif self.screen == ClientBootstrap.SCREEN_CHART and self.snapshot ~= nil then
		model.chart = ChartView.build(self.snapshot.tier, self.snapshot.current)
	elseif self.screen == ClientBootstrap.SCREEN_ALMANAC and self.snapshot ~= nil then
		model.almanac = AlmanacView.build(self.snapshot.almanac, self.almanacPage)
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
