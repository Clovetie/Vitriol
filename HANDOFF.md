# Handoff — Vitriol, end of iteration 3

Everything in this file was produced by running a command in this repository, not
recalled. Where a claim is unverified it says so. Two iterations of "the doc said X,
the code did Y, and the test found out" are recorded in §4 for exactly that reason.

---

## 0. Prompt for the next agent

```
You are continuing work on VITRIOL, a Roblox night-survival horror game about an
IK-controlled, blind, tendril-based creature that hunts by vibration, scent and
memory and LEARNS the player's habits. The repository is Explorer-first: there is
NO Rojo project and you must not create one. Work on the branch you were given;
never create or switch branches.

Read first, in this order:
  docs/00-VISION.md          the 7 design pillars; these override everything
  docs/01-ARCHITECTURE.md    Explorer hierarchy, ownership, cadence budgets, and
                             §13 = the list of known tool exceptions
  docs/03-MONSTER-TECH.md    FABRIK, rig, movement, replication (§7.1 is now the
                             real byte layout: header 13 B, 589 B per Braid snapshot)
  docs/08-RESEARCH-NOTES.md  verified engine facts. Do not re-litigate these.
  docs/09-HANDOFF-PROMPTS.md the WP1-WP10 breakdown and the shared preamble
  HANDOFF.md §2/§3/§4        what exists, what the harnesses forbid, what was wrong

Roblox docs are available as Markdown: append .md to any create.roblox.com/docs URL
(classes live at /docs/reference/engine/classes/<Name>.md; libraries at
/docs/reference/engine/libraries/<name>.md), or fetch
https://create.roblox.com/docs/reference/engine/llms.txt for the index. Prefer that
over searching - and record what you verify in docs/08 with the URL and a date.

YOUR TASK THIS ITERATION: WP5 - the creature body, no AI yet (see docs/09).
  ServerStorage/Vitriol/Creature/Body/{TendrilRig, Locomotion}, CreatureCore, the
  part-mode renderer path, and a keyboard pilot behind GameConfig.Features.DebugPilot.
  Acceptance: the creature climbs a wall, hangs from a ceiling and crosses open
  ground with a trailing rest pose, at 60 Hz with 2 creatures, Profiler under 1.2 ms.

  What already exists for you, tested and ready (do not rewrite it):
    Shared/Skeleton        flat joint-chain data; :reset() + rest pose; built STRAIGHT
    Lib/Fabrik             the solver, cone limits, dampChain, blendToRest
    Shared/SkeletonCodec   encode/decode over arrays, 4-byte core quaternion included
    Creature/Replicator    the buffer adapters, rate tiers, publish loop; register it
                           with CadenceService, do not write your own loop
    Shared/NoiseField      decay + wind advection + weather mask + surface coupling.
                           Footfalls go in at EMIT time with the material multiplier
                           already applied (MonsterConfig.Senses.VibrationCoupling)
    Services/CadenceService  ONE scheduler. Register {Name, PeriodSeconds, BudgetMs,
                           Run}. Bootstrap already binds Heartbeat; a service that
                           calls task.spawn/task.wait fails the session harness.
    Config/MonsterConfig   Rig/Locomotion/Archetypes blocks are already written with
                           the numbers docs/03 cites; read them before inventing any.
  Rules that bite here specifically:
    - One Workspace:BulkMoveTo per creature per frame; zero table allocations in the
      frame path; never .Touched (impulse from AssemblyLinearVelocity deltas).
    - Anchor search is budgeted: MaxCandidatesPerTick / MaxOcclusionRaysPerTick.
    - Ceiling and wall movement must need no special-casing: the core's "up" comes
      from the anchor centroid normal (docs/03 §5.1), which is why the codec ships a
      core orientation at all.
    - New cadence slots need a budget share in GameConfig.Budgets (SlowShares /
      FrameShares); Bootstrap checks that a row's shares still fit the row.

HARD RULES (docs/09 preamble; these are load-bearing):
  1. Every source file starts with a header comment giving its Explorer location
     and instance class.
  2. Nothing in Lib/ may call game:GetService, touch an Instance, or yield.
  3. No magic numbers - every tunable goes in a Config module, with a comment giving
     its unit and the doc section that justifies it.
  4. Never use .Touched.
  5. Frame-path code allocates zero tables (Lib/Tables has the pool).
  6. Lighting is written by clients only.
  7. Bone.Transform / Motor6D.Transform do not replicate - bones are presentation.
  8. Run the checks below and paste their real output before you say "done".
  9. If a human would do it better (meshes, map, UI, audio, animations) do NOT
     generate it - extend docs/10-HUMAN-AUTHORED.md with a precise spec instead.
 10. Update the ROOT ROADMAP.md when you finish a WP.

BEFORE YOU SAY DONE, run all of these and report the actual output:
  node tools/vitriol-smoke-test.js                 (363 passed, 0 failed)
  node tools/vitriol-session-test.js               (80 passed, 0 failed)
  node tools/check-syntax.js code                  (2 failures: Lib/RNG, Lib/Noise)
  node tools/metrics.js --src code
  node tools/hot-loop-scan.js --src code           (inside-a-loop 7, in-a-RunService-file 0)
  node tools/call-graph.js --src code
  node tools/find-dead-config.js --src code        (only the two Gerstner lines)
  node tools/evaluate-models.js --models tools/models.example.json \
       --suite tools/evaluation-suite.example.json
The last one must print:
  fixture-known-good: ADMIT 100.0%
  candidate-local: REJECT 0.0%

If you are running low on budget, stop cleanly: update ROADMAP.md, commit, and
write the next handoff. A partial iteration that is committed and honest is worth
more than an unfinished one that is not.
```

---

## 1. Verified state at handoff

Iteration 3's work is committed on `arena/01a08196-vitriol` (WP3 close-out + WP4).

| Check | Output |
| --- | --- |
| `vitriol-smoke-test.js` | `VITRIOL smoke test: 363 passed, 0 failed` |
| `vitriol-session-test.js` | `VITRIOL session test: 80 passed, 0 failed` |
| `check-syntax.js code` | 34 OK / `2 file(s) failed` — `Lib/RNG.luau`, `Lib/Noise.luau` (§3) |
| `metrics.js --src code` | `LOC 8944 \| code 6239 \| comments 1978 \| exports 305 \| requires 24` (36 files) |
| `hot-loop-scan.js --src code` | `Priced calls: 16 \| inside-a-loop: 7 \| in a RunService file: 0` |
| `call-graph.js --src code` | `Exports: 305 (used 11, orphaned 294)` — the graph has real edges now: `Bootstrap -> NoiseField/CadenceService/Remotes`, `ClientIntentHandler -> NetContract.stats`, `DebugHandler -> Time/Threat/Health/Cadence snapshots` |
| `find-dead-config.js --src code` | only the two hard-coded `src/...Gerstner...: not found` lines |
| `evaluate-models.js` | `fixture-known-good: ADMIT 100.0%` / `candidate-local: REJECT 0.0%` |

The 7 inside-a-loop flags are unchanged from iteration 2 (`table.insert` in
`Genetics` 181/220 and `RegionIntegrity` 46/105/106/108/160). The other 9 priced
calls, all outside loops: `:FindFirstChild` 3× in `Remotes` (client bind path) and
3× in `TimeService:acquireAnchor` (memoised on `self.anchor`, so once per server);
`os.clock()` twice in `CadenceService:_runSlot`, which is once per slot *dispatch*
rather than once per frame by design; and `table.sort` in `DebugHandler`'s `phases`
answer. None is in a file that binds `RunService` — `Bootstrap` and `Profiler` touch
it and contain zero priced calls, which is a deliberate constraint (§6.8).

---

## 2. What exists

`code/ReplicatedStorage/Vitriol/`

**Config/** (7, parse clean): `GameConfig`, `SurvivalConfig`, `DayNightConfig`,
`MonsterConfig`, `DestructionConfig`, `GoreConfig`, `VehicleConfig`. New since
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
- `Services/HealthService` — `init`, `start`, `observe`, `attach`, `forget`, `addWound`, `addWoundByUserId`, `limbSevered`, `trackDamage`, `tickBleed`, `metersAllowRegen`, `scentScale`, `snapshot`, `stop`.
- `Bootstrap` (ModuleScript) — `ensure()` (idempotent), `stop()`, `runtime()`.

`code/ServerScriptService/Vitriol/`
- `Main` (Script) — requires Bootstrap, calls `ensure()`. The only server Script that runs on its own by design.
- `RemoteHandlers/ClientIntentHandler` (Script) — `NetContract.admit` → route table filled by services (`runtime:routeIntent`), counts unrouted, `runtime.intentStats()`.
- `RemoteHandlers/DebugHandler` (Script) — `RF_DebugQuery` `OnServerInvoke`, read-only: `clock/phases/cadence/budget/help`.
- `Diagnostics/Profiler` (Script) — one 1 Hz slot: reads `CadenceService:stats` +
  `summary`, drops one LOD tier after `WatchdogSamples` consecutive over-budget
  windows and walks it back a tier at a time when they come in under (there is no
  separate "recover" entry point — recovery is the same poll), replicates
  `LodTier` as a TimeAnchor attribute for the clients, and fans the tier out through
  `runtime.onDegrade(fn)` so consumers never have to poll it. Exposes
  `Profiler.tier()`, `:degrade()`, `:reset()` for the debug handler and tests.

`tools/`
- `vitriol-smoke-test.js` + `vitriol/tests.luau` — pure modules, 363 assertions.
- `vitriol-session-test.js` + `vitriol/session.luau` — the server, 80 assertions.
- `lib/luau-transform.js` — the shared Luau→Lua transform (both harnesses; also where the forbidden constructs are enforced).
- `lib/luau.js` (`stripCommentsAndStrings`), the `check-syntax`/`metrics`/`hot-loop-scan`/`call-graph`/`find-dead-config`/`evaluate-models` gates.
- `smoke-test.js`, `validate-project.js`, `audit.sh` are unrelated legacy — do not edit or reorganise `code/` for them.

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
  including indirect `require`s.
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
- **There is no gore module in this repository.** The user referred to "the provided
  gore module"; it does not exist. Stop looking. Its interface is specified in
  `docs/04` §3.3 and `docs/10`, with `GoreConfig.Contract`/`GoreConfig.Fallback`
  (asset-free). Keep it an external dependency with a working fallback and keep
  flagging the gap.
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
7. The kill is region-integrity damage from
   `|tendril velocity| × grip × region vulnerability`; zero integrity severs, then
   hands off via `GoreAdapter`.
8. **One scheduler.** `CadenceService` is driven by Bootstrap's single
   `RunService.Heartbeat` binding; services register slots. Consequence worth
   remembering when you add one: the file that touches `RunService` must contain no
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
