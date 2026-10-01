# Handoff — TIDEKEEPER, end of iteration 7

TIDEKEEPER is a cozy async island trading post for Roblox. The tide runs on a real
clock, and every visitor who arrives while you are offline is a real player's
drifter, delayed. It lives in `tidekeeper/`, entirely separate from VITRIOL, with
its own copy of the tooling. 60 Luau files, 13 428 lines. **1 118 executed
assertions across two suites, 0 failures**, and 925 of them run byte-for-byte in
both a real Luau 0.700 VM and fengari with identical results.

**Iteration 7 in one line: four separate features were shipped and completely
inert, and all 14 checks were green the entire time.**

---

## 1. The four dead features

Each was found the same way — by asking *what reads this?* — and each is the same
shape as the iteration-6 remote bug: **two modules that are individually correct,
with the feature lost in the gap between them.**

### 1.1 `RF_Dispatch` was decoration

`DispatchHandler` recorded the player's choices on the post:

```lua
S.dispatchedAt   = epoch
S.dispatchLetter = payload.letterId
S.dispatchCargo  = cargo
```

`ExchangeService:buildDrifter`, which builds the outbound drifter at logout, read
**none of them**. It recomputed cargo by walking the shelves in slot order and
hard-coded `d.letterId = 0`. So: your cargo choice was silently replaced, and **no
letter had ever reached another player**. That also made Ledger template 105 ("your
drifter brought a note back") unreachable prose, and made `MAX_LETTER_ID = 96` a
ceiling on a phrase list that did not exist.

### 1.2 No post could ever be promoted

`S.tier` was set to `1` when a post was created, and **no code anywhere ever
changed it** — the only other write in the project was `PostCodec` decoding what it
had encoded. Every tier-gated system was therefore unreachable: 24 shelves at tier
4, the four currents behind `CURRENT_MIN_TIER`, `PASSIVE_CAP_BY_TIER`, the
6/10/16/24 order-rule limits, and the whole of doc 06 §7. There was no remote to
buy a tier and no cost to pay for one.

### 1.3 Shelf density was a comment, not a rule

`Post.setShelf` wrote to any slot inside the tier limit, while `clearShelf`
compacts with `table.remove`. A gap was therefore possible — and `PostCodec` writes
`#shelves` then indexes `1..n`, so **a gap makes the post unsaveable**: encode
throws, the save fails, the session is lost. `PostHandler` passes a client-supplied
slot straight in, so any client could place into slot 6 of an empty post and
permanently break its own save. Remotely triggerable data loss, reachable by
editing one number in a payload.

### 1.4 `app.logger` could be nil

With `silent = true`, `Bootstrap` left `app.logger` nil, and **seven rejection
paths across the remote handlers call it unconditionally**. Every validation
failure would throw instead of returning `E_ILLEGAL` — the client gets an exception
where it should get a status, and the one code path that only runs when something
is already wrong is the one that breaks. `silent` now means "say nothing", not "be
nil".

---

## 2. The check that closes the other direction

`member-scan` (iteration 6) catches a field **read** that is never written.
`tidekeeper-dead-write-scan.js` (new, 15th gate check) catches a field **written**
to shared state that is never read. Between them both directions of the
cross-module field contract are now closed.

It found exactly the two dead writes and nothing else — **26 fields checked, no
false positives**. Scoped deliberately to the post/session state object: widening
it to every table in the project would drown the signal, and a scan that cries wolf
gets switched off and then protects nothing.

Session scenario 17 asserts the two halves of dispatch actually meet, and was
verified by reverting `ExchangeService` to its broken form:

```
FAIL  the drifter carries the letter the player attached  -- got 0.0, expected 41.0
FAIL  the drifter carries exactly the cargo the player chose  -- got 2, expected 1.0
FAIL  ...and it is the right find  -- got 7.0, expected 3.0
```

---

## 3. Progression, measured rather than invented

Added `EconomyConfig.TIER_COST`, `Post.promotionCost/canPromote/promote`,
`NetContract.RF_Upgrade` (1 burst / 3 per minute) and `PostHandler.upgrade`. The
upgrade payload carries nothing but a sequence number: the server knows the post,
the post knows its tier, the cost is server config. There is nothing in it to forge.

`tools/tests/economy-sim.lua` simulates 12 seeds × 70 days of a
diligent-but-not-optimal player and reports the day each seed arrived:

| Tier | Cost | p10 | **median** | p90 | doc 06 target |
| --- | --- | --- | --- | --- | --- |
| 2 | 320 | 3 | **3** | 5 | day 3 |
| 3 | 3 400 | 14 | **17** | 20 | day 16 |
| 4 | 15 500 | 49 | **50** | 55 | day 52 |

All 12 seeds reach tier 4. **Three rounds of calibration were needed because
promotion compounds** — each tier makes the next arrive sooner. The first costs were
read off a curve measured with every post locked at tier 1, which was the only
curve obtainable at the time, and put tier 4 at day 22 instead of 52. *A
progression curve cannot be calibrated against a simulation that cannot progress.*

The sim takes ~2 minutes, so it is **not** in the gate. `pure-tests.lua` pins the
three calibrated numbers and asserts the costs stay strictly increasing, so they
cannot drift without someone re-running it.

---

## 4. Content — every data-only line is now done and pinned

| Content | Target | Status |
| --- | --- | --- |
| Finds | 200 | ✅ it6 |
| Ledger prose variants | 180 | ✅ it6 |
| Fixed-phrase letters | 120 | ✅ **it7** |
| Seed Drifters (named) | 64 | ✅ **it7** |
| Badges | 40 | ✅ **it7** (data; awarding is it8) |

Two content defects found on the way:

- **The 176 finds added in iteration 6 had no display names.** `Strings.FIND`
  stopped at id 24, so every find above it rendered as "something the sea left".
  The data shipped and the words did not. The coverage test now walks the real find
  table instead of a sample.
- **Seed Drifters were anonymous.** doc 03 §8 calls a Seed "a character, not a
  statistic", but nothing supplied a name for their owner ids, so every one
  rendered as **"Someone"** — and a session test claims 2 398 seed arrivals in a
  simulated month. The Ledger, the one surface carrying this game's entire
  emotional argument, was mostly a list of anonymous Someones. There are now 64
  named characters, each leaning hard on one taste axis so they are legible over
  time, and `Format.actorName` resolves them at the single point the Ledger asks.

Letters are split the way finds are: `LettersConfig` holds the stable persisted ids
and the server-side validation ceiling, `Strings.LETTER` holds the localisable
copy. Every phrase is written to be harmless sent by a stranger, to a child, out of
context — the rules are in the module header and adding a phrase means re-reading
them. `MAX_LETTER_ID` is now derived from the content so it cannot drift again.

---

## 5. Commands and their real output

```
$ node tidekeeper/tools/tidekeeper-quality-gate.js
TIDEKEEPER quality gate — iteration 7, source root tidekeeper/code (60 Luau file(s))

  ok  doc-gate           TIDEKEEPER doc gate: 171/171 checks passed
  ok  separation         no dependency on the VITRIOL tree
  ok  check-syntax       All 60 Luau file(s) parsed successfully.
  ok  metrics              53  code/ReplicatedStorage/Tidekeeper/Domain/Resolve.luau
  ok  hot-loop-scan         1  :Clone (instance clone)
  ok  call-graph           ShowcaseService.new  <- Bootstrap
  ok  find-dead-config     ✓ no dead keys
  ok  member-scan        clean — every cross-module member resolves (680 checked)
  ok  dead-write-scan    clean — every field written to shared state is read somewhere (26 checked)
  ok  determinism-scan   clean
  ok  smoke-test         TIDEKEEPER smoke test: 926 passed, 0 failed, 0 static proof(s) failed
  ok  session-test       TIDEKEEPER session test: 193 passed, 0 failed
  ok  luau-test          TIDEKEEPER Luau test: 925 passed, 0 failed, agrees with fengari
  ok  luau-bench         TIDEKEEPER Luau bench: within budget
  ok  git-diff-check

TIDEKEEPER quality gate: 15/15 checks passed
```

The scan reports 2/2 RunService connections.

The economy sim is opt-in and not part of the gate:

```
node tidekeeper/tools/tidekeeper-session-test.js --tests tools/tests/economy-sim.lua
```

**Prerequisites every turn** — the branch is reset to the session base between
turns and neither `node_modules` nor `tools/bin/luau` survives:

```
cd /home/user/Vitriol && git fetch && git reset --hard origin/arena/01a0f2ee-vitriol
cd tidekeeper/tools && npm install
git clone --depth 1 --branch 0.700 https://github.com/luau-lang/luau /tmp/luau \
  && make -C /tmp/luau config=release luau -j$(nproc) \
  && cp /tmp/luau/luau tidekeeper/tools/bin/luau
```

Without the binary the gate shows 13 of 15 checks with 2 skips — correct output,
not a failure.

---

## 6. What is *not* verified, stated plainly

- **Nothing has ever run in Roblox Studio.** Seven iterations. No DataModel, no
  Instance, no replication, no real player. Everything below L3.5.
- **No client code is verified.** No test constructs an Instance, so the entire
  client layer — including `Main.client.luau`, still never executed — is unproven
  by construction. This is a permanent, structural limit of the toolchain, not an
  oversight to be fixed with more assertions.
- **`RF_Upgrade` has no client caller.** The server path is tested end to end
  through the real handler; nothing in the UI invokes it.
- **The letter picker does not exist.** `DispatchView` builds a payload with a
  letter id; nothing lets a player choose one. `LedgerView` now carries
  `letterText`; nothing displays it.
- **Badges are data only.** No stat is incremented and nothing is awarded.
- The economy numbers come from one player model, stated in the sim's header. It is
  the fast end of the distribution, not a prediction.

---

## 7. What iteration 7 was asked for and did not do

- **Décor, meshes, tier structures, music, SFX** — all need an engine or a human.
  doc 07 now marks them by what blocks them rather than naming an iteration.
- **OD18 (LibMP)** — still blocked on Studio.
- **OD19 (port `fake-platform.lua`, delete fengari)** — not needed; the shims are
  not costing anything yet.

---

## 8. Decisions iteration 7 made

- **D37** — Content thresholds pin to the doc 07 target, and so do calibrated
  economy constants. `pure-tests` asserts the three tier costs by value.
- **D38** — A simulation used to calibrate a system must be able to exercise that
  system. Calibrating progression against a tier-locked sim produced costs that
  were wrong by a factor of two.
- **D39** — Shared-state field contracts are checked in both directions:
  `member-scan` for reads, `dead-write-scan` for writes.
- **OD7 ✅ CLOSED — not available for v1.** Six iterations. Confirmed against the
  per-version API dump: five v615 opt-in members, `CreateUserNotificationAsync`
  still removed at v616, while the same page shows `Instance` changing at v734, so
  the dump is current. R5 already requires the game to work with zero
  notifications. Re-open only if the method reappears.
- **OD14 ✅ CLOSED — no.** Warmth stays prose-only. Held three iterations for a
  playtest that seven iterations without Studio make clearly distant; the reasoning
  was never really empirical. Wiring warmth into price makes it a stat to farm and
  turns every visitor into an optimisation problem, which contradicts doc 00's
  pillars. Cheap to reverse if a playtest disagrees.

---

## 9. Open questions for iteration 8

| # | Question | Lean |
| --- | --- | --- |
| OD15 | Open | — |
| OD18 | LibMP sampled profiling | Blocked on Studio |
| OD19 | Port `fake-platform.lua`, delete fengari | Only if the shims start costing |
| **new** | Badge stats need persisting → `SCHEMA_VERSION` 3 + migration | `Version.migrate` already exists for this |

---

## 10. Prompt for iteration 8

The copy-paste prompt is **doc 12, "Prompt — Iteration 8: make the new systems
reachable by a player"**. In short: award the badges (12 lifetime stats, a schema
bump and a migration — and returning `nil` from an `UpdateAsync` transform *aborts
the write*, a bug this project has shipped twice); build the client UI for upgrade,
the letter picker and the received letter; re-run the economy sim if any income
number moves.

And before anything else: `git fetch && git reset --hard`, `npm install`, build
Luau, run the gate, read it. Then go looking for the fifth dead feature — because
there have been four, in two consecutive iterations, and every one of them lived in
the gap between two modules that were each individually correct.
