# VITRIOL — Handoff Prompts (for the next iteration / next agent)

Each work package (WP) is a **self-contained prompt**. Copy one into a fresh
session. They are ordered by dependency; do not skip ahead.

## Shared preamble (paste this at the top of every WP prompt)

```
You are continuing work on VITRIOL, a Roblox night-survival horror game about an
IK-controlled tendril creature. The repository is Explorer-first: there is NO Rojo
project and you must not create one.

Before writing any code, read, in this order:
  docs/00-VISION.md            (design pillars — these override everything)
  docs/01-ARCHITECTURE.md      (Explorer hierarchy, ownership, budgets, conventions)
  docs/02-MONSTER-DESIGN.md    (if your WP touches the creature)
  docs/03-MONSTER-TECH.md      (if your WP touches IK/movement/replication)
  docs/08-RESEARCH-NOTES.md    (verified engine facts — do not re-litigate these)

Hard rules:
  1. Every source file starts with a header comment stating its Explorer location
     and instance class (docs/01-ARCHITECTURE.md §12).
  2. Nothing in Lib/ may call game:GetService, touch an Instance, or yield.
  3. No magic numbers — every tunable goes in ReplicatedStorage/Vitriol/Config.
  4. Never use .Touched. Use spatial queries with a cached OverlapParams.
  5. Frame-path code allocates zero tables (use pools).
  6. Lighting is written by clients only (Lighting.ClockTime is Not Replicated).
  7. Bone.Transform / Motor6D.Transform do not replicate — bones are presentation.
  8. Before declaring done, run the project's own checks and report the output:
        node tools/check-syntax.js <the files you touched>
        node tools/metrics.js --src code
        node tools/hot-loop-scan.js --src code
        node tools/call-graph.js --src code
        node tools/find-dead-config.js --src code
        node tools/vitriol-smoke-test.js
     (tools/validate-project.js expects a Rojo project file and is expected to
      report it missing — that is not a failure for this project.)
  9. If something is better made by a human (meshes, map, UI, audio, animations),
     do NOT generate it. Extend docs/10-HUMAN-AUTHORED.md with a precise spec and
     hierarchy instead.
 10. Update the root ROADMAP.md status when you finish a WP (it is at the repo
     root, not under docs/).

Roblox docs are available as Markdown: append .md to any create.roblox.com/docs
URL, or fetch https://create.roblox.com/docs/reference/engine/llms.txt for the
engine API index. Prefer that over searching.
```

---

## WP1 — Pure math core + tests  ✅ *delivered: iterations 1 and 2*

**Status:** `Lib/RNG`, `Lib/Fabrik`, `Lib/Genetics` and the smoke harness exist.
Remaining: `MathExt`, `Noise`, `SpatialHash`, `UtilityAI`, `QLearning`,
`MarkovPredictor`, `Signal`, `Tables`.

```
Implement the remaining pure modules listed in docs/01-ARCHITECTURE.md §7, under
code/ReplicatedStorage/Vitriol/Lib/, each with the mandatory header comment.

Required public APIs (exact names, so dependents don't churn):
  MathExt:  lerp, damp(a,b,lambda,dt), smoothstep(t), smoothstepRange(x,a,b),
            angleBetween(v1,v2), clampMagnitude(v,max), approach(a,b,maxDelta)
  Noise:    new(seed), :value1(x), :value3(x,y,z), :v3(seedOffset,t) -> (x,y,z)
            (deterministic, no math.random, no allocation in the hot path)
  SpatialHash: new(cellSize), :insert(id,x,y,z,payload), :remove(id), :move(id,x,y,z),
            :query(x,y,z,radius,fn), :sampleDecay(x,y,z,radius,now)
  UtilityAI: new(), :consider(name, score, weight), :select(rng, temperature) -> name
  QLearning: new(cfg), :q(feats, action), :act(feats, rng, logPrior, kappa, temp),
             :learn(feats, action, reward, nextFeats), :resetTraces(),
             :serialize() -> table, QLearning.deserialize(t, cfg)
             -> linear function approximation, replacing eligibility traces,
                reward clamping, weight-norm cap (docs/02-MONSTER-DESIGN.md §8).
  MarkovPredictor: new(nStates), :observe(from, to), :predict(from, k) -> {state, p},
             :entropy(from), :serialize(), MarkovPredictor.deserialize(t)
  Signal:   new(), :connect(fn) -> conn, :fire(...), :disconnectAll()
  Tables:   newPool(factory), :get(), :release(t), deepFreeze(t), shallowCopy(t)

Every module must run under tools/vitriol-smoke-test.js. Add assertions to
tools/vitriol/tests.luau for:
  - QLearning converges on a 3-state bandit (assert the optimal action's Q is
    highest after N updates)
  - MarkovPredictor.predict returns a normalised distribution (sums to ~1.0)
  - SpatialHash.query returns exactly the inserted ids inside the radius
  - Noise is deterministic across two instances with the same seed
  - MathExt.damp is frame-rate independent (compare 1×dt vs 2×(dt/2), tolerance 1e-6)
Keep all modules free of game:GetService / Instance / task.* calls.
```

---

## WP2 — Configs are complete and read

```
Audit code/ReplicatedStorage/Vitriol/Config/*.luau against every number referenced
in docs/02..07. Any number in the docs that is not in a Config module must be added
there, with a comment giving its unit and the doc section that justifies it.
Then run `node tools/find-dead-config.js --src code` and make it report zero
unread keys — if a key is genuinely unused by code yet, either delete it or add the
reader that needs it. Do not leave speculative knobs.
```

---

## WP3 — Shared layer: Skeleton, SkeletonCodec, NoiseField, Remotes  🟨 *partial*

> Delivered and tested: `Skeleton`, `SkeletonCodec`, `NoiseField`. Still owed:
> `Remotes`, `NetContract`; `Skeleton:reset()`; the quantised-quaternion core
> orientation in the codec payload (docs/03 §7.1 lists 4 bytes for it, the codec
> currently emits none); `buffer` adapters for `encode`/`decode`; wind advection,
> rain masking and the material-coupling table in `NoiseField`; and the
> 200-random-chain round-trip test this WP asks for.

```
Implement the Shared modules from docs/01-ARCHITECTURE.md §2 under
code/ReplicatedStorage/Vitriol/Shared/.

Skeleton:      flat-array joint chain per docs/03-MONSTER-TECH.md §2. No instances,
               no allocation after construction. Include :reset() and :copyFrom().
SkeletonCodec: pack(skeletons, coreCF, seq) -> Buffer and unpack(buf) -> table,
               using the int16/int8 quantisation table in docs/03 §7.1.
               Round-trip test required in tools/vitriol/tests.luau:
               max positional error < 0.02 studs over 200 random chains.
NoiseField:    the 6-channel model from docs/02-MONSTER-DESIGN.md §2, built on
               SpatialHash, with decay, wind advection, rain masking and the
               material coupling table. Both server (authoritative) and client
               (for the Attune overlay) use the same module.
Remotes:       creates/looks up exactly the remotes listed in docs/01 §2, with
               WaitForChild + timeout, and is the ONLY place remotes are created.
NetContract:   declarative payload schemas + server-side validation for every
               client->server message. Reject and rate-limit; never trust a client.

Constraints: NoiseField and Skeleton must be allocation-free per call and must pass
hot-loop-scan with no expensive calls flagged inside loops.
```

---

## WP4 — Server services skeleton + session flow

```
Implement ServerStorage/Vitriol/Services/{SessionService, TimeService,
ThreatService, HealthService} and ServerStorage/Vitriol/Bootstrap, plus
ServerScriptService/Vitriol/Main.

- Bootstrap starts services in a declared order, each with init/start/stop, and
  every spawned loop is tracked so stop() cancels it.
- TimeService owns the clock and publishes the attributes + RE_TimeSync payload
  from docs/06-DAY-NIGHT.md §6. It must NOT touch Lighting (that is client-only).
- SessionService runs the Dawn/Day/Dusk/Night state machine with lengths from
  DayNightConfig.Pacing, with NIGHT scaled by ThreatLevel.
- ThreatService computes Threat Level from nights survived, player count and kills.
- Profiler (ServerScriptService/Vitriol/Diagnostics/Profiler) measures each cadence
  against the budgets in docs/01 §9 and auto-degrades LOD after 10 consecutive
  2x-budget samples.

Acceptance: a server with zero players still runs the full cycle correctly and
logs one line per phase change with elapsed time.
```

---

## WP5 — The creature body (no AI yet)

```
Implement ServerStorage/Vitriol/Creature/Body/{TendrilRig, Locomotion} and
CreatureCore, plus the part-mode renderer path.

- TendrilRig builds N tendril Skeletons from the genome (count, length, taper,
  specialisation) and solves them each frame with Lib/Fabrik: cone limits,
  preferred bend plane, rest-curl blend, damped secondary motion (docs/03 §3).
- Locomotion implements the anchor-and-haul gait cycle (docs/03 §5.1): raycast fan
  for anchors, commit, tension, haul, release. Ceiling and wall movement must work
  with no special-casing (core "up" derives from the anchor centroid normal).
- Add a Studio-only keyboard drive so a human can pilot the creature and evaluate
  the gait before any AI exists. Gate it behind GameConfig.Features.DebugPilot.
- Write part CFrames with one Workspace:BulkMoveTo call per creature per frame.
- Respect the LOD ladder (docs/03 §8.3) and the 1.2 ms frame budget.

Acceptance: in a test place the creature climbs a wall, hangs from a ceiling, and
crosses open ground with a trailing rest pose, at 60 Hz with 2 creatures and
Profiler reporting < 1.2 ms.
```

---

## WP6 — Senses, memory, prediction (instinct-only policy)

```
Implement ServerStorage/Vitriol/Creature/Brain/{Senses, Memory, Predictor,
Steering, BehaviorTree, Tactics, Policy} with QLearning DISABLED
(GameConfig.Features.CreatureLearning = false).

- Senses samples NoiseField per docs/02 §2.1, with the budgeted occlusion raycast
  and one GetPartBoundsInRadius per tick (cached OverlapParams).
- Memory implements the three tiers from docs/02 §3, including Hazards writing
  into the PathfindingService Costs table (docs/02 §5.2 / docs/08 §5).
- Predictor wraps Lib/MarkovPredictor over LocationClass x PostureClass states,
  reading zone tags authored per docs/10-HUMAN-AUTHORED.md §2.
- Policy uses UtilityAI + the instinct prior from docs/02 §6 (kappa high) and
  selects from the 13-action set in docs/02 §7.
- Every action gets a behaviour tree in Tactics; BehaviorTree provides
  Selector/Sequence/Parallel/Retry/Timeout/Condition nodes.
- Add AIDebugDump output: one line per decision with the top 3 scores and why.

Acceptance: make a noise in a test place and the creature investigates; run to a
tagged Garage repeatedly and by the 4th time it goes to the Garage FIRST. That
last check is the whole point — it must be demonstrable.
```

---

## WP7 — Learning on

```
Enable GameConfig.Features.CreatureLearning and wire Lib/QLearning into Policy per
docs/02 §8 (features, update rule, rewards, guardrails).

- Episode = one night. Serialize weights at dawn through PersistenceService.
- Aggregate per-lineage action priors into the species prior (docs/02 §5.3).
- A/B test: run the same scripted player policy against CreatureLearning on/off and
  log capture rate over 20 simulated nights. Report the numbers.
- Add the legibility tells from docs/02 §11 as they become reachable.

Acceptance: capture rate with learning ON must exceed OFF by a measurable margin
over 20 nights, AND the creature must still fail sometimes (capture rate < 1.0).
If learning makes it perfect, the reward function is wrong — fix the reward, do not
cap the creature.
```

---

## WP8 — Grab, kill choreography, gore

```
Implement ServerStorage/Vitriol/Creature/Body/{Grapple, KillChoreography},
Services/GoreService, Shared/{RegionIntegrity, GoreAdapter}, and the client
controllers VictimCamera + PostProcessDriver hooks.

- Grapple per docs/03 §6 (IKMoveTo drag, helical coil, escape mash).
- KillChoreography per docs/04 §1 state table, with every transition interruptible.
- RegionIntegrity per docs/04 §2 (shear damage, severance, downstream rule).
  It is a PURE module and must be unit-tested in tools/vitriol-smoke-test.js:
  assert that two different wrap geometries produce different sever orders.
- GoreAdapter per docs/04 §3, including the built-in fallback so the whole system
  runs with no gore assets present.

Acceptance: docs/04 §7, all five criteria.
```

---

## WP9 — Destruction + vehicles

```
Implement Services/{DestructionService, VehicleService, InventoryService} and the
client InteractionController + VehicleController + DebrisRenderer.

- Joint graph, materials, integrity BFS, debris pooling per docs/07 §2.
- VehicleSeat path first (docs/07 §3.1A), custom controller behind a feature flag.
- One intent schema for all interactions (docs/07 §4) with server validation.
- Every break and every impact emits into NoiseField.

Acceptance: docs/07 §6, all six criteria — in particular the corner-post collapse
must happen with no bespoke collapse script.
```

---

## WP10 — Survival + day/night presentation

```
Implement Services/SurvivalService and the client controllers LightingDriver,
SurvivalHud (cue player only — no bars), CreatureAudio, VibrationFx.

- SurvivalService per docs/05, with debuffs declared purely as data.
- LightingDriver per docs/06 §5 rules: 60 Hz damped interpolation, epsilon-gated
  writes, join easing, and it is the ONLY writer of Lighting/Atmosphere/effects.
- Verify with a grep that no server script references Lighting at all.

Acceptance: docs/05 §7 and docs/06 §9.
```

---

## Definition of done for the whole project

`docs/ROADMAP.md` M0–M6 complete, all six acceptance criteria in `docs/00-VISION.md`
§10 demonstrated on video or in a test place, all tooling green, and
`docs/10-HUMAN-AUTHORED.md` fully specified so a human can build the art with no
further questions.
