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
TimeModel.minutesToClock(min)   -> number      -- 0..24
TimeModel.phaseOf(clockHours)   -> Phase       -- Dawn|Day|Dusk|Night
TimeModel.phaseWeight(clock)    -> number      -- 0..1 blend for cross-fades
TimeModel.sunElevation(clock, latitudeDeg) -> number   -- for realism checks
```

### 2.1 Pacing (`DayNightConfig.Pacing`)

| Phase | Default length | Notes |
| --- | --- | --- |
| `DAWN` | 45 s | the relief beat; creatures withdraw |
| `DAY` | 210 s | scavenge/fortify |
| `DUSK` | 60 s | **the most important minute in the game** — all tension |
| `NIGHT` | 240 s + 45 s × (ThreatLevel × 4) | scales with Threat |
| **Full cycle** | ~9.5 min at Threat 0.2 → ~12 min at Threat 1.0 | inside the 8–14 min target |

`NIGHT` length is driven by **Threat Level, not by a constant** (`00-VISION.md` P5).

### 2.2 The clock itself
- One in-game day = one real cycle above. `ClockMinutes` advances at
  `1440 / cycleSeconds` minutes per real second.
- Dusk/night are **not** linearly mapped from the real cycle: the clock *slows*
  through `DUSK` (a longer, more cinematic sunset) and *speeds* through `DAY`.
  Implemented as a piecewise rate table in `DayNightConfig.RateCurve` — this is
  what makes the transition feel "seamless and realistic" instead of a constant
  crawl.

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
-- attributes on Workspace.Vitriol.World.TimeAnchor
ClockMinutes : number    -- 0..1440, updated 1 Hz (clients interpolate)
NightIndex   : number    -- 1..N
ThreatLevel  : number    -- 0..1
MoonPhase    : number    -- 0..7
WeatherSeed  : number    -- for client-side rain/fog variation
PhaseName    : string    -- "Dawn"|"Day"|"Dusk"|"Night"  (UI only)
```

`RE_TimeSync` carries the same payload plus `cycleSeconds` and `rateCurveVersion`,
so a late-joining client can reconstruct the exact clock without waiting.

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
6. Moon phase measurably changes night brightness and creature visual range.
