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

> **Rewritten at the end of iteration 4.** The original version of this prompt assumed
> iteration 4 had reached Studio and could start iteration 5 on content. It did not —
> no Roblox Studio is reachable from this environment (three iterations running). So
> iteration 5 inherits both the engine work and the content work, and the first job is
> to find out which half is actually possible.

```
You are iteration 5 of TIDEKEEPER (`tidekeeper/`). It plays in simulation: 57 modules,
1005 assertions, 0 failures, 12/12 quality gate. Nothing has ever run inside Roblox.

BRANCH: your session's fixed branch only.
SEPARATION: never touch the VITRIOL tree (/code, /docs, /tools and the three root .md
files belong to the other game).

READ FIRST, IN THIS ORDER:
  tidekeeper/HANDOFF.md            -- especially section 3 (what is NOT verified) and
                                      section 5 (D23-D30, and three real bugs)
  tidekeeper/docs/10-RESEARCH-NOTES.md section 7
  tidekeeper/ROADMAP.md            -- open decisions OD1-OD18

STEP 0 -- TRIAGE, BEFORE YOU PLAN ANYTHING.
Answer these three, with evidence, and write the answers into the handoff:
  a) Is a Roblox Studio process reachable? Try an MCP server (doc 10 section 7.3 lists
     several, 14 to 68 tools). If yes, L4 and L5 are both reachable this session and
     they outrank everything else below.
  b) Can you reach github.com release assets? If yes, install Lute (OD17). If not,
     build the luau CLI from source -- four minutes, tidekeeper/tools/bin/README.md.
  c) Re-check ExperienceNotificationService. It has been "coming" since RDC 2026 and
     has been checked and found absent in iterations 2, 3 and 4. Check again, record
     the date and the answer, and change nothing if the answer is still no.
Do not plan the iteration until step 0 is done. Iterations 2, 3 and 4 each planned
around Studio being available and each had to re-plan.

THEN, IF STUDIO IS REACHABLE (this is the whole ballgame):
  1. Run the pure core under `execute_luau` and diff it against the L3.5 numbers in
     doc 04 section 6.1. Median headroom is only 1.1x, so a slower engine result is a
     real finding and must be reported, not averaged away.
  2. Verify on the engine, not in theory: buffer/base64 round trip, a real DataStore
     write and read of the v1 fixture blob, a real MemoryStore queue, and the cost of
     Tide.height.
  3. RUN THE CLIENT. Main.client.luau builds real UI and has never executed. It is the
     largest untested surface in the project. Expect it to be broken. Playtest, capture
     console output and screenshots, and fix.
  4. Claim L4, then L5, with transcripts pasted in.

IF STUDIO IS NOT REACHABLE, do not fake it and do not spend the iteration trying.
Say so in one line and do this instead:
  1. OD17 -- move pure-tests.lua onto a real Luau runner. The fengari harness needs
     floatifyNumbers, a bit32 shim and a %d->%.0f rewrite to work at all
     (tools/README.md section 5b), and every one of those is a place the harness can
     disagree with the shipping game. Deleting them is worth more than new features.
  2. Build a headless render test: drive ClientBootstrap through a whole session and
     assert on the view-model tables. The views are pure (D25) so this needs no engine.
  3. Content, per the list below.

CONTENT (do this in either branch of the above):
  - 200 finds via the pipeline in doc 09 section 2, with the human curation gate.
    Expect to reject about 35%. Record every generated asset's source and licence in
    tidekeeper/docs/ASSETS.md.
  - 180 Ledger prose templates, 120 fixed-phrase letters, 64 Seed Drifter characters,
    90 decor pieces, 4 post tier structures, 40 badges.
  - Every new template MUST be added to scenario 15's SAMPLE table in the same commit.
    The test fails on an id with no prose AND on prose with no id, in both directions.
  - Directives do not nest: `{plural:1|one boat|{1} boats}` is a bug, not a feature
    (doc 08 section 8.1).
  - Contingency: if Scene Generator has not shipped, build the island by hand per
    doc 11 section 2. Do not block on an unreleased tool.

ECONOMY TUNING:
  - Run the 30-day simulated lifetime at 8 play patterns (daily 5 min, daily 20 min,
    twice-weekly, lapsed-and-returned, whale, non-payer, tier-rusher, pure-idler) and
    tune the curves in doc 06 section 7 against the result.
  - Settle OD14. The lean is NO -- keep warmth prose-only. Wiring it into price makes
    warmth a stat to farm and turns every visitor into an optimisation problem, which
    inverts the pillars in doc 00. Overturn it only with playtest evidence.

COLD START (R4) and DISCOVERY (R8): unchanged -- playtest below 200 DAU with the
echo/seed mix (doc 03 section 8); choose the shipping title against live Roblox search
data; thumbnail from the Chart screen; 3 Moments-format clips of the Ledger replay.

LAUNCH: complete every item in doc 13 section 6. Do not tick a box you did not verify.
Telemetry for D1, D7, first-30-seconds churn, session length, and the live/echo/seed
mix. Soft-launch region and rollback plan.

WHAT IRRITATES THE REVIEWER, LEARNED THE HARD WAY:
  - A green check that enforces nothing. Iteration 4's connection counter matched the
    literal identifier `RunService` and so never saw `self.runService.Heartbeat:Connect`
    -- it reported 1/2 for a game with 2. When you write a check, first confirm it
    CATCHES the thing that already exists.
  - Server code producing data nothing reads. slotsFor filled Ledger slots from a
    positional pool for two iterations and rendered a coin amount as an object's name.
    Nothing caught it until a client existed.
  - A sentinel inside the legal range of its field (D28). publishedAt = 0 meant "never"
    in a game where epoch 0 is real, and it broke ALL publishing.

Claim the highest level you have EVIDENCE for and no higher: L3.5 if nothing changed,
L4 with an execute_luau transcript, L5 with a playtest, L6 only if a human played it.
A partial honest result beats a complete claimed one.

Update ROADMAP.md, rewrite HANDOFF.md, write the iteration 6 prompt.
Run: node tidekeeper/tools/tidekeeper-quality-gate.js -- it must be green, and it now
includes the real-Luau benchmark. Paste the real output.
```

---

## Prompt — Iteration 6: content

> **Written at the end of iteration 5.** Iteration 5 took the no-Studio branch and spent
> itself on tooling truth: the correctness suite now runs in real Luau with no shims, and
> the client executed for the first time (and two screens threw). None of the content
> work happened. That is iteration 6's whole job.

```
You are iteration 6 of TIDEKEEPER (`tidekeeper/`). The engineering argument is over.
57 modules, 1055 assertions, 13/13 quality gate, correctness cross-checked in a real
Luau VM. The game has almost no CONTENT, and that is now the only thing that matters.

BRANCH: your session's fixed branch only.
SEPARATION: never touch the VITRIOL tree (/code, /docs, /tools and the three root .md
files belong to the other game).

READ FIRST:
  tidekeeper/HANDOFF.md              -- sections 3, 5 and 6 especially
  tidekeeper/docs/07-WORLD-AND-CONTENT.md
  tidekeeper/docs/06-ECONOMY-PROGRESSION.md
  tidekeeper/docs/11-HUMAN-AUTHORED.md
  tidekeeper/docs/09-AI-BUILD-PIPELINE.md section 2 (the asset pipeline + curation gate)

STEP 0 -- TRIAGE, BEFORE YOU PLAN. Three questions, answered with EVIDENCE:
  a) Is a Roblox Studio process reachable? Check for a process, a DISPLAY, a listening
     MCP port, and rojo/lune/lute on PATH. WARNING: `pgrep -af "roblox|studio"` matches
     its own command line -- iteration 5 nearly planned around a Studio that did not
     exist. Confirm any positive a second way.
     If yes: L4, L5 and R1 unlock in one session and they outrank everything below.
  b) Can you reach github.com RELEASE ASSETS (not just api.github.com)? If not, build
     the luau CLI from source -- four minutes, tidekeeper/tools/bin/README.md.
  c) Re-check ExperienceNotificationService. Absent in iterations 2, 3, 4 and 5. Record
     the date and the answer; change nothing if it is still absent.

THEN RESTORE THE ENVIRONMENT (both are gitignored and vanish on a clean checkout):
  cd tidekeeper/tools && npm install
  # plus the luau binary, per tools/bin/README.md
Without them the gate reports 11/13 with 2 skips. That is correct output, not a pass.

DELIVER, IN THIS ORDER:

1. ASSUME Main.client.luau IS BROKEN.
   It is the only file that has never executed, and two of the six PURE client modules
   threw on their first run. Read it line by line against the view-model contract that
   scenario 16 asserts. Every field it reads must be one a view actually returns.
   You cannot run it without Studio -- so make the failure impossible to hide: extend
   the determinism scan or write a static check that every `model.x` it touches exists
   in the corresponding view's return table.

2. CONTENT. This is the bulk of the iteration.
   - 200 finds via the pipeline in doc 09 section 2, with the human curation gate.
     Expect to reject about 35%. Record every generated asset's source and licence in
     tidekeeper/docs/ASSETS.md.
   - 180 Ledger prose templates, 120 fixed-phrase letters, 64 Seed Drifter characters,
     90 decor pieces, 4 post tier structures, 40 badges.
   - Contingency: if Scene Generator has not shipped, build the island by hand per
     doc 11 section 2. Do not block on an unreleased tool.

   THE CONTENT RULES THAT ARE ALREADY ENFORCED -- read them before writing a line:
   - Every new template id MUST get prose AND an entry in scenario 15's SAMPLE table,
     in the same commit. The test fails on an id with no prose and on prose with no id,
     in BOTH directions.
   - Slot values in SAMPLE must be SEMANTICALLY VALID, not arbitrary integers. An
     earlier version used `(k + variant) % 7 + 1` and produced tide code 6, which does
     not exist, and the suite then failed for a reason unrelated to the game.
   - Directives DO NOT NEST. `{plural:1|one boat|{1} boats}` leaks literal braces to
     the player (doc 08 section 8.1).
   - No sentence is ever stored or replicated (D26). Prose lives in Client/Strings.luau
     and nowhere else.
   - Variants are chosen by hash(actorId, epoch), never randomly (D27).

3. ECONOMY TUNING.
   - Run the 30-day simulated lifetime at 8 play patterns (daily 5 min, daily 20 min,
     twice-weekly, lapsed-and-returned, whale, non-payer, tier-rusher, pure-idler) and
     tune the curves in doc 06 section 7 against the result.
   - Settle OD14. The lean is NO -- keep warmth prose-only. Wiring it into price makes
     warmth a stat to farm and turns every visitor into an optimisation problem, which
     inverts the pillars in doc 00. Overturn it only with playtest evidence.

4. ONLY IF STUDIO IS REACHABLE: run the pure core under execute_luau and diff against
   the L3.5 numbers in doc 04 section 6.1 (median headroom is only 1.1x, so a slower
   engine result is a real finding, not noise); verify buffer/base64, a real DataStore
   write/read of the v1 fixture, a real MemoryStore queue; then RUN THE CLIENT, playtest,
   capture console output and screenshots. Claim L4, then L5, with transcripts pasted in.

WHAT THIS PROJECT HAS LEARNED THE HARD WAY -- do not repeat any of these:
  - check-syntax PARSES, it does not EXECUTE. OrdersView was syntactically perfect,
    passed a 13-rule scan, and threw at load time on a table that never existed.
  - A green check that enforces nothing is worse than no check. The connection counter
    matched the literal identifier `RunService` and never saw
    `self.runService.Heartbeat:Connect` -- it reported 1/2 for a game with 2. When you
    write a check, first confirm it CATCHES the thing that already exists.
  - One name must not mean two things (D28). `publishedAt = 0` meant "never" in a game
    where epoch 0 is real. `shelves` meant an array in the domain and a count on the
    wire. Both shipped. Both broke something silently.
  - Server code producing data nothing reads is untested code wearing a passing suite.
  - A check can observe itself. See the pgrep note in step 0(a).

Claim the highest level you have EVIDENCE for and no higher: L3.5 if nothing changed,
L4 with an execute_luau transcript, L5 with a playtest, L6 only if a human played it.
A partial honest result beats a complete claimed one -- say what you did not do.

Run `node tidekeeper/tools/tidekeeper-quality-gate.js`; it must be green. Paste the
real output. Update ROADMAP.md, rewrite HANDOFF.md, write the iteration 7 prompt.
```

---

## Prompt — Iteration 7: the rest of the content, and the economy it feeds

```text
You are iteration 7 of TIDEKEEPER (`tidekeeper/`). Iteration 6 found that the game
was 100% non-functional for every player -- `Main.client.luau` looked up the seven
remotes under `ReplicatedStorage/Tidekeeper` while `Remotes.build` parents them
under the sibling `ReplicatedStorage/TidekeeperRemotes`, so every lookup returned
nil and every session answered "offline". It is fixed. All 14 gate checks were
green the entire time it was broken. Internalise that before you trust the gate.

Work on branch `arena/01a0f2ee-vitriol` only. Never touch VITRIOL; everything you
write lives under `tidekeeper/`.

FIRST, every time, before planning anything:
  cd /home/user/Vitriol && git fetch && git reset --hard origin/arena/01a0f2ee-vitriol
  cd tidekeeper/tools && npm install
  git clone --depth 1 --branch 0.700 https://github.com/luau-lang/luau /tmp/luau \
    && make -C /tmp/luau config=release luau -j$(nproc) \
    && cp /tmp/luau/luau tidekeeper/tools/bin/luau
The branch is reset to the session base between turns and `node_modules` and
`tools/bin/luau` do not survive. A `MODULE_NOT_FOUND` means you skipped this, not
that something broke. Then run the gate and read it before deciding anything.

Your job is the content that iteration 6 did not do, and the economy it feeds.

1. CONTENT. Doc 07 section 5 is the contract. Done: 200 finds, 180 Ledger
   phrasings. Remaining and owned by you:
     - 120 fixed-phrase letters (policy-reviewed: no free text, ever)
     - 64 Seed Drifters as named characters
     - 40 achievements/badges, config only
   Each one gets a test that pins the COUNT to the doc 07 target, and a validator
   that checks the rows are well formed. Iteration 6 found two assertions still
   pinned to iteration-2 placeholders (24 finds, 40 phrasings) -- content that is
   not pinned to its target can be deleted without turning the gate red.
   Remember Seed Drifters are exempt from at-most-once delivery; their ids recur
   by design.

2. ECONOMY TUNING, now that the find table is 200 rows and not 24. The value
   curve runs from 1 coin in zone 1 to ~500 in zone 4. Nobody has checked what
   that does to progression. Simulate it: how long to tier 2, 3, 4? Does a player
   who only works zone 1 ever get anywhere? Is there a dominant find? Use the
   session harness with many seeds and report distributions, not one run.
   If you change a number, say what the simulation said before and after.

3. OD14 (warmth into price). The standing lean is NO -- wiring warmth into price
   turns warmth into a stat to farm, and the whole point of warmth is that it is
   something you notice rather than optimise. Either close it as "no" with the
   reasoning written down, or produce simulation evidence that changes the lean.
   Do not leave it open a fourth time.

4. OD7, and only this one, is worth re-checking: RDC 2026 promised the turn-based
   notification API in Studio Beta in October 2026, and it is now that window.
   Check `robloxapi.github.io/ref/class/ExperienceNotificationService.html` -- the
   per-version member dump, not the prose docs. If `CreateUserNotificationAsync`
   is back, that is genuine news; write it up. If not, one paragraph and move on.
   The official roadmap page is a 404, not a flake -- do not retry it.
   Do NOT re-fetch the performance/LibMP pages to pad a research section. A note
   saying "reconfirmed, no change" is a way of looking busy.

Honesty rules, unchanged and non-negotiable:
  - Claim L4 only with an execute_luau transcript, L5 with a playtest, L6 only if
    a human played it. Studio has been unreachable for six iterations; if that is
    still true, say so plainly and do not imply otherwise.
  - Paste real tool output. Never paraphrase it.
  - Verify a new check by DELIBERATELY BREAKING something and watching it fail.
    A green check that enforces nothing is worse than no check, and this project
    has shipped three of them.
  - A partial honest result beats a complete claimed one. Say what you did not do.

Run `node tidekeeper/tools/tidekeeper-quality-gate.js`; it must be green. Paste the
real output. Update ROADMAP.md, rewrite HANDOFF.md, write the iteration 8 prompt.
```

---

## Prompt — Iteration 8: make the new systems reachable by a player

```text
You are iteration 8 of TIDEKEEPER (`tidekeeper/`). Read this part twice.

Iteration 7 found FOUR features that were shipped and completely inert, and
all 14 gate checks were green the whole time:
  1. RF_Dispatch: the handler recorded the player's cargo and letter choice
     on the post; ExchangeService read neither. No letter had ever reached a
     player and cargo selection was silently discarded.
  2. Tier promotion did not exist. S.tier was set to 1 at creation and no
     code anywhere ever changed it, so 24-shelf posts, three of the five
     currents, the passive caps and the entire doc 06 progression table
     described a game nobody could play.
  3. Post.setShelf let a client-supplied slot leave a gap, and a gap makes
     the post UNSAVEABLE -- remotely triggerable data loss.
  4. app.logger could be nil while seven handler rejection paths called it
     unconditionally, so every validation failure threw instead of returning
     a status.
Iteration 6 found the same shape (the client looked for remotes in the wrong
folder). The pattern is now established beyond argument: THE BUGS IN THIS
PROJECT LIVE IN THE GAP BETWEEN TWO MODULES THAT ARE EACH INDIVIDUALLY
CORRECT. Spend your first hour looking for another one before you write
anything. Two scans now help: member-scan (a field read but never written)
and dead-write-scan (a field written but never read).

Work on branch `arena/01a0f2ee-vitriol` only. Never touch VITRIOL.

FIRST, every time:
  cd /home/user/Vitriol && git fetch && git reset --hard origin/arena/01a0f2ee-vitriol
  cd tidekeeper/tools && npm install
  git clone --depth 1 --branch 0.700 https://github.com/luau-lang/luau /tmp/luau \
    && make -C /tmp/luau config=release luau -j$(nproc) \
    && cp /tmp/luau/luau tidekeeper/tools/bin/luau
The branch is reset to the session base between turns and node_modules and
tools/bin/luau do not survive. Then run the gate and READ it.

Your job: the systems iteration 7 built are reachable by code but not by a
player. Close that.

1. AWARD THE BADGES. BadgesConfig ships 40 rows and 12 lifetime stats and
   nothing increments a stat or awards anything. Note the design constraint
   in the module header: a badge tests ONE stat against a threshold, and
   that restriction is deliberate -- do not "improve" it into a rules
   engine. The stats are LIFETIME counters, never balances, because doc 06
   section 2 says an achievement is never revoked. They need to persist, so
   this touches PostCodec: that means a SCHEMA_VERSION bump and a migration,
   and Version.migrate already exists for exactly this. Returning nil from
   an UpdateAsync transform ABORTS the write -- this project has shipped
   that bug twice.

2. CLIENT UI for the things that now exist: the upgrade button (RF_Upgrade,
   which has no client caller at all), the letter picker (120 phrases, and
   DispatchView must send the id the player chose), and the letter the
   Ledger receives (LedgerView already carries `letterText`; nothing shows
   it). Remember Main.client.luau was broken for three iterations because no
   test constructs an Instance. That limit has not changed. Anything you
   write in the client layer is unverified by construction -- say so.

3. ECONOMY, if you change any income number: re-run
   `node tidekeeper/tools/tidekeeper-session-test.js --tests tools/tests/economy-sim.lua`
   and update both EconomyConfig's comment and doc 06 section 7. The costs
   there were measured over 12 seeds x 70 days, and promotion COMPOUNDS, so
   a small income change moves tier 4 by a week. pure-tests pins the three
   calibrated numbers so you cannot change them silently.

4. RESEARCH: OD7 is CLOSED (not available for v1, six iterations, confirmed
   against the per-version API dump). Do not re-open it unless
   CreateUserNotificationAsync reappears. Do not pad a research section with
   "reconfirmed, no change".

Honesty rules, unchanged:
  - L4 needs an execute_luau transcript, L5 a playtest, L6 a human. Studio
    has been unreachable for seven iterations; if that is still true, say so
    plainly and do not imply otherwise.
  - Paste real tool output. Never paraphrase it.
  - Verify every new check by DELIBERATELY BREAKING something and watching
    it fail. This project has shipped three checks that enforced nothing.
  - A partial honest result beats a complete claimed one.

Run `node tidekeeper/tools/tidekeeper-quality-gate.js`; it must be green.
Paste the real output. Update ROADMAP.md, rewrite HANDOFF.md, write the
iteration 9 prompt.
```

---

## Prompt — Iteration 9: the player can finally see it

```
You are iteration 9 of TIDEKEEPER, a Roblox game being built inside the
Clovetie/Vitriol repository. Work only on your session's fixed branch. Never
touch the VITRIOL tree: TIDEKEEPER is entirely inside tidekeeper/.

START HERE, IN THIS ORDER.

1.  git fetch && git reset --hard origin/<your branch>. The working tree is
    reset to the session base between turns, so the previous iteration's
    commits exist only on the remote.
2.  cd tidekeeper/tools && npm install
3.  Build Luau 0.700 into tidekeeper/tools/bin/luau (about 3-4 minutes):
      git clone --depth 1 --branch 0.700 https://github.com/luau-lang/luau /tmp/luau
      make -C /tmp/luau config=release luau -j$(nproc)
      cp /tmp/luau/luau tidekeeper/tools/bin/luau
    Without it the gate shows 14 of 16 plus two skips. That is correct, not a
    failure.
4.  node tidekeeper/tools/tidekeeper-quality-gate.js  -- and READ it before
    you write anything. It takes about three minutes.
5.  Read tidekeeper/HANDOFF.md.

THEN, BEFORE YOU BUILD ANYTHING, SPEND THE FIRST HOUR HUNTING DEAD FEATURES.

Iterations 6, 7 and 8 each found features that were shipped and inert, every
time with a fully green gate, every time in the seam between two modules that
were each individually correct. Iteration 8 found four. The scans have climbed
one level each time: member-scan (a field read, never written), dead-write-scan
(written, never read), orphan-scan (a function defined, never called).

So: find the fifth level. Ask what the three scans still cannot see. Some
candidates, none of them checked yet:
  * a remote that is bound but that no client code ever calls;
  * a Ledger template id that no code path can ever produce;
  * a config table whose keys are read but whose VALUES can never matter
    (e.g. a weight that is always multiplied by zero);
  * a branch that is unreachable because an earlier guard subsumes it;
  * a stat that is incremented and never read by any badge, UI or report.
If you find one, write the scan before the fix, and put it in the gate.

YOUR MAIN WORK: THE CLIENT. The server is now well ahead of the client, which
is the imbalance to correct.

  a. RF_Upgrade has NO CALLER. Tier promotion works, is tested, and no player
     can trigger it. Build the client path, including showing the cost and
     refusing clearly when the player cannot pay.
  b. The letter picker and the display of letterText. 120 letters exist and
     nothing shows them.
  c. The Ledger is the surface carrying this game's entire emotional argument
     and it cannot show history: see OD22. loadLedgerPage exists and is called
     by nothing, so every entry past MAX_LEDGER_RESIDENT (200) is archived and
     then unreadable forever. This needs a remote, a pager and a decision on
     how far back to keep.
  d. Close OD21: schedule the pool reaper. Decide WHICH server reaps -- every
     server reaping every shard is a quota fire.

RULES THAT WILL BITE YOU, LEARNED THE EXPENSIVE WAY.

  * Returning nil from an UpdateAsync transform ABORTS the write. That has
    been shipped as a bug twice and used deliberately once (restorePost).
    Know which one you are doing.
  * Badge ids are persisted bit indices. From the first live award onwards,
    only a row's NAME may change -- never its id, stat or threshold.
  * Before changing the save schema, capture a fixture of the OUTGOING version
    first, from the code that still writes it. See tools/fixture-blobs/README.
    Once SCHEMA_VERSION moves, that blob can only be hand-forged, and a forged
    fixture proves nothing.
  * pure-tests.lua has section/notOk but NO ge. session-tests.lua has
    eq/ge/le/ok and no notOk. Check before using one.
  * newServer and settle live in tools/tests/session-prelude.lua. Import them.
  * RF_Upgrade is rate-limited to 1 burst / 3 per minute; advance the clock
    between attempts in tests or you will get E_REJECTED.
  * Post.setShelf refuses slot > #S.shelves + 1. Fill densely or append.
  * Do not paste raw tool output into a fenced block without stripping
    trailing whitespace: git diff --check fails the gate on it.

HONESTY RULES. Studio has been unreachable for eight consecutive iterations;
assume it still is and say so plainly rather than claiming a verification level
you did not reach. Nothing above L3.5 may be claimed without Studio. Paste real
tool output; never paraphrase it. A partial honest result beats a complete
claimed one.

Finish with: a green gate (paste it), ROADMAP.md updated, HANDOFF.md rewritten,
and the iteration 10 prompt written into docs/12-ITERATION-PROMPTS.md.
```

---

## Prompt — Iteration 10: the Ledger remembers, and the contract stops lying

```
You are iteration 10 of TIDEKEEPER, a Roblox game being built inside the
Clovetie/Vitriol repository. Work only on your session's fixed branch. Never
touch the VITRIOL tree: TIDEKEEPER is entirely inside tidekeeper/.

START HERE, IN THIS ORDER.

1.  git fetch && git reset --hard origin/<your branch>. The working tree is
    reset to the session base between turns, so the previous iteration's
    commits exist only on the remote.
2.  cd tidekeeper/tools && npm install
3.  Build Luau 0.700 into tidekeeper/tools/bin/luau (about 3-4 minutes):
      git clone --depth 1 --branch 0.700 https://github.com/luau-lang/luau /tmp/luau
      make -C /tmp/luau config=release luau -j$(nproc)
      cp /tmp/luau/luau tidekeeper/tools/bin/luau
4.  node tidekeeper/tools/tidekeeper-quality-gate.js
    It must print 17/17 before you change anything. If it does not, fixing
    that IS your iteration.
5.  Read tidekeeper/HANDOFF.md, then docs 00, 01, 05 section 9, and 08
    section 8.4. Then read docs/10-RESEARCH-NOTES.md section 12 -- the
    ladder of dead features -- before you plan anything.

WHAT NINE ITERATIONS HAVE TAUGHT THIS PROJECT, AND YOUR FIRST JOB.

Every iteration from 6 to 9 found a feature that was fully built, fully
tested, and dead -- because it was dead in the SEAM between two modules that
were each correct on their own. Nine such features so far. Every one was
green on every check that existed the day before it was found. The scans have
climbed one level each time: a field read but never written; a field written
but never read; a function never called; an allowlist entry gone stale; and
in iteration 9, a REMOTE that one side never spoke -- five of six, which is
to say the client could not perform a single action.

So: BEFORE YOU BUILD ANYTHING, find level six. Ask what kind of dead thing
the five existing scans still cannot see, and write the scan that sees it.
Candidates worth considering, though do not let this list limit you:

  - A config key whose reader exists but is itself never called (find-dead-
    config only proves a textual reader exists).
  - A string in Client/Strings.luau that nothing ever displays -- the
    player-facing equivalent of a dead write.
  - A cadence slot registered by nobody, or a registered job whose body can
    never do work.
  - A table field in a persisted blob that migrates correctly and is read
    by nothing (dead-write-scan only covers S/S2/state/post).
  - A session scenario that asserts only on values it computed itself --
    a test that cannot fail. This one is the most dangerous on the list.

Whatever you pick, prove the scan works with a NEGATIVE CONTROL: break the
real thing on purpose, show the scan failing with exactly the expected
message, restore, show it clean. Paste both runs. A scan that has never been
seen to fail is not evidence. Then wire it into the gate as check 18 with
requiredFrom set to 10.

THEN, THE SCHEDULED WORK, in this order.

  a. Close OD22: ledger history is written and never read back.
     LedgerService:flushPending archives pages with saveLedgerPage;
     loadLedgerPage is called by nothing and no remote asks for history. Every
     entry past MAX_LEDGER_RESIDENT (200) is unreadable forever right now. The
     Ledger carries this game's whole emotional argument -- "absence is
     content" -- so a Ledger that quietly forgets is the worst possible bug
     for the design, not merely a missing feature.
     This needs: a new remote row in NetContract.REMOTES (strict spec, a page
     cursor, no strings, rate-limited like the rest), a server handler, a
     client pager, and a decision on retention -- how far back is kept, and
     what the player sees at the end of history. Write that decision down with
     its reasoning. Note that remote-scan (check 17) will hold you to wiring
     BOTH sides; it has no allowlist, deliberately.

  b. Close OD23: status code 4 means E_COOLDOWN from PostHandler and
     E_ALREADY_OUT from DispatchHandler. ClientBootstrap:statusText currently
     takes the remote name to disambiguate, which works and is a smell. Give
     NetContract one status enum with non-overlapping codes, move both
     handlers onto it, and simplify statusText back to a pure mapping. Keep
     the remote-name parameter only if you can state a reason it is still
     needed.

  c. The screens the new verbs deserve. Iteration 9 gave the client its
     actions; the views behind them are still thin. Check the orphan-scan
     allowlist for the presentation helpers parked there with "blocked on a
     client that does not exist yet" and retire as many as you honestly can.
     When an entry stops being an orphan the scan FAILS on the stale entry --
     that is working as intended, so remove the entry in the same commit.

RULES THAT HAVE NOT CHANGED.

  - Determinism (doc 04 section 5) is not negotiable.
  - No free text over the wire. Ids only. NetContract.hasNoStringFields is
    the proof and it must keep being called.
  - The server owns prices (D46). The client displays, never computes.
  - A client payload builder is validated through the server's own
    NetContract.accept, never round-tripped against itself (D45).
  - Every allowlist entry is verified in both directions (D44).
  - Paste real tool output. Never paraphrase it.
  - A partial honest result beats a complete claimed one. Always.

ON THE BENCH. It is best-of-3 as of iteration 9 and prints every sample.
Contention only ever inflates a measurement, so the minimum is the estimate.
Do NOT raise the 18 us budget to make something pass; if the median genuinely
moves, that is a performance regression and you should find it.

FINISH BY.

  - Running the full gate and pasting it (18/18 if you added the scan).
  - Updating the docs you invalidated, ROADMAP.md, and HANDOFF.md to the
    template in docs/12-ITERATION-PROMPTS.md.
  - Writing the iteration-11 prompt into docs/12-ITERATION-PROMPTS.md and
    extending the doc gate's prompt loop to cover it.
  - Committing and pushing to your branch.
```

## Prompt — Iteration 11: level seven, and the things only Studio can tell us

```
You are iteration 11 of TIDEKEEPER, a Roblox game being built inside the
Clovetie/Vitriol repository. Work only on your session's fixed branch. Never
touch the VITRIOL tree: TIDEKEEPER is entirely inside tidekeeper/.

START HERE, IN THIS ORDER.

1.  git fetch && git reset --hard origin/<your branch>. The working tree is
    reset to the session base between turns, so the previous iteration's
    commits exist only on the remote.
2.  cd tidekeeper/tools && npm install
3.  Build Luau 0.700 into tidekeeper/tools/bin/luau (about 3-4 minutes):
      git clone --depth 1 --branch 0.700 https://github.com/luau-lang/luau /tmp/luau
      make -C /tmp/luau config=release luau -j$(nproc)
      cp /tmp/luau/luau tidekeeper/tools/bin/luau
4.  node tidekeeper/tools/tidekeeper-quality-gate.js
    It must print 18/18 before you change anything. If it does not, fixing
    that IS your iteration.
5.  Read tidekeeper/HANDOFF.md, then docs/10-RESEARCH-NOTES.md sections 12
    and 13 -- the ladder of dead features and what it has cost to find each
    level -- before you plan anything.

YOUR FIRST JOB: LEVEL SEVEN.

Ten iterations; six levels of dead feature; every one green on every check
that existed the day before it was found:

  1  member-scan        a field READ that is never written
  2  dead-write-scan    a field WRITTEN that is never read
  3  orphan-scan        a FUNCTION defined that is never called
  4  orphan-scan (D44)  an ALLOWLIST ENTRY gone stale
  5  remote-scan        a REMOTE one side never speaks
  6  dead-content-scan  a STRING a player can never see

Find level seven before you build anything. The candidate I would bet on,
and could not get to in iteration 10:

  - A TEST THAT CANNOT FAIL. A session scenario that asserts only on values
    it computed itself, or whose assertion is tautological (eq(x, x)), or
    that is inside a conditional that never runs. There are now 554 session
    assertions and 1201 smoke assertions; if even a handful are vacuous, the
    suite's authority is overstated by exactly that much and nobody knows
    which ones. A mutation-style check is the honest version: perturb a
    constant, confirm some test notices. Start with the cheap static form
    (an assertion whose expected value is derived from the same expression
    as the actual) and only then consider mutation.

Others, if you find a better one:
  - A config key whose reader exists but is itself never called.
  - A cadence job registered but whose body can never do work.
  - A persisted blob field that migrates correctly and is read by nothing
    (dead-write-scan only covers S/S2/state/post).
  - A Ledger template that is reachable in code but that no realistic game
    state can actually produce.

Whatever you pick, prove it with a NEGATIVE CONTROL: break the real thing on
purpose, show the scan failing with exactly the expected message, restore,
show it clean. Paste both runs. Then wire it in as check 19 with
requiredFrom 11.

A WARNING FROM ITERATION 10. The dead-content scan was written, and was
wrong within the hour: a refactor in the same commit introduced a lookup
table and the scan called four live labels dead. A scan written against
today's code encodes today's idioms. Before you trust yours, run it against
a deliberately UNUSUAL but legitimate way of writing the same thing.

THEN, THE SCHEDULED WORK.

  a. The screens are real now but thin. ChartView and AlmanacView were born
     in iteration 10 and have no interaction -- the almanac pages but nothing
     calls AlmanacView with page 2, and the chart shows locks but cannot be
     used to choose a current. Check the orphan allowlist for presentation
     helpers still parked there and retire what you honestly can. Remember
     that when an entry stops being an orphan the scan FAILS on the stale
     entry: that is D44 working, so remove the entry in the same commit.

  b. OD15 is the oldest open question: is base64 packing still paying for
     itself, given DataStore compresses values itself? It is cheap to
     answer now -- the fixtures exist, the codec is pure, and you can
     measure it in the Luau harness rather than guessing. Close it either
     way, with numbers.

  c. Look hard at the dispatch and letters path end to end. Iteration 7 gave
     drifters 120 letters, iteration 9 gave the client a letter picker, and
     iteration 10 found that the screen had been offering a superseded
     12-line phrase table the whole time. That area has produced a defect in
     three consecutive iterations. Read it as a whole rather than trusting
     that the last fix finished the job.

RULES THAT HAVE NOT CHANGED.

  - Determinism (doc 04 section 5) is not negotiable.
  - No free text over the wire. Ids only. NetContract.hasNoStringFields is
    the proof and it must keep being called.
  - The server owns prices (D46). The client displays, never computes.
  - A client payload builder is validated through the server's own
    NetContract.accept, never round-tripped against itself (D45).
  - Every allowlist entry is verified in both directions (D44).
  - Content is reachable or it does not exist (D48).
  - Paste real tool output. Never paraphrase it.
  - A partial honest result beats a complete claimed one. Always.

ON THE BENCH. Best-of-3, every sample printed. Contention only inflates, so
the minimum is the estimate. Do NOT raise the 18 us budget to make something
pass; if the median genuinely moves, that is a regression -- find it.

ON STUDIO. L4 and L5 have been blocked since iteration 4 and this is now the
single largest gap in what the project can claim: no Instance has ever been
created, no DataStore call has ever been real, no frame has ever been drawn.
If you have Studio access, that is worth more than anything else on this
list -- do it first and say exactly what changed. If you do not, say so
plainly in the handoff rather than letting L3.5 drift into sounding like
"it works".

FINISH BY.

  - Running the full gate and pasting it (19/19 if you added the scan).
  - Updating the docs you invalidated, ROADMAP.md, and HANDOFF.md to the
    template in docs/12-ITERATION-PROMPTS.md.
  - Writing the iteration-12 prompt into docs/12-ITERATION-PROMPTS.md and
    extending the doc gate's prompt loop to cover it.
  - Committing and pushing to your branch.
```

## Prompt — Iteration 12+: contingency and live

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
