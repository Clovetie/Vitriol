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

## 5. Determinism rules the gate should grow to enforce

[`../docs/04-SIMULATION-MODEL.md`](../docs/04-SIMULATION-MODEL.md) §5 lists rules that
are mechanically checkable. Iteration 2 should add a `tidekeeper-determinism-scan.js`
that greps `code/ReplicatedStorage/Tidekeeper/{Lib,Domain}` for:

- `math.random`
- `os.time` / `os.clock` / `tick` / `GetServerTimeNow`
- bare `pairs(` in files under `Domain/`
- `game:GetService`
- `#` applied to a table built with holes

and fails on any hit. These are the bugs that will otherwise be found in production by a
player whose offline replay disagreed with the server.
