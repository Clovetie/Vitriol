# Handoff — TIDEKEEPER, end of iteration 4

**State:** the game is playable end to end in simulation. 57 Luau modules, 12 222 lines,
layers L0–L5. The client layer exists — eight pure presenter modules and exactly one
`LocalScript` — and every word a player reads is now generated from integers at read
time. **1 005 executed assertions across two suites, 0 failures.** The 18 µs
`Visit.resolve` budget, deferred by iterations 2 and 3, is **measured and closed**.

**Verification level claimed: L3.5** — *runs in a real Luau VM* (doc 09 §4). This level
was added this iteration. It is **not** L4: no Roblox engine was involved, no DataModel
exists, and no real DataStore has been touched. See §3.

**The iteration in one sentence:** two of the three things iteration 3 declared blocked
on "no Roblox Studio is reachable" turned out not to need Studio at all, and finding
that out was worth more than the features.

**Read in this order:**

| # | File | Why |
| --- | --- | --- |
| 1 | this file | what happened, what is true, what to do next |
| 2 | [`ROADMAP.md`](ROADMAP.md) | tracker, validation snapshot, open decisions OD1–OD18 |
| 3 | [`docs/10-RESEARCH-NOTES.md`](docs/10-RESEARCH-NOTES.md) | **§7 is new** and is the most important reading in this iteration |
| 4 | [`docs/04-SIMULATION-MODEL.md`](docs/04-SIMULATION-MODEL.md) | §6.1 — the measured performance numbers |
| 5 | [`docs/08-CLIENT-UX-MOBILE.md`](docs/08-CLIENT-UX-MOBILE.md) | §8.1–8.2 — how the client and the prose system actually work |
| 6 | [`docs/05-PERSISTENCE.md`](docs/05-PERSISTENCE.md) | §6.1 — schema v2 and the sentinel bug |
| 7 | [`tools/bin/README.md`](tools/bin/README.md) | how to build the Luau VM the bench needs |

---

## 1. What was built

```
code/ReplicatedStorage/Tidekeeper/Client/     (new — 8 modules, all pure)
  Strings          every word a player reads, keyed by template id
  Format           expands {directives}; five miss counters, no silent fallback
  LedgerView       the replay screen; re-runs the real Visit.resolve
  TideView         the tide clock, in the player's local timezone
  PostView         shelves, stock, coin
  OrdersView       the standing-orders editor, opcode-driven
  DispatchView     choosing where a Drifter goes
  ClientBootstrap  wires the views to the remotes; no Instances

code/StarterPlayer/StarterPlayerScripts/Tidekeeper/
  Main.client.luau  the ONLY client file that touches `game`,
                    holds the ONLY client RunService connection,
                    and is the ONLY place a client Instance is created
```

Plus, on the tooling side:

```
tools/lib/luau-native.js        bundles pure modules for a real Luau VM
tools/bench/resolve-bench.luau  the OD12 benchmark chunk
tools/tidekeeper-luau-bench.js  runner; skips loudly when no VM is present
tools/fixture-blobs/post-v1.b64 a genuine 249-byte v1 PostCodec blob
tools/bin/README.md             how to build Luau in four minutes
```

### 1.1 The client is a presenter layer, not an application (D25)

Eight of the nine client files are pure: they take data, they return a view-model table,
and they cannot see the DataModel. `Client` is in the determinism scan's `NO_DATAMODEL`
set, so a view that calls `GetService` fails the build rather than being caught in
review. The single `LocalScript` owns everything impure.

This means every screen in the game is testable without Roblox, and scenario 15 does
exactly that: it renders the entire Ledger, checks every line, and never constructs an
Instance.

### 1.2 No sentence is ever stored or replicated (D26, D27)

A Ledger entry on the wire is `(templateId, epoch, actorId, slots[])` — about 24 bytes
of integers. The prose lives only in `Client/Strings.luau` and is expanded at read time.
Two consequences, both load-bearing:

- **Translation is one file.** Every historical entry in every existing save re-renders
  in a new language, because the save contains no English.
- **The phrasing is chosen by `hash(actorId, epoch)`, never randomly.** The Ledger is a
  *replay* (doc 04 §7). Reopening it must produce the same words forever, or the game's
  memory becomes quietly unreliable.

---

## 2. Commands and their real output

### `node tidekeeper/tools/tidekeeper-quality-gate.js`

```
TIDEKEEPER quality gate — iteration 4, source root tidekeeper/code (57 Luau file(s))

  ok  doc-gate           TIDEKEEPER doc gate: 169/169 checks passed
  ok  separation         no dependency on the VITRIOL tree
  ok  check-syntax       All 57 Luau file(s) parsed successfully.
  ok  metrics              53  code/ReplicatedStorage/Tidekeeper/Domain/Resolve.luau
  ok  hot-loop-scan         1  :Clone (instance clone)
  ok  call-graph           ShowcaseService.new  <- Bootstrap
  ok  find-dead-config     ✓ no dead keys
  ok  determinism-scan   clean
  ok  smoke-test         TIDEKEEPER smoke test: 888 passed, 0 failed, 0 static proof(s) failed
  ok  session-test       TIDEKEEPER session test: 117 passed, 0 failed
  ok  luau-bench         TIDEKEEPER Luau bench: within budget (median 15.903 us, p99 22.326 us, catch-up 2946.6 us).
  ok  git-diff-check

TIDEKEEPER quality gate: 12/12 checks passed
```

### `node tidekeeper/tools/tidekeeper-luau-bench.js`

```
=== Visit.resolve (REAL Luau) ===
  median         15.980 us
  p99            18.312 us
  budget         18 us median / 50 us p99 (doc 04 section 6)
  headroom       1.1x under the median budget
  calibration    1e6 integer adds took 4.7 ms
  ratio          one visit costs about 3416 integer adds

=== Resolve.run (REAL Luau) ===
  1 epoch, no arrivals            17.0 us
  27 epochs, 216 arrivals       2945.3 us   (the documented worst case)
  budget for a full catch-up   12000.0 us   (doc 01 section 5: 12 ms slow slot)
  headroom                         4.1x

RESULT median=15.980us p99=18.312us catchup=2945.3us verdict=WITHIN_BUDGET
```

Needs a `luau` binary; see [`tools/bin/README.md`](tools/bin/README.md). Without one it
prints `SKIPPED` with build instructions and exits 0 — the gate stays green but says so.

### `node tidekeeper/tools/tidekeeper-determinism-scan.js`

**13 rules now**, clean, 5 explicit allowances, and a whole-tree connection count:

```
  ok  single-connection      2/2 RunService connection(s)
         .../Services/CadenceService.luau:209
         .../StarterPlayerScripts/Tidekeeper/Main.client.luau:78
clean
```

The connection budget is now **exactly exhausted**, which is the intended steady state:
one scheduler per side, and a thirteenth connection anywhere fails the build.

### `node tidekeeper/tools/tidekeeper-session-test.js`

```
TIDEKEEPER session test: 117 passed, 0 failed
measured: 5.64 DataStore and 5.24 MemoryStore requests per session
          over 200 sessions across 8 posts and 30 days
```

Unchanged request cost — the client layer adds no platform calls, which is the point of
it being a presenter.

---

## 3. What is *not* verified, stated plainly

- **Nothing has run inside Roblox.** No Studio was reachable from this environment, in
  this iteration or the two before it. Everything is either fengari (L2), a fake
  DataModel (L3), or the standalone Luau VM (L3.5).
- **L3.5 is not L4.** The `luau` CLI is the same *language runtime* Roblox embeds, at a
  pinned version, but there is no DataModel, the GC tuning and build flags differ, and
  the hardware is a CI box. Doc 09 §4 has the full table. The performance numbers are a
  fair order of magnitude and are **not** numbers from Roblox hardware.
- **No Instance has ever been created.** The client's `Main.client.luau` builds real UI
  and has been parsed, scanned and reviewed — it has never been *run*. This is the
  largest untested surface in the project and iteration 5 must treat it that way.
- **Median performance headroom is 1.1×.** That is inside budget and it is thin. It is
  reported as thin everywhere rather than rounded up to "comfortable".
- **No human has played this.** R1 is still open.

---

## 4. Where the documents were wrong

| Document | Was | Is |
| --- | --- | --- |
| doc 04 §6 | "at a measured target of ≤ 18 µs … ~11.7 ms" | a real catch-up is **2.9 ms**; the 11.7 ms figure came from multiplying the *budget* by the worst case and calling it a measurement |
| doc 09 §4 | L3 → L4 with nothing between | **L3.5** exists; the gap between "a fake DataModel" and "the Roblox engine" contains a real, useful rung |
| doc 10 §6.4 | OD12 needs Studio | it needed a compiler |
| ROADMAP OD14 | "settle in it4" | moved to it5 **with a stated lean and a reason**, not silently slipped |

---

## 5. Decisions iteration 4 made that iteration 5 inherits

Decisions D13–D22 are unchanged and remain in force. New:

| # | Decision | Why |
| --- | --- | --- |
| D23 | `publishedAt` is persisted at schema v2 by **appending at the blob tail**, never inserting | v2 is byte-for-byte v1 plus a `u32`; a reader that ignored the tail would still parse the head |
| D24 | Fixture blobs in `tools/fixture-blobs/` are **never edited and never regenerated** | a regenerated fixture tests the current code against itself; the entire value is that those bytes were written by code that no longer exists |
| D25 | The client is a pure presenter layer plus exactly one `LocalScript` | `Main.client.luau` is the only client file touching `game` and owns the only client `RunService` connection; enforced by the scan, not by review |
| D26 | **No sentence is ever stored or replicated.** `(templateId, slots)` renders through `Strings`/`Format` at read time | translation becomes one file, and every historical save re-renders in the new language |
| D27 | Prose variants are chosen by `hash(actorId, epoch)`, never randomly | the Ledger is a replay; it must read identically forever |
| D28 | **A sentinel must be impossible to confuse with a legal value.** Check it against the *range* of the field, not against what looks empty | see §5.1 |
| D29 | An exemption list may say *which* file may do X, never *how many times*. Where the invariant is a count, **count it** | see §5.2 |
| D30 | Receipts have their own Ledger template range (100–105), separate from visit templates (1–99) | see §5.3 |

### 5.1 The sentinel bug — D28

`publishedAt` was first written as `0 = never published`. But `Tide.epoch(TideConfig.EPOCH)`
is **0** — epoch 0 is a real epoch, the *first* one. So a post created during the first
6.2 hours of the game's existence read as "already published at epoch 0", and
`ExchangeService:publish` refused it forever with `lastEpoch 0 >= epoch 0`.

Six previously-green session assertions went red simultaneously. Because the client work
landed in the same iteration, the failures looked like the new tests and cost real time
before the actual cause was found. The fix: `publishedAt` is **absent** in memory for
"never", and the codec stores **`epoch + 1`** on the wire so that wire-0 is unambiguous.

The general lesson is the decision: *what is the range of this field, and does the
sentinel fall inside it?* "Zero looks empty" is not an argument.

### 5.2 Exemptions cannot express counts — D29

The determinism scan gained an `exceptFiles` option this iteration for a good reason:
`except` matches a **basename**, and both `Main.server.luau` and `Main.client.luau`
reduce to `"Main"`, so exempting one would have silently exempted the other. That was a
real hole and `exceptFiles` closes it.

But it exposed the deeper problem: the rule that matters is not "which file may connect
to `RunService`" — it is "**how many** `RunService` connections exist in the whole
game". An exemption list cannot say that. So a thirteenth check counts them across the
tree with `MAX_CONNECTIONS = 2`, one per side, and naming a file in an exemption list no
longer buys it a second connection.

**And the first version of the count was itself wrong**, which is worth recording. It
matched on the literal identifier `RunService`, so it never saw
`self.runService.Heartbeat:Connect(...)` in `CadenceService` — the service takes
RunService by injection, which is precisely what lets the session harness drive the
server with no DataModel. The check reported **1/2** for a game that has two
connections: a green check for an invariant nobody was enforcing, which is worse than
no check at all.

It now matches on the **signal name** rather than the receiver, and reports 2/2. The
general form of the lesson: *a static check written against one calling convention
silently exempts every other convention in the codebase.* Test a new check by
confirming it catches the thing that already exists, not by confirming it is quiet.

### 5.3 The bug the localisation test found — D30

Scenario 15 was written to check that every Ledger template has prose. It found that,
and then it found something much worse.

`LedgerService:slotsFor` was filling Ledger slots from a positional pool
`{spent, warmth, noteId, flags}` **regardless of what the template's slots meant**. So a
receipt — "your drifter, at somebody else's post" — was rendered through a *visit*
template, and a coin amount landed in a `{find:1}` slot. The game confidently named an
object "12", and a tide code of 6 appeared where only 1–5 exist.

The fix is structural rather than a slot remap, because the remap would have been a lie:
a receipt genuinely does not know which find was on the shelf, what the host's tide was
doing, or what class of boat the host saw. Those facts do not exist on that side of the
exchange. So receipts now have **their own template range, 100–105**, with prose written
for what a receipt actually knows, and `slotsFor` maps each one explicitly. The one
piece of real data recovered rather than invented is the tide: it is a pure function of
time, so `Tide.codeForEpoch(r.epoch)` reconstructs it exactly.

**This bug was invisible for two iterations because nothing rendered those entries.**
Server code that produces data no one reads yet is untested code wearing a passing test
suite.

---

## 6. Open questions for iteration 5

Full table in [`ROADMAP.md`](ROADMAP.md). The ones that will actually bite:

- **OD14 — does `warmth` affect price?** Now has a lean: **no, keep it prose-only.**
  Wiring it into price turns warmth into a stat to farm and makes every visitor an
  optimisation problem, which inverts doc 00's pillars. Decide against a playtest.
- **OD17 — adopt Lute.** It has a native Luau test runner, which would let
  `pure-tests.lua` stop being *transformed Lua 5.3 under fengari* and become real Luau —
  deleting `floatifyNumbers`, the `bit32` shim and the `%d`→`%.0f` rewrite outright, and
  with them a whole class of "the harness disagrees with the game" bug.
- **OD18 — adopt LibMP** for the client frame budget, sampled on a fraction of sessions.
- **The `single-connection` check reports 1/2 and should report 2/2.** See §5.2.
- **Studio, finally.** The MCP ecosystem is far richer than doc 09 §2 recorded (doc 10
  §7.3): 68-tool servers with `execute_luau`, `start_playtest`, screenshots and Open
  Cloud passthrough. All of them need a running Studio process. If one is available in
  iteration 5, L4 and L5 are reachable in a single session.

---

## 7. Prompt for iteration 5

See [`docs/12-ITERATION-PROMPTS.md`](docs/12-ITERATION-PROMPTS.md) §5 for the copy-paste
prompt.
