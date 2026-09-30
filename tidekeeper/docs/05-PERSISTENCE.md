# 05 — Persistence, Budgets and Wire Formats

Every number here is derived from a documented 2026 platform limit. Sources are in
[`10-RESEARCH-NOTES.md`](10-RESEARCH-NOTES.md).

---

## 1. The limits we are designing against

| Limit | Value | Source |
| --- | --- | --- |
| DataStore total storage | **500 MB + 1 MB × lifetime users** (from 2026-07-29; was 100 MB) | [limit change](https://bloxbot.ai/guide/roblox-datastore-limits-july-2026) |
| DataStore request budget | in-game **and** Open Cloud now share **one** per-experience budget | same |
| DataStore value size | 4 MB per key | creator docs |
| DataStore server rate | ~60 requests/min/server, 6/s | creator docs |
| MemoryStore total memory | **64 KB + 1.2 KB × [number of users]**, per *universe* | [creator-docs](https://github.com/Roblox/creator-docs/blob/main/content/en-us/cloud-services/memory-stores/index.md) |
| MemoryStore request units | `1000 + 100 × CCU` per minute, universe-wide | same |
| MemoryStore per-structure | 100 000 request units/min; sorted map/queue 1 M items, 100 MB | same |
| MemoryStore item size | key ≤ 128 B, value ≤ 32 KB | same |
| MemoryStore HashMap | no item-count or per-structure memory limit; universe quota still applies | [HashMap beta](https://devforum.roblox.com/t/memorystore-hashmap-beta/2977379) |
| Open Cloud Luau Execution | 5 min/task, **10 concurrent per place** | [docs](https://create.roblox.com/docs/cloud/reference/features/luau-execution) |
| Open Cloud from HttpService | 2 500 OC requests/min/server | creator docs |
| Experience Notifications | 13+, opted in, **1/user/day/experience** | [rate limits](https://devforum.roblox.com/t/updates-to-notification-rate-limits/3007106) |

**The one that shapes everything: MemoryStore's quota is tiny and universe-wide.** At
1 000 CCU it is ~1.2 MB *total*. Treat MemoryStore as a coordination cache, never as
storage. See [`03-ASYNC-SOCIAL.md`](03-ASYNC-SOCIAL.md) §6.

## 2. Key map

| Store | Key | Value | Size | TTL |
| --- | --- | --- | --- | --- |
| DS `Post` | `p:{userId}` | packed post blob | ≤ **6 KB** | forever |
| DS `Ledger` | `l:{userId}:{page}` | 64 entries | ≤ **8 KB** | 180 d, reaped |
| DS `DrifterPool` | `c{cur}:e{epoch}:s{shard}` | ≤ 200 packed Drifters | ≤ **13.3 KB** | reaped at epoch+28 |
| DS `Receipts` | `r:{ownerId % 256}` | pending receipts | ≤ **16 KB** | drained on read |
| DS `Showcase` | `s:{week}:{bucket}` | Renown aggregates | ≤ **32 KB** | 8 weeks |
| DS `Meta` | `m:global` | season, event flags, schema floor | ≤ 1 KB | forever |
| MS Hash `xidx` | `c{cur}:e{epoch}` | shard fill bitmap | 26 B | 2 epochs |
| MS Hash `lock` | `p:{userId}` | session lock token | 24 B | 90 s |
| MS Queue `recov` | `recov` | failed-save payload refs | — | 24 h |

**Total live footprint at 10 000 DAU:** posts ~60 MB, ledgers ~40 MB (paged, reaped),
pool ~8.5 MB, receipts ~4 MB. Well inside `500 MB + 10 GB`.

## 3. Post blob — 6 KB budget

The single most important size constraint in the game. A post must serialise to ≤ 6 KB
including the base64/JSON overhead DataStore imposes on binary.

| Section | Bytes | Notes |
| --- | --- | --- |
| header (`v`, `postId`, `salt`, `t_r`, `tier`, `season`) | 24 | |
| coin, Standing × 5, Renown | 26 | integers |
| shelves (≤ 24 × {findId u16, qty u16, price u32, arrange u16}) | 240 | |
| store (≤ 120 × {findId u16, qty u16}) | 480 | non-shelf stock |
| standing-orders program | ≤ 1 024 | see doc 06 §5, bytecode not text |
| almanac bitset (256 finds) | 32 | |
| comb-node state (≤ 96 × u16 maturity) | 192 | |
| recent hosts/visitors ring (48 × u48) | 288 | fairness cooldowns, doc 03 §9 |
| taste accumulators (8 × i32 + counts) | 64 | |
| pending barter claims (≤ 16 × 12 B) | 192 | |
| cosmetics / layout | ≤ 512 | |
| offline drifter cache (≤ 48 × 68 B) | 3 264 | **only written for offline-enabled sessions** |
| **subtotal, online** | **≈ 3 100 B** | |
| **subtotal, offline-enabled** | **≈ 6 360 B** | over budget → see below |

**Decision:** the offline Drifter cache does **not** live in the post blob. It goes in a
second key `po:{userId}`, written only when offline play is enabled for that user. This
keeps the hot path at ~3.1 KB and one request. Recorded as a binding decision for
iteration 3.

### 3.1 Encoding

`buffer` + manual bit packing, then `base64` for DataStore. Do **not** use
`HttpService:JSONEncode` on the hot blob — it is 3–4× larger and slower. JSON is used
only for the `Meta` key, which is human-edited.

## 4. Drifter wire format — 68 bytes

```
offset size field         notes
  0     1   v             schema version
  1     8   id            owner*8192 + (epoch mod 8192)  -- see the note below
  9     8   owner         userId
 17     4   epoch         int32
 21     1   current       0..4
 22     1   class         0..3
 23     1   tier          1..4
 24     2   standing      banded u16
 26     2   renown        banded u16
 28     4   budget        u32
 32     8   taste         8 × i8
 40     8   wants         4 × u16
 48     8   cargo         4 × u16
 56     2   letterId      u16
 58     1   beacons       u8
 59     4   look          u32 packed cosmetics
 63     4   checksum      FNV-1a over bytes 0..62
 67     1   reserved      must be 0
```

`checksum` is not security — it is corruption detection across a store that has been
migrated. A bad checksum drops the Drifter silently and increments a counter.

> **Corrected in iteration 2 — the `id` construction.** This document originally
> specified `id = (userId << 24) | epochLow`. **That is not representable.** Roblox user
> ids already exceed 2^32; shifting one left by 24 produces a value above 2^53, which a
> Luau `number` (an IEEE-754 double) cannot hold exactly. The id would silently round,
> and two different Drifters would collide with no error anywhere.
>
> The shipped construction is `id = owner * 8192 + (epoch mod 8192)`
> (`GameConfig.DRIFTER_ID_EPOCH_SPAN = 8192`, `OWNER_ID_MAX = 2^40`):
>
> - exact for every owner below 2^40, which is ~200× the largest user id in existence;
> - still 8 bytes on the wire, so the record stays 68 bytes;
> - unique per owner for 8192 consecutive epochs (~5.8 years), and Drifters expire after
>   seven days.
>
> The visitor ring in the post blob packs `(owner, epoch)` the same way, into a u48.
> `DrifterCodec.makeId` refuses an out-of-range owner rather than rounding.

## 5. Receipt wire format — 28 bytes

```
  0  1  v
  1  8  drifterId
  9  8  hostId
 17  4  epoch
 21  1  outcome
 22  4  spent
 26  1  warmth (i8)
 27  1  flags  (bit0 noteId present -> 2 extra bytes appended)
```

## 6. Ledger entry — 24 bytes + slots

Entries are `(templateId u16, epoch i32, actorId u64, slotCount u8, slots[])` where each
slot is a `u32` tagged union (find id / integer / name index / phrase index). Prose is
reconstructed on the client from `templateId` + slots, so the *text* is never stored and
can be re-translated or rewritten in a later patch without a migration. This is a
deliberate localisation and live-ops affordance.

## 7. Session locking

Roblox can run two servers for one player briefly (teleport, rejoin race). Without a
lock this duplicates stock.

- Acquire `MS lock p:{userId}` with a 90 s TTL and a random token on load.
- Refresh every 30 s in the `io` cadence slot.
- On load, if the lock is held by another token, wait up to 6 s, then **retry once**,
  then refuse the session with "your post is still closing up". Never load anyway.
- On save, verify the token still matches before `UpdateAsync`. If not, **abandon the
  write** and push the payload to the `recov` queue. Losing a session is survivable;
  overwriting a newer save is not.

## 8. Retry policy

All adapter calls use the same policy. Implement once in `DataStoreAdapter`.

| Attempt | Delay | Notes |
| --- | --- | --- |
| 1 | 0 | |
| 2 | 0.5 s + jitter | |
| 3 | 1.5 s + jitter | |
| 4 | 4 s + jitter | |
| 5 | 9 s + jitter | last |

Exponential with jitter, as the creator docs recommend for `DataUpdateConflict`. Never
retry a `UpdateAsync` whose transform already succeeded — `UpdateAsync` is the retry
primitive, use it rather than get-then-set.

Budget guard: before any call, check `DataStoreService:GetRequestBudgetForRequestType`
and defer if below a floor of 8. The `BudgetMeter` diagnostic exposes this live.

## 9. Reaping

Two reapers, both on the `slow` cadence slot, both idempotent, both rate-limited:

1. **Pool reaper** — deletes `DrifterPool` shards older than `epoch - 28`. One shard per
   slow tick maximum. A shard deleted twice is harmless.
2. **Ledger reaper** — deletes ledger pages older than 180 days on the owner's own load,
   costing nothing extra.

Never run a reaper from Open Cloud during peak hours: since 2026-07-29 it competes with
live servers for the same request budget.

## 10. Open Cloud usage

Exactly two sanctioned uses. Anything else needs a written decision in `ROADMAP.md`.

1. **Nightly Currents tick** — one Luau Execution task that rotates seasonal modifiers
   and writes `Meta m:global`. Runs at the global traffic trough. ≤ 1 task, ≤ 60 s.
2. **CI** — running the headless test suite against an uploaded place, per the
   [official CI/CD demo](https://github.com/Roblox/place-ci-cd-demo).

**Not** sanctioned: per-player simulation, bulk migration during peak, notification
fan-out over DataStore scans (the rate limits make this hopeless — a community report
measured 5.5 hours to read 100 000 entries at 300 req/min
([devforum](https://devforum.roblox.com/t/experience-notifications-and-rate-limits/4615621))).
Notification targeting is derived at **logout**, not by scanning.

## 11. Testing persistence without Roblox

Iteration 3 must ship an in-memory fake implementing the exact adapter interface,
including:

- injected failures at a configurable rate,
- `DataUpdateConflict` simulation on concurrent `UpdateAsync`,
- quota exhaustion,
- budget starvation,
- lock contention between two simulated servers.

The session harness then runs the full join → resolve → save → rejoin cycle against the
fake and asserts the economy invariants of doc 04 §9 across a simulated 30-day,
200-session lifetime. That test is what will catch the duplication bug before players do.
