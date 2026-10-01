--!nonstrict
-- ReplicatedStorage/Tidekeeper/Client/LetterView (ModuleScript)
--
-- The letter picker. 120 fixed phrases, grouped into the seven categories of
-- `LettersConfig.CATEGORY_NAMES`, so a player chooses a note by tapping
-- twice rather than scrolling a list of 120.
--
-- WHY A PICKER AND NOT A TEXT BOX
-- -------------------------------
-- doc 13 section 2: there is no free text anywhere in this game. A player
-- picks an id and the ID is what crosses the wire -- so there is nothing to
-- filter, no moderation hot path, and no way for this feature to become an
-- unmoderated chat channel. The words themselves live in `Strings.LETTER`
-- and are localisable; `LettersConfig` owns only the stable ids and the
-- category each belongs to.
--
-- The 120 letters have existed since iteration 7 and nothing could show them
-- or choose one: `RF_Dispatch` had no client caller at all, and the payload
-- builder it would have used sent a `phrase` index into a different table.
-- This module is the missing half.
--
-- Pure: tables in, tables out, no Instances. That is what lets the session
-- suite assert the picker against the real letter data with no GUI anywhere.
--
-- Layer: Client (view model).

local LettersConfig = require(script.Parent.Parent.Config.LettersConfig)
local Strings = require(script.Parent.Strings)
local Format = require(script.Parent.Format)

local LetterView = {}

LetterView.NONE = 0

-- Build the category list once at load: the letter table never changes at
-- runtime, so grouping it per open would be work repeated for nothing.
local CATEGORIES = {}
do
	local names = LettersConfig.CATEGORY_NAMES
	for i = 1, #names do
		CATEGORIES[i] = { index = i, name = names[i], ids = {} }
	end
	local rows = LettersConfig.LETTERS
	for i = 1, #rows do
		local row = rows[i]
		local id, category = row[1], row[2]
		local bucket = CATEGORIES[category]
		if bucket ~= nil then
			bucket.ids[#bucket.ids + 1] = id
		end
	end
end

LetterView.CATEGORY_COUNT = #CATEGORIES

-- The top level of the picker: seven categories and how many notes each
-- holds.
function LetterView.categories()
	local out = {}
	for i = 1, #CATEGORIES do
		local c = CATEGORIES[i]
		out[i] = {
			index = c.index,
			name = c.name,
			count = #c.ids,
			label = Format.label("LETTER_CATEGORY", { c.name }),
		}
	end
	return out
end

-- The notes inside one category, each with the words a player will actually
-- read. Returns an empty list for a category that does not exist rather than
-- throwing: a picker that errors on a bad tap is worse than one that shows
-- nothing.
function LetterView.lettersIn(categoryIndex)
	local bucket = CATEGORIES[categoryIndex]
	local out = {}
	if bucket == nil then
		return out
	end
	for i = 1, #bucket.ids do
		local id = bucket.ids[i]
		out[i] = { id = id, text = Format.letterText(id) }
	end
	return out
end

-- The whole picker as one model, including the "no note" option, which is
-- the default and must always be reachable in one tap.
function LetterView.build(selectedId)
	local chosen = math.floor(selectedId or LetterView.NONE)
	if chosen < 0 or chosen > LettersConfig.MAX_LETTER_ID then
		chosen = LetterView.NONE
	end
	local model = {
		title = Format.label("LETTER_TITLE"),
		noneLabel = Format.label("LETTER_NONE"),
		selectedId = chosen,
		selectedText = nil,
		categories = LetterView.categories(),
	}
	if chosen ~= LetterView.NONE then
		local text = Format.letterText(chosen)
		model.selectedText = text
		model.chosenLabel = Format.label("LETTER_CHOSEN", { text })
	end
	return model
end

-- Validate a chosen id before it goes anywhere near the wire. The server
-- re-checks it (DispatchHandler clamps against the same ceiling); this is
-- here so an impossible choice never costs the player a round trip.
function LetterView.isValid(id)
	if type(id) ~= "number" or id ~= math.floor(id) then
		return false
	end
	if id == LetterView.NONE then
		return true
	end
	return id >= 1 and id <= LettersConfig.MAX_LETTER_ID and Strings.LETTER[id] ~= nil
end

return LetterView
