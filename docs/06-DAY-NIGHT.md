# VITRIOL — Day/Night Cycle

Seamless, realistic, and — critically — **client-driven**, because of an engine
detail most Roblox day/night systems get wrong (verified in
`08-RESEARCH-NOTES.md` §4).

---

## 1. The single most important fact

> **`Lighting.ClockTime` is flagged `Not Replicated` in the current Roblox API
> reference.** A server that sets `Lighting.ClockTime` changes nothing on any
> client.

Therefore:

```
SERVER (TimeService)                     CLIENT (LightingDriver)
  owns the authoritative clock   ─────►   reads replicated clock
  publishes ClockMinutes                  interpolates locally at 60 Hz
  + ThreatLevel + NightIndex              writes Lighting/Atmosphere/effects
```

**Server is the source of truth for *time*; the client is the authority for
*pixels*.** Every lighting property is written on the client only. This also means
a client that lags gets its own smooth sunrise instead of a hitch.

Transport:
- Scalar state → **attributes** on `Workspace.Vitriol.World.TimeAnchor`
  (`ClockMinutes`, `NightIndex`, `ThreatLevel`, `WeatherSeed`, `MoonPhase`).
  Attributes replicate cheaply and are the right tool for low-rate scalars.
- Snapshots / catch-up on join → `Comms.RE_TimeSync` (server → all).
- Continuous smoothness → the client **interpolates** between received values; it
  never waits for a server tick to move the sun.

---

## 2. Time model

`Shared/TimeModel` is pure and shared by both sides.

```lua
TimeModel.minutesToClock(min)      -> number    -- 0..24, wraps
TimeModel.clockToMinutes(h)        -> number
TimeModel.phaseOf(clockHours)      -> Phase     -- Dawn|Day|Dusk|Night
TimeModel.phaseSpan(phase)         -> startHour, lengthHours
TimeModel.phaseClock(phase, p)     -> clockHours          -- the forward map
TimeModel.phaseProgress(clock, ph) -> 0..1                -- the inverse
TimeModel.phaseWeight(clock)       -> phase, 0..1         -- cross-fade scalar
TimeModel.warp(p, ease)            -> warped, monotone
TimeModel.phaseSeconds(phase, threat) / cycleSeconds(threat)
TimeModel.nextPhase(phase)         -> Phase
TimeModel.skyKey(clockHours)       -> "Sky_Day" | "Sky_Dusk" | "Sky_Night"
TimeModel.sunElevation(clock, latitudeDeg) -> number      -- for realism checks
TimeModel.nextMoonPhase(p) / moonBrightnessDelta(p)
```

That is the complete shared surface, and it is the whole reason both sides agree:
`TimeService` advances it, `LightingDriver` paints it, and neither may re-derive a
boundary locally.

### 2.1 Pacing (`DayNightConfig.Pacing`)

| Phase | Default length | Notes |
| --- | --- | --- |
| `DAWN` | 45 s | the relief beat; creatures withdraw |
| `DAY` | 210 s | scavenge/fortify |
| `DUSK` | 60 s | **the most important minute in the game** — all tension |
| `NIGHT` | 240 s + 45 s × (ThreatLevel × 4) | scales with Threat |
| **Full cycle** | ~9.5 min at Threat 0.2 → ~12 min at Threat 1.0 | inside the 8–14 min target |

`NIGHT` length is driven by **Threat Level, not by a constant** (`00-VISION.md` P5).

### 2.2 The clock itself (rewritten in WP4 — read this before adding a second clock)
- One in-game day = one real cycle above.
- **The phase machine is authoritative and the clock is derived from it.** Each
  phase owns a fixed span of clock hours (`PhaseHours`) and a real duration
  (`Pacing`, Night scaled by Threat); `TimeModel.phaseClock(phase, progress)` maps
  one to the other. There is no free-running `1440 / cycleSeconds` accumulator any
  more, and no `RateCurve` table: a clock integrated from a rate lands on
  `DayStart` at 45 s *by luck*, so one server would say **Night** while the sky
  still said **Dusk** — the exact seam §9.3 forbids. Derived instead of integrated,
  the boundary is hit to the last bit at every Threat Level, which is asserted in
  `tools/vitriol/tests.luau`.
- The "slow dusk, brisk day" feel that `RateCurve` existed to provide is now
  `DayNightConfig.Pacing.Ease`, a per-phase warp of `progress` through smoothstep
  (negative = dawdle through the second half, which is where 18.5–19.8 lives).
  Clamped to ±2/3 so it can never be non-monotone, and exact at both endpoints by
  construction — so it can tint a transition but never move one.

---

## 3. The keyframe table (the whole look, as data)

`DayNightConfig.Keyframes` is an ordered array of stops. Everything else is
interpolated. **No lighting value is ever hard-coded in a controller.**

```lua
{
    Hour        = 18.5,
    OutdoorAmbient = Color3.fromRGB(...),
    Ambient        = Color3.fromRGB(...),
    Brightness     = 1.6,
    ExposureCompensation = -0.2,
    ShadowSoftness = 0.2,
    EnvironmentDiffuseScale  = 0.55,
    EnvironmentSpecularScale = 0.35,
    Fog = { Color = ..., Start = 120, End = 900 },
    Atmosphere = { Density = 0.42, Offset = 0.25, Color = ..., Decay = 0.95,
                   Glare = 0.35, Haze = 1.6 },
    Effects = {
        ColorCorrection = { TintColor = ..., Brightness = 0.0, Contrast = 0.08, Saturation = -0.05 },
        Bloom           = { Intensity = 0.6, Size = 24, Threshold = 1.9 },
        SunRays         = { Intensity = 0.18, Spread = 0.9 },
        DepthOfField    = { FocusDistance = 60, InFocusRadius = 90, FarIntensity = 0.15 },
    },
    SkyKey = "Sky_Dusk",
}
```

### 3.1 Suggested stops (starting point — tune in Studio)

| Hour | Phase | OutdoorAmbient | Brightness | Fog End | Atmosphere Density | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 0.0 | deep night | `(18,22,34)` | 0.35 | 380 | 0.30 | moonlight only, high contrast |
| 3.0 | witching hour | `(14,18,30)` | 0.30 | 320 | 0.34 | the darkest point; max tension |
| 5.0 | pre-dawn | `(38,42,60)` | 0.55 | 450 | 0.38 | first hint of blue |
| 6.3 | dawn | `(120,105,110)` | 1.1 | 700 | 0.40 | long amber horizon |
| 8.0 | morning | `(150,150,155)` | 1.8 | 1200 | 0.34 | crisp |
| 12.0 | noon | `(175,175,178)` | 2.2 | 1600 | 0.28 | max visibility |
| 16.0 | afternoon | `(165,155,145)` | 1.9 | 1300 | 0.32 | warm-up begins |
| 18.5 | dusk | `(120,80,70)` | 1.4 | 800 | 0.42 | **the money shot** |
| 19.8 | last light | `(55,45,60)` | 0.8 | 520 | 0.40 | silhouettes only |
| 21.0 | nightfall | `(24,28,42)` | 0.45 | 400 | 0.32 | the creature is already out |

Interpolation rules:
- **Colours**: interpolate in a perceptual-ish space — convert to HSV-ish via
  `Color3:ToHSV()` and lerp H/S/V, then back. Lerping RGB through `(120,80,70) →
  (24,28,42)` goes muddy grey; HSV lerping keeps the sunset orange alive.
- **Scalars**: `smoothstep` on the *phase weight*, not raw hour distance, so
  transitions hold, then move.
- **Sky**: cross-fade by parenting the matching `Sky` and tweening nothing — Roblox
  does not blend skyboxes, so we switch at the phase boundary where the fog is
  thickest (`19.8`), hiding the pop. Alternative: stack two `Sky` objects and
  tween `Sky.SkyboxBk` transparency — not supported; the fog-cover switch is the
  reliable method.

---

## 4. Realism layer

Small additions that punch far above their cost:

1. **Sun/moon geometry is free.** `Lighting:GetSunDirection()` and
   `Lighting:GetMoonDirection()` are available — use them to drive:
   - shadow length/angle checks,
   - whether a `THERMAL`/`LIGHT` sense should be boosted (creatures avoid the sun),
   - the direction of long shadows for the `DUSK` mood.
2. **Moon phase** (`DayNightConfig.MoonPhase`, 0–7, advanced per night). Drives
   night `Brightness` (±0.12) and `OutdoorAmbient` coolness, and — importantly —
   **the creature's night vision range**. A new moon is a stealth night; a full
   moon is a visibility night. (`Lighting:GetMoonPhase()` exists but is marked
   deprecated in the API reference, so we own our own phase counter.)
3. **Geographic latitude** (`Lighting.GeographicLatitude`) affects how steeply the
   sun sets. Set once; a higher latitude gives longer, more cinematic dusks.
4. **`EnvironmentDiffuseScale` / `EnvironmentSpecularScale` default to 0** in
   current engine versions — set them to ~0.55/0.35 or the sky will not
   contribute to lighting at all and nights will look flat.
5. **Weather** (post-MVP, flag-gated): `Overcast` multiplies `Brightness` ×0.7 and
   `FogEnd` ×0.5; `Rain` additionally **halves `VIBRATION` range** in
   `NoiseField` — a stealth resource (`00-VISION.md` §5.1.3) that comes almost
   for free from the same keyframe table.

---

## 5. Seamless transition — the implementation rules

1. **Never tween `Lighting` from a server.** See §1.
2. **Never set the same property from two places.** `LightingDriver` is the *only*
   writer of `Lighting`, `Atmosphere`, and the post-processing effects. `Debug`
   commands go through it too.
3. **Write at 60 Hz from interpolated state**, not on a `TweenService` tween. Tweens
   fight each other when the server corrects the clock; a per-frame lerp toward the
   target with `damp()` never does.
4. **Rate-limit writes**: only write a property if `|new − current| > epsilon`
   (e.g. `0.002` for scalars). This avoids thousands of pointless property sets.
5. **Debounce on join**: a player joining mid-night receives `RE_TimeSync`, then
   the driver eases in over 1.0 s from a neutral state rather than snapping.
6. **Dusk/night audio-visual handoff**: `CreatureAudio` cross-fades ambience beds
   on `phaseWeight`, not on a discrete phase change, so there is no audible seam.

---

## 6. What the server publishes

```lua
-- attributes on Workspace.Vitriol.World.TimeAnchor, all written by TimeService and
-- nothing else, each only when it actually changed (an attribute write replicates
-- even at the same value). See §2.2 for why the hour hand is derived, not counted.
ClockMinutes  : number   -- 0..1440, updated at Driver.SnapshotRateHz
NightIndex    : number   -- 0..N; "nights survived so far", so it increments on Night -> Dawn
ThreatLevel   : number   -- 0..1
MoonPhase     : number   -- 0..7 index into DayNightConfig.Moon.Phases
WeatherSeed   : number   -- for client-side rain/fog variation
PhaseName     : string   -- "Dawn"|"Day"|"Dusk"|"Night"  (UI and audio beds read this)
PhaseProgress : number   -- 0..1 within the current phase; the mid-transition blend
LodTier       : number   -- 0..3, only after the budget watchdog degrades (docs/01 §4)
WindX/WindY/WindZ, WeatherKind : only while GameConfig.Features.Weather is on
```

`RE_TimeSync` carries, in order: `clockMinutes, phase, phaseProgress, threatLevel,
nightIndex, weatherKind, cycleSeconds` — the same state, but addressed to one client
on join (`TimeService.onPlayerAdded`) and re-broadcast at the snapshot rate, so a
late joiner reconstructs the exact clock and the exact mid-phase blend without waiting.

When `GameConfig.Features.Weather` is switched on, the wind vector is published
alongside the clock (`WindX/Y/Z`) for the same reason the clock is: `NoiseField`
advects scent from it, and the Attune overlay has to advect by the same number or it
would show players a plume the creature is not smelling.

**Anti-cheat note:** the clock is server-authoritative and clients only *render*
it. A client tampering with its own Lighting gains nothing gameplay-relevant,
because every gameplay decision (creature senses, survival drains, Threat) reads
the server clock.

---

## 7. Studio-authored settings (not code)

These are set **manually in Studio** and must not be scripted — several are
deprecated or script-security-gated at runtime:

| Setting | Value | Why not in code |
| --- | --- | --- |
| `Lighting.Technology` / `LightingStyle` | `Future` | `Technology` is marked **deprecated** in the API reference and `LightingStyle` is script-security — set it in the Properties window |
| `Lighting.GlobalShadows` | `true` | static |
| `Lighting.GeographicLatitude` | `45` | static |
| `SoundService.RespectFilteringEnabled` | `true` | required |
| `Workspace.StreamingEnabled` | `true` | required for map size |
| `Sky_Day` / `Sky_Dusk` / `Sky_Night` | human-authored | see `10-HUMAN-AUTHORED.md` |

---

## 8. Debug tooling

`ServerScriptService/Vitriol/Diagnostics/AIDebugDump` exposes (permission-gated):

| Command | Effect |
| --- | --- |
| `setclock 18.5` | jump the clock (server-side, replicated) |
| `speedtime 20` | run the cycle 20× for tuning |
| `phasetest dusk` | hold at a phase and sweep ±0.5 h |
| `dumpkeyframes` | print the interpolated values at the current clock |

Without these, tuning a day/night cycle takes hours instead of minutes.

---

## 9. Acceptance criteria

1. A player joining at any point in the cycle has correct lighting within 1 s, with
   no visible snap.
2. Setting `Lighting.ClockTime` **on the server alone** provably does not change
   the client — documented, and the driver is the only path. (This is the trap;
   the test is that our system doesn't fall in it.)
3. A full cycle from noon → noon shows no discontinuity at any phase boundary
   (record and review; the `19.8` sky switch must be hidden by fog).
4. `Night` length responds to `ThreatLevel` exactly per `Pacing`.
5. Zero `Lighting` property writes originate from a server script
   (grep-verifiable: no `Lighting` reference under `ServerStorage`/`ServerScriptService`).
   **Stronger, and executed:** `tools/vitriol-session-test.js` runs the real services on
   a fake DataModel whose `Lighting` is a poisoned object — fetching it is *counted*,
   writing it *errors*. The run asserts both counters are zero, which is the property the
   rule is about rather than the text pattern that approximates it.
6. Moon phase measurably changes night brightness and creature visual range.
   The clock half is executed (`moonBrightnessDelta`, `nextMoonPhase` advance exactly at
   Night -> Dawn and nowhere else); the "visual range" half belongs to `Senses`, in WP6.
7. **A server with zero players runs a full cycle and logs exactly one line per phase
   change, with the elapsed time in it** — executed by the same harness:
   `node tools/vitriol-session-test.js` counts the log lines against
   `SessionService`'s own transition counter, so a second emitter or a dropped one breaks
   the gate rather than the expected number of cycles this test happens to simulate.
