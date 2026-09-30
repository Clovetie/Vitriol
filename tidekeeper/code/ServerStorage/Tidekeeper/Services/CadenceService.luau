--!nonstrict
-- ServerStorage/Tidekeeper/Services/CadenceService (ModuleScript)
--
-- Layer L3. THE SCHEDULER. There is exactly one `RunService` connection in
-- this game and it is created here (doc 01 section 5). Nothing else in the
-- tree may call `task.spawn`, `task.wait`, `task.delay`, or connect to
-- `RunService`; `tidekeeper-determinism-scan.js` enforces that statically.
--
-- Why one connection, when Roblox makes it so easy to have forty: a server
-- with forty Heartbeat connections has no profile, only a total. With one,
-- every millisecond of server time belongs to a named slot with a declared
-- budget, and `Diagnostics/Profiler` can say which slot went over.
--
--   slot     rate            budget/tick   what runs
--   frame    every Heartbeat 0.6 ms        reserved; normally empty
--   think    4 Hz            2.0 ms        post tick, comb respawn, orders
--   slow     0.5 Hz          6.0 ms        ledger flush, decay, showcase, reapers
--   io       0.2 Hz          budgeted      adapter batches
--   resolve  on demand       12 ms         catch-up for a joining player
--
-- `resolve` is the only slot allowed to exceed a frame's worth of work, and
-- it does so by CHUNKING: at most `GameConfig.EPOCHS_PER_RESOLVE_TICK` tide
-- epochs per tick, at most `MAX_CATCHUP_EPOCHS` in total. A player returning
-- after a week resolves over about seven ticks while the client plays the
-- Ledger's opening animation. The wait is disguised as content.
--
-- CHUNKING IS PART OF THE DETERMINISTIC CONTRACT, NOT AN OPTIMISATION.
-- `Resolve.run`'s arrival scheduling is `mod epochCount`, so the width of the
-- window changes where a Drifter lands (HANDOFF "the one non-commuting
-- property"). The chunk plan is therefore a PURE FUNCTION of
-- (resolvedAt, now) -- see `CadenceService.planChunks` -- and the Drifter to
-- chunk assignment is a pure function of (drifterId, salt, chunkCount). Two
-- servers, or a server and an offline client, plan identically and get
-- identical history.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tidekeeper = ReplicatedStorage:WaitForChild("Tidekeeper")

local GameConfig = require(Tidekeeper.Config.GameConfig)
local Hash = require(Tidekeeper.Lib.Hash)
local Tide = require(Tidekeeper.Lib.Tide)

local CadenceService = {}
CadenceService.__index = CadenceService

local SLOT_FRAME = "frame"
local SLOT_THINK = "think"
local SLOT_SLOW = "slow"
local SLOT_IO = "io"
local SLOT_RESOLVE = "resolve"

CadenceService.SLOT_FRAME = SLOT_FRAME
CadenceService.SLOT_THINK = SLOT_THINK
CadenceService.SLOT_SLOW = SLOT_SLOW
CadenceService.SLOT_IO = SLOT_IO
CadenceService.SLOT_RESOLVE = SLOT_RESOLVE

-- { name, period seconds, budget ms }
local SLOTS = {
	{ SLOT_FRAME, 0, 0.6 },
	{ SLOT_THINK, 0.25, 2.0 },
	{ SLOT_SLOW, 2.0, 6.0 },
	{ SLOT_IO, 5.0, 0 },
	{ SLOT_RESOLVE, 0, 12.0 },
}

local EPOCHS_PER_TICK = GameConfig.EPOCHS_PER_RESOLVE_TICK
local MAX_EPOCHS = GameConfig.MAX_CATCHUP_EPOCHS

CadenceService.EPOCHS_PER_TICK = EPOCHS_PER_TICK

-- ------------------------------------------------------- the chunk plan

-- Pure. Given the post's `resolvedAt` and the wall time `now`, return the
-- list of chunk boundaries as absolute timestamps, each covering at most
-- EPOCHS_PER_TICK tide epochs, with the last chunk ending exactly at `now`.
--
-- Clamping to MAX_EPOCHS happens inside `Resolve.run`, so the FIRST chunk
-- carries the clamp and the LONG_ABSENCE entry; that is why the plan starts
-- from the clamped epoch rather than from resolvedAt when the gap is large.
function CadenceService.planChunks(resolvedAt, now)
	local chunks = {}
	local target = math.floor(now)
	if target <= resolvedAt then
		return chunks
	end
	local fromEpoch = Tide.epoch(resolvedAt)
	local toEpoch = Tide.epoch(target)
	if toEpoch <= fromEpoch then
		return chunks
	end
	local firstEpoch = fromEpoch + 1
	local span = toEpoch - fromEpoch
	if span > MAX_EPOCHS then
		-- The clamped run collapses everything older into one summary; it is
		-- chunk one and it is charged the whole skipped span.
		firstEpoch = toEpoch - MAX_EPOCHS + 1
		chunks[1] = { from = firstEpoch, to = math.min(firstEpoch + EPOCHS_PER_TICK - 1, toEpoch), clamped = true }
	end
	local cursor = firstEpoch
	if #chunks == 1 then
		cursor = chunks[1].to + 1
	end
	while cursor <= toEpoch do
		local last = math.min(cursor + EPOCHS_PER_TICK - 1, toEpoch)
		chunks[#chunks + 1] = { from = cursor, to = last, clamped = false }
		cursor = last + 1
	end
	-- Each chunk's `now` is the last second of its final epoch, except the
	-- last chunk, which ends at the real `now` so that resolvedAt lands on
	-- the truth rather than on an epoch boundary.
	for i = 1, #chunks do
		chunks[i].now = Tide.epochStart(chunks[i].to + 1) - 1
	end
	chunks[#chunks].now = target
	return chunks
end

-- Pure. Which chunk does this Drifter belong to? Deterministic in the id and
-- the post's salt, so the assignment survives a retry, a different server,
-- and an offline replay.
function CadenceService.chunkForDrifter(drifterId, salt, chunkCount)
	if chunkCount <= 1 then
		return 1
	end
	return Hash.reduce(Hash.mix(drifterId, salt, 11), chunkCount) + 1
end

-- ------------------------------------------------------------ the service

local function newSlotState(row)
	return {
		name = row[1],
		period = row[2],
		budgetMs = row[3],
		accumulated = 0,
		tasks = {},
		runs = 0,
		overruns = 0,
		lastMs = 0,
		peakMs = 0,
		totalMs = 0,
	}
end

function CadenceService.new(options)
	local opts = options or {}
	local self = setmetatable({}, CadenceService)
	self.runService = opts.runService or game:GetService("RunService")
	self.clock = opts.clock or os.clock
	self.logger = opts.logger
	self.profiler = opts.profiler
	self.connection = nil
	self.slots = {}
	self.order = {}
	for i = 1, #SLOTS do
		local state = newSlotState(SLOTS[i])
		self.slots[state.name] = state
		self.order[i] = state.name
	end
	self.resolveQueue = {}
	self.resolveHead = 1
	self.ticks = 0
	self.errors = 0
	return self
end

function CadenceService:log(message)
	if self.logger ~= nil then
		self.logger("CadenceService", message)
	end
end

-- Register a repeating task in a slot. Returns a handle with :cancel().
function CadenceService:register(slotName, taskName, fn)
	local slot = self.slots[slotName]
	if slot == nil then
		error("CadenceService: unknown slot " .. tostring(slotName), 2)
	end
	local entry = { name = taskName, fn = fn, cancelled = false }
	slot.tasks[#slot.tasks + 1] = entry
	return {
		cancel = function()
			entry.cancelled = true
		end,
	}
end

-- Queue a chunked resolve. `job` is
--   { name, chunks = {...}, step = function(chunk, index) -> ok, done = function() }
-- and CadenceService runs at most one chunk per tick so that a seven-day
-- catch-up cannot stall a frame.
function CadenceService:enqueueResolve(job)
	job.index = 1
	self.resolveQueue[#self.resolveQueue + 1] = job
	return job
end

function CadenceService:pendingResolves()
	return #self.resolveQueue - self.resolveHead + 1
end

function CadenceService:start()
	if self.connection ~= nil then
		return
	end
	-- THE one connection. If you are reading this because you want a second
	-- one: register a slot instead.
	self.connection = self.runService.Heartbeat:Connect(function(dt)
		self:step(dt)
	end)
	self:log("started")
end

function CadenceService:stop()
	if self.connection ~= nil then
		self.connection:Disconnect()
		self.connection = nil
	end
end

function CadenceService:runSlot(slot)
	local started = self.clock()
	local tasks = slot.tasks
	local live = 0
	for i = 1, #tasks do
		local entry = tasks[i]
		if not entry.cancelled then
			live = live + 1
			tasks[live] = entry
			local ok, err = pcall(entry.fn)
			if not ok then
				self.errors = self.errors + 1
				self:log("slot " .. slot.name .. " task " .. entry.name .. " errored: " .. tostring(err))
			end
		end
	end
	for i = #tasks, live + 1, -1 do
		tasks[i] = nil
	end
	local elapsed = (self.clock() - started) * 1000
	slot.runs = slot.runs + 1
	slot.lastMs = elapsed
	slot.totalMs = slot.totalMs + elapsed
	if elapsed > slot.peakMs then
		slot.peakMs = elapsed
	end
	if slot.budgetMs > 0 and elapsed > slot.budgetMs then
		slot.overruns = slot.overruns + 1
	end
	if self.profiler ~= nil then
		self.profiler:sample(slot.name, elapsed, slot.budgetMs)
	end
end

-- One Heartbeat. Exposed so the session harness can drive the whole server
-- from a virtual clock rather than from wall time.
function CadenceService:step(dt)
	self.ticks = self.ticks + 1
	for i = 1, #self.order do
		local slot = self.slots[self.order[i]]
		if slot.name ~= SLOT_RESOLVE then
			if slot.period <= 0 then
				self:runSlot(slot)
			else
				slot.accumulated = slot.accumulated + dt
				if slot.accumulated >= slot.period then
					slot.accumulated = 0
					self:runSlot(slot)
				end
			end
		end
	end
	self:stepResolve()
end

-- At most ONE chunk per tick, and a chunk is at most EPOCHS_PER_TICK epochs.
function CadenceService:stepResolve()
	if self.resolveHead > #self.resolveQueue then
		if self.resolveHead > 1 then
			-- Compact rather than grow forever.
			for i = 1, #self.resolveQueue do
				self.resolveQueue[i] = nil
			end
			self.resolveHead = 1
		end
		return
	end
	local slot = self.slots[SLOT_RESOLVE]
	local job = self.resolveQueue[self.resolveHead]
	local started = self.clock()
	local chunk = job.chunks[job.index]
	local ok, err = pcall(function()
		job.step(chunk, job.index)
	end)
	if not ok then
		self.errors = self.errors + 1
		self:log("resolve job " .. tostring(job.name) .. " errored: " .. tostring(err))
		job.index = #job.chunks + 1
	else
		job.index = job.index + 1
	end
	local elapsed = (self.clock() - started) * 1000
	slot.runs = slot.runs + 1
	slot.lastMs = elapsed
	slot.totalMs = slot.totalMs + elapsed
	if elapsed > slot.peakMs then
		slot.peakMs = elapsed
	end
	if elapsed > slot.budgetMs then
		slot.overruns = slot.overruns + 1
	end
	if self.profiler ~= nil then
		self.profiler:sample(SLOT_RESOLVE, elapsed, slot.budgetMs)
	end
	if job.index > #job.chunks then
		self.resolveQueue[self.resolveHead] = nil
		self.resolveHead = self.resolveHead + 1
		if job.done ~= nil then
			local doneOk, doneErr = pcall(job.done)
			if not doneOk then
				self.errors = self.errors + 1
				self:log("resolve job " .. tostring(job.name) .. " completion errored: " .. tostring(doneErr))
			end
		end
	end
end

-- Drain everything that is queued. Used by BindToClose and by the harness.
function CadenceService:flushResolves(maxTicks)
	local limit = maxTicks or 1024
	local n = 0
	while self:pendingResolves() > 0 and n < limit do
		n = n + 1
		self:stepResolve()
	end
	return n
end

function CadenceService:report()
	local out = {}
	for i = 1, #self.order do
		local slot = self.slots[self.order[i]]
		out[i] = {
			name = slot.name,
			runs = slot.runs,
			overruns = slot.overruns,
			budgetMs = slot.budgetMs,
			peakMs = slot.peakMs,
			meanMs = slot.runs > 0 and (slot.totalMs / slot.runs) or 0,
		}
	end
	return out
end

return CadenceService
