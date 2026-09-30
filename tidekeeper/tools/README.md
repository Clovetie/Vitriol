# TIDEKEEPER tooling

A **fork** of the repository's analysis tooling, scoped to `tidekeeper/`. It is
deliberately a copy and not a shared dependency: the two games in this repository must
be able to change their gates independently, and a shared tool is a shared coupling.

Generated output goes to `tidekeeper/tools/reports/` (git-ignored).

## Quick start

```bash
npm --prefix tidekeeper/tools install
node tidekeeper/tools/tidekeeper-quality-gate.js
```

## What is here now (end of iteration 3)

| Tool | Origin | Purpose |
| --- | --- | --- |
| `tidekeeper-quality-gate.js` | **new** | The one command to run before committing — see §4 |
| `tidekeeper-doc-gate.js` | **new** | Validates the design documents themselves — see §3 |
| `tidekeeper-determinism-scan.js` | **new, it2, extended it3** | Static enforcement of the determinism and layering rules — see §5 |
| `tidekeeper-smoke-test.js` | **new, it2** | The real `Config`/`Lib`/`Shared`/`Domain` modules in a Lua VM — 858 assertions |
| `tidekeeper-session-test.js` | **new, it3** | The real **server** against a fake DataModel — 72 assertions and the request-cost report, see §6 |
| `lib/harness.js` | **new, it3** | The shared fengari harness, extracted from the smoke test — see §5b |
| `tests/pure-tests.lua` | it2 | The smoke suite |
| `tests/fake-platform.lua` | **it3** | A fake Roblox DataModel, 705 lines |
| `tests/session-tests.lua` | **it3** | 14 server scenarios |
| `check-syntax.js` | copied | Luau syntax check via `luaparse` |
| `metrics.js` | copied | LOC, comment ratio, exports, heuristic complexity |
| `call-graph.js` | copied | `require()` graph, orphaned exports, layering violations |
| `hot-loop-scan.js` | copied | Priced calls inside loops and in `RunService` files |
| `find-dead-config.js` | copied | Config keys with no reader |
| `lib/` | copied | shared helpers (`paths`, `luau`, `luau-transform`, `evaluate`) |
| `selene.toml`, `stylua.toml` | copied | lint/format config |

`lib/paths.js` resolves `tidekeeper/code` as the default source root, so the copied
tools point at the right tree with no arguments.

### Still to build

| Tool | Iteration | Purpose |
| --- | --- | --- |
| `fixture-blobs/` | 4 | Real captured save payloads, migrated to current on every gate run. Deferred from it3 and folded into OD16, which introduces schema v2 and therefore the first migration worth testing. |
| Localisation-coverage check | 4 | Every `Domain/Ledger` template id and slot arity must render from `Client/Strings`. |

## 3. `tidekeeper-doc-gate.js`

Iteration 1's deliverable is documentation, so it gets a real check rather than a claim.
It verifies:

1. every required document exists, is non-trivial, and starts with an H1;
2. every relative Markdown link inside `tidekeeper/` resolves;
3. **the tide constants are internally consistent** — it parses the constants table in
   `docs/02` and independently recomputes the epoch length, spring and neap ranges, the
   spring/neap beat period, the `TideHeight(EPOCH)` test vector, and the 27-epoch
   catch-up cap, failing if the document's stated values disagree;
4. **the storage arithmetic holds** — the Drifter byte layout in `docs/05` is contiguous
   and totals 68 bytes, agrees with `docs/03`, and the warm-shard size equals
   `200 × 68 B`;
5. every iteration prompt is present and carries both the branch rule and the
   separation rule;
6. no document links into the VITRIOL tree.

It is a consistency checker, not a judgement of whether the design is any good. It has
already caught four genuine arithmetic and omission errors in the iteration-1 docs.

```bash
node tidekeeper/tools/tidekeeper-doc-gate.js
node tidekeeper/tools/tidekeeper-doc-gate.js --json tidekeeper/tools/reports/doc-gate.json
```

## 4. `tidekeeper-quality-gate.js`

The single command every iteration runs before committing. It orchestrates the other
tools rather than replacing them, and **degrades honestly**: with `code/` empty it runs
the doc gate, reports `code: empty` for the source checks, and passes. As soon as
iteration 2 lands a module it starts enforcing syntax, hot-loop and dead-config rules,
and from iteration 2 it requires `tidekeeper-smoke-test.js` to exist and pass.

```bash
node tidekeeper/tools/tidekeeper-quality-gate.js
node tidekeeper/tools/tidekeeper-quality-gate.js --report tidekeeper/tools/reports/gate.json
```

The report keeps bounded stdout/stderr for every command so a later agent can inspect
the exact evidence without rerunning the suite.

**It is an evidence aggregator, not a substitute for Roblox Studio.** See the
verification ladder in [`../docs/09-AI-BUILD-PIPELINE.md`](../docs/09-AI-BUILD-PIPELINE.md) §4:
nothing this gate reports can take you above level L3.

## 5. `tidekeeper-determinism-scan.js` — shipped in iteration 2, extended in iteration 3

[`../docs/04-SIMULATION-MODEL.md`](../docs/04-SIMULATION-MODEL.md) §5 lists rules that are
mechanically checkable, and this tool checks them. The smoke test proves today's code is
deterministic; this proves tomorrow's cannot stop being deterministic by accident.

```
node tidekeeper/tools/tidekeeper-determinism-scan.js [--src tidekeeper/code] [--json out.json]
```

Exit 0 = clean, 1 = violations. It is wired into the quality gate as an **enforcing**
check (unlike `hot-loop-scan`, `call-graph`, `metrics` and `find-dead-config`, which
report and always exit 0).

| Rule | Scope | Why |
| --- | --- | --- |
| `math.random` | all | one unseedable global stream shared with every script in the place |
| `clock` — `os.time` / `os.clock` / `tick` | pure + `Domain/` | time enters the simulation only as `Resolve.run`'s `now` argument. Adapters and services read the clock through injected `clock`/`monotonic` functions, which is what makes the session harness able to run 30 days in 19 seconds |
| `datetime` — `DateTime` / `GetServerTimeNow` | all | same |
| `services` — `game:GetService` | all but `Shared/Remotes` | the DataModel is reached through injected dependencies, so `Bootstrap.start()` is the only composition root |
| `platform` — `Instance.new` / `workspace` / `script.Parent` | pure layers | `Config`, `Lib`, `Shared`, `Domain` must load with no DataModel at all |
| `scheduler` — `task.*` / `wait` / `delay` / `spawn` | pure + `Domain/` | a yield makes the result depend on frame timing |
| `scheduler-scope` | `Services/` | services may not yield on their own; they hand work to `CadenceService`, which the harness drives one step at a time |
| `coroutine.*` | all | same |
| `runservice` | all but the Studio guard | a Heartbeat connection is an unbounded source of nondeterminism |
| `unordered-iteration` — bare `pairs()` / `next()` | `Domain/` | hash-part order is unspecified and the resolver iterates stock and rules |
| `no-free-text` | `Services/`, `Adapters/` | player-visible strings are template ids resolved on the client (doc 08); a literal sentence on the server is both an unlocalisable string and a replication cost |
| `layering` — require pointing at a higher layer | all | `Config < Lib < Shared < Domain < Adapters < Services < Client` |

Comments are stripped before matching. **String literals are not** — this was a real bug
in the iteration-2 version, which blanked strings too and therefore could not see
`game:GetService("DataStoreService")`, the single most important thing the `services`
rule exists to catch. Rules that match a *word inside a call* now run against a
comment-stripped but string-preserving view, and the two rules that genuinely need
strings blanked (`no-free-text`'s own heuristics) ask for that view explicitly.

Each rule has an escape hatch — `-- determinism-scan: allow <rule> <reason>` on the
preceding line — and every use of it is printed in the report so it stays visible.
There are **five** today: four in `Shared/Remotes.luau`, the sanctioned remote factory,
and one `IsStudio` guard in `DebugHandler.luau`. Adding a sixth should feel expensive.

A rule may be **scoped** — restricted to the layers where it is actually a defect — but
never **weakened**. When iteration 3 needed services to call `os.time`, the fix was to
inject a clock and narrow the rule to the pure layers, not to delete it.

**It earned its keep on its first run**, flagging `local workspace = ...` in
`Domain/Resolve.luau`: a local shadowing a Roblox global, which is exactly how platform
surface creeps back into a pure module.

The one rule from the original iteration-1 sketch that is *not* implemented is "`#`
applied to a table built with holes". It is not statically decidable in Lua, and a check
that guesses would either be noise or false comfort. The property is covered dynamically
instead: `Post.checkInvariants` rejects a holed `shelves` array, and the smoke test runs
it after every epoch of every resolve.

## 5b. Running the real modules outside Roblox — what the harness has to fake

`tidekeeper-smoke-test.js` loads the actual `.luau` files, transforms them to Lua 5.3
with `lib/luau-transform.js`, and runs them in fengari. Three things had to be built for
that to be *honest* rather than merely green:

**1. `bit32`, implemented without bitwise operators.** fengari's lexer turns any numeric
literal above `2^31-1` into a float, `math.tointeger` then returns `nil` for it, and `&`
raises *"number has no integer representation"*. Every uint32 constant in the game — the
FNV basis, the SplitMix mixers, the murmur finalizer — is above that threshold. The shim
uses a 64 KB byte-wise XOR table, derives AND and OR from XOR by
`a AND b = (a + b - (a XOR b)) / 2`, and does shifts as pre-masked multiplication.

**2. Luau number semantics.** This is the important one. Luau has exactly one number
type, an IEEE-754 double. Lua 5.3 has two, and **fengari's integer subtype is 32 bits
wide with silent wraparound** — `255 * 16777216` evaluates to `-16777216` inside it.
Running the real codecs on that produces confidently wrong answers rather than errors.
The harness therefore rewrites every integer literal to a float (`floatifyNumbers`,
which skips strings, comments and hex) and forces `math.floor`/`ceil`/`abs`/`max`/`min`
to return floats. After that, fengari arithmetic *is* Luau arithmetic. Without this the
suite reports 841 passes and every one of them is meaningless.

**3. Allocation measurement, which is not available.** fengari does not implement
`lua_gc`, so `collectgarbage("count")` errors and there is no allocation counter to
read. Rather than drop the zero-allocation claim or invent a number, the harness proves
it twice: **statically**, by extracting the body of `Visit.resolve` from the real source
and asserting it contains no `{`, no `..`, and no allocating helper; and **dynamically**,
by recording the identity of every buffer in the reused context, running 3 000 visits,
and asserting nothing was replaced. Neither is a heap profiler and the report says so.

## 6. `tidekeeper-session-test.js` — shipped in iteration 3

The smoke test proves the *simulation* is right. This proves the *server* is right, and
it is where the operational failures live.

```bash
node tidekeeper/tools/tidekeeper-session-test.js
node tidekeeper/tools/tidekeeper-session-test.js --json tidekeeper/tools/reports/session.json
```

### The one design decision that matters

**The fake is a DataModel, not an adapter.** The obvious approach is to write a
`FakeDataStoreAdapter` and inject it. It tests nothing: the adapter is exactly where
this game's interesting bugs are — the retry classification, the budget deferral, the
`UpdateAsync` transform that reads and removes atomically, the lock protocol, the
"`nil` means new player but a failed read does not" distinction. Faking the adapter
means faking the code that needs testing.

So [`tests/fake-platform.lua`](tests/fake-platform.lua) sits *below* the adapter. It
implements `DataStoreService`, `MemoryStoreService`, `Players`, `RunService` and
`PolicyService`, and the real `DataStoreAdapter` runs against it unmodified.
`Bootstrap.start()` takes every dependency as an argument, so the production server and
the harness construct the *same objects* — there is no test-mode branch anywhere in the
services.

### What it models

- Request counts per type, and the per-server per-minute budgets
  (`60 + numPlayers × 40`; list `5 + numPlayers × 2`), with `UpdateAsync` decrementing
  **both** read and write.
- Deterministic failure injection using the **error strings Roblox actually
  produces** — `DataUpdateConflict`, `TotalRequestsOverLimit`, `TotalMemoryOverLimit`,
  `RequestThrottled` — because the adapter classifies by matching them, and a fake that
  invented its own messages would let a classification bug through.
- A virtual clock: `task.wait` advances time instead of sleeping, so the adapter's real
  backoff schedule (0, 0.5, 1.5, 4, 9 s) runs at full speed and a 30-day, 200-session
  lifetime completes in about 19 seconds.
- MemoryStore hash maps and a queue, with TTL expiry on the same clock.

It deliberately does **not** model real concurrency or latency. Two "servers" are two
adapter instances over one backend, interleaved explicitly by the test; real threads
would make the suite nondeterministic, which is the one thing it may not be.

### What it found

On its first green run it produced three defects, two of which silently destroyed
player history. They are tabulated in
[`../docs/03-ASYNC-SOCIAL.md`](../docs/03-ASYNC-SOCIAL.md) §6.3 and explained as
platform behaviour in [`../docs/10-RESEARCH-NOTES.md`](../docs/10-RESEARCH-NOTES.md)
§6.4. The short version: **returning `nil` from an `UpdateAsync` transform aborts the
update, it does not delete the key**, and that one fact was two bugs.

### Adding a scenario

Wrap it in `do ... end` (Lua's 200-local limit applies to the chunk's main function),
build a server with the local `newServer` helper, drive the scheduler with `settle`,
and assert with `ok` / `eq` / `le` / `ge`. Numbers the documentation quotes go into the
`REPORT` global, which the runner prints and can write to JSON — a documented
performance claim that no test measures is a claim that is already wrong and nobody has
noticed.
