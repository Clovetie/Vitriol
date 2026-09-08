# VITRIOL — Destruction, Structures & Vehicles

This is the player's **expression layer** — and, per `00-VISION.md` P3, the loudest
microphone in the game. Every break is a noise event the creature hears. That dual
role is the whole point: the same system that makes driving a car through a porch
*fun* also makes it *costly*.

---

## 1. Design intent

| Goal | Mechanism |
| --- | --- |
| Cars are weapons and transport | mass × velocity impulse damages structures *and* creatures |
| Houses feel like structures, not props | a **joint graph**: remove the right supports and the whole thing comes down |
| Barricading is a real loop | the planks you smash are the planks you rebuild |
| Destruction is information | every break emits `VIBRATION` (+ `AIR` for loud materials) |
| It must never tank the server | pooled debris, capped integrity BFS, no `.Touched` |

---

## 2. Structures: the joint graph

### 2.1 Authoring contract (human-authored, see `10-HUMAN-AUTHORED.md` §2)

A destructible structure is a `Model` tagged `Vitriol_Structure` containing:

```
Porch_House_01 (MO)                        [CS: Vitriol_Structure]
├─ Meta (CFG)                              ← material class, integrity budget, sound set
├─ Anchor (PT, anchored, CanCollide=false) ← graph root / world reference
├─ Frame (FL)
│  ├─ Post_NW (PT)      [CS: Vitriol_Joint]   ← load-bearing
│  ├─ Post_NE (PT)      [CS: Vitriol_Joint]
│  ├─ Beam_Top (PT)     [CS: Vitriol_Joint]
│  └─ ...
├─ Skin (FL)                               ← non-structural mesh parts (windows, trim)
└─ Joints (FL)                             ← created at runtime by DestructionService
   ├─ Weld_Post_NW__Beam_Top (RE_CONST)
   └─ ...
```

Rules for the author:
- Structural parts are `Anchored = true` at rest and become unanchored **only**
  when their support path to ground breaks.
- Attachments are not required; the service creates constraints at runtime from a
  **declared adjacency list** in `Meta` (deterministic and reviewable), or infers
  adjacency from part bounding-box contact at load (`DestructionConfig.InferAdjacency`).
- Glass/trim go in `Skin`: they shatter cosmetically and never affect integrity.

### 2.2 Runtime model

```lua
type Joint = {
    part        : BasePart,
    material    : MaterialClass,     -- Wood | Concrete | Glass | Metal | Masonry
    hp          : number,
    maxHp       : number,
    loadPath    : number,            -- BFS depth to the ground anchor (recomputed on break)
    isSupport   : boolean,           -- carries load from above
    neighbours  : {number},          -- adjacency indices
    constraints : {Instance},
    anchored    : boolean,
}
```

`DestructionService` holds one graph per structure, built once at load, and
**never re-scans the hierarchy** during play.

### 2.3 Damage

```
damage = impulseEnergy / materialResistance
impulseEnergy = 0.5 · mass · |Δv|²          -- from the impacting assembly
```

Sources of `Δv`:
- **Vehicle / thrown object**: `AssemblyLinearVelocity` sampled the frame before
  impact vs after (per-frame velocity sampler on tracked assemblies only).
- **Creature breach**: `Strength` gene × `BREACH` action, applied over time.
- **Tool / melee**: fixed damage per hit type from `DestructionConfig.Tools`.
- **Collapse load**: when a part above loses support, its fall energy is applied to
  whatever it lands on (via a single `GetPartBoundsInBox` on impact).

Materials (`DestructionConfig.Materials`):

| Material | HP mult | Resistance | Debris count | Sound set | `VIBRATION` |
| --- | --- | --- | --- | --- | --- |
| `Glass` | 0.25 | 0.1 | 6 shards | shatter | 0.35 |
| `Wood` (plank) | 1.0 | 0.5 | 3 splinters | crack/snap | 0.70 |
| `Masonry` | 3.5 | 2.2 | 5 chunks | crunch | 0.90 |
| `Concrete` | 6.0 | 4.0 | 6 chunks | deep crunch | 1.00 |
| `Metal` | 4.0 | 3.0 | 2 (bends, rarely breaks) | clang | 0.95 |

### 2.4 Structural integrity propagation (the fun part)

When a joint breaks:

```
1. Remove its constraints; unanchor the part; apply residual impulse.
2. BFS from the ground anchor over remaining adjacency (cap: 64 nodes/step,
   amortised across frames if exceeded).
3. Any part not reached has lost its load path → unanchor it and everything
   hanging from it, converting the sub-assembly into falling debris.
4. Falling parts, on landing, apply their impact energy to whatever they hit
   (one spatial query, budgeted) → chain collapses are possible and intended.
5. Emit VIBRATION proportional to total mass that moved.
```

**This is what makes "drive the car into the corner posts" a real strategy.** Topple
the right two posts and the roof does the rest. It also means the *creature* can be
crushed by a collapsing porch — the intended, engineered way to seriously wound it
(`02-MONSTER-DESIGN.md` §13).

### 2.5 Debris

- **Pooled.** `Workspace.Vitriol.Debris` holds `DestructionConfig.PoolSize`
  (default 96) reusable parts, tagged `Vitriol_Debris`. Nothing is `Instance.new`'d
  during play after warmup.
- Each debris part gets `Massless = false`, `CanCollide = true` briefly then
  `false` after `SettleTime`, then a transparency ramp and return to pool.
- **Hard cap on simultaneous unanchored parts** (`MaxLivePhysics`, default 40).
  Beyond that, breaks produce sparks/particles instead of physical chunks. This is
  the single most important perf guard in the destruction system.
- Cosmetic-only debris on clients: `RE_Destruction` tells clients to spawn
  short-lived visual splinters that never simulate — cheap, and it keeps the
  server's physics count low.

### 2.6 Never use `.Touched`

`.Touched` fires unreliably at speed, doesn't give you impulse energy, and at
scale it's a per-frame cost you can't budget. Instead:
- **Velocity-delta sampling** on tracked assemblies (cars, debris, creature core).
- **`Workspace:GetPartBoundsInBox` / `GetPartBoundsInRadius`** with cached
  `OverlapParams` at the moment of impact.
- `CanQuery` stays `true` on structural parts; `CanCollide` can be `false` —
  they are independent flags (verified).

---

## 3. Vehicles

### 3.1 Two implementations, pick per vehicle

**(A) `VehicleSeat` (quick, robust, less feel).** `VehicleSeat` exposes
`MaxSpeed`, `Torque`, `TurnSpeed`, `Throttle`, `Steer`, `HeadsUpDisplay`, `Disabled`
(verified). Wheels must be connected by **motors**, not hinges — the seat does not
drive hinge-linked wheels. Use this for MVP.

**(B) Custom controller (recommended target).** One unanchored chassis assembly +
independent wheel assemblies:

```
Car_Pickup (MO)                             [CS: Vitriol_Vehicle]
├─ Meta (CFG)                               ← mass, power, grip, fuel, health
├─ Chassis (PT, unanchored)                 ← the assembly root; holds LV/AV
│  ├─ Body (MP, Massless=true)
│  ├─ DriverSeat (Seat)
│  ├─ Drive (LV)          ← LinearVelocity, VectorRelativeTo=World, MaxForce tuned
│  ├─ Steer (AV)          ← AngularVelocity, ActuatorType=Motor
│  ├─ Downforce (VF)      ← VectorForce, keeps it planted at speed
│  └─ Hitbox (PT, CanQuery=true, CanCollide=false, Transparency=1)
├─ Wheels (FL)
│  ├─ Wheel_FL (PT, unanchored, own assembly)
│  │  ├─ AxleMount (ATT)
│  │  ├─ Suspension (TSC)   ← TorsionSpringConstraint: Stiffness/Damping/MaxAngle/Restitution
│  │  └─ Spin (HNG)         ← HingeConstraint for rolling
│  └─ ... ×4
└─ Lamps (FL)                               ← SpotLight / SurfaceLight (EM emitters!)
```

`TorsionSpringConstraint` (verified API: `Stiffness`, `Damping`, `LimitsEnabled`,
`MaxAngle` default 45, `Restitution`, `Radius`, `MaxTorque`) is exactly right for
suspension travel; note **`CurrentAngle` is not replicated**, so never read it on a
client for gameplay.

Controller loop (server, 30 Hz, only while occupied):
```
throttle, steer  ← RE_ClientIntent from the driver (validated, rate-limited)
Drive.MaxForce   ← clamp(power * throttle, ...)
Steer.AngularVelocity ← steer * turnRate * speedFalloff(velocity)
Downforce.Force  ← -Y * k * |v|²      (grip rises with speed, so crashes are worse)
```

### 3.2 Fuel, damage, and the noise budget
- Fuel drains with throttle; running out mid-night, far from base, is a real
  failure state (and `Collapse` waits for you).
- Vehicle `Health` degrades from impacts; a wrecked car still works as a barricade.
- **Headlights are EM emitters** (`NoiseField.EM` proportional to power draw).
  Driving with lights off is quieter to the creature but you can't see. This is a
  permanent, delicious trade-off with zero extra systems.
- Engine noise is `AIR` scaled by RPM; tyre scrub on gravel is `VIBRATION`.

### 3.3 Car ↔ structure ↔ creature

```
impactEnergy = 0.5 · AssemblyMass · |Δv|²
if hits structure → DestructionService.damageJoint(joint, impactEnergy)
if hits creature  → CreatureCore.damage(impactEnergy · CreatureImpactScale)
                    + force STALK→RETREAT / TENDERIZE→THROW interrupt
if hits player    → HealthService.bluntDamage(...)   (yes, you can run over friends)
always            → NoiseField.emit("VIBRATION", pos, clamp(impactEnergy/E_REF))
                    + NoiseField.emit("AIR", pos, ...)
```

`AssemblyMass` is **infinite if any part of the assembly is anchored** (verified) —
so a "crash" into an anchored part must be treated as an infinite-mass collision and
the *car* takes all the damage. Handle that case explicitly or you get NaN impulses.

**Creature-car interaction is a first-class rescue mechanic:** hitting the creature
during `TENDERIZE` forces `THROW`, dropping the victim alive (`04` §6). Players
will absolutely do this on purpose.

---

## 4. Player interactions (the "more interaction with the environment" ask)

All interactions go through one `InteractionController` (client) → `RE_ClientIntent`
→ server validation. **One intent schema, one validator, one set of animations.**

| Interaction | Input | Server action | Cost |
| --- | --- | --- | --- |
| **Open/close door** | hold E | toggle hinge `Motor6D`/`HingeConstraint` target | small `AIR` |
| **Kick door** | sprint + E | damage door joint; may break | loud `VIBRATION` |
| **Barricade** | hold E with planks | spawn plank joints over door/window | medium `VIBRATION` |
| **Remove barricade** | hold E | reverse; returns planks | medium |
| **Smash plank** | melee | damage joint | loud |
| **Break window** | melee / thrown object | `Skin` glass shatter (cosmetic + `AIR`) | loud, but no integrity change |
| **Climb through window** | E at broken window | teleport/step through; small damage risk | quiet |
| **Enter/exit vehicle** | E at seat | seat weld + ownership auto-assign | engine start `AIR` |
| **Search container** | hold E | roll loot from `Meta` table; one-time | rustle `AIR` |
| **Carry object** | E | weld-to-hand with `RigidConstraint`; capacity-limited | footsteps louder |
| **Drop/throw object** | Q | un-weld + `ApplyImpulse` | impact `VIBRATION` |
| **Push vehicle** | hold E near | apply `VectorForce` while in contact | slow, loud |
| **Crank generator** | hold E | restores power to a zone; **emits EM** | loud + EM |
| **Extinguish / light fire** | E | toggles `THERMAL` + `EM` + light | — |
| **Attune (listen)** | hold C | stops movement, boosts local perception overlay | makes you vulnerable |

Design rule: **every interaction has a noise cost in the table above.** If an
interaction is silent, it must have some other cost (time, stamina, resources).

---

## 5. Performance rules (non-negotiable)

1. **No `.Touched` anywhere.** Spatial queries with cached `OverlapParams` only.
2. **Debris is pooled**, capped, and time-limited.
3. **Integrity BFS is capped** (64 nodes/step) and amortised.
4. **Off-screen structures don't simulate**: falling debris beyond `StreamRadius`
   is resolved instantly (part removed, no physics).
5. **Debris physics is budgeted globally**, not per structure: one counter, one
   eviction policy.
6. **Nothing in this system runs per frame** unless it has work to do. The velocity
   sampler only tracks assemblies that are currently moving.
7. `hot-loop-scan.js` must show **no** `Clone`/`Raycast` inside the destruction
   frame path.

---

## 6. Acceptance criteria

1. Driving a car into the two corner posts of the test porch collapses the roof
   **without** any bespoke "collapse script" — purely from the integrity BFS.
2. A plank barricade can be built, smashed and rebuilt, and each event is audible
   to the creature (assert via `NoiseField.sample`).
3. 200 simultaneous breaks do not drop the server below 45 Hz (debris cap engages
   and produces particles instead of physics).
4. Running over the creature during a kill always drops the victim alive.
5. Driving with headlights off measurably reduces `NoiseField.sample(pos, "EM")`
   at 40 studs.
6. `find-dead-config.js` reports no unread keys in `DestructionConfig`/`VehicleConfig`.
