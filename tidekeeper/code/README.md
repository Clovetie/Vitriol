# `tidekeeper/code` — the Studio Explorer tree

**Empty by design at the end of iteration 1.** Iteration 2 begins filling it.

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

## Build order

| Iteration | Adds |
| --- | --- |
| 2 | `ReplicatedStorage/Tidekeeper/{Lib,Domain,Shared,Config}` |
| 3 | `ServerStorage/Tidekeeper/{Adapters,Services,Bootstrap}`, `ServerScriptService/Tidekeeper/*` |
| 4 | `StarterPlayer/StarterPlayerScripts/Tidekeeper/*` |
| 5 | content-only config expansion; no new modules expected |
