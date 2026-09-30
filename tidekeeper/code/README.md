# `tidekeeper/code` — the Studio Explorer tree

**Iteration 3 added the server: 48 modules, 10 546 lines, layers L0–L4.** The pure half
still touches nothing — no `game`, no service, no `Instance`, no clock — and that is
what keeps the whole tree runnable, and tested, outside Roblox.

```
ReplicatedStorage/Tidekeeper/
  Config/   GameConfig TideConfig EconomyConfig DrifterConfig
            OrdersConfig FindsConfig NotifyConfig
  Lib/      MathExt Hash RNG Tables Signal Codec Schema Tide          (L0, pure)
  Shared/   Version DrifterCodec PostCodec ReceiptCodec
            NetContract Remotes                       (wire + net contract)
  Domain/   Standing Almanac Drifter Post Orders Ledger Visit Resolve (L2, pure)

ServerStorage/Tidekeeper/
  Adapters/ DataStoreAdapter MemoryAdapter NotifyAdapter PolicyAdapter (L1, yields)
  Services/ Bootstrap Cadence Player Post Exchange Ledger Notify Showcase (L3)

ServerScriptService/Tidekeeper/
  Main.server.luau                                     (the only Script)
  RemoteHandlers/  Session SetOrders Arrange Comb Dispatch Debug        (L4)
  Diagnostics/     Profiler BudgetMeter
```

Still to come: `StarterPlayer/StarterPlayerScripts/Tidekeeper/*` in iteration 4.

`Services/Bootstrap.luau` is the **single composition root**. It takes every dependency
as an argument — the four Roblox services, a clock, a monotonic source, a waiter, a
seed — so the production `Main.server.luau` and the session harness construct the same
objects and there is no test-mode branch anywhere below it.

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
4. Exactly one `RunService` connection exists in the whole game, made by
   `Main.server.luau` and stepped into `CadenceService`. Services never yield on their
   own; they queue work and `CadenceService` drives it. That is why the session harness
   can call `app.cadence:step(dt)` and simulate 30 days in 19 seconds.
5. Nothing here may reference the sibling VITRIOL tree at `/code`.
6. **No native bitwise operators.** Use `bit32.*`. The syntax checker parses Lua 5.1,
   where `&`, `|` and `~` are syntax errors, and iteration 1 deliberately dropped the
   sibling project's known-failure allowlist rather than inherit an excuse.
7. **No `pairs()` in `Domain/`.** Hash-part iteration order is unspecified, and the
   resolver iterates stock and rules. Use a numeric `for`, `ipairs`, or
   `Tables.sortedPairs`. Enforced by `tools/tidekeeper-determinism-scan.js`.
8. **Never name a local `workspace`.** It shadows a Roblox global. The determinism scan
   caught exactly this in `Domain/Resolve.luau` on its first run.
9. **`game:GetService` appears in exactly one file**, `Shared/Remotes.luau`, with an
   explicit determinism-scan allowance. Everything else receives services as arguments.
10. **Never return `nil` from an `UpdateAsync` transform.** It aborts the update; it
    does not delete the key. This shipped twice in iteration 3 and destroyed player
    history both times. To delete, call `RemoveAsync`. See
    [`../docs/10-RESEARCH-NOTES.md`](../docs/10-RESEARCH-NOTES.md) §6.4.
11. **No player-visible sentences on the server.** Emit a `Ledger` template id and
    slots; the client renders the words.

## What iteration 3 proved, and what it did not

| Claim | Evidence | Strength |
| --- | --- | --- |
| The pure core runs and is correct | 858 assertions in a real Lua VM against the real files | strong |
| `Resolve.run` is deterministic | 1 000 identical runs byte-identical, twice more on other paths | strong |
| `Visit.resolve` allocates nothing | no table constructor in the body (static) + 3 000 visits replace no buffer (dynamic) | strong, but not a heap profiler |
| The wire formats round-trip | every field, every width, every corruption path | strong |
| The **server** survives a simulated month | 72 assertions, 14 scenarios, 200 sessions across 8 posts and 30 virtual days against a fake DataModel | good — a fake platform, not the platform |
| A session costs ≈ 5 platform requests | measured **5.64 DataStore / 5.24 MemoryStore**, CI ceilings 8 and 6 | good |
| Retry, backoff and budget deferral work | driven by injected `DataUpdateConflict` / `TotalRequestsOverLimit` using Roblox's real error strings | good |
| Every Drifter is delivered at most once | asserted over the full month; found and fixed a 27-per-month double delivery | good |
| A MemoryStore outage does not block play | scenario 11 runs a whole session with the service dead | good |
| `Visit.resolve` fits 18 µs | **not proven, two iterations running.** No Studio has been reachable. OD12 | none |
| Any of this is *fun* | not proven and not provable here. Iteration 4's R1 playtest | none |

## Build order

| Iteration | Adds |
| --- | --- |
| 2 | `ReplicatedStorage/Tidekeeper/{Lib,Domain,Shared,Config}` ✅ |
| 3 | `ServerStorage/Tidekeeper/{Adapters,Services}`, `ServerScriptService/Tidekeeper/*` ✅ |
| 4 | `StarterPlayer/StarterPlayerScripts/Tidekeeper/*`, `Client/Strings`, PostCodec schema v2 |
| 5 | content-only config expansion; no new modules expected |
