# Handoff — TIDEKEEPER, end of iteration 2

**State:** the pure core exists, runs, and is tested. 25 Luau modules, 5 263 lines,
layers L0 (`Lib`) and L2 (`Domain`) only, plus `Config` and the `Shared` wire formats.
858 executed assertions, 0 failures. Nothing in `code/` touches `game`, a service, an
`Instance`, or the clock.

**Verification level claimed: L2** — *executed in a Lua VM outside Roblox*
(doc 09 §4). Not L3, not L5. Nothing here has run inside Roblox Studio, no DataStore
has been touched, and the 18 µs performance budget is **not** verified. See §3.

**Read in this order:**

| # | File | Why |
| --- | --- | --- |
| 1 | this file | what happened, what is true, what to do next |
| 2 | [`ROADMAP.md`](ROADMAP.md) | tracker, the validation snapshot, open decisions OD1–OD14 |
| 3 | [`code/README.md`](code/README.md) | the Explorer tree and the eight rules for files in it |
| 4 | [`docs/01-ARCHITECTURE.md`](docs/01-ARCHITECTURE.md) | layering and budgets — iteration 3 lives at L1 and L3 |
| 5 | [`docs/05-PERSISTENCE.md`](docs/05-PERSISTENCE.md) | key map, wire formats, locking, retries |
| 6 | [`docs/03-ASYNC-SOCIAL.md`](docs/03-ASYNC-SOCIAL.md) | the Drifter Exchange, which is iteration 3's hardest problem |
| 7 | [`tools/README.md`](tools/README.md) | §5 and §5b: the determinism scan, and what the harness has to fake |

---

## 1. What was built

```
code/ReplicatedStorage/Tidekeeper/
  Config/   GameConfig TideConfig EconomyConfig DrifterConfig OrdersConfig FindsConfig
  Lib/      MathExt Hash RNG Tables Signal Codec Schema Tide
  Shared/   Version DrifterCodec PostCodec
  Domain/   Standing Almanac Drifter Post Orders Ledger Visit Resolve
tools/
  tidekeeper-smoke-test.js         858 assertions against the real modules
  tidekeeper-determinism-scan.js   8 static rules, enforcing
  tests/pure-tests.lua             the suite
```

The three modules worth reading first, because everything else serves them:

- **`Domain/Resolve.luau`** — `Resolve.run(S, now, inbound, work) -> (S', entries, receipts, info)`.
  Pure, total, deterministic, bounded at 27 tide epochs. Deep-copies `S` on entry, so a
  resolve can be run a thousand times from the same input and compared byte for byte.
  `now` is an argument; the module cannot learn the time.
- **`Domain/Visit.luau`** — one Drifter, one post, one outcome, in eight stages. Fills a
  *delta*; `Visit.apply` is the only thing that mutates the post. That split is what
  makes the conservation invariant checkable and what will let the client replay a visit
  against a read-only mirror in iteration 4.
- **`Lib/Tide.luau`** — the shared clock. Three constituents unrolled to scalars,
  allocation-free `height`, analytic `velocity`, and a bisecting `nextStateChange` that
  returns an exact integer second.

### Three findings from iteration 2

**1. Writing the spec down is not the same as computing it.** Executing doc 02 §8's
twelve tide test vectors found that **three of them were wrong** — not marginally, but
by 4.27 studs, by 6 events, and by 3 studs. Each was "reasoned about" rather than
computed. Two of the five documentation corrections below are the same species. The doc
gate now re-derives those three vectors in JavaScript from the §2.2 constants, so the
same class of error cannot recur silently, and the Lua harness asserts them
independently: two implementations, written from the constants, agreeing to 1e-9.

**2. The test environment was lying, and would have kept lying.** fengari's integer
subtype is **32 bits wide with silent wraparound** (`luaconf.LUA_MAXINTEGER === 2147483647`).
Luau has no integer subtype at all — every number is a double. Running the real codecs
under fengari's defaults produced a suite that reported **841 passing assertions**, of
which every single one involving a value above 2³¹ was meaningless: `255 * 16777216`
evaluated to `-16777216` and the u32 round-trip test "passed" its way to `-1`. The fix
was to make the harness match Luau rather than Lua 5.3 — rewrite integer literals to
floats, force `math.floor` and friends to return floats — and it is documented at length
in `tools/README.md` §5b because **any future harness for this project has to do the
same thing**.

**3. A static rule caught what 858 dynamic assertions could not.** The determinism scan's
first run flagged `local workspace = work or Resolve.newWorkspace()` — a local shadowing
the Roblox global `workspace` inside a module whose entire value proposition is that it
never touches Roblox. No test could have failed on that; it is correct Lua and correct
behaviour. It is also exactly how platform surface creeps back into a pure layer two
iterations later. The rule stays.

---

## 2. Commands and their real output

Every command below was run from the repository root at the end of iteration 2, and the
output is pasted verbatim.

### `node tidekeeper/tools/tidekeeper-quality-gate.js`

```
TIDEKEEPER quality gate — iteration 2, source root tidekeeper/code (25 Luau file(s))

  ok  doc-gate           TIDEKEEPER doc gate: 148/148 checks passed
  ok  separation         no dependency on the VITRIOL tree
  ok  check-syntax       All 25 Luau file(s) parsed successfully.
  ok  metrics              39  code/ReplicatedStorage/Tidekeeper/Shared/PostCodec.luau
  ok  hot-loop-scan         1  table.sort
  ok  call-graph           Version.classify  <- PostCodec
  ok  find-dead-config     ✓ no dead keys
  ok  determinism-scan   clean
  ok  smoke-test         TIDEKEEPER smoke test: 858 passed, 0 failed, 0 static proof(s) failed
wait  session-test       tidekeeper-session-test.js not present yet (expected in iteration 3; this is iteration 2).
  ok  git-diff-check

TIDEKEEPER quality gate: 10/11 checks passed, 1 not applicable yet
```

The gate now carries a hand-edited `CURRENT_ITERATION` constant. **Iteration 3 must bump
it to 3**, which is what turns `session-test` from `wait` into a hard requirement.

### `node tidekeeper/tools/tidekeeper-doc-gate.js`

```
note: checked 45 relative Markdown links
note: tide: epoch=22357s, spring=26.8, neap=13.2, beat=14.767d, cap=6.99d
note: tide measured: +T_M2 height=11.232754, LOW entries/30d=52, daily range 15.97..29.73
note: checked 5 iteration prompts
TIDEKEEPER doc gate: 148/148 checks passed
```

### `node tidekeeper/tools/tidekeeper-determinism-scan.js`

```
TIDEKEEPER determinism scan — 25 file(s), 5288 line(s) under tidekeeper/code

  ok  math.random            0 violation(s)
  ok  clock                  0 violation(s)
  ok  datetime               0 violation(s)
  ok  services               0 violation(s)
  ok  scheduler              0 violation(s)
  ok  coroutine              0 violation(s)
  ok  unordered-iteration    0 violation(s)
  ok  layering               0 violation(s)

clean
```

### `node tidekeeper/tools/check-syntax.js tidekeeper/code`

```
All 25 Luau file(s) parsed successfully.
```

No known-failure allowlist. Iteration 1 dropped the sibling project's, and the rule
"`bit32.*` only, no native `&` `|` `~`" is what keeps it dropped.

### `node tidekeeper/tools/tidekeeper-smoke-test.js`

```
=== assertions by section ===
  MathExt          28        Version          18        Visit           113
  Hash             21        DrifterCodec     40        PostCodec        36
  RNG              28        Standing         38        Resolve          64
  Tables           33        Almanac          23        determinism      13
  Signal           14        Post             53        economy          46
  Codec            86        Orders          100        benchmark         2
  Schema           25        Ledger           28
  Tide             49

--- static proofs (source inspection, not the VM) ---
  ok  Visit.resolve body located  [241 lines]
  ok  Visit.resolve contains no table constructor  [0 occurrence(s) of '{']
  ok  Visit.resolve calls no allocating helper  [none]

harness wall time: 79703 ms
TIDEKEEPER smoke test: 858 passed, 0 failed, 0 static proof(s) failed
```

Against doc 04 §8's per-area minimums: Tide ≥30 → **49**; RNG ≥20 → **28**;
Codec ≥40 → **86**; Orders ≥50 → **100**; Visit ≥80 → **113**; Resolve ≥40 → **64**;
determinism ≥10 → **13**; economy ≥30 → **46**. Total ≥300 → **858**.

Measured blob sizes, printed by the suite:

```
post blob size: 289 bytes (fixture)
MAXIMAL post blob: 3312 bytes, budget 6144 (base64: 4416 bytes)
post blob after a busy 27-epoch week: 526 bytes
a 200-record drifter shard: 13607 bytes (13.29 KB)
```

The maximal post — 160 store entries, 24 shelves, a full 48-entry visitor ring, 64
claims and a 1 024-byte orders program — is **3 312 bytes against the 6 KB budget**, and
**4 416 bytes base64**, comfortably inside a 32 KB MemoryStore value. The 13.29 KB warm
shard matches doc 03 §6 exactly.

---

## 3. What is *not* verified, stated plainly

| Claim | Status |
| --- | --- |
| `Visit.resolve` fits 18 µs median / 50 µs p99 | **NOT VERIFIED.** See below. |
| Anything behaves this way inside Roblox Studio | not verified — nothing has run there |
| DataStore / MemoryStore behaviour, quotas, throttling | not verified — no adapter exists yet |
| The async notification API | not verified — **iteration 3's first task** |
| The game is fun | not verified and not provable here — iteration 4's R1 playtest |

**The benchmark.** `Visit.resolve` measures **1.73 ms median, 2.36 ms p99** in fengari.
The same harness clocks 1e6 integer additions at ~94 ms, i.e. ~94 ns per addition
against Luau's ~1–2 ns. Dividing through puts the true figure somewhere in a 20–60 µs
band, which straddles the budget and therefore settles nothing. The harness prints this
verdict itself rather than letting a reader infer a pass. **Measure it in Studio in
iteration 3** via the MCP `execute_luau` tool (doc 09 §3), before tuning anything.

**The zero-allocation claim** is supported by two proofs and neither is a heap profiler:
statically, the body of `Visit.resolve` extracted from the real source contains no `{`,
no `..`, and no allocating helper; dynamically, 3 000 visits replace none of the 13
buffers in the reused context. fengari does not implement `lua_gc`, so
`collectgarbage("count")` is unavailable — this was the honest alternative to inventing
a number.

---

## 4. Where the documents were wrong

Five corrections, all made in the documents themselves with a marked note explaining the
error, and all now asserted by a test or by the doc gate.

| # | Doc | Was | Is | Why the original was wrong |
| --- | --- | --- | --- | --- |
| 1 | 02 §8 | `height(EPOCH + T_M2)` "within 0.9 of 15.5" | `11.232754472632912` (4.267 away) | after one M2 period S2 and K1 have both drifted; only M2 returned to phase |
| 2 | 02 §8 | `LOW` entries over 30 d ∈ [55, 65] | **52** | assumed ~2 LOW windows per M2 cycle; the −6 threshold is only crossed on the bigger swings |
| 3 | 02 §8 | spring/neap daily range ≈26.8 / ≈13.2 | **29.73 / 15.97** | computed `2*(A_M2 ± A_S2)` and forgot K1's 2.1 amplitude entirely |
| 4 | 05 §4 | `id = (userId << 24) \| epochLow` | `id = owner * 8192 + (epoch mod 8192)` | **not representable.** User ids exceed 2³², shifted by 24 that is > 2⁵³, and a Luau double would silently round two Drifters onto the same id |
| 5 | 06 §2 | 11 000 Standing falls to "~4 700" in a fortnight | **5 798** | ~4 700 is decay toward zero; decay is toward the *band floor*, and the per-epoch `floor()` fixes the exact value |

Plus two clarifications, not errors:

- **06 §3** wrote `pricePressure(p, budget, dearTaste)` but the body never used `budget`
  — it uses the find's base value. The shipped signature is
  `Visit.pricePressure(price, baseValue, dearTaste)`.
- **04 §4** wrote `D.taste[2]` using doc 03 §5's **0-based** axis numbering. Lua is
  1-based, so the cheap/dear axis is index **3**. The doc now says `D.taste[DEAR]` and
  the code uses `DrifterConfig.AXIS_DEAR`. Rule going forward: prose may use 0-based axis
  numbers; **code always uses the named constant.**

---

## 5. Decisions iteration 2 made that iteration 3 inherits

| # | Decision | Reason |
| --- | --- | --- |
| D1 | `--!nonstrict` on every module | `--!strict` fights the table-driven config shapes for no runtime benefit |
| D2 | **`bit32.*` only — never `&`, `\|`, `~`** | `check-syntax.js` parses Lua 5.1, where those are syntax errors, and there is no allowlist |
| D3 | `Post.store` is a **sorted array** of `{id, qty}` with binary search, never a `[id] = qty` map | `pairs` order is unspecified and the resolver iterates stock; a map would make the simulation non-deterministic |
| D4 | `Resolve.run` deep-copies `S`; `Visit.resolve` writes into a pre-allocated context | one copy per *session*, not per visit; this is what makes the 1 000-run replay proof possible |
| D5 | `Visit.resolve` returns a delta; `Visit.apply` is the only mutator | makes conservation checkable and lets the client replay against a read-only mirror |
| D6 | `RNG:normal` is **Bates-4**, not Box–Muller | Box–Muller needs `log` and `cos`, whose last bit is libm-dependent, and this value decides whether a player got paid |
| D7 | Arrival epoch = `firstEpoch + (Hash.mix(id, salt, 7) mod epochCount)`, overflow spills forward then is **dropped and counted** | a silent drop is an invisible economy leak |
| D8 | Nested config tables are **arrays of arrays**, never named sub-keys | `find-dead-config.js` only collects keys at brace depth ≤ 2 |
| D9 | `S.sold` is a second 32-byte bitset beside `S.almanac` | "first one you ever sold" cannot be derived from "ever held" — everything on a shelf was held |
| D10 | Barter forms a **claim** on `S.claims`, bounded at 64, never a transfer | doc 03 §9; an unbounded queue is a way for a griefer to make a post fail to save |
| D11 | The quality gate carries a hand-edited `CURRENT_ITERATION` | a gate that infers how far along the project is will eventually infer wrongly |

### Config keys deliberately left unreferenced

`find-dead-config.js` reports five. All are reserved, none are dead:

| Key | Wanted by |
| --- | --- |
| `GameConfig.EPOCHS_PER_RESOLVE_TICK` | iteration 3, `CadenceService` chunking |
| `GameConfig.MAX_RESIDENT_DRIFTERS` | iteration 3, `ExchangeService` warm shard |
| `GameConfig.RECEIPT_BLOB_BYTES` | iteration 3, `ReceiptCodec` |
| `FindsConfig.GROUP_NAMES` | iteration 4, UI |
| `FindsConfig.ZONE_COUNT` | iteration 3, beachcombing |

If iteration 3 does not consume the first three, delete them rather than let the list rot.

### The one non-commuting property — read this before writing `ExchangeService`

A Drifter's arrival epoch depends on **the width of the window being resolved**
(`mod epochCount`). Consequences, both pinned by assertions so they cannot change
silently:

- with **no** inbound Drifters, resolving 1 epoch then 2 more is byte-identical to
  resolving 3 at once — decay, spoilage, comb maturation and passive income all commute;
- with inbound Drifters, feeding the **same list** to two windows is **not** the same run.

That is correct — in the live game the exchange hands each Drifter to exactly one
resolve — but it makes **at-most-once delivery a hard requirement** on `ExchangeService`.
A retry that re-delivers a batch corrupts history rather than duplicating it. Design the
claim/ack protocol for that from the start.

---

## 6. Open questions for iteration 3

1. **What is the shipped async-notification API?** The whole design assumes something
   exists. Verify before designing `NotifyService` (see the prompt below). OD7.
2. **Do MemoryStore keys count toward the memory quota?** Size assuming they do. OD9.
3. **Is `Visit.resolve` actually inside 18 µs in Luau?** Unknown. OD12.
4. **Is one `RunService` connection enough** once resolve is chunked at ≤4 epochs/tick
   and 8 posts may be resolving at once? Doc 01 §5 says yes; measure it.
5. **What happens when two servers resolve the same post?** Doc 05 §7 specifies a 90 s
   MemoryStore session lock. The fake-persistence layer must simulate losing that race.

---

## 7. Prompt for iteration 3

Copy the block below verbatim.

```
You are iteration 3 of TIDEKEEPER, a Roblox game living in `tidekeeper/` inside a
repository it shares with an unrelated game called VITRIOL.

BRANCH: work only on your session's fixed branch. Never create or push another.
SEPARATION: never read from or write to the VITRIOL tree at /code, /docs, /tools, or
/README.md, /ROADMAP.md, /HANDOFF.md. Everything you touch is under tidekeeper/.
The quality gate greps every file under tidekeeper/ for the word "Vitriol" and fails.

READ IN THIS ORDER: tidekeeper/HANDOFF.md, tidekeeper/ROADMAP.md,
tidekeeper/code/README.md, tidekeeper/tools/README.md (§5 and §5b especially),
then docs 01, 03, 05, 13.

Iteration 2 delivered the pure core: 25 modules, 858 passing assertions, verification
level L2. Your job is persistence, the Drifter Exchange, and the server services.

FIRST TASK, BEFORE ANY CODE — use web search, do not guess:
  (a) Verify the SHIPPED async/turn-based notification API. Roblox's turn-based
      notification system entered Studio Beta around October 2026 and Developer Push
      Notification Support was on the late-2026 roadmap (doc 10 §1.1-1.3). Find what
      actually shipped, with a date and a link, write it into docs/10-RESEARCH-NOTES.md
      §6, and design NotifyService against reality. The game must remain fully playable
      with zero notifications.
  (b) Re-verify the DataStore and MemoryStore quota numbers in doc 10 §3. They were
      correct in September 2026; confirm they still are, and correct the docs if not.
  (c) Check whether Roblox Studio's MCP server API has changed (doc 09 §2). Iteration 4
      depends on it.

THEN BUILD:
  L1  ServerStorage/Tidekeeper/Adapters/
        DataStoreAdapter   retry policy doc 05 §8, budget guard, session lock doc 05 §7
        MemoryAdapter      hash map + queue, sharded, quota-aware, degrades never blocks
        NotifyAdapter      per the API you verified in (a)
        PolicyAdapter      doc 13 §3 — wire it even though nothing depends on it yet
  L3  ServerStorage/Tidekeeper/Services/
        CadenceService     THE single RunService connection, slots per doc 01 §5
        PlayerService PostService ExchangeService LedgerService NotifyService
        ShowcaseService
      ServerStorage/Tidekeeper/Bootstrap
      ServerScriptService/Tidekeeper/Main, RemoteHandlers/*, Diagnostics/{Profiler,BudgetMeter}
      ReplicatedStorage/Tidekeeper/Shared/Remotes, NetContract
      ReplicatedStorage/Tidekeeper/Shared/ReceiptCodec  (28 B, doc 05 §5)

  Plus the in-memory fake persistence layer of doc 05 §11, with INJECTED FAILURES:
  DataUpdateConflict, quota exhaustion, request-budget starvation, throttling, and
  two-server session-lock contention.

HARD RULES — these are inherited and non-negotiable:
  - Exactly ONE RunService connection in the entire game, in CadenceService.
  - Only adapters may yield. Only adapters may touch DataStore/MemoryStore/Http.
  - Nothing under Lib/ or Domain/ may gain a dependency on anything you write.
    tidekeeper-determinism-scan.js enforces the layer ordering; do not weaken it.
  - bit32.* only; no native & | ~ anywhere. There is no known-failure allowlist.
  - No pairs() in Domain/. Prefer sorted iteration everywhere a result is persisted.
  - Remotes are created in exactly one file and validated by NetContract.
  - No remote accepts free text (doc 13 §2).
  - Resolve runs chunked: <= 4 epochs/tick, <= 27 epochs total (doc 01 §5).
  - ExchangeService MUST deliver each Drifter to exactly one resolve. See HANDOFF §5,
    "the one non-commuting property" — at-most-once is a correctness requirement, not
    an optimisation, and a retried batch corrupts history.

BUILD tidekeeper/tools/tidekeeper-session-test.js: boot the server against a virtual
DataModel and the fake stores, and run a SIMULATED 30-DAY, 200-SESSION LIFETIME across
at least 8 posts exchanging real Drifters through the real ExchangeService. Assert every
economy invariant in doc 04 §9 at every step. This test is the point of the iteration.
Reuse tidekeeper-smoke-test.js's harness scaffolding — in particular floatifyNumbers and
the bit32 shim, documented in tools/README.md §5b. Without them fengari's 32-bit integer
subtype will silently wrap every value above 2^31 and the suite will pass while being
wrong; iteration 2 hit exactly this and it cost real time.

ALSO:
  - Bump CURRENT_ITERATION to 3 in tidekeeper-quality-gate.js. This makes the session
    test a hard requirement, which is the point.
  - Measure Visit.resolve in Studio via the MCP execute_luau tool and settle OD12.
    If you cannot reach Studio, say so plainly and leave OD12 open — do not estimate.
  - Either consume or delete GameConfig.EPOCHS_PER_RESOLVE_TICK,
    GameConfig.MAX_RESIDENT_DRIFTERS and GameConfig.RECEIPT_BLOB_BYTES (HANDOFF §5).

REPORT, with real numbers and real pasted output:
  - measured DataStore/MemoryStore request cost per session vs. the 5/session budget
    (doc 03 §6.3);
  - measured MemoryStore footprint vs. the 64 KB + 1.2 KB x users quota (doc 05 §1);
  - what every injected failure did to the economy invariants.

Claim L3 — "runs against a simulated platform". Do NOT claim real DataStore or
MemoryStore behaviour, and do not claim a Studio measurement you did not take. If
something is unverified, say so in a table like HANDOFF §3.

These commands must all pass, and their real output must be pasted into HANDOFF.md:
  node tidekeeper/tools/tidekeeper-quality-gate.js
  node tidekeeper/tools/tidekeeper-doc-gate.js
  node tidekeeper/tools/tidekeeper-determinism-scan.js
  node tidekeeper/tools/check-syntax.js tidekeeper/code
  node tidekeeper/tools/tidekeeper-smoke-test.js
  node tidekeeper/tools/tidekeeper-session-test.js

Finally: update ROADMAP.md (iteration 3 row, validation snapshot, open decisions),
rewrite HANDOFF.md in this file's shape, and write the iteration 4 prompt into it.
Use web search wherever a fact about the platform matters. Ask if you have questions.
```
