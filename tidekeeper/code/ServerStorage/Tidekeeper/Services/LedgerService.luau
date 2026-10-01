--!nonstrict
-- ServerStorage/Tidekeeper/Services/LedgerService (ModuleScript)
--
-- Layer L3. The Ledger is the first thing a returning player reads and the
-- main reason they came back (doc 02 section 4). This service keeps the
-- resident tail in memory, pages the rest to DataStore, and is the ONLY
-- place that turns entries into something a client is allowed to see.
--
-- WHY ENTRIES ARE IDS AND SLOTS, NOT SENTENCES
-- --------------------------------------------
-- An entry is `{ t = templateId, e = epoch, a = actorId, s = {slots} }`.
-- The prose lives on the client in a localisation table. This is not a
-- micro-optimisation, it is three separate requirements collapsing into one
-- representation:
--
--   * doc 13 section 2 -- no free text ANYWHERE, so there is no text to
--     filter, no `FilterStringAsync` on the join path, and no way for one
--     player to send another a string;
--   * doc 05 -- an entry is 12 bytes instead of ~90, so 200 resident
--     entries cost 2.4 KB of a 6 KB post blob;
--   * doc 06 -- translating the game means translating 12 templates, not a
--     corpus, and a template can change wording after launch without a
--     migration.
--
-- Slots are integers: find ids, coin amounts, counts. `Ledger.selectTemplate`
-- picks which template an outcome deserves, and that choice is pure, so the
-- same visit always reads the same way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local GameConfig = require(Tidekeeper.Config.GameConfig)
local Tide = require(Tidekeeper.Lib.Tide)
local Ledger = require(Tidekeeper.Domain.Ledger)

local LedgerService = {}
LedgerService.__index = LedgerService

-- A page is written only when the resident tail overflows, which at 200
-- resident entries and a handful of visits an epoch is rare. Pages are
-- append-only and never rewritten.
local PAGE_SIZE = 200

local function newStats()
	return {
		appended = 0,
		pagesWritten = 0,
		pagesRead = 0,
		pagesReaped = 0,
		pageWriteFailures = 0,
		historyReads = 0,
		dropped = 0,
	}
end

function LedgerService.new(options)
	local opts = options or {}
	local self = setmetatable({}, LedgerService)
	self.data = opts.data
	self.posts = opts.posts
	self.clock = opts.clock or os.time
	self.logger = opts.logger
	self.stats = newStats()
	self.pending = {}
	-- A sorted companion to `pending`, because iterating a map with `pairs`
	-- and then writing to DataStore makes the request ORDER depend on hash
	-- iteration order, and the session harness compares request sequences.
	self.pendingOrder = {}
	return self
end

function LedgerService:log(message)
	if self.logger ~= nil then
		self.logger("LedgerService", message)
	end
end

-- Resident entries live inside the post state so that they are saved,
-- migrated and version-checked by exactly one mechanism.
function LedgerService:residentOf(S)
	local list = S.ledger
	if list == nil then
		list = {}
		S.ledger = list
	end
	return list
end

-- Append a batch produced by `Resolve.run`. Overflow goes to `self.pending`
-- and is flushed on the `io` slot rather than written inline: a resolve must
-- never turn into a DataStore write while the player is waiting.
function LedgerService:appendAll(userId, S, entries)
	if #entries == 0 then
		return 0
	end
	local list = self:residentOf(S)
	local cap = GameConfig.MAX_LEDGER_RESIDENT
	for i = 1, #entries do
		local entry = entries[i]
		if Ledger.isValid(entry) then
			-- `Ledger.append` drops from the front silently, which is right
			-- for the domain (it does not know DataStore exists) and wrong
			-- for us, so the eviction is captured here before it happens.
			if #list >= cap then
				self:queuePage(userId, list[1])
			end
			Ledger.append(list, entry, cap)
			self.stats.appended = self.stats.appended + 1
		else
			self.stats.dropped = self.stats.dropped + 1
		end
	end
	return #entries
end

function LedgerService:queuePage(userId, entry)
	local overflow = self.pending[userId]
	if overflow == nil then
		overflow = {}
		self.pending[userId] = overflow
		self.pendingOrder[#self.pendingOrder + 1] = userId
		table.sort(self.pendingOrder)
	end
	overflow[#overflow + 1] = entry
end

-- Turn the receipts this player's own Drifter earned elsewhere into entries
-- in their Ledger. This is the payoff loop of the whole game: you see what
-- your traveller did while you were gone, at somebody else's post.
function LedgerService:absorbReceipts(userId, S, receipts)
	if #receipts == 0 then
		return 0
	end
	local entries = {}
	local n = 0
	for i = 1, #receipts do
		local r = receipts[i]
		-- The receipt carries the outcome and the numbers; `selectTemplate`
		-- turns that into which sentence the player reads. `remote` is what
		-- makes it read as "your traveller, elsewhere" rather than "someone,
		-- here".
		-- REMOTE range. `selectTemplate` answers "who came to my post" and
		-- its slots mean find ids and shelf prices -- facts a receipt does
		-- not have. Feeding a receipt through it put a coin amount where a
		-- find id belongs and rendered "12" as the name of an object.
		local templateId = Ledger.selectRemoteTemplate(r.outcome, {
			warmth = r.warmth,
			spent = r.spent,
			noteId = r.noteId,
		})
		local entry = Ledger.entry(templateId, r.epoch, r.hostId, self:slotsFor(templateId, r))
		if entry ~= nil then
			n = n + 1
			entries[n] = entry
		else
			self.stats.dropped = self.stats.dropped + 1
		end
	end
	return self:appendAll(userId, S, entries)
end

-- Templates declare their arity in `Ledger.SLOT_COUNT`, and `Ledger.entry`
-- refuses a mismatch, so the slot list is built to the template rather than
-- guessed. An entry that would not validate is dropped and counted, never
-- silently reshaped.
function LedgerService:slotsFor(templateId, r)
	-- Explicit per template. The previous version filled slots from a
	-- positional pool `{spent, warmth, noteId, flags}` regardless of what the
	-- template's slots MEANT, so template 102's "tide" slot received a coin
	-- amount. It never showed up because nothing rendered these entries until
	-- the client existed.
	if templateId == Ledger.T_REMOTE_SOLD then
		return { r.spent or 0, r.warmth or 0 }
	elseif templateId == Ledger.T_REMOTE_MISSED then
		-- A real tide code, derived from the epoch the receipt carries --
		-- the tide is a pure function of time, so this is not a guess.
		return { Tide.codeForEpoch(r.epoch) }
	elseif templateId == Ledger.T_REMOTE_LETTER then
		return { r.noteId or 0 }
	end
	-- 101, 103, 104: one slot, the reception.
	return { r.warmth or 0 }
end

-- Registered on the `io` slot. One page write per call, at most.
function LedgerService:flushPending()
	for i = 1, #self.pendingOrder do
		local userId = self.pendingOrder[i]
		local overflow = self.pending[userId]
		if overflow ~= nil and #overflow >= PAGE_SIZE then
			local page = {}
			for j = 1, PAGE_SIZE do
				page[j] = overflow[j]
			end
			-- One page per tide epoch per player. Epochs are 22357 seconds,
			-- so a page key can never collide with a different batch, and
			-- the key is derivable from an entry's own epoch when reading
			-- history back.
			-- OD22. The page number comes from an atomic counter in the
			-- player's index key, NOT from the epoch. The epoch looked
			-- safe -- "one page per tide epoch per player" -- but
			-- saveLedgerPage overwrites, so two servers flushing inside
			-- one 6.2-hour epoch (an ordinary server hop) would destroy
			-- one of the two pages. Allocating first also means a page is
			-- only ever written under a number the index knows about.
			local allocOk, pageIndex, droppedPages = self.data:allocLedgerPage(userId)
			if not allocOk then
				self.stats.pageWriteFailures = self.stats.pageWriteFailures + 1
				return
			end
			local ok = self.data:saveLedgerPage(userId, pageIndex, page)
			if ok then
				-- Pages that fell out of the retention window. Deleting
				-- them here is the ledger reaper, and it costs nothing
				-- extra: we already know exactly which keys they are.
				for i = 1, #(droppedPages or {}) do
					if self.data:removeLedgerPage(userId, droppedPages[i]) then
						self.stats.pagesReaped = self.stats.pagesReaped + 1
					end
				end
				self.stats.pagesWritten = self.stats.pagesWritten + 1
				local kept = {}
				for j = PAGE_SIZE + 1, #overflow do
					kept[#kept + 1] = overflow[j]
				end
				self.pending[userId] = kept
			else
				self.stats.pageWriteFailures = self.stats.pageWriteFailures + 1
			end
			return
		end
	end
end

-- ---------------------------------------------------------- history (OD22)
--
-- The Ledger carries this game's whole emotional argument -- "absence is
-- content", doc 00 -- and until iteration 10 it quietly forgot. Entries
-- evicted past MAX_LEDGER_RESIDENT (200) were archived to pages and
-- `loadLedgerPage` was called by nothing, so every entry older than the most
-- recent 200 was unreadable forever. A game whose premise is "look at what
-- happened while you were away" must not be the thing that loses it.
--
-- PAGING. `cursor` is the index into the player's page list counted from the
-- NEWEST page: 0 is "the most recent archived page", 1 the one before it,
-- and so on. Counting from the newest is what makes the cursor stable while
-- new pages are being written at the other end -- a cursor counted from the
-- oldest would slide under the reader every time a page was reaped.
--
-- Returns (entries, nextCursor, total). `nextCursor` is nil at the end of
-- history, which is how the client knows to stop asking and say so.
LedgerService.HISTORY_PAGE_MAX = 200

function LedgerService:history(userId, cursor)
	local c = math.floor(cursor or 0)
	if c < 0 then
		c = 0
	end
	local ok, pages = self.data:loadLedgerIndex(userId)
	if not ok or pages == nil or #pages == 0 then
		return {}, nil, 0
	end
	local total = #pages
	-- Newest first.
	local which = total - c
	if which < 1 then
		return {}, nil, total
	end
	local readOk, entries = self.data:loadLedgerPage(userId, pages[which])
	self.stats.historyReads = self.stats.historyReads + 1
	if not readOk or entries == nil then
		-- A page in the index that will not load is a hole, not the end of
		-- history: report it as empty but keep the cursor moving, so one
		-- unreadable page cannot hide every older page behind it.
		return {}, (which > 1) and (c + 1) or nil, total
	end
	self.stats.pagesRead = self.stats.pagesRead + 1
	local out = {}
	for i = 1, math.min(#entries, LedgerService.HISTORY_PAGE_MAX) do
		out[i] = entries[i]
	end
	return out, (which > 1) and (c + 1) or nil, total
end

function LedgerService:forget(userId)
	self.pending[userId] = nil
	for i = 1, #self.pendingOrder do
		if self.pendingOrder[i] == userId then
			table.remove(self.pendingOrder, i)
			break
		end
	end
end

function LedgerService:resetStats()
	self.stats = newStats()
end

return LedgerService
