--!nonstrict
-- ReplicatedStorage/Tidekeeper/Client/AlmanacView (ModuleScript)
--
-- The almanac: every find in the game, and whether this post has ever held
-- one.
--
-- Like the chart, SCREEN_ALMANAC rendered nothing but a tide header for five
-- iterations, and the dead-content scan found it from the label end:
-- ALMANAC_TITLE and ALMANAC_HELD existed and nothing could display them.
--
-- THE ALMANAC IS A RECORD OF HAVING HELD, NOT OF HAVING SOLD. `S.almanac` is
-- a 32-byte bitset written by `Post.addStock`, so a find counts the moment it
-- passes through your hands. That is deliberate (doc 07): the almanac is a
-- memory, not an inventory, and selling something should not erase the fact
-- that you once found it.

local Almanac = require(script.Parent.Parent.Domain.Almanac)
local Post = require(script.Parent.Parent.Domain.Post)
local Format = require(script.Parent.Format)

local AlmanacView = {}

-- How many rows a page shows. The almanac is 200 finds; building 200 names
-- on a phone every time the screen is opened is the kind of thing doc 08
-- section 7 budgets against, so it pages.
AlmanacView.PAGE = 50

function AlmanacView.pageCount()
	local total = Post.knownFindCount()
	return math.max(1, math.ceil(total / AlmanacView.PAGE))
end

-- `almanac` is the 32-byte bitset from the snapshot. A client that has not
-- received one yet shows every find as unheld rather than showing nothing --
-- an empty almanac is a true statement about a new post.
function AlmanacView.build(almanac, page)
	local total = Post.knownFindCount()
	local p = math.floor(page or 1)
	if p < 1 then
		p = 1
	end
	local pages = AlmanacView.pageCount()
	if p > pages then
		p = pages
	end

	local held = 0
	if almanac ~= nil and Almanac.isValid(almanac) then
		held = Almanac.count(almanac)
	end

	local rows = {}
	local first = (p - 1) * AlmanacView.PAGE + 1
	local last = math.min(total, first + AlmanacView.PAGE - 1)
	for id = first, last do
		local has = almanac ~= nil and Almanac.has(almanac, id) or false
		rows[#rows + 1] = {
			findId = id,
			-- An unheld find shows as a blank, not as its name. Listing
			-- everything by name would turn the almanac from a record of
			-- what you have seen into a checklist handed out at the start.
			name = has and Format.findName(id) or "",
			held = has,
		}
	end

	return {
		title = Format.label("ALMANAC_TITLE"),
		heldText = Format.label("ALMANAC_HELD", { held, total }),
		rows = rows,
		page = p,
		pages = pages,
		held = held,
		total = total,
		isEmpty = held == 0,
	}
end

return AlmanacView
