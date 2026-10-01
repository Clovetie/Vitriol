# Handoff — TIDEKEEPER, end of iteration 8

TIDEKEEPER is a cozy async island trading post for Roblox. The tide runs on a real
clock, and every visitor who arrives while you are offline is a real player's
drifter, delayed. It lives in `tidekeeper/`, entirely separate from VITRIOL, with
its own copy of the tooling. 61 Luau files, 13 931 lines. **1 417 executed
assertions across two suites, 0 failures**, and 1 200 of them run byte-for-byte in
both a real Luau 0.700 VM and fengari with identical results.

**Iteration 8 in one line: the last-resort safety net against losing a player's
save had never once been read, and the proof of the game's main security invariant
had never once run — with all fifteen checks green.**

---

## 1. Four more dead features

The iteration-8 prompt said to spend the first hour hunting a fifth dead feature
before building anything. That hour found four, and they are the same shape as the
ones found in iterations 6 and 7: **two modules that are each individually correct,
with the feature lost in the gap between them.**

### 1.1 The failed-save recovery queue was write-only — fixed

`DataStoreAdapter:savePost` pushes the payload onto a MemoryStore queue whenever a
write is abandoned, either because the session lock went stale or because the retry
budget ran out. It is the last line of defence against a player losing a session.

`popRecovery` and `ackRecovery` existed, were correct, and **were called by
nothing**. The net caught the blob and dropped it on the floor; the entry sat in
MemoryStore until its TTL expired. The comment directly above `pushRecovery` has
read *"so the next join can retry it"* since iteration 4.

`PostService:sweepRecovery` now drains it on an idle `slow` tick — only when this
server owes no save, so a healthy server pays one MemoryStore read and nothing more.

**The guard is the hard part, and it is the reason this took longer than writing
the drain.** By the time a blob is retried, the server that took the lock may have
written something newer; restoring blindly would *cause* the loss the queue exists
to prevent. So:

| Situation | Action |
| --- | --- |
| The player is resident on this server | **Defer** — we hold the lock and will write something newer ourselves |
| The stored post is newer than the queued blob | **Drop** — the entry is obsolete; acking it is the correct ending |
| Otherwise | **Restore**, then ack |

Two details that are easy to get wrong and are now pinned by tests:

* `DataStoreAdapter:restorePost` returns `nil` from its `UpdateAsync` transform when
  the stored value wins, which **aborts the write**. This project has shipped that
  behaviour as a *bug* twice; here it is exactly the semantics wanted.
* `ReadAsync` returns **one id for the whole batch**, so the ack is all-or-nothing.
  A batch containing anything deferred or failed is left unacked and the 30 s
  invisibility window re-presents it. Slower, and it cannot lose a blob.

### 1.2 The proof of the main security invariant never ran — fixed

doc 13 §2: no remote accepts a string field anywhere in its payload. Strings are the
arbitrary-content surface — the thing that turns a trade remote into an unmoderated
chat channel — so the contract is ids and numbers only.

`NetContract.hasNoStringFields()` walks the specs and proves it. **Nothing called
it**, while three separate comments in the codebase stated that the smoke test
asserted it. It is now asserted for real, with a canary that poisons `SPECS` to
prove the walker can actually fail rather than always returning true.

### 1.3 Ledger history is written and never read — documented, OD22

`LedgerService:flushPending` archives older entries into pages via `saveLedgerPage`.
`loadLedgerPage` exists to read them back, is called by nothing, and no remote asks
for history. **Every entry past `MAX_LEDGER_RESIDENT` (200) is archived and then
unreadable forever.** One of the archiving comments even says the page key is
"derivable from an entry's own epoch when reading history back" — the read path was
designed and never built.

Not fixed, because doing it properly needs a remote, a client pager and a retention
decision. Allowlisted with a reason and raised as **OD22**, so it can no longer be
mistaken for working.

### 1.4 The drifter pool is never reaped — documented, OD21

`DataStoreAdapter:reapPoolShard` is correct and scheduled by nobody, so the pool only
grows. Keys carry a TTL, so this is growth rather than a leak, but it is a launch
blocker against the 8.5 MB budget. Raised as **OD21**.

---

## 2. The scan that finds this class of defect

The member scan and the dead-write scan both check **fields**. A function that is
defined, correct, unit-tested and never called is invisible to both — every module
parses, type-checks and passes its tests, and the feature is simply missing from the
seam.

`tidekeeper-orphan-scan.js` is now **gate check 16**: 455 exported functions, each
either called somewhere in the game or in the test suites, or on an allowlist with a
written reason. Tests count as callers deliberately — a function exercised only by
tests is staged, not dead — but it must then carry a reason saying what will call it,
so "staged" cannot quietly become "forgotten".

**The allowlist is verified in both directions.** An orphan that is not on it fails
the scan; an entry on it that is *no longer* an orphan also fails, so the list cannot
rot into a pile of stale excuses. Same discipline as D39.

The 27 allowlisted entries are grouped by *why*: deliberate library surface,
diagnostics called from a console, teardown paths, UI payload builders blocked on a
client that does not exist, the two `NotifyService` functions blocked on OD7, and the
two compliance checks (`PolicyAdapter.mayTradePaidItems`,
`mayOfferPaidRandomItems`) that are dormant only because nothing in the game takes
money — if that ever changes, they **must** gate it.

It immediately found dead code **in the badge module written in the same session** —
two helpers defined and never used. They were deleted, not allowlisted.

**The scans have now followed this defect up one level per iteration:**

| Iteration | Scan | Catches |
| --- | --- | --- |
| 6 | `member-scan` | a field **read** that is never written |
| 7 | `dead-write-scan` | a field **written** that is never read |
| 8 | `orphan-scan` | a **function** defined that is never called |

Iteration 9's first job is to find the next level. The prompt lists candidates.

---

## 3. Badges are awarded — schema v3

The 40 badges have existed as data since iteration 7 and nothing awarded them.

* `S.stats` gained six lifetime counters (`lettersSent`, `lettersReceived`,
  `giftsGiven`, `driftersDispatched`, `tidesElapsed`, and `tideStatesSeen`, which is
  a 5-bit mask rather than a count — seeing LOW twice is not seeing two states).
* `S.badges` is a 40-bit mask, five bytes. Badge id 1 is byte 1 bit 0; **ids are
  persisted bit indices and are never renumbered.**
* `SCHEMA_VERSION` is **3**, with a real `v2 -> v3` migration. New fields arrive
  **zeroed, never backfilled** — we genuinely do not know how many letters a pre-v3
  player sent, and guessing would hand out achievements nobody earned. `tidesElapsed`
  is the one that stings: a long-standing player restarts that count at zero.
  Backfilling it from `resolvedAt` was considered and rejected, because it would award
  the long-absence badges to someone who had merely been away.
* Six of the twelve badge stats are **derived** from state the post already holds
  (`tierReached`, `shelvesUnlocked`, `almanacEntries`, `currentsUnlocked`, and the two
  original counters), so they cost no bytes and cannot drift out of sync.
* `Resolve.run` evaluates once at the end of the whole resolve, not per epoch: every
  threshold reads a monotone counter, so the answers agree and it is a fraction of the
  work. The newly earned ids come back as `info.badgesEarned`.

### 3.1 Wiring it up exposed a defect in the data

**A brand-new post immediately earned three badges.** `shelvesUnlocked` is
`tier * 6`, so a tier-1 post starts with six shelves and walked straight past "Second
Shelf" (threshold 2) and "Full House" (6); `currentsUnlocked` starts at 1 and walked
past "Coldwater Regular" (1).

The ladders had been written against the plain English of the badge names rather than
against the values the stats can actually take — `shelvesUnlocked` only ever takes
6/12/18/24, and `currentsUnlocked` only 1/3/4/5. Nothing noticed for an iteration
because nothing had ever evaluated them.

Ids 11–15 and 34–37 were repurposed. **That was safe only because no badge had ever
been awarded to anybody**; from the first live award onwards, a row may have its name
changed and nothing else. Two rules are now pinned by tests:

1. a new post earns **nothing** — the first badge must cost the player an act;
2. every threshold is a value its stat can actually **reach**.

### 3.2 A real v2 fixture, captured at the last possible moment

`tools/fixture-blobs/post-v2.b64` (238 bytes) was captured from a git worktree at
commit `4e8b1a1` — the last code whose `PostCodec` still wrote v2 — **in the same
session that raised `SCHEMA_VERSION` to 3**. That is the last moment it could be
captured at all: once the encoder moves, old bytes can only be hand-forged, and a
forged fixture proves nothing about what the old code really wrote. A round-trip test
encodes and decodes with the *same* code and so agrees with itself by construction,
including after a change that orphans every live save.

The v1 fixture now migrates v1 → v2 → v3 and both are asserted field by field.

---

## 4. Commands and their real output

```
TIDEKEEPER quality gate — iteration 8, source root tidekeeper/code (61 Luau file(s))

  ok  doc-gate           TIDEKEEPER doc gate: 174/174 checks passed
  ok  separation         no dependency on the VITRIOL tree
  ok  check-syntax       All 61 Luau file(s) parsed successfully.
  ok  metrics              58  code/ReplicatedStorage/Tidekeeper/Shared/PostCodec.luau
  ok  hot-loop-scan         1  :Clone (instance clone)
  ok  call-graph           ShowcaseService.new  <- Bootstrap
  ok  find-dead-config     ✓ no dead keys
  ok  member-scan        clean — every cross-module member resolves (695 checked)
  ok  dead-write-scan    clean — every field written to shared state is read somewhere (27 checked)
  ok  orphan-scan        clean — every exported function is called, or allowlisted with a reason (455 checked, 27 allowli
  ok  determinism-scan   clean
  ok  smoke-test         TIDEKEEPER smoke test: 1201 passed, 0 failed, 0 static proof(s) failed
  ok  session-test       TIDEKEEPER session test: 217 passed, 0 failed
  ok  luau-test          TIDEKEEPER Luau test: 1200 passed, 0 failed, agrees with fengari
  ok  luau-bench         TIDEKEEPER Luau bench: within budget (median 13.209 us, p99 21.269 us, catch-up 2391.4 us).
  ok  git-diff-check

TIDEKEEPER quality gate: 16/16 checks passed
```

The sim is deliberately **not** in the gate (it takes about two minutes):

```
node tidekeeper/tools/tidekeeper-session-test.js --tests tools/tests/economy-sim.lua
```

**Prerequisites each turn.** The working tree is reset to the session base between
turns, so iteration 8's commits exist only on the remote:

```
git fetch && git reset --hard origin/<branch>
cd tidekeeper/tools && npm install
git clone --depth 1 --branch 0.700 https://github.com/luau-lang/luau /tmp/luau
make -C /tmp/luau config=release luau -j$(nproc)
cp /tmp/luau/luau tidekeeper/tools/bin/luau
```

Without the Luau binary the gate shows 14/16 and two skips. That is correct, not a
failure.

---

## 5. What is *not* verified, stated plainly

**Studio has been unreachable for eight consecutive iterations.** No `DISPLAY`, no
`rojo`, no `lune`, no `lute`. Nothing here has run inside Roblox.

* **Verification level claimed: L3.5** — real Luau 0.700 executing the real modules,
  with a fake platform layer. Not L4 (Studio), not L5 (a live server).
* The client has **never been rendered**. Its payload builders are exercised by tests
  against the real server, and that is all.
* Performance numbers come from the bench harness on this machine, not from a Roblox
  server: median 13.2 µs against an 18 µs budget, p99 21.3 µs against 50 µs, full
  catch-up 2.4 ms against 12 ms.
* The recovery sweep is proven against `fake-platform.lua`'s MemoryStore queue, which
  implements the batch-id semantics faithfully — but no real MemoryStore has ever been
  called.
* Nothing above L3.5 may be claimed without Studio.

---

## 6. What iteration 8 was asked for and did not do

* **Client UI for `RF_Upgrade`, the letter picker, and `letterText`.** Not built. The
  dead-feature hunt found four things instead of the expected one, and fixing the
  data-loss path and shipping badges with a schema migration consumed the iteration.
  This is now the **headline task for iteration 9**, and the imbalance is real: the
  server is well ahead of the client.
* **OD21 and OD22** are raised and documented rather than closed.
* `economy-sim.lua` was not re-run, because no income number moved: badges award no
  coin and the recovery sweep touches no economy value.

---

## 7. Decisions iteration 8 made

* **D40** — a lifetime counter may be read by a badge; a balance may not. doc 06 says
  an achievement is never revoked, so a badge may only ever read a quantity that
  cannot go down. This is why `S.coin` is deliberately unreadable by the badge system.
* **D41** — prefer a **derived** stat over a counted one. A counter incremented in one
  place and read in another is precisely the shape of bug three scans now exist to
  catch; six of the twelve badge stats are derived and therefore cannot drift.
* **D42** — before changing the save schema, capture a fixture of the **outgoing**
  version first, from the code that still writes it.
* **D43** — a threshold must be a value its stat can reach, and must not already be
  true at birth. Both are pinned by tests, not by review.
* **D44** — an allowlist that silences a check must be verified in both directions,
  or it becomes a place to hide findings.

---

## 8. Open questions for iteration 9

| # | Question | Recommendation |
| --- | --- | --- |
| **OD21** | The pool reaper is never scheduled | Schedule it, but decide *which* server reaps — every server reaping every shard is a quota fire. One shard per slow tick, jittered by `jobId`. |
| **OD22** | Ledger history is archived and unreadable | Build it. The Ledger carries this game's entire emotional argument; silently losing its history is worse than it sounds. Needs a remote, a pager, and a retention answer. |
| OD15 | Does base64 packing still pay? | Measure, do not redesign. Sizes are far inside budget. |
| OD18 | LibMP for client frame budget | Still blocked on Studio. |
| OD19 | Delete fengari | Not yet. The two-VM cross-check is an asset, not debt. |
| OD20 | Dispatch fields are session-scoped | **Closed: leave as is.** A re-pick costs one tap; persisting costs a schema field. |
| OD7 | Turn-based notifications | **Closed.** The send half of the API does not exist. Re-open only if `CreateUserNotificationAsync` reappears. |

---

## 9. Prompt for iteration 9

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
