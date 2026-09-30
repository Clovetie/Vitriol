--!nonstrict
-- ReplicatedStorage/Tidekeeper/Client/DispatchView (ModuleScript)
--
-- Sending your own Drifter out. Layer: Client. Pure.
--
-- This is the screen where the player becomes somebody else's content, and it
-- is the one screen where the safety design is load-bearing rather than
-- theoretical (doc 13 section 2):
--
--   * the player picks a PHRASE INDEX from `Strings.PHRASE`, never types;
--   * the recipient is one of three ANONYMOUS slots -- no name, no user id, no
--     way to target a specific person, and therefore no way to use the
--     mechanic to harass one;
--   * cargo is find ids and quantities the server already knows the player
--     owns.
--
-- Everything that crosses the wire from here is a small integer. There is no
-- text to filter, which is why the game has no moderation hot path at all.

local Format = require(script.Parent.Format)
local Strings = require(script.Parent.Strings)

local DispatchView = {}

DispatchView.SLOT_COUNT = 3
DispatchView.MAX_CARGO = 4

-- The three destinations. They are deliberately characterised by CURRENT and
-- tide only -- a flavour of destination, not a person.
function DispatchView.build(slots, held, alreadyOut)
	local options = {}
	for i = 1, math.min(DispatchView.SLOT_COUNT, #slots) do
		local slot = slots[i]
		options[i] = {
			index = i,
			current = slot.current,
			label = Format.label("CHART_CURRENT", { slot.current }),
			-- No name. No id. Nothing that identifies a player.
			hint = Format.tideName(slot.tideCode or 0),
		}
	end

	local cargo = {}
	for i = 1, #held do
		local item = held[i]
		cargo[i] = {
			findId = item.id,
			name = Format.findName(item.id),
			available = item.qty,
		}
	end

	return {
		title = Format.label("DISPATCH_TITLE"),
		options = options,
		cargo = cargo,
		phrases = Strings.PHRASE,
		blocked = alreadyOut == true,
		blockedText = alreadyOut and Format.label("DISPATCH_ALREADY") or nil,
		sentText = Format.label("DISPATCH_SENT"),
	}
end

-- The RF_Dispatch payload. Integers only, and the phrase is an INDEX.
function DispatchView.payload(seq, slotIndex, phraseIndex, cargo)
	local items = {}
	for i = 1, math.min(DispatchView.MAX_CARGO, #cargo) do
		items[i] = { id = math.floor(cargo[i].findId or 0), qty = math.floor(cargo[i].qty or 0) }
	end
	local phrase = math.floor(phraseIndex or 0)
	if phrase < 0 or phrase > #Strings.PHRASE then
		phrase = 0
	end
	return {
		seq = seq,
		slot = math.floor(slotIndex or 0),
		phrase = phrase,
		cargo = items,
	}
end

-- Proves the claim above rather than asserting it in a comment: no value this
-- module puts on the wire is a string. Called by the session suite.
function DispatchView.payloadHasNoStrings(payload)
	for key, value in pairs(payload) do
		if type(key) == "string" and type(value) == "string" then
			return false, key
		end
		if type(value) == "table" then
			for k2, v2 in pairs(value) do
				if type(v2) == "string" then
					return false, tostring(key) .. "." .. tostring(k2)
				end
			end
		end
	end
	return true
end

return DispatchView
