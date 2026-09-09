# Handoff — Vitriol, playable creature slice (2026-09-09 UTC)

Everything in this file was produced by running a command in this repository, not
recalled. Where a claim is unverified it says so. Two iterations of "the doc said X,
the code did Y, and the test found out" are recorded in §4 for exactly that reason.

---

## 0. Prompt for the next agent

```
Continue the Vitriol Roblox prototype on the fixed branch
arena/01a0847b-vitriol. The repository is Explorer-first: do not create a Rojo
project or switch branches.

Read first:
  docs/00-VISION.md          design pillars and scope
  docs/01-ARCHITECTURE.md    Explorer hierarchy, authority, cadence and budgets
  docs/03-MONSTER-TECH.md    FABRIK, procedural rig, locomotion and replication
  docs/04-KILL-CHOREOGRAPHY.md kill scene and BloodEngine adapter contract
  docs/08-RESEARCH-NOTES.md  verified Roblox/BloodEngine facts
  ROADMAP.md                 current decisions and validation snapshot

The playable continuation is already implemented: the Braid is code-generated,
Threat 1 has one creature, creatures are woundable-only and never killable, the
server owns the victim kill, the victim receives a first-person camera event, and
BloodAdapter integrates the supplied BloodEngine hierarchy at
ReplicatedStorage > VModules > BloodEngine with a bounded LOW fallback. The
upstream MIT source and Assets.rbxm are checked in under
code/ReplicatedStorage/VModules/BloodEngine; Studio import/layout still needs
human verification.

Do not add a second scheduler, client health authority, creature death path, or
cross-server evolution. Keep gameplay on CadenceService. If adding a config key,
wire a real reader or document why it is a future WP key. Any human-only map/UI/
audio/Studio action belongs in docs/10-HUMAN-AUTHORED.md and ROADMAP.md.

Before saying done, run and report the real output of:
  node tools/vitriol-smoke-test.js
  node tools/vitriol-session-test.js
  node tools/check-syntax.js code
  node tools/metrics.js --src code
  node tools/hot-loop-scan.js --src code
  node tools/call-graph.js --src code
  node tools/find-dead-config.js --src code
  node tools/evaluate-models.js --models tools/models.example.json \
       --suite tools/evaluation-suite.example.json
  node tools/vitriol-quality-gate.js --src code
The evaluator must print fixture-known-good: ADMIT 100.0% and
candidate-local: REJECT 0.0%. The known syntax exception is Lua 5.1 luaparse
rejecting bitwise `&` in Lib/RNG.luau and Lib/Noise.luau. Do not claim Studio,
real Buffer replication, camera feel, or BloodEngine visual acceptance without
running Roblox Studio.

If budget is low, update ROADMAP.md, commit the honest partial result, and write
the next handoff rather than claiming completion.
```

---

## 0.1 Current continuation — creature slice

Resolved scope decisions:

- The Braid is generated entirely from code; no mesh, rig, or Studio asset is needed
  for the MVP creature body.
- Monsters are never killable. `CreatureCore:wound()` only lowers locomotion and
  active-tendril capacity; at `MonsterConfig.Wounds.DisableThreatAt` it becomes
  non-threatening but remains alive and visible.
- `GameConfig.Session.MaxCreatures = 1` and `MonsterConfig.Threat.CreatureCountAtThreat
  = {}` keep one readable creature at Threat 1. There is no cross-server evolution.
- A player reaching `MonsterConfig.Kill.GrabDistance` starts the cadence-stepped
  `Creature/Body/KillChoreography`; `HealthService` alone writes player health.
  The server sends `RE_CreatureEvent` with numeric `CreatureId`/`VictimUserId`, and
  `StarterPlayerScripts/.../VictimCamera` holds the victim's own camera at the head
  in first person. Spectators ignore the event and remain third person.
- `BloodConfig`/`BloodAdapter` is the only visual blood caller. It probes the supplied
  `ReplicatedStorage/VModules/BloodEngine` hierarchy first, uses
  `BloodEngine.new(settings):Emit(...)` when installed, defaults the prototype to LOW
  intensity, gates sever visuals, and keeps a bounded stylised fallback.
- Optional limb hiding is behind `BloodConfig.Dismemberment.Enabled` (false by
  default); `KillChoreography` exposes one sever callback during TENDERIZE.

New runtime files:

- `code/ServerStorage/Vitriol/Creature/Body/{TendrilRig,Locomotion,KillChoreography}.luau`
- `code/ServerStorage/Vitriol/Creature/CreatureCore.luau`
- `code/ServerStorage/Vitriol/Services/CreatureService.luau`
- `code/ReplicatedStorage/Vitriol/{Config/BloodConfig,Shared/BloodAdapter}.luau`
- `code/StarterPlayer/StarterPlayerScripts/Vitriol/{ClientMain,Controllers/VictimCamera}.luau`

Bootstrap now creates BloodAdapter, Health kill callbacks, CreatureService, one frame
slot, and one think slot. No gameplay code adds a RunService connection or task yield.
The session harness exercises spawn, close-range scene start, remote event payload,
player-only death, and the existing scheduler/Lighting invariants.

Unverified Studio work remains explicit: actual Roblox Part/CFrame/BulkMoveTo display,
wall/ceiling purchase, real Buffer replication, client camera feel, audio/post-process,
and importing the checked-in BloodEngine source/Assets.rbxm into the exact Explorer
shape. Do not claim these as headless-proven.

## 1. Verified state at handoff

The current working branch is `arena/01a0847b-vitriol`. Iteration 3's server
foundation is retained; this continuation adds the generated Braid, spawn/runtime
wiring, Blood adapter, bounded victim scene, and first-person victim camera. Changes
are included in the current continuation commit; Studio verification remains open.

| Check | Output |
| --- | --- |
| `vitriol-smoke-test.js` | `VITRIOL smoke test: 366 passed, 0 failed` |
| `vitriol-session-test.js` | `VITRIOL session test: 87 passed, 0 failed` |
| `check-syntax.js code` | 43 OK / `2 file(s) failed` — `Lib/RNG.luau`, `Lib/Noise.luau` (§3) |
| `metrics.js --src code` | `45 files; LOC 10993; code 8001; comments 2125; exports 381; requires 35` |
| `hot-loop-scan.js --src code` | `Priced calls: 31 \| inside-a-loop: 8 \| in a RunService file: 0` |
| `call-graph.js --src code` | current graph includes `Bootstrap -> BloodAdapter/CreatureService`, `CreatureService -> CreatureCore/TendrilRig/Locomotion`, `HealthService -> KillChoreography`, and `ClientMain -> VictimCamera/Remotes` |
| `find-dead-config.js --src code` | audits all eight Vitriol configs; planned future-WP keys are reported for review |
| `evaluate-models.js` | `fixture-known-good: ADMIT 100.0%` / `candidate-local: REJECT 0.0%` |
| `vitriol-quality-gate.js --src code` | `9/9 checks passed` including both harnesses and `git diff --check` |

Latest validation run for this continuation (2026-09-09 UTC): smoke **366 passed,
0 failed**; session **87 passed, 0 failed**. `check-syntax.js code` reports 43
parseable files plus the two known bitwise exceptions (`Lib/RNG.luau`, `Lib/Noise.luau`).
Metrics report 45 files, 10,993 LOC, 8,001 code lines, 2,125 comment lines, 381
exports and 35 require edges. Hot-loop reports 31 priced calls, 8 inside loops, and
0 in a RunService file. The evaluator prints `fixture-known-good: ADMIT 100.0%` and
`candidate-local: REJECT 0.0%`.

The 8 loop flags are the seven existing `table.insert` sites in `Genetics` and
`RegionIntegrity` plus the one kill-only `FindFirstChild` limb lookup in
`HealthService`; none is in a frame-bound RunService file. The call graph reports
45 modules, 381 exports and 35 require edges, including the Bootstrap/BloodAdapter/
CreatureService and client VictimCamera edges. The dead-config audit now scans all eight Vitriol config modules; its reported
future-WP keys (AI/body-integrity/animation, destruction, vehicle and survival
settings) are recorded as verify-before-removing candidates, not silently removed.
`vitriol-quality-gate.js --src code` is the preferred single future-agent command
and most recently passed 9/9 checks.

---

## 2. What exists

`code/ReplicatedStorage/VModules/BloodEngine/` mirrors the supplied upstream
BloodEngine v1.1.3 ModuleScript family (`init`, `Operator`, `Settings`, `Functions`)
and its `Assets.rbxm`, with the upstream MIT notice. In Studio, make the root
ModuleScript addressable as `ReplicatedStorage.VModules.BloodEngine`; the adapter
also accepts a `BloodEngine` Folder containing an `init` child.

`code/ReplicatedStorage/Vitriol/`

**Config/** (8, parse clean): `GameConfig`, `SurvivalConfig`, `DayNightConfig`,
`MonsterConfig`, `DestructionConfig`, `GoreConfig`, `BloodConfig`, `VehicleConfig`. New since
iteration 2: `GameConfig.{Net,Intents,Diagnostics}`, `GameConfig.Ticks.CadenceSlopSeconds`,
`GameConfig.Budgets.{SlowShares,FrameShares}`, `GameConfig.LOD.Tiers`,
`GameConfig.Session.{SecondsPerRealSecond,RoundName,DataStoreName,PhaseLogLines}`,
`GameConfig.Features.DataPersistence`, `MonsterConfig.Threat`,
`MonsterConfig.Senses.{AdvectionMaxAgeSeconds,NoiseCellSize}`,
`DayNightConfig.PHASES` (the ordered list the phase machine and the debug handler read),
`DayNightConfig.Pacing.{Ease,NightThreatMultiplier}`,
`DayNightConfig.Driver.AnchorMaterial`, `SurvivalConfig.Health`, `SurvivalConfig.Emission.BloodAirIntensity`.
`DayNightConfig.RateCurve` is **deleted** (§4.7).

**Lib/** (11, pure — no services, no Instances, no yields): `MathExt`, `RNG`,
`Fabrik`, `Genetics`, `Tables`, `Signal`, `Noise`, `SpatialHash`, `UtilityAI`,
`QLearning`, `MarkovPredictor`. Surfaces as iteration 2's handoff described them;
`SpatialHash:sampleDecay` and `:prune(now, maxAge, onRemove)` now have a consumer
(`NoiseField`), which is what their signatures were shaped for.

**Shared/** (7): `RegionIntegrity`, `Skeleton` (+rest pose/`:reset()`),
`SkeletonCodec`, `NoiseField` (+ advection/masks/coupling), `Remotes`, `NetContract`,
`TimeModel`.

| Module | Surface |
| --- | --- |
| `Remotes` | `.Definition` (7 remotes: name/class/direction/owner/schema/notes), `BY_NAME`, `init()`, `get(name)`, `await(name, timeout)`, `bindAll(timeout)`, `names()`, `clientToServer()`, `definition(name)`, `coverageProblems(schemas)`, `reportBindFailure(what)` |
| `NetContract` | `.Reject`, `.Schemas.{ClientIntent,DebugQuery}`, `.Actions`, `.ActionNames`, `.DebugCommands`, `validate(schema,payload)`, `newGate()`, `limits(schema)`, `allow(gate,key,schema,now)`, `checkSequence(...)`, `admit(gate,key,schema,payload,now) -> ok,code,extra`, `forget`, `stats` |
| `TimeModel` | `PHASES`, `PHASE_HOURS`, `HOURS_PER_DAY`, `MAX_EASE`, `clamp01`, `warp`, `minutesToClock`, `clockToMinutes`, `phaseSpan`, `phaseClock`, `phaseProgress`, `phaseOf`, `phaseWeight`, `nextPhase`, `phaseSeconds`, `cycleSeconds`, `skyKey`, `sunElevation`, `isDaylight`, `nextMoonPhase`, `moonBrightnessDelta` |
| `SkeletonCodec` | `encode(out, skels, core, ref, seq, id, quat) -> count, reconCore`, `decode(bytes, skels, ref) -> core, seq, quat`, `creatureId`, `byteCount`, `normaliseQuat`, `coreDisplacement`; `HEADER_BYTES 13`, `JOINT_BYTES 6`, `JOINT_STEP .01`, `CORE_STEP .02`, `MAX_JOINT_ERROR .00866`, `MAX_CORE_ERROR .01732`, `MAX_ANGLE_ERROR .015873 rad` |
| `NoiseField` | `new(cfg)`, `:emit(channel,x,y,z,i,now,opts?)`, `:emitAt`, `:sample`, `:sampleAll`, `:loudestChannel`, `:setWind(x,y,z)`, `:setWeather(entry)`, `:setChannelMask`, `:setAdvectionWindow`, `:advectionWindow`, `:remove`, `:prune(now)`, `:count`, `:clear` |

`code/ServerStorage/Vitriol/`
- `Creature/Replicator` — `new(count, opts)`, `:encode`, `:snapshot`, `:publish(dt, recipients, ...)`, `:setRate`, `:stats`, `:reset`, and the `toBuffer/toBytes/checkParity` adapters.
- `Services/CadenceService` — `new(cfg)`, `:register(slot) -> id`, `:unregister(id)`, `:start`, `:stop`, `:pump(dt)`, `:stats(name)`, `:slotNames`, `:clearPeaks`, `:summary`.
- `Services/TimeService` — `init(services)`, `start`, `advance(dt)`, `publish`, `setThreat`, `setWeather`, `seekTo`, `seekToPhase`, `setTimeScale`, `onPlayerAdded`, `snapshot`, `stop`; owns `Workspace.Vitriol.World.TimeAnchor`.
- `Services/SessionService` — `init`, `start`, `tick`, `beginRound`, `endRound`, `phaseChanged`, `nightEnded`, `killRegistered`, `loadRecord`, `saveRecord`, `snapshot`, `stop`.
- `Services/ThreatService` — `init`, `start`, `recompute`, `tick`, `creatureCount`, `nightsSurvived`, `killRegistered`, `playerChanged`, `setOverride`, `snapshot`, `stop`.
- `Creature/Body/TendrilRig` — numeric generated chains, constrained FABRIK/rest blending, anchors, damped display skeletons.
- `Creature/Body/Locomotion` — bounded ray fan, material-aware anchors, haul/glide movement.
- `Creature/Body/KillChoreography` — deterministic GRAB→LIFT→COIL→TENDERIZE→CONSUME→DISCARD scene with optional sever callback.
- `Creature/CreatureCore` — generated Braid Model/Parts, one guarded `BulkMoveTo`, wound-only state and snapshot.
- `Services/CreatureService` — one-creature reconciliation/spawn, target bridge, wound API, victim event, cadence slots.
- `Services/HealthService` — `init`, `start`, `observe`, `attach`, `forget`, `addWound`, `addWoundByUserId`, `beginCreatureKill`, `tickCreatureKills`, `limbSevered`, `trackDamage`, `tickBleed`, `metersAllowRegen`, `scentScale`, `snapshot`, `stop`.
- `Shared/BloodAdapter` — BloodEngine probe/constructor/Emit adapter, LOW/FULL gate, bounded fallback.
- `StarterPlayerScripts/Vitriol/Controllers/VictimCamera` — victim-only first-person camera bound to `RE_CreatureEvent`.
- `Bootstrap` (ModuleScript) — `ensure()` (idempotent), `stop()`, `runtime()`.

`code/ServerScriptService/Vitriol/`
- `Main` (Script) — requires Bootstrap, calls `ensure()`. The only server Script that runs on its own by design.
- `RemoteHandlers/ClientIntentHandler` (Script) — `NetContract.admit` → route table filled by services (`runtime:routeIntent`), counts unrouted, `runtime.intentStats()`.
- `RemoteHandlers/DebugHandler` (Script) — `RF_DebugQuery` `OnServerInvoke`, read-only: `clock/phases/cadence/budget/help`.
- `Diagnostics/Profiler` (Script) — binds `RunService.Heartbeat` **itself**: the only
  binding besides `Bootstrap`'s pump, and it lives outside `CadenceService` on purpose
  (a slot the scheduler fails to run would blind the watchdog that detects exactly
  that). It only *reads*: `CadenceService:stats` +
  `summary`, drops one LOD tier after `WatchdogSamples` consecutive over-budget
  windows and walks it back a tier at a time when they come in under (there is no
  separate "recover" entry point — recovery is the same poll), replicates
  `LodTier` as a TimeAnchor attribute for the clients, and fans the tier out through
  `runtime.onDegrade(fn)` so consumers never have to poll it. Exposes
  `Profiler.tier()`, `:degrade()`, `:reset()` for the debug handler and tests.

`tools/`
- `vitriol-smoke-test.js` + `vitriol/tests.luau` — pure modules, 366 assertions.
- `vitriol-session-test.js` + `vitriol/session.luau` — the server, 87 assertions.
- `lib/luau-transform.js` — the shared Luau→Lua transform (both harnesses; also where the forbidden constructs are enforced).
- `lib/paths.js` (Explorer-first `code/` resolver), `lib/luau.js` (`stripCommentsAndStrings`), the `vitriol-quality-gate`, `check-syntax`, `metrics`, `hot-loop-scan`, `call-graph`, `find-dead-config`, and `evaluate-models` gates.
- `audit.sh` is the broad report runner; `validate-project.js` remains optional legacy Rojo validation and is skipped for this Explorer-first checkout.

---

## 3. Harness constraints (learned the hard way; do not rediscover)

Both harnesses transform Luau to Lua 5.3 and run it in fengari. **The transform
throws rather than mangling**, so tested code must avoid:
- `continue`; backtick strings — and note the backtick test is on the **raw line**,
  so a backtick inside a `-- comment` on a code line fails the run. Use 'single
  quotes' in prose comments of tested modules.
- `{T}?` generics; prefer `any`. Multi-line function heads are handled, but keep
  heads on one line where you can; a `+=` right-hand side must still be a single
  line for `check-syntax.js`'s sake.
- Multiplicative hash mixers (`z * 0x85EBCA6B` overflows 2^53 in fengari) and
  `+ 2^32` normalisers; normalise in the float domain.

Module resolution differs between the two, on purpose:
- `vitriol-smoke-test.js` uses a hand-kept `MODULES` map — **add new modules to it**,
  including indirect `require`s. `Services/*` are deliberately **not** in it: a service
  needs the fake DataModel, the poisoned `task`/`Lighting` and the virtual clock, which
  is the session harness's job. Put reusable logic in `Shared/` or `Lib/` and unit it in
  the smoke test; the service stays thin enough to test by booting it.
- `vitriol-session-test.js` scans all of `code/` and resolves `require(...)` by
  **last path segment**, so two files with the same basename is a hard error (the
  harness says so and exits).

The session harness additionally:
- poisons `task.wait/spawn/defer/delay` (they `error`) — that is how "one scheduler
  only" is enforced;
- counts `RunService.Heartbeat:Connect` and asserts it equals 2 (the cadence pump and
  the watchdog);
- makes `Lighting` a poisoned object: writing any property errors, and *fetching the
  service* is counted;
- runs `os.clock` off a virtual clock, so `SIM.burn(ms)` can make one slot look
  expensive deterministically (that is how the Profiler's auto-degrade is tested);
- has no real replication. It proves logic: not packet size, not attribute delivery
  order, not what a client sees. Anything about those stays on the Studio checklist.

`tools/vitriol/tests.luau` wraps each section in `do ... end` (Lua's 200-active-locals
limit) and uses flat `check(cond, msg)`; there is no `describe/case` DSL. Same style in
`tools/vitriol/session.luau`. `--tests <path>` points either harness at a scratch file
(relative to the repo root); `--debug-transform` writes transformed sources to
`/tmp/vitriol-*.lua` (session: `/tmp/vitriol-session-*.lua`), which is the fastest way
to see what the harness actually ran.

`check-syntax.js` fails on `Lib/RNG.luau` and `Lib/Noise.luau` because luaparse is
Lua 5.1 and cannot read bitwise operators. Both files are *executed* under Lua 5.3 by
the smoke test, which is stronger evidence than a parse. Documented in docs/01 §13.

A Lua-pattern trap that bit the test itself (not shipped code): in a pattern, `-`
after a class is the lazy quantifier, so `"(%a+) -> (%a+)"` never matches an arrow.
Write `%s*%->`.

---

## 4. Bugs found by writing this code (each pinned by a regression test)

Iteration 2's list is still valid and is recorded in `ROADMAP.md` (Noise lattice
hash, Fisher–Yates draw, SpatialHash re-insert, QLearning trace decay, and
core-relative vs parent-relative quantisation). Iteration 3 added:

1. **`TimeService` unit confusion.** `clockMinutes = minutesToClock(phaseClock(...))`
   fed hours into a minutes→hours converter: a 6.66 h dawn became 0.11. The
   documented attribute contract (docs/06 §6, `0..1440`) is minutes, so the call is
   `clockToMinutes`. Invisible to every static check; found by booting the service.
2. **`TimeService:setWeather` argument mismatch** with `NoiseField:setWeather(entry)`
   — the *kind string* landed in the entry slot, so the mask indexed off a string.
3. **Phase→hour lookups bypassed the model.** `DayNightConfig.PhaseHours` is keyed
   `DawnStart/DayStart/...`; `PhaseHours[phase]` was nil everywhere. Fixed by routing
   all phase↔hour naming through `TimeModel.phaseSpan`, which now also returns
   `nil` for a phase not in `PHASES` instead of silently answering Night.
4. **`SessionService` had a field and a method both named `log`.** The field shadowed
   the method, so `self:log(msg)` called the injected sink with `self` as its level —
   producing `[[vitriol]]` prefixes and, on some paths, a crash. The method is `emit`
   now. Rule for this codebase: an injected callback field and a method of the same
   name on the same table is a bug.
5. **`HealthService` registered a player death as a session kill**, which would have
   made dying raise the Threat Level (docs/02 §12 counts creatures the *group*
   killed). Now asserted: a player death leaves the kill count alone.
6. **`Bootstrap.stop()` leaked the noise-prune slot** — "one call stops everything"
   was false. Asserted: 0 enabled slots after stop.
7. **`DayNightConfig.RateCurve` and `Pacing` disagreed** (2.5 min/s ⇒ 576 s/day vs a
   555–735 s paced cycle). Two clocks, one world: the sky would have said Dusk while
   `PhaseName` said Night. The rate curve is gone; the clock is *derived* from the
   phase machine through `Pacing.Ease` (docs/06 §2.2), so a boundary is hit exactly at
   every Threat Level — asserted to 1e-9 across 400 simulated seconds.
8. **Uncapped advection is a hang, not a slow path.** Sampling with a search window of
   `wind × the channel's whole audibility lifetime` made the spatial-hash cell range
   cubic (SCENT: 7 644 studs ⇒ 478³ cells ⇒ a 180 s harness timeout). `AdvectedMaxAge`
   / `MonsterConfig.Senses.AdvectionMaxAgeSeconds = 20` caps it, with the rationale
   that evidence older than the window is the memory layer's job (docs/02 §2/§3).
9. **Two harness-transform bugs** (documented so nobody re-breaks them): it wrapped
   `for x in string.gmatch(...)` in `pairs(...)` (an iterator became a table), and it
   stripped `: Type` annotations across the *body* of a multi-line call, turning
   `conn:disconnect()` into `conn()`. Both are in `tools/lib/luau-transform.js` with
   comments explaining the boundary; anonymous `function(a: T)` heads are now handled
   too, which is what lets services keep typed callbacks in table constructors.

---

## 5. Standing constraints from the user

- **Structure is presented as a real Roblox Studio Explorer tree** with class
  annotations. Explicitly **not** a Rojo layout, and no `default.project.json` may be
  created.
- Script Explorer locations are stated in every file's header comment.
- Anything a human would do better (map, meshes, UI, audio, animation) gets a precise
  spec in `docs/10-HUMAN-AUTHORED.md`, never generated assets.
- **BloodEngine source is checked in under `code/ReplicatedStorage/VModules/BloodEngine`.**
  It mirrors the supplied upstream MIT v1.1.3 scripts and `Assets.rbxm`; the adapter
  is still the only visual-blood caller, probes `ReplicatedStorage/VModules/BloodEngine`
  first, uses `new(settings)`/`:Emit(...)`, defaults to LOW, and keeps a bounded
  fallback. Do not claim the checked-in engine has been Studio-verified until the
  Explorer import and real visuals are tested.
- `tools/validate-project.js` and `tools/audit.sh` are Rojo-specific; do not
  reorganise `code/` to satisfy them. `tools/smoke-test.js` is unrelated legacy.
- The `evaluate-models.js` gate must be run and must pass.
- `docs/00-VISION.md`'s pillars override everything; `docs/08-RESEARCH-NOTES.md`'s
  verified facts are not to be re-litigated (append to it when you verify something).
- Buffer adapters belong in the replicator, not the codec (the codec stays pure
  number arrays so quantisation stays testable).

---

## 6. Architecture conclusions that gate all later work

1. `Bone.Transform` / `Motor6D.Transform` do not replicate → the server owns a
   logical joint chain and replicates it compactly; clients own the rig and dead
   reckon. Part CFrames *do* replicate → part-chain visuals via `BulkMoveTo` are the
   MVP path. (A `Buffer` sent through a `RemoteEvent` is **copied**, so
   `Replicator` may reuse its scratch buffer between sends — and one buffer object
   cannot be shared between `Actor`s, so an actor gets bytes, not the buffer.)
2. Do not depend on `IKControl`. There is a 2026 `ChainRoot` regression
   (devforum/4391277, fixed 2026-05-08). The owned FABRIK solver is primary.
3. `Lighting.ClockTime` is Not Replicated → the server publishes a clock; a
   per-client `LightingDriver` is the sole Lighting writer. The server's only
   Lighting-adjacent artefact is the `TimeAnchor` part's attributes.
4. Perception runs in desynced `Actor`s. `require` before desync; one Actor per
   worker; parallel phases cannot write the DataModel.
5. No `.Touched`: impulse from `AssemblyLinearVelocity` deltas +
   `GetPartBoundsInRadius` + joint-graph BFS. Every break emits into `NoiseField`.
6. AI layering: genome → instinct log-prior + capability gates → Q-learning (linear
   features, Boltzmann, replacing traces) → Utility AI → Behaviour Tree → Steering →
   IK. Cross-night: GA over genomes (DataStore) + aggregated priors (MemoryStore,
   max expiry 45 days).
7. The minimum kill is a bounded cadence scene owned by HealthService; optional
   region/limb presentation is gated by `BloodConfig.Dismemberment` and hands visual
   blood to `BloodAdapter`, never to gameplay code directly. Full region-integrity
   Grapple remains a later M5 completion item.
8. **One scheduler.** `CadenceService` is driven by Bootstrap's single
   `RunService.Heartbeat` binding and every piece of *gameplay* work is a registered
   slot on it. The only other binding is the Profiler's read-only watchdog, deliberately
   outside the scheduler it audits; the session harness asserts the total is exactly 2,
   so neither number can creep. Consequence worth remembering when you add one: the file that touches `RunService` must contain no
   priced call, so measurement lives inside `CadenceService:_runSlot` and the frame
   `dt` is passed in rather than timed. `hot-loop-scan.js`'s "in a RunService file:
   0" is the visible sign that this is holding.
9. **The clock is derived, not integrated.** Any second accumulator that "advances
   the time of day" reintroduces the seam §4.7 removed. If a phase needs a new
   boundary, change `DayNightConfig` and `TimeModel`, never a local timer.
10. **Field vs observer.** Propagation (decay, advection, weather mask, surface
    coupling) is `NoiseField`'s; acuity thresholds, localisation error, the downwind
    sniff boost, water-immersion masking and occlusion are `Senses'`. The table in
    docs/02 §2 is the arbiter; code and doc were made to agree in iteration 3 and the
    session test asserts the weather path end-to-end through the clock.
