--!nonstrict
-- ReplicatedStorage/Tidekeeper/Client/ChartView (ModuleScript)
--
-- The chart: the five Currents, and which of them this post has earned.
--
-- SCREEN_CHART has existed as a constant since iteration 5 and rendered
-- nothing but the tide header -- the client switched to it and showed an
-- empty page. The dead-content scan found it from the other end, by noticing
-- that CHART_TITLE and CHART_LOCKED were labels no code could display.
--
-- Pure, like every view: it takes a tier and the post's current and returns
-- a table. No lookups, no services, nothing to mock in a test.
--
-- WHY THE UNLOCK RULE IS NOT DUPLICATED HERE. `EconomyConfig.CURRENT_MIN_TIER`
-- is the single source of truth and it lives in shared config, so both this
-- screen and `ExchangeService:currentAllowed` read the same array. Writing
-- "tier 3" into the view would be the arrangePayload bug again: a client
-- quietly disagreeing with the server about a rule.

local EconomyConfig = require(script.Parent.Parent.Config.EconomyConfig)
local Format = require(script.Parent.Format)

local ChartView = {}

-- Currents are numbered from 0 (the home current, The Shallows) because that
-- is how `S.current` is stored; CURRENT_MIN_TIER is a 1-based array over the
-- same set, hence the +1.
function ChartView.count()
	return #EconomyConfig.CURRENT_MIN_TIER
end

function ChartView.minTierFor(current)
	return EconomyConfig.CURRENT_MIN_TIER[current + 1]
end

function ChartView.isUnlocked(tier, current)
	local minTier = ChartView.minTierFor(current)
	if minTier == nil then
		return false
	end
	return (tier or 1) >= minTier
end

function ChartView.build(tier, current)
	local t = tier or 1
	local rows = {}
	for i = 1, ChartView.count() do
		local id = i - 1
		local minTier = EconomyConfig.CURRENT_MIN_TIER[i]
		local unlocked = ChartView.isUnlocked(t, id)
		rows[i] = {
			current = id,
			name = Format.label("CHART_CURRENT", { id }),
			unlocked = unlocked,
			minTier = minTier,
			isHome = id == (current or 0),
			-- A locked row says WHEN it opens rather than just refusing.
			-- "Opens at tier 3" is a goal; a greyed-out row with no words
			-- is a dead end.
			lockedText = (not unlocked) and Format.label("CHART_LOCKED", { minTier }) or nil,
		}
	end
	return {
		title = Format.label("CHART_TITLE"),
		rows = rows,
		current = current or 0,
		tier = t,
	}
end

return ChartView
