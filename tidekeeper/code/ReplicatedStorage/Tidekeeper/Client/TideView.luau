--!nonstrict
-- ReplicatedStorage/Tidekeeper/Client/TideView (ModuleScript)
--
-- The tide, on the real clock. Layer: Client. Pure.
--
-- THE CLIENT DOES NOT HAVE ITS OWN CLOCK AND DOES NOT HAVE ITS OWN TIDE.
-- It calls the same `Lib/Tide` the server and the simulation call, with a
-- `now` passed in from above. That is the whole reason the tide can be "the
-- shared clock": every player, every server and every replay agree because
-- they are all evaluating one pure function of wall-clock time, not
-- replicating a value.
--
-- Consequently there is no tide state to get out of sync, nothing to
-- reconcile on a rejoin, and no bandwidth spent on it at all.

local Tide = require(script.Parent.Parent.Lib.Tide)
local Format = require(script.Parent.Format)

local TideView = {}

TideView.CURVE_SAMPLES = 64

-- The tide curve for the day containing `now`, as heights. Used for the arc
-- at the top of the Chart screen.
function TideView.dayCurve(now, out)
	local samples = out or table.create(TideView.CURVE_SAMPLES)
	local dayStart = math.floor(now / 86400) * 86400
	local step = 86400 / (TideView.CURVE_SAMPLES - 1)
	for i = 1, TideView.CURVE_SAMPLES do
		samples[i] = Tide.height(dayStart + (i - 1) * step)
	end
	return samples
end

-- Normalise a height to 0..1 for drawing, against the documented maximum
-- rather than the maximum of the sample -- otherwise a neap day would draw
-- itself as tall as a spring day and the player would learn nothing.
function TideView.normalise(height)
	local n = height / Tide.MAX_HEIGHT
	if n < 0 then
		return 0
	elseif n > 1 then
		return 1
	end
	return n
end

-- When is the next low water? This is the single most actionable number in
-- the game -- low water is when you can comb -- so it gets its own call and
-- its own label.
--
-- Searches forward in coarse steps and then refines. Bounded work, no loops
-- that can run away, and no yields: it is called once per second at most, on
-- a phone.
function TideView.nextLow(now, horizonSeconds)
	local horizon = horizonSeconds or 86400
	local COARSE = 600
	local bestT, bestH = nil, nil
	local t = now
	local limit = now + horizon
	while t < limit do
		local h = Tide.height(t)
		if bestH == nil or h < bestH then
			bestH, bestT = h, t
		end
		t = t + COARSE
	end
	if bestT == nil then
		return nil, nil
	end
	-- Refine within one coarse step either side.
	local lo = bestT - COARSE
	local hi = bestT + COARSE
	local step = 15
	t = lo
	while t <= hi do
		local h = Tide.height(t)
		if h < bestH then
			bestH, bestT = h, t
		end
		t = t + step
	end
	return bestT, bestH
end

-- The whole header model, in one call.
function TideView.header(now)
	local state = Tide.state(now)
	local epoch = Tide.epoch(now)
	local lowAt = TideView.nextLow(now)
	local code = TideView.STATE_CODE[state] or 0
	return {
		state = state,
		stateCode = code,
		stateText = Format.label("TIDE_NOW", { code }),
		epoch = epoch,
		height = Tide.height(now),
		normalised = TideView.normalise(Tide.height(now)),
		secondsToLow = lowAt and math.max(0, math.floor(lowAt - now)) or nil,
		lowText = lowAt and Format.label("CHART_NEXT_LOW", { 0 }):gsub("{1}", Format.duration(lowAt - now)) or nil,
		canComb = state == "LOW" or state == "EBB",
	}
end

-- Mirrors Visit.TIDE_CODE. Kept here rather than imported from Domain/Visit
-- because the client has no business requiring the resolver to name a tide.
TideView.STATE_CODE = { LOW = 1, EBB = 2, FLOOD = 3, SLACK = 4, HIGH = 5 }

return TideView
