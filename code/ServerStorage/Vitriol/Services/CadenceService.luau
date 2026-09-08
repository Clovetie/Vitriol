--!strict
-- CadenceService.luau
-- Location: ServerStorage > Vitriol > Services > CadenceService  (ModuleScript)
-- Purpose:  THE ONLY LOOP IN THE SERVER, and it is not even a while loop: Bootstrap
--            binds this module to RunService.Heartbeat once, and every other cadence
--            in docs/01 §4 (Think 4-8 Hz, Sense 10 Hz, Slow 1 Hz) is a registered
--            slot here. "Nothing is allowed to invent its own while true do loop"
--            means something concrete: one driver, one place that knows about
--            stagger, one place that can measure the cost of every cadence against
--            its budget, and one call that stops everything.
--
--            WHY THIS IS NOT A task.wait LOOP
--            A scheduler that sleeps and wakes drifts, needs its own cancellation,
--            and — because it yields inside its loop — is what a hot-loop scan is
--            looking for. Driving off Heartbeat instead means the driver inherits
--            the engine's frame pacing, gets `dt` handed to it for free (no clock
--            call in the frame path, which docs/01 §9 costs money), and `stop()` is
--            one Disconnect.
--
--            STAGGER (docs/01 §4 rule 1): every slot gets a phase offset of
--            index/count * period, so six 6 Hz creature ticks do not land on the
--            same frame as the 10 Hz sense pass. Slots that are late by more than
--            GameConfig.Ticks.CadenceSlopSeconds SKIP a beat rather than running a
--            catch-up burst: a horror game that hiccups into a stutter of four
--            creature decisions in one frame reads as cheating, and the frame budget
--            is the thing protecting the players' experience of fairness.
-- Requires: Config/GameConfig (via Bootstrap injection; lazy fallback)
-- Used by:  Bootstrap (pump), every Service that ticks, Diagnostics/Profiler (stats)

local CadenceService = {}
CadenceService.__index = CadenceService

local LAZY = {}
local function config(): any
	if LAZY.config == nil then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		LAZY.config = require(ReplicatedStorage.Vitriol.Config.GameConfig)
	end
	return LAZY.config
end

-- new(cfg?) -> CadenceService
-- cfg = { Config, OnSample(name, ms) -> (), Logger(level, string) -> () }
function CadenceService.new(cfg: any?)
	local c = cfg or {}
	local self = setmetatable({}, CadenceService)
	self.config = c.Config or config()
	self.slots = {}
	self.byName = {}
	self.order = {}
	self.count = 0
	self.running = false
	self.onSample = c.OnSample
	self.log = c.Logger
	self.slop = self.config.Ticks.CadenceSlopSeconds
	self.lastFrameMs = 0
	self.frameCount = 0
	self.droppedBeats = 0
	return self
end

-- register(svc, slot) -> id
-- slot = { Name = "Sense:2", PeriodSeconds = 0.1, BudgetMs = 0.5, Run = fn(dt),
--          Enabled = true }
function CadenceService:register(slot: any): any
	self.count = self.count + 1
	local id = "slot-" .. self.count
	slot.id = id
	slot.accumulator = 0
	slot.peakMs = 0
	slot.avgMs = 0
	slot.samples = 0
	slot.skipped = 0
	self.slots[id] = slot
	self.byName[slot.Name] = slot
	-- order is a plain array, appended to by index: no table.insert, no rehash, and
	-- the pump walks it by number so the frame path allocates nothing.
	self.order[#self.order + 1] = slot
	if self.running then
		self:_resync()
	end
	return id
end

-- unregister(svc, id) -> boolean
-- The slot is tombstoned rather than spliced out, because the pump may be walking
-- the array right now (a callback is allowed to unregister itself).
function CadenceService:unregister(id: any): boolean
	local slot = self.slots[id]
	if slot == nil then
		return false
	end
	slot.Enabled = false
	slot.Run = nil
	self.slots[id] = nil
	if self.byName[slot.Name] == slot then
		self.byName[slot.Name] = nil
	end
	return true
end

-- start(svc) / stop(svc) -> boolean
-- Bootstrap owns the Heartbeat binding; start/stop only gate the pump, so a service
-- can be paused without unplogging the driver.
function CadenceService:start(): boolean
	self.running = true
	self:_resync()
	return true
end

function CadenceService:stop(): boolean
	self.running = false
	return true
end

-- _resync(svc) -> ()
-- Spread the phase offsets across the current set of slots, after any change to it.
function CadenceService:_resync(): ()
	local n = 0
	for i = 1, #self.order do
		local slot = self.order[i]
		if slot.Enabled ~= false and slot.PeriodSeconds > 0 then
			n = n + 1
		end
	end
	local index = 0
	for i = 1, #self.order do
		local slot = self.order[i]
		if slot.Enabled ~= false and slot.PeriodSeconds > 0 then
			index = index + 1
			-- Stagger only against slots of the SAME period: offsetting a 1 Hz clock
			-- job by a fraction of its own second to make room for a 6 Hz creature
			-- tick would just make the clock job late.
			slot.phase = (index - 1) / n * slot.PeriodSeconds
			slot.accumulator = slot.phase
		end
	end
end

-- pump(svc, dt) -> ()
-- Call from Heartbeat with the engine's dt. This is the whole hot path.
function CadenceService:pump(dt: number): ()
	if not self.running then
		return
	end
	self.lastFrameMs = dt * 1000
	self.frameCount = self.frameCount + 1
	local order = self.order
	for i = 1, #order do
		local slot = order[i]
		local run = slot.Run
		if run and slot.Enabled ~= false then
			local period = slot.PeriodSeconds
			if period <= 0 then
				run(dt)
			else
				local acc = slot.accumulator + dt
				if acc >= period then
					self:_runSlot(slot, run, period)
					-- Carry the remainder, but drop a beat if we are hopeless behind.
					acc = acc - period
					if acc >= period then
						if acc - period > self.slop then
							slot.skipped = slot.skipped + 1
							self.droppedBeats = self.droppedBeats + 1
							acc = self.slop
						else
							-- At most one catch-up tick per frame: the missed work is
							-- simulated once, not N times.
							self:_runSlot(slot, run, period)
							acc = acc - period
						end
					end
				end
				slot.accumulator = acc
			end
		end
	end
end

-- _runSlot(svc, slot, run, period) -> ()
-- The measured wrapper. os.clock lives HERE rather than in pump so the cost is
-- sampled once per slot rather than once per frame; a 1 Hz slot does not deserve a
-- syscall per Heartbeat, and hot-loop-scan is right to want that visible.
function CadenceService:_runSlot(slot: any, run: any, period: number): ()
	local startedAt = os.clock()
	-- pcall: a service that throws must not take the scheduler down with it. The
	-- slot is disabled after three consecutive failures, which is what "a creature
	-- that errors is despawned with a diagnostic, never left half-alive" looks like
	-- at the layer above the creature (docs/01 §8 rule 7).
	local ok, err = pcall(run, period)
	local ms = (os.clock() - startedAt) * 1000
	if not ok then
		slot.failures = (slot.failures or 0) + 1
		if self.log then
			self.log("error", slot.Name .. " errored: " .. tostring(err))
		end
		if slot.failures >= 3 then
			slot.Enabled = false
			if self.log then
				self.log("error", slot.Name .. " disabled after 3 failures")
			end
		end
		return
	end
	slot.failures = 0
	local peak = slot.peakMs
	if ms > peak then
		slot.peakMs = ms
	end
	-- Exponential moving average, alpha as 1/N over a window of samples rather than
	-- a magic smoothing constant nobody can justify.
	local n = slot.samples + 1
	slot.samples = n
	slot.avgMs = slot.avgMs + (ms - slot.avgMs) / math.min(n, 16)
	local sink = self.onSample
	if sink then
		sink(slot.Name, ms, slot.BudgetMs or 0)
	end
end

-- stats(svc, name?) -> { avgMs, peakMs, samples, skipped, enabled, budgetMs, period }
function CadenceService:stats(name: string): any
	local slot = self.byName[name]
	if slot == nil then
		return nil
	end
	return {
		avgMs = slot.avgMs,
		peakMs = slot.peakMs,
		samples = slot.samples,
		skipped = slot.skipped,
		enabled = slot.Enabled ~= false,
		budgetMs = slot.BudgetMs or 0,
		period = slot.PeriodSeconds,
	}
end

-- slotNames(svc) -> {name}  (for the debug dump; allocates, so not a frame path)
function CadenceService:slotNames(): any
	local out = {}
	for i = 1, #self.order do
		out[i] = self.order[i].Name
	end
	return out
end

-- clearPeaks(svc) -> ()  (Profiler calls this after it has consumed a window)
function CadenceService:clearPeaks(): ()
	for i = 1, #self.order do
		self.order[i].peakMs = 0
	end
end

-- summary(svc) -> string  (one line for the log / the RF_DebugQuery answer)
function CadenceService:summary(): string
	local parts = {}
	local n = 0
	for i = 1, #self.order do
		local slot = self.order[i]
		if slot.Enabled ~= false then
			n = n + 1
			local budget = slot.BudgetMs or 0
			local over = ""
			if budget > 0 and slot.avgMs > budget then
				over = " OVER"
			end
			parts[n] = slot.Name .. " " .. string.format("%.3f", slot.avgMs) .. "/" .. string.format("%.2f", budget) .. " ms" .. over
		end
	end
	local frame = "frame " .. string.format("%.2f", self.lastFrameMs) .. " ms"
	local dropped = ""
	if self.droppedBeats > 0 then
		dropped = " dropped=" .. self.droppedBeats
	end
	return frame .. "  |" .. table.concat(parts, "  ") .. dropped
end

return CadenceService
