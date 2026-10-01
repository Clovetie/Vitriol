# Handoff — TIDEKEEPER, iteration 9 (2026-10-01 UTC)

TIDEKEEPER is a cozy async island trading post for Roblox. The tide runs on a real
clock, and every visitor who arrives while you are offline is a real player's
drifter, delayed. It lives in `tidekeeper/`, entirely separate from VITRIOL, with
its own copy of the tooling. **62 Luau files, 14 389 lines. 1 718 executed
assertions across two suites, 0 failures**, and 1 200 of them run byte-for-byte in
both a real Luau 0.700 VM and fengari with identical results.

**Iteration 9 in one line: the client could start a session, receive pushes, and
perform no action whatsoever — five of six remotes had zero callers and two of
three payload builders would have been rejected on arrival — with all sixteen
checks green.**

---

## 0. Prompt for the next agent

See §9. It is also in `docs/12-ITERATION-PROMPTS.md`.

## 1. Verification level claimed

**L3.5.** Everything runs headless: the pure core and the full server against a fake
platform, plus a real Luau 0.700 VM cross-checking the pure suite. Nothing has run in
Roblox Studio — no Instance is created, no DataStore is real, no frame is drawn. L4
and L5 remain blocked on Studio access, as they have been since iteration 4.

## 2. What is actually true

| Check | Real pasted output |
| --- | --- |
| quality gate | `TIDEKEEPER quality gate: 17/17 checks passed` |
| doc gate | `TIDEKEEPER doc gate: 177/177 checks passed` |
| syntax | `All 62 Luau file(s) parsed successfully.` |
| member-scan | `clean — every cross-module member resolves (729 checked)` |
| dead-write-scan | `clean — every field written to shared state is read somewhere (27 checked)` |
| orphan-scan | `clean — every exported function is called, or allowlisted with a reason (468 checked, 24 allowlisted)` |
| **remote-scan** | `clean — every remote is spoken by both sides (8 checked)` |
| determinism-scan | `clean` |
| smoke-test | `TIDEKEEPER smoke test: 1201 passed, 0 failed, 0 static proof(s) failed` |
| session-test | `TIDEKEEPER session test: 517 passed, 0 failed` |
| luau-test | `TIDEKEEPER Luau test: 1200 passed, 0 failed, agrees with fengari` |
| luau-bench | `within budget (median 15.675 us, p99 24.344 us, catch-up 2863.8 us)` |

## 3. What was built

**The client can act.** `ClientBootstrap` gained one seam and six verbs:

| path | what changed |
| --- | --- |
| `code/ReplicatedStorage/Tidekeeper/Client/ClientBootstrap.luau` | `:act(remoteName, payload)` — invoke, check status, fold the reply, mark dirty — plus `:arrange`, `:comb`, `:setOrders`, `:dispatch`, `:upgrade`, `:upgradeOffer`; `AUTHORITATIVE_FIELDS`; `:statusText` now handles codes 3 and 4 |
| `code/ReplicatedStorage/Tidekeeper/Client/PostView.luau` | `arrangePayload` sends `findId`, not `find`; clamps to `EconomyConfig.MAX_PRICE`, not the storage u32 |
| `code/ReplicatedStorage/Tidekeeper/Client/DispatchView.luau` | `payload` rewritten to the real spec: seq, targets, letterId, cargo |
| `code/ReplicatedStorage/Tidekeeper/Client/LetterView.luau` | **new** — 120 letters in 7 categories, chosen by id |
| `code/ReplicatedStorage/Tidekeeper/Client/Strings.luau` | 10 new labels, including `ERR_ILLEGAL` and `ERR_COOLDOWN` |
| `code/ServerScriptService/Tidekeeper/RemoteHandlers/SessionHandler.luau` | the snapshot now carries `nextCost` |
| `code/ServerStorage/Tidekeeper/Adapters/MemoryAdapter.luau` | **new** `:tryLease(name, token, ttl)` |
| `code/ServerStorage/Tidekeeper/Services/ExchangeService.luau` | **new** `:reapTick(now)`, `REAP_AGE_EPOCHS`, `REAP_LEASE_TTL` |
| `code/ServerStorage/Tidekeeper/Services/Bootstrap.luau` | registers `exchange.reap` on the IO slot |
| `tools/tidekeeper-remote-scan.js` | **new** — gate check 17 |
| `tools/tidekeeper-luau-bench.js` | best-of-3, every sample printed |
| `tools/tests/session-tests.lua` | scenarios 21, 22, 23 |

### The find, in detail

Six client → server remotes existed. All six were bound on the server, rate-limited,
schema-checked and covered by session tests. The client invoked exactly **one** —
`RF_Session` — and then listened. Arranging a shelf, combing the beach, setting
standing orders, dispatching a drifter and buying a tier each had a complete, correct,
tested server half and **no way for a player to reach it**.

Underneath that, two of the three payload builders the client owned produced payloads
the server would have rejected outright — only possible because none had ever been
sent. Every spec is a **strict** map, so a misnamed field is a rejection, not a
warning:

| builder | sent | the spec wants |
| --- | --- | --- |
| `PostView.arrangePayload` | `find`, price clamped to 4294967295 | `findId`, `MAX_PRICE` = 4294967 — 1000× lower |
| `DispatchView.payload` | `slot`, `phrase`, cargo as id/qty pairs | `targets` array, `letterId`, cargo as plain ids |
| `OrdersView.setOrdersPayload` | — | already conformant |

And `statusText` mapped only codes 1 and 2, sending everything else to `ERR_OFFLINE`
— "Can't reach the post right now." A comb refused because the tide was wrong told
the player their connection had dropped. Nothing noticed, because no client code
could reach a remote that returns a 3 or a 4.

## 4. Decisions taken

**D45 — a client payload builder is validated against the server's own schema,
through `NetContract.accept`.** Never round-tripped against itself. Both broken
builders had tests; both tests agreed with the builder and not with the server.

**D46 — prices and costs cross the wire from the server; the client displays, never
computes.** `:upgrade()` sends the sequence number alone. `:upgradeOffer()` reads
`snapshot.nextCost`. A client that computes a price locally will eventually show one
number and charge another, which in a cozy game reads as dishonesty rather than as a
bug.

**The pool reaper takes a lease (OD21).** 5 Currents × 64 shards = 320 keys per
epoch; twenty servers deleting all 320 is twenty times the budget for one result. One
`reap:<epoch>` MemoryStore lease decides it. If MemoryStore is down, *nobody* reaps —
a missed reap is visible growth, twenty blind reapers during an outage is a quota
fire.

**The bench is best-of-3, and the budget did not move.** Unchanged code measured
15.8 µs standalone and 19.0 µs after a full gate, against 18 µs. Contention can only
inflate a measurement, so the minimum is the best estimate of the true cost; every
sample is printed so the spread is visible.

**`remote-scan` has no allowlist, deliberately.** Library surface and diagnostics can
legitimately be uncalled; a remote cannot. Both sides are in this repo.

## 5. Where the docs were wrong

- **Doc 05 §9** said neither reaper was scheduled and called the pool reaper a launch
  blocker. The pool reaper is now scheduled; the section is rewritten with the lease
  design, the arithmetic, and the outage behaviour. The *ledger* reaper is still not
  written and the doc now says only that.
- **Doc 08** described a client that "executes" (§8.3) without ever noting that it
  could not perform a single action. New §8.4 states the hole plainly, tabulates the
  three payload builders against the real specs, and records the `statusText` lie.
- **Doc 10** had no account of why each iteration keeps finding dead features. New
  §12 writes the ladder down as a rule, with the two implementation traps and the
  bench measurement problem.
- **ROADMAP** had OD21 open with "needs a decision about which server reaps" — now
  closed, with the answer. OD23 added.

## 6. What iteration 9 was asked for and did not do

- **OD22 is still open.** Ledger history is still written and never read. It needs a
  new remote, a handler, a client pager and a retention decision — a whole
  iteration's work, and doing it badly at the end of this one would have been worse
  than leaving it. It is item (a) of the iteration-10 prompt.
- **The screens are still thin.** The verbs exist; the views behind them are minimal.
  Several presentation helpers remain on the orphan allowlist, honestly labelled.
- **No Studio.** L4/L5 unchanged since iteration 4.

## 7. Open questions for iteration 10

- **OD22** — ledger history, including how far back to keep and what the player sees
  at the end of history.
- **OD23** — status code 4 means `E_COOLDOWN` from one handler and `E_ALREADY_OUT`
  from another. The client works around it; the contract should be fixed.
- **OD15** — is base64 packing still paying for itself?
- **Level six.** Which kind of dead feature can the five scans still not see? The
  iteration-10 prompt lists candidates; the one I would bet on is a session scenario
  that asserts only on values it computed itself.

## 8. Commands and their real output

```
TIDEKEEPER quality gate — iteration 9, source root tidekeeper/code (62 Luau file(s))

  ok  doc-gate           TIDEKEEPER doc gate: 177/177 checks passed
  ok  separation         no dependency on the VITRIOL tree
  ok  check-syntax       All 62 Luau file(s) parsed successfully.
  ok  metrics              58  code/ReplicatedStorage/Tidekeeper/Shared/PostCodec.luau
  ok  hot-loop-scan         1  :Clone (instance clone)
  ok  call-graph           ShowcaseService.new  <- Bootstrap
  ok  find-dead-config     ✓ no dead keys
  ok  member-scan        clean — every cross-module member resolves (729 checked)
  ok  dead-write-scan    clean — every field written to shared state is read somewhere (27 checked)
  ok  orphan-scan        clean — every exported function is called, or allowlisted with a reason (468 checked, 24 allowli
  ok  remote-scan        clean — every remote is spoken by both sides (8 checked)
  ok  determinism-scan   clean
  ok  smoke-test         TIDEKEEPER smoke test: 1201 passed, 0 failed, 0 static proof(s) failed
  ok  session-test       TIDEKEEPER session test: 517 passed, 0 failed
  ok  luau-test          TIDEKEEPER Luau test: 1200 passed, 0 failed, agrees with fengari
  ok  luau-bench         TIDEKEEPER Luau bench: within budget (median 17.647 us, p99 33.178 us, catch-up 3566.5 us).
  ok  git-diff-check

TIDEKEEPER quality gate: 17/17 checks passed
```

Negative controls run this iteration, because a check that has never been seen to
fail is not evidence:

- **remote-scan**: deleting the `RF_Upgrade` and `RF_Arrange` call sites produced
  exactly 2 FAILs and exit 1; restoring them returned it to clean.
- **the lease**: replacing `tryLease` with `true` made the second server duplicate
  **284** deletes, and session scenario 23 failed on all three of its lease
  assertions.
- **the orphan allowlist**: fixing `arrangePayload` and `setOrdersPayload` made their
  allowlist entries stale, and the scan failed on them until they were removed. That
  is D44 working on its author.

## 9. Prompt for iteration 10

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
