# Handoff — TIDEKEEPER, end of iteration 5

**State:** the harness can now be believed, and the client has run. 57 Luau modules,
~12 300 lines. **1 055 executed assertions across two suites, 0 failures**, and 887 of
them are now independently re-run in a **real Luau VM** that agrees exactly.

**Verification level claimed: L3.5** — *runs in a real Luau VM* (doc 09 §4). Iteration 4
earned that level for the performance benchmark; iteration 5 extends it to the entire
correctness suite. It is **not** L4: no Roblox engine was involved, no Instance has been
created, no real DataStore touched.

**The iteration in one sentence:** until now every correctness claim in this project was
made about a lightly rewritten copy of the code, and the first time the client was
actually executed, two of its six screens threw on load.

**This iteration did not ship the game.** Content volume, economy tuning and the
cold-start playtest were in the prompt and are **not started** — see §6. A partial
honest result beats a complete claimed one.

**Read in this order:**

| # | File | Why |
| --- | --- | --- |
| 1 | this file | what happened, what is true, what to do next |
| 2 | [`docs/10-RESEARCH-NOTES.md`](docs/10-RESEARCH-NOTES.md) | **§8 is new** — triage, OD17, and the two client bugs |
| 3 | [`ROADMAP.md`](ROADMAP.md) | tracker, validation snapshot, open decisions OD1–OD19 |
| 4 | [`docs/08-CLIENT-UX-MOBILE.md`](docs/08-CLIENT-UX-MOBILE.md) | §8.3 — what scenario 16 actually asserts |
| 5 | [`tools/README.md`](tools/README.md) | §7 — the two runners and why both exist |
| 6 | [`tools/bin/README.md`](tools/bin/README.md) | how to build the Luau VM, four minutes |

---

## 1. Triage first — the rule iteration 4 imposed, and it paid

Iterations 2, 3 and 4 each planned around Studio being available and each had to
re-plan. The iteration-4 prompt made triage mandatory *before* planning. All three
answers, with evidence, are in doc 10 §8:

| | Question | Answer |
| --- | --- | --- |
| (a) | Studio reachable? | **No.** No process, `DISPLAY` unset, no MCP port, no `rojo`/`lune`/`lute`. |
| (b) | GitHub release assets? | **No** (`SSL_ERROR_SYSCALL`), though `api.github.com` is 200. Lute still unavailable. |
| (c) | Notification API shipped? | **No.** `last_updated 2026-09-30`, same three opt-in members. Fourth check, fourth no. |

**(a) deserves a note, because the first answer was wrong.** `pgrep -afi "roblox|studio"`
reported a hit — which was the grep matching *its own command line*. Had that gone
unchecked, this iteration would have been planned around a Studio that does not exist.
It is the same failure mode as iteration 4's connection counter: a check that appears
to confirm something while actually observing itself.

---

## 2. What was built

### 2.1 OD17 — the correctness suite runs in real Luau, with no shims

`tools/tidekeeper-luau-test.js`. This is the important one.

`tests/pure-tests.lua` has always run under **fengari**, a Lua 5.3 VM. Lua 5.3 is not
Luau, so that harness reshapes both the game and the tests before either will run:

| fengari needs | real Luau |
| --- | --- |
| every numeric literal rewritten to a float | nothing |
| `bit32` rebuilt from a 64 KB byte-wise XOR table | native |
| `math.floor/ceil/abs/max/min` wrapped to return floats | nothing |
| `string.format("%d", …)` rewritten to `%.0f` | nothing |

Each row is a divergence between the tested artefact and the shipped one. One of them
once produced **841 meaningless passes**. So: *every correctness claim this project has
made since iteration 2 was a claim about a lightly rewritten copy of the code.*

Now both VMs run the same file and agree:

```
=== pure-tests.lua in REAL Luau (tidekeeper/tools/bin/luau) ===
  passed         887
  failed         0
  wall time      735 ms
  shims applied  none (the fengari harness needs four)

=== cross-check against the fengari suite ===
  fengari        887 passed, 0 failed
  real Luau      887 passed, 0 failed
  agreement      identical
```

Three things to keep:

- **The suite is shared byte for byte.** A doctored copy would have reintroduced the
  exact problem the port exists to remove. It cost one alias (`TidekeeperRequire`) and
  one injected fixture string.
- **Agreement is the deliverable, not the Luau number.** Two independent VMs agreeing
  rules out "the harness is wrong" *and* "the port is wrong" at once. `--compare` is how
  the gate runs it.
- **0.7 s versus 72 s.** A hundredfold speedup changes how a suite gets used. A
  72-second loop gets run at the end; a 0.7-second one gets run constantly.

**fengari stays.** The session harness needs a fake DataModel (`fake-platform.lua`, 705
lines) that has not been ported, so the shims remain in the tree regardless — and
keeping both preserves the cross-check, which is the most valuable property here. Real
Luau is authoritative; fengari is the second opinion and the no-binary fallback.

### 2.2 Scenario 16 — the client, driven against the real server

Iteration 4's handoff said plainly: *"no Instance has ever been created … this is the
largest untested surface in the project."* Scenario 16 drives the real
`ClientBootstrap` against the real remote handlers over the fake platform. No engine is
needed because the client is a presenter (D25) — the only faked object is a
`RemoteFunction`, a table with one method.

Beyond "does not crash", it asserts: every one of the six screens renders and carries a
named tide state; the data screens carry data, not a shell; `step()` redraws **only**
when dirty; the `renderer:draw(model)` seam is called exactly once with a well-formed
model; a missing remote and a throwing remote both degrade to a human message with no
directive in it and both count the failure; and sequence numbers are never reused.
Detail in doc 08 §8.3.

### 2.3 `lib/module-map.js`

The module list had been copy-pasted into three runners. A fourth consumer made that
untenable — a module added to one list and not the others gives a `nil` require that
surfaces as a confusing runtime error in one tool while the others stay green. It also
documents the trap that bit during the refactor: **two path conventions**, absolute for
`luau-native` and relative for the fengari harness, and handing over the wrong one
produces a doubled path that *looks* like a missing file.

---

## 3. The two bugs scenario 16 found on first run

Both were in code that had **never once been executed**.

**`OrdersView` threw at load time.** Its last line was `#Drifter.CLASS_NAMES` — a table
that has never existed in any version of this project; the real export is
`Drifter.CLASS_COUNT`. In Studio this takes the entire Orders screen with it, and
`require` failures cascade to everything downstream.

**`PostView` indexed a number.** The field `shelves` meant the shelf **array** in the
domain (`S.shelves[i].id`) and the shelf **count** on the wire (`Post.shelfCount(S)`).
`PostView.build` reads the array, as the word implies, so it threw.

The second is worth dwelling on because the fix direction was not obvious until the
evidence was read: **`PostView` was already reading `snapshot.shelfCount`.** The client
had been written against the honest contract and the *server* was the wrong side. So the
count became `shelfCount` in all four places that send it, and `shelves` is the array
everywhere. **This is D28 again** — one name must not mean two things — and it is the
second time that exact failure has shipped.

**The general finding, and it is the one to carry forward:
`check-syntax` parses, it does not execute.** A module can be syntactically perfect, pass
a 13-rule determinism scan, be reviewed, and still throw on the first line of real use.
Only running it catches that.

---

## 4. Commands and their real output

```
TIDEKEEPER quality gate — iteration 5, source root tidekeeper/code (57 Luau file(s))

  ok  doc-gate           TIDEKEEPER doc gate: 172/172 checks passed
  ok  separation         no dependency on the VITRIOL tree
  ok  check-syntax       All 57 Luau file(s) parsed successfully.
  ok  metrics              53  code/ReplicatedStorage/Tidekeeper/Domain/Resolve.luau
  ok  hot-loop-scan         1  :Clone (instance clone)
  ok  call-graph           ShowcaseService.new  <- Bootstrap
  ok  find-dead-config     ✓ no dead keys
  ok  determinism-scan   clean
  ok  smoke-test         TIDEKEEPER smoke test: 888 passed, 0 failed, 0 static proof(s) failed
  ok  session-test       TIDEKEEPER session test: 167 passed, 0 failed
  ok  luau-test          TIDEKEEPER Luau test: 887 passed, 0 failed, agrees with fengari
  ok  luau-bench         TIDEKEEPER Luau bench: within budget (median 15.492 us, p99 23.827 us, catch-up 2868.9 us).
  ok  git-diff-check

TIDEKEEPER quality gate: 13/13 checks passed
```

**On a clean checkout two things are missing and both are gitignored on purpose:**

```bash
cd tidekeeper/tools && npm install          # fengari + luaparse; without it every
                                            # Lua-running check dies with MODULE_NOT_FOUND
# and see tools/bin/README.md for the luau binary (four minutes from source)
```

Without the binary the gate reports `skip luau-test`, `skip luau-bench` and
**11/13 passed, 2 not applicable yet** — correct output, not a failure.

---

## 5. What is *not* verified, stated plainly

- **Nothing has run inside Roblox.** Four iterations, four times unreachable. L4, L5 and
  R1 are not "nearly done" — nothing about them has been started, and no further work in
  this environment will start them.
- **No Instance has ever been created.** `Main.client.luau` is still the one file that
  has never executed. Scenario 16 tests the seam it calls, not the Instance code behind
  it. Given that two of the six *pure* client modules threw on first execution, assume
  this file is broken until proven otherwise.
- **L3.5 is not L4.** Same VM, no DataModel, different GC tuning and build flags, CI
  hardware.
- **Median performance headroom is 1.1×.** Inside budget, and thin.
- **The game has no content.** 21 Ledger templates against a target of 180; no finds, no
  letters, no Seed Drifters, no island.
- **No human has played this.**

---

## 6. What iteration 5 was asked for and did not do

Stated flatly, because the roadmap tables alone make it look like slippage rather than a
decision:

| Asked | Status | Why |
| --- | --- | --- |
| 200 finds, 180 templates, 120 letters, 64 Seed Drifters, 90 décor, 40 badges | **not started** | the iteration went entirely into making the harness trustworthy and running the client |
| Economy tuning across 8 play patterns | **not started** | — |
| Cold-start playtest (R4) | **not started** | needs humans |
| Title, thumbnail, Moments clips, launch checklist | **not started** | needs a published place |

The judgement: a content pass written against a harness that reshapes the code before
testing it, and against a client whose screens had never been loaded, would have been
content built on two unknowns. Both are now known. Iteration 6 can write content against
a suite that runs the real language and a client that has been executed.

---

## 7. Decisions iteration 5 made

D13–D30 stand. New:

| # | Decision | Why |
| --- | --- | --- |
| D31 | **Real Luau is authoritative for correctness; fengari is the second opinion.** The two runners share the test file byte for byte and the gate asserts they agree | agreement across independent VMs rules out both "the harness is wrong" and "the port is wrong"; a doctored copy of the suite would prove neither |
| D32 | A shared `lib/module-map.js` is the only place the module list lives, and it exports absolute *and* relative forms by name | three copies had already drifted; the two path conventions are a real trap and are now documented at the point of use |
| D33 | **Triage before planning.** Capability questions get answered with evidence, and a check that could be observing itself gets re-run a second way | the `pgrep` false positive would have planned the whole iteration around a Studio that does not exist |

---

## 8. Open questions for iteration 6

Full table in [`ROADMAP.md`](ROADMAP.md).

- **Content is the whole job now.** The tooling argument is finished: the suite runs the
  real language, the client executes, the gate is 13 checks. There is nothing left to
  sharpen before writing content, and sharpening tools further would be avoidance.
- **Assume `Main.client.luau` is broken.** Two of six pure client modules threw on first
  execution. That file has still never run.
- **OD18 (LibMP) and OD19 (porting `fake-platform.lua`)** are both parked: OD18 needs
  Studio, OD19 is only worth it if the fengari shims start costing again — today the
  cross-check they enable is an asset.
- **Studio.** The MCP ecosystem is ready (doc 10 §7.3) and useless without a running
  Studio process. If one ever appears, L4, L5 and R1 all unlock in a single session, and
  that outranks everything else.

---

## 9. Prompt for iteration 6

See [`docs/12-ITERATION-PROMPTS.md`](docs/12-ITERATION-PROMPTS.md), heading
**"Prompt — Iteration 6: content"**.
