# VITRIOL — Deep Research Notes (engine facts, sources, gotchas)

Every engine claim made in the other documents is sourced here. Items are marked:

- ✅ **verified** — read directly from the Roblox API reference / creator docs in
  this iteration (date of research: 2026-09-08).
- ⚠️ **secondary** — from a reputable non-official source (devforum staff post,
  legacy wiki, Roblox GitHub mirrors). Re-check in Studio before relying on it.
- ❓ **to verify** — assumed from experience; must be confirmed in Studio before
  the dependent system ships.

> **Tip for every future iteration:** Roblox publishes its documentation as
> Markdown, and there is a machine-readable index. Fetch
> `https://create.roblox.com/docs/llms.txt` (docs index) and
> `https://create.roblox.com/docs/reference/engine/llms.txt` (engine API index), or
> append `.md` to any docs URL (e.g.
> `https://create.roblox.com/docs/reference/engine/classes/Bone.md`). This is
> dramatically more reliable than searching.

---

## 1. Inverse kinematics

### 1.1 ✅ `IKControl`
Source: `https://create.roblox.com/docs/reference/engine/classes/IKControl`

Properties (current): `ChainRoot`, `Enabled`, `EndEffector`, `EndEffectorOffset`,
`Offset`, `Pole`, `Priority`, `SmoothTime`, `Target`, `Type`, `Weight`.

Methods (current): `GetChainCount()`, `GetChainLength()`, `GetNodeLocalCFrame(i)`,
`GetNodeWorldCFrame(i)`, `GetRawFinalTarget()`, `GetSmoothedFinalTarget()`.

- Required properties: `Type`, `EndEffector`, `Target`, `ChainRoot`
  (`https://create.roblox.com/docs/animation/inverse-kinematics`).
- Must be a child of a `Humanoid` or `AnimationController` **with an `Animator`**,
  otherwise it has no effect.
- `Priority`: higher values are resolved **later** (so they override).
- `Pole`: exists in the current API (it was added in 542, **removed in 546**, and
  **re-added in 548**) — controls the bend plane. Useful, but its history is a
  warning about depending on it.

### 1.2 ✅ `Enum.IKControlType`
Source: `https://create.roblox.com/docs/reference/engine/enums/IKControlType`

| Name | Value | Meaning |
| --- | --- | --- |
| `Transform` | 0 | full 6-DoF; aligns end-effector CFrame to target |
| `Position` | 1 | aligns position only |
| `Rotation` | 2 | aligns rotation only |
| `LookAt` | 3 | orients the chain so an axis on the end effector points at the target |

> Note: older material mentions `Reach`/`Plant` types. The **current** enum lists
> only the four above. Do not code against removed items.

### 1.3 ✅ Chain must be ≥ 2 links
Source: devforum `https://devforum.roblox.com/t/i-cant-figure-ik-out/2986137`
(⚠️ staff/community, but consistent with the docs' "all connected parts between
ChainRoot and EndEffector"). For a single-limb rig you must insert a **ghost limb**
to get a solvable chain.

### 1.4 ⚠️ 2026 `IKControl` regression (important)
Source: `https://devforum.roblox.com/t/ik-control-chainroot-behavioral-change-breaks-pre-existing-chains/4391277`

- Reported **2026-02-16**: `ChainRoot` set to a part that is *not* `Motor6D`-animated
  caused the chain to go completely static.
- Roblox staff (2026-03-24) confirmed it was the same bug as *"Inverse Kinematics no
  longer functioning when used with an Animation Controller"*
  (`.../4526713`) and said a fix was coming.
- Roblox staff (2026-05-08) reported it **fixed**.

**Consequence for Vitriol:** a same-year regression in the exact component a
procedural creature would depend on is why `03-MONSTER-TECH.md` §1 chooses a
self-written FABRIK solver as the primary path. If you ever do use `IKControl` for
the creature, add a boot-time self-test that verifies a chain actually solves.

### 1.5 ✅ FABRIK
Aristidou, A. & Lasenby, J. (2011). *"FABRIK: a fast, iterative solver for the
inverse kinematics problem."* Graphical Models 73(5), 243–260.
Full algorithm restated in `03-MONSTER-TECH.md` §3. Reference Luau/Roblox
implementations exist (e.g. `github.com/datlass/fabrik-ik-motor6d`) but we implement
our own because we need cone limits, curl, taper and a stable bend plane.

---

## 2. Bones, skinning, procedural deformation

### 2.1 ✅ `Bone.Transform` is writable at runtime
Source: `https://create.roblox.com/docs/reference/engine/classes/Bone.md`

- `Bone.Transform` — `access: ReadWrite`, `thread_safety: ReadSafe`,
  `serialization: { can_load: true, can_save: false }`.
- Doc text: *"This property is set by Roblox when animations on skinned meshes are
  played, although it can be manipulated manually in a manner similar to
  `Motor6D.Transform`."*
- Doc text: *"Roblox uses the offset of the bones from the default pose to drive an
  animation, and **bones are not replicated or serialized**."*
- `Bone.TransformedWorldCFrame` — `ReadWrite`, but `thread_safety: **Unsafe**`
  (do not read it inside a parallel phase).
- `Bone` inherits from `Attachment`; the inherited `CFrame` is the bone's *reference*
  position, and inherited `WorldCFrame`/world properties return the **un-transformed**
  position.

**Consequences (both load-bearing for our architecture):**
1. Procedural bone animation must run **on each client** — the server cannot send
   bone transforms (`01-ARCHITECTURE.md` §5.2, `03` §4 mode B).
2. Nothing authored on a bone transform persists to save (`can_save: false`).

### 2.2 ⚠️ Motor6D ↔ Bone equivalence & transform order
Source: `https://roblox.github.io/avatar-evolution/api/class/Bone`

- Motor6D: child part is relative to `Transform * ParentPart.CFrame * CParent`.
- Bone: child bones are relative to `Transform * ParentPart.CFrame * Bone.CFrame`.
- *"Bones internally implement the animatable joint interface and can be driven by
  Animators interchangeably with Motor6Ds."*
- *"Physical Constraints directly attached to Bones will use the transformed
  positions for simulation."* — useful: we can attach a `RopeConstraint` to a bone
  and get correct physics follow.
- Skinning is joint-name based and **limited to the same `Model`** (descendant
  `Model`s are treated as separate). *"Skinning is based on joint connections so
  that classic dismemberment on death works as expected"* — i.e. detaching a part
  correctly un-skins it. Directly relevant to our severance system.

### 2.3 ⚠️ Skinning authoring rules
Source: `https://roblox.github.io/avatar-evolution/skinning.html` and
`https://create.roblox.com/docs/art/modeling/skin-a-simple-mesh`

- **Do not scale joints** in the DCC tool; zero/identity joint transforms before
  binding. Non-uniform joint scale breaks the mesh.
- Squash/stretch must be achieved with **translation**, not joint scale.
- Scaling a `MeshPart` in Studio updates descendant bone positions; changing
  `MeshPart.Size` does **not**.
- Import rigged meshes with the AvatarImporter plugin; use "Custom" for non-R15.

→ These go straight into `10-HUMAN-AUTHORED.md` §3 as constraints on the creature
meshes.

---

## 3. Physics, spatial queries, assemblies

### 3.1 ✅ `WorldRoot` query & bulk APIs
Source: `https://create.roblox.com/docs/reference/engine/classes/WorldRoot`

- `GetPartBoundsInBox(cframe, size, overlapParams) -> {BasePart}`
- `GetPartBoundsInRadius(position, radius, overlapParams) -> {BasePart}`
  (default `OverlapParams{MaxParts=0, Tolerance=0, BruteForceAllSlow=false,
  RespectCanCollide=false, CollisionGroup="Default", FilterDescendantsInstances={}}`)
- `GetPartsInPart(part, overlapParams) -> {BasePart}`
- `BulkMoveTo(partList, cframeList, eventMode: Enum.BulkMoveMode)`
- `IKMoveTo(part, target, translateStiffness, rotateStiffness, collisionsMode: Enum.IKCollisionsMode)`
- `Raycast`, `Spherecast`, `Blockcast`, `Shapecast`
- `RegisterCollisionGroup`, `UnregisterCollisionGroup`, `RenameCollisionGroup`,
  `CollisionGroupSetCollidable`, `GetRegisteredCollisionGroups`,
  `IsCollisionGroupRegistered`, `GetMaxCollisionGroups`
- Tagged **"Write Parallel" / "Simulation Access"** → safe to call from a
  desynchronised parallel phase. This is what makes the parallel perception plan
  viable (`03` §8.2).
- Doc explicitly warns: `GetPartBoundsIn*` consider **bounding boxes**, not occupied
  volume — for accuracy use `GetPartsInPart` or filter yourself. (Relevant for
  cylinders/spheres/meshes — our tendrils.)

### 3.2 ✅ `CanQuery` vs `CanCollide` are independent
`BasePart.CanQuery = false` excludes a part from `GetPartBoundsInBox`,
`GetPartBoundsInRadius`, `GetPartsInPart` and `Raycast`. So you can have a part
that collides but is invisible to queries, and vice versa.
(⚠️ commonly cited on devforum, e.g.
`https://devforum.roblox.com/t/parttouched-or-spatial-queries/1763924`; consistent
with the API reference.)

### 3.3 ✅ Assemblies
Source: `https://create.roblox.com/docs/physics/assemblies`

- `BasePart.AssemblyLinearVelocity`, `AssemblyAngularVelocity`,
  `AssemblyCenterOfMass` (read-only), `AssemblyMass`, `AssemblyRootPart`.
- *"All forces applied to a specific `BasePart` are applied to its assembly — for
  instance, `BasePart:ApplyImpulse()` applies impulse to the assembly at
  `BasePart.AssemblyCenterOfMass`."*
- **"If the assembly has an anchored part, the assembly's mass is considered
  infinite."** → `07-DESTRUCTION-VEHICLES.md` §3.3 handles this explicitly.
- You **cannot** set `AssemblyRootPart` explicitly; it is chosen by heuristics, and
  it is the part used for physics replication and network ownership.
- Docs recommend `VectorForce`/`LinearVelocity`/`ApplyImpulse` over writing
  `AssemblyLinearVelocity` directly.

### 3.4 ✅ `TorsionSpringConstraint` (suspension)
Sources: `https://create.roblox.com/docs/physics/constraints/torsion-spring` and the
API reference. Properties: `Stiffness` (default 100), `Damping`, `LimitsEnabled`,
`MaxAngle` (default 45°), `Restitution` (default 0), `Radius` (default 0.4),
`MaxTorque` (default inf), `CurrentAngle`.
- **`CurrentAngle` is not replicated** — never read it client-side for gameplay.
- `Damping = 0` oscillates forever; raise it to settle.

### 3.5 ❓ `Enum.IKCollisionsMode` item names
`IKMoveTo` takes an `Enum.IKCollisionsMode`. Assumed items: `NoCollisions`,
`IncludeContactedMechanisms`, `IgnoreContactedMechanisms`. **Verify the exact item
names in Studio** before shipping the grab/drag system; the call signature itself is
verified from the `WorldRoot` reference.

### 3.6 ❓ `VehicleSeat` property set
Sources: legacy Roblox wiki / community (`rbxlegacy.wiki`, grokipedia). Properties
believed current: `MaxSpeed`, `Torque`, `TurnSpeed`, `Throttle`, `Steer`,
`HeadsUpDisplay`, `Disabled`, `Type` (hinge count). The community consensus is that
legacy automatic movement expects **motor-linked** wheels, not hinge-linked.
**Verify against the current API reference** (`.../classes/VehicleSeat.md`) before
building the vehicle layer; the custom-controller path in `07` §3.1(B) avoids the
dependency entirely.

---

## 4. Lighting & environment

### 4.1 ✅ `Lighting.ClockTime` is **Not Replicated**
Source: `https://create.roblox.com/docs/reference/engine/classes/Lighting`
The property listing explicitly tags `ClockTime` as **"Not Replicated"** — unlike
`Ambient`, `Brightness`, `FogEnd` etc., which carry no such tag.

**This is the single most important environment fact in the project** and the
reason `06-DAY-NIGHT.md` §1 makes the clock a replicated *value* applied locally on
each client. Most Roblox day/night tutorials set `Lighting.ClockTime` on the server
and appear to work in Studio (single process) while silently failing in a live
server.

### 4.2 ✅ Other `Lighting` facts from the same page
- `Technology` is **Deprecated**; `LightingStyle` exists but is **Roblox Script
  Security** → set the technology in Studio, not in code (`06` §7).
- `EnvironmentDiffuseScale` and `EnvironmentSpecularScale` **default to 0** in
  current versions. Set them (≈0.55 / 0.35) or the sky contributes nothing to
  lighting and nights look flat.
- `GlobalShadows` defaulted to `false` in version 553 → set `true` explicitly.
- `GeographicLatitude` default `41.7332993`; `FogStart` 0; `FogEnd` 100000.
- `ClockTime` default has changed between versions (14 at some point) — never rely
  on a default; always set it.
- Methods: `GetMinutesAfterMidnight()`, `SetMinutesAfterMidnight(m)`,
  `GetSunDirection()`, `GetMoonDirection()`; `GetMoonPhase()` is **Deprecated**
  → we own our moon-phase counter (`06` §4.2).
- Event: `LightingChanged(skyChanged: boolean)` — useful for the client driver to
  know when *something else* touched lighting.
- `ShadowColor` and `Outlines` are deprecated.

### 4.3 ⚠️ `Atmosphere`
Properties used in `06`: `Density`, `Offset`, `Color`, `Decay`, `Glare`, `Haze`.
Canonical reference: `https://create.roblox.com/docs/reference/engine/classes/Atmosphere`.
The specific value guidance in `06` §3.1 comes from the keyframe table we authored,
with starting points informed by a third-party lighting guide — **tune in Studio**.
One `Atmosphere` per experience.

### 4.4 ❓ Skybox cross-fading
Roblox does not blend two `Sky` objects. `06` §3.1 therefore switches `Sky` at the
fog-thickest hour. If a real cross-fade is wanted, the alternative is two cameras
rendering to `ViewportFrame`s — expensive; not recommended.

---

## 5. Pathfinding

Source: `https://create.roblox.com/docs/characters/pathfinding` (+ the
`PathfindingService` reference).

`PathfindingService:CreatePath(agentParameters)` — verified parameter table:

| Key | Type | Default |
| --- | --- | --- |
| `AgentRadius` | integer (studs) | 2 |
| `AgentHeight` | integer (studs) | 5 |
| `AgentCanJump` | boolean | true |
| `AgentCanClimb` | boolean (TrussParts) | false |
| `WaypointSpacing` | number | 4 (`math.huge` = no intermediate waypoints) |
| `Costs` | table (Material name or `PathfindingModifier` label → cost) | nil |

- `Path:ComputeAsync(start, finish)`; check `Path.Status ==
  Enum.PathStatus.Success`; iterate `Path:GetWaypoints()`
  (`waypoint.Position`, `waypoint.Action`, `waypoint.Label`).
- `Path.Blocked(blockedWaypointIndex)` event → recompute.
- A cost of `math.huge` makes a region **non-traversable**.
- `PathfindingModifier` parts label regions; the matching `Costs` key applies.
- Deprecated: `ComputeRawPathAsync`, `ComputeSmoothPathAsync`, `FindPathAsync`,
  `PathfindingService.EmptyCutoff`. Do not use.

**Vitriol use (`02` §5.2):** `Costs` is written *from creature memory* — a learned
hazard raises its region's cost, so the creature "learns to avoid the collapsed
porch" with zero bespoke code. This is the single most elegant reuse in the design.

---

## 6. Parallel Luau

Source: `https://create.roblox.com/docs/scripting/multithreading`

- `Actor` instances are execution-isolation units; **scripts inside the same Actor
  run serially with respect to each other** → one actor per creature group, not one
  for everything.
- `task.desynchronize()` / `task.synchronize()`; or `RBXScriptSignal:ConnectParallel()`.
- **"You can't use `require()` in a desynchronized parallel phase. Require scripts
  you want to use first in a serial context."** → `01-ARCHITECTURE.md` §2.1 keeps
  `Lib` pure and requires everything before desynchronising.
- Thread-safety levels: `Unsafe` (cannot read/write in parallel), `Read Parallel`
  (read only), `Local Safe` (usable within the same actor), `Safe` (read/write).
- Parallel phases generally **cannot write to the DataModel** → all instance writes
  happen after `task.synchronize()`.
- ⚠️ Known pitfall: `task.desynchronize()` errors outside an `Actor`; there was a
  deferred-signal-related false-positive bug
  (`https://devforum.roblox.com/t/taskdesynchronize-should-only-be-called-from-a-script-that-is-a-descendant-of-an-actor/3077542`).

---

## 7. Persistence

### 7.1 ✅ MemoryStore
Source: `https://create.roblox.com/docs/cloud-services/memory-stores/sorted-map`

- `MemoryStoreSortedMap:SetAsync(key, value, expirationSeconds, sortKey?)`.
- **Maximum expiration is 3,888,000 seconds (45 days).**
- **GDPR:** if the store holds user data subject to the Right to be Forgotten you
  **must** remove it within 30 days even if you set a 45-day expiry.
- `UpdateAsync(key, callback, expiration)` reads the latest value and retries on
  contention until success, `nil` return, or max retries.
- `MemoryStoreHashMap:SetAsync/GetAsync/UpdateAsync/RemoveAsync`.

### 7.2 ❓ DataStore budgets
`DataStoreService:GetRequestBudgetForRequestType(Enum.DataStoreRequestType.*)`
should gate every write; use `UpdateAsync` for read-modify-write; wrap in `pcall`
with backoff. Exact current budget numbers **must be read from the reference at
implementation time** — they have changed historically and we should not hard-code
them.

### 7.3 Design consequence
Species persistence (`01` §11) is designed so that **a total persistence failure is
silent and non-fatal**: the game falls back to an in-memory genome pool. Never let a
DataStore outage end a round.

---

## 8. Learning algorithm references

- **FABRIK** — Aristidou & Lasenby, 2011 (see §1.5).
- **Eligibility traces / TD(λ)** — Sutton & Barto, *Reinforcement Learning: An
  Introduction*, 2nd ed., ch. 7 & 12 (replacing vs accumulating traces; we use
  **replacing** because the feature vector is binary and re-visits are common).
- **Linear function approximation** — Sutton & Barto ch. 9. Chosen over any
  neural approach because Luau has no autodiff/GPU and the frame budget is 16 ms;
  a ~80–900 weight linear model is a few hundred multiply-adds.
- **Potential-based reward shaping** — Ng, Harada & Russell, 1999, *"Policy
  invariance under reward transformations."* Only shaping of the form
  `F(s,s') = γΦ(s') − Φ(s)` preserves the optimal policy. `02` §8.4 uses exactly
  this form, with `Φ(s) = −dist_to_best_known_prey / 100`. Using any other shaping
  form would silently bias the creature toward weird behaviour.
- **Boltzmann (softmax) exploration** — anneals from exploratory to greedy while
  keeping a non-zero probability of every action, which matters because we *want*
  the creature to occasionally do something unexpected (`02` §8.6).
- **Baldwin effect** — learning is not inherited, but the *capacity/prior* for it
  is. This is why `02` §5.3 inherits an aggregated action prior rather than raw Q
  weights.
- **Utility AI** — a scored-action selector; standard practice in game AI
  (e.g. *The Sims*, *Fear*). We layer Q on top so designers keep a readable,
  tunable surface (`02` §9.1).

---

## 9. Open research items for the next iteration

| Item | Why it matters | How to check |
| --- | --- | --- |
| `Enum.IKCollisionsMode` exact items | grab/drag implementation | Studio autocomplete on `Enum.IKCollisionsMode` |
| `VehicleSeat` current property list | vehicle layer choice | `.../classes/VehicleSeat.md` |
| `Enum.BulkMoveMode` items (`FireAllEvents`/`FireCFrameChanged`/`None`) | renderer write path | Studio autocomplete |
| RemoteEvent per-packet size limits | skeleton codec budget | Creator docs "Network communication" + test |
| `MemoryStoreQueue` semantics for cross-server species exchange | post-MVP evolution | `.../memory-stores/queues` |
| Whether `Model:PivotTo` on a 200-part model is cheaper than `BulkMoveTo` | renderer | MicroProfile in Studio |
| `Humanoid.BreakJointsOnDeath` + `ChangeState(Physics)` interaction with `IKMoveTo` | grab system | Studio test place |
| Terrain water `CanQuery` behaviour | scent/vibration masking by water | Studio test |

---

## 10. Verified engine facts added by iteration 3 (WP3/WP4)

- ✅ **Attributes are read on the client with `Instance:GetAttributeChangedSignal(name)`.**
  There is **no** `GetAttributeChangeListener` — the name appears in a lot of
  third-party tutorials and does not resolve. Verified
  `create.roblox.com/docs/reference/engine/classes/Script.md` (inherited `Instance`
  members list), 2026-09-08. This is the API `LightingDriver` must use for the
  `TimeAnchor` attributes in `06` §6.
- ✅ **A `Script` only runs when it is a descendant of `Workspace` or
  `ServerScriptService`.** Code parked in `ServerStorage` never executes there, so
  `ServerStorage/Vitriol/Bootstrap` is a **ModuleScript** and `ServerScriptService`'s
  `Main` requires it (docs/01 §2 updated to match). Same source, §"Description".
- ✅ **`buffer` semantics** (`libraries/buffer.md`): `buffer.create(n)` is zero-filled,
  max 1 GiB; `readu8`/`writeu8`/… take **0-based byte offsets** and error out of
  range; multi-byte reads are little-endian; a `Buffer` sent through a `RemoteEvent`
  is **copied** (so `Replicator` may reuse its scratch buffer between sends), and one
  buffer object cannot be shared between parallel `Actor`s (so an actor must be given
  bytes, not the shared scratch).
