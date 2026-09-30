--!nonstrict
-- ServerScriptService/Tidekeeper/Diagnostics/Profiler (ModuleScript)
--
-- Per-slot timing, kept by CadenceService calling `sample` once per slot run.
--
-- WHY A RING BUFFER AND A P95 RATHER THAN A MEAN
-- ----------------------------------------------
-- A mean frame time hides exactly the thing that ruins a Roblox experience:
-- the one tick in two hundred that took 40 ms because a resolve, a save and
-- a showcase flush landed together. Players do not feel the mean, they feel
-- the hitch. So this keeps the last 256 samples per slot and reports p95 and
-- max alongside the mean.
--
-- It is allocation-free after construction: the ring is pre-sized, the sort
-- buffer is reused, and nothing here creates a table per sample. A profiler
-- that allocates is a profiler that changes what it measures.

local Profiler = {}
Profiler.__index = Profiler

local WINDOW = 256

function Profiler.new()
	local self = setmetatable({}, Profiler)
	self.slots = {}
	self.order = {}
	self.sortBuffer = table.create(WINDOW)
	return self
end

function Profiler:slotFor(name)
	local slot = self.slots[name]
	if slot == nil then
		slot = {
			name = name,
			ring = table.create(WINDOW, 0),
			count = 0,
			cursor = 0,
			total = 0,
			max = 0,
			overruns = 0,
			budget = 0,
		}
		self.slots[name] = slot
		self.order[#self.order + 1] = name
		table.sort(self.order)
	end
	return slot
end

function Profiler:sample(name, milliseconds, budgetMs)
	local slot = self:slotFor(name)
	slot.budget = budgetMs or slot.budget
	slot.cursor = slot.cursor % WINDOW + 1
	slot.ring[slot.cursor] = milliseconds
	if slot.count < WINDOW then
		slot.count = slot.count + 1
	end
	slot.total = slot.total + milliseconds
	if milliseconds > slot.max then
		slot.max = milliseconds
	end
	if slot.budget > 0 and milliseconds > slot.budget then
		slot.overruns = slot.overruns + 1
	end
end

-- p95 over the window. Sorting 256 numbers costs far less than the thing
-- being measured, and this runs at most once every two seconds.
function Profiler:percentile(name, fraction)
	local slot = self.slots[name]
	if slot == nil or slot.count == 0 then
		return 0
	end
	local buf = self.sortBuffer
	for i = 1, slot.count do
		buf[i] = slot.ring[i]
	end
	for i = slot.count + 1, #buf do
		buf[i] = nil
	end
	table.sort(buf)
	local index = math.ceil(slot.count * fraction)
	if index < 1 then
		index = 1
	end
	if index > slot.count then
		index = slot.count
	end
	return buf[index]
end

function Profiler:report()
	local rows = {}
	for i = 1, #self.order do
		local name = self.order[i]
		local slot = self.slots[name]
		rows[i] = {
			name = name,
			samples = slot.count,
			meanMs = slot.count > 0 and (slot.total / slot.count) or 0,
			p95Ms = self:percentile(name, 0.95),
			maxMs = slot.max,
			budgetMs = slot.budget,
			overruns = slot.overruns,
		}
	end
	return rows
end

function Profiler:worstOffender()
	local rows = self:report()
	local worst = nil
	for i = 1, #rows do
		local row = rows[i]
		if row.budgetMs > 0 then
			local ratio = row.p95Ms / row.budgetMs
			if worst == nil or ratio > worst.ratio then
				worst = { name = row.name, ratio = ratio, row = row }
			end
		end
	end
	return worst
end

function Profiler:reset()
	self.slots = {}
	self.order = {}
end

return Profiler
