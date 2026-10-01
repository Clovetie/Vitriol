--!nonstrict
-- ServerScriptService/Tidekeeper/RemoteHandlers/PostHandler (ModuleScript)
--
-- `RF_Arrange` (shelve a find at a price), `RF_SetOrders` (upload the
-- standing-orders program), `RF_Comb` (work a comb node).
--
-- THE SHAPE OF EVERY HANDLER HERE IS: accept -> resolve state -> ask the
-- DOMAIN -> mark dirty. The domain module returns `(false, message)` for
-- anything illegal, so the handler never re-implements a rule; if a price
-- cap is wrong it is wrong in `Post.setShelf` and it is wrong in the offline
-- resolver too, which is exactly what we want. A validation rule that exists
-- only at the network edge is a rule the resolver does not enforce, and the
-- resolver runs on eight hours of absence with nobody watching.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local NetContract = require(Tidekeeper.Shared.NetContract)
local EconomyConfig = require(Tidekeeper.Config.EconomyConfig)
local Hash = require(Tidekeeper.Lib.Hash)
local RNG = require(Tidekeeper.Lib.RNG)
local Tide = require(Tidekeeper.Lib.Tide)
local Post = require(Tidekeeper.Domain.Post)
local Orders = require(Tidekeeper.Domain.Orders)

local PostHandler = {}


-- A comb node yields once per tide epoch. Not a timer in seconds: the tide
-- is the clock for everything in this game, and a node that refreshes on a
-- private 90-second cooldown would be the one system that does not answer to
-- it (doc 02 section 3).
local function combKey(zoneId, nodeId)
	return zoneId * 64 + nodeId
end

function PostHandler.bind(app)
	if app.remotes == nil then
		return
	end
	local arrange = app.remotes[NetContract.RF_ARRANGE]
	if arrange ~= nil then
		arrange.OnServerInvoke = function(player, payload)
			return PostHandler.arrange(app, player, payload)
		end
	end
	local orders = app.remotes[NetContract.RF_SET_ORDERS]
	if orders ~= nil then
		orders.OnServerInvoke = function(player, payload)
			return PostHandler.setOrders(app, player, payload)
		end
	end
	local comb = app.remotes[NetContract.RF_COMB]
	if comb ~= nil then
		comb.OnServerInvoke = function(player, payload)
			return PostHandler.comb(app, player, payload)
		end
	end
	local upgrade = app.remotes[NetContract.RF_UPGRADE]
	if upgrade ~= nil then
		upgrade.OnServerInvoke = function(player, payload)
			return PostHandler.upgrade(app, player, payload)
		end
	end
end

local function begin(app, player, name, payload)
	local userId = player.UserId
	local ok, why = NetContract.accept(app.guard, userId, name, payload, app.clock())
	if not ok then
		app.logger("PostHandler", "rejected " .. name .. " from " .. tostring(userId) .. ": " .. tostring(why))
		return nil, { status = NetContract.E_REJECTED }
	end
	local S = app.posts:get(userId)
	if S == nil then
		return nil, { status = NetContract.E_NO_POST }
	end
	return S, nil
end

-- ------------------------------------------------------------- arrange

function PostHandler.arrange(app, player, payload)
	local S, failure = begin(app, player, NetContract.RF_ARRANGE, payload)
	if S == nil then
		return failure
	end
	local userId = player.UserId

	if payload.findId == 0 then
		local cleared = Post.clearShelf(S, payload.slot)
		if not cleared then
			return { status = NetContract.E_ILLEGAL }
		end
		app.posts:markDirty(userId)
		return { status = NetContract.OK, shelfCount = Post.shelfCount(S) }
	end

	-- You may only shelve what you actually hold. This is the check that the
	-- schema cannot express and that the client must never be trusted with.
	if Post.stockOf(S, payload.findId) <= 0 then
		return { status = NetContract.E_ILLEGAL }
	end
	local ok, why = Post.setShelf(S, payload.slot, payload.findId, payload.price)
	if not ok then
		app.logger("PostHandler", "illegal arrange from " .. tostring(userId) .. ": " .. tostring(why))
		return { status = NetContract.E_ILLEGAL }
	end
	app.posts:markDirty(userId)
	return { status = NetContract.OK, shelfCount = Post.shelfCount(S) }
end

-- ------------------------------------------------------------- upgrade

-- Buy the next tier. The payload carries nothing but a sequence number: the
-- server knows which post this is, the post knows its own tier, and the cost
-- is server-side config. There is nothing here for a client to forge.
--
-- This is the remote that did not exist until iteration 7, which is why no
-- post in the game had ever been anything other than tier 1.
function PostHandler.upgrade(app, player, payload)
	local S, failure = begin(app, player, NetContract.RF_UPGRADE, payload)
	if S == nil then
		return failure
	end
	local userId = player.UserId

	local ok, why = Post.promote(S)
	if not ok then
		app.logger("PostHandler", "refused upgrade for " .. tostring(userId) .. ": " .. tostring(why))
		return { status = NetContract.E_ILLEGAL }
	end
	app.posts:markDirty(userId)
	return { status = NetContract.OK, tier = S.tier, coin = S.coin, nextCost = Post.promotionCost(S) }
end

-- ------------------------------------------------------------ setOrders

-- The client uploads BYTES, not a rule tree (doc 01 section 4). The only
-- thing that can produce those bytes is `Orders.encode`, and `Orders.decode`
-- rejects anything else, so the attack surface is a byte array with a length
-- cap rather than a recursive structure with a depth cap.
function PostHandler.setOrders(app, player, payload)
	local S, failure = begin(app, player, NetContract.RF_SET_ORDERS, payload)
	if S == nil then
		return failure
	end
	local userId = player.UserId

	local program, why = Orders.decode(payload.bytes, 1, #payload.bytes)
	if program == nil then
		app.logger("PostHandler", "undecodable orders from " .. tostring(userId) .. ": " .. tostring(why))
		return { status = NetContract.E_ILLEGAL }
	end
	-- Tier caps the rule count, so validation needs the SERVER's idea of the
	-- player's tier and never the client's.
	local ok, badWhy = Orders.validate(program, S.tier)
	if not ok then
		app.logger("PostHandler", "invalid orders from " .. tostring(userId) .. ": " .. tostring(badWhy))
		return { status = NetContract.E_ILLEGAL }
	end
	S.orders = program
	app.posts:markDirty(userId)
	return { status = NetContract.OK, rules = #program.rules, bytes = Orders.byteLength(program) }
end

-- ---------------------------------------------------------------- comb

-- Combing the tide line is the one active thing you do while present. It is
-- deterministic in (salt, zone, node, epoch): two players combing the same
-- node in the same epoch is fine, but the SAME player cannot reroll it by
-- leaving and coming back, because the roll does not depend on when they
-- asked.
function PostHandler.comb(app, player, payload)
	local S, failure = begin(app, player, NetContract.RF_COMB, payload)
	if S == nil then
		return failure
	end
	local userId = player.UserId
	local epoch = Tide.epoch(app.clock())

	local key = combKey(payload.zoneId, payload.nodeId)
	-- A node regrows over COMB_RESPAWN_EPOCHS tide epochs, not on a private
	-- timer in seconds. Everything in this game answers to the tide, and a
	-- node that refreshed every 90 seconds would be the one system that
	-- rewarded sitting still.
	local lastEpoch = S.comb[payload.nodeId]
	if lastEpoch ~= nil and lastEpoch > 0 and epoch - lastEpoch < EconomyConfig.COMB_RESPAWN_EPOCHS then
		return { status = NetContract.E_COOLDOWN, epoch = epoch, readyAt = lastEpoch + EconomyConfig.COMB_RESPAWN_EPOCHS }
	end

	-- The tide gates the zone. Zone 1 is the tide line itself: it only
	-- exists at low water. This is the tide being load-bearing rather than
	-- decorative -- there is a thing you can only do at certain real hours,
	-- and the game tells you when they are rather than making you guess.
	local state = Tide.stateForEpoch(epoch)
	if payload.zoneId == 1 and state ~= "LOW" then
		return { status = NetContract.E_ILLEGAL }
	end

	local rng = RNG.new(Hash.mix(S.salt, key, epoch))
	-- Only ids with a row in the finds table; `MAX_FIND_ID` is the schema
	-- ceiling, `knownFindCount` is what actually exists this version.
	local findId = 1 + rng:range(0, Post.knownFindCount() - 1)
	local qty = 1 + rng:range(0, 2)
	-- `addStock` returns the quantity ACTUALLY added, which is 0 when the
	-- store is full or the stack is capped. Zero is not an error the player
	-- caused, so it reports as NetContract.OK with qty 0 and the client says the shelf
	-- is full.
	local added = Post.addStock(S, findId, qty)
	S.comb[payload.nodeId] = epoch
	app.posts:markDirty(userId)
	return { status = NetContract.OK, findId = findId, qty = added, epoch = epoch }
end

PostHandler.OK = NetContract.OK
PostHandler.E_REJECTED = NetContract.E_REJECTED
PostHandler.E_NO_POST = NetContract.E_NO_POST
PostHandler.E_ILLEGAL = NetContract.E_ILLEGAL
PostHandler.E_COOLDOWN = NetContract.E_COOLDOWN

return PostHandler
