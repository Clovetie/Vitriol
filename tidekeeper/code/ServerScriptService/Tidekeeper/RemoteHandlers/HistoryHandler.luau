--!nonstrict
-- ServerScriptService/Tidekeeper/RemoteHandlers/HistoryHandler (ModuleScript)
--
-- `RF_History` -- the client asking "what happened before the last 200
-- things?".
--
-- WHY THIS EXISTS (OD22)
-- ----------------------
-- The Ledger holds MAX_LEDGER_RESIDENT (200) entries in the post blob.
-- Everything older was archived to a page by `LedgerService:flushPending`,
-- and `DataStoreAdapter:loadLedgerPage` was called by NOTHING. Nine
-- iterations of entries were written to DataStore and could not be read back
-- by any code path that existed.
--
-- That is the worst possible bug for this particular game rather than merely
-- a missing feature. Doc 00's first pillar is "absence is content": the whole
-- promise is that you come back and find out what happened while you were
-- gone. A Ledger that silently forgets is the game failing at the one thing
-- it says it is for.
--
-- It obeys the same four rules as every other handler in this folder; see
-- the header of SessionHandler.
--
-- NOTE ON COST. Each call is one index read plus one page read, which is why
-- RF_History is throttled harder than the action remotes (2 burst, 10 per
-- minute). Paging is a deliberate tap, not a scroll.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local NetContract = require(Tidekeeper.Shared.NetContract)

local HistoryHandler = {}

function HistoryHandler.bind(app)
	if app.remotes == nil then
		return
	end
	local remote = app.remotes[NetContract.RF_HISTORY]
	if remote == nil then
		return
	end
	remote.OnServerInvoke = function(player, payload)
		return HistoryHandler.handle(app, player, payload)
	end
end

function HistoryHandler.handle(app, player, payload)
	local userId = player.UserId
	local now = app.clock()
	local ok, why = NetContract.accept(app.guard, userId, NetContract.RF_HISTORY, payload, now)
	if not ok then
		app.logger("HistoryHandler", "rejected RF_History from " .. tostring(userId) .. ": " .. tostring(why))
		return { status = NetContract.E_REJECTED }
	end

	-- A player with no post in memory has no business reading an archive:
	-- the join may still be in flight, and answering would mean reading
	-- DataStore for somebody who is not here yet.
	if app.posts:get(userId) == nil then
		return { status = NetContract.E_NO_POST }
	end

	local entries, nextCursor, total = app.ledger:history(userId, payload.cursor)

	-- `nextCursor` nil means "that was the oldest page". The client needs to
	-- be able to tell that apart from "this page happened to be empty", so
	-- `more` is explicit rather than inferred from the entry count.
	return {
		status = NetContract.OK,
		cursor = payload.cursor,
		entries = entries,
		more = nextCursor ~= nil,
		nextCursor = nextCursor or 0,
		pages = total,
	}
end

return HistoryHandler
