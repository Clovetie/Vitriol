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

## What is here now (iteration 1)

| Tool | Origin | Purpose |
| --- | --- | --- |
| `tidekeeper-doc-gate.js` | **new** | Validates the design documents themselves — see §3 |
| `tidekeeper-quality-gate.js` | **new** | The one command to run before committing — see §4 |
| `check-syntax.js` | copied | Luau syntax check via `luaparse` |
| `metrics.js` | copied | LOC, comment ratio, exports, heuristic complexity |
| `call-graph.js` | copied | `require()` graph, orphaned exports, layering violations |
| `hot-loop-scan.js` | copied | Priced calls inside loops and in `RunService` files |
| `find-dead-config.js` | copied | Config keys with no reader |
| `lib/` | copied | shared helpers (`paths`, `luau`, `luau-transform`, `evaluate`) |
| `selene.toml`, `stylua.toml` | copied | lint/format config |

`lib/paths.js` resolves `tidekeeper/code` as the default source root, so the copied
tools point at the right tree with no arguments.

## What iterations 2 and 3 must add

| Tool | Iteration | Purpose |
| --- | --- | --- |
| `tidekeeper-smoke-test.js` | 2 | Loads the **real** `Lib` and `Domain` modules into a Lua 5.3 VM (fengari) and asserts their behaviour: tide vectors, RNG determinism, codec round-trips, the standing-order interpreter, `Visit.resolve` outcomes, and the two determinism proofs. Target ≥ 300 assertions. |
| `tidekeeper-session-test.js` | 3 | Boots the server against a virtual DataModel and the fake persistence layer, and runs a simulated 30-day / 200-session lifetime across ≥ 8 posts, asserting the economy invariants at every step. |
| `fixture-blobs/` | 3 | Real captured save payloads, migrated to current on every gate run. |

Both should follow the pattern of the sibling project's harnesses in `/tools` — **read
them as reference implementations, do not import them.**

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

## 5. `tidekeeper-determinism-scan.js` — shipped in iteration 2

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
| `os.time` / `os.clock` / `os.date` / `tick` | all | time enters the simulation only as `Resolve.run`'s `now` argument |
| `DateTime` / `GetServerTimeNow` | all | same |
| `game:GetService` / `Instance.new` / `workspace` | all | L0–L2 are pure; platform surface lives at L1/L3 |
| `task.*` / `wait` / `delay` / `spawn` | all | a yield makes the result depend on frame timing |
| `coroutine.*` | all | same |
| bare `pairs()` / `next()` | `Domain/` only | hash-part order is unspecified and the resolver iterates stock and rules |
| require pointing at a higher layer | all | `Config < Lib < Shared < Domain < Services < Client` |

Strings and comments are blanked before matching, so a rule name inside an error message
is never a violation. Each rule has an escape hatch — `-- determinism-scan: allow <rule>
<reason>` on the preceding line — and every use of it is printed in the report so it
stays visible. There are none today.

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
