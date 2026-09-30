# Handoff — TIDEKEEPER, iteration 1 (2026-09-30 UTC)

Everything in this file was produced by running a command in this repository or by a
web search performed on 2026-09-30. Where a claim is unverified it says so.

---

## 0. Prompt for the next agent

```
You are iteration 2 of the TIDEKEEPER project, a Roblox async cozy-trading game that
lives in `tidekeeper/` in this repository. Iteration 1 produced the complete design;
your job is to implement the pure layers and prove them.

BRANCH: work only on your session's fixed branch. Never switch or create branches.

SEPARATION (hard rule): TIDEKEEPER is a different game from VITRIOL, which lives in
`/code`, `/docs` and `/tools` at the repository root. You may not read, modify,
reference or require anything from the VITRIOL tree, and you may not modify its docs
or tooling. Everything you write goes under `tidekeeper/`.

READ FIRST, in this order:
  tidekeeper/README.md
  tidekeeper/docs/00-VISION.md          pillars, loop, scope, forbidden list
  tidekeeper/docs/01-ARCHITECTURE.md    layering, Explorer tree, cadence, budgets
  tidekeeper/docs/02-TIDE-AND-TIME.md   the shared clock — implement EXACTLY as specified
  tidekeeper/docs/04-SIMULATION-MODEL.md resolve-on-read, determinism rules, test contract
  tidekeeper/docs/06-ECONOMY-PROGRESSION.md standing orders language, economy maths
  tidekeeper/docs/05-PERSISTENCE.md §4-6 wire formats you must encode/decode
  tidekeeper/ROADMAP.md                 open decisions

BUILD (Explorer-first; mirror the tree in `tidekeeper/code/`, one file per module, each
with a header comment stating its Studio path — there is NO Rojo project and you must
not create one):

  L0  ReplicatedStorage/Tidekeeper/Lib/
        Tide      exactly doc 02 §9; pure; no os.time inside; zero allocation in height()
        RNG       seeded, splittable, deterministic; NEVER wrap math.random
        Hash      fixed documented 32-bit mix; it is part of the save format
        MathExt, Tables (pool, sortedPairs, deep freeze), Signal, Codec, Schema
  L2  ReplicatedStorage/Tidekeeper/Domain/
        Post, Drifter, Orders, Visit, Resolve, Ledger, Almanac, Standing
  Shared/
        DrifterCodec, PostCodec, Version      (codecs only; no service access)
  Config/
        GameConfig, TideConfig, EconomyConfig, DrifterConfig, OrdersConfig
        (FindsConfig may be a small representative subset in this iteration — annotate it)

DO NOT BUILD: any service, adapter, remote, client code, DataStore/MemoryStore call, or
anything that yields. No Instance access anywhere. No `game`, no services, no os.time()
in L0/L2 — time is always an argument.

DETERMINISM IS THE POINT. Re-read doc 04 §5 and obey every rule. In particular:
  - no math.random anywhere
  - no pairs() iteration where order affects output
  - all money and stock are integers
  - Visit.resolve arrival order sorted by Hash.mix(drifterId, epoch)

TEST HARNESS: create `tidekeeper/tools/tidekeeper-smoke-test.js` following the pattern of
the sibling project's harness (fengari Lua VM loading the REAL modules — read
`tools/vitriol-smoke-test.js` as a reference implementation only; do not import it).
The gate at `tidekeeper/tools/tidekeeper-quality-gate.js` already expects it and will
start failing as soon as you add a Luau file, which is intentional.

REQUIRED ASSERTIONS (doc 04 §8): >= 300 total, including all 12 tide vectors from
doc 02 §8 and both determinism proofs from doc 04 §5.1. Also assert every economy
invariant in doc 04 §9 that is provable without persistence.

ALSO ADD: `tidekeeper/tools/tidekeeper-determinism-scan.js` per tools/README §5.

BENCHMARK and report: median and p99 wall time of Visit.resolve, and allocation count
in the steady path. Budget is 18 us median (doc 04 §6). If you miss it, say so and say
by how much — do not quietly move the budget.

BEFORE SAYING DONE, run and paste the REAL output of:
  node tidekeeper/tools/tidekeeper-smoke-test.js
  node tidekeeper/tools/check-syntax.js tidekeeper/code
  node tidekeeper/tools/metrics.js --src tidekeeper/code
  node tidekeeper/tools/hot-loop-scan.js --src tidekeeper/code
  node tidekeeper/tools/call-graph.js --src tidekeeper/code
  node tidekeeper/tools/find-dead-config.js --src tidekeeper/code
  node tidekeeper/tools/tidekeeper-quality-gate.js

Claim verification level L2 and nothing higher (doc 09 §4). You have no Studio and no
engine; do not claim buffer behaviour, DataStore behaviour, or performance on real
hardware.

FINALLY: update tidekeeper/ROADMAP.md honestly, and rewrite tidekeeper/HANDOFF.md using
the template in docs/12-ITERATION-PROMPTS.md, including the copy-paste prompt for
iteration 3. If you run low on budget, commit the honest partial result and write the
handoff rather than claiming completion.
```

---

## 1. Verification level claimed

**None.** This iteration produced documentation and tooling, not code. Nothing here has
been executed inside the Roblox engine and no gameplay behaviour has been demonstrated.
The verification ladder in [`docs/09-AI-BUILD-PIPELINE.md`](docs/09-AI-BUILD-PIPELINE.md)
§4 starts at L1 in iteration 2.

What *has* been verified is the internal consistency of the design, by a tool that can
fail — see §2.

---

## 2. What is actually true

Real, pasted output.

```
$ node tidekeeper/tools/tidekeeper-doc-gate.js
note: checked 38 relative Markdown links
note: tide: epoch=22357s, spring=26.8, neap=13.2, beat=14.767d, cap=6.99d
note: checked 5 iteration prompts
TIDEKEEPER doc gate: 137/137 checks passed
```

```
$ node tidekeeper/tools/tidekeeper-quality-gate.js
TIDEKEEPER quality gate — source root tidekeeper/code (0 Luau file(s))

  ok  doc-gate           TIDEKEEPER doc gate: 137/137 checks passed
  ok  separation         no dependency on the VITRIOL tree
 skip check-syntax       no Luau source under the source root yet
 skip metrics            no Luau source under the source root yet
 skip hot-loop-scan      no Luau source under the source root yet
 skip call-graph         no Luau source under the source root yet
 skip find-dead-config   no Luau source under the source root yet
 wait smoke-test         tidekeeper-smoke-test.js not present yet (expected in iteration 2).
 wait session-test       tidekeeper-session-test.js not present yet (expected in iteration 3).
  ok  git-diff-check

TIDEKEEPER quality gate: 3/10 checks passed, 7 not applicable yet
```

The doc gate independently recomputes the tide arithmetic from the constants table
rather than trusting the prose, and it checks that the Drifter byte layout is contiguous
and totals 68 bytes. It found four real errors in the drafts (see §5).

---

## 3. What was built

```
tidekeeper/
  README.md                       entry point, separation contract, the three findings
  ROADMAP.md                      iteration tracker + 11 open decisions with owners
  HANDOFF.md                      this file
  code/README.md                  the Explorer-tree contract; no code yet, by design
  docs/00-VISION.md               pitch, 5 pillars, core loop, progression, scope, titles
  docs/01-ARCHITECTURE.md         4 layers, full Explorer tree, authority table,
                                  7 remotes, 5 cadence slots, budgets, failure policy
  docs/02-TIDE-AND-TIME.md        3-harmonic tide, exact constants, 5 states, epochs,
                                  forward search, trust boundary, 12 test vectors
  docs/03-ASYNC-SOCIAL.md         the Drifter Exchange: 68-byte record, 4 classes,
                                  8-axis taste, two-tier storage, receipts, fairness,
                                  liquidity targets, notifications, the Chart
  docs/04-SIMULATION-MODEL.md     resolve-on-read, the epoch step, Visit.resolve,
                                  prose generation, 10 determinism rules, chunking,
                                  7 economy invariants, migration, offline play
  docs/05-PERSISTENCE.md          12 platform limits, key map, 6 KB post budget,
                                  wire formats, session locking, retries, reaping
  docs/06-ECONOMY-PROGRESSION.md  3 currencies, 5 Currents, pricing, passive caps,
                                  the standing-order language, 200 finds, pacing table
  docs/07-WORLD-AND-CONTENT.md    island, 4 zones, the Bar, content inventory,
                                  art direction, audio, seasons
  docs/08-CLIENT-UX-MOBILE.md     6 screens, the first 60 seconds, the Ledger,
                                  mobile rules, RDC 2026 UI usage, accessibility
  docs/09-AI-BUILD-PIPELINE.md    2026 survey of Roblox generative/vibe-coding AI,
                                  per-iteration usage, 7 rules, the verification ladder
  docs/10-RESEARCH-NOTES.md       40+ sourced facts with confidence levels,
                                  the three findings, 8 known unknowns
  docs/11-HUMAN-AUTHORED.md       briefs for island, water, audio, meshes, prose,
                                  the R1 playtest, the Studio-only checklist
  docs/12-ITERATION-PROMPTS.md    full prompts for it2–it6+, handoff template, 10 rules
  docs/13-RISKS-AND-COMPLIANCE.md 3 risk-removing decisions, safety table,
                                  15-risk register, monetisation, pre-launch checklist
  tools/tidekeeper-doc-gate.js    NEW — validates the design documents
  tools/tidekeeper-quality-gate.js NEW — the single gate; degrades honestly
  tools/README.md                 what is here, what it2/it3 must add
  tools/package.json
  tools/{check-syntax,metrics,call-graph,hot-loop-scan,find-dead-config}.js
  tools/lib/{paths,luau,luau-transform,evaluate}.js
  tools/{selene,stylua}.toml
```

**No `.luau` file exists anywhere under `tidekeeper/`.** That was the agreed scope.

---

## 4. Decisions taken

| # | Decision | Reasoning | Documented in |
| --- | --- | --- | --- |
| 1 | The game is an **async cozy trading sim** with a real-clock tide | Attacks the cold-start failure mode structurally, and is the flagship use of the async-notification system Roblox ships in Oct 2026 | 00 §4 |
| 2 | **Every visitor is a real player, delayed** | The one mechanic no other Roblox game has; makes a 3-CCU server feel populated | 03 §1–2 |
| 3 | The tide is a **pure function of UTC time**, never stored or replicated | Zero bytes, zero remotes, and it makes offline replay and exact notification scheduling possible | 02 §1 |
| 4 | **Resolve-on-read**, never simulate an absent player | Cost scales with sessions, not population × time; Luau Execution cannot do the alternative | 04 §1 |
| 5 | MemoryStore holds an **index only**; the Drifter pool is in DataStore | The quota is `64 KB + 1.2 KB × users` universe-wide — ~1.2 MB at 1 000 CCU | 03 §6, 10 §3 |
| 6 | Drifter = **68 bytes**, Receipt = 28 bytes, post blob ≤ 6 KB | Everything downstream is sized from these | 05 §3–5 |
| 7 | **No paid random items, ever** | Removes the entire regulated-monetisation surface of Roblox's May 2026 clarification | 13 §1 D1 |
| 8 | **No free text anywhere**; letters are fixed phrases | The dominant safety risk in a player-contact game | 13 §1 D2, 08 §9 |
| 9 | **No Robux-for-item peer trading**; barter is a claim, not a transfer | ToS compliance, and it removes the duplication exploit class | 13 §1 D2, 03 §9 |
| 10 | `PolicyService` wired from day one anyway | ~30 lines now; expensive to retrofit | 13 §1 D3 |
| 11 | Standing decays to a **band floor**, never to zero | Absence must never erase an achievement; returning players are the most valuable | 06 §2 |
| 12 | Offline Drifter cache lives in a **second DataStore key**, not the post blob | Keeps the hot path at ~3.1 KB and one request | 05 §3 |
| 13 | Ledger prose is **template + slots**, never runtime-LLM | Determinism, offline play, cost, moderation, and it is translatable without a migration | 04 §4.1, 09 §3 |
| 14 | **12-player servers** | Async presence means a small server costs nothing socially and buys a lot of performance | 07 §1 |
| 15 | Tooling is **forked**, not shared, with the sibling project | Two games must be able to change their gates independently | tools/README |
| 16 | Iterations 2–3 use **no Studio and no generative asset tooling** | Those tools are strong at assets and weak at systems; front-load systems | 09 §2 |
| 17 | Shipping title deferred to it5 | It is a live-search-data decision, not a taste decision | 00 §10, OD1 |

---

## 5. Where the docs were wrong

The doc gate caught four real errors in the drafts. All are fixed; they are recorded
because they are evidence the gate is worth running.

1. **Warm shard size was wrong.** The draft stated 13.6 KB for 200 × 68 B. The real
   figure is 13.3 KB (13 600 bytes). The downstream "live pool" figure was corrected
   from ~8.7 MB to ~8.5 MB. Cause: dividing bytes by 1 000 instead of 1 024 in one place
   and not the other.
2. **A broken cross-document link** — `docs/00-VISION.md` linked to `../ROADMAP.md`
   before `tidekeeper/ROADMAP.md` existed, which would have resolved to the *VITRIOL*
   roadmap. Exactly the kind of accidental coupling the separation rule exists to stop.
3. **The iteration 6+ prompt omitted the branch and separation rules.** Every other
   prompt had them. Added.
4. **A stray non-ASCII character** ("synodic半") in `02-TIDE-AND-TIME.md` §2, from a
   drafting slip.

Two further things worth flagging to iteration 2:

5. **The 27-epoch catch-up cap is 6.99 days, not exactly 7.** `27 × 22 357 s = 603 639 s`.
   The docs say "≈ 7 days" and the gate tolerates ≥ 6.9 d. Do not "fix" this by changing
   the epoch length — the epoch is `T_M2 / 2` and that is load-bearing. If a full 7 days
   is ever required, the cap becomes 28.
6. **The spring/neap beat computes to 14.767 days**, not the 14.765 quoted from the real
   -world figure. The gate tolerates ±0.02 d. The difference is because `T_M2` is
   rounded to whole seconds. Harmless; documented here so nobody "corrects" it later.

---

## 6. What is NOT verified

Explicitly, so no later iteration mistakes this document for evidence.

- **No Luau has been written, parsed, or executed.** Every module signature in the docs
  is a specification, not an implementation.
- **No Roblox engine behaviour.** In particular: `buffer` + base64 round-tripping a 6 KB
  blob through a real DataStore, real MemoryStore `UpdateAsync` contention, real
  `BindToClose` timing, and whether the RDC 2026 orthographic camera and UI blur behave
  as announced.
- **The 18 µs `Visit.resolve` budget is an estimate**, not a measurement.
- **The exact API of the async-notification system is unknown.** It entered Studio Beta
  in October 2026 and this design was written from the announcement, not from shipped
  documentation. **Iteration 3's first task is to verify it.**
- **Whether the concept is fun.** Risk R1. The Ledger has not been in front of a human.
  This is the largest unmitigated risk in the project and iteration 4 owns it.
- **Market figures** in `docs/10-RESEARCH-NOTES.md` §4 are mostly secondary reporting and
  are marked 🟡. The retention benchmarks in 4.8 are a single developer's anecdote,
  directionally useful and not authoritative.
- **Whether MemoryStore keys count toward the memory quota.** DevForum consensus says no
  for sorted maps; it is unverified, and the design is sized as though they do.

---

## 7. Open questions handed forward

| # | Question | Recommendation | Owner |
| --- | --- | --- | --- |
| Q1 | Does the shipped async-notification API match the announcement? | **Verify before writing NotifyService.** Design for 1/day/user regardless; the game must be fully playable with notifications off. | it3 |
| Q2 | Is `Visit.resolve` really ≤ 18 µs in Luau? | Benchmark in it2 headlessly, then confirm in-engine with MCP `execute_luau` in it4. If it is 3× over, chunk to 2 epochs/tick rather than cutting features. | it2/it4 |
| Q3 | Does the Ledger land emotionally? (R1) | Prototype it *before* building it5's content. Five players, ten minutes, unprompted. If nobody mentions a visitor by name, the concept needs rework. | it4 |
| Q4 | Do Echoes read as dishonest when the population is small? (R4, OD4) | Make the Ledger marker prominent and playtest the < 200 DAU case explicitly. Seed Drifters being *characters* is the hedge. | it5 |
| Q5 | Is the standing-order language expressive enough to be interesting, and simple enough for a child? | The live preview panel (doc 06 §5.5) is the mitigation and it is only possible because the resolver is pure. Do not compromise the purity to save time in it2. | it2/it4 |
| Q6 | Geographic or thematic Currents? (OD2) | Thematic, with a geographic bias in shard selection, so timezone overlap improves without fragmenting identity. | it5 |
| Q7 | Will the DataStore shared request budget bite during reaping? | Reapers are already rate-limited to one shard per slow tick. Instrument `BudgetMeter` in it3 and watch it. | it3 |
| Q8 | Does Scene Generator ship in time to blockout the island? (OD8) | Assume no. The hand-built contingency in doc 11 §2 is the plan of record. | it5 |

---

## 8. A note on scope discipline

The forbidden list in `docs/01-ARCHITECTURE.md` §10 and `docs/00-VISION.md` §8 is
binding on every iteration: no combat, no real-time co-presence mechanics, no second
scheduler, no client authority, no free text, no paid random items, no Rojo project,
and no reference to the VITRIOL tree.

The failure mode this project is most likely to die of is not technical. It is an
iteration deciding that the async loop would be "better with a bit of real-time
multiplayer". It would not be. The async loop is the entire reason this game exists.
