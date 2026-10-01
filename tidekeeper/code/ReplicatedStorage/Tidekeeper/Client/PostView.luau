--!nonstrict
-- ReplicatedStorage/Tidekeeper/Client/PostView (ModuleScript)
--
-- Shelves, stock and prices. Layer: Client. Pure.
--
-- THE CLIENT IS NEVER AUTHORITATIVE (doc 01 section 4). This module renders
-- what the server said and builds the INTEGER payloads that ask the server to
-- change something. It never computes what a thing is worth, never decides
-- whether a price is allowed, and never updates its own copy optimistically
-- and hopes. The server's next snapshot is the truth; anything else is how a
-- client ends up displaying coin the player does not have.

local Post = require(script.Parent.Parent.Domain.Post)
local Format = require(script.Parent.Format)
local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)

local PostView = {}

-- Build the shelf rows from a snapshot. `snapshot.shelves` is the array of
-- `{ id, price }` the server sent; empty slots up to `maxShelves` are
-- rendered as placeholders so the player can see what tiering up would buy.
function PostView.build(snapshot)
	local rows = {}
	local shelves = snapshot.shelves or {}
	local maxShelves = snapshot.maxShelves or Post.maxShelves(snapshot.tier or 1)

	for i = 1, maxShelves do
		local shelf = shelves[i]
		if shelf ~= nil and shelf.id ~= nil and shelf.id > 0 then
			rows[i] = {
				slot = i,
				findId = shelf.id,
				name = Format.findName(shelf.id),
				price = shelf.price or 0,
				priceText = Format.label("POST_COIN", { shelf.price or 0 }),
				empty = false,
			}
		else
			rows[i] = {
				slot = i,
				findId = 0,
				name = Format.label("POST_EMPTY_SHELF"),
				price = 0,
				priceText = "",
				empty = true,
			}
		end
	end

	return {
		rows = rows,
		tierText = Format.label("POST_TIER", { snapshot.tier or 1 }),
		shelfText = Format.label("POST_SHELVES", { snapshot.shelfCount or #shelves, maxShelves }),
		stockText = Format.label("POST_STOCK", { snapshot.stock or 0 }),
		coinText = Format.label("POST_COIN", { snapshot.coin or 0 }),
		renownText = Format.label("POST_RENOWN", { snapshot.renown or 0 }),
		-- The label on the price field of the arrange control. Arranging is
		-- the one place a player types a number, and an unlabelled number
		-- box is a guess.
		priceLabel = Format.label("POST_SET_PRICE"),
	}
end

-- The payload for RF_Arrange. Integers only, and clamped here so an obviously
-- impossible request never leaves the device -- not because the server trusts
-- us (it re-checks everything) but because a rejected round trip costs the
-- player a second for nothing.
--
-- TWO BUGS LIVED HERE UNTIL ITERATION 9, AND ONLY BECAUSE NOTHING SENT IT.
-- The key was `find`; `SPEC_ARRANGE` has always called it `findId`, and the
-- spec is strict, so every arrange this function could ever have built would
-- have been rejected by the server as malformed. The clamp was also wrong:
-- it used the u32 ceiling of the storage format (4294967295) rather than
-- `EconomyConfig.MAX_PRICE` (4294967), the ceiling the contract actually
-- enforces -- a thousand times too generous.
--
-- Clamping client-side is not the server trusting us: the server re-checks
-- everything. It is so that an obviously impossible request never costs the
-- player a round trip. That only works if the client clamps to the SAME
-- number the server does, which is why the constant is imported rather than
-- written out.
function PostView.arrangePayload(seq, slot, findId, price)
	local p = math.floor(price or 0)
	if p < 0 then
		p = 0
	elseif p > EconomyConfig.MAX_PRICE then
		p = EconomyConfig.MAX_PRICE
	end
	return {
		seq = seq,
		slot = math.floor(slot or 0),
		findId = math.floor(findId or 0),
		price = p,
	}
end

return PostView
