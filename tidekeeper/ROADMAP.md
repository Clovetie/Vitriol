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

## Iteration 3 — the server exists ✅

| Deliverable | Status |
| --- | --- |
| **First task:** verify the shipped async-notification API and correct doc 10 §6 | ✅ it has **not** shipped; doc 10 §6.1 |
| `Adapters/{DataStore,Memory,Notify,Policy}Adapter` | ✅ |
| `Services/{Cadence,Player,Post,Exchange,Ledger,Notify,Showcase}Service` | ✅ |
| `Bootstrap`, `Main`, `RemoteHandlers/*`, `Diagnostics/{Profiler,BudgetMeter}` | ✅ |
| `Shared/{Remotes,NetContract,ReceiptCodec}`, `Config/NotifyConfig` | ✅ |
| Fake platform with injected failures (doc 05 §11) | ✅ a fake **DataModel**, not a fake adapter — 705 lines |
| `tools/tidekeeper-session-test.js` — 30-day / 200-session simulated lifetime | ✅ 14 scenarios, 72 assertions |
| Economy invariants green across that lifetime | ✅ `Post.checkInvariants` after every chunk |
| Measured request cost vs. the 5/session budget | ✅ **5.64 DataStore, 5.24 MemoryStore** per session |
| Determinism scan extended, never weakened | ✅ 8 rules → 12; three of them stricter replacements |
| `tools/lib/harness.js` extracted, smoke test unchanged at 858 | ✅ |
| `fixture-blobs/` + migration tests | ⬜ **deferred to it4** — folded into OD16, which needs schema v2 anyway |

**Three defects found by the harness, all fixed** (doc 03 §6.3): locks were never
released, 27 Drifters per simulated month were delivered twice, and a MemoryStore
outage blocked every join. The first two were the same platform fact — returning `nil`
from an `UpdateAsync` transform aborts the update, it does not delete the key.

## Iteration 4 — it plays 🟡

| Deliverable | Status |
| --- | --- |
| `Client/` layer: bootstrap + six views, all integer-driven | ✅ 8 modules + 1 LocalScript |
| `Client/Strings` — every word the player reads, keyed by template id | ✅ |
| The Ledger replay, re-running the real `Visit.resolve` | ✅ `LedgerView` |
| ≥ 40 Ledger prose templates | ✅ 21 ids × 3–4 variants |
| **OD16: `S.publishedAt` in PostCodec v2, with a real migration through `Shared/Version`** | ✅ doc 05 §6.1 |
| Migration test: load a v1 blob, assert it upgrades | ✅ committed 249-byte fixture |
| Localisation-coverage test: every template id and slot arity renders | ✅ scenario 15 |
| **OD12 settled** | ✅ — by **real Luau**, not MCP. doc 04 §6.1, L3.5 |
| Studio MCP connection; `execute_luau` | ⬜ **no Studio reachable** — deferred to it5 |
| `execute_luau` verification: buffer/base64 round trip, MemoryStore, `Tide.height` cost | ⬜ deferred to it5 |
| Playtest with console output + screenshots | ⬜ deferred to it5 |
| **R1: the Ledger in front of five real humans** | ⬜ deferred to it5 |

The half of iteration 4 that needed a running Roblox Studio did not happen, because
none is reachable from this environment — the same wall iterations 2 and 3 hit. What
changed is that **one of those blocked items turned out not to need Studio at all**:
OD12 was closed by building the standalone Luau VM (doc 10 §7.4). The remaining
Studio-shaped work is genuinely Studio-shaped and is restated in iteration 5.

## Iteration 5 — the harness tells the truth 🟡

Triage (doc 10 §8) found Studio unreachable for the fourth iteration, so iteration 5
took the no-Studio branch of its own prompt: tooling truth first, then content.

| Deliverable | Status |
| --- | --- |
| **OD17: the correctness suite runs in real Luau, zero shims** | ✅ 887 = 887, cross-checked |
| **Scenario 16: the client driven against the real server** | ✅ found 2 load-time crashes |
| Module list deduplicated into `lib/module-map.js` | ✅ |
| 200 finds via the generative pipeline + human curation gate | ⬜ **not started** |
| 180 Ledger templates, 120 letters, 64 Seed Drifters, 90 décor, 4 tiers, 40 badges | ⬜ **not started** |
| Island finished (Scene Generator if shipped, hand-built otherwise) | ⬜ **not started** |
| Economy tuned against 8 simulated play patterns | ⬜ **not started** |
| **R4: cold-start playtest at < 200 DAU** | ⬜ needs humans |
| Shipping title chosen against live search data | ⬜ |
| Thumbnail + 3 Moments clips | ⬜ |
| Pre-launch checklist (doc 13 §6) complete | ⬜ |
| Telemetry + soft-launch region + rollback plan | ⬜ |

**This iteration did not ship the game.** It is named for what it actually did: made
the test harness trustworthy, and ran the client for the first time. Content volume,
economy tuning and everything requiring a human or an engine move to iteration 6.

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
| OD7 | Does the daily notification cap really reset on visit? (doc 10 §1.2) | ~~it3~~ | **Moot for now (doc 10 §6.1): the API has not shipped.** The shipped docs describe a flat 1/user/day static throttle and that is what `NotifyService` enforces |
| OD8 | Does Scene Generator ship in 2026? (doc 09 §2) | it5 | Assume no; hand-build contingency is the plan of record |
| OD9 | Do MemoryStore keys count toward the memory quota? (doc 10 §6) | ~~it3~~ | **Answered (doc 10 §6.2): documented as counting for sorted maps, unstated for hash maps.** `MemoryAdapter` charges for them |
| OD10 | Offline-play reconciliation policy (doc 04 §11) | it5 | Last-write-wins on post, union on ledger, conflict noted |
| OD11 | Rewarded Video Ads at all? (doc 13 §4) | post-it5 | Not at launch; the tone is fragile |
| OD12 | Is `Visit.resolve` actually inside 18 µs in Luau? | ~~it4~~ | **Closed at L3.5 (doc 04 §6.1).** Real Luau 0.700, median **15.9 µs** against an 18 µs budget — inside, but only 1.1×. p99 26.3 µs and full catch-up 2.9 ms both have room. `--codegen` is *slower*, so the hot path is table-bound, not arithmetic-bound |
| OD13 | Arrival scheduling is window-width dependent (see below) | ~~it3~~ | **Closed.** `CadenceService.planChunks` and `chunkForDrifter` are pure; at-most-once is asserted by session scenario 8 |
| OD14 | Should `warmth` feed the price a Drifter will accept, not just the prose? | **it5** | **Lean: no — keep it prose-only.** Now that the client exists, `warmth` reads as memory and courtesy. Wiring it into price turns it into a stat to farm and makes every visitor an optimisation problem, which is the opposite of doc 00's pillars. Decide against a playtest, not in the abstract |
| OD15 | DataStore compresses values itself; does our base64 packing still pay? (doc 10 §6.2) | it4 | Binary packing is not compression, but base64 inflates 33 %. Sizes are far inside budget — measure, do not redesign |
| OD17 | Run the correctness suite in real Luau instead of transformed Lua 5.3 | ~~it5~~ | **Closed (doc 10 §8.4), and without Lute.** `tidekeeper-luau-test.js` runs the suite shim-free; 887 = 887 against fengari, 0.7 s vs 72 s. Lute release binaries remain unreachable and turned out not to be needed — it would have added a test runner and a profiler, not a different measurement |
| OD18 | Adopt **LibMP** to measure the client frame budget on real devices (doc 10 §7.2) | it6 | Yes for the Ledger replay, sampled on a fraction of sessions — Roblox warns it raises memory. **Blocked on Studio**, like L4/L5 |
| OD19 | Port `fake-platform.lua` to real Luau so fengari can be deleted entirely | it6+ | Only worth it if the shims start costing again. The cross-check between two VMs is currently an asset, not debt |
| OD16 | `S.publishedAt` is not persisted, so one-Drifter-per-epoch holds only per server (doc 10 §6.4) | ~~it4~~ | **Closed.** Schema v2 appends it at the blob tail with a real migration and a committed v1 fixture (doc 05 §6.1). Shipped a sentinel bug en route — see **D28** |

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

## Validation snapshot — end of iteration 5

| Check | Real output |
| --- | --- |
| `tidekeeper-quality-gate.js` | **13/13** checks passed |
| `tidekeeper-doc-gate.js` | **172/172** checks passed |
| `check-syntax.js` | all **57** Luau files parsed |
| `tidekeeper-determinism-scan.js` | **clean** — 13 rules, 5 allowances, **2/2** RunService connections |
| `tidekeeper-smoke-test.js` (fengari) | **888 passed, 0 failed**, 3/3 static proofs |
| `tidekeeper-luau-test.js` (real Luau) | **887 passed, 0 failed, agrees with fengari** — 0.7 s |
| `tidekeeper-session-test.js` | **167 passed, 0 failed** — 16 scenarios |
| `tidekeeper-luau-bench.js` | **within budget** — median 15.5 µs, p99 23.8 µs, catch-up 2.87 ms |
| Executed assertions | **1 055** (888 + 167), plus 887 cross-checked in a second VM |
| Verification level claimed | **L3.5** — correctness *and* timings now in a real Luau VM. Still not L4: no engine |

## Validation snapshot — end of iteration 4

Full command output is pasted in [`HANDOFF.md`](HANDOFF.md) §2.

| Check | Real output |
| --- | --- |
| `tidekeeper-quality-gate.js` | **12/12** checks passed (11/12 + 1 skip without a local `luau` binary) |
| `tidekeeper-doc-gate.js` | **172/172** checks passed |
| `check-syntax.js` | all **57** Luau files parsed |
| `tidekeeper-determinism-scan.js` | **clean** — 57 files, **13** rules, 5 explicit allowances, **2/2** RunService connections |
| `tidekeeper-smoke-test.js` | **888 passed, 0 failed**, 3/3 static proofs |
| `tidekeeper-session-test.js` | **117 passed, 0 failed** — 15 scenarios against a fake DataModel |
| `tidekeeper-luau-bench.js` | **within budget** — median 15.9 µs, p99 22.3 µs, catch-up 2.95 ms |
| Measured platform cost | **5.64 DataStore / 5.24 MemoryStore requests per session** (unchanged) |
| Gameplay code | **57** modules, **12 222** lines, layers L0–L5 |
| Verification level claimed | **L3.5 — runs in a real Luau VM** (doc 09 §4). Not L4: no Roblox engine was involved |

## Validation snapshot — end of iteration 3

Full command output is pasted in [`HANDOFF.md`](HANDOFF.md) §2.

| Check | Real output |
| --- | --- |
| `tidekeeper-quality-gate.js` | **11/11** checks passed |
| `tidekeeper-doc-gate.js` | **159/159** checks passed |
| `check-syntax.js` | all **48** Luau files parsed |
| `tidekeeper-determinism-scan.js` | **clean** — 48 files, 10 594 lines, **12** rules, 5 explicit allowances |
| `tidekeeper-smoke-test.js` | **858 passed, 0 failed**, 3/3 static proofs |
| `tidekeeper-session-test.js` | **72 passed, 0 failed** — 14 scenarios against a fake DataModel |
| `find-dead-config.js` | **no dead keys** — the five reserved keys are now consumed or display-only |
| Measured platform cost | **5.64 DataStore / 5.24 MemoryStore requests per session** over 200 sessions, 8 posts, 30 virtual days |
| Gameplay code | 48 modules, 10 546 lines, layers L0–L4 |
| Verification level claimed | **L3 — runs against a simulated platform** (doc 09 §4) |

### Iteration-2 snapshot, kept for the record

| Check | Real output |
| --- | --- |
| `tidekeeper-doc-gate.js` | 148/148 |
| `tidekeeper-quality-gate.js` | 10/11 passed, 1 not applicable yet |
| `check-syntax.js` | all 25 Luau files parsed |
| `tidekeeper-determinism-scan.js` | clean — 25 files, 5 288 lines, 8 rules |
| `tidekeeper-smoke-test.js` | 858 passed, 0 failed |
| Gameplay code | 25 modules, 5 263 lines, layers L0/L2 only |
| Verification level claimed | L2 — executed in a Lua VM outside Roblox |

### Iteration-1 snapshot, kept for the record

| Check | Real output |
| --- | --- |
| `tidekeeper-doc-gate.js` | 137/137 |
| `tidekeeper-quality-gate.js` | 3 pass, 7 N/A, 0 fail |
| Gameplay code | none — deliberately |
| Verification level claimed | none (docs only) |
