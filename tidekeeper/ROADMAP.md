# TIDEKEEPER — Roadmap

Iteration tracker. Status legend: ⬜ not started · 🟨 in progress · ✅ done.

Separate from the VITRIOL roadmap at the repository root. The two games share a
repository and nothing else.

---

## Iteration 1 — research, design, tooling fork ✅

| Deliverable | Status |
| --- | --- |
| Web research: 2026 Roblox platform, RDC 2026, data-service limits, policy | ✅ |
| Web research: Roblox generative / "vibe coding" AI tooling survey | ✅ |
| Web research: 2026 charts, genre performance, retention benchmarks | ✅ |
| Concept selection and lock | ✅ |
| `docs/00-VISION.md` — pitch, pillars, loop, scope, idea bank, titles | ✅ |
| `docs/01-ARCHITECTURE.md` — layering, Explorer tree, authority, cadence, budgets | ✅ |
| `docs/02-TIDE-AND-TIME.md` — constants, states, epochs, 12 test vectors | ✅ |
| `docs/03-ASYNC-SOCIAL.md` — the Drifter Exchange, two-tier storage, fairness | ✅ |
| `docs/04-SIMULATION-MODEL.md` — resolve-on-read, determinism rules, invariants | ✅ |
| `docs/05-PERSISTENCE.md` — key map, wire formats, budgets, locking, retries | ✅ |
| `docs/06-ECONOMY-PROGRESSION.md` — currencies, Currents, standing orders, pacing | ✅ |
| `docs/07-WORLD-AND-CONTENT.md` — island, zones, content inventory, art direction | ✅ |
| `docs/08-CLIENT-UX-MOBILE.md` — six screens, first 60 s, mobile, accessibility | ✅ |
| `docs/09-AI-BUILD-PIPELINE.md` — AI tool survey + per-iteration usage + rules | ✅ |
| `docs/10-RESEARCH-NOTES.md` — 40+ sourced facts, confidence levels, unknowns | ✅ |
| `docs/11-HUMAN-AUTHORED.md` — briefs for everything an AI must not judge | ✅ |
| `docs/12-ITERATION-PROMPTS.md` — prompts for it2–it6+, handoff template | ✅ |
| `docs/13-RISKS-AND-COMPLIANCE.md` — 15-risk register, safety, monetisation | ✅ |
| `tools/` — forked analysis tooling scoped to `tidekeeper/` | ✅ |
| `tools/tidekeeper-doc-gate.js` — new, validates the docs themselves | ✅ |
| `tools/tidekeeper-quality-gate.js` — new, degrades honestly while `code/` is empty | ✅ |
| Gameplay code | ⬜ **deliberately none — iteration 2** |

## Iteration 2 — the pure core ✅

| Deliverable | Status |
| --- | --- |
| `Lib/{Tide,RNG,Hash,MathExt,Tables,Signal,Codec,Schema}` | ✅ 8 modules |
| `Domain/{Post,Drifter,Orders,Visit,Resolve,Ledger,Almanac,Standing}` | ✅ 8 modules |
| `Shared/{DrifterCodec,PostCodec,Version}` | ✅ 3 modules |
| `Config/{Game,Tide,Economy,Drifter,Orders}Config` + `FindsConfig` | ✅ 6 modules |
| `tools/tidekeeper-smoke-test.js`, ≥ 300 executed assertions | ✅ **858**, 0 failed |
| Both determinism proofs (doc 04 §5.1) green | ✅ plus a third, on the clamped path |
| `Visit.resolve` benchmarked against the 18 µs budget | 🟨 measured, **not verified** — see below |
| `tools/tidekeeper-determinism-scan.js` (tools/README §5) | ✅ 8 rules, clean |
| Zero-allocation claim for `Visit.resolve` | ✅ two proofs, neither a heap profiler |
| Doc corrections found by executing the spec | ✅ 5 (docs 02, 04, 05, 06) |

**The benchmark caveat, stated plainly.** `Visit.resolve` runs at a **1.73 ms median /
2.36 ms p99** inside fengari. fengari is a Lua interpreter written in JavaScript; the
same harness measures 1e6 integer additions at ~94 ms, i.e. ~94 ns per addition against
Luau's ~1–2 ns. Dividing through puts the real figure somewhere in the 20–60 µs band —
which straddles the 18 µs budget and therefore **proves nothing**. The budget is an
iteration-3 task, measured in Studio via the MCP `execute_luau` tool (doc 09 §3). The
harness number is a regression tripwire, not a verdict.

## Iteration 3 — the server exists ⬜

| Deliverable | Status |
| --- | --- |
| **First task:** verify the shipped async-notification API and correct doc 10 §6 | ⬜ |
| `Adapters/{DataStore,Memory,Notify,Policy}Adapter` | ⬜ |
| `Services/{Cadence,Player,Post,Exchange,Ledger,Notify,Showcase}Service` | ⬜ |
| `Bootstrap`, `Main`, `RemoteHandlers/*`, `Diagnostics/{Profiler,BudgetMeter}` | ⬜ |
| `Shared/{Remotes,NetContract}` | ⬜ |
| In-memory fake persistence with injected failures (doc 05 §11) | ⬜ |
| `tools/tidekeeper-session-test.js` — 30-day / 200-session simulated lifetime | ⬜ |
| Economy invariants green across that lifetime | ⬜ |
| Measured request cost vs. the 5/session budget | ⬜ |
| `fixture-blobs/` + migration tests | ⬜ |

## Iteration 4 — it plays ⬜

| Deliverable | Status |
| --- | --- |
| `ClientMain`, six controllers, six screens | ⬜ |
| The Ledger replay, re-running the real `Visit.resolve` | ⬜ |
| ≥ 40 Ledger prose templates | ⬜ |
| RDC 2026 UI feature flags + fallbacks | ⬜ |
| Studio MCP connection; Explorer tree built by script | ⬜ |
| `execute_luau` verification: buffer/base64, MemoryStore, `Tide.height` cost | ⬜ |
| Playtest with console output + screenshots | ⬜ |
| **R1: the Ledger in front of five real humans** | ⬜ |

## Iteration 5 — it ships ⬜

| Deliverable | Status |
| --- | --- |
| 200 finds via the generative pipeline + human curation gate | ⬜ |
| 180 Ledger templates, 120 letters, 64 Seed Drifters, 90 décor, 4 tiers, 40 badges | ⬜ |
| Island finished (Scene Generator if shipped, hand-built otherwise) | ⬜ |
| Economy tuned against 8 simulated play patterns | ⬜ |
| **R4: cold-start playtest at < 200 DAU** | ⬜ |
| Shipping title chosen against live search data | ⬜ |
| Thumbnail + 3 Moments clips | ⬜ |
| Pre-launch checklist (doc 13 §6) complete | ⬜ |
| Telemetry + soft-launch region + rollback plan | ⬜ |

## Iteration 6+ ⬜

Contingency, live telemetry, then the idea bank in doc 00 §9. Scope is defined by
`HANDOFF.md`, not by this table.

---

## Open decisions

Recorded rather than guessed. Each has an owning iteration.

| # | Decision | Owner | Current lean |
| --- | --- | --- | --- |
| OD1 | Shipping title (doc 00 §10) | it5 | "Keep a Tidepost" |
| OD2 | Currents geographic or thematic (doc 03 §12) | it5 | Thematic, with a geographic bias in shard selection |
| OD3 | Drifter TTL — is 7 days right? | it5 | Instrument it; do not guess |
| OD4 | Do Echoes read as dishonest? (doc 03 §8) | it5 | Playtest; the Ledger marker must be prominent |
| OD5 | Is `warmth` ever public? (doc 03 §12, doc 08 §9) | it5 | No, aggregate colour only. Reopen only with a policy review |
| OD6 | Can a player see whose Drifter it was? (doc 03 §12) | it4 | Display name only, no link, no join |
| OD7 | Does the daily notification cap really reset on visit? (doc 10 §1.2) | it3 | Verify against shipped docs; design for 1/day regardless |
| OD8 | Does Scene Generator ship in 2026? (doc 09 §2) | it5 | Assume no; hand-build contingency is the plan of record |
| OD9 | Do MemoryStore keys count toward the memory quota? (doc 10 §6) | it3 | Size assuming they do |
| OD10 | Offline-play reconciliation policy (doc 04 §11) | it5 | Last-write-wins on post, union on ledger, conflict noted |
| OD11 | Rewarded Video Ads at all? (doc 13 §4) | post-it5 | Not at launch; the tone is fragile |
| OD12 | Is `Visit.resolve` actually inside 18 µs in Luau? | it3 | Unknown. Measure in Studio before tuning anything |
| OD13 | Arrival scheduling is window-width dependent (see below) | it3 | `ExchangeService` must deliver each Drifter to exactly one resolve |
| OD14 | Should `warmth` feed the price a Drifter will accept, not just the prose? | it5 | Currently prose-only. Playtest first |

### OD13 in full — the one non-commuting property

Iteration 2 found and **pinned** a property that iteration 3 must respect. A Drifter's
arrival epoch is `firstEpoch + (Hash.mix(id, salt, 7) mod epochCount)`. `epochCount` is
the width of the window being resolved, so feeding the *same* inbound list to a 1-epoch
resolve and then a 2-epoch resolve does **not** produce the state of a single 3-epoch
resolve. With no inbound drifters the resolver commutes exactly (asserted); with inbound
drifters it does not (also asserted, as a negative test, so it cannot silently change).

This is correct behaviour, not a bug: in the live game the exchange hands each Drifter
to exactly one resolve. But it makes *at-most-once delivery* a hard requirement on
`ExchangeService`, not a nicety, and a retry that re-delivers a batch would corrupt
history rather than duplicate it.

## Validation snapshot — end of iteration 2

Full command output is pasted in [`HANDOFF.md`](HANDOFF.md) §2.

| Check | Real output |
| --- | --- |
| `tidekeeper-doc-gate.js` | **148/148** checks passed |
| `tidekeeper-quality-gate.js` | **10/11** passed, 1 not applicable yet (session harness, iteration 3) |
| `check-syntax.js` | all **25** Luau files parsed |
| `tidekeeper-determinism-scan.js` | **clean** — 25 files, 5 288 lines, 8 rules |
| `tidekeeper-smoke-test.js` | **858 passed, 0 failed**, 3/3 static proofs |
| `find-dead-config.js` | 5 keys unreferenced, all reserved for iterations 3–4 (listed in HANDOFF §5) |
| Gameplay code | 25 modules, 5 263 lines, layers L0/L2 only |
| Verification level claimed | **L2 — executed in a Lua VM outside Roblox** (doc 09 §4) |

### Iteration-1 snapshot, kept for the record

| Check | Real output |
| --- | --- |
| `tidekeeper-doc-gate.js` | 137/137 |
| `tidekeeper-quality-gate.js` | 3 pass, 7 N/A, 0 fail |
| Gameplay code | none — deliberately |
| Verification level claimed | none (docs only) |
