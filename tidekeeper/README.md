# TIDEKEEPER

A Roblox cozy trading game about a **tidal island post**, a **sea that rises and falls on
a real clock**, and **visitors who are real players you will never be online with**.

> **This repository folder is at the end of iteration 2.** It contains the complete
> research, the complete design, its own copy of the tooling, and **the pure simulation
> core**: 25 Luau modules under `code/ReplicatedStorage/Tidekeeper/`, exercised by 858
> executed assertions with 0 failures.
>
> Verification level: **L2 — executed in a Lua VM outside Roblox.** Nothing has run
> inside Roblox Studio yet, no DataStore has been touched, and the 18 µs performance
> budget is explicitly *not* verified. [`HANDOFF.md`](HANDOFF.md) §3 lists everything
> that is unproven; start there.

---

## Separation from VITRIOL

This is a **different game** from VITRIOL, which lives at the repository root in
`/code`, `/docs` and `/tools`. The two share a repository and nothing else.

| | VITRIOL | TIDEKEEPER |
| --- | --- | --- |
| Genre | night-survival horror, procedural creature | cozy async trading, tidal island |
| Tree | `/code`, `/docs`, `/tools` | `tidekeeper/code`, `tidekeeper/docs`, `tidekeeper/tools` |
| Tooling | `tools/vitriol-*.js` | `tidekeeper/tools/tidekeeper-*.js` (forked copy) |
| Maturity | Mature (gore) | **All Ages** |

**Hard rule, binding on every future iteration:** nothing in `tidekeeper/` may read,
reference or require anything in the VITRIOL tree, and nothing in the VITRIOL tree may
reference this folder. `tidekeeper/tools/tidekeeper-doc-gate.js` checks this.

---

## Read in this order

| # | Document | What it settles |
| --- | --- | --- |
| 1 | [`docs/00-VISION.md`](docs/00-VISION.md) | Pitch, pillars, core loop, scope, idea bank, title candidates |
| 2 | [`docs/01-ARCHITECTURE.md`](docs/01-ARCHITECTURE.md) | Layering, **Studio Explorer hierarchy**, authority, cadence, budgets |
| 3 | [`docs/02-TIDE-AND-TIME.md`](docs/02-TIDE-AND-TIME.md) | The shared clock — three harmonics, constants, test vectors |
| 4 | [`docs/03-ASYNC-SOCIAL.md`](docs/03-ASYNC-SOCIAL.md) | **The Drifter Exchange** — the differentiator |
| 5 | [`docs/04-SIMULATION-MODEL.md`](docs/04-SIMULATION-MODEL.md) | **Resolve-on-read**, determinism rules, economy invariants |
| 6 | [`docs/05-PERSISTENCE.md`](docs/05-PERSISTENCE.md) | Wire formats, key map, budgets against real 2026 limits |
| 7 | [`docs/06-ECONOMY-PROGRESSION.md`](docs/06-ECONOMY-PROGRESSION.md) | Currencies, Currents, the standing-order language, pacing |
| 8 | [`docs/07-WORLD-AND-CONTENT.md`](docs/07-WORLD-AND-CONTENT.md) | Island, zones, the Bar, content inventory, art direction |
| 9 | [`docs/08-CLIENT-UX-MOBILE.md`](docs/08-CLIENT-UX-MOBILE.md) | Six screens, the first 60 seconds, mobile rules, accessibility |
| 10 | [`docs/09-AI-BUILD-PIPELINE.md`](docs/09-AI-BUILD-PIPELINE.md) | **2026 survey of Roblox generative/vibe-coding AI** and how each iteration uses it |
| 11 | [`docs/10-RESEARCH-NOTES.md`](docs/10-RESEARCH-NOTES.md) | **Every sourced fact**, with confidence levels and known unknowns |
| 12 | [`docs/11-HUMAN-AUTHORED.md`](docs/11-HUMAN-AUTHORED.md) | What an AI must not be trusted to judge |
| 13 | [`docs/12-ITERATION-PROMPTS.md`](docs/12-ITERATION-PROMPTS.md) | **Copy-paste prompts for iterations 2–5+** and the handoff template |
| 14 | [`docs/13-RISKS-AND-COMPLIANCE.md`](docs/13-RISKS-AND-COMPLIANCE.md) | Risk register, safety design, monetisation, pre-launch checklist |
| — | [`ROADMAP.md`](ROADMAP.md) | Iteration tracker and open decisions |
| — | [`HANDOFF.md`](HANDOFF.md) | **Start here if you are the next agent** |

---

## The three findings that shape everything

Research on 2026-09-30 against live Roblox documentation and developer-forum sources
produced three constraints. Every architectural decision follows from them. Full sources
in [`docs/10-RESEARCH-NOTES.md`](docs/10-RESEARCH-NOTES.md).

1. **MemoryStore is a coordination cache, not storage.** Its memory quota is
   `64 KB + 1.2 KB × [number of users]` and it applies to the *whole universe*, not per
   server — roughly 1.2 MB at 1 000 CCU. Any async design that pools player data there
   dies at the moment it succeeds. The Drifter pool therefore lives in DataStore, and
   MemoryStore holds only a ~17 KB shard-fill index.

2. **You cannot run a server for an absent player, and you should not want to.** Open
   Cloud Luau Execution is capped at 5 minutes per task and 10 concurrent tasks per
   place — enough for one global nightly tick, hopeless for N posts. Hence
   **resolve-on-read**: cost scales with *sessions*, not with population × time. It also
   gives us Roblox's forthcoming offline solo play almost for free.

3. **Notification targeting must be computed at logout, not by scanning.** A developer
   measured ~5.5 hours to scan 100 000 DataStore entries at the Open Cloud read limit.
   Because the tide is a pure function of wall-clock time, the exact second of the next
   notable event is known the moment a player leaves — so the notification is scheduled
   then, from data already in hand.

---

## Layout

```
tidekeeper/
  docs/     14 design documents — the iteration-1 deliverable
  code/     empty; iterations 2+ fill it, mirroring the Explorer tree
  tools/    forked, TIDEKEEPER-specific analysis and gate tooling
  ROADMAP.md
  HANDOFF.md
```

`code/` will mirror Explorer paths exactly, e.g.
`code/ReplicatedStorage/Tidekeeper/Lib/Tide.luau` →
`ReplicatedStorage > Tidekeeper > Lib > Tide (ModuleScript)`.

**There is no Rojo project and there must not be one** — the hierarchy is specified as a
Studio Explorer tree ([`docs/01-ARCHITECTURE.md`](docs/01-ARCHITECTURE.md) §2).

---

## Running the checks

```bash
npm --prefix tidekeeper/tools install     # once (luaparse, fengari)

# The gate. Right now it runs the doc gate and reports that code/ is empty.
node tidekeeper/tools/tidekeeper-quality-gate.js

# Individual reports:
node tidekeeper/tools/tidekeeper-doc-gate.js
node tidekeeper/tools/check-syntax.js tidekeeper/code
node tidekeeper/tools/metrics.js --src tidekeeper/code
node tidekeeper/tools/hot-loop-scan.js --src tidekeeper/code
node tidekeeper/tools/call-graph.js --src tidekeeper/code
node tidekeeper/tools/find-dead-config.js --src tidekeeper/code
```

See [`tools/README.md`](tools/README.md). Iteration 2 adds
`tidekeeper-smoke-test.js`; iteration 3 adds `tidekeeper-session-test.js`.
