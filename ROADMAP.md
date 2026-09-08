# VITRIOL — Roadmap

Iteration tracker. Status legend: ⬜ not started · 🟨 in progress · ✅ done.

## Iteration 1 — **this one** ✅

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

## Milestones

### M0 — Foundations ✅ (this iteration)
Design locked, pure math core executing under test, all tunables in Config.

### M1 — Shared layer + services skeleton (WP1–WP4) ⬜
`Skeleton`, `SkeletonCodec`, `NoiseField`, `Remotes`, `NetContract`;
`SessionService`, `TimeService`, `ThreatService`, `HealthService`, `Bootstrap`,
`Profiler`.
**Exit:** an empty server runs the full Dawn→Night cycle and logs phase timings.

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

- No service, controller or creature code exists yet — everything under
  `ServerStorage`, `ServerScriptService` and `StarterPlayerScripts` is still
  design-only. `tools/call-graph.js` therefore reports every `Lib`/`Shared`
  export as *unused*; that is expected until WP1–WP10 consume them.
- `tools/find-dead-config.js` will report unread Config keys for the same reason.
  WP2's job is to drive that to zero.
- `tools/check-syntax.js` fails on `Lib/RNG.luau` only: luaparse is a **Lua 5.1**
  parser and cannot read bitwise operators. The file is executed for real by
  `tools/vitriol-smoke-test.js` under Lua 5.3, which is stronger evidence.
- `tools/validate-project.js` expects a Rojo `default.project.json`. This project
  is deliberately Explorer-first, so that one check reports a missing project file
  by design.
