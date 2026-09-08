# VITRIOL — Kill Choreography, Body Integrity & Gore Contract

`00-VISION.md` P6: death is a scene, not a screen. This document specifies the
procedural kill, the body-integrity model that drives it, and the **exact
contract** the supplied Gore module must satisfy.

> **Verified gap:** the project owner refers to a "provided gore module". This
> repository contains **only** `tools/` and these documents — no gore module
> exists here. Rather than block, this document specifies the interface
> (`GoreConfig` + `GoreAdapter`) so the creature system can be built and tested
> now, and the real module drops in later behind the same API.

---

## 1. The sequence

```
  CONTACT ──► GRAB ──► LIFT/DRAG ──► COIL ──► TENDERIZE ──┬─► CONSUME ──► DISCARD
     │          │          │           │          │       │                   │
     │          │          │           │          │       └─► REGURGITATE     │
     │          │          │           │          └──────────► (rare, humour) │
     │          │          │           └─► ESCAPE (player wins the mash)      │
     │          │          └─► THROW (if interrupted / knocked)               │
     │          └─► FUMBLE (low GripTenacity / injured tendril)               │
     └─► MISS
```

Every arrow is a **state**, and every state is interruptible. This is what makes
the kill feel like an event rather than an animation.

### 1.1 State table

| State | Duration | What happens | Interruptible by |
| --- | --- | --- | --- |
| `GRAB` | 0.15–0.3 s | tip contacts `GrabTarget`; victim enters `Physics` state; first tendril wraps | victim `IKMoveTo` failing (obstruction) → `FUMBLE` |
| `LIFT` | 0.3–0.8 s | victim raised; 2nd/3rd tendrils join; camera snaps to `VictimCamera` | damage to creature above threshold → `THROW` |
| `DRAG` | 0–4 s | optional: creature relocates while holding (toward its den). Long, terrifying, escapable | `ESCAPE`, `THROW` |
| `COIL` | 0.6–1.2 s | helical wrap completes (see `03` §6.2); audio: rope tension | `ESCAPE` |
| `TENDERIZE` | 2.5–6 s | shear oscillation; region damage accrues; **severs happen here** | `THROW`, creature damage |
| `CONSUME` | 2–4 s | remains drawn into the core; core visibly swells; metabolism restored | nothing (this is the commit) |
| `DISCARD` | 0.5 s | one severed piece is flung away (see §4) | — |
| `THROW` | 0.4 s | victim flung with impulse; takes fall/impact damage; gets up | — |
| `ESCAPE` | 0.2 s | coil bursts; victim dropped with `GripTenacity`-scaled injury | — |
| `FUMBLE` | 0.6 s | failed grip; creature recoils, re-coils (this is the "wounded predator" tell) | — |

### 1.2 Victim presentation
- `VictimCamera` (LocalScript) takes over: tight FOV, muffled low-pass audio,
  heartbeat, red vignette, screen-space "squeeze" distortion driven by the coil's
  compression factor.
- **Other players see the whole thing in third person** — the creature reconfigures
  around the victim. This is the game's shareable moment; do not hide it.
- Audio language: wet rope tension → cartilage → a wet *give* → silence, then the
  sub-bass "swallow". No screams from the creature (it has no mouth).

---

## 2. Body integrity model (`Shared/RegionIntegrity`)

The kill is **procedural** because damage accrues per body region and the creature
removes pieces as regions fail. No two kills are the same because the shear
distribution depends on the wrap geometry, the creature's `ShearRate`, and how the
victim is oriented.

### 2.1 Regions

| Region | Base integrity | Vulnerability | Severable | Contents |
| --- | --- | --- | --- | --- |
| `Head` | 60 | 1.4 | yes | skull chunk |
| `Torso` | 180 | 0.7 | no (core consumption only) | viscera |
| `LeftArm` / `RightArm` | 70 | 1.1 | yes | arm |
| `LeftLeg` / `RightLeg` | 90 | 1.0 | yes | leg |
| `Hand` × 2 | 35 | 1.3 | yes | hand |

Values live in `GoreConfig.Regions`, not in code.

### 2.2 Shear damage (the "tenderize" mechanic)

The creature applies **friction-based internal shear**, mirroring how a constrictor
works:

```
v_shear   = |ω_coil| · r_region + |v_oscillation|        -- relative surface speed
stress    = v_shear · gripPressure · vulnerability[region]
integrity[region] -= stress · dt · ShearRate · tenderizeCurve(t)
```

- `ω_coil` — angular rate of the wrap (from the genome's `ShearRate`, 6–14 Hz).
- `r_region` — radius of that region from the coil axis (limbs at the outside take
  more; the torso, compressed at the centre, takes less but for longer).
- `gripPressure` — from `GripTenacity`, rising as the mash progress fails.
- `tenderizeCurve(t)` — ramps up over the first 1.5 s (the creature "settles in").

**This is why limbs come off:** distal regions are lighter, more vulnerable, and
further from the axis, so they fail first — biomechanically plausible and it makes
each kill different depending on how the victim was held.

### 2.3 Severance

```
if integrity[region] <= 0 then
    sever(region)
    → GoreAdapter.spawnSevered(region, worldCF, velocity)
    → mark region absent; downstream regions detach too (Hand goes with Arm)
    → emit NoiseField SCENT burst (blood) ×6
    → victim takes integrity-proportional damage
```

Downstream rule: severing `RightArm` also removes `RightHand`. Enforced in one
place (`RegionIntegrity.sever`) so it can't drift.

---

## 3. The Gore module contract

`ReplicatedStorage/Vitriol/Shared/GoreAdapter` is the **only** caller. Whatever
the supplied module looks like, we adapt to it here — no other module touches gore.

### 3.1 Assumed API (to be confirmed against the real module)

```lua
Gore.emit(kind: string, params: {
    Position  : Vector3,
    CFrame    : CFrame?,     -- orientation of the emission
    Velocity  : Vector3?,    -- initial impulse
    Scale     : number?,     -- 1 = human-sized
    Intensity : number?,     -- 0..1, how much
    Color     : Color3?,     -- override
    LifeTime  : number?,     -- auto-cleanup seconds
    Attachment: Instance?,   -- optional: parent to a part instead of world
}) -> ()
```

| `kind` | Used for |
| --- | --- |
| `"blood_spray"` | impact, severance |
| `"blood_mist"` | tenderize oscillation (fine, sustained) |
| `"blood_pool"` | ground decal, persists |
| `"chunk"` | small tissue pieces |
| `"severed"` | a named limb (needs a `Region` key) |
| `"viscera"` | consumption |
| `"gib_burst"` | overkill / vehicle impact |

### 3.2 What the adapter guarantees regardless

1. **Server authority.** All gore is spawned on the server; clients get it through
   normal instance replication. No client may spawn gore.
2. **Budget.** A hard cap (`GoreConfig.MaxActiveEmitters`, default 24) with
   round-robin eviction. Gore must never be the reason the server drops frames.
3. **Lifetime.** Everything gets `Debris`-style cleanup (`GoreConfig.Lifetimes`).
4. **Graceful degradation.** If the supplied module is missing or its API differs,
   `GoreAdapter` falls back to built-in placeholder parts/particles and logs
   **once**. The creature system must never error because gore is absent.
5. **Content gate.** `GoreConfig.Intensity` scales everything so the same code can
   ship a low-gore build (Roblox community standards matter — see §5).

### 3.3 Fallback (built-in, no assets required)

If the real module is unavailable, the adapter uses:
- `Part` spheres with `Material = Enum.Material.Slate`, dark red, small, unanchored,
  `CanCollide = false`, `Transparency` ramped by a `TweenService` tween, destroyed
  on lifetime.
- A `ParticleEmitter` template with `Rate`, `Speed`, `Lifetime` from config.
- A `Decal` on the nearest downward surface (one raycast, budgeted) for pools.

This is intentionally ugly. It exists so the kill choreography can be **played and
balanced** before the real gore module lands.

---

## 4. Discard behaviour (the "snatches pieces away" ask)

After `CONSUME`, with probability `GoreConfig.DiscardChance` (default 0.65):

1. Choose a held severed piece (preferring the most recently severed).
2. One tendril flicks it away with `ApplyImpulse` along a randomised vector biased
   *away from the den* — predators cache scraps.
3. The piece lands and becomes a **persistent scent marker** (`NoiseField`, decaying
   over ~6 min) and a **spatial memory entry** for the creature.
4. Players who find a discarded limb learn two things: it fed here, and it went
   that way. **Free storytelling from one `ApplyImpulse`.**

---

## 5. Roblox community-standards guardrails (do not skip)

- `GoreConfig.Intensity` is a **first-class shipped setting**, not a debug value.
  Provide `LOW` (impact-only, no severance visuals) and `FULL`.
- No dismemberment of *living* players outside the kill sequence.
- Blood colour is desaturated (`GoreConfig.BloodColor`), and pools fade — this reads
  as stylised rather than gratuitous and keeps moderation risk low.
- Never spawn gore inside another player's camera near-plane (a cheap distance
  check).

---

## 6. Interaction with other systems (the compounding)

| System | Interaction |
| --- | --- |
| **Survival** | A `Starved`/`Parched` victim has lower `meanRegionIntegrity` → faster severs, harder escape. Weakness is *mechanically* fatal. |
| **Noise** | Severance emits a `SCENT` burst; `THROW` emits `VIBRATION`. Other creatures can be drawn to a kill. |
| **Memory** | Kill site → high interest score; discarded limb → landmark. |
| **Destruction** | A vehicle impact on the creature during `TENDERIZE` forces `THROW` — players can rescue a teammate with a car. |
| **Persistence** | The victim's last position enters species memory and biases tomorrow's patrol. |
| **Threat** | A completed kill raises Threat Level more than any other event. |

---

## 7. Acceptance criteria for this subsystem

1. A kill can complete with the gore module **absent** (fallback path) and with it
   present, with no code change.
2. Two kills with different grab orientations produce **different** sever orders.
   (Testable headlessly: `RegionIntegrity` is a pure module — assert it in
   `tools/vitriol-smoke-test.js`.)
3. A victim can escape at any point before `CONSUME`, and escaping at 90% shear
   leaves them visibly mangled (missing region persists for the rest of the night).
4. Total server cost of a kill (excluding physics) stays under 0.3 ms/frame.
5. `GoreConfig.Intensity = LOW` produces zero sever visuals and still completes the
   kill.
