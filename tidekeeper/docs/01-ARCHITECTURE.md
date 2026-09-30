# 01 — Architecture

Explorer-first, like the sibling project. **There is no Rojo project and there must not
be one.** The hierarchy below is the contract; `tidekeeper/code/` will mirror it exactly
so that every file's destination in Studio is obvious from its path.

---

## 1. Layering rules

Four layers. Dependencies point **downward only**. The call-graph tool enforces this.

```
  L3  Scenes      client controllers, server services  — may touch services & Instances
  L2  Domain      post, drifter, ledger, standing orders — pure logic over plain tables
  L1  Adapters    datastore, memorystore, notifications  — the only code that yields
  L0  Lib         tide, rng, codec, math, signal, tables — pure, no services, no yields
```

| Rule | Enforced by |
| --- | --- |
| L0 may not `require` anything above L0 and may not reference `game`, any service, or `os.time()` | `call-graph.js` + `check-syntax.js` grep rule |
| L2 may not yield and may not touch `Instance` | code review + `hot-loop-scan.js` |
| Only L1 may call `DataStoreService`, `MemoryStoreService`, `HttpService`, notifications | `find-dead-config.js` companion rule |
| Only L3 may create remotes, and only through `Shared/Remotes` | single-file rule |
| Exactly **one** `RunService` connection exists in the whole game | `CadenceService`, §5 |

The reason L2 is pure and non-yielding is [`04-SIMULATION-MODEL.md`](04-SIMULATION-MODEL.md):
the domain layer has to run identically inside a live server, inside a headless test, and
inside an offline solo session. The moment it yields or reads a service, that stops
being true.

## 2. Explorer hierarchy

```
ReplicatedStorage
└── Tidekeeper
    ├── Config
    │   ├── GameConfig          (ModuleScript)  session, caps, feature flags
    │   ├── TideConfig                          amplitudes/periods — constants, see 02 §2.3
    │   ├── EconomyConfig                       prices, curves, Standing bands
    │   ├── DrifterConfig                       taste dimensions, budget bands, classes
    │   ├── FindsConfig                         the 200 Almanac finds + drop tables
    │   ├── OrdersConfig                        standing-order verbs and limits
    │   ├── NotifyConfig                        notification kinds, cooldowns, copy keys
    │   └── UIConfig                            layout constants, breakpoints, palette
    ├── Lib                     (L0 — pure)
    │   ├── Tide                                the shared clock (doc 02)
    │   ├── RNG                                 seeded, splittable, deterministic
    │   ├── Hash                                stable 32-bit string/int hashing
    │   ├── MathExt
    │   ├── Tables                              object pool, deep freeze, stable sort
    │   ├── Signal
    │   ├── Codec                               varint + bitpack primitives
    │   └── Schema                              declarative table validation
    ├── Domain                  (L2 — pure)
    │   ├── Post                                post state, shelves, tiers
    │   ├── Drifter                             the visitor record + taste matching
    │   ├── Orders                              standing-order interpreter
    │   ├── Visit                               ONE deterministic visit resolution
    │   ├── Resolve                             the resolve-on-read driver (doc 04)
    │   ├── Ledger                              entry construction + grouping by epoch
    │   ├── Almanac
    │   └── Standing                            reputation maths
    └── Shared
        ├── Remotes                             the ONLY place a remote is created
        ├── NetContract                         schema + token bucket + replay guard
        ├── DrifterCodec                        Drifter <-> compact buffer
        ├── PostCodec                           Post <-> versioned DataStore blob
        └── Version                             schema versions + migration registry

ServerScriptService
└── Tidekeeper
    ├── Main                    (Script)        the single entry point
    ├── RemoteHandlers
    │   ├── SessionHandler
    │   ├── PostHandler                         stock, price, arrange
    │   ├── DispatchHandler                     send a Drifter
    │   └── DebugHandler                        studio-only, gated
    └── Diagnostics
        ├── Profiler
        └── BudgetMeter                         live DataStore/MemoryStore accounting

ServerStorage
└── Tidekeeper
    ├── Bootstrap               (ModuleScript)  wires everything, called by Main
    ├── Services                (L3)
    │   ├── CadenceService                      THE scheduler. one Heartbeat.
    │   ├── PlayerService                       join/leave, profile lifecycle
    │   ├── PostService                         authoritative post state in memory
    │   ├── ExchangeService                     the Drifter Exchange (doc 03)
    │   ├── LedgerService
    │   ├── NotifyService
    │   └── ShowcaseService                     Renown ratings
    └── Adapters                (L1 — the only yielding code)
        ├── DataStoreAdapter                    retry, backoff, budget, versioning
        ├── MemoryAdapter                       hash maps + queues, sharded
        ├── NotifyAdapter                       Experience Notifications
        └── PolicyAdapter                       PolicyService checks (doc 13)

StarterPlayer
└── StarterPlayerScripts
    └── Tidekeeper
        ├── ClientMain          (LocalScript)
        ├── Controllers
        │   ├── TideController                  water plane, gauge, countdown
        │   ├── LedgerController                the animated replay
        │   ├── PostController                  shelves, arrange mode
        │   ├── CombController                  beachcombing input + prediction
        │   ├── ChartController                 the 2D orthographic Chart screen
        │   └── DispatchController
        └── UI
            ├── Screens/...
            └── Components/...

Workspace
└── Tidepost                                    human-authored, see doc 11
    ├── Island
    ├── Flats                                   zone parts, tagged
    ├── Water                                   the plane driven by TideController
    └── Dock
```

## 3. Authority

| Thing | Authority | Notes |
| --- | --- | --- |
| Tide height | **neither** — derived | doc 02 §1 |
| Post state (stock, prices, tier) | **server** | client holds a read-only mirror |
| Standing / Renown | **server** | never written from a remote payload |
| Visit resolution | **server**, deterministic | client may *replay* it for the animation |
| Ledger entries | **server**, append-only | |
| Beachcomb pickup | **server** validates state + position + cooldown | doc 02 §7 |
| Camera, water, UI | **client** | |
| Drifter snapshot on logout | **server** builds it from server state | never from a client payload |

The rule of thumb: **the client may compute anything it likes, but only to decide what
to draw and what to ask for.**

## 4. Remote surface

Exactly seven remotes. All created in `Shared/Remotes`, all validated by
`Shared/NetContract` (declarative schema, token bucket, monotonic sequence).

| Remote | Dir | Payload | Budget |
| --- | --- | --- | --- |
| `RF_Session` | C→S | `{}` | 1 per join |
| `RE_PostSnapshot` | S→C | versioned post blob | on join + on change |
| `RE_LedgerBatch` | S→C | up to 24 entries | on join, then paged |
| `RF_SetOrders` | C→S | orders program (≤ 2 KB) | 6 / min |
| `RF_Arrange` | C→S | `{slot, itemId, price}` | 30 / min |
| `RF_Comb` | C→S | `{zoneId, nodeId}` | 40 / min |
| `RF_Dispatch` | C→S | `{targets[≤3], letterId, cargo[≤4]}` | 4 / min |

No remote accepts free text. Letters are **fixed-phrase IDs** into a curated table (doc 13).

## 5. Cadence — the single scheduler

One `RunService.Heartbeat` connection exists, in `CadenceService`. Everything else
registers a slot. Nothing in the game may call `task.spawn`, `task.wait`, `task.delay`,
or connect to `RunService` directly. This is a hard rule; it is the reason the sibling
project's server stayed profileable, and it is worth more here because the simulation is
the expensive part.

| Slot | Rate | Budget/tick | What runs |
| --- | --- | --- | --- |
| `frame` | every Heartbeat | **0.6 ms** | nothing by default; reserved for water + interpolation on the server (normally empty) |
| `think` | 4 Hz | **2.0 ms** | post tick, comb node respawn, order re-evaluation |
| `slow` | 0.5 Hz | **6.0 ms** | ledger flush, standing decay, showcase aggregation |
| `io` | 0.2 Hz | **budgeted, not timed** | DataStore/MemoryStore batches via the adapters |
| `resolve` | on demand | **12 ms, chunked** | resolve-on-read catch-up for a joining player |

`resolve` is the only slot allowed to exceed a frame's worth of work, and it does so by
**chunking across ticks**: at most 4 tide epochs of catch-up per tick, max 27 epochs
total (doc 02 §5). A player joining after a week of absence therefore resolves over ~7
ticks, ~1.75 s, while the client shows the Ledger's opening animation. The wait is
disguised as content.

## 6. Server memory and instance budgets

Deliberately tight, because the browser-play target (end of 2026) and mobile are the
primary clients.

| Budget | Limit | Rationale |
| --- | --- | --- |
| Parts in `Workspace` at rest | **≤ 1 800** | browser + low-end mobile |
| Unique meshes | **≤ 120** | Almanac finds reuse a shared atlas; see doc 11 |
| Server memory per player | **≤ 300 KB** | 30-player server → ≤ 9 MB of game state |
| Post state in memory | **≤ 12 KB** | serialises to ≤ 6 KB (doc 05) |
| Drifters resident per post | **≤ 24** | inbound queue depth |
| Ledger entries resident | **≤ 200**, paged | older pages fetched on demand |
| Remotes fired per player per second | **≤ 8** | |
| Client heap growth per session | **≤ 40 MB** | must be measured in Studio, not asserted here |

## 7. Player session lifecycle

```
PlayerAdded
  ├─ PolicyAdapter:load(player)              -- doc 13; before anything monetised
  ├─ DataStoreAdapter:loadPost(userId)       -- with session lock
  │     └─ PostCodec:decode + migrate        -- Version registry
  ├─ Resolve:plan(post, now)                 -- how many epochs to catch up (≤27)
  ├─ ExchangeService:claimInbound(post, plan)-- pull Drifters for those epochs
  ├─ CadenceService:enqueue("resolve", ...)  -- chunked, ~4 epochs/tick
  │     └─ per epoch: Visit.resolve() * N    -- pure, deterministic
  ├─ LedgerService:append(entries)
  ├─ RE_PostSnapshot + RE_LedgerBatch        -- client starts the replay
  └─ NotifyService:cancelPending(userId)     -- they came back; don't nag

PlayerRemoving
  ├─ Drifter.build(post, player)             -- server-side snapshot
  ├─ ExchangeService:publish(drifter)        -- into the current epoch shard
  ├─ NotifyService:scheduleNext(post, now)   -- compute the next notable tide event
  └─ DataStoreAdapter:savePost(...)          -- UpdateAsync, release lock
```

`BindToClose` must complete the save path for every player in ≤ 25 s. The adapter
budgets for 30 players × 1 write and refuses to start new work after the deadline.

## 8. Failure policy

| Failure | Behaviour |
| --- | --- |
| DataStore read fails after retries | **Do not** create a fresh post. Kick with a clear message. Silent data loss is unacceptable in a game whose entire content is history. |
| DataStore write fails at save | Retry with backoff; on final failure, serialise to a `MemoryStore` recovery queue keyed by userId and retry on next join |
| MemoryStore over quota | Exchange degrades to DataStore-only tier. The game still works, drifters are staler. **Never** block the session. |
| Exchange returns zero Drifters | Fall back to the **Seed Drifter** pool (doc 03 §8). The Ledger is never empty. |
| Notification send fails | Swallow. It is never load-bearing. |
| Resolve exceeds 27 epochs | Clamp to 27 and write a `LONG_ABSENCE` ledger entry that summarises the gap in prose. Do not silently discard. |

## 9. Config policy

Every key in every `Config` module must have a **real reader** in shipped code, or be
annotated `-- @future WPn` with the work package that will read it.
`tidekeeper/tools/find-dead-config.js` reports violations and the quality gate fails on
un-annotated dead keys. This rule exists because the sibling project accumulated
speculative config and it cost a full audit to clean up.

## 10. What is explicitly forbidden

- A second scheduler, or any direct `RunService` connection outside `CadenceService`.
- Any `task.wait` / `task.delay` in gameplay code.
- Client authority over stock, Standing, Renown, or visit outcomes.
- A remote that accepts free text.
- Storing the tide.
- A Rojo project file.
- `while true do ... task.wait() end` anywhere.
- Cross-referencing the VITRIOL tree at `/code`.
