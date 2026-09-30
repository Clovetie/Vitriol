--!nonstrict
-- ReplicatedStorage/Tidekeeper/Lib/Tide (ModuleScript)
--
-- Layer L0: pure. No services, no `game`, no time reads, no yields.
--
-- THE SHARED CLOCK (doc 02).
--
-- The tide is a pure function of UTC seconds. It is never stored, never
-- replicated and never authoritative on one side: server, client and headless
-- test each compute it from `t` and necessarily agree. `t` is ALWAYS an
-- argument -- this module must never learn what time it is.
--
-- Hot-loop rule (doc 02 section 9): `Tide.height` runs every frame on the
-- client. It allocates nothing, calls no service, and reads no clock.

local TideConfig = require(script.Parent.Parent.Config.TideConfig)

local Tide = {}

local floor = math.floor
local ceil = math.ceil
local cos = math.cos
local sin = math.sin

local TAU = 6.283185307179586

local EPOCH = TideConfig.EPOCH
local EPOCH_SECONDS = TideConfig.EPOCH_SECONDS
local Z0 = TideConfig.Z0
local LOW_BELOW = TideConfig.LOW_BELOW
local SLACK_FROM = TideConfig.SLACK_FROM
local SLACK_TO = TideConfig.SLACK_TO

-- Unroll the constituent table into scalars at load time. Three reasons:
-- the height function is called every frame, indexing a nested table in a loop
-- is the single biggest cost here, and unrolling makes the zero-allocation
-- guarantee obvious by inspection rather than by trust.
local C = TideConfig.CONSTITUENTS
local W1 = TAU / C[1][1]
local A1 = C[1][2]
local P1 = C[1][3]
local W2 = TAU / C[2][1]
local A2 = C[2][2]
local P2 = C[2][3]
local W3 = TAU / C[3][1]
local A3 = C[3][2]
local P3 = C[3][3]

Tide.EPOCH = EPOCH
Tide.EPOCH_SECONDS = EPOCH_SECONDS
-- The theoretical bound: |height| can never exceed the sum of the amplitudes.
Tide.MAX_HEIGHT = A1 + A2 + A3

-- Height in studs above mean water at UTC second `t`.
function Tide.height(t)
	local x = t - EPOCH
	return Z0 + A1 * cos(W1 * x + P1) + A2 * cos(W2 * x + P2) + A3 * cos(W3 * x + P3)
end

-- Analytic derivative, studs per second. Positive means flooding (rising).
-- This is the ONLY thing allowed to decide EBB vs FLOOD: a finite difference
-- would be sampling-rate dependent and therefore not deterministic across
-- callers (doc 02 section 3).
function Tide.velocity(t)
	local x = t - EPOCH
	return -(A1 * W1 * sin(W1 * x + P1) + A2 * W2 * sin(W2 * x + P2) + A3 * W3 * sin(W3 * x + P3))
end

-- "LOW" | "EBB" | "FLOOD" | "SLACK" | "HIGH". The bands are exhaustive.
function Tide.state(t)
	local h = Tide.height(t)
	if h < LOW_BELOW then
		return "LOW"
	end
	if h > SLACK_TO then
		return "HIGH"
	end
	if h >= SLACK_FROM then
		return "SLACK"
	end
	if Tide.velocity(t) >= 0 then
		return "FLOOD"
	end
	return "EBB"
end

-- Tide epoch index. Negative for times before the game's epoch; floor division
-- keeps the sequence monotonic across that boundary.
function Tide.epoch(t)
	return floor((t - EPOCH) / EPOCH_SECONDS)
end

-- Inverse of `epoch`: the UTC second at which tide epoch `n` begins.
function Tide.epochStart(n)
	return EPOCH + n * EPOCH_SECONDS
end

-- How far through epoch `epoch(t)` we are, in [0, 1).
function Tide.epochProgress(t)
	local n = Tide.epoch(t)
	return (t - Tide.epochStart(n)) / EPOCH_SECONDS
end

-- The next integer second strictly after `t` at which `state` differs from the
-- state at `t`. Returns `(second, newState)`, or nil if no change happens
-- inside `horizon` seconds.
--
-- Method (doc 02 section 6): a coarse scan at SCAN_STEP to bracket the change,
-- then BISECTIONS halvings, then a ceil and a short forward walk so the value
-- returned is the FIRST integer second that actually reports the new state.
-- Without that last walk the answer can land one second early and a countdown
-- built on it would visibly stall at zero.
function Tide.nextStateChange(t, horizon)
	local step = TideConfig.SCAN_STEP
	local limit = horizon or TideConfig.SCAN_HORIZON
	local start = floor(t)
	local from = Tide.state(start)
	local a = start
	local stop = start + limit
	while a < stop do
		local b = a + step
		if b > stop then
			b = stop
		end
		if Tide.state(b) ~= from then
			local lo = a
			local hi = b
			for _ = 1, TideConfig.BISECTIONS do
				local mid = (lo + hi) * 0.5
				if Tide.state(mid) == from then
					lo = mid
				else
					hi = mid
				end
			end
			local second = ceil(hi)
			-- At most a couple of iterations: hi is already within
			-- step/2^BISECTIONS of the true crossing.
			while second > start and Tide.state(second - 1) ~= from do
				second = second - 1
			end
			while Tide.state(second) == from do
				second = second + 1
			end
			return second, Tide.state(second)
		end
		a = b
	end
	return nil
end

-- Local extrema by velocity sign change, bisected on `velocity` rather than on
-- `state` so the answer is the true turning point and not a band boundary.
local function nextTurning(t, wantRising, horizon)
	local step = TideConfig.SCAN_STEP
	local limit = horizon or TideConfig.SCAN_HORIZON
	local start = floor(t)
	local a = start
	local va = Tide.velocity(a)
	local stop = start + limit
	while a < stop do
		local b = a + step
		if b > stop then
			b = stop
		end
		local vb = Tide.velocity(b)
		-- Low water: velocity goes negative -> positive. High water: the reverse.
		local crossed
		if wantRising then
			crossed = va < 0 and vb >= 0
		else
			crossed = va > 0 and vb <= 0
		end
		if crossed then
			local lo = a
			local hi = b
			for _ = 1, TideConfig.BISECTIONS do
				local mid = (lo + hi) * 0.5
				local vm = Tide.velocity(mid)
				local sameAsLo
				if wantRising then
					sameAsLo = vm < 0
				else
					sameAsLo = vm > 0
				end
				if sameAsLo then
					lo = mid
				else
					hi = mid
				end
			end
			return floor(hi + 0.5)
		end
		a = b
		va = vb
	end
	return nil
end

function Tide.nextLowWater(t, horizon)
	return nextTurning(t, true, horizon)
end

function Tide.nextHighWater(t, horizon)
	return nextTurning(t, false, horizon)
end

-- Min and max height over the UTC day containing `t`, for the Chart screen.
-- Returns `(minHeight, maxHeight, dayStart)`.
function Tide.rangeForDay(t)
	local day = TideConfig.DAY_SECONDS
	local dayStart = floor(t / day) * day
	local sample = TideConfig.RANGE_SAMPLE_STEP
	local lo = math.huge
	local hi = -math.huge
	local s = dayStart
	local dayEnd = dayStart + day
	while s < dayEnd do
		local h = Tide.height(s)
		if h < lo then
			lo = h
		end
		if h > hi then
			hi = h
		end
		s = s + sample
	end
	return lo, hi, dayStart
end

-- The state a whole tide epoch is characterised by: sampled at its midpoint.
-- The resolver uses this so that "the tide during epoch e" is a single stable
-- value rather than something that depends on when a visit happened to land.
function Tide.stateForEpoch(n)
	return Tide.state(Tide.epochStart(n) + EPOCH_SECONDS * 0.5)
end

return Tide
