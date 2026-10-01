--!nonstrict
-- ServerScriptService/Tidekeeper/RemoteHandlers/DispatchHandler (ModuleScript)
--
-- `RF_Dispatch` -- sending YOUR traveller out with a letter and cargo.
--
-- THE PRIVACY DESIGN, WHICH IS THE INTERESTING PART
-- -------------------------------------------------
-- A player never names a destination. The exchange offers up to three
-- anonymous slots and the client says "the second one". The client never
-- learns whose post it was, before or after; the Ledger entry that comes
-- back names the host only once the visit has actually happened, and only
-- to the person whose traveller it was.
--
-- That rules out, by construction and not by moderation:
--   * targeted harassment (you cannot pick a person);
--   * alt-account farming (you cannot pick your own second account);
--   * the "friend circles trade with each other" economy collapse that
--     every asynchronous trading game gets.
--
-- The letter is a NUMBER -- an index into a fixed authored phrase list
-- (doc 13 section 2). There is no free text anywhere in TIDEKEEPER, so
-- there is no text filtering on any hot path and no way to smuggle a
-- message. The cost is expressiveness; the benefit is that a nine-year-old
-- can use this system unsupervised and the worst thing a stranger can send
-- them is phrase 41.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local NetContract = require(Tidekeeper.Shared.NetContract)
local DrifterConfig = require(Tidekeeper.Config.DrifterConfig)
local Tide = require(Tidekeeper.Lib.Tide)
local LettersConfig = require(Tidekeeper.Config.LettersConfig)
local Post = require(Tidekeeper.Domain.Post)

local DispatchHandler = {}


-- One traveller out at a time, per epoch. The scarcity is what makes the
-- choice mean anything, and it is also what bounds the exchange's write
-- rate to one publish per player per epoch.
function DispatchHandler.bind(app)
	if app.remotes == nil then
		return
	end
	local remote = app.remotes[NetContract.RF_DISPATCH]
	if remote == nil then
		return
	end
	remote.OnServerInvoke = function(player, payload)
		return DispatchHandler.handle(app, player, payload)
	end
end

function DispatchHandler.handle(app, player, payload)
	local userId = player.UserId
	local now = app.clock()
	local ok, why = NetContract.accept(app.guard, userId, NetContract.RF_DISPATCH, payload, now)
	if not ok then
		app.logger("DispatchHandler", "rejected RF_Dispatch from " .. tostring(userId) .. ": " .. tostring(why))
		return { status = NetContract.E_REJECTED }
	end
	local S = app.posts:get(userId)
	if S == nil then
		return { status = NetContract.E_NO_POST }
	end
	local epoch = Tide.epoch(now)
	if S.dispatchedAt ~= nil and S.dispatchedAt >= epoch then
		return { status = NetContract.E_ALREADY_OUT, epoch = epoch }
	end

	-- Cargo is validated against what is actually in the store. The client
	-- sends find ids it believes it holds; the server checks, and a mismatch
	-- is an illegal request rather than a silently-trimmed one, because a
	-- silently-trimmed request is indistinguishable from a working exploit.
	local cargo = payload.cargo
	if #cargo > DrifterConfig.MAX_CARGO then
		return { status = NetContract.E_ILLEGAL }
	end
	for i = 1, #cargo do
		if Post.stockOf(S, cargo[i]) <= 0 then
			return { status = NetContract.E_ILLEGAL }
		end
		for j = 1, i - 1 do
			if cargo[j] == cargo[i] then
				return { status = NetContract.E_ILLEGAL }
			end
		end
	end
	if payload.letterId > 0 and payload.letterId > DispatchHandler.MAX_LETTER_ID then
		return { status = NetContract.E_ILLEGAL }
	end

	-- The dispatch is recorded on the post and published at LOGOUT, not
	-- here. Publishing now would let a player dispatch, watch the exchange,
	-- and dispatch again; publishing at logout is also the only moment the
	-- Drifter's snapshot is final.
	S.dispatchedAt = epoch
	S.dispatchLetter = payload.letterId
	S.dispatchCargo = cargo
	app.posts:markDirty(userId)
	return { status = NetContract.OK, epoch = epoch, cargo = #cargo }
end

-- The authored phrase list lives in Config/LettersConfig, which is under
-- ReplicatedStorage and therefore visible to both sides. The server needs
-- the ceiling so it can reject a forged index.
--
-- This was hard-coded to 96 until iteration 7, while the real list did not
-- exist at all. Deriving it means the ceiling cannot drift from the content
-- again: add a phrase and the validator follows.
DispatchHandler.MAX_LETTER_ID = LettersConfig.MAX_LETTER_ID

DispatchHandler.OK = NetContract.OK
DispatchHandler.E_REJECTED = NetContract.E_REJECTED
DispatchHandler.E_NO_POST = NetContract.E_NO_POST
DispatchHandler.E_ILLEGAL = NetContract.E_ILLEGAL
DispatchHandler.E_ALREADY_OUT = NetContract.E_ALREADY_OUT

return DispatchHandler
