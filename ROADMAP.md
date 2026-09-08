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

## Iteration 3 — the server exists  🟨 **this one**

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
| New gate: `tools/vitriol-session-test.js` (fake DataModel + virtual clock), 78 assertions | ✅ |
| 363 runtime assertions in the smoke test (was 198) | ✅ |
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
cadence pump and the watchdog). 78 assertions, 0 failures.

### M2 — The body, no brain (WP5) ⬜
`TendrilRig`, `Locomotion`, `CreatureCore`, part-mode renderer, `BulkMoveTo`
writes, Studio keyboard pilot.
**Exit:** a human can drive the creature up a wall and across a ceiling at 60 Hz
with two creatures, `Profiler` < 1.2 ms.

### M3 — Instinct-only creature (WP6) ⬜
`Senses`, `Memory`, `Predictor`, `Steering`, `BehaviorTree`, `Tactics`, `Policy`
(UtilityAI + instinct prior, **Q disabled**).
**Exit:** make a noise → it investigates. Walk to the same Garage four times →
on the fourth it goes there *first*, and `AIDebugDump` shows why.

### M4 — Learning on (WP7) ⬜
`QLearning` wired in, episode serialization, species priors, A/B measurement.
**Exit:** capture rate over 20 simulated nights is measurably higher with learning
ON, and still below 1.0.

### M5 — The kill (WP8) ⬜
`Grapple`, `KillChoreography`, `GoreService`, `GoreAdapter`, `VictimCamera`.
**Exit:** all five criteria in `docs/04` §7, including running with **no** gore
assets present.

### M6 — World interaction (WP9–WP10) ⬜
`DestructionService`, `VehicleService`, `InventoryService`, `InteractionController`,
`SurvivalService`, `LightingDriver`, `CreatureAudio`, `VibrationFx`.
**Exit:** all criteria in `docs/05` §7, `docs/06` §9 and `docs/07` §6.

## Open decisions for the project owner

Tracked in `docs/02-MONSTER-DESIGN.md` §13:

1. Killable or only woundable? (recommendation: woundable for MVP)
2. Creature count at Threat 1.0? (recommendation: 1 → 2 by night 4)
3. Cross-server species evolution in the first playable? (recommendation: no)
4. Does the victim watch their own kill in first person? (recommendation: yes)
5. **The gore module** — supply it, or run on the built-in fallback?
   (`docs/04` §3 / `docs/10` §8)

## Known gaps in this iteration

- No creature or client code exists yet: `ServerStorage/Vitriol/Creature/*` is
  `Replicator` only, and nothing under `StarterPlayerScripts` has been written.
  `tools/call-graph.js` therefore still reports most `Lib`/`Shared` exports as
  *unused*; that is expected until WP5–WP10 consume them.
- `tools/find-dead-config.js --src code` will keep reporting Config blocks whose
  readers arrive later (WP2's remainder). To check a config you just touched, pass
  `--src code --file <that file>`, or it calls every top-level block dead. None of
  iteration 3's new keys are unread.
- `tools/check-syntax.js` fails on `Lib/RNG.luau` and `Lib/Noise.luau`: luaparse is a
  **Lua 5.1** parser and cannot read bitwise operators. Both files are executed for
  real by `tools/vitriol-smoke-test.js` under Lua 5.3, which is stronger evidence.
- The session harness proves *logic* against a fake DataModel. It cannot prove
  replication, attribute delivery timing, packet size, or that a client sees the sky
  it should — those stay on the Studio checklist (docs/06 §9 items 1-3,
  and the halves of 5-6 that need a real place).
- `tools/validate-project.js` expects a Rojo `default.project.json`. This project
  is deliberately Explorer-first, so that one check reports a missing project file
  by design.
