# VITRIOL — Monster Tech (skeleton, IK, movement, replication)

How the creature is actually built and moved. Every claim about the engine here is
sourced in `08-RESEARCH-NOTES.md`.

---

## 1. Why we write our own solver instead of using `IKControl`

Roblox ships `IKControl`, and it is genuinely good for **humanoid rigs**. For a
blind tendril organism it is the wrong tool, for five concrete reasons:

| # | Constraint | Consequence for Vitriol |
| --- | --- | --- |
| 1 | `IKControl` must be a child of a `Humanoid` or `AnimationController` **with an `Animator`**, and requires `Type`, `EndEffector`, `Target`, `ChainRoot` all set | The creature would need an `AnimationController` per rig and one `IKControl` per tendril (8–14 instances), each reconfigured every frame |
| 2 | The solver needs a chain of **at least 2 links** | Fine for tendrils, but it means every rig must be authored as a jointed chain — no freedom to change segment counts at runtime from the genome |
| 3 | `IKControl` has no concept of **cone limits, curl, taper, handedness or rest pose** | Tendril character *is* those things. Without them you get robotic, flipping limbs |
| 4 | `IKControl` results are **not replicated** any more usefully than bones are | We need server-authoritative simulation regardless |
| 5 | There was a **2026 regression** where `IKControl` chains broke when `ChainRoot` was not a `Motor6D`-animated part / when used with an `AnimationController` (reported Feb 2026, fixed May 2026) | A core system of the game must not depend on a component with a same-year regression history |

**Decision:** implement **constrained FABRIK** ourselves in pure Luau
(`ReplicatedStorage/Vitriol/Lib/Fabrik`). Use `IKControl` only for *player* rigs
(hand placement on a steering wheel, a door handle, a ledge) where its humanoid
integration is a genuine advantage.

---

## 2. The skeleton representation

`Shared/Skeleton` is a flat, allocation-free structure — **no instances**:

```lua
type Skeleton = {
    count   : number,          -- joints in this chain
    x       : {number},        -- world X per joint
    y       : {number},
    z       : {number},
    len     : {number},        -- bone length from joint i to i+1
    radius  : {number},        -- visual taper radius per joint
    upX     : {number},        -- stable bend-plane reference (anti-flip)
    upY     : {number},
    upZ     : {number},
    dirty   : boolean,
}
```

Flat arrays (not `{Vector3}` tables) are deliberate: no per-frame allocation, and
`hot-loop-scan.js` / `metrics.js` will show it. One `Skeleton` per tendril; a
`TendrilRig` holds `n` of them plus the core transform.

---

## 3. FABRIK, precisely

FABRIK = **F**orward **A**nd **B**ackward **R**eaching **I**nverse **K**inematics
(Aristidou & Lasenby, *Graphical Models* 73(5), 2011). It is an iterative,
geometry-based solver: no Jacobians, no matrix inversion, converges in 2–6
iterations for tendril-length chains, and it *never* produces a stretched or
exploded chain because every step re-imposes the exact bone lengths.

### 3.1 Algorithm

Given joints `p₁…pₙ`, bone lengths `d₁…dₙ₋₁` (`dᵢ = |pᵢ₊₁ − pᵢ|`), total length
`L = Σdᵢ`, base `b` (fixed) and target `t`:

```
if |t − p₁| > L then                      -- UNREACHABLE: stretch toward target
    for i = 1 .. n−1:
        r  ← |t − pᵢ|                      -- distance from THIS joint to the target
        λ  ← dᵢ / r
        pᵢ₊₁ ← (1 − λ)·pᵢ + λ·t
    return                                 -- fully extended; this is correct behaviour
else
    repeat
        -- FORWARD REACHING  (fix the end effector on the target)
        pₙ ← t
        for i = n−1 .. 1:
            r  ← |pᵢ₊₁ − pᵢ|
            λ  ← dᵢ / r
            pᵢ ← (1 − λ)·pᵢ₊₁ + λ·pᵢ

        -- BACKWARD REACHING (fix the root on the base)
        p₁ ← b
        for i = 2 .. n:
            r  ← |pᵢ − pᵢ₋₁|
            λ  ← dᵢ₋₁ / r
            pᵢ ← (1 − λ)·pᵢ₋₁ + λ·pᵢ      -- keeps the OLD pᵢ direction, rescaled
    until |pₙ − t| < tolerance  or  iterations > maxIterations
```

Note the two lines that are easy to get wrong: in the unreachable case `r` is
measured to the **target**, and in backward reaching the blend keeps the **old**
`pᵢ`, not `pᵢ₋₁`. Getting either wrong produces a chain that collapses onto itself.
`tools/vitriol-smoke-test.js` asserts both (bone lengths preserved exactly, end
effector inside tolerance, chain not degenerate).

`Lib/Fabrik` exposes:

```lua
Fabrik.solve(skel, targetX, targetY, targetZ, opts) -> boolean  -- reached?
Fabrik.solveChain(px, py, pz, len, tx, ty, tz, tol, maxIter) -> boolean
Fabrik.constrain(skel, i, maxAngleDeg)                          -- cone limit
Fabrik.blendToRest(skel, rest, alpha)                           -- curl / idle
```

### 3.2 Joint constraints (what makes it look alive)

After each iteration, for each interior joint `i`:

1. **Cone limit.** Let `a = pᵢ − pᵢ₋₁`, `b = pᵢ₊₁ − pᵢ`. If
   `angle(a,b) > maxAngleᵢ`, rotate `pᵢ₊₁` about `axis = a × b` so the angle equals
   `maxAngleᵢ`, then re-impose `|pᵢ₊₁ − pᵢ| = dᵢ`.
   `maxAngleᵢ` tapers along the tendril (proximal joints stiffer: ~35°, distal
   ~70°) — that is what makes the base look muscular and the tip whippy.
2. **Preferred bend plane.** Pure FABRIK is free to flip the elbow of the chain
   180° between frames, which reads as *glitching*. Each tendril stores a stable
   `up` vector; after solving we project the bend direction onto the plane spanned
   by `(bone, up)` and blend by `planeBias` (0.6 default).
3. **Curl / rest pose.** Every tendril has a rest chain (a gentle helix). When the
   target is far or the tendril is idle, `blendToRest(skel, rest, alpha)` pulls it
   home. `alpha` rises with `1 − urgency`. **This one feature is the difference
   between "rope" and "organism".**

### 3.3 Secondary motion (the trailing whip)

Real tentacles lag their base. We get that for free with a **damped follow** on
the *presentation* layer, not the simulation:

```
rendered[i] = damp(rendered[i], solved[i], stiffness[i], dt)
stiffness[i] = lerp(S_TIP, S_BASE, i / n)        -- tip lags most
```

`damp(a, b, λ, dt) = a + (b − a)·(1 − exp(−λ·dt))` — frame-rate independent
(`Lib/MathExt`). Plus a seeded noise offset:

```
offset[i] = Noise.v3(tendrilId * 17 + i, time * freq) * amp * taper[i]
```

`Lib/Noise` must be **deterministic and seeded** so server and clients agree.

### 3.4 From joint positions to transforms

For each segment `i`:

```lua
local dir = normalize(p[i+1] - p[i])
local up  = stabilize(planeUp[i], dir)              -- reject dir from up
local cf  = CFrame.lookAt(p[i] + dir * (len[i] * 0.5), p[i+1], up)
```

- **Part-mode rendering** (`CreatureRenderer`, MVP): write `cf` straight to the
  segment part via `Model:PivotTo` on a per-tendril `Model`, or `BulkMoveTo` for
  the whole creature in one call (`Workspace:BulkMoveTo(partList, cframeList, mode)`
  — verified API).
- **Bone-mode rendering** (upgrade path): convert `cf` into the bone's *local*
  space and write `Bone.Transform` (writable at runtime, verified) **on each
  client**. Bones are not replicated, so this is presentation only.

`stabilize()` matters: naively using a world up vector makes chains flip when they
point straight up/down. Rejecting `dir` from a *persistent* per-segment up vector
(and only slowly rotating that vector) fixes it.

---

## 4. Rendering modes

| Mode | Cost | Looks | Replicates | Use |
| --- | --- | --- | --- | --- |
| **A. Part chain** | 8–14 parts × 8–16 segments = up to ~200 parts/creature | good with a cylinder+sphere mesh kit | yes (part CFrames replicate) | **MVP**, and all `FAR` LOD |
| **B. Skinned mesh + Bones** | 1 `MeshPart` + ~12 `Bone`s per tendril | excellent (smooth, tapered, organic) | no — client writes `Bone.Transform` locally | post-MVP for `NEAR` LOD |
| **C. Beam / Trail** | near zero | thin, translucent | parent part only | ambient micro-tendrils, `OFFSCREEN` |

**Hybrid plan:** server always simulates the abstract skeleton (mode-independent).
Clients pick a mode by LOD. This means the *simulation* never changes when the art
upgrades — the single most important decoupling in the project.

> Asset note: mode B needs **human-authored skinned meshes with bone chains** named
> to match (see `10-HUMAN-AUTHORED.md` §3). Bones must be unscaled at bind time.

---

## 5. Movement: anchor and haul

The creature does not walk; it **finds purchase and pulls itself**. No physics
simulation is involved — the core is kinematic. That is a deliberate choice:
physics-driven multi-segment creatures are unstable, expensive, and impossible to
replicate cleanly.

### 5.1 The gait cycle

```
1. SEEK ANCHORS   raycast fan (5–9 rays) from candidate tendrils toward surfaces
                  within reach; score by material grip, surface normal, distance
2. COMMIT         pick 2–4 anchors (ANCHOR-specialised tendrils first)
3. TENSION        FABRIK each committed tendril to its anchor point; cone-limited
4. HAUL           move the core toward the centroid of anchors with an eased
                  impulse curve (fast start, slow settle) — 0.25–0.5 s per haul
5. RELEASE        detach the rear anchors, advance the cycle
```

- Haul speed = `Speed` gene × mass penalty × injury penalty.
- **Ceiling/wall movement** falls out naturally: anchors can be anywhere, and the
  core's "up" is derived from the anchor centroid normal, not world up. The
  creature can hang upside down with zero special-casing.
- `BURROW` reuses step 4 with anchors below the terrain surface and hides the core.

### 5.2 Locomotion fallbacks
- If no anchors are found (open field), fall back to a smooth glide with the
  tendrils in a trailing rest pose — reads as "flowing", which is unsettling and
  cheap.
- `PathfindingService` is used **only for routing decisions** (which region to go
  to, how to get around a lake), never for per-frame movement. Agent params:
  `AgentRadius` from `Mass`, `AgentHeight` small (it flattens), `AgentCanJump =
  false`, `Costs` from `Hazards` memory (this is how it *learns* to avoid the
  collapsed porch — the cost table is written by memory).

---

## 6. Grabbing, coiling, dragging

### 6.1 Grab
1. `CHARGE` commits; a tendril tip within `grabRadius` of a `GrabTarget` part
   (parented to each character by `StarterCharacterScripts/Vitriol/GrabTarget`)
   initiates.
2. Server marks the victim `Grabbed` (attribute) and assigns the grabbing tendril.
3. Victim is put into physics mode: `humanoid:ChangeState(Enum.HumanoidStateType.Physics)`
   (or `PlatformStand = true` if we want animation control).
4. Victim movement is driven by `Workspace:IKMoveTo(rootPart, targetCFrame,
   translateStiffness, rotateStiffness, collisionsMode)` — verified API on
   `WorldRoot`. This gives a soft, springy drag with no constraint soup.
   Fallback if `IKMoveTo` misbehaves: `AlignPosition` + `AlignOrientation` on the
   root part with `MaxForce`/`MaxTorque` tuned.

### 6.2 Coil (the wrap)
The wrap is a **helix around the victim's body axis**:

```
helix(s) = centre + axis·(s·pitch) + (cos(θ)·u + sin(θ)·v) · bodyRadius(s)
θ(s)     = s · turns · 2π
```

- `u, v` = orthonormal basis perpendicular to `axis`.
- `turns` = `2 + floor(4 · GripTenacity)`; `pitch` = body height / turns.
- Solve the tendril to successive helix points **proximal → distal**, fixing each
  solved joint before solving the next (a simple, stable sequential constraint).
- Visually the victim disappears inside a braid — the Carrion read we want.

### 6.3 Escape
`mashProgress += inputRate·dt`; the coil holds while
`mashProgress < escapeThreshold`, where

```
escapeThreshold = BASE_MASH · GripTenacity · (0.4 + 0.6·meanRegionIntegrity)
```

A mangled player is harder to escape — systems compounding (P7).

---

## 7. Replication of the creature

### 7.1 Payload
`Shared/SkeletonCodec` packs **positions only** (client derives orientation with
`CFrame.lookAt` + its own stable-up logic):

| Field | Type | Bytes |
| --- | --- | --- |
| creatureId | uint8 | 1 |
| tick / snapshot seq | uint16 | 2 |
| core position | 3 × int16 (0.02 stud quantised, relative to last core) | 6 |
| core orientation | 4 × int8 (quantised quaternion) | 4 |
| per joint | 3 × int16 (offset from parent joint, 0.01 stud) | 6 |

8 tendrils × 12 joints = 96 joints → **~590 B per snapshot**.

| Rate | Payload | Bandwidth |
| --- | --- | --- |
| `NEAR` 15 Hz | 590 B | **~8.9 KB/s per creature** |
| `MID` 8 Hz, 8 joints/tendril | ~400 B | ~3.2 KB/s |
| `FAR` 4 Hz, 4 joints/tendril | ~200 B | ~0.8 KB/s |

Only sent to players inside `GameConfig.LOD.StreamRadius`. Two creatures at `NEAR`
≈ 18 KB/s — comfortable. **Never** use per-joint attributes or one remote per joint.

### 7.2 Interpolation
Clients keep a 3-snapshot ring buffer and render at `now − 100 ms` (interpolation
delay), with **extrapolation** (dead reckoning from the last two snapshots) if a
snapshot is late. `SkeletonInterpolator` owns this. Never snap: blend over 80 ms on
any discontinuity.

### 7.3 Events vs state
Anything that is a *moment* is an event on `RE_CreatureEvent`, not state:
`roar`, `impact`, `breach`, `grab`, `coil`, `sever`, `consume`, `flinch`. Clients
play audio/FX from those. State (skeleton, position) streams; moments fire.

---

## 8. Performance

### 8.1 Cost model
FABRIK per joint per iteration ≈ 1 `sqrt` + ~12 flops. For 2 creatures × 8
tendrils × 12 joints × 4 iterations = **768 joint-updates/frame** ≈ tens of
microseconds. The solver is **not** the bottleneck. The bottlenecks are, in order:

1. **Raycasts** (anchor seeking + occlusion). Hard-cap per tick, share across
   tendrils, cache results for the frame.
2. **Part writes** (mode A). Use `BulkMoveTo` — one call for the whole creature.
3. **Allocation**. Pool everything; the frame path allocates **zero** tables.
4. **Spatial queries**. One `GetPartBoundsInRadius` per sense tick with a cached
   `OverlapParams` (note: reuse the params object; do not build a new one per call).

### 8.2 Parallelism plan
- One `Actor` (`ServerStorage/Vitriol/Actors/CreatureWorker`) per creature *group*,
  not per creature — scripts in the same actor run serially, so putting all
  creatures in one actor buys nothing.
- Inside the actor: `require()` **all** modules *before* `task.desynchronize()`
  (require is not allowed in a parallel phase — verified).
- In parallel: sensing raycasts/spatial queries, FABRIK, steering math.
- In serial (`task.synchronize()`): every instance write (part CFrames, attributes,
  remote fires).
- Expect ~2–3× headroom on 4 cores. Do not add actors until `Profiler` says so.

### 8.3 LOD ladder (from `01-ARCHITECTURE.md` §4)

| Tier | Distance | Solve rate | Joints/tendril | Secondary motion | Audio occlusion |
| --- | --- | --- | --- | --- | --- |
| `NEAR` | ≤ 60 | 60 Hz | full | yes | yes |
| `MID` | ≤ 140 | 30 Hz | 8 | yes (coarse) | no |
| `FAR` | ≤ 300 | 4 Hz | 4 | no | no |
| `OFFSCREEN` | — | 2 Hz | 3 | no | no |

---

## 9. Collision groups

Registered once at boot (`PhysicsService`):

| Group | Collides with |
| --- | --- |
| `Vitriol_Creature` | `Default`, `Vitriol_Structure`, `Vitriol_Vehicle`, `Vitriol_Debris` |
| `Vitriol_Player` | `Default`, `Vitriol_Structure`, `Vitriol_Vehicle` |
| `Vitriol_Structure` | `Default`, `Vitriol_Creature`, `Vitriol_Player`, `Vitriol_Vehicle`, `Vitriol_Debris` |
| `Vitriol_Debris` | `Default`, `Vitriol_Structure` |
| `Vitriol_NonCollide` | nothing |

Notes:
- The creature must **not** collide with players except through the grab system,
  otherwise physics fights the `IKMoveTo` drag. Exclude `Vitriol_Player` from
  `Vitriol_Creature`.
- `CanQuery` must stay `true` on anything perception samples; `CanCollide` can be
  `false`. These are independent flags — verified.

---

## 10. Build order for this subsystem

1. `Lib/RNG` → `Lib/Fabrik` (+ unit tests in `tools/vitriol-smoke-test.js`).
2. `Shared/Skeleton` → `TendrilRig` → part-mode renderer, **static** creature.
3. `Locomotion` anchor+haul, no AI (keyboard-drive it in Studio).
4. `Senses` + `NoiseField` (drive by hand: make noise, watch it come).
5. `Policy` with **instinct prior only** (no Q). Playable creature.
6. `QLearning` on top. A/B with `Features.CreatureLearning`.
7. `Grapple` + `KillChoreography`.
8. Bone-mode rendering + codec compression.

Steps 1–5 are the MVP creature. Each step is independently testable, which is why
the order is what it is.
