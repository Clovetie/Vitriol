# Handoff — TIDEKEEPER, iteration 12 (2026-10-03 UTC)

TIDEKEEPER is a cozy async island trading post for Roblox. The tide runs on a real
clock, and every visitor who arrives while you are offline is a real player's
drifter, delayed. It lives in `tidekeeper/`, entirely separate from VITRIOL, with
its own copy of the tooling. **65 Luau files, 15 036 lines. 1 901 executed
assertions across two suites, 0 failures**, and 1 266 of them run byte-for-byte in
both a real Luau 0.700 VM and fengari with identical results.

**Iteration 12 in one line: the fake platform was more forgiving than Roblox in five
ways, and one of them was hiding a bug that would have deleted players' ledger
history in production.**

---

## 0. Prompt for the next agent

See §9. It is also in `docs/12-ITERATION-PROMPTS.md`.

## 1. Verification level claimed

**L3.5. I had no Studio access, so L4/L5 are unchanged since iteration 4 — nothing
in this project has ever created an Instance, made a real DataStore call, or drawn a
frame.** The prompt asked me to say that in one plain sentence rather than substitute
another scan for it, so that is the sentence.

What I did instead was audit the floor underneath every other claim.

## 2. What is actually true

| Check | Real pasted output |
| --- | --- |
| quality gate | `TIDEKEEPER quality gate: 19/19 checks passed` |
| doc gate | `TIDEKEEPER doc gate: 186/186 checks passed` |
| syntax | `All 65 Luau file(s) parsed successfully.` |
| member-scan | `clean — every cross-module member resolves (808 checked)` |
| dead-write-scan | `clean — every field written to shared state is read somewhere (27 checked)` |
| orphan-scan | `clean — every exported function is called, or allowlisted with a reason (487 checked, 20 allowlisted)` |
| remote-scan | `clean — every remote is spoken by both sides (9 checked)` |
| dead-content-scan | `clean — every piece of player-facing content is reachable (92 checked)` |
| mutation-scan | `clean — every guarded constant is still pinned by a test (52 mutated, 32 known-unguarded)` |
| determinism-scan | `clean` |
| smoke-test | `TIDEKEEPER smoke test: 1267 passed, 0 failed, 0 static proof(s) failed` |
| session-test | `TIDEKEEPER session test: 634 passed, 0 failed` |
| luau-test | `TIDEKEEPER Luau test: 1266 passed, 0 failed, agrees with fengari` |
| luau-bench | `within budget (median 13.12 us, p99 15.276 us, catch-up 2308.5 us)` |

## 3. What was built

### The fake platform was lying

`tools/tests/fake-platform.lua` is where "it works" ultimately bottoms out, and
nothing had ever checked it against the real API. Five divergences, **every one in
the direction of being more permissive than Roblox**:

| # | the fake did | Roblox does |
| --- | --- | --- |
| 1 | called each DataStore transform **once** | re-runs it on contention, discarding earlier results |
| 2 | same for MemoryStore | same |
| 3 | defaulted a missing expiration to **45 s** | expiration is required |
| 4 | no expiration ceiling | rejects past 45 days (3 888 000 s) |
| 5 | accepted `SetAsync(key, nil)` as a remove | errors; only `RemoveAsync` deletes |

A fake that is *stricter* than production produces false alarms, which get noticed. A
fake that is *looser* produces false confidence, which does not. Sources and quotes
in doc 10 §15.1.

### What divergence 1 was hiding

`allocLedgerPage` appends evicted page numbers to `dropped`, and `LedgerService`
deletes **exactly** the keys that list names. It — and `drainReceipts` — reset their
accumulator in the `attempt` retry wrapper, which covers *this adapter* retrying, and
**not inside the transform**, which is where Roblox's own re-run happens.

On any contended write the reaper would have been handed each evicted page two or
three times and deleted pages **still in the index**: silent loss of a player's
history, in the one system whose whole purpose is remembering. Worse, the code was
two iterations old and already carried the comment *"Reset on retry: UpdateAsync may
run the transform more than once"* — in the wrong place.

Transform re-runs are now **on by default** in the fake, not opt-in. Production
always has this possibility.

| path | what changed |
| --- | --- |
| `tools/tests/fake-platform.lua` | all five divergences; `transformRetries` defaults to 1 |
| `code/.../Adapters/DataStoreAdapter.luau` | resets moved **inside** both transforms |
| `tools/tests/session-tests.lua` | scenario 29 — fails `got 2.0, expected 0.0` against the old code |
| `tools/tests/pure-tests.lua` | new `Saturation` section |
| `tools/tidekeeper-mutation-scan.js` | five ceilings promoted; guarded 47 → 52 |

### A limit never reached is a limit never tested

Most of iteration 11's unguarded constants had the same excuse: *"no scenario reaches
the cap"*. The `Saturation` section fills `MAX_STORE_ENTRIES`, `VISITOR_RING_SIZE`,
`MAX_ARRIVALS_PER_EPOCH`, `MAX_CATCHUP_EPOCHS` and `MAX_RESIDENT_DRIFTERS`, and also
checks that a **saturated post still survives the codec** — the failure where a cap
and a codec bound disagree and saving a maxed-out post destroys it.

## 4. Decisions taken

**D53 — an `UpdateAsync` transform must be re-entrant.** Anything it accumulates into
is reset as its first statement, never in the surrounding retry wrapper. Doc 05 §9.3.

**D54 — a test double must never be more permissive than the thing it doubles.**
Where the real API errors, the fake errors.

## 5. OD19 closed, for a reason nobody had stated

The question was "delete fengari now that real Luau runs the suite". The answer is
**keep it**, and the two-VM cross-check is only the secondary argument:

| suite | assertions | VM |
| --- | --- | --- |
| smoke | 1 267 | fengari only |
| session | 634 | fengari only |
| luau-test | 1 266 | real Luau 0.700 (bundled pure suite) |

Deleting fengari deletes **1 901 assertions**, including the whole
server-against-fake-platform layer. The real question is the inverse, and it is the
next iteration's main job: port the session harness to bundled Luau so the fake
platform runs on the actual target VM.

## 6. Where the docs were wrong

- **Doc 05** said nothing about transform re-entrancy. New §9.3 states the rule and
  tabulates both bugs.
- **Doc 10** gains §15: the sources, the five divergences, what divergence 1 hid, and
  the OD19 numbers.
- **ROADMAP** closes OD19, records iteration 12, adds D53–D54.

## 7. What iteration 12 did not do

- **Studio.** No access. Unchanged since iteration 4.
- **32 constants remain unguarded.** The `NotifyConfig` block is inert until OD7's
  send API exists; the interesting ones left are `MAX_COIN`, `MAX_LEDGER_RESIDENT`,
  `MAX_ORDERS_BYTES` and `OWNER_ID_MAX`.
- **The rest of the fake platform is unaudited** — the queue, pagination,
  `GetRangeAsync` bounds, and what each call returns on a missing key.

## 8. Commands and their real output

```
TIDEKEEPER quality gate — iteration 12, source root tidekeeper/code (65 Luau file(s))

  ok  doc-gate           TIDEKEEPER doc gate: 186/186 checks passed
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
  ok  mutation-scan      clean — every guarded constant is still pinned by a test (52 mutated, 32 known-unguarded)
  ok  determinism-scan   clean
  ok  smoke-test         TIDEKEEPER smoke test: 1267 passed, 0 failed, 0 static proof(s) failed
  ok  session-test       TIDEKEEPER session test: 634 passed, 0 failed
  ok  luau-test          TIDEKEEPER Luau test: 1266 passed, 0 failed, agrees with fengari
  ok  luau-bench         TIDEKEEPER Luau bench: within budget (median 13.12 us, p99 15.276 us, catch-up 2308.5 us).
  ok  git-diff-check

TIDEKEEPER quality gate: 19/19 checks passed
```

The negative control for the bug is the bug itself: against the pre-fix adapter,
session scenario 29 reports

```
FAIL  a dropped page is reported exactly once, not once per transform run  -- got 2.0, expected 0.0
```

and with the resets moved inside the transforms the suite returns `634 passed, 0
failed`. The five ceilings were likewise confirmed by the mutation scan promoting
them from UNGUARDED to GUARDED and still reporting clean.

**A process note that cost real work.** Iteration 11's commits were made in a sandbox
whose GitHub token had expired, so they existed only locally; the sandbox was then
recycled and the git history was gone. The working tree survived via the workspace
snapshot, so iteration 11 was recovered by resetting the branch pointer to
`origin` **without** touching files (`git reset`, never `git reset --hard`) and
re-committing. The iteration-13 prompt now says to check `git log` before resetting,
and to push early.

## 9. Prompt for iteration 13

```
You are iteration 13 of TIDEKEEPER, a Roblox game being built inside the
Clovetie/Vitriol repository. Work only on your session's fixed branch. Never
touch the VITRIOL tree: TIDEKEEPER is entirely inside tidekeeper/.

START HERE, IN THIS ORDER.

1.  git fetch && git reset --hard origin/<your branch>. The working tree is
    reset to the session base between turns, so the previous iteration's
    commits exist only on the remote. CHECK `git log` BEFORE YOU RESET: if
    the previous turn could not push, the commits exist only in the working
    tree and a hard reset destroys them. This happened between iterations 11
    and 12.
2.  cd tidekeeper/tools && npm install
3.  Build Luau 0.700 into tidekeeper/tools/bin/luau (about 3-4 minutes):
      git clone --depth 1 --branch 0.700 https://github.com/luau-lang/luau /tmp/luau
      make -C /tmp/luau config=release luau -j$(nproc)
      cp /tmp/luau/luau tidekeeper/tools/bin/luau
4.  node tidekeeper/tools/tidekeeper-quality-gate.js
    It must print 19/19 before you change anything.
5.  Read tidekeeper/HANDOFF.md, then docs/10-RESEARCH-NOTES.md section 15 and
    docs/05-PERSISTENCE.md section 9.3.

STUDIO FIRST, IF YOU CAN. L4/L5 have been blocked since iteration 4. Nothing
here has ever created an Instance, made a real DataStore call, or drawn a
frame. If you can run real Roblox, that outranks everything below: build the
place (tools/lib/module-map.js is the single source of truth for where each
file belongs), press play, and report exactly what breaks. If you cannot,
say so in one plain sentence and do the work below instead. Do not dress up
a substitute as the real thing.

YOUR MAIN JOB: PORT THE SESSION HARNESS TO REAL LUAU.

Iteration 12 closed OD19 by discovering that fengari is load-bearing:

    smoke      1267 assertions   fengari only
    session     634 assertions   fengari only
    luau-test  1266 assertions   real Luau 0.700 (bundled pure suite)

So two thirds of this project's evidence runs on a Lua 5.3 VM that is NOT
the target runtime, with four shims and every numeric literal rewritten to a
float. The pure suite already proves the bundling approach works
(tidekeeper-luau-test.js builds one .luau file and runs it). Extend it to
the session suite: bundle fake-platform.lua and session-tests.lua the same
way and run them under tools/bin/luau.

Why this is worth an iteration: iteration 12 found that the fake platform
had been lying about UpdateAsync semantics, and that this hid a real
data-loss bug. The fake is the floor under everything. Running it on the
actual target VM removes a whole class of "works in fengari" from under that
floor -- and the number semantics differ, which is exactly where a game that
is integer-only by decree (D14) should want certainty.

Expect this to find real divergences. Report them; they are the point. If
the port turns out to be genuinely impossible, say WHY in specific terms
(which global, which shim, which primitive) rather than giving up vaguely,
and that write-up is itself a good result.

THEN, IF THERE IS TIME.

  a. 32 constants remain unguarded (the UNGUARDED table in
     tools/tidekeeper-mutation-scan.js). The NotifyConfig block is inert
     until OD7's send API exists and can stay. The interesting ones left are
     MAX_COIN, MAX_LEDGER_RESIDENT, MAX_ORDERS_BYTES and
     GameConfig.OWNER_ID_MAX -- each needs a scenario that actually reaches
     the limit, which is where iteration 12 found its bugs.

  b. Audit the REST of fake-platform.lua the way iteration 12 audited
     UpdateAsync: the queue, ListKeysAsync/ListItemsAsync pagination,
     GetRangeAsync bounds, and what each call returns on a missing key.
     Divergences in the forgiving direction are bugs (D54). Use web search
     and cite what you check.

RULES THAT HAVE NOT CHANGED.

  - Determinism (doc 04 section 5) is not negotiable.
  - No free text over the wire. Ids only.
  - The server owns prices (D46). The client displays, never computes.
  - Content is reachable or it does not exist (D48).
  - A pinned constant needs a literal AND a behavioural link (D50).
  - Test a new scan against a legitimate but unusual idiom (D51).
  - Compare like with like, and say what you excluded (D52).
  - An UpdateAsync transform must be re-entrant (D53).
  - A test double must never be more permissive than the real thing (D54).
  - Paste real tool output. Never paraphrase it.
  - A partial honest result beats a complete claimed one. Always.

ON THE BENCH. Best-of-3, every sample printed, 18 us budget. Do not raise it.

ON THE MUTATION SCAN. The gate runs the guarded set (~30 s). `--full` is
about 90 minutes; start it early and work while it runs. It restores every
file it touches, but check `git status` if you interrupt it.

FINISH BY.

  - Running the full gate and pasting it.
  - Updating the docs you invalidated, ROADMAP.md, and HANDOFF.md.
  - Writing the iteration-14 prompt into docs/12-ITERATION-PROMPTS.md and
    extending the doc gate's prompt loop to cover it.
  - Committing and pushing to your branch. Push EARLY -- do not leave the
    only copy of an iteration's work in a sandbox.
```
