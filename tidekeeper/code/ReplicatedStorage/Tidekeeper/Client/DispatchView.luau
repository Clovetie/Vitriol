--!nonstrict
-- ReplicatedStorage/Tidekeeper/Client/DispatchView (ModuleScript)
--
-- Sending your own Drifter out. Layer: Client. Pure.
--
-- This is the screen where the player becomes somebody else's content, and it
-- is the one screen where the safety design is load-bearing rather than
-- theoretical (doc 13 section 2):
--
--   * the player picks a LETTER ID from `LetterView`, never types;
--   * the recipient is one of three ANONYMOUS slots -- no name, no user id, no
--     way to target a specific person, and therefore no way to use the
--     mechanic to harass one;
--   * cargo is find ids and quantities the server already knows the player
--     owns.
--
-- Everything that crosses the wire from here is a small integer. There is no
-- text to filter, which is why the game has no moderation hot path at all.

local Format = require(script.Parent.Format)
local LetterView = require(script.Parent.LetterView)
local LettersConfig = require(script.Parent.Parent.Config.LettersConfig)

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
		cargoTitle = Format.label("DISPATCH_CARGO"),
		-- The letter picker, by id. `Strings.PHRASE` used to be handed over
		-- here -- 12 canned lines from the design that preceded letters.
		-- Iteration 7 gave drifters 120 real letters and `letterId`; the
		-- phrase list stayed wired to the renderer for three iterations
		-- afterwards, offering the player a choice the wire could no longer
		-- carry. The dead-content scan found its label and the table went
		-- with it.
		letterCategories = LetterView.categories(),
		blocked = alreadyOut == true,
		blockedText = alreadyOut and Format.label("DISPATCH_ALREADY") or nil,
		sentText = Format.label("DISPATCH_SENT"),
	}
end

-- The RF_Dispatch payload. Integers only, and the letter is an ID, never text.
--
-- THIS FUNCTION BUILT A PAYLOAD THE SERVER COULD NEVER HAVE ACCEPTED, in
-- three separate ways, from iteration 6 until iteration 9 -- and nothing
-- noticed because no client code ever sent one. Against `SPEC_DISPATCH`:
--
--   * it sent `slot`, the spec wants `targets`, an ARRAY of 1..3 indices
--     (you may send one drifter to several destinations);
--   * it sent `phrase`, indexing `Strings.PHRASE`; the spec wants `letterId`,
--     indexing the 120 letters in LettersConfig. Two different tables with
--     two different ceilings;
--   * cargo elements were tables `{id, qty}`; the spec wants plain find ids,
--     because quantity is not the client's to choose -- the server moves what
--     the shelf actually holds.
--
-- The spec is strict, so each of these alone was a guaranteed rejection.
-- Iteration 9's conformance test now validates this function's output against
-- the server's own schema, so the three halves cannot drift apart again.
function DispatchView.payload(seq, targets, letterId, cargo)
	local out = {}
	local list = type(targets) == "table" and targets or { targets }
	for i = 1, math.min(DispatchView.SLOT_COUNT, #list) do
		local t = math.floor(list[i] or 0)
		if t >= 1 and t <= DispatchView.SLOT_COUNT then
			out[#out + 1] = t
		end
	end
	if #out == 0 then
		out[1] = 1
	end

	local items = {}
	for i = 1, math.min(DispatchView.MAX_CARGO, #cargo) do
		local entry = cargo[i]
		-- Accept either a plain id or the {findId=} shape the picker builds,
		-- and put a plain id on the wire either way.
		local id = type(entry) == "table" and (entry.findId or entry.id) or entry
		items[i] = math.floor(id or 0)
	end

	local letter = math.floor(letterId or 0)
	if letter < 0 or letter > LettersConfig.MAX_LETTER_ID then
		letter = 0
	end

	return {
		seq = seq,
		targets = out,
		letterId = letter,
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
