# Handoff — TIDEKEEPER, iteration 10 (2026-10-02 UTC)

TIDEKEEPER is a cozy async island trading post for Roblox. The tide runs on a real
clock, and every visitor who arrives while you are offline is a real player's
drifter, delayed. It lives in `tidekeeper/`, entirely separate from VITRIOL, with
its own copy of the tooling. **65 Luau files, 14 967 lines. 1 755 executed
assertions across two suites, 0 failures**, and 1 200 of them run byte-for-byte in
both a real Luau 0.700 VM and fengari with identical results.

**Iteration 10 in one line: the Ledger — the screen carrying this game's whole
argument — had been archiving history to a key nothing could read, and 18 of 51
player-facing labels could never reach a player's eyes, including the entire
navigation bar.**

---

## 0. Prompt for the next agent

See §9. It is also in `docs/12-ITERATION-PROMPTS.md`.

## 1. Verification level claimed

**L3.5.** Everything runs headless: the pure core and the full server against a fake
platform, plus a real Luau 0.700 VM cross-checking the pure suite. **Nothing has ever
run in Roblox Studio** — no Instance has been created, no DataStore call has been
real, no frame has been drawn. L4 and L5 have been blocked since iteration 4 and this
is now the single largest gap in what this project can claim.

## 2. What is actually true

| Check | Real pasted output |
| --- | --- |
| quality gate | `TIDEKEEPER quality gate: 18/18 checks passed` |
| doc gate | `TIDEKEEPER doc gate: 180/180 checks passed` |
| syntax | `All 65 Luau file(s) parsed successfully.` |
| member-scan | `clean — every cross-module member resolves (803 checked)` |
| dead-write-scan | `clean — every field written to shared state is read somewhere (27 checked)` |
| orphan-scan | `clean — every exported function is called, or allowlisted with a reason (484 checked, 23 allowlisted)` |
| remote-scan | `clean — every remote is spoken by both sides (9 checked)` |
| **dead-content-scan** | `clean — every piece of player-facing content is reachable (92 checked)` |
| determinism-scan | `clean` |
| smoke-test | `TIDEKEEPER smoke test: 1201 passed, 0 failed, 0 static proof(s) failed` |
| session-test | `TIDEKEEPER session test: 554 passed, 0 failed` |
| luau-test | `TIDEKEEPER Luau test: 1200 passed, 0 failed, agrees with fengari` |
| luau-bench | `within budget (median 15.537 us, p99 24.001 us, catch-up 2883.7 us)` |

## 3. What was built

### Level six: content a player can never see

`tools/tidekeeper-dead-content-scan.js`, gate check 18. It checks four things:

1. every `Strings.UI` key is displayed by something;
2. every `Format.label("KEY")` names a key that **exists** (a missing key returns `""`
   and counts a silent miss, so a typo is a blank label and no error anywhere);
3. every Ledger template has a prose row;
4. every prose row has a template.

**On its first run, 18 of 51 UI labels were dead.** Checks 3 and 4 were already clean
and now stay clean. Table of what was dead, and what it meant, in doc 08 §8.5.

| path | what changed |
| --- | --- |
| `tools/tidekeeper-dead-content-scan.js` | **new** — check 18, with its own `stripComments()` |
| `code/.../Client/ChartView.luau` | **new** — the five Currents and which your tier has earned |
| `code/.../Client/AlmanacView.luau` | **new** — 200 finds, paged 50 at a time |
| `code/.../Client/ClientBootstrap.luau` | the navigation bar; `:history()`; the in-flight guard; `statusText` simplified |
| `code/.../Client/LedgerView.luau` | group headings, the skip affordance, `LedgerView.archive`; dead `PHRASES` export removed |
| `code/.../Client/DispatchView.luau` | cargo label; `Strings.PHRASE` replaced with `LetterView.categories()` |
| `code/.../Client/Strings.luau` | `Strings.PHRASE` (12 rows) and `DISPATCH_PHRASE` deleted |
| `code/.../Client/PostView.luau`, `OrdersView.luau` | the missing control labels, and a real rule limit per tier |
| `code/.../Shared/NetContract.luau` | the status enum; `RF_History` row and `SPEC_HISTORY` |
| `code/.../RemoteHandlers/HistoryHandler.luau` | **new** |
| `code/.../Adapters/DataStoreAdapter.luau` | `allocLedgerPage`, `loadLedgerIndex`, `removeLedgerPage` |
| `code/.../Services/LedgerService.luau` | atomic page allocation; `:history()`; the ledger reaper |
| `tools/tests/session-tests.lua` | scenarios 24, 25, 26 |

### Following one dead label found a dead content table

`DISPATCH_PHRASE` led to `Strings.PHRASE` — 12 canned lines from the design that
preceded letters. Iteration 7 replaced phrases with 120 real letters and `letterId`;
for three iterations afterwards `DispatchView.build` and `LedgerView.PHRASES` were
still handing the renderer a choice the wire could no longer carry. Deleted.

### OD22 — the Ledger remembers

`loadLedgerPage` was called by nothing, so every entry past `MAX_LEDGER_RESIDENT`
(200) was archived and unreadable forever. For this game that is the worst available
bug rather than a missing feature: doc 00's first pillar is *absence is content*, and
the Ledger is where absence becomes content.

**There was no way to read it back even in principle** — page keys were
`l:<userId>:<epoch>` and nothing recorded which epochs had pages. **And the epoch was
not a safe key:** `saveLedgerPage` overwrites, so two servers flushing for one player
inside a 6.2-hour epoch — an ordinary server hop — silently destroyed one of the two
pages. Design table in doc 05 §9.2.

### OD23 — one status enum

Code 4 meant `E_COOLDOWN` from `PostHandler` and `E_ALREADY_OUT` from
`DispatchHandler`. `NetContract` now owns the enum, `E_ALREADY_OUT` moved to 5, and
`statusText` lost its remote-name parameter.

## 4. Decisions taken

**D47 — a scan must blank whatever can lie to it and keep whatever carries meaning.**
Iteration 9's "parse from raw, detect in stripped" was the special case, not the
principle. Here the thing being *detected* is a string literal, so stripping erases
every call site and raw text lets comments vote. Doc 10 §13.2.

**D48 — content is reachable or it does not exist.** Both directions: a label nothing
displays, and a `Format.label` naming a key that is not there.

**D49 — one action in flight at a time.** `invoke` yields; a second tap races the
first reply into the snapshot. `ERR_BUSY` is truthful and kinder than letting the
rate limiter call it a rejection.

**Retention is 32 pages, and the reaper runs where the information already is.** The
page numbers falling out of the index come back from the allocation call, so deleting
them costs no scan and no schedule.

**The archive cursor counts back from the newest page.** Counted from the oldest it
would slide under a reader every time a page was reaped.

## 5. Where the docs were wrong

- **Doc 05 §9** said the ledger reaper was "deletes pages older than 180 days on the
  owner's own load" — a design that was never written and would not have worked,
  since nothing knew which pages existed. Replaced with §9.2: numbering, reading,
  retention, and the cross-server overwrite it fixed.
- **Doc 08** described screens that rendered nothing. New §8.5 lists all 18 dead
  labels and what each one's absence meant; §8.6 covers the archive view.
- **Doc 10** had the ladder at five levels. Now six, plus §13 on why the iteration-9
  parsing rule had to be generalised rather than reused.
- **ROADMAP** closes OD22 and OD23 and records D47–D49.

## 6. What iteration 10 was asked for and did not do

- **Level seven was not attempted.** The prompt asked for one scan and I wrote it;
  the candidate I most believe in — *a test that cannot fail* — is written up as the
  first job of iteration 11. With 1 755 assertions, if even a handful are vacuous the
  suite's authority is overstated by exactly that much and nobody knows which ones.
- **The new screens have no interaction.** `AlmanacView` pages but nothing calls it
  with page 2; `ChartView` shows locks but cannot be used to choose a current.
- **OD15** (is base64 packing still paying for itself?) is untouched and is now the
  oldest open question.
- **No Studio.** Unchanged since iteration 4.

## 7. Open questions for iteration 11

- **Level seven**, and specifically the vacuous-test question above.
- **OD15** — base64 packing vs DataStore's own compression. Cheap to answer with
  numbers now; close it either way.
- **The dispatch/letters path has produced a defect in three consecutive
  iterations** (7: letters could never travel; 9: the payload builder was
  non-conformant; 10: the screen offered a superseded phrase table). Read it as a
  whole rather than trusting that the last fix finished the job.
- **Studio.** L3.5 must not be allowed to drift into sounding like "it works".

## 8. Commands and their real output

```
TIDEKEEPER quality gate — iteration 10, source root tidekeeper/code (65 Luau file(s))

  ok  doc-gate           TIDEKEEPER doc gate: 180/180 checks passed
  ok  separation         no dependency on the VITRIOL tree
  ok  check-syntax       All 65 Luau file(s) parsed successfully.
  ok  metrics              58  code/ReplicatedStorage/Tidekeeper/Shared/PostCodec.luau
  ok  hot-loop-scan         1  :Clone (instance clone)
  ok  call-graph           ShowcaseService.new  <- Bootstrap
  ok  find-dead-config     ✓ no dead keys
  ok  member-scan        clean — every cross-module member resolves (803 checked)
  ok  dead-write-scan    clean — every field written to shared state is read somewhere (27 checked)
  ok  orphan-scan        clean — every exported function is called, or allowlisted with a reason (484 checked, 23 allowli
  ok  remote-scan        clean — every remote is spoken by both sides (9 checked)
  ok  dead-content-scan  clean — every piece of player-facing content is reachable (92 checked)
  ok  determinism-scan   clean
  ok  smoke-test         TIDEKEEPER smoke test: 1201 passed, 0 failed, 0 static proof(s) failed
  ok  session-test       TIDEKEEPER session test: 554 passed, 0 failed
  ok  luau-test          TIDEKEEPER Luau test: 1200 passed, 0 failed, agrees with fengari
  ok  luau-bench         TIDEKEEPER Luau bench: within budget (median 15.537 us, p99 24.001 us, catch-up 2883.7 us).
  ok  git-diff-check

TIDEKEEPER quality gate: 18/18 checks passed
```

Negative controls, because a check that has never been seen to fail is not evidence.
All four content checks:

- removing one `Format.label("CHART_TITLE")` call → `FAIL Strings.UI.CHART_TITLE —
  defined, never displayed`;
- typo'ing it to `CHART_TILTE` → both the dead-label FAIL **and** `FAIL
  Format.label("CHART_TILTE") — no such key in Strings.UI; renders as an EMPTY label`;
- deleting prose row 201 → `FAIL Ledger.T_EPOCH_QUIET (201) — no prose row`;
- renumbering the template to 202 → `FAIL ... no prose row` **and** `FAIL
  Strings.LEDGER[201] — prose with no template constant`;
- restored → `clean — every piece of player-facing content is reachable (92 checked)`.

And the page allocator: reverting `allocLedgerPage` to the old epoch-derived index
failed **6** assertions across scenarios 24 and 25, including `both servers' pages
survive -- got 0, floor 2.0`. Restored → 554/0.

Two checks also fired on my own work this iteration, which is the design working on
its author: the orphan allowlist went stale the moment `loadLedgerPage` gained a
caller, and the layering check caught `ChartView`/`AlmanacView` reaching for
`game:GetService` when client views must use relative requires.

## 9. Prompt for iteration 11

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
