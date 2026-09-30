# Handoff — TIDEKEEPER, end of iteration 3

**State:** the server exists and runs. 48 Luau modules, 10 546 lines, layers L0–L4.
The pure core is unchanged and still passes 858 assertions; on top of it there are now
four adapters, eight services, four remote handlers, two diagnostics, and a **session
harness that boots the whole server against a fake Roblox DataModel** and measures what
it costs. 930 executed assertions across the two suites, 0 failures.

**Verification level claimed: L3** — *runs against a simulated platform* (doc 09 §4).
Not L4, not L5. Nothing has run inside Roblox Studio, no real DataStore has been
touched, and the 18 µs `Visit.resolve` budget is still **not** measured. See §3.

**The iteration in one sentence:** the session harness found three defects that no
amount of reading the code would have found, two of which silently destroyed player
history, and that is the whole argument for having built it.

**Read in this order:**

| # | File | Why |
| --- | --- | --- |
| 1 | this file | what happened, what is true, what to do next |
| 2 | [`ROADMAP.md`](ROADMAP.md) | tracker, validation snapshot, open decisions OD1–OD16 |
| 3 | [`code/README.md`](code/README.md) | the Explorer tree and the rules for files in it |
| 4 | [`docs/01-ARCHITECTURE.md`](docs/01-ARCHITECTURE.md) | layering and cadence budgets |
| 5 | [`docs/05-PERSISTENCE.md`](docs/05-PERSISTENCE.md) | §7.1 and §11 are new and are the important parts |
| 6 | [`docs/03-ASYNC-SOCIAL.md`](docs/03-ASYNC-SOCIAL.md) | §6.3 has the measured request cost and the defect table |
| 7 | [`tools/README.md`](tools/README.md) | §5, §5b, §6: the scans, the fengari traps, the session harness |

---

## 1. What was built

```
code/ServerStorage/Tidekeeper/
  Adapters/   DataStoreAdapter  MemoryAdapter  NotifyAdapter  PolicyAdapter
  Services/   CadenceService  PostService  ExchangeService  LedgerService
              NotifyService  ShowcaseService  PlayerService  Bootstrap
code/ServerScriptService/Tidekeeper/
  Main.server.luau
  RemoteHandlers/  SessionHandler  PostHandler  DispatchHandler  DebugHandler
  Diagnostics/     Profiler  BudgetMeter
code/ReplicatedStorage/Tidekeeper/
  Config/Notify Config, Shared/ReceiptCodec, Shared/NetContract, Shared/Remotes
tools/
  lib/harness.js               extracted from the smoke test, shared by both suites
  tests/fake-platform.lua      a fake DataModel, 705 lines
  tests/session-tests.lua      14 scenarios, 72 assertions
  tidekeeper-session-test.js   the runner, and the request-cost report
```

The shape worth noticing: **`Bootstrap.start()` is the entire server architecture in one
readable function**, and it takes every dependency as an argument. `Main.server.luau`
calls it with nothing; the session harness calls it with fakes. There is no "test mode"
branch anywhere in the services, because a test-mode branch is a code path that ships
untested by definition.

### Three findings from iteration 3

**1. Returning `nil` from an `UpdateAsync` transform aborts the update — it does not
delete the key.** This one fact caused two separate, independently fatal bugs:

- `MemoryAdapter:releaseLock` "transformed the lock into nothing" and therefore never
  released anything. Every lock sat until its 90-second TTL expired, so a player who
  left and rejoined within ninety seconds was locked out of their own post.
- `DataStoreAdapter:claimDrifters` returned `nil` when a pool shard emptied, which
  cancelled the removal *after* the records had been handed to a resolve. Over a
  simulated month, **27 real players' Drifters were delivered twice** — and because
  `Resolve.run` schedules arrivals `mod epochCount`, a re-delivered Drifter does not
  duplicate an item, it rewrites history into a different history.

Neither is visible by reading the code. Both read as obviously correct. Both are
one-line consequences of an API detail that the documentation states plainly and that
we implemented anyway.

**2. A budget that counts only the expensive-looking call is not a budget.** The claim
path capped DataStore claims at three requests but did not charge the MemoryStore index
probes that drive them, so a sparse exchange walked backwards through six echo epochs
probing the index for each. Measured cost was 6.24 MemoryStore requests per session
against a design target of two. Charging probes against the same budget brought it to
5.24. The remaining gap is honest and documented, not rounded away.

**3. The turn-based notification API still has not shipped, and building for its
absence made the design better.** Verified 2026-10-01 (doc 10 §6.1): the RDC 2026
announcement promised Studio Beta in October and full release by year end;
`ExperienceNotificationService` is unchanged and client-only; the only send path is a
Creator Store Open Cloud package the developer installs by hand, with dashboard-authored
message bodies of ≤99 characters and a hard cap of one notification per user per day,
with delivery **explicitly not guaranteed**. So `NotifyAdapter` reports itself
`disabled` unless the package is present, `NotifyService` keeps only the
highest-priority candidate per player per day, and **nothing anywhere depends on a send
succeeding**. The most likely outcome of every notification call, for the entire life of
the project, is "disabled". That is the boring path and it is tested.

---

## 2. Commands and their real output

All six pass. Output below is pasted verbatim from this machine, 2026-10-01.

### `node tidekeeper/tools/tidekeeper-quality-gate.js`

```
TIDEKEEPER quality gate — iteration 3, source root tidekeeper/code (48 Luau file(s))

  ok  doc-gate           TIDEKEEPER doc gate: 159/159 checks passed
  ok  separation         no dependency on the VITRIOL tree
  ok  check-syntax       All 48 Luau file(s) parsed successfully.
  ok  metrics              53  code/ReplicatedStorage/Tidekeeper/Domain/Resolve.luau
  ok  hot-loop-scan         1  :Clone (instance clone)
  ok  call-graph           ShowcaseService.new  <- Bootstrap
  ok  find-dead-config     ✓ no dead keys
  ok  determinism-scan   clean
  ok  smoke-test         TIDEKEEPER smoke test: 858 passed, 0 failed, 0 static proof(s) failed
  ok  session-test       TIDEKEEPER session test: 72 passed, 0 failed
  ok  git-diff-check

TIDEKEEPER quality gate: 11/11 checks passed
```

### `node tidekeeper/tools/tidekeeper-doc-gate.js`

```
note: checked 56 relative Markdown links
note: tide: epoch=22357s, spring=26.8, neap=13.2, beat=14.767d, cap=6.99d
note: tide measured: +T_M2 height=11.232754, LOW entries/30d=52, daily range 15.97..29.73
note: checked 5 iteration prompts
TIDEKEEPER doc gate: 159/159 checks passed
```

### `node tidekeeper/tools/tidekeeper-determinism-scan.js`

The scan gained five rules this iteration and lost none. The pure-core rules were
scoped from "everywhere" to `Config/ Lib/ Shared/ Domain/`, which changes the verdict on
zero existing files — and the surface they used to cover is now covered by three
*stricter* rules that name the single file each thing is allowed in.

```
TIDEKEEPER determinism scan — 48 file(s), 10594 line(s) under tidekeeper/code

  ok  math.random            0 violation(s)
  ok  clock                  0 violation(s)
  ok  datetime               0 violation(s)
  ok  services               0 violation(s)
  ok  scheduler              0 violation(s)
  ok  coroutine              0 violation(s)
  ok  unordered-iteration    0 violation(s)
  ok  platform               0 violation(s)
  ok  runservice             0 violation(s)
  ok  scheduler-scope        0 violation(s)
  ok  no-free-text           0 violation(s)
  ok  layering               0 violation(s)

explicit allowances:
  tidekeeper/code/ReplicatedStorage/Tidekeeper/Shared/Remotes.luau:38  services  — Shared/Remotes is the single sanctioned remote factory (doc 01 section 4)
  tidekeeper/code/ReplicatedStorage/Tidekeeper/Shared/Remotes.luau:42  services  — Shared/Remotes is the single sanctioned remote factory (doc 01 section 4)
  tidekeeper/code/ReplicatedStorage/Tidekeeper/Shared/Remotes.luau:53  services  — Shared/Remotes is the single sanctioned remote factory (doc 01 section 4)
  tidekeeper/code/ReplicatedStorage/Tidekeeper/Shared/Remotes.luau:69  services  — Shared/Remotes is the single sanctioned remote factory (doc 01 section 4)
  tidekeeper/code/ServerScriptService/Tidekeeper/RemoteHandlers/DebugHandler.luau:27  runservice  — IsStudio only, no connection is made; the Studio check must happen before the remote is created

clean
```

One rule needed a bug fix to be worth anything: the original scan blanked string
literals before matching, which meant `game:GetService("DataStoreService")` — the only
way anyone actually reaches a service — was invisible to it. Rules that name a service
now match against a comment-stripped but string-preserving view of the line.

### `node tidekeeper/tools/check-syntax.js tidekeeper/code`

```
All 48 Luau file(s) parsed successfully.
```

### `node tidekeeper/tools/tidekeeper-smoke-test.js`

```
TIDEKEEPER smoke test: 858 passed, 0 failed, 0 static proof(s) failed
```

Unchanged from iteration 2, which is the point: the harness scaffolding was extracted
into `tools/lib/harness.js` for the session suite to share, and the smoke test reports
exactly the same 858 assertions afterwards. That is the only acceptable evidence that a
refactor of test infrastructure did not quietly change what is being tested.

### `node tidekeeper/tools/tidekeeper-session-test.js`

```
measured: 5.64 DataStore and 5.24 MemoryStore requests per session over 200 sessions across 8 posts and 30 days

--- measured platform cost ---
  sessions simulated                   200
  distinct posts                       8
  days of virtual time                 30
  DataStore requests, total            1129
  DataStore requests per session       5.64
  MemoryStore requests, total          1048
  MemoryStore requests per session     5.24
  adapter retries                      0
  post saves                           200
  drifters published                   200
  drifters claimed: live               114
  drifters claimed: echo               0
  drifters claimed: seed               2398
  duplicate deliveries refused         0
  cold-start session requests          4

harness wall time: 19150 ms
TIDEKEEPER session test: 72 passed, 0 failed
```

**Against the budget.** Doc 03 §6.3 designed for 5 requests per session; measured 5.64
DataStore. A cold-start session costs 4. At the per-server allowance of
`60 + numPlayers × 40` writes per minute, a 30-player server cycling every 12 minutes
spends roughly 14 requests/minute against 1 260 available. MemoryStore measured 5.24
against a documented target of 2 — the doc has been corrected with the real figure and
an explanation rather than the other way round.

**What the injected failures did.** Scenario 4 injects `DataUpdateConflict` at 40 %:
the adapter classified them, retried, and the write landed — coin 4242 survived. Scenario
5 injects quota exhaustion at 100 %: the join failed **fast**, spending under one second
of backoff rather than the full 15-second schedule, because a quota error does not get
better by waiting. Scenario 6 takes MemoryStore away entirely: the player still got in,
running unlocked, with the degradation counted. Scenario 3 makes every request fail
during a load: the join was **refused** rather than served a fresh empty post, and the
real post with coin 9999 was intact afterwards.

---

## 3. What is *not* verified, stated plainly

| Claim | Status | Why |
| --- | --- | --- |
| The simulation is deterministic and correct | **Verified L2** | 858 assertions in a Lua VM |
| The server survives conflicts, throttling, quota loss and lock contention | **Verified L3** | 72 assertions against a fake DataModel |
| 5.64 DataStore / 5.24 MemoryStore requests per session | **Measured, against a fake** | the fake models per-server budgets, not cross-server contention or real latency |
| `Visit.resolve` fits an 18 µs budget | **NOT VERIFIED (OD12)** | no Roblox Studio was reachable this iteration either; fengari timings are 30–100× slow and meaningless here |
| Cadence slot budgets (0.6 / 2.0 / 6.0 / 12.0 ms) | **NOT VERIFIED** | the virtual clock makes every slot cost 0 ms, so scenario 12 asserts the *accounting*, not the speed |
| Post blob stays under 6 KB through a real DataStore round trip | **NOT VERIFIED** | encoded size is measured (4 416 B base64 worst case); the round trip needs Studio |
| Notification send path works | **NOT VERIFIED, and cannot be** | the Open Cloud package is not installed and the experience has no visits; the *disabled* path is tested, the *sending* path is tested only against a stub sender |
| One Drifter per post per epoch holds across servers | **NOT VERIFIED (OD16)** | `S.publishedAt` is not persisted; same-server case is covered |
| Real concurrency | **NOT MODELLED** | two "servers" are two adapter instances over one backend, interleaved explicitly |

---

## 4. Where the documents were wrong

| Doc | Was | Now |
| --- | --- | --- |
| 03 §6.3 | "mean 4.66 DataStore and 2.00 MemoryStore requests per session" — a number written before the harness existed | the measured 5.64 / 5.24, with the method, the ceilings, and the defect table |
| 05 §7 | release described as an `UpdateAsync` | §7.1: release is a `RemoveAsync`, there is no atomic compare-and-delete, and `holdsLock` must not cost a request |
| 05 §11 | "iteration 3 must ship an in-memory fake implementing the adapter interface" | it ships a fake **DataModel** instead, and §11 explains why faking the adapter would have faked exactly the code that needed testing |
| 10 §6 | — | §6.4 added: the three platform facts the harness proved by contradiction, and OD16 |

---

## 5. Decisions iteration 3 made that iteration 4 inherits

| # | Decision | Rationale |
| --- | --- | --- |
| D13 | `Bootstrap.start(opts)` is the only place anything is constructed | one readable function is the architecture; injection is what makes the session harness possible |
| D14 | The fake is a DataModel, never an adapter | the adapter is where the bugs are |
| D15 | Seed Drifters are exempt from the at-most-once set | they recur by design; putting them in it made a quiet exchange produce an empty Ledger after one pass |
| D16 | An emptied pool shard is written back as an empty list, not removed in the same transform | one wasted key beats duplicated history |
| D17 | Lock ownership between refreshes is answered from local state | the refresh on the `slow` slot is the authority; reading it per save cost a request per session |
| D18 | No lock service means no lock, not no game | `acquireLock` degrades to unlocked and counts it |
| D19 | One Drifter per post per tide epoch, enforced in `ExchangeService:publish` | the id is `makeId(owner, epoch)`, so a second publication collides |
| D20 | The Drifter is published at **logout**, after the save succeeds | publishing first would put a visitor in the world carrying goods the owner's post never recorded parting with |
| D21 | Index probes are charged against the same per-claim request budget as claims | see finding 2 |
| D22 | Determinism-scan rules may be *scoped*, never *weakened*, and every narrowing must be replaced by something stricter | the five new rules name the single file each capability lives in |

Iterations 1–2 decisions D1–D12 are unchanged and still enforced. The one that matters
most for iteration 4 is repeated below.

### The one non-commuting property — still true, still load-bearing

`Resolve.run` assigns each inbound Drifter an arrival epoch of
`Hash.reduce(Hash.mix(d.id, S.salt, 7), epochCount) + 1`. **`epochCount` is the width of
the window being resolved.** Splitting a 12-epoch catch-up into three 4-epoch chunks is
therefore *not* the same computation as one 12-epoch run — a Drifter lands somewhere
else. This is not a bug; it makes the chunk plan part of the specification:

- `CadenceService.planChunks(resolvedAt, now)` is a **pure function** of those two
  numbers, so two servers plan identically;
- `CadenceService.chunkForDrifter(id, salt, chunkCount)` is a **pure function** of
  those three, so the assignment survives a retry;
- and therefore at-most-once delivery is a **correctness requirement**, not an
  optimisation. Scenario 8 asserts it directly.

---

## 6. Open questions for iteration 4

1. **Is `Visit.resolve` inside 18 µs?** Still unknown. OD12. Needs Studio.
2. **Should `S.publishedAt` be persisted?** OD16 — yes, almost certainly, in schema v2.
   `Shared/Version.luau` exists for exactly this and has never been exercised.
3. **Does a 6 KB base64 post blob round-trip cleanly through a real DataStore?** Doc 05
   §3.1 says yes; the platform docs now say "data stores compress your data, avoid
   pre-compressing it yourself" (OD15). Our packing is not compression, but it should be
   checked on real infrastructure.
4. **What do the cadence slots actually cost?** Every timing in doc 01 §5 is an estimate.
5. **Does `warmth` affect price?** OD14, still unanswered, and it is a *design* question
   that iteration 4 should settle before the client makes it visible.

---

## 7. Prompt for iteration 4

Copy the block below verbatim.

```
You are iteration 4 of TIDEKEEPER, a Roblox game living in `tidekeeper/` inside a
repository it shares with an unrelated game called VITRIOL.

BRANCH: work only on your session's fixed branch. Never create or push another.
SEPARATION: never read from or write to the VITRIOL tree at /code, /docs, /tools, or
/README.md, /ROADMAP.md, /HANDOFF.md. Everything you touch is under tidekeeper/.
The quality gate greps every file under tidekeeper/ for the word "Vitriol" and fails.

READ IN THIS ORDER: tidekeeper/HANDOFF.md, tidekeeper/ROADMAP.md,
tidekeeper/code/README.md, tidekeeper/tools/README.md (§5, §5b, §6), then docs 01, 02,
06, 07, 08, 13.

Iteration 3 delivered the server: 48 modules, 930 assertions across two suites,
verification level L3 — it runs against a fake DataModel. Your job is THE CLIENT and
the first thing a player actually sees.

FIRST TASK, BEFORE ANY CODE — use web search, do not guess:
  (a) Re-check whether the turn-based / push notification API has shipped (doc 10 §6.1
      says it had not as of 2026-10-01, with a promise of full release by end of 2026).
      If it has, write the real API into doc 10 §7 and adapt NotifyAdapter. If it has
      not, say so with a date and move on — the game must stay fully playable with zero
      notifications.
  (b) Check current Roblox client-performance guidance and whatever has replaced or
      joined the microprofiler for measuring client frame cost, and anything new about
      streaming, instance budgets or UI performance that changes doc 07.
  (c) Re-check the Studio MCP server tool list (doc 10 §6.3). OD12 depends on
      `execute_luau`; the playtest subagent and screen_capture are the it4 path to
      seeing the game run.

THEN BUILD:
  ReplicatedStorage/Tidekeeper/Client/     (a new layer; the determinism scan already
                                            knows "Client" sits last in LAYER_ORDER)
    ClientBootstrap   the mirror of Bootstrap: one composition root, injected deps
    TideView          the tide, on the real clock, driven by Lib/Tide — no new clock
    LedgerView        renders entries from template ids and integer slots ONLY
    PostView          shelves, stock, prices
    OrdersView        the standing-orders editor, emitting Orders.encode bytes
    DispatchView      pick one of three anonymous slots, an authored phrase id, cargo
    Strings           THE localisation table: every word the player reads lives here
  StarterPlayer/StarterPlayerScripts/Tidekeeper/Main.client.luau

HARD RULES — inherited and non-negotiable:
  - NO FREE TEXT ANYWHERE. No TextBox, no TextService, no FilterStringAsync. The
    determinism scan enforces this and it is not negotiable for any reason.
  - The client is never authoritative. It sends integers; the server decides.
  - Every string the player reads comes from Client/Strings, keyed by a template id.
    A sentence hard-coded in a view is a sentence that cannot be translated.
  - Exactly ONE RunService connection on the server (CadenceService). Decide and
    document how many the client gets; one is the right answer.
  - No remote may be created outside Shared/Remotes.
  - bit32.* only. No pairs() in Domain/.
  - Do not weaken tidekeeper-determinism-scan.js. Scope a rule only if you replace it
    with something stricter, and say so in HANDOFF.

ALSO, IN ORDER OF VALUE:
  1. SETTLE OD12. Connect to Roblox Studio via MCP and measure Visit.resolve with
     execute_luau. Two iterations have now deferred this. If Studio is genuinely
     unreachable, say so plainly in a table like HANDOFF §3 and DO NOT ESTIMATE.
  2. SETTLE OD16. Add S.publishedAt to PostCodec as schema version 2, with a real
     migration through Shared/Version.luau, which has never been exercised. Add a
     session-test scenario that loads a v1 blob and asserts the migration.
  3. Extend tidekeeper-session-test.js with a CLIENT-SIDE scenario: the client's
     rendering of a Ledger batch must produce a string for every template id and every
     slot arity in Domain/Ledger, with no missing keys. That is a unit test of the
     localisation table and it will catch the omissions before a player does.
  4. Bump CURRENT_ITERATION to 4 in tidekeeper-quality-gate.js.

REPORT, with real numbers and real pasted output:
  - the Studio measurement, or a plain statement that there was none;
  - client frame cost, however you measured it, with the method stated;
  - the migration test result;
  - whether the notification API has shipped, with a date and a link.

Claim only what you verified. Verification levels are in doc 09 §4 and the honest
answer is usually L3.

These commands must all pass, and their real output must be pasted into HANDOFF.md:
  node tidekeeper/tools/tidekeeper-quality-gate.js
  node tidekeeper/tools/tidekeeper-doc-gate.js
  node tidekeeper/tools/tidekeeper-determinism-scan.js
  node tidekeeper/tools/check-syntax.js tidekeeper/code
  node tidekeeper/tools/tidekeeper-smoke-test.js
  node tidekeeper/tools/tidekeeper-session-test.js

Finally: update ROADMAP.md (iteration 4 row, validation snapshot, open decisions),
rewrite HANDOFF.md in this file's shape, and write the iteration 5 prompt into it.
Use web search wherever a fact about the platform matters. Ask if you have questions.
```
