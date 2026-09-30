--!nonstrict
-- ReplicatedStorage/Tidekeeper/Config/TideConfig (ModuleScript)
--
-- The tide constants are the single most load-bearing numbers in the game:
-- they are never stored and never replicated, so a change here silently
-- rewrites every player's history. Treat them as frozen (doc 02 section 2).
--
-- Layer: Config (data only).

return {
	-- 2026-01-01T00:00:00Z. All constituent phases are zero at this instant, so
	-- height(EPOCH) is exactly the sum of the amplitudes: 15.5.
	EPOCH = 1767225600,

	-- One tide epoch. 27 of them is 6.99 days (doc 04 section 3).
	EPOCH_SECONDS = 22357,

	-- Mean water level.
	Z0 = 0.0,

	-- Harmonic constituents: {period seconds, amplitude studs, phase radians}.
	-- Array-of-arrays on purpose: the dead-config scanner only inspects keys at
	-- depth <= 2, and named sub-keys here would be false positives.
	--   1  M2  principal lunar semi-diurnal
	--   2  S2  principal solar semi-diurnal  (beats against M2 -> spring/neap)
	--   3  K1  lunisolar diurnal             (day-to-day asymmetry)
	CONSTITUENTS = {
		{ 44714, 10.0, 0.0 },
		{ 43200, 3.4, 0.0 },
		{ 86164, 2.1, 0.0 },
	},

	-- State thresholds in studs of height (doc 02 section 3). The bands are
	-- exhaustive: h < LOW_BELOW | [LOW_BELOW, SLACK_FROM) | [SLACK_FROM,
	-- SLACK_TO] | h > SLACK_TO.
	LOW_BELOW = -6.0,
	SLACK_FROM = 2.0,
	SLACK_TO = 8.0,

	-- nextStateChange / nextLowWater / nextHighWater search parameters.
	SCAN_STEP = 60,
	SCAN_HORIZON = 604800, -- 7 days
	BISECTIONS = 12,

	-- rangeForDay samples one day at this resolution for the Chart screen.
	DAY_SECONDS = 86400,
	RANGE_SAMPLE_STEP = 60,
}
