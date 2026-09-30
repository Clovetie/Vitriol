# VITRIOL

A Roblox night-survival horror game about an **IK-controlled, blind, tendril
creature** that hunts by vibration, scent and memory — and **learns your habits**.

> **This repository is at the playable procedural-creature slice:** the Braid,
> single-scheduler server wiring, woundable-only creature rules, first-person victim
> scene, and BloodEngine adapter are executed by the headless harnesses. `docs/` is
> the design; the modules under `code/` mirror the Explorer tree and are the source
> of truth.

> **This repository also hosts a second, unrelated game.**
> [`tidekeeper/`](tidekeeper/README.md) is **TIDEKEEPER**, a cozy asynchronous trading
> game, at the end of its own iteration 1 (research + design + forked tooling, no code
> yet). The two projects share a repository and nothing else: neither tree may
> reference the other, and each has its own `docs/`, `code/`, `tools/`, `ROADMAP.md`
> and `HANDOFF.md`. Everything below this line is about VITRIOL only.

---

## Read in this order

| # | Document | What it settles |
| --- | --- | --- |
| 1 | [`docs/00-VISION.md`](docs/00-VISION.md) | Pillars, core loop, idea bank, scope, what AI builds vs what a human builds |
| 2 | [`docs/01-ARCHITECTURE.md`](docs/01-ARCHITECTURE.md) | **Studio Explorer hierarchy**, ownership, tick budgets, replication rules |
| 3 | [`docs/02-MONSTER-DESIGN.md`](docs/02-MONSTER-DESIGN.md) | Senses, memory, prediction, genetics, the RL specification |
| 4 | [`docs/03-MONSTER-TECH.md`](docs/03-MONSTER-TECH.md) | FABRIK math, rig, anchor-and-haul movement, replication |
| 5 | [`docs/04-KILL-CHOREOGRAPHY.md`](docs/04-KILL-CHOREOGRAPHY.md) | The procedural kill, body integrity, BloodEngine adapter |
| 6 | [`docs/05-SURVIVAL.md`](docs/05-SURVIVAL.md) | Hunger/thirst coupling; `Parched`, `Starved`, `Collapse` |
| 7 | [`docs/06-DAY-NIGHT.md`](docs/06-DAY-NIGHT.md) | Seamless cycle, keyframe table, client-authoritative lighting |
| 8 | [`docs/07-DESTRUCTION-VEHICLES.md`](docs/07-DESTRUCTION-VEHICLES.md) | Breakable joint graph, integrity collapse, cars |
| 9 | [`docs/08-RESEARCH-NOTES.md`](docs/08-RESEARCH-NOTES.md) | **Sourced** engine facts and gotchas |
| 10 | [`docs/09-HANDOFF-PROMPTS.md`](docs/09-HANDOFF-PROMPTS.md) | Copy-paste prompts WP1–WP10 for the next iteration |
| 11 | [`docs/10-HUMAN-AUTHORED.md`](docs/10-HUMAN-AUTHORED.md) | Briefs + hierarchies for map, UI, meshes, audio — **no code** |
| — | [`ROADMAP.md`](ROADMAP.md) | Milestones and open decisions |

---

## The three findings that shape everything

Research (2026-09-08) against the live Roblox documentation produced three
non-obvious constraints. Every architectural decision follows from them. Full
sources in [`docs/08-RESEARCH-NOTES.md`](docs/08-RESEARCH-NOTES.md).

1. **`Lighting.ClockTime` is flagged `Not Replicated`.** A server-side day/night
   system silently does nothing on clients. The clock is therefore published as a
   replicated *value* and each client applies it locally (`LightingDriver`).

2. **`Bone.Transform` is writable at runtime but bones are neither replicated nor
   serialized.** Procedural bone animation is a *presentation* layer, so the
   creature's skeleton is simulated on the server, packed into a `Buffer`, and
   reconstructed per client.

3. **`IKControl` is the wrong tool for this creature.** It needs a
   `Humanoid`/`AnimationController` + `Animator`, has no notion of cone limits,
   curl, taper or rest pose, and had a same-year regression (reported Feb 2026,
   fixed May 2026). We implement **constrained FABRIK** ourselves instead — pure
   Luau, unit-tested, and it is what makes the tendril character possible.

---

## Layout

```
docs/     11 design documents (the iteration-1 deliverable)
code/     Copy-paste-ready Luau, mirroring the Studio Explorer tree
tools/    The repo's analysis tooling + the Vitriol runtime smoke test
ROADMAP.md
```

`code/` mirrors Explorer paths so the destination of each file is obvious, e.g.
`code/ReplicatedStorage/Vitriol/Lib/Fabrik.luau` →
`ReplicatedStorage > Vitriol > Lib > Fabrik (ModuleScript)`. Every file also
states that path in a header comment.

**There is no Rojo project and there must not be one** — the hierarchy is
specified as a Studio Explorer tree (`docs/01-ARCHITECTURE.md` §2).

---

## Running the checks

```bash
npm --prefix tools install        # once

# One strict, dependency-light evidence gate:
node tools/vitriol-quality-gate.js --src code

# Or run an individual report:
node tools/vitriol-smoke-test.js
node tools/vitriol-session-test.js
node tools/check-syntax.js code
node tools/metrics.js --src code
node tools/hot-loop-scan.js --src code
node tools/call-graph.js --src code
node tools/find-dead-config.js --src code
node tools/evaluate-models.js \
  --models tools/models.example.json \
  --suite tools/evaluation-suite.example.json
```

`tools/vitriol-smoke-test.js` loads the **real** modules from `code/` into a
Lua 5.3 VM (fengari) and asserts their behaviour — convergence, bone-length
preservation, cone limits, determinism, genome budget projection, kill choreography,
and that two different coil geometries produce different sever orders. The session
harness boots the server with a virtual DataModel and exercises creature spawning,
first-person victim events, player-only death, and scheduler invariants. These are
not reimplementations, so regressions in the source modules fail the suites.

### Verified state

Re-run every time; these are the latest recorded outputs:

| Check | Result |
| --- | --- |
| `vitriol-smoke-test.js` | **366 passed, 0 failed** |
| `vitriol-session-test.js` | **87 passed, 0 failed** |
| `check-syntax.js code` | **43 OK, 2 known failures** — `Lib/RNG.luau` and `Lib/Noise.luau` use Luau bitwise syntax rejected by the Lua 5.1 parser |
| `metrics.js --src code` | **45 files; LOC 10993; code 8001; comments 2125; exports 381; requires 35** |
| `hot-loop-scan.js --src code` | **31 priced calls; 8 inside loops; 0 in a RunService file** |
| `call-graph.js --src code` | **45 modules; 381 exports; 35 require edges** |
| `find-dead-config.js --src code` | all eight Vitriol configs; planned future-WP keys are reported for review |
| model evaluation | **ADMIT 100.0% / REJECT 0.0%** |
| `vitriol-quality-gate.js --src code` | **9/9 checks passed** |

---

## BloodEngine / Studio verification

The supplied BloodEngine v1.1.3 source and `Assets.rbxm` are checked in at
`code/ReplicatedStorage/VModules/BloodEngine` under the MIT notice. Import it into
Studio as `ReplicatedStorage > VModules > BloodEngine`; `Shared/BloodAdapter` accepts
either a root ModuleScript or a Folder containing `init`. Until that human import and
visual pass happens, the bounded LOW fallback keeps the server path playable. Real
BloodEngine droplets/pools, Buffer replication, wall/ceiling traversal, and camera
feel remain Studio acceptance work and are not claimed by the headless harnesses.
