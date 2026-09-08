--!strict
-- DayNightConfig.luau
-- Location: ReplicatedStorage > Vitriol > Config > DayNightConfig  (ModuleScript)
-- Purpose:  The whole look and pacing of the day/night cycle, as data.
--           IMPORTANT: these values are applied on the CLIENT by LightingDriver,
--           because Lighting.ClockTime is flagged Not Replicated
--           (docs/06-DAY-NIGHT.md §1, docs/08-RESEARCH-NOTES.md §4.1).
--           No lighting value may ever be hard-coded in a controller.
-- Requires: (none)
-- Used by:  Services/TimeService, Services/ThreatService, Client/LightingDriver

local DayNightConfig = {}

-- Phase lengths in REAL seconds (docs/06 §2.1). NIGHT scales with Threat Level.
DayNightConfig.Pacing = {
	DawnSeconds = 45,
	DaySeconds = 210,
	DuskSeconds = 60,
	NightBaseSeconds = 240,
	NightPerThreatSeconds = 45, -- added 4x, so Threat 1.0 adds 180s
	StartAt = "Day", -- first phase of a round
}

-- Phase boundaries in CLOCK HOURS (0-24). Used for phase lookup + blending.
-- The phase ORDER, next to the hours that bound it. This lives in config rather than
-- in TimeModel because SessionService, the debug dump and the client all walk the same
-- list, and a second copy of an order is how two systems start disagreeing about it.
DayNightConfig.PHASES = { "Dawn", "Day", "Dusk", "Night" }

DayNightConfig.PhaseHours = {
	DawnStart = 5.0,
	DayStart = 8.0,
	DuskStart = 17.5,
	NightStart = 20.0,
}

-- How the clock MOVES inside a phase (docs/06 §2.2, rewritten in WP4).
-- The phase machine owns real durations; the clock is derived, so 'Ease' is the
-- only knob left for "slow dusk, brisk day" and it can never desynchronise the sky
-- from the gameplay phase. Semantics (see Shared/TimeModel.warp): 0 is linear,
-- +1 slows the ends and speeds the middle, -1 speeds the ends and HANGS the middle.
-- Dusk hangs, which is where the golden hour lives. Clamped to +-2/3 so the clock
-- can never run backwards inside a phase.
DayNightConfig.Pacing.Ease = {
	Dawn = 0.35,
	Day = 0.60,
	Dusk = -0.60,
	Night = -0.20,
}

-- NIGHT = NightBaseSeconds + NightPerThreatSeconds * NightThreatMultiplier * Threat.
-- The multiplier is written out instead of buried in the arithmetic so the doc's
-- "240 s + 45 s x (ThreatLevel x 4)" is a lookup, not a reading test.
DayNightConfig.Pacing.NightThreatMultiplier = 4

-- Moon phase drives night brightness AND the creature's effective visual range
-- (docs/06 §4.2). Advanced once per night by NightService.
DayNightConfig.Moon = {
	Phases = 8, -- 0 = new, 4 = full
	BrightnessDelta = 0.12, -- +/- at full/new
	CreatureVisionMultiplier = { new = 0.75, full = 1.25 },
	StartPhase = 2,
}

DayNightConfig.Latitude = 45 -- steeper latitude = longer, more cinematic dusks

-- Season, for the sun-elevation check behind creature sunlight avoidance
-- (docs/06 §4.1, TimeModel.sunElevation). 0 = equinox, +23.44 = northern summer.
DayNightConfig.SunDeclinationDegrees = 12.0

-- The keyframe table. Everything between stops is interpolated. Colours
-- interpolate in HSV, scalars via smoothstep on the phase weight (docs/06 §3).
-- Values below are a TUNED STARTING POINT - refine in Studio with 'setclock'.
DayNightConfig.Keyframes = {
	{
		Hour = 0.0, SkyKey = "Sky_Night",
		OutdoorAmbient = { 18, 22, 34 }, Ambient = { 12, 14, 22 },
		Brightness = 0.35, ExposureCompensation = 0.10, ShadowSoftness = 0.35,
		EnvironmentDiffuseScale = 0.45, EnvironmentSpecularScale = 0.25,
		Fog = { Color = { 10, 12, 20 }, Start = 60, End = 380 },
		Atmosphere = { Density = 0.30, Offset = 0.25, Color = { 20, 24, 40 }, Decay = 0.95, Glare = 0.10, Haze = 1.0 },
		Effects = {
			ColorCorrection = { TintColor = { 190, 200, 235 }, Brightness = -0.02, Contrast = 0.12, Saturation = -0.25 },
			Bloom = { Intensity = 0.4, Size = 24, Threshold = 1.6 },
			SunRays = { Intensity = 0.0, Spread = 0.9 },
			DepthOfField = { FocusDistance = 40, InFocusRadius = 60, FarIntensity = 0.25 },
		},
	},
	{
		Hour = 3.0, SkyKey = "Sky_Night",
		OutdoorAmbient = { 14, 18, 30 }, Ambient = { 10, 12, 20 },
		Brightness = 0.30, ExposureCompensation = 0.15, ShadowSoftness = 0.35,
		EnvironmentDiffuseScale = 0.42, EnvironmentSpecularScale = 0.22,
		Fog = { Color = { 8, 10, 18 }, Start = 50, End = 320 },
		Atmosphere = { Density = 0.34, Offset = 0.25, Color = { 16, 20, 36 }, Decay = 0.95, Glare = 0.08, Haze = 1.2 },
		Effects = {
			ColorCorrection = { TintColor = { 180, 190, 230 }, Brightness = -0.04, Contrast = 0.14, Saturation = -0.30 },
			Bloom = { Intensity = 0.35, Size = 24, Threshold = 1.5 },
			SunRays = { Intensity = 0.0, Spread = 0.9 },
			DepthOfField = { FocusDistance = 35, InFocusRadius = 55, FarIntensity = 0.30 },
		},
	},
	{
		Hour = 5.0, SkyKey = "Sky_Night",
		OutdoorAmbient = { 38, 42, 60 }, Ambient = { 22, 24, 34 },
		Brightness = 0.55, ExposureCompensation = 0.05, ShadowSoftness = 0.30,
		EnvironmentDiffuseScale = 0.48, EnvironmentSpecularScale = 0.28,
		Fog = { Color = { 30, 32, 48 }, Start = 60, End = 450 },
		Atmosphere = { Density = 0.38, Offset = 0.25, Color = { 40, 44, 66 }, Decay = 0.95, Glare = 0.15, Haze = 1.4 },
		Effects = {
			ColorCorrection = { TintColor = { 200, 200, 225 }, Brightness = -0.02, Contrast = 0.10, Saturation = -0.15 },
			Bloom = { Intensity = 0.45, Size = 24, Threshold = 1.7 },
			SunRays = { Intensity = 0.0, Spread = 0.9 },
			DepthOfField = { FocusDistance = 45, InFocusRadius = 70, FarIntensity = 0.22 },
		},
	},
	{
		Hour = 6.3, SkyKey = "Sky_Day",
		OutdoorAmbient = { 120, 105, 110 }, Ambient = { 55, 50, 52 },
		Brightness = 1.10, ExposureCompensation = 0.0, ShadowSoftness = 0.25,
		EnvironmentDiffuseScale = 0.55, EnvironmentSpecularScale = 0.32,
		Fog = { Color = { 120, 100, 90 }, Start = 80, End = 700 },
		Atmosphere = { Density = 0.40, Offset = 0.25, Color = { 150, 110, 90 }, Decay = 0.95, Glare = 0.30, Haze = 1.6 },
		Effects = {
			ColorCorrection = { TintColor = { 255, 225, 205 }, Brightness = 0.0, Contrast = 0.08, Saturation = -0.05 },
			Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.9 },
			SunRays = { Intensity = 0.15, Spread = 0.9 },
			DepthOfField = { FocusDistance = 60, InFocusRadius = 90, FarIntensity = 0.15 },
		},
	},
	{
		Hour = 12.0, SkyKey = "Sky_Day",
		OutdoorAmbient = { 175, 175, 178 }, Ambient = { 78, 78, 80 },
		Brightness = 2.20, ExposureCompensation = -0.20, ShadowSoftness = 0.20,
		EnvironmentDiffuseScale = 0.55, EnvironmentSpecularScale = 0.35,
		Fog = { Color = { 170, 180, 190 }, Start = 150, End = 1600 },
		Atmosphere = { Density = 0.28, Offset = 0.25, Color = { 170, 190, 210 }, Decay = 0.95, Glare = 0.25, Haze = 0.9 },
		Effects = {
			ColorCorrection = { TintColor = { 255, 255, 255 }, Brightness = 0.0, Contrast = 0.05, Saturation = 0.0 },
			Bloom = { Intensity = 0.5, Size = 24, Threshold = 2.0 },
			SunRays = { Intensity = 0.10, Spread = 0.9 },
			DepthOfField = { FocusDistance = 80, InFocusRadius = 120, FarIntensity = 0.10 },
		},
	},
	{
		Hour = 16.0, SkyKey = "Sky_Day",
		OutdoorAmbient = { 165, 155, 145 }, Ambient = { 72, 68, 64 },
		Brightness = 1.90, ExposureCompensation = -0.10, ShadowSoftness = 0.22,
		EnvironmentDiffuseScale = 0.55, EnvironmentSpecularScale = 0.35,
		Fog = { Color = { 165, 155, 140 }, Start = 120, End = 1300 },
		Atmosphere = { Density = 0.32, Offset = 0.25, Color = { 175, 160, 140 }, Decay = 0.95, Glare = 0.28, Haze = 1.1 },
		Effects = {
			ColorCorrection = { TintColor = { 255, 245, 230 }, Brightness = 0.0, Contrast = 0.07, Saturation = -0.02 },
			Bloom = { Intensity = 0.55, Size = 24, Threshold = 1.95 },
			SunRays = { Intensity = 0.12, Spread = 0.9 },
			DepthOfField = { FocusDistance = 70, InFocusRadius = 100, FarIntensity = 0.12 },
		},
	},
	{
		Hour = 18.5, SkyKey = "Sky_Dusk",
		OutdoorAmbient = { 120, 80, 70 }, Ambient = { 52, 40, 38 },
		Brightness = 1.40, ExposureCompensation = 0.0, ShadowSoftness = 0.28,
		EnvironmentDiffuseScale = 0.55, EnvironmentSpecularScale = 0.35,
		Fog = { Color = { 120, 80, 65 }, Start = 90, End = 800 },
		Atmosphere = { Density = 0.42, Offset = 0.25, Color = { 160, 95, 65 }, Decay = 0.95, Glare = 0.35, Haze = 1.6 },
		Effects = {
			ColorCorrection = { TintColor = { 255, 210, 180 }, Brightness = -0.01, Contrast = 0.08, Saturation = -0.05 },
			Bloom = { Intensity = 0.6, Size = 24, Threshold = 1.9 },
			SunRays = { Intensity = 0.18, Spread = 0.9 },
			DepthOfField = { FocusDistance = 60, InFocusRadius = 90, FarIntensity = 0.15 },
		},
	},
	{
		Hour = 19.8, SkyKey = "Sky_Dusk",
		OutdoorAmbient = { 55, 45, 60 }, Ambient = { 30, 26, 34 },
		Brightness = 0.80, ExposureCompensation = 0.05, ShadowSoftness = 0.32,
		EnvironmentDiffuseScale = 0.50, EnvironmentSpecularScale = 0.30,
		Fog = { Color = { 55, 45, 55 }, Start = 70, End = 520 },
		Atmosphere = { Density = 0.40, Offset = 0.25, Color = { 80, 60, 70 }, Decay = 0.95, Glare = 0.22, Haze = 1.5 },
		Effects = {
			ColorCorrection = { TintColor = { 235, 210, 225 }, Brightness = -0.03, Contrast = 0.10, Saturation = -0.12 },
			Bloom = { Intensity = 0.5, Size = 24, Threshold = 1.8 },
			SunRays = { Intensity = 0.10, Spread = 0.9 },
			DepthOfField = { FocusDistance = 50, InFocusRadius = 75, FarIntensity = 0.20 },
		},
	},
	{
		Hour = 21.0, SkyKey = "Sky_Night",
		OutdoorAmbient = { 24, 28, 42 }, Ambient = { 16, 18, 28 },
		Brightness = 0.45, ExposureCompensation = 0.08, ShadowSoftness = 0.34,
		EnvironmentDiffuseScale = 0.46, EnvironmentSpecularScale = 0.26,
		Fog = { Color = { 14, 16, 26 }, Start = 55, End = 400 },
		Atmosphere = { Density = 0.32, Offset = 0.25, Color = { 26, 30, 48 }, Decay = 0.95, Glare = 0.12, Haze = 1.1 },
		Effects = {
			ColorCorrection = { TintColor = { 190, 200, 235 }, Brightness = -0.03, Contrast = 0.12, Saturation = -0.22 },
			Bloom = { Intensity = 0.4, Size = 24, Threshold = 1.6 },
			SunRays = { Intensity = 0.0, Spread = 0.9 },
			DepthOfField = { FocusDistance = 40, InFocusRadius = 60, FarIntensity = 0.25 },
		},
	},
}

-- Sky switch happens at the fog-thickest hour to hide the pop: Roblox does not
-- blend Sky objects (docs/06 §3.1).
DayNightConfig.SkySwitchHour = 19.8

-- Weather (post-MVP, flag-gated). Rain MASKS vibration - a stealth resource
-- (docs/00-VISION.md §5.1.3).
DayNightConfig.Weather = {
	Clear = { BrightnessMul = 1.0, FogEndMul = 1.0, VibrationMask = 1.0, AirMask = 1.0 },
	Overcast = { BrightnessMul = 0.70, FogEndMul = 0.50, VibrationMask = 1.0, AirMask = 0.95 },
	Rain = { BrightnessMul = 0.60, FogEndMul = 0.40, VibrationMask = 0.50, AirMask = 0.80 },
	Storm = { BrightnessMul = 0.45, FogEndMul = 0.30, VibrationMask = 0.35, AirMask = 0.65 },
}

-- LightingDriver behaviour (docs/06 §5).
DayNightConfig.Driver = {
	Epsilon = 0.002, -- skip writes smaller than this
	JoinEaseSeconds = 1.0, -- ease in on join instead of snapping
	SnapshotRateHz = 1, -- how often the server republishes the clock attribute
	InterpolationLagSeconds = 0.0, -- clock is smooth, no need for lag
	AnchorMaterial = "Plastic", -- the 0-size TimeAnchor part; invisible either way (docs/06 §6)
}

return DayNightConfig
