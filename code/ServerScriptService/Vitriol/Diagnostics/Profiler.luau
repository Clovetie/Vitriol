--!strict
-- Profiler.luau
-- Location: ServerScriptService > Vitriol > Diagnostics > Profiler  (Script)
-- Purpose:  The budget watchdog. It measures each cadence slot against its share of
--            the docs/01 §4 row budget and, after GameConfig.Budgets.WatchdogSamples
--            consecutive oversampling windows, drops the server one LOD tier and says
--            so. This is the file that turns "the game is designed around a 1.2 ms
--            frame" from a wish into an enforced invariant.
--
--            WHY IT POLLS AND DOES NOT INSTRUMENT. CadenceService already times every
--            slot dispatch with os.clock, so the numbers exist; reading them here
--            costs one table per slot per report window (10 s) instead of a syscall
--            per slot per frame. That is also why this file contains no priced call
--            inside its Heartbeat closure - the scheduler measures, the watchdog only
--            reads, and hot-loop-scan can therefore report "in a RunService file: 0"
--            for the whole tree, which is the number that matters.
--
--            The "microprofile" half of the original brief is deliberately the
--            per-slot average rather than MicroProfiler.BeginSample scopes: that API is
--            FFlag-gated and unverified in docs/08, and a number that only exists in a
--            dev build cannot protect a shipped one.
-- Requires: ServerStorage.Vitriol.Bootstrap, Config/GameConfig
-- Used by:  Roblox (runs itself); CreatureService/Replicator read LodTier

local ServerStorage = game:GetService("ServerStorage")
local RunService = game:GetService("RunService")

local runtime = require(ServerStorage.Vitriol.Bootstrap).ensure()
local Config = runtime.Config
local cadence = runtime.Cadence

local DEGRADE_MESSAGE = "cadence over budget for "
local consecutive = 0
local elapsed = 0
local reportSeconds = Config.Diagnostics.ProfilerReportSeconds
local multiplier = Config.Budgets.WatchdogMultiplier
local needed = Config.Budgets.WatchdogSamples
local tierCount = #Config.LOD.Tiers

-- degrade(reason) -> ()
-- One tier at a time: an auto-degrader that jumps to the bottom on a single bad
-- window turns a transient hitch into a worse-looking night for everyone.
local function degrade(reason: string): ()
	local nextTier = runtime.LodTier + 1
	if nextTier > tierCount - 1 then
		nextTier = tierCount - 1
	end
	if nextTier == runtime.LodTier then
		return
	end
	runtime.LodTier = nextTier
	if runtime.Time and runtime.Time.anchor then
		-- Replicated on the same instance the clock already uses, so a client that
		-- wants to shed work needs no second subscription.
		runtime.Time.anchor:SetAttribute("LodTier", nextTier)
	end
	-- degradeHooks, not onDegrade: the latter is the registration function, and
	-- running it here would re-register the hook on every degrade.
	local hooks = runtime.degradeHooks
	if hooks then
		for i = 1, #hooks do
			pcall(hooks[i], nextTier, reason)
		end
	end
	if Config.Diagnostics.ProfilerDegradeLog then
		print("[" .. Config.Diagnostics.Prefix .. "] degraded to LOD tier " .. nextTier .. " (" .. reason .. ")")
	end
end

-- report() -> string
-- Walks the slot list once. Allocation-heavy by design: it runs every
-- ProfilerReportSeconds, and a watchdog written to be free is a watchdog that lies.
local function report(): ()
	local names = cadence:slotNames()
	local worst = 0
	local worstName = ""
	for i = 1, #names do
		local name = names[i]
		local stats = cadence:stats(name)
		if stats and stats.enabled then
			local budget = stats.budgetMs
			if budget > 0 then
				local ratio = stats.avgMs / budget
				if ratio > worst then
					worst = ratio
					worstName = name
				end
			end
		end
	end
	if worst > multiplier then
		consecutive = consecutive + 1
		if consecutive >= needed then
			degrade(worstName .. " at " .. string.format("%.2f", worst) .. "x its budget for " .. consecutive .. " windows")
			consecutive = 0
		end
	else
		consecutive = 0
	end
	cadence:clearPeaks()
end

local function onFrame(dt: number): ()
	elapsed = elapsed + dt
	if elapsed >= reportSeconds then
		elapsed = 0
		report()
	end
end

-- onDegrade(svc, fn) -> ()
-- CreatureService/Replicator register here (docs/01 §4's LOD rule); the watchdog
-- knows nothing about creatures on purpose.
function runtime.onDegrade(fn: any): ()
	local hooks = runtime.degradeHooks
	if hooks == nil then
		hooks = {}
		runtime.degradeHooks = hooks
	end
	hooks[#hooks + 1] = fn
end

-- NOT runtime.connection: Bootstrap owns that handle, and overwriting it would leave the
-- scheduler undisconnectable at shutdown.
runtime.profilerConnection = RunService.Heartbeat:Connect(onFrame)
