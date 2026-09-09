# VITRIOL — Roadmap

Iteration tracker. Status legend: ⬜ not started · 🟨 in progress · ✅ done.

## Iteration 1 — foundations  ✅

Brainstorming, deep research, architecture, and a verified pure-code foundation.

| Deliverable | Status |
| --- | --- |
| `docs/00-VISION.md` — pillars, core loop, idea bank, scope | ✅ |
| `docs/01-ARCHITECTURE.md` — Explorer-first hierarchy, ownership, budgets | ✅ |
| `docs/02-MONSTER-DESIGN.md` — senses, memory, prediction, genetics, RL | ✅ |
| `docs/03-MONSTER-TECH.md` — FABRIK, rig, movement, replication | ✅ |
| `docs/04-KILL-CHOREOGRAPHY.md` — kill states, body integrity, gore contract | ✅ |
| `docs/05-SURVIVAL.md` — meters, coupling, debuffs | ✅ |
| `docs/06-DAY-NIGHT.md` — time model, keyframes, client-authoritative lighting | ✅ |
| `docs/07-DESTRUCTION-VEHICLES.md` — joint graph, integrity BFS, vehicles | ✅ |
| `docs/08-RESEARCH-NOTES.md` — sourced engine facts + gotchas | ✅ |
| `docs/09-HANDOFF-PROMPTS.md` — WP1–WP10 prompts | ✅ |
| `docs/10-HUMAN-AUTHORED.md` — specs for map/UI/meshes/audio (no code) | ✅ |
| `Lib/{MathExt,RNG,Fabrik,Genetics}` + `Shared/RegionIntegrity` | ✅ |
| `Config/{Game,DayNight,Monster,Survival,Destruction,Vehicle,Gore}Config` | ✅ |
| `tools/vitriol-smoke-test.js` + 78 runtime assertions | ✅ |

## Iteration 2 — pure layer, shared layer  ✅

Building the verified foundation outward, one work package at a time. Every module
below is *executed* by `tools/vitriol-smoke-test.js`, not merely parsed.

| Deliverable | Status |
| --- | --- |
| WP1 `Lib/Tables` — object pool (zero-allocation hot paths) | ✅ |
| WP1 `Lib/Signal` — connect/once/fire, safe disconnect during fire | ✅ |
| WP1 `Lib/Noise` — seeded value noise (permutation table) | ✅ |
| WP1 `Lib/SpatialHash` — fixed-cell spatial index + decay sampling | ✅ |
| WP1 `Lib/UtilityAI` — softmax option selection | ✅ |
| WP1 `Lib/QLearning` — linear Q, replacing traces, Boltzmann + instinct prior | ✅ |
| WP1 `Lib/MarkovPredictor` — player-pattern prediction + predictability | ✅ |
| WP3 `Shared/Skeleton` — flat-array joint chain, Fabrik-compatible | ✅ |
| WP3 `Shared/SkeletonCodec` — core-relative quantisation, DPCM feedback | ✅ |
| WP3 `Shared/NoiseField` — 6-channel decaying impulse field | ✅ |
| Harness: `require()` shim + multi-line `+=` support | ✅ |
| Runtime assertions at the end of iteration 2: 198 | ✅ |

## Iteration 3 — the server exists  ✅

The server foundation is complete and remains covered by the session harness. The
creature slice below is the current continuation.

The shared layer closed (WP3) and the server started (WP4), with both harnesses
executing real code. Everything below is *run*, not parsed.

| Deliverable | Status |
| --- | --- |
| WP3 `Shared/Remotes` — the only place a remote is created; `WaitForChild` + timeout on the client; polices `Comms` for strays | ✅ |
| WP3 `Shared/NetContract` — declarative schema per client→server message, token-bucket admission, monotonic-sequence replay guard; 400-payload fuzz | ✅ |
| WP3 `Skeleton:reset()` + rest pose (and a default chain built straight, not knotted) | ✅ |
| WP3 codec core orientation — 4×int8 quaternion, header 13 B, Braid snapshot 589 B; `docs/03` §7.1 corrected to agree | ✅ |
| WP3 buffer adapters in `Creature/Replicator` (not the codec) + executed array⇄Buffer parity proof | ✅ |
| WP3 `NoiseField` wind advection, weather masking, surface coupling — and `docs/02` §2 rewritten to match the ownership split | ✅ |
| WP3 round-trip test over **200 random chains**, max error 0.00820 studs vs the 0.02 budget | ✅ |
| WP4 `Services/CadenceService` — one Heartbeat-driven scheduler for all four cadences, staggered, slot-measured | ✅ |
| WP4 `TimeService` — clock *derived* from the phase machine (`DayNightConfig.RateCurve` deleted: an integrated clock and a paced phase machine drift apart) | ✅ |
| WP4 `SessionService` / `ThreatService` / `HealthService` + `Bootstrap` + `Main` | ✅ |
| WP4 `Diagnostics/Profiler` — per-cadence budget watchdog, auto-degrade one LOD tier | ✅ |
| WP4 `RemoteHandlers/{ClientIntentHandler,DebugHandler}` — validation applied; `RF_DebugQuery` is read-only by schema | ✅ |
| New gate: `tools/vitriol-session-test.js` (fake DataModel + virtual clock), 87 assertions | ✅ |
| 366 runtime assertions in the smoke test (was 198) | ✅ |
| WP2 remainder — `find-dead-config` still reports blocks whose readers arrive in WP5–WP10 (`Genes`, `Memory`, `Prediction`, `CollisionGroups`, `Tags`, `AnimationIds`, …) | ⬜ |

### Bugs found by writing the code (iteration 3, all fixed, all regression-tested)

| Where | What was wrong |
| --- | --- |
| `TimeService` | `clockMinutes` was computed with `minutesToClock(phaseClock(...))` — hours in, hours out, divided by 60 twice. A 6.66 h dawn reported as 0.11. The attribute contract (docs/06 §6, `0..1440`) is minutes, so the conversion is `clockToMinutes`. Found only by executing the service. |
| `TimeService` | called `noise:setWeather(kind, entry)` against a one-argument API; the entry landed in the wrong slot and the mask was indexed off a string. |
| `TimeService` | read `DayNightConfig.PhaseHours[phase]`, but that table is keyed `DayStart`/`DuskStart`/… — every lookup was nil. Fixed by routing all phase↔hour naming through `TimeModel.phaseSpan`, which also now *refuses* an unknown phase instead of silently answering Night. |
| `SessionService` | the injected logger field and the method were both called `log`, so the method resolved to the field and the field to the method: every log line became `[[vitriol]]` or a crash. The method is `emit` now, and the double-prefix bug it hid is gone. |
| `HealthService` | `killRegistered()` on a *player* death would have made dying make the hunt harder; the dial counts creatures the group killed. |
| `Bootstrap` | `stop()` left the noise-prune slot registered, so "stop cancels everything" was false. Asserted now (0 enabled slots after stop). |
| `DayNightConfig` | `RateCurve`'s mean 2.5 min/s (576 s/day) contradicted `Pacing`'s 555–735 s cycle: the sky and `PhaseName` would have disagreed within a minute of start. The table is deleted and the pace is `Pacing.Ease` instead. |
| `NoiseField` | advection sampled with a search window of wind × the channel's whole audibility lifetime — O(radius³) cells, and it hung the harness for 180 s (SCENT: 7 644 studs of span, 478³ cells). Now capped by `AdvectedMaxAge`, with the memory layer owning older evidence. |
| harness | the transform wrapped `for x in string.gmatch(...)` in `pairs(...)`, and stripped `: Type` annotations across a *call* line so `conn:disconnect()` became `conn()`. Both fixed in `tools/lib/luau-transform.js`, which is now shared by the two harnesses so they cannot disagree about what legal Luau is. |

### Bugs found by writing the code (all fixed, all now regression-tested)

| Where | What was wrong |
| --- | --- |
| `Lib/Noise` | xorshift32 used as a *lattice hash* collapsed to a near-constant (`value1(i)` spanned 0.0742–0.0816 over 64 samples — a dynamic range of 0.007). Replaced with a seeded permutation table. |
| `Lib/Noise` | the Fisher–Yates draw divided by 2⁴⁸ instead of 2³², so the shuffle was a fixed near-reversal. |
| `Lib/SpatialHash` | re-`insert`ing an existing id left `entries[id]` pointing at the old table with stale coordinates, while the cell index used the new ones. |
| `Lib/QLearning` | trace decay skipped the taken action, so stale eligibilities stayed pinned at 1.0 and credit flowed back at full strength forever. |
| `Shared/SkeletonCodec` | parent-relative quantisation (as originally specified in `docs/03` §7.1) costs 0.02748 studs at the tip vs a 0.00866 budget; switched to core-relative and corrected the doc. |

## Current continuation — playable procedural creature slice  🟨

This slice resolves the product decisions that were previously open: the Braid is
**woundable-only**, Threat 1 owns **one** creature, there is no cross-server species
evolution, and a victim watches the authoritative kill scene from their own head in
first person. The server remains single-authority and all gameplay cadence is still
owned by `CadenceService`.

| Deliverable | Status |
| --- | --- |
| `Creature/Body/TendrilRig` — numeric chains + constrained FABRIK + rest/noise pose | ✅ |
| `Creature/Body/Locomotion` — bounded ray fan, anchors, wall/ceiling up vector, open-ground glide | ✅ |
| `Creature/CreatureCore` — generated Braid Model/Parts, wound state, guarded `BulkMoveTo` | ✅ |
| `Services/CreatureService` — one-creature lifecycle, genome expression, cadence registration, target bridge | ✅ |
| `Creature/Body/KillChoreography` — cadence-stepped bounded victim scene | ✅ |
| `HealthService` — creature grab, player-only kill, optional dismemberment hook, Blood emission | ✅ |
| `Shared/BloodAdapter` + `BloodConfig` — BloodEngine probe, LOW gate, bounded fallback | ✅ |
| `StarterPlayerScripts/.../VictimCamera` — local first-person victim presentation | ✅ |
| Replicator stream wiring / generated parts | 🟨 — real `buffer`/Studio verification remains |
| Studio climb/ceiling proof, camera/audio/post-process polish | ⬜ — human verification required |
| Keyboard debug pilot | ⬜ — not needed for the one-player playable slice yet |

The Braid is generated entirely by code. No mesh or Studio-authored creature asset is
required for this slice. The supplied BloodEngine v1.1.3 source and `Assets.rbxm` are
checked in under `code/ReplicatedStorage/VModules/BloodEngine`; the adapter searches
that path first, accepts the source folder-with-`init` shape, and degrades to a bounded
stylised drop if Studio has not imported it. Optional limb hiding is disabled by
default and remains behind `BloodConfig.Dismemberment.Enabled`.

### M2 — The body, no brain  🟨
`TendrilRig`, `Locomotion`, `CreatureCore`, part-mode renderer, and server spawn are
implemented. Studio acceptance is still open: a human must verify wall/ceiling
purchase, visual readability, and the 1.2 ms frame budget in a real place.

### M5 — The kill  🟨
The minimum server/client path now exists: a creature reaching `GrabDistance` starts
`KillChoreography`, `HealthService` owns player damage/death, BloodAdapter emits LOW/FULL
visuals, and `VictimCamera` is local-only. Full region-integrity choreography,
Grapple interactions, audio/post-process, and a real BloodEngine/Studio pass remain.

## Milestones

### M0 — Foundations ✅ (this iteration)
Design locked, pure math core executing under test, all tunables in Config.

### M1 — Shared layer + services skeleton (WP1–WP4) ✅ (iteration 3)
`Skeleton`, `SkeletonCodec`, `NoiseField`, `Remotes`, `NetContract`;
`CadenceService`, `SessionService`, `TimeService`, `ThreatService`, `HealthService`,
`Bootstrap`, `Profiler`, `ClientIntentHandler`, `DebugHandler`.
**Exit — met, and executed:** `node tools/vitriol-session-test.js` boots the real
`Bootstrap` on a fake DataModel with a virtual clock and asserts that a zero-player
server runs a full cycle, logs exactly one line per phase change with the elapsed time,
never touches `Lighting`, and registers exactly two `Heartbeat` connections (the
cadence pump and the watchdog). 87 assertions, 0 failures.

### M2 — The body, no brain (WP5) 🟨
The code-generated one-creature body and server wiring are present; the two-creature
keyboard-pilot Studio exit is intentionally not claimed. See the continuation table
above for the verified headless scope.

### M3 — Instinct-only creature (WP6) ⬜
`Senses`, `Memory`, `Predictor`, `Steering`, `BehaviorTree`, `Tactics`, `Policy`
(UtilityAI + instinct prior, **Q disabled**).
**Exit:** make a noise → it investigates. Walk to the same Garage four times →
on the fourth it goes there *first*, and `AIDebugDump` shows why.

### M4 — Learning on (WP7) ⬜
`QLearning` wired in, episode serialization, species priors, A/B measurement.
**Exit:** capture rate over 20 simulated nights is measurably higher with learning
ON, and still below 1.0.

### M5 — The kill (WP8) 🟨
A minimum `KillChoreography`/`HealthService`/`BloodAdapter`/`VictimCamera` path is
implemented. Full Grapple, region-integrity choreography and Studio presentation are
still open; see the continuation table above.

### M6 — World interaction (WP9–WP10) ⬜
`DestructionService`, `VehicleService`, `InventoryService`, `InteractionController`,
`SurvivalService`, `LightingDriver`, `CreatureAudio`, `VibrationFx`.
**Exit:** all criteria in `docs/05` §7, `docs/06` §9 and `docs/07` §6.

## Resolved product decisions

1. Monsters are **never killable**; they are woundable until `Threatening=false`.
2. Threat 1 owns **one** creature for the readable MVP.
3. Cross-server species evolution is **not** implemented.
4. A victim watches their own kill in **first person**; spectators retain third-person.
5. BloodEngine/Blood is the integration seam. The v1.1.3 source is checked in, but
   runtime still tolerates a Studio place that has not imported it; LOW stylised
   fallback remains bounded.
6. Limb dismemberment is optional and disabled by default through
   `BloodConfig.Dismemberment.Enabled`.

The only remaining decision is the human Studio/content pass, not the gameplay
authority or scope.

## Known gaps in this iteration

- The headless server path is live, but Roblox Studio has not been run here. A human
  must verify actual Part rendering, wall/ceiling raycasts, `BulkMoveTo`, real Buffer
  replication, the client camera, and audio/post-process presentation.
- BloodEngine v1.1.3 source and `Assets.rbxm` are now checked in under
  `code/ReplicatedStorage/VModules/BloodEngine` with its MIT notice. `BloodAdapter`
  probes `ReplicatedStorage/VModules/BloodEngine` first and accepts either a root
  ModuleScript or a Folder containing `init`; Studio import/layout and real visuals
  remain unverified.
- Full `Grapple`, region-integrity sever ordering, predator AI (`Senses`/`Memory`/
  `Steering`), survival, destruction, vehicles, and human-authored UI/audio remain
  later roadmap work. The current kill scene is intentionally a minimal playable seam.
- `tools/find-dead-config.js --src code` still uses its legacy default file list and
  reports those two absent Gerstner paths. Per-config audits were run with explicit
  `--file` arguments; future WP readers are expected to make several planned keys live.
- `tools/check-syntax.js` fails on `Lib/RNG.luau` and `Lib/Noise.luau`: luaparse is a
  **Lua 5.1** parser and cannot read bitwise operators. Both files, plus the new
  choreography, are executed for real by the smoke/session harnesses.
- The project remains Explorer-first. `tools/validate-project.js` expects a Rojo
  `default.project.json`; no such project is to be created merely for tooling.

## Latest validation snapshot — 2026-09-09 UTC

- `node tools/vitriol-smoke-test.js`: **366 passed, 0 failed**.
- `node tools/vitriol-session-test.js`: **87 passed, 0 failed**; includes creature
  spawn, bounded victim scene, first-person event payload, player-only death, wound-only
  creature disablement, and no extra scheduler.
- `node tools/check-syntax.js code`: **43 files parse**; the two known Lua 5.1 parser
  exceptions remain `Lib/RNG.luau` and `Lib/Noise.luau` (bitwise `&`).
- `node tools/metrics.js --src code`: **45 files; LOC 10993 | code 8001 | comments
  2125 | exports 381 | requires 35**.
- `node tools/hot-loop-scan.js --src code`: **Priced calls 31 | inside-a-loop 8 | in
  a RunService file 0**; the extra loop flag is the kill-only limb lookup.
- `node tools/call-graph.js --src code`: **45 modules | 381 exports | 35 require
  edges**; includes the BloodAdapter/CreatureService/kill/camera edges.
- `node tools/find-dead-config.js --src code`: the legacy default reports the two
  absent Gerstner paths; explicit Vitriol config audits retain documented future-WP
  keys (`MonsterConfig` AI, `GoreConfig` body-integrity, `GameConfig` animation/tag
  settings) rather than deleting planned readers.
- `node tools/evaluate-models.js --models tools/models.example.json --suite
  tools/evaluation-suite.example.json`: `fixture-known-good: ADMIT 100.0%`,
  `candidate-local: REJECT 0.0%`.
