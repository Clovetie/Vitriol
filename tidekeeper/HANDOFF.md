# Handoff — TIDEKEEPER, end of iteration 6

TIDEKEEPER is a cozy async island trading post for Roblox. The tide runs on a real
clock, and every visitor who arrives while you are offline is a real player's
drifter, delayed. It lives in `tidekeeper/`, entirely separate from VITRIOL, with
its own copy of the tooling. 57 Luau files, 12 478 lines. **1 055 executed
assertions across two suites, 0 failures**, and 887 of them run byte-for-byte in
both a real Luau 0.700 VM and fengari with identical results.

**Iteration 6 in one line: the game was 100% non-functional for every player, all
14 checks were green, and nothing in the toolchain could see it.**

---

## 1. Triage first — and this time it found the thing that mattered

The rule since iteration 4 is: before planning anything, verify the environment
and audit the handoff's claims against reality. It has now paid twice.

| Claim checked | Reality |
| --- | --- |
| Studio reachable | **No.** Sixth consecutive iteration. No process, `DISPLAY` unset, no `rojo`/`lune`/`lute` on PATH. |
| 57 `.luau` files | ✅ |
| 21 Ledger templates | ✅ |
| "~12 300 lines" | ❌ **12 177** at the time. Corrected, now 12 478. |
| Branch at `b35e9ef` | ❌ reset to `becec6b` again; `node_modules` and `tools/bin/luau` both gone. |

Then the real audit. `Main.client.luau` was the only file in the project that had
**never executed** — not in a test, not in Studio, not anywhere. The iteration-6
prompt said to assume it was broken. It was, in two independent ways:

1. **Wrong parent folder.** It looked up remotes as
   `Tidekeeper:FindFirstChild(name)` — i.e. inside `ReplicatedStorage/Tidekeeper/`.
   `Shared/Remotes.build` parents them into a **sibling** folder,
   `ReplicatedStorage/TidekeeperRemotes` (`FOLDER_NAME = "TidekeeperRemotes"`). All
   seven lookups returned nil. The client warned seven times, started with an empty
   remotes table, and answered every session request "offline", forever.
2. **No wait.** Even at the correct path, `FindFirstChild` is a race against
   replication on join. `Remotes.await(timeout)` exists for exactly this.

Both are fixed by the same two lines: the client now `require`s `Shared/Remotes`
and calls `Remotes.await(30)`, degrading to `{}` with a warning on failure.

**The lesson is the shape, not the typo.** The client re-derived a path that
another module owns instead of calling the function whose entire job is to know
it. That rule is now written into the source at the call site.

---

## 2. Why no check caught it, and the check that now does

No test in this project constructs an Instance. The whole harness runs pure Lua
against injected fakes. **Therefore no Instance-path bug is visible to any of it**
— and that is a permanent, structural limit of this toolchain, not an oversight to
be fixed by adding more assertions. It is written down so it is not rediscovered.

What *was* addressable is the adjacent recurring bug class: a cross-module field
that reads plausibly and resolves to nil. This project has shipped three:

| Bug | Iteration | Effect |
| --- | --- | --- |
| `Drifter.CLASS_NAMES` (real export: `CLASS_COUNT`) | 5 | `OrdersView` threw at module load for a whole iteration |
| `GameConfig.MAX_SHELF_PRICE` (never existed) | 4 | assumed while writing `PostView` |
| `Tidekeeper:FindFirstChild(remote)` | 4–6 | game unplayable |

Luau does no compile-time member checking on a plain table, `check-syntax` only
parses, and the determinism scan only inspects shape. So: **`tidekeeper-member-scan.js`**,
the 14th gate check. For every `local X = require(...Foo)`, every `X.Member`
reference must be assigned somewhere in `Foo` (`function Foo.m`, `Foo.m =`, or a
top-level key of the returned table literal). It is deliberately conservative —
any module writing computed keys is skipped wholesale rather than guessed at,
because a member scan that cries wolf gets switched off and then protects nothing.
**658 references checked, clean.**

It was verified by **deliberately re-introducing both historical bugs** and
watching it fail, not by observing a green tree:

```
FAIL .../Client/OrdersView.luau:138  Drifter.CLASS_NAMES  — Drifter never assigns CLASS_NAMES
FAIL .../Client/PostView.luau:14  GameConfig.MAX_SHELF_PRICE  — GameConfig never assigns MAX_SHELF_PRICE
```

Its own first version was wrong in exactly the way it warns about: it only
understood `local Mod = {`, while **every** Config module here is an anonymous
`return { ... }`. It reported 70-odd confident failures, all false. If that had
shipped, the check would have been disabled within a day. Noted in its source.

---

## 3. The content, finally

Doc 07 §5 has been the contract since iteration 1. Two lines of it are pure data
and were still carrying iteration-2 placeholders:

| Content | Target | Was | Now |
| --- | --- | --- | --- |
| Finds | 200 | 24 | **200 ✅** |
| Ledger prose variants | 180 | 67 | **180 ✅** |

The 176 new finds span 6 groups × 4 zones, each with an 8-axis taste vector
(salvage/craft, plain/ornate, cheap/dear, hoard/spend, solitary/social,
shallow/deep, steady/erratic, kind/shrewd). Value and rarity track zone — zone 1
medians 4 coin at 200–250 per mille, zone 4 medians 275 coin at single-digit per
mille. The vectors are authored, not filled: `gold_signet` reads dear/shrewd/hoard,
`sailors_valentine` reads ornate/social/kind, and those two pull opposite drifters.

The 113 new Ledger phrasings matter more than the number suggests. The Ledger is
the **only** way an absent player's post talks to them, and at three variants per
template it read like a receipt printer — the same sentence every tide with the
numbers swapped. Session scenario 15 already renders every variant of every
template with semantically valid slots, so all 113 were directive-checked on the
first run.

Still outstanding (iteration 7): 120 letters, 64 Seed Drifters, 40 badges. The
remaining rows — meshes, décor, tier structures, music, SFX — need a running
engine or a human, and doc 07 now says so instead of claiming an iteration.

---

## 4. Two more checks that were counting instead of checking

```lua
eq(Tables.count(idsSeen), 24, "every find id is unique")
```

This asserted a **count**. A duplicated id would have passed as long as the total
came out right. It now compares against `#FindsConfig.FINDS`, which is the actual
uniqueness statement.

The find-row validator never looked inside the taste vector or at the perishable
flag — a typo'd axis (`-700` for `-70`) or `perishable = 2` went straight into the
economy. Both are now checked. Verified by breaking a row deliberately:

```
FAIL  economy / every find row is well formed -- expected 0, got 1   (taste -800)
FAIL  economy / every find row is well formed -- expected 0, got 2   (perishable 2)
```

And both content thresholds are now pinned to the **v1 targets** (200 finds, 180
phrasings) rather than the iteration-2 placeholders (24, 40). Content that is not
pinned to its target can be deleted wholesale without turning the gate red.

---

## 5. Commands and their real output

```
$ node tidekeeper/tools/tidekeeper-quality-gate.js
TIDEKEEPER quality gate — iteration 6, source root tidekeeper/code (57 Luau file(s))

  ok  doc-gate           TIDEKEEPER doc gate: 168/168 checks passed
  ok  separation         no dependency on the VITRIOL tree
  ok  check-syntax       All 57 Luau file(s) parsed successfully.
  ok  metrics              53  code/ReplicatedStorage/Tidekeeper/Domain/Resolve.luau
  ok  hot-loop-scan         1  :Clone (instance clone)
  ok  call-graph           ShowcaseService.new  <- Bootstrap
  ok  find-dead-config     ✓ no dead keys
  ok  member-scan        clean — every cross-module member resolves (658 checked)
  ok  determinism-scan   clean
  ok  smoke-test         TIDEKEEPER smoke test: 888 passed, 0 failed, 0 static proof(s) failed
  ok  session-test       TIDEKEEPER session test: 167 passed, 0 failed
  ok  luau-test          TIDEKEEPER Luau test: 887 passed, 0 failed, agrees with fengari
  ok  luau-bench         TIDEKEEPER Luau bench: within budget (median 13.482 us, p99 21.504 us, catch-up 2471.1 us).
  ok  git-diff-check

TIDEKEEPER quality gate: 14/14 checks passed
```

The scan reports 2/2 RunService connections.

`Visit.resolve` median is **flat at ~13.5 µs** against an 18 µs budget with an
eight-times-larger find table, which is the expected result and worth stating: the
hot path indexes finds, it does not scan them. p99 21.5 µs (budget 50), catch-up
2.47 ms (budget 12 ms).

**Prerequisites every turn** — the branch is reset to the session base between
turns and neither `node_modules` nor `tools/bin/luau` survives:

```
cd /home/user/Vitriol && git fetch && git reset --hard origin/arena/01a0f2ee-vitriol
cd tidekeeper/tools && npm install
git clone --depth 1 --branch 0.700 https://github.com/luau-lang/luau /tmp/luau \
  && make -C /tmp/luau config=release luau -j$(nproc) \
  && cp /tmp/luau/luau tidekeeper/tools/bin/luau
```

Without the binary the gate shows 12 of 14 checks with 2 skips — correct output,
not a failure.

---

## 6. What is *not* verified, stated plainly

- **Nothing has ever run in Roblox Studio.** Six iterations. No DataModel, no
  Instance, no replication, no real player. Everything below L3.5.
- **The remote fix is unexecuted.** It is a two-line change to the one file that
  has never run. It is *correct by inspection* — it calls the accessor the server
  side already uses and the tests already cover — but no test constructs an
  Instance, so **no check in this project can confirm it**. It must be the first
  thing anyone with Studio access verifies.
- **The 200-find economy is untuned.** The table is validated for well-formedness,
  not for balance. Nobody has simulated what a 1→500 coin value curve does to
  progression, or whether a dominant find exists.
- Performance is L3.5: real Luau 0.700 at `-O2`, which is the language runtime
  Roblox embeds, but not the Roblox engine.

---

## 7. What iteration 6 was asked for and did not do

- **Letters, Seed Drifters, badges** — not written. The finds and prose consumed
  the content budget. Handed to iteration 7 with targets intact.
- **Economy tuning** — not done, and it is now the most valuable open work.
- **OD14 (warmth into price)** — not closed. Lean is still **no**.
- **OD18 (LibMP)** — still blocked on Studio.
- No research beyond OD7. The iteration-5 pass ran on the same calendar date;
  re-fetching unchanged pages to produce a longer section would have been theatre.

---

## 8. Decisions iteration 6 made

- **D34** — Never re-derive a path another module owns; call that module's
  accessor. The remote bug is the worked example.
- **D35** — A new check must be verified by deliberately breaking something and
  watching it fail. Three checks in this project's history were green and enforcing
  nothing. Applied to the member scan and both find validators this iteration.
- **D36** — Content assertions pin to the doc 07 **target**, never to the current
  count.
- **OD7 → still open but now time-boxed.** RDC 2026 promised the turn-based
  notification API in Studio Beta in **October 2026**, and that window opened on
  the day of this iteration. The API dump still shows only the five v615 opt-in
  members, with `CreateUserNotificationAsync` removed at v616. Iteration 7 is the
  first iteration where re-checking is genuinely worthwhile.
- **Correction:** the official roadmap page is a **404**, not the 502 iteration 5
  recorded. Do not retry it.

---

## 9. Open questions for iteration 7

| # | Question | Lean |
| --- | --- | --- |
| OD7 | Turn-based notification API | Re-check once — the beta window is open |
| OD14 | Warmth into price | **No** — it turns warmth into a stat to farm. Close it or disprove it |
| OD15 | Open | — |
| OD18 | LibMP sampled profiling | Blocked on Studio |
| OD19 | Port `fake-platform.lua` and delete fengari | Only if the shims start costing |

---

## 10. Prompt for iteration 7

The copy-paste prompt is **doc 12, "Prompt — Iteration 7: the rest of the content,
and the economy it feeds"**. In short: 120 letters, 64 Seed Drifters, 40 badges,
each pinned to its doc 07 target by a test; tune the economy against the new
200-row find table with multi-seed simulation and report distributions rather than
one run; close OD14; re-check OD7 once and nothing else.

And before anything else: `git fetch && git reset --hard`, `npm install`, build
Luau, run the gate, read it. Then assume the thing nobody has executed is broken —
because for three iterations running, it was.
