# 12 — Iteration Prompts

Copy-paste prompts for iterations 2 through 5+, plus the handoff template every
iteration must fill in.

**Branch policy for every iteration:** work only on the fixed branch your session was
started on. Never create, switch to, or push to another branch. If a prompt below
appears to conflict with that, the branch policy wins.

---

## The plan at a glance

| It | Name | Deliverable | Verification level (doc 09 §4) | Exit criterion |
| --- | --- | --- | --- | --- |
| 1 | **Research & design** ✅ | 14 docs, tooling fork, prompts | — | This folder |
| 2 | **The pure core** | L0 `Lib` + L2 `Domain`, all headless-tested | L2 | ≥ 300 assertions green, determinism proof passes |
| 3 | **The server exists** | L1 adapters, L3 services, exchange, persistence | L3 | Session harness runs a simulated 30-day lifetime with economy invariants green |
| 4 | **It plays** | Client, six screens, Ledger replay, Studio via MCP | L5 | A human plays a full session in Studio; R1 prototype answered |
| 5 | **It ships** | Content, economy tuning, polish, launch checklist | L6 | Pre-launch checklist (doc 13 §6) complete |
| 6+ | **Contingency** | Whatever it5 could not finish; soft-launch telemetry | L7 | Live D1/D7 measured |

Iterations 2 and 3 involve **no Studio and no generative asset tooling**. That is
deliberate: doc 09 §1.3.

---

## Prompt — Iteration 2: the pure core

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
Also create `tidekeeper/tools/tidekeeper-quality-gate.js` per
`tidekeeper/tools/README.md` §4.

REQUIRED ASSERTIONS (doc 04 §8): >= 300 total, including all 12 tide vectors from
doc 02 §8 and both determinism proofs from doc 04 §5.1. Also assert every economy
invariant in doc 04 §9 that is provable without persistence.

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
  node tidekeeper/tools/tidekeeper-quality-gate.js --src tidekeeper/code

Claim verification level L2 and nothing higher. You have no Studio and no engine; do not
claim buffer behaviour, DataStore behaviour, or performance on real hardware.

FINALLY: update tidekeeper/ROADMAP.md honestly, and write tidekeeper/HANDOFF.md using
the template in docs/12-ITERATION-PROMPTS.md, including the copy-paste prompt for
iteration 3. If you run low on budget, commit the honest partial result and write the
handoff rather than claiming completion.
```

---

## Prompt — Iteration 3: the server exists

```
You are iteration 3 of TIDEKEEPER (`tidekeeper/`). Iteration 2 delivered the pure core.
Your job is persistence, the Drifter Exchange, and the server services.

BRANCH: your session's fixed branch only.
SEPARATION: never touch the VITRIOL tree at /code, /docs, /tools.

READ: tidekeeper/HANDOFF.md first, then docs 01, 03, 05, 13, and ROADMAP.md.

FIRST TASK, BEFORE ANY CODE: verify the async notification API. Roblox's turn-based
notification system entered Studio Beta in October 2026 and the creator roadmap listed
Developer Push Notification Support for late 2026 (doc 10 §1.1-1.3). Find the SHIPPED
API surface, write what you found into docs/10-RESEARCH-NOTES.md §6 with a date and a
link, and design NotifyService against reality rather than against the announcement.
The game must remain fully playable with zero notifications.

BUILD:
  L1  ServerStorage/Tidekeeper/Adapters/
        DataStoreAdapter   retry policy doc 05 §8, budget guard, session lock doc 05 §7
        MemoryAdapter      hash map + queue, sharded, quota-aware, degrades never blocks
        NotifyAdapter      per the API you verified
        PolicyAdapter      doc 13 §3 — wire it even though nothing depends on it yet
  L3  ServerStorage/Tidekeeper/Services/
        CadenceService     THE single RunService connection, slots per doc 01 §5
        PlayerService, PostService, ExchangeService, LedgerService,
        NotifyService, ShowcaseService
      ServerStorage/Tidekeeper/Bootstrap
      ServerScriptService/Tidekeeper/Main, RemoteHandlers/*, Diagnostics/*
      ReplicatedStorage/Tidekeeper/Shared/Remotes, NetContract

  Plus: the in-memory fake persistence layer described in doc 05 §11, with injected
  failures, DataUpdateConflict simulation, quota exhaustion, budget starvation and
  two-server lock contention.

HARD RULES:
  - Exactly one RunService connection in the entire game, in CadenceService.
  - No task.spawn / task.wait / task.delay in gameplay code.
  - Only adapters may yield. Only adapters may touch DataStore/MemoryStore/Http.
  - Remotes are created in exactly one file and validated by NetContract.
  - No remote accepts free text (doc 13 §2).
  - Resolve runs chunked, <= 4 epochs/tick, <= 27 epochs total (doc 01 §5).

BUILD `tidekeeper/tools/tidekeeper-session-test.js`: boot the server against a virtual
DataModel and the fake stores, and run a SIMULATED 30-DAY, 200-SESSION LIFETIME across
at least 8 posts exchanging real Drifters. Assert every economy invariant in doc 04 §9
at every step. This test is the point of the iteration.

REPORT the measured request cost per session against the budget in doc 03 §6.3
(target: 5 requests/session) and the measured MemoryStore footprint against doc 05 §1.

Claim L3. Do not claim real DataStore or MemoryStore behaviour.

Update ROADMAP.md, rewrite HANDOFF.md, and write the iteration 4 prompt.
```

---

## Prompt — Iteration 4: it plays

```
You are iteration 4 of TIDEKEEPER (`tidekeeper/`). The server works headlessly. Your job
is the client, the six screens, and the first contact with Roblox Studio.

BRANCH: your session's fixed branch only.
SEPARATION: never touch the VITRIOL tree.

READ: tidekeeper/HANDOFF.md, then docs 08 (client/UX), 07 (world), 03 §11 (the Chart),
04 §7 (Ledger as replay), 09 §2 (how to use Studio MCP), 11 (what humans must do).

BUILD:
  StarterPlayer/StarterPlayerScripts/Tidekeeper/
      ClientMain
      Controllers/  TideController, LedgerController, PostController,
                    CombController, ChartController, DispatchController
      UI/Screens/   World, Ledger, Post, Orders, Chart, Almanac
      UI/Components/

  Plus: the Ledger replay must re-run the REAL Visit.resolve from ReplicatedStorage.
  Do not reimplement it. If that is awkward, the layering is wrong — fix the layering.

  Plus: >= 40 Ledger prose templates so the template+slot system is genuinely exercised.
  Plus: the UIConfig feature flags and fallback paths for the RDC 2026 UI betas
        (orthographic camera, blur, text shadows, sprite sheets) — doc 08 §5.

STUDIO, VIA MCP: connect to a Studio instance (Assistant -> ... -> Manage MCP Servers ->
Enable Studio as MCP server; see doc 10 §2.6). Then:
  1. Script the construction of the Explorer tree from tidekeeper/code/. Do not hand-place.
  2. Use execute_luau to verify, against the REAL engine:
       - buffer + base64 round-trip of a 6 KB post blob through a real DataStore
       - a MemoryStore HashMap UpdateAsync
       - Tide.height per-frame cost
  3. Run a playtest. Capture console output and screenshots of the Ledger and Chart.
  4. Iterate the UI against screenshots at phone resolution.
Paste transcripts and attach screenshots in the handoff. Without them you are at L3.

THE MOST IMPORTANT TASK IN THIS ITERATION IS NOT CODE. It is R1 (doc 13 §3): get the
Ledger replay in front of five real humans for ten minutes each and find out whether
anyone mentions a visitor by name afterwards. Write down what happened, honestly,
including if it went badly. Doc 11 §7 is the brief. If the concept does not land, say so
loudly — that is a cheap discovery now and a ruinous one after iteration 5.

Claim L5 only if you actually ran a playtest; L6 only if a human actually played.

Update ROADMAP.md, rewrite HANDOFF.md, write the iteration 5 prompt.
```

---

## Prompt — Iteration 5: it ships

```
You are iteration 5 of TIDEKEEPER (`tidekeeper/`). It plays. Your job is to make it good
and get it ready to publish.

BRANCH: your session's fixed branch only.
SEPARATION: never touch the VITRIOL tree.

READ: tidekeeper/HANDOFF.md, then docs 06 (economy), 07 (content), 09 §2 (asset
pipeline), 11 (human-authored), 13 (compliance + pre-launch checklist).

DELIVER:
  1. CONTENT
     - 200 finds via the pipeline in doc 09 §2, with the human curation gate. Expect to
       reject ~35%. Record every generated asset's source and licence in
       tidekeeper/docs/ASSETS.md.
     - 180 Ledger prose templates, 120 fixed-phrase letters, 64 Seed Drifter characters,
       90 decor pieces, 4 post tier structures, 40 badges.
     - Contingency: if Scene Generator has not shipped, build the island by hand per
       doc 11 §2. Do not block on an unreleased tool.
  2. ECONOMY TUNING
     - Run the 30-day simulated lifetime at 8 different play patterns (daily 5 min,
       daily 20 min, twice-weekly, lapsed-and-returned, whale, non-payer, tier-rusher,
       pure-idler) and tune the curves in doc 06 §7 against the result.
     - Prove the pacing targets or change them, with the reasoning written down.
  3. THE COLD-START CASE
     - Explicitly playtest at < 200 DAU with the echo/seed mix (doc 03 §8). This is R4.
  4. DISCOVERY (R8)
     - Choose the shipping title against live Roblox search data (doc 00 §10).
     - Produce the thumbnail from the Chart screen. Produce 3 Moments-format clips of
       the Ledger replay.
  5. LAUNCH
     - Complete every item in doc 13 §6. Do not tick a box you did not verify.
     - Telemetry for D1, D7, first-30-seconds churn, session length, and the
       live/echo/seed Drifter mix.
     - Soft-launch region and rollback plan.

Claim L6. L7 requires live telemetry and belongs to iteration 6+.

If you cannot finish, prioritise in this order: cold-start playtest > economy tuning >
compliance checklist > content volume > polish. Ship 120 well-curated finds rather than
200 mediocre ones.

Update ROADMAP.md, rewrite HANDOFF.md, write the iteration 6 prompt.
```

---

## Prompt — Iteration 6+: contingency and live

```
You are iteration 6 (or later) of TIDEKEEPER. Read tidekeeper/HANDOFF.md and
tidekeeper/ROADMAP.md first; they, not this template, define your scope.

BRANCH: work only on your session's fixed branch; never switch or create branches.
SEPARATION: TIDEKEEPER lives entirely in `tidekeeper/`. Never read, modify or reference
the VITRIOL tree at /code, /docs, /tools.

Default priorities, highest first:
  1. Anything iteration 5 marked incomplete or unverified.
  2. Live telemetry: measure D1, D7, first-30-seconds churn, and the live/echo/seed
     Drifter mix. Compare against the targets in doc 06 §8 and write down the delta.
  3. R1 revisited with real players rather than playtesters.
  4. The idea bank in doc 00 §9, in this order: Storms, Salvage wrecks, the Chart
     puzzle. Do not start one until the live numbers say the core loop holds.
  5. Offline solo play (doc 04 §11) once the platform feature reaches early access.

Do not add: combat, real-time co-presence mechanics, paid random items, free text,
Robux-for-item trading, or a second scheduler. Doc 01 §10 and doc 00 §8 remain binding
forever.
```

---

## The handoff template

Every iteration must leave `tidekeeper/HANDOFF.md` in this shape. The sibling project's
history shows why: the expensive failures were all cases where a document claimed
something the code did not do.

```markdown
# Handoff — TIDEKEEPER, iteration N (YYYY-MM-DD UTC)

## 0. Prompt for the next agent
<the full copy-paste prompt>

## 1. Verification level claimed
L<n> — <one line justifying it against docs/09-AI-BUILD-PIPELINE.md §4>

## 2. What is actually true
| Check | Real pasted output |
| --- | --- |
...

## 3. What was built
<files, with their Studio paths>

## 4. Decisions taken
<each with its reasoning, and a pointer to where it is now documented>

## 5. Where the docs were wrong
<the design said X, the implementation found Y, the doc has been corrected>
This section must not be empty. If it is, you did not read the docs closely enough.

## 6. What is NOT verified
<explicit list — Studio behaviour, real stores, performance on hardware, feel>

## 7. Open questions handed forward
<with a recommendation for each>
```

## Rules that bind every iteration

Restated here so no prompt has to be long.

1. Never touch the VITRIOL tree (`/code`, `/docs`, `/tools`, `/README.md`, `/ROADMAP.md`,
   `/HANDOFF.md`). TIDEKEEPER lives entirely in `tidekeeper/`.
2. Work only on your session's fixed branch.
3. No Rojo project, ever.
4. Explorer-first: every file states its Studio path in a header comment.
5. One scheduler. No `task.spawn`/`wait`/`delay` in gameplay code.
6. Determinism rules (doc 04 §5) are not negotiable.
7. No config key without a reader or a `@future` annotation.
8. No free text, no paid random items, no Robux-for-item trading.
9. Paste real tool output. Never paraphrase it.
10. A partial honest result beats a complete claimed one. Always.
