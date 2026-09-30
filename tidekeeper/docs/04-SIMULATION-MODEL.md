# 04 — The Simulation Model: resolve-on-read and determinism

The technical core. If this document is implemented correctly, the game supports a
million offline posts at zero marginal cost and works offline on a phone. If it is
implemented sloppily, the game cannot scale past a few thousand players and can never
be tested.

---

## 1. The governing decision

> **A post is never simulated while its owner is offline. It is simulated forward, in
> bounded deterministic steps, at the moment the owner reads it.**

Roblox gives you no way to run a server for an absent player, and you should not want
one. The alternatives and why they lose:

| Approach | Why rejected |
| --- | --- |
| Persistent server per post | Impossible on Roblox and ruinous anywhere |
| Open Cloud Luau Execution cron | 5 min per task, 10 concurrent per place ([docs](https://create.roblox.com/docs/cloud/reference/features/luau-execution)). Fine for one global tick, hopeless for N posts. Also now shares the DataStore request budget with live servers. |
| Simulate on any server that happens to be up | Non-deterministic, contended, and costs requests proportional to population × time |
| **Resolve on read** | Cost is proportional to *sessions*, not to population × time. Exactly what we want. |

Resolve-on-read also gives us offline solo play (Roblox, mid-2027) essentially for free,
because the resolver is a pure function that does not need the network.

## 2. The state/step formulation

A post is `(S, t_r)`: state, and the wall-clock second at which that state was last
resolved.

```
Resolve(S, t_r, now, inbound[]) -> (S', entries[], t_r')
```

The resolver is:

- **pure** — no services, no `os.time()`, no yields, no `Instance`;
- **total** — defined for every input, including `now < t_r` (clock skew: no-op);
- **deterministic** — same inputs, same outputs, bit for bit;
- **bounded** — at most `MAX_EPOCHS = 27` steps (doc 02 §5), i.e. 7 days.

Everything else in the game is presentation on top of this function.

## 3. The step

The step size is **one tide epoch** (22 357 s ≈ 6 h 12 m). Not an arbitrary tick: an
epoch is exactly one tide swing, so within a step the tide state is essentially constant
in *character* (one high-to-low or one low-to-high), which is what the visit logic
depends on.

```
for e = epoch(t_r) + 1 .. min(epoch(now), epoch(t_r) + 27):
    seed  = Hash.mix(S.postId, e, S.salt)
    rng   = RNG.new(seed)
    ctx   = { epoch = e, tideAtArrival = ..., orders = S.orders, tier = S.tier }

    1. decay      Standing toward its band floor
    2. respawn    comb nodes that matured during e
    3. spoil      perishable stock
    4. arrivals   select which inbound Drifters arrive in e  (rng)
    5. for each arrival, in arrival order:
           Visit.resolve(S, drifter, ctx, rng) -> (ΔS, entry, receipt)
    6. accrue     passive income from standing orders
    7. emit       one epoch-summary ledger entry
```

Ordering within step 5 is by `Hash.mix(drifterId, e)` ascending — a stable total order
independent of the order the exchange happened to return them in. **This is essential**;
without it the resolution is not reproducible.

### 3.1 The clamp

If `epoch(now) - epoch(t_r) > 27`, we clamp. The skipped time is not silently dropped:
we emit a `LONG_ABSENCE` ledger entry that states the real gap ("You were away
nineteen days. The flats kept their own counsel.") and apply a **bounded** summary:
Standing decays to its band floor, perishables are gone, non-perishable stock survives,
and the player receives a small "found while you were away" cache so returning after a
long break is pleasant rather than punitive.

Returning players are the most valuable players a live game has. Never make the return
feel like a bill.

## 4. `Visit.resolve` — the atom

One Drifter, one post, one deterministic outcome. Roughly 150 lines of pure Luau, and
the most heavily tested function in the game.

```
Visit.resolve(S, D, ctx, rng) -> (ΔS, LedgerEntry, Receipt)
```

**Stages:**

1. **Berth check.** Does `D.class` admit at `ctx.tideAtArrival`? (doc 03 §4.) If not →
   `MISSED_TIDE`, no state change, a wistful ledger entry, a neutral receipt. This is a
   *good* outcome to receive occasionally; it teaches the tide.
2. **Gate.** Does `S.orders` admit this Drifter? Standing threshold, Current, class,
   reserved berths. If refused → `REFUSED`, small Standing loss, negative warmth.
3. **Offer.** Build the visible shelf set. Filter by order rules.
4. **Match.** Score each shelf item against `D.taste` and `D.wants`:
   ```
   score(item) = w_t * cosine(item.tasteVec, D.taste)
               + w_w * (item.id ∈ D.wants and 1 or 0)
               + w_p * pricePressure(item.price, D.budget, D.taste[2])
               + w_r * rng:normal(0, 0.12)          -- the only randomness
   ```
   Weights in `EconomyConfig`. The noise term is small and seeded; it exists so two
   identical visits do not read as scripted.
5. **Purchase.** Greedy by score while budget remains and `maxItems` (from class) is not
   exceeded.
6. **Barter.** If `D.cargo` is non-empty and orders accept barter, form a *claim*, not a
   transfer (doc 03 §9).
7. **Settle.** Compute `ΔS` (stock down, coin up), Standing delta, warmth, and the
   receipt.
8. **Narrate.** Build the ledger entry's prose from a **template + slot** system. The
   prose is generated from the numbers, deterministically. Never LLM-generated at
   runtime.

### 4.1 Prose generation

The Ledger's quality is the game's quality, so this is specified, not left to iteration 4.

An entry is `(templateId, slots[])`. Templates live in `FindsConfig`/`EconomyConfig` and
are selected by a decision table over `(outcome, warmth band, class, match quality,
notable flags)`. Example:

| Condition | Template |
| --- | --- |
| `SERVED`, warmth > 60, matched a `want` | "{name} came in on the {tidePhrase} and went straight to the {item}, like she'd known it was there." |
| `SERVED`, warmth < -20, price pressure high | "{name} bought the {item}. {pronounCap} did not look pleased about the price." |
| `MISSED_TIDE`, `DEEPWATER` | "A {class} stood off the bar for an hour and turned back. Not enough water." |
| `REFUSED`, Standing gate | "{name} was turned away at the gate. {pronounCap} left a mark on the post." |

Target: **≥ 180 templates** at v1, so a 10-visit Ledger essentially never repeats.
Iteration 5 owns writing them; iteration 4 owns the selection machinery and must ship
with ≥ 40 so the system is exercised.

## 5. Determinism: the rules

Violating any of these breaks offline replay, server verification, and the entire test
suite. The quality gate should grep for them.

| Rule | Reason |
| --- | --- |
| Never iterate a hash table with `pairs()` where order affects output | Luau table order is not guaranteed stable across runs |
| Use `Tables.sortedPairs` or explicit arrays in all resolver code | |
| Never call `math.random` | Global RNG state is shared and unseedable per-visit |
| All randomness from `RNG.new(seed)`, seeded from `Hash.mix` of stable integers | |
| Never read `os.time()`, `os.clock()`, `tick()`, or `workspace:GetServerTimeNow()` inside L0/L2 | Time is an *argument* |
| Never use floating-point accumulation across steps for anything that must match | Accumulate in integers; convert at the edge |
| All money and stock are **integers** | No float drift in the economy, ever |
| `Hash.mix` must be a fixed, documented 32-bit function | It is part of the save format |
| No `#table` on tables with holes | Undefined length |
| Client-side replay must call the *same* `Visit.resolve` | Not a reimplementation |

### 5.1 The replay proof

Iteration 2's harness must include this test, and it is the single most important test
in the project:

```
given a fixed post state, a fixed drifter list, and a fixed time span,
  run Resolve 1000 times
  assert every run produces byte-identical (S', entries, receipts)

given the same inputs,
  run Resolve once on "server" and once via the client replay path
  assert identical
```

## 6. Chunking — how it runs without a hitch

Resolve is pure, but it is not free. Worst case is 27 epochs × up to 24 Drifters = 648
`Visit.resolve` calls. At a measured target of ≤ 18 µs per visit that is ~11.7 ms — a
frame's worth, on a server also doing other things.

So `CadenceService` runs it in the `resolve` slot, **4 epochs per tick**, ≤ 12 ms per
tick, max 7 ticks. The client covers the gap with the Ledger's opening animation, which
takes ~2 s anyway. The player never sees a hitch, and the server never blows a frame.

**Budget to hold iteration 2 to:** `Visit.resolve` ≤ **18 µs** median, ≤ 50 µs p99,
**zero allocations** in the steady path (use `Tables` pooling for the scratch arrays).
The harness must measure and report this, not assert it by eye.

## 7. The Ledger as replay, not log

Because resolution is deterministic and the entries carry their seeds, the client can
*re-derive* the whole sequence and play it back as an animated scene: the boat comes in,
the figure walks the pier, picks things up, the tide silhouette behind it moves.

This costs almost nothing (the data is already there) and is the difference between
"a list of transactions" and the reason people play the game. It is also why
`Visit.resolve` must be in `ReplicatedStorage`, not `ServerStorage` — the client needs
it. The client having the algorithm is not a security problem: the client never has the
*authority*, only the ability to reproduce what the server already decided.

## 8. Testability contract

Every function in L0 and L2 is testable with no Roblox instance at all. The harness
(`tidekeeper/tools/tidekeeper-smoke-test.js`, iteration 2) loads the real modules into a
Lua VM with a minimal mock and asserts behaviour, in the sibling project's proven style.

Required coverage at the end of iteration 2:

| Area | Assertions |
| --- | --- |
| Tide (doc 02 §8 vectors) | ≥ 30 |
| RNG determinism + distribution | ≥ 20 |
| Codec round-trip (Drifter, Post, Receipt) | ≥ 40 |
| Orders interpreter | ≥ 50 |
| `Visit.resolve` outcomes, all 5 | ≥ 80 |
| `Resolve` bounds, clamp, monotonicity | ≥ 40 |
| Determinism proofs (§5.1) | ≥ 10 |
| Economy invariants (§9) | ≥ 30 |
| **Total** | **≥ 300** |

## 9. Economy invariants the harness must prove

These are safety properties. A violation is a duplication bug or an inflation bug, and
both are fatal to a trading game.

1. **Conservation.** Across any `Resolve`, `Σ stock_out + Σ stock_kept == Σ stock_in`.
   Nothing is created except by explicit, logged generation (comb nodes, passive income).
2. **No negative.** No stock, coin, Standing or Renown value may go below its floor.
3. **Monotonic time.** `t_r'` is strictly ≥ `t_r`, and ledger entries are ordered by
   `(epoch, arrivalOrder)`.
4. **Bounded generation.** Passive income per epoch ≤ `EconomyConfig.PassiveCap[tier]`.
5. **Idempotent claim.** Resolving the same Drifter twice is impossible — claiming
   removes it from the shard in the same `UpdateAsync`.
6. **Receipt exactly once.** Each resolved visit yields exactly one receipt.
7. **Clamp safety.** A 400-day absence resolves in bounded time and leaves valid state.

## 10. Migration and versioning

The save format *will* change. Design for it from the first byte.

- Every persisted blob starts with a `uint8` schema version.
- `Shared/Version` holds a registry `{from -> to -> migrate(blob)}`; load applies the
  chain. Migrations are pure and unit-tested with real captured blobs.
- **Never** delete a migration. The oldest supported version is `1` forever.
- A blob whose version is *newer* than the running server (rollback scenario) is
  **refused**, not guessed at. The player is kicked with a clear message. Guessing
  corrupts.
- Iteration 3 must ship a `tools/fixture-blobs/` directory of real captured payloads,
  and the harness must migrate each to current on every run.

## 11. Offline solo play (mid-2027)

Recorded now because the design gets it nearly free, and iteration 5 should not have to
rearchitect.

In an offline session there is no exchange, so:

- inbound Drifters come from a **locally cached pool** written at the last online session
  (up to 48, ~3.3 KB);
- receipts accumulate locally and are flushed on reconnect;
- the tide is computed identically (it only needs the device clock);
- the resolver is unchanged.

The only new work is a reconciliation path for the case where the player played offline
and then online on another device. Policy: **last-write-wins on the post, union on the
ledger**, with the conflict noted in the Ledger. Iteration 5, not before.
