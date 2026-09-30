# 02 — The Tide and the Shared Clock

This document specifies the single function that the entire game is timed against. It is
short on purpose: the whole point is that this is small, pure, and depended on by
everything.

---

## 1. The governing decision

> **The tide is a pure function of UTC wall-clock time. It is never stored, never
> replicated, and never authoritative on any single machine.**

This is the analogue of VITRIOL's `Lighting.ClockTime` finding, arrived at from the
opposite direction: rather than discovering that a value *cannot* be replicated, we
choose a world clock that *must not be*, because deriving it is strictly better than
sending it.

Consequences, all of them good:

- Every game server agrees without coordination.
- Every client agrees with its server without a remote.
- An **offline replay** of eleven hours ago computes the exact tide that was there.
- A **future** tide is computable, so notifications can be scheduled precisely.
- Zero bytes of DataStore, zero bytes of MemoryStore, zero remotes, zero drift.

The only shared input is `os.time()`, which returns UNIX epoch seconds and is the same
on the server and (within clock skew) the client. Clients are never trusted with tide
height for anything that awards an item; see §7.

## 2. The model

Real tides are dominated by a small number of harmonic constituents. We use three, which
is enough to produce a tide that is regular enough to learn and irregular enough to stay
interesting.

| Constituent | Real-world analogue | Period | Role in the game |
| --- | --- | --- | --- |
| `M2` | principal lunar semidiurnal | **12 h 25.2 min** (44 714 s) | The main two-highs-two-lows-a-day rhythm |
| `S2` | principal solar semidiurnal | **12 h 00 min** (43 200 s) | Beats against M2 to produce spring/neap |
| `K1` | lunisolar diurnal | **23 h 56.1 min** (86 164 s) | Diurnal inequality — makes the two daily lows unequal |

The beat between `M2` and `S2` produces the **spring–neap cycle** automatically, with a
period of `1 / |1/44714 − 1/43200|` ≈ **1 275 700 s ≈ 14.765 days**, which is the real
synodic fortnight. We do not hand-author it; it falls out.

### 2.1 The function

```
TideHeight(t) =           -- t: UNIX seconds (integer)
      A_M2 * cos(2π * (t - φ_M2) / T_M2)
    + A_S2 * cos(2π * (t - φ_S2) / T_S2)
    + A_K1 * cos(2π * (t - φ_K1) / T_K1)
    + Z0
```

Returns a height in **studs relative to the flats datum**. Negative means the flats are
dry.

### 2.2 Constants (iteration 2 must use exactly these)

| Symbol | Value | Note |
| --- | --- | --- |
| `T_M2` | `44714` s | 12 h 25.2 min |
| `T_S2` | `43200` s | 12 h |
| `T_K1` | `86164` s | 23 h 56.1 min (sidereal day) |
| `A_M2` | `10.0` studs | dominant |
| `A_S2` | `3.4` studs | spring range 26.8, neap range 13.2 |
| `A_K1` | `2.1` studs | diurnal inequality |
| `Z0` | `0.0` | datum offset; tuning knob, keep at 0 in v1 |
| `φ_M2` | `0` | epoch phase; see §2.3 |
| `φ_S2` | `0` | |
| `φ_K1` | `0` | |
| `EPOCH` | `1767225600` (2026-01-01T00:00:00Z) | all phases measured from here |

Derived, for the docs and the UI:

- **Spring range** = `2*(A_M2 + A_S2)` = **26.8 studs** — *semidiurnal component only.*
- **Neap range** = `2*(A_M2 − A_S2)` = **13.2 studs** — *semidiurnal component only.*

K1's 2.1-stud diurnal amplitude adds to both. The figures a player actually sees,
measured over 60 days in iteration 2's harness, are a **29.73** stud spring range and a
**15.97** stud neap range. §8's test vectors use the measured numbers.
- **Spring/neap period** ≈ **14.765 days**
- **Mean low-water interval** ≈ **12 h 25 min**

### 2.3 Phase policy

All three phases are **0 at `EPOCH`**, meaning `2026-01-01T00:00:00Z` is a high water
everywhere. This is arbitrary and that is fine — it makes the function trivially testable
(`TideHeight(EPOCH) == A_M2 + A_S2 + A_K1 + Z0 == 15.5`) and gives a fixed reference the
whole team and every test fixture can share.

**Do not** make phase a config knob that ships. If it changes after launch, every
player's learned intuition about "the flats are dry after school" breaks, and every
historical Ledger replay becomes wrong. It is a constant. `DayNightConfig`-style
tunability is an anti-feature here.

## 3. Tide states

The continuous height is bucketed into five states. The buckets are what gameplay reads;
raw height is only for the water plane and the UI gauge.

| State | Condition | Duration (typical) | Gameplay |
| --- | --- | --- | --- |
| `LOW` | `h < -6` | ~2 h 10 m | Flats fully dry. **Beachcombing**, all zones. |
| `EBB` | `h ∈ [-6, 2)` and falling | ~2 h 55 m | Flats partially dry, water receding. Beachcombing, inner zones only. |
| `FLOOD` | `h ∈ [-6, 2)` and rising | ~2 h 55 m | **Danger window.** Beachcombing still possible; being caught out costs carried stock. |
| `HIGH` | `h > 8` | ~2 h 05 m | **Dockwork.** Deep-draught traders reach the pier. Flats inaccessible. |
| `SLACK` | `h ∈ [2, 8]` | ~2 h 20 m | Transition. Neither activity at full value. Best time for stock & price. |

`SLACK` exists so there is always a low-pressure window for the *decision* beat of the
core loop (§00 beat 4). Without it, the loop is always urgent, which is exhausting.

Rising/falling is determined by the sign of the analytic derivative, not by sampling two
points — sampling introduces frame-rate-dependent behaviour.

### 3.1 The derivative

```
TideVelocity(t) =
    - A_M2 * (2π/T_M2) * sin(2π*(t-φ_M2)/T_M2)
    - A_S2 * (2π/T_S2) * sin(2π*(t-φ_S2)/T_S2)
    - A_K1 * (2π/T_K1) * sin(2π*(t-φ_K1)/T_K1)
```

Units: studs/second. Used for `EBB` vs `FLOOD`, for the water-plane animation, and for
the "how long have I got" countdown.

## 4. Forward search — the thing notifications need

Gameplay repeatedly asks *"when is the next X?"*. Because the function is smooth and its
shortest period is 43 200 s, a bounded search is exact enough and is cheap.

```
NextStateChange(t, horizonSeconds) -> (tChange, newState) | nil
```

**Algorithm (iteration 2 must implement exactly this, it is what the tests assert):**

1. Coarse scan forward from `t` in **60 s** steps up to `horizon` (default 7 days),
   evaluating the bucket. Stop at the first step where the bucket differs.
2. Bisect the 60 s interval **12 times** to land within ~15 ms. Return the integer second.

Cost: worst case 10 080 evaluations for a 7-day horizon, each three `cos` calls. ~0.4 ms
in Luau. Call it once per player per session and cache; never call it in a loop.

`NextLowWater(t)` and `NextHighWater(t)` use the same machinery against
`TideVelocity` sign changes.

## 5. Epoch buckets — the unit of async coordination

Continuous time is useless as a key. Everything async is bucketed into a **Tide Epoch**:

```
TideEpoch(t) = floor((t - EPOCH) / 22357)      -- 22357 = T_M2 / 2
```

One epoch is **half an M2 period ≈ 6 h 12 min**, i.e. one high-to-low or low-to-high
swing. There are ~3.87 epochs per day.

The Tide Epoch is the coordination key for:

- **Drifter exchange shards** — drifters are pooled per `(current, epoch)`.
- **Deterministic seeds** — `seed = hash(postId, drifterId, epoch)`.
- **Resolve-on-read step boundaries** — offline catch-up advances epoch by epoch.
- **Notification scheduling** — "at the start of epoch N your dock floods".
- **Ledger grouping** — the Ledger is grouped by epoch, and each group has a tide
  silhouette drawn behind it. This is why the Ledger feels like a tidal record and not
  a list of transactions.

A 7-day catch-up cap is therefore **27 epochs**, which bounds every replay loop in the
game to 27 iterations. That number appears throughout the architecture.

## 6. What the client is allowed to do

The client computes the tide **locally, every frame**, for:

- the water plane height and its shader,
- the gauge, the countdown, the Chart screen,
- gating whether the "go beachcombing" button is enabled (cosmetic gating).

The server computes the tide **on demand only**, for:

- validating that a beachcomb pickup happened in a legal state,
- deciding which Drifter class may dock,
- stamping epochs on ledger entries.

There is **no tide remote and no tide replication**. If a client's clock is wrong, its
water looks wrong and its pickups are rejected; that is a self-correcting incentive.

## 7. Trust boundary

Tide state is trivially forgeable client-side, so:

- **Never** award an item because the client said the tide was low. The server
  recomputes `TideHeight(os.time())` at the moment of the award.
- Allow a **±90 s tolerance** on state checks to absorb latency and clock skew. A player
  who legitimately grabbed something 40 s before the flats flooded should not be punished.
- Reject with a soft failure ("the water took it") rather than an error. Never accuse.

## 8. Test vectors

Iteration 2's harness must assert all of these. They are computed from the constants in
§2.2 and are the contract.

> **Corrected in iteration 2.** Three of the twelve rows below were wrong when this
> document was written: they were reasoned about rather than computed. The §2.2
> constants are the contract, so the constants won and the table was fixed. The
> corrections, all now asserted in `tools/tests/pure-tests.lua`:
>
> | Row | Was | Is | Why the original was wrong |
> | --- | --- | --- | --- |
> | `TideHeight(EPOCH + T_M2)` | "within 0.9 of 15.5" | `11.2327544726` (4.267 away) | after one M2 period, S2 and K1 have both drifted; only M2 has returned to phase |
> | `LOW` entries over 30 days | `∈ [55, 65]` | **52** | the estimate assumed roughly two LOW windows per M2 cycle; the −6 threshold is only crossed on the bigger swings |
> | spring / neap daily range | `≈26.8` / `≈13.2` | `29.73` / `15.97` | the estimate computed `2*(A_M2 ± A_S2)` and forgot K1's 2.1 amplitude entirely |

| Input | Expected | Tolerance |
| --- | --- | --- |
| `TideHeight(EPOCH)` | `15.5` | 1e-9 |
| `TideVelocity(EPOCH)` | `0.0` | 1e-9 |
| `TideEpoch(EPOCH)` | `0` | exact |
| `TideEpoch(EPOCH + 22356)` | `0` | exact |
| `TideEpoch(EPOCH + 22357)` | `1` | exact |
| `TideHeight(EPOCH + T_M2)` — one M2 period on | `11.232754472632912` | 1e-9 |
| `TideHeight(t)` for any `t` | `∈ [-15.5, 15.5]` | — |
| mean of `TideHeight` over 30 days at 60 s steps | `0.0` | 0.05 |
| count of `LOW` entries over 30 days | `∈ [50, 54]` (measured: **52**) | — |
| `NextStateChange(t, 7d)` | never `nil` for any `t` | — |
| determinism | `TideHeight(t)` bit-identical across 10 000 repeated calls | exact |
| spring/neap | max daily range over 60 days peaks `≈29.73`, troughs `≈15.97` | 0.3 |

## 9. Module surface (for iteration 2)

`ReplicatedStorage > Tidekeeper > Lib > Tide (ModuleScript)`

```
Tide.EPOCH            : number          -- 1767225600
Tide.EPOCH_SECONDS    : number          -- 22357
Tide.height(t)        -> number
Tide.velocity(t)      -> number
Tide.state(t)         -> "LOW"|"EBB"|"FLOOD"|"HIGH"|"SLACK"
Tide.epoch(t)         -> integer
Tide.epochStart(n)    -> number         -- inverse of epoch()
Tide.nextStateChange(t, horizon?) -> (number, string)?
Tide.nextLowWater(t)  -> number
Tide.nextHighWater(t) -> number
Tide.rangeForDay(t)   -> (number, number)   -- for the Chart screen
```

Pure. No services, no `os.time()` inside the module — the caller passes `t` always. This
is what makes it testable and what makes offline replay possible.

**Hot-loop rule:** `Tide.height` is called every frame on the client. It must allocate
nothing and must not call `os.clock`, `os.time`, or any service. The hot-loop scanner in
`tidekeeper/tools/hot-loop-scan.js` will be pointed at this file specifically.
