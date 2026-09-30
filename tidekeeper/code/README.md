# `tidekeeper/code` — the Studio Explorer tree

**Iteration 2 filled the pure half: 25 modules, layers L0 and L2 only.** Nothing here
touches `game`, a service, an `Instance`, or the clock. That is what makes the whole
tree runnable — and tested — outside Roblox.

```
ReplicatedStorage/Tidekeeper/
  Config/   GameConfig TideConfig EconomyConfig DrifterConfig OrdersConfig FindsConfig
  Lib/      MathExt Hash RNG Tables Signal Codec Schema Tide          (L0, pure)
  Shared/   Version DrifterCodec PostCodec                            (wire formats)
  Domain/   Standing Almanac Drifter Post Orders Ledger Visit Resolve (L2, pure)
```

Still to come: `ServerStorage/Tidekeeper/{Adapters,Services,Bootstrap}` and
`ServerScriptService/Tidekeeper/*` in iteration 3, `StarterPlayer/...` in iteration 4.

Files here mirror the Roblox Studio Explorer hierarchy exactly, so the destination of
every file is obvious from its path:

```
code/ReplicatedStorage/Tidekeeper/Lib/Tide.luau
  ->  ReplicatedStorage > Tidekeeper > Lib > Tide   (ModuleScript)
```

Every file must also state that path in a header comment.

The full hierarchy is specified in [`../docs/01-ARCHITECTURE.md`](../docs/01-ARCHITECTURE.md) §2.

## Rules

1. **There is no Rojo project and there must not be one.** The hierarchy is the contract.
2. Four layers, dependencies point downward only: `Lib` (L0, pure) → `Domain` (L2, pure)
   → `Adapters` (L1, the only yielding code) → `Services`/`Controllers` (L3).
3. `Lib` and `Domain` may not reference `game`, any service, `os.time()`, or `Instance`.
   Time is always an argument.
4. Exactly one `RunService` connection exists in the whole game, in `CadenceService`.
5. Nothing here may reference the sibling VITRIOL tree at `/code`.
6. **No native bitwise operators.** Use `bit32.*`. The syntax checker parses Lua 5.1,
   where `&`, `|` and `~` are syntax errors, and iteration 1 deliberately dropped the
   sibling project's known-failure allowlist rather than inherit an excuse.
7. **No `pairs()` in `Domain/`.** Hash-part iteration order is unspecified, and the
   resolver iterates stock and rules. Use a numeric `for`, `ipairs`, or
   `Tables.sortedPairs`. Enforced by `tools/tidekeeper-determinism-scan.js`.
8. **Never name a local `workspace`.** It shadows a Roblox global. The determinism scan
   caught exactly this in `Domain/Resolve.luau` on its first run.

## What iteration 2 proved, and what it did not

| Claim | Evidence | Strength |
| --- | --- | --- |
| The pure core runs and is correct | 858 assertions in a real Lua VM against the real files | strong |
| `Resolve.run` is deterministic | 1 000 identical runs byte-identical, twice more on other paths | strong |
| `Visit.resolve` allocates nothing | no table constructor in the body (static) + 3 000 visits replace no buffer (dynamic) | strong, but not a heap profiler |
| The wire formats round-trip | every field, every width, every corruption path | strong |
| `Visit.resolve` fits 18 µs | **not proven.** fengari is ~50× slower than Luau; measure in Studio | none |
| Any of this is *fun* | not proven and not provable here. Iteration 4's R1 playtest | none |

## Build order

| Iteration | Adds |
| --- | --- |
| 2 | `ReplicatedStorage/Tidekeeper/{Lib,Domain,Shared,Config}` ✅ |
| 3 | `ServerStorage/Tidekeeper/{Adapters,Services,Bootstrap}`, `ServerScriptService/Tidekeeper/*` |
| 4 | `StarterPlayer/StarterPlayerScripts/Tidekeeper/*` |
| 5 | content-only config expansion; no new modules expected |
