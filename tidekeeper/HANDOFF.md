# Handoff — TIDEKEEPER, iteration 11 (2026-10-02 UTC)

TIDEKEEPER is a cozy async island trading post for Roblox. The tide runs on a real
clock, and every visitor who arrives while you are offline is a real player's
drifter, delayed. It lives in `tidekeeper/`, entirely separate from VITRIOL, with
its own copy of the tooling. **65 Luau files, 15 012 lines. 1 828 executed
assertions across two suites, 0 failures**, and 1 241 of them run byte-for-byte in
both a real Luau 0.700 VM and fengari with identical results.

**Iteration 11 in one line: 54 of 86 config constants could be changed without a
single one of 1 755 assertions noticing — including every number in the economy
table, the longest design document in the project.**

---

## 0. Prompt for the next agent

See §9. It is also in `docs/12-ITERATION-PROMPTS.md`.

## 1. Verification level claimed

**L3.5.** Everything runs headless. **Nothing has ever run in Roblox Studio** — no
Instance created, no DataStore call real, no frame drawn, no human has seen this
game. L4/L5 have been blocked since iteration 4, and after this iteration I would
put it more strongly than previous handoffs have: every claim here rests on a fake
platform written by the same process that wrote the code, and a fake platform agrees
with its author by construction.

## 2. What is actually true

| Check | Real pasted output |
| --- | --- |
| quality gate | `TIDEKEEPER quality gate: 19/19 checks passed` |
| doc gate | `TIDEKEEPER doc gate: 183/183 checks passed` |
| syntax | `All 65 Luau file(s) parsed successfully.` |
| member-scan | `clean — every cross-module member resolves (808 checked)` |
| dead-write-scan | `clean — every field written to shared state is read somewhere (27 checked)` |
| orphan-scan | `clean — every exported function is called, or allowlisted with a reason (487 checked, 20 allowlisted)` |
| remote-scan | `clean — every remote is spoken by both sides (9 checked)` |
| dead-content-scan | `clean — every piece of player-facing content is reachable (92 checked)` |
| **mutation-scan** | `clean — every guarded constant is still pinned by a test (47 mutated, 37 known-unguarded)` |
| determinism-scan | `clean` |
| smoke-test | `TIDEKEEPER smoke test: 1242 passed, 0 failed, 0 static proof(s) failed` |
| session-test | `TIDEKEEPER session test: 586 passed, 0 failed` |
| luau-test | `TIDEKEEPER Luau test: 1241 passed, 0 failed, agrees with fengari` |
| luau-bench | `within budget (median 16.124 us, p99 21.191 us, catch-up 2892.7 us)` |

## 3. What was built

### Level seven: a value no test constrains

The six scans before this one ask questions the source can answer. This one cannot:
*does the suite actually check this?* is only answerable by breaking the code and
seeing whether anything notices.

**Two cheaper versions were tried first and both came back clean.** Recorded so the
next agent does not re-spend the hours:

| asked | result |
| --- | --- |
| assertions that never run (instrumented `debug.getinfo` vs static call sites) | **3 of 1130**, all legitimate `ok(false, ...)` failure branches |
| tests asserting on fields that do not exist (`member-scan` extended over `tools/tests`, which it had never covered) | **1615** refs, **0** problems |

**Mutation found what those could not.** Changing every scalar in `Config/` by one
and re-running all 1 755 assertions: **54 of 86 survived**. Among them every number
in the economy table — `STANDING_ON_SERVED`, `RENOWN_ON_GIFT`, `WARMTH_BASE_SERVED`,
`SPOIL_PER_MILLE`, `PASSIVE_RATE_PER_MILLE`. The iteration-7 balance pass tuned
values that no test would have noticed being wrong.

| path | what changed |
| --- | --- |
| `tools/tidekeeper-mutation-scan.js` | **new** — gate check 19, two modes |
| `tools/tests/pure-tests.lua` | **new** `EconomyPinning` and `BlobBudget` sections |
| `tools/tests/session-tests.lua` | scenarios 27 (the letter journey) and 28 (the screens) |
| `code/.../Client/ClientBootstrap.luau` | the shore's tide dial; `setAlmanacPage`, `previewOrders`, `orderChoices` |
| `tools/tidekeeper-orphan-scan.js` | the "client UI not built" category is now **empty**; 23 → 20 allowlisted |

### The trap this iteration is really about

```lua
eq(delta.warmth, EconomyConfig.WARMTH_BASE_SERVED, "...")   -- pins NOTHING
```

Mutate the config and both sides move together. **That is itself the vacuous test I
went looking for**, and it is the natural thing to write. A pin needs two halves: the
constant equals a **literal** (the tripwire), and the behaviour equals the constant
(which stops the literal becoming a lie). 47 constants are now guarded, up from 28.

### Cost forced a better design

A full run is ~90 minutes, which cannot sit in a 3-minute gate. So the default mode
re-mutates only the **already-guarded** set against the 0.8 s real-Luau suite (~30 s).
That is not a weaker full run — it answers a different and more useful question:
**has a test rotted?**

## 4. Decisions taken

**D50 — a pinned constant needs a literal and a behavioural link.** Neither half is
sufficient; only the first is what mutation rewards.

**D51 — test a new scan against a legitimate but unusual idiom before trusting it.**
Iteration 10 predicted this; iteration 11 proved it twice (below).

**D52 — a measurement must compare like with like, and say what it excluded.**

## 5. Where the docs were wrong

- **Doc 06**, the economy document, had *no* test behind any of its numbers. New
  §6.1 records that, explains the two-halves pinning rule, and warns that changing a
  number here will now fail a test on purpose.
- **Doc 10** had the ladder at six levels; now seven, plus §14 on the two clean
  negative results, the vacuous-pin trap, and the OD15 correction.
- **ROADMAP** closes OD15 with numbers and records D50–D52.

## 6. Two things I got wrong, and how they surfaced

**The OD15 measurement was 3.6× too flattering.** My first answer said base64 packing
beat JSON by 5.9× compressed. It built a post with a 200-entry resident ledger and
serialised that to JSON — but the post blob does not contain the ledger, which lives
in its own pages. I was comparing the packed blob against JSON of strictly more data.
The round-trip assertion caught it: `#backBS.ledger` threw, because a decoded post
has no ledger to count. Corrected: **3.06× raw, 1.63× compressed.** Keep the packing,
but the honest margin is 1.6×, and the better argument is that packing gives a hard
size *bound*, which is what makes the 6 144-byte budget enforceable at all.

**My own scan was brittle in exactly the way iteration 10 warned about.** Adding a
trailing comment to a config line made it report that the constant *"no longer
exists"* — and the same brittleness had been hiding two constants
(`GameConfig.OWNER_ID_MAX`, `TideConfig.SCAN_HORIZON`) from the scan entirely, so
they had never been mutated. Fixed and classified. The deliberate-idiom test is the
thing I would most recommend to whoever writes the next scan.

## 7. What iteration 11 was asked for and did not do

- **No Studio.** Unchanged since iteration 4, and now the largest gap by a wide
  margin — see §1 and the prompt.
- **37 constants remain unguarded**, each with an honest reason in the scan. The
  valuable ones are ceilings no scenario reaches (`MAX_ARRIVALS_PER_EPOCH`,
  `MAX_RESIDENT_DRIFTERS`, `VISITOR_RING_SIZE`, `MAX_CATCHUP_EPOCHS`).
- **The chart cannot be used to choose a current** — no remote exists for it, and
  inventing one at the end of an iteration would have been the wrong call.
- **OD19** (delete fengari) untouched.

## 8. Commands and their real output

```
TIDEKEEPER quality gate — iteration 11, source root tidekeeper/code (65 Luau file(s))

  ok  doc-gate           TIDEKEEPER doc gate: 183/183 checks passed
  ok  separation         no dependency on the VITRIOL tree
  ok  check-syntax       All 65 Luau file(s) parsed successfully.
  ok  metrics              59  code/ReplicatedStorage/Tidekeeper/Client/ClientBootstrap.luau
  ok  hot-loop-scan         1  :Clone (instance clone)
  ok  call-graph           ShowcaseService.new  <- Bootstrap
  ok  find-dead-config     ✓ no dead keys
  ok  member-scan        clean — every cross-module member resolves (808 checked)
  ok  dead-write-scan    clean — every field written to shared state is read somewhere (27 checked)
  ok  orphan-scan        clean — every exported function is called, or allowlisted with a reason (487 checked, 20 allowli
  ok  remote-scan        clean — every remote is spoken by both sides (9 checked)
  ok  dead-content-scan  clean — every piece of player-facing content is reachable (92 checked)
  ok  mutation-scan      clean — every guarded constant is still pinned by a test (47 mutated, 37 known-unguarded)
  ok  determinism-scan   clean
  ok  smoke-test         TIDEKEEPER smoke test: 1242 passed, 0 failed, 0 static proof(s) failed
  ok  session-test       TIDEKEEPER session test: 586 passed, 0 failed
  ok  luau-test          TIDEKEEPER Luau test: 1241 passed, 0 failed, agrees with fengari
  ok  luau-bench         TIDEKEEPER Luau bench: within budget (median 16.124 us, p99 21.191 us, catch-up 2892.7 us).
  ok  git-diff-check

TIDEKEEPER quality gate: 19/19 checks passed
```

Negative controls, because a check never seen to fail is not evidence:

- **deleting one pinning assertion** → `FAIL EconomyConfig.STANDING_ON_SERVED —
  GUARDED, but changing it from 34 breaks NO test. The assertion that pinned it is
  gone or weakened.`
- **adding an unclassified config constant** → `FAIL EconomyConfig.BRAND_NEW_KNOB —
  new config constant, not classified. Run --full and add it to GUARDED or
  UNGUARDED.`
- **the idiom test** (a trailing comment on `MIN_PRICE`) → `FAIL EconomyConfig.MIN_PRICE
  — listed as GUARDED but no longer exists in config`, which is how the two hidden
  constants were found.
- restored → `clean — every guarded constant is still pinned by a test`.

The dispatch/letters path was read end to end after three consecutive iterations of
defects there. **It is sound** — 120 ids, 120 texts, 7 categories, ceilings derived
from config on both sides. The gap was in the testing: every previous fix was
verified only at the link it touched. Scenario 27 now drives the whole chain, from
the picker to the words a stranger reads.

## 9. Prompt for iteration 12

```
You are iteration 12 of TIDEKEEPER, a Roblox game being built inside the
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
    It must print 19/19 before you change anything. If it does not, fixing
    that IS your iteration.
5.  Read tidekeeper/HANDOFF.md, then docs/10-RESEARCH-NOTES.md sections 12,
    13 and 14 -- the ladder, and what each level cost to find.

THE BIGGEST THING IS NO LONGER A SCAN.

Eleven iterations have built seven levels of scan and every one found
something real. That has been the right instinct and it is reaching its
limit. Here is the honest state of this project:

  * 1828 assertions, 0 failures, 19 gate checks, all green.
  * NOT ONE LINE HAS EVER RUN IN ROBLOX STUDIO. No Instance has been
    created. No DataStore call has been real. No frame has been drawn. No
    human has ever seen this game.

L4 and L5 have been blocked since iteration 4. Everything the project claims
rests on a fake platform written by the same process that wrote the code --
and a fake platform agrees with its author by construction. That is the
single largest risk here, and it is larger than anything another scan will
find.

SO, FIRST: IF YOU HAVE STUDIO ACCESS OR ANY WAY TO RUN REAL ROBLOX, DO THAT.
Build the place file, open it, press play, and write down exactly what breaks
-- it will not be nothing. Rojo is the expected route; the module map in
tools/lib/module-map.js is the single source of truth for where every file
belongs. Report what happened in plain language, including the parts that
embarrassed the design.

IF YOU DO NOT HAVE STUDIO ACCESS, DO NOT PRETEND OTHERWISE AND DO NOT
SUBSTITUTE ANOTHER SCAN FOR IT. Say so in the handoff in one plain sentence,
and spend the iteration on the highest-value work that does not need it:

  a. SHRINK THE UNGUARDED LIST. 37 config constants are still constrained by
     no test (see the UNGUARDED table in tools/tidekeeper-mutation-scan.js,
     each with an honest reason). The most valuable ones are the ceilings
     nothing reaches: MAX_ARRIVALS_PER_EPOCH, MAX_RESIDENT_DRIFTERS,
     MAX_STORE_ENTRIES, VISITOR_RING_SIZE, MAX_CATCHUP_EPOCHS. Each needs a
     scenario that actually saturates the limit, which is exactly the kind of
     scenario that finds real bugs. Promote what you pin, and remember the
     scan verifies the list in both directions.

  b. THE FAKE PLATFORM IS THE WEAKEST LINK. tools/tests/fake-platform.lua is
     where "it works" ultimately bottoms out, and nothing checks it against
     the real API surface. Compare it, member by member, against the
     published DataStore/MemoryStore/Players APIs -- argument counts, return
     shapes, what throws versus what returns nil, UpdateAsync transform
     semantics. Every place it is more forgiving than Roblox is a bug the
     suite cannot see. Use web search; the docs are current and you should
     cite what you check.

  c. OD19 is still open: delete fengari now that real Luau runs the suite, or
     write down why the two-VM cross-check still earns its keep.

RULES THAT HAVE NOT CHANGED.

  - Determinism (doc 04 section 5) is not negotiable.
  - No free text over the wire. Ids only.
  - The server owns prices (D46). The client displays, never computes.
  - Content is reachable or it does not exist (D48).
  - A pinned constant needs a literal AND a behavioural link (D50) -- an
    assertion against the constant alone is vacuous.
  - Test a new scan against a legitimate but unusual idiom (D51).
  - A measurement must compare like with like and say what it excluded (D52).
  - Every allowlist is verified in both directions (D44).
  - Paste real tool output. Never paraphrase it.
  - A partial honest result beats a complete claimed one. Always.

ON THE BENCH. Best-of-3, every sample printed, 18 us budget. Do not raise it
to make something pass.

ON THE MUTATION SCAN. The gate runs the guarded set only (~30 s). Run
`node tidekeeper/tools/tidekeeper-mutation-scan.js --full` if you add config
or want the whole picture; it takes about 90 minutes, so start it early and
do other work while it runs. It restores every file it touches, including on
failure -- if you interrupt it anyway, check `git status` before trusting the
tree.

FINISH BY.

  - Running the full gate and pasting it.
  - Updating the docs you invalidated, ROADMAP.md, and HANDOFF.md.
  - Writing the iteration-13 prompt into docs/12-ITERATION-PROMPTS.md and
    extending the doc gate's prompt loop to cover it.
  - Committing and pushing to your branch.
```
