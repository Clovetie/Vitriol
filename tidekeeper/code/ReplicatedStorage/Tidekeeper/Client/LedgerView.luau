--!nonstrict
-- ReplicatedStorage/Tidekeeper/Client/LedgerView (ModuleScript)
--
-- The signature screen (doc 08 section 3), as a PRESENTER.
--
-- Layer: Client. Pure. It builds a render model -- a plain table of strings,
-- numbers and colour bands -- and hands it to whatever draws. It creates no
-- Instance, connects to nothing, and reads no clock.
--
-- WHY A PRESENTER AND NOT A GUI MODULE
-- ------------------------------------
-- The Ledger is the product. If the only way to check it is to look at it,
-- then nobody checks it, and the first time anyone notices that template 250
-- renders as "Someone came by." is when a player who was away for a month
-- comes back. Splitting "what does it say" from "what does it look like"
-- means the first half runs in the test suite with the real Domain modules
-- and the real Strings table, 200 entries at a time.
--
-- Doc 08 section 3 also asks for a paced replay grouped by tide epoch, with a
-- tide silhouette per group and warmth as edge colour. All three are decided
-- here, deterministically, from integers.

local Tide = require(script.Parent.Parent.Lib.Tide)
local Ledger = require(script.Parent.Parent.Domain.Ledger)
local Format = require(script.Parent.Format)
local Strings = require(script.Parent.Strings)

local LedgerView = {}

-- Pacing, doc 08 section 3: ~1.6 s per entry, tap to advance.
LedgerView.SECONDS_PER_ENTRY = 1.6
LedgerView.SILHOUETTE_SAMPLES = 16

-- Warmth bands. The player never sees a number (doc 03 section 12) -- the
-- entry's edge takes a colour temperature instead. Bands, not a gradient, so
-- the difference is legible at a glance on a phone.
LedgerView.BAND_COLD = 1
LedgerView.BAND_COOL = 2
LedgerView.BAND_NEUTRAL = 3
LedgerView.BAND_WARM = 4
LedgerView.BAND_HOT = 5

function LedgerView.warmthBand(warmth)
	local w = warmth or 0
	if w <= -60 then
		return LedgerView.BAND_COLD
	elseif w <= Ledger.COLD then
		return LedgerView.BAND_COOL
	elseif w < Ledger.WARM then
		return LedgerView.BAND_NEUTRAL
	elseif w < 100 then
		return LedgerView.BAND_WARM
	end
	return LedgerView.BAND_HOT
end

-- The tide silhouette behind a group: `SILHOUETTE_SAMPLES` heights across the
-- epoch, from the REAL tide function (doc 02 section 5). The screen is a tidal
-- record, not a decoration, and re-deriving it from `Tide.height` is what
-- keeps that true when the constants change.
function LedgerView.silhouette(epoch, out)
	local samples = out or table.create(LedgerView.SILHOUETTE_SAMPLES)
	local start = Tide.epochStart(epoch)
	local step = Tide.EPOCH_SECONDS / (LedgerView.SILHOUETTE_SAMPLES - 1)
	for i = 1, LedgerView.SILHOUETTE_SAMPLES do
		samples[i] = Tide.height(start + (i - 1) * step)
	end
	return samples
end

-- Group entries by epoch, preserving order within a group.
--
-- `entries` is the array the server replicated. `names` maps actorId ->
-- display name; a missing name is fine and renders as "Someone", because a
-- name lookup that fails must not cost the player their history.
function LedgerView.build(entries, names, options)
	local opts = options or {}
	local groups = {}
	local byEpoch = {}
	local order = {}
	local unread = 0

	for i = 1, #entries do
		local entry = entries[i]
		local epoch = entry.epoch or 0
		local group = byEpoch[epoch]
		if group == nil then
			group = {
				epoch = epoch,
				tideState = Tide.stateForEpoch(epoch),
				lines = {},
				silhouette = nil,
			}
			byEpoch[epoch] = group
			order[#order + 1] = epoch
			groups[#groups + 1] = group
		end

		local actorName = names and names[entry.actorId] or nil
		group.lines[#group.lines + 1] = {
			templateId = entry.templateId,
			actorId = entry.actorId,
			epoch = epoch,
			text = Format.renderEntry(entry, actorName),
			band = LedgerView.warmthBand(entry.warmth),
			-- A letter is the one thing that gets its own affordance.
			hasLetter = (entry.noteId ~= nil and entry.noteId > 0) or false,
		}
		unread = unread + 1
	end

	-- Silhouettes are the only per-group cost that is not a string, so they
	-- are built lazily unless the caller asks. A 27-epoch catch-up would
	-- otherwise sample the tide 432 times before the first frame.
	if opts.withSilhouettes then
		for i = 1, #groups do
			groups[i].silhouette = LedgerView.silhouette(groups[i].epoch)
		end
	end

	return {
		groups = groups,
		count = unread,
		title = Format.label("LEDGER_TITLE"),
		emptyText = Format.label("LEDGER_EMPTY"),
		badge = unread > 0 and Format.label("LEDGER_UNREAD", { unread }) or nil,
		-- Doc 08 section 3: ~20 s for a 12-entry Ledger if you let it run.
		runtimeSeconds = unread * LedgerView.SECONDS_PER_ENTRY,
		isEmpty = unread == 0,
	}
end

-- The single highlighted line the Ledger collapses to at 0:20 (doc 08
-- section 2). Pick the entry the player can act on: an unmet want beats a
-- sale, because an unmet want is a reason to go combing.
function LedgerView.highlight(model)
	if model.isEmpty then
		return nil
	end
	local best, bestScore = nil, -1
	for g = 1, #model.groups do
		local lines = model.groups[g].lines
		for i = 1, #lines do
			local line = lines[i]
			local score = 0
			local t = line.templateId
			if t == Ledger.T_REFUSED_COLD then
				score = 5 -- someone wanted something you did not have
			elseif t == Ledger.T_PARTIAL_BUDGET then
				score = 4
			elseif t == Ledger.T_MISSED_TIDE or t == Ledger.T_MISSED_TIDE_DEEPWATER then
				score = 3
			elseif t == Ledger.T_GIFT then
				score = 2
			elseif t == Ledger.T_SERVED_WANT then
				score = 1
			end
			if line.hasLetter then
				score = score + 6
			end
			if score > bestScore then
				best, bestScore = line, score
			end
		end
	end
	return best
end

-- Every distinct template id the model actually rendered. The coverage test
-- uses this to prove the suite exercised the prose it claims to cover, rather
-- than trusting that 200 entries happened to hit all 15 templates.
function LedgerView.templatesUsed(model, into)
	local seen = into or {}
	for g = 1, #model.groups do
		local lines = model.groups[g].lines
		for i = 1, #lines do
			seen[lines[i].templateId] = (seen[lines[i].templateId] or 0) + 1
		end
	end
	return seen
end

LedgerView.PHRASES = Strings.PHRASE

return LedgerView
