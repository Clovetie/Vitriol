--!nonstrict
-- ServerScriptService/Tidekeeper/RemoteHandlers/SessionHandler (ModuleScript)
--
-- `RF_Session` -- the client asking "what is my post, and what happened?".
--
-- EVERY HANDLER IN THIS FOLDER OBEYS THE SAME FOUR RULES (doc 01 section 4):
--
--   1. `NetContract.accept` FIRST, before touching any state. It checks the
--      rate limit, the sequence number and the schema in that order, and
--      every rejection is counted. A handler that validates halfway through
--      its work has already done half the work for an attacker.
--   2. The payload is INTEGERS ONLY. No strings cross this boundary in
--      either direction (doc 13 section 2), which is provable -- see
--      `NetContract.hasNoStringFields`, asserted by the smoke test.
--   3. The client is never trusted for anything the server can derive. It
--      sends "shelf 3, find 41, price 12"; it never sends its coin balance,
--      its tier, or what a thing is worth.
--   4. The response is a small table of integers and a status code. Error
--      text is for the server log; the client owns the words.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local NetContract = require(Tidekeeper.Shared.NetContract)
local Tide = require(Tidekeeper.Lib.Tide)
local Post = require(Tidekeeper.Domain.Post)

local SessionHandler = {}

-- Status codes. The client maps these to sentences.

function SessionHandler.bind(app)
	if app.remotes == nil then
		return
	end
	local remote = app.remotes[NetContract.RF_SESSION]
	if remote == nil then
		return
	end
	remote.OnServerInvoke = function(player, payload)
		return SessionHandler.handle(app, player, payload)
	end
end

-- Split out from `bind` so the session harness can call it directly without
-- a RemoteFunction in the middle.
function SessionHandler.handle(app, player, payload)
	local userId = player.UserId
	local now = app.clock()
	local ok, why = NetContract.accept(app.guard, userId, NetContract.RF_SESSION, payload, now)
	if not ok then
		app.logger("SessionHandler", "rejected RF_Session from " .. tostring(userId) .. ": " .. tostring(why))
		return { status = NetContract.E_REJECTED }
	end

	local S = app.posts:get(userId)
	if S == nil then
		-- The join is still in flight, or it failed and the player was told
		-- to rejoin. Either way there is nothing to hand over, and INVENTING
		-- an empty post here is how save systems eat people's progress.
		return { status = NetContract.E_NO_POST }
	end

	local session = app.players:sessionOf(userId)
	return {
		status = NetContract.OK,
		tier = S.tier,
		season = S.season,
		current = S.current,
		coin = S.coin,
		renown = S.renown,
		epoch = Tide.epoch(now),
		resolvedAt = S.resolvedAt,
		-- NAME MEANS THE SAME THING ON BOTH SIDES OF THE WIRE.
		-- `shelves` was the shelf COUNT here and the shelf ARRAY in the
		-- domain (`S.shelves[i].id`), so PostView.build -- which reads the
		-- array, as the word implies -- indexed a number and threw. The
		-- count is now `shelfCount`; `shelves` is the array everywhere.
		shelfCount = Post.shelfCount(S),
		shelves = S.shelves,
		maxShelves = Post.maxShelves(S.tier),
		-- What the next tier costs, or nil at the top. The client must never
		-- compute this from its own copy of the table: a client showing a
		-- different price from the one charged is how a cozy game gets a
		-- reputation for lying. The server is the only place the number
		-- exists.
		nextCost = Post.promotionCost(S),
		stock = Post.totalStock(S),
		-- The 32-byte almanac bitset, for the almanac screen. Bytes, not a
		-- list of names: 200 find names would be 200 strings crossing the
		-- wire for a screen the player may never open, and the client
		-- already owns the names.
		almanac = S.almanac,
		chunks = session and session.chunkCount or 0,
		pending = app.cadence:pendingResolves(),
	}
end

SessionHandler.OK = NetContract.OK
SessionHandler.E_REJECTED = NetContract.E_REJECTED
SessionHandler.E_NO_POST = NetContract.E_NO_POST

return SessionHandler
