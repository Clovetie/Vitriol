--!nonstrict
-- ReplicatedStorage/Tidekeeper/Client/Format (ModuleScript)
--
-- Turns `(templateId, slots[], actorName)` into a sentence.
--
-- Layer: Client. Pure. No services, no Instances, no clock, no yields -- which
-- is what lets the whole prose layer be tested headlessly, and why the
-- localisation-coverage check can prove that every template id the DOMAIN can
-- emit has prose on the CLIENT. Those two lists living in different files is
-- the bug this module exists to make impossible.
--
-- DETERMINISM
-- -----------
-- Variant selection hashes (actorId, epoch). It does not call `math.random`
-- and it does not keep a counter. The same Ledger entry therefore renders the
-- same sentence every time it is read, on every device, forever. A replay that
-- re-words itself between viewings is a replay the player cannot trust, and
-- trust in the Ledger is the entire product.
--
-- FAILURE POLICY
-- --------------
-- A missing name renders a fallback noun. A missing template renders a plain
-- factual line. Neither ever renders "{find:1}" or an empty string at a
-- player: shabby beats broken, and silence beats a bug report. Every fallback
-- increments a counter so the coverage test can assert the count is zero for
-- the shipping content set -- the graceful path exists for safety, not as an
-- excuse to leave holes.

local Hash = require(script.Parent.Parent.Lib.Hash)
local Ledger = require(script.Parent.Parent.Domain.Ledger)
local Strings = require(script.Parent.Strings)
local SeedsConfig = require(script.Parent.Parent.Config.SeedsConfig)

local Format = {}

-- Counters, for the coverage test and the diagnostics screen. Not player
-- facing.
Format.misses = {
	template = 0,
	find = 0,
	class = 0,
	tide = 0,
	arity = 0,
	letter = 0,
}

function Format.resetMisses()
	Format.misses.template = 0
	Format.misses.find = 0
	Format.misses.class = 0
	Format.misses.tide = 0
	Format.misses.arity = 0
	Format.misses.letter = 0
end

function Format.totalMisses()
	local m = Format.misses
	return m.template + m.find + m.class + m.tide + m.arity + m.letter
end

-- ----------------------------------------------------------------- lookups

function Format.findName(id)
	local name = Strings.FIND[id]
	if name == nil then
		Format.misses.find = Format.misses.find + 1
		return Strings.FIND_FALLBACK
	end
	return name
end

function Format.className(id)
	local name = Strings.CLASS[id]
	if name == nil then
		Format.misses.class = Format.misses.class + 1
		return Strings.CLASS_FALLBACK
	end
	return name
end

-- The text of a letter a drifter carried home. Ledger template 105 announces
-- that a note arrived; this is the note. Until iteration 7 no letter could
-- ever travel (ExchangeService hard-coded letterId = 0), so this lookup had
-- nothing to resolve and template 105 was unreachable prose.
function Format.letterText(id)
	if id == nil or id <= 0 then
		return nil
	end
	local text = Strings.LETTER[id]
	if text == nil then
		Format.misses.letter = Format.misses.letter + 1
		return Strings.LETTER_FALLBACK
	end
	return text
end

-- Resolve the name to print for an actor id.
--
-- Real players come from the `names` map the caller supplies. Seed Drifters
-- are not players and will never be in that map, so until iteration 7 every
-- one of them rendered as "Someone" -- and seeds are the majority of
-- arrivals at a quiet post. Naming them here, at the one place the Ledger
-- asks for a name, means no caller has to know seeds exist.
function Format.actorName(actorId, names)
	if actorId == nil then
		return nil
	end
	if names ~= nil and names[actorId] ~= nil then
		return names[actorId]
	end
	local index = actorId - SeedsConfig.SEED_OWNER_BASE + 1
	if index >= 1 and index <= SeedsConfig.SEED_COUNT then
		local seed = SeedsConfig.SEEDS[index]
		if seed ~= nil then
			return seed[2]
		end
	end
	return nil
end

function Format.tideName(code)
	local name = Strings.TIDE[code]
	if name == nil then
		Format.misses.tide = Format.misses.tide + 1
		return Strings.TIDE_FALLBACK
	end
	return name
end

-- --------------------------------------------------------------- variants

-- Deterministic variant choice. `Hash.mix` is the same mixer the simulation
-- uses, so this costs what a table lookup costs and introduces no new source
-- of divergence between two clients reading the same entry.
function Format.variantIndex(actorId, epoch, count)
	if count <= 1 then
		return 1
	end
	return Hash.reduce(Hash.mix(actorId or 0, epoch or 0, 11), count) + 1
end

-- ------------------------------------------------------------ substitution

-- Replace one `{...}` directive. Returns a string, always.
local function substitute(directive, slots, actorName)
	if directive == "actor" then
		return actorName or "Someone"
	end
	if directive == "coin" then
		return Strings.COIN
	end

	local kind, rest = string.match(directive, "^(%a+):(.+)$")
	if kind == "find" then
		return Format.findName(slots[tonumber(rest) or 0])
	elseif kind == "class" then
		return Format.className(slots[tonumber(rest) or 0])
	elseif kind == "tide" then
		return Format.tideName(slots[tonumber(rest) or 0])
	elseif kind == "plural" then
		-- {plural:N|singular|plural}
		local idxText, singular, plural = string.match(rest, "^(%d+)|([^|]*)|(.*)$")
		if idxText ~= nil then
			local value = slots[tonumber(idxText) or 0] or 0
			local word = (value == 1) and singular or plural
			-- A variant may nest a slot inside the plural branch, e.g.
			-- "{plural:1|one boat|{1} boats}". Resolve that here rather than
			-- requiring a second pass over the whole string.
			word = string.gsub(word, "{(%d+)}", function(n)
				return tostring(slots[tonumber(n)] or 0)
			end)
			return word
		end
	end

	local slotIndex = tonumber(directive)
	if slotIndex ~= nil then
		local value = slots[slotIndex]
		if value == nil then
			Format.misses.arity = Format.misses.arity + 1
			return "0"
		end
		return tostring(value)
	end

	-- An unknown directive. Render nothing rather than braces.
	Format.misses.arity = Format.misses.arity + 1
	return ""
end

-- Expand every directive in `text`.
function Format.expand(text, slots, actorName)
	local out = string.gsub(text, "{([^{}]+)}", function(directive)
		return substitute(directive, slots or {}, actorName)
	end)
	return out
end

-- ------------------------------------------------------------------ render

-- The one function the Ledger view calls.
--
-- `entry` is `{ templateId, epoch, actorId, slots, slotCount }` exactly as
-- `Domain/Ledger.entry` produced it on the server.
function Format.renderEntry(entry, actorName)
	local templateId = entry.templateId
	local variants = Strings.LEDGER[templateId]
	if variants == nil or #variants == 0 then
		Format.misses.template = Format.misses.template + 1
		-- A factual, unembarrassing fallback. It says nothing false.
		return "Someone came by."
	end

	-- Arity check. The domain declares how many slots a template carries; if
	-- the prose and the domain disagree, that is a content bug and the
	-- coverage test must fail rather than a player seeing "{4}".
	--
	-- AN ENTRY ARRIVES IN ONE OF TWO SHAPES and the difference is not
	-- cosmetic. `Ledger.entry` returns `{templateId, epoch, actorId, slots}`
	-- with `slots` sized exactly to the template. `Visit.narrate` writes into
	-- a REUSED context whose `slots` array is permanently oversized (that
	-- reuse is what makes Visit.resolve allocate nothing), so it carries an
	-- explicit `slotCount` and `#slots` would over-report. Trusting either
	-- field alone mis-reads half the entries in the game; the iteration-4
	-- coverage test found exactly that by reporting 60 phantom misses.
	local declared = Ledger.SLOT_COUNT[templateId]
	local have = entry.slotCount or (entry.slots and #entry.slots) or 0
	if declared ~= nil and have < declared then
		Format.misses.arity = Format.misses.arity + 1
	end

	local index = Format.variantIndex(entry.actorId, entry.epoch, #variants)
	return Format.expand(variants[index], entry.slots, actorName)
end

-- A UI label. Same substitution machinery, no variants, no actor.
function Format.label(key, slots)
	local text = Strings.UI[key]
	if text == nil then
		Format.misses.template = Format.misses.template + 1
		return ""
	end
	return Format.expand(text, slots or {})
end

-- ------------------------------------------------------------------ numbers

-- Durations, for "low water in 3h 20m". Integer maths only: this runs on the
-- render path and a float formatter here would show up in the frame budget
-- for no benefit.
function Format.duration(seconds)
	if seconds <= 60 then
		return Strings.UI.TIME_SOON
	end
	local minutes = math.floor(seconds / 60)
	local hours = math.floor(minutes / 60)
	if hours >= 1 then
		local rem = minutes - hours * 60
		if rem == 0 then
			return Format.expand(Strings.UI.TIME_HOURS, { hours })
		end
		return Format.expand(Strings.UI.TIME_HOURS, { hours }) .. " " .. Format.expand(Strings.UI.TIME_MINUTES, { rem })
	end
	return Format.expand(Strings.UI.TIME_MINUTES, { minutes })
end

return Format
