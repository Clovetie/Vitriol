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

## Iteration 2 — the pure core ⬜

| Deliverable | Status |
| --- | --- |
| `Lib/{Tide,RNG,Hash,MathExt,Tables,Signal,Codec,Schema}` | ⬜ |
| `Domain/{Post,Drifter,Orders,Visit,Resolve,Ledger,Almanac,Standing}` | ⬜ |
| `Shared/{DrifterCodec,PostCodec,Version}` | ⬜ |
| `Config/{Game,Tide,Economy,Drifter,Orders}Config` | ⬜ |
| `tools/tidekeeper-smoke-test.js`, ≥ 300 executed assertions | ⬜ |
| Both determinism proofs (doc 04 §5.1) green | ⬜ |
| `Visit.resolve` benchmarked against the 18 µs budget | ⬜ |
| `tools/tidekeeper-determinism-scan.js` (tools/README §5) | ⬜ |

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

## Validation snapshot — end of iteration 1

| Check | Real output |
| --- | --- |
| `tidekeeper-doc-gate.js` | see `HANDOFF.md` §2 |
| `tidekeeper-quality-gate.js` | see `HANDOFF.md` §2 |
| Gameplay code | none — deliberately |
| Verification level claimed | **none** (docs only; see doc 09 §4) |
