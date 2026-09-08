--!strict
-- TimeModel.luau
-- Location: ReplicatedStorage > Vitriol > Shared > TimeModel  (ModuleScript)
-- Purpose:  The whole day/night clock as PURE maths, so the server that owns the
--           clock and the client that paints the sky compute the SAME thing
--           (docs/06-DAY-NIGHT.md §2). TimeService advances it; LightingDriver
--           renders it; neither one may re-derive phase boundaries locally.
--
--           THE DECISION THIS MODULE RECORDS (WP4, correcting docs/06 §2.2)
--   The session state machine (DayNightConfig.Pacing, in real seconds, Night scaled
--   by Threat) is authoritative for WHAT PHASE WE ARE IN. The clock is therefore
--   DERIVED from it rather than free-running: each phase owns a fixed span of
--   clock hours (DayNightConfig.PhaseHours) and a real duration, and within the
--   phase the clock moves by 'warp(progress)'. A free-running clock plus a separate
--   phase machine drifts apart - one server would say "Night" while the sky still
--   says Dusk, which is precisely the discontinuity docs/06 §9.3 forbids.
--   The old 'RateCurve' table was that free-running clock, and it is gone: the
--   cinematic "slow dusk, brisk day" behaviour it existed to provide is now the
--   per-phase 'Pacing.Ease' value, which cannot desynchronise anything.
--
--   Consequence, and it is asserted in the smoke test: at the instant a phase
--   changes, the clock is EXACTLY on the next boundary hour, for every Threat
--   Level, with no numeric integration error - because progress is mapped through
--   warp() rather than accumulated as rate * dt.
--
--           PURE: no Instances, no services, no Lighting. Colour interpolation and
--           every Lighting write are client-only, in LightingDriver (docs/06 §5).
-- Requires: Config/DayNightConfig
-- Used by:  ServerStorage > Vitriol > Services/TimeService, SessionService,
--           ThreatService, StarterPlayer > ... > Controllers/LightingDriver

local DayNightConfig = require(script.Parent.Parent.Config.DayNightConfig)

local TimeModel = {}

-- The order the cycle runs in. SessionService walks it; a phase never skips.
TimeModel.PHASES = DayNightConfig.PHASES

TimeModel.PHASE_HOURS = DayNightConfig.PhaseHours

-- Hours in a day, minutes in a day. Both are structural, so they live here rather
-- than in Config (nobody tunes a day to 23 hours).
local HOURS_PER_DAY = 24
local MINUTES_PER_HOUR = 60
local MINUTES_PER_DAY = HOURS_PER_DAY * MINUTES_PER_HOUR -- 1440, docs/06 §2.2

-- warp(p) = p + ease * (smoothstep(p) - p), and why that shape:
--   * endpoints are exact by construction (smoothstep(0)=0, smoothstep(1)=1), which
--     is what makes the clock hit a boundary hour precisely;
--   |ease| <= MAX_EASE keeps it monotone (d warp/dp = 1 + ease*(6p(1-p) - 1) >=
--     1 - 2/3 > 0), so the sun never runs backwards mid-phase;
--   * ease < 0 means "fast at both ends, slow in the middle", i.e. the clock hangs
--     at the middle of the phase - for Dusk that is the 18.5 golden hour, which is
--     the whole "cinematic sunset" ask, expressed without a second clock.
local MAX_EASE = 2 / 3

local function smoothstep(p: number): number
	if p <= 0 then
		return 0
	elseif p >= 1 then
		return 1
	end
	return p * p * (3 - 2 * p)
end

function TimeModel.clamp01(v: number): number
	if v ~= v or v < 0 then
		return 0
	elseif v > 1 then
		return 1
	end
	return v
end

-- warp(progress, ease) -> warped 0..1
function TimeModel.warp(progress: number, ease: number?): number
	local p = TimeModel.clamp01(progress)
	local e = ease or 0
	if e > MAX_EASE then
		e = MAX_EASE
	elseif e < -MAX_EASE then
		e = -MAX_EASE
	end
	return p + e * (smoothstep(p) - p)
end

-- minutesToClock(minutes) -> hours 0..24
function TimeModel.minutesToClock(minutes: number): number
	local h = (minutes / MINUTES_PER_HOUR) % HOURS_PER_DAY
	if h < 0 then
		h += HOURS_PER_DAY
	end
	return h
end

-- clockToMinutes(hours) -> minutes within the day
function TimeModel.clockToMinutes(clockHours: number): number
	return clockHours * MINUTES_PER_HOUR
end

-- MINUTES_PER_DAY, for a caller that needs to convert without the literals.
TimeModel.MINUTES_PER_DAY = MINUTES_PER_DAY
TimeModel.HOURS_PER_DAY = HOURS_PER_DAY
TimeModel.MAX_EASE = MAX_EASE

-- phaseSpan(phase) -> startHour, lengthInHours  (nil, nil for a phase that is not in
-- DayNightConfig.PHASES)
-- Night wraps past midnight, so its length is computed modulo 24 and the caller uses
-- phaseClock to get a wrapped hour back. The lookup goes through PHASE_START_KEY and
-- the config's own order rather than an if-chain, for two reasons: the naming
-- convention (Dawn -> DawnStart) exists in exactly one place, so a service that wants
-- "the hour Day begins" cannot invent a second one; and an unknown phase name is a
-- caller bug, which must be reported as nil instead of quietly answering Night.
local PHASE_START_KEY = {
	Dawn = "DawnStart",
	Day = "DayStart",
	Dusk = "DuskStart",
	Night = "NightStart",
}

function TimeModel.phaseSpan(phase: any): any, any
	local hours = TimeModel.PHASE_HOURS
	local key = PHASE_START_KEY[phase]
	if key == nil then
		return nil, nil
	end
	local startHour = hours[key]
	local order = TimeModel.PHASES
	local nextHour: any = nil
	for i = 1, #order do
		if order[i] == phase then
			nextHour = hours[PHASE_START_KEY[order[i + 1] or order[1]]]
			break
		end
	end
	if startHour == nil or nextHour == nil then
		return nil, nil
	end
	local length = nextHour - startHour
	if length <= 0 then
		length = length + HOURS_PER_DAY
	end
	return startHour, length
end

-- phaseClock(phase, progress) -> clock hours 0..24
-- The one way to turn "how far through this phase are we" into "what time is it".
function TimeModel.phaseClock(phase: string, progress: number): number
	local startHour, length = TimeModel.phaseSpan(phase)
	local ease = (DayNightConfig.Pacing.Ease or {})[phase]
	local warped = TimeModel.warp(progress, ease)
	local hour = startHour + length * warped
	if hour >= HOURS_PER_DAY then
		hour = hour - HOURS_PER_DAY
	end
	return hour
end

-- phaseProgress(clockHours, phase) -> 0..1 (the inverse of phaseClock, on the warp)
function TimeModel.phaseProgress(clockHours: number, phase: string): number
	local startHour, length = TimeModel.phaseSpan(phase)
	local offset = clockHours - startHour
	if offset < 0 then
		offset = offset + HOURS_PER_DAY
	end
	return TimeModel.clamp01(offset / length)
end

-- phaseOf(clockHours) -> "Dawn"|"Day"|"Dusk"|"Night"
function TimeModel.phaseOf(clockHours: number): string
	local hours = TimeModel.PHASE_HOURS
	local h = clockHours % HOURS_PER_DAY
	if h < 0 then
		h = h + HOURS_PER_DAY
	end
	if h >= hours.NightStart or h < hours.DawnStart then
		return "Night"
	elseif h < hours.DayStart then
		return "Dawn"
	elseif h < hours.DuskStart then
		return "Day"
	end
	return "Dusk"
end

-- phaseWeight(clockHours) -> phase, weight 0..1
-- The cross-fade scalar docs/06 §5.6 asks for ("CreatureAudio cross-fades ambience
-- beds on phaseWeight, not on a discrete phase change"), and the same number the
-- LightingDriver smoothsteps its scalar writes with.
function TimeModel.phaseWeight(clockHours: number): string, number
	local phase = TimeModel.phaseOf(clockHours)
	return phase, TimeModel.phaseProgress(clockHours, phase)
end

-- nextPhase(phase) -> phase
function TimeModel.nextPhase(phase: string): string
	local order = TimeModel.PHASES
	for i = 1, #order do
		if order[i] == phase then
			local nextIndex = i + 1
			if nextIndex > #order then
				nextIndex = 1
			end
			return order[nextIndex]
		end
	end
	return order[1]
end

-- phaseSeconds(phase, threatLevel) -> real seconds (docs/06 §2.1).
-- NIGHT is the only phase Threat Level lengthens (P5: the night is a pressure dial,
-- not a timer - the dial is what moves the number).
function TimeModel.phaseSeconds(phase: string, threatLevel: number): number
	local pacing = DayNightConfig.Pacing
	if phase == "Night" then
		return pacing.NightBaseSeconds + pacing.NightPerThreatSeconds * pacing.NightThreatMultiplier * threatLevel
	elseif phase == "Dawn" then
		return pacing.DawnSeconds
	elseif phase == "Day" then
		return pacing.DaySeconds
	end
	return pacing.DuskSeconds
end

-- cycleSeconds(threatLevel) -> real seconds for a full Dawn->Night.
function TimeModel.cycleSeconds(threatLevel: number): number
	local total = 0
	for i = 1, #TimeModel.PHASES do
		total = total + TimeModel.phaseSeconds(TimeModel.PHASES[i], threatLevel)
	end
	return total
end

-- skyKey(clockHours) -> the Keyframes entry name to use.
-- Chosen by the last stop at or before the hour, wrapping through midnight. The
-- switch itself is a client presentation detail (docs/06 §3.1: no blending exists,
-- so it happens where the fog is thickest), but the ANSWER must be shared, or the
-- audio bed and the sky disagree about which hour it is.
function TimeModel.skyKey(clockHours: number): string
	local stops = DayNightConfig.Keyframes
	local best = nil
	local bestHour = -math.huge
	for i = 1, #stops do
		local hour = stops[i].Hour
		if hour <= clockHours and hour > bestHour then
			bestHour = hour
			best = stops[i].SkyKey
		end
	end
	if best == nil then
		-- Before the first stop of the day: the day ends where it began, so walk
		-- backwards from the last stop instead.
		local last = stops[#stops]
		if last ~= nil then
			return last.SkyKey
		end
		return "Sky_Night"
	end
	return best
end

-- sunElevation(clockHours, latitudeDeg) -> degrees above the horizon.
-- The analytic check behind "should a blind creature care about the sun at all"
-- (docs/06 §4.1): a warm-blooded core that avoids daylight because it is *seen*
-- (silhouette) and because its prey is awake. Declination comes from config so a
-- designer can retune the season without touching this file.
function TimeModel.sunElevation(clockHours: number, latitudeDeg: number?): number
	local lat = latitudeDeg or DayNightConfig.Latitude
	local dec = math.rad(DayNightConfig.SunDeclinationDegrees)
	local phi = math.rad(lat)
	local hourAngle = math.rad((clockHours - 12) * 15)
	local s = math.sin(phi) * math.sin(dec) + math.cos(phi) * math.cos(dec) * math.cos(hourAngle)
	if s > 1 then
		s = 1
	elseif s < -1 then
		s = -1
	end
	return math.asin(s) * (180 / math.pi)
end

-- isDaylight(clockHours) -> boolean, using the horizon crossing only.
function TimeModel.isDaylight(clockHours: number): boolean
	return TimeModel.sunElevation(clockHours) > 0
end

-- nextMoonPhase(phase) -> phase (docs/06 §4.2: we own the counter because
-- Lighting:GetMoonPhase() is deprecated). Advances once per night, wraps.
function TimeModel.nextMoonPhase(phase: number): number
	local phases = DayNightConfig.Moon.Phases
	local nxt = phase + 1
	if nxt >= phases then
		nxt = 0
	end
	return nxt
end

-- moonBrightnessDelta(phase) -> added Lighting.Brightness, scaled by how full the
-- moon is (new moon = darkest, full = brightest).
function TimeModel.moonBrightnessDelta(phase: number): number
	local phases = DayNightConfig.Moon.Phases
	local full = phases * 0.5 -- 4 of 8 in the default table
	local distance = math.abs(phase - full) / full
	return DayNightConfig.Moon.BrightnessDelta * (1 - distance)
end

return TimeModel
