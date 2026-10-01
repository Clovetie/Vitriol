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
| DataStore per-server rate (default) | **`60 + numPlayers × 40`**/min read, write and remove; `5 + numPlayers × 2`/min list. Creator-configurable with `SetRateLimitForRequestType` | [error codes and limits](https://create.roblox.com/docs/cloud-services/data-stores/error-codes-and-limits) |
| DataStore per-experience rate | read `300 + CCU × 40`, write `300 + CCU × 20`, list `300 + CCU × 2`, remove `300 + CCU × 40` per minute — **shared with Open Cloud** | same |
| DataStore per-key throughput | read 25 MB/min, write **4 MB/min**, rounded up to the next KB per request | same |
| MemoryStore total memory | **64 KB + 1.2 KB × [number of users]**, per *universe* | [creator-docs](https://github.com/Roblox/creator-docs/blob/main/content/en-us/cloud-services/memory-stores/index.md) |
| MemoryStore request units | **`1000 + 120 × CCU`** per minute, universe-wide | same |
| MemoryStore per-structure | 100 000 request units/min; sorted map/queue 1 M items, 100 MB (**including keys**) | same |
| MemoryStore per-partition | throttling begins ≈30 000 request units/min; hash-map per key ≈5 000 write / 15 000 read | same |
| MemoryStore item size | key ≤ 128 B, value ≤ 32 KB | same |
| MemoryStore HashMap | no item-count or per-structure memory limit; universe quota still applies | [HashMap beta](https://devforum.roblox.com/t/memorystore-hashmap-beta/2977379) |
| Open Cloud Luau Execution | 5 min/task, **10 concurrent per place** | [docs](https://create.roblox.com/docs/cloud/reference/features/luau-execution) |
| Open Cloud from HttpService | 2 500 OC requests/min/server | creator docs |
| Experience Notifications | 13+, opted in, **1/user/day/experience** | [rate limits](https://devforum.roblox.com/t/updates-to-notification-rate-limits/3007106) |

> **Re-verified 2026-10-01 (iteration 3).** Four rows above changed and are corrected in
> place; the derivations they feed did not change materially. The MemoryStore request
> quota is `1000 + 120 × CCU`, not `100 × CCU`. The DataStore per-server figure was not
> "~60/min" — that is only the constant term. The per-experience and per-key throughput
> limits were missing entirely and are the ones that actually bind. The 500 MB + 1 MB
> storage limit is confirmed against the primary doc and is measured on the *compressed*
> size of the latest version of each key. Full audit trail in
> [`10-RESEARCH-NOTES.md`](10-RESEARCH-NOTES.md) §6.2.

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

### 6.1 Schema v2 — the first real migration (iteration 4)

`SCHEMA_VERSION` went 1 → 2 to persist `publishedAt`. The change is deliberately the
*cheapest possible* shape, because the point of doing it in iteration 4 rather than at
launch was to prove the migration machinery on a field nobody would miss:

- **Append at the tail, never insert.** v2 is byte-for-byte v1 followed by one `u32`
  and then the checksum. A v1 reader that ignored the tail would still parse the head.
- **Decode order is fixed:** version byte → `Version.classify` → checksum → parse (the
  tail read is conditional on the version) → `Version.migrate`. Migration runs *after*
  the `pcall`, so a malformed blob is rejected before any migration code sees it.
- **`registerMigrations()` is idempotent**, so requiring the codec twice is safe.
- **A genuine v1 blob is committed as a fixture** (`tools/fixture-blobs/post-v1.b64`,
  249 bytes, base64). **D24: fixtures are never edited and never regenerated.** A
  regenerated fixture tests the current code against itself and proves nothing; the
  whole value is that those bytes were written by code that no longer exists.

**The bug this shipped with, and what it cost.** `publishedAt` was first written as
`0 = never published`. `Tide.epoch(TideConfig.EPOCH)` is **0** — epoch 0 is a real
epoch, the first one — so a post created in the first 6.2 hours of the game read as
"already published at epoch 0" and `ExchangeService:publish` refused it forever. Six
previously-green session assertions went red at once and the cause looked like the
unrelated client work landing in the same iteration.

**D28: a sentinel must be impossible to confuse with a legal value.** The fix is that
`publishedAt` is **absent** in memory for "never", and the codec stores **`epoch + 1`**
on the wire so that wire-0 is unambiguous. Check a sentinel against the *range* of the
field, not against what looks empty.

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

### 7.1 What iteration 3 learned building it

**Releasing a lock is a `RemoveAsync`, not an `UpdateAsync` returning `nil`.**
Returning `nil` from a MemoryStore transform *aborts the update*; it does not delete
the key. The first implementation read as "transform the lock into nothing" and in
fact never released anything, so every lock sat until its 90-second TTL expired and a
player who rejoined quickly was locked out of their own post. There is no atomic
compare-and-delete in the API, so ownership is checked against the token the adapter
itself issued and the delete is unconditional after that. The residual race — our lock
expires, another server takes it, we then remove theirs — costs a redundant
acquisition, never a double write, because `savePost` re-checks ownership.

**`holdsLock` must not cost a request.** Reading the lock before every save spent one
MemoryStore request per session to learn something the adapter already knew. The
refresh on the `slow` slot is the authority; between refreshes the locally recorded
token is the answer, and it is never staler than one refresh interval.

**No lock service means no lock, not no game.** If MemoryStore is throttled or over
quota, `acquireLock` degrades to running unlocked and counts it
(`stats.unlockedSessions`), per [`01-ARCHITECTURE.md`](01-ARCHITECTURE.md) §8. The
alternative — refusing every join while the index is unavailable — turns a degraded
side system into a total outage.

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

Two reapers, both idempotent, both rate-limited:

1. **Pool reaper** — deletes `DrifterPool` shards older than `epoch - 28`. One shard per
   **IO** tick maximum, on one leaseholding server. A shard deleted twice is harmless,
   and most shards were never written at all (a shard exists only if a drifter hashed
   into it).
2. **Ledger reaper** — written in iteration 10, and it costs nothing extra because it
   runs where the information already is. `allocLedgerPage` keeps the player's page
   list; when a new page pushes the list past `LEDGER_PAGES_KEPT` (32) the oldest
   numbers fall out of the index and are handed straight back to the caller, which
   deletes exactly those keys. No scan, no probe, no schedule.

Never run a reaper from Open Cloud during peak hours: since 2026-07-29 it competes with
live servers for the same request budget.

**Status, iteration 9 — the pool reaper is scheduled (OD21 closed).**

`ExchangeService:reapTick` runs on the **IO** slot (5 s), deletes **one** shard per
tick, and targets exactly one epoch: `epoch - (MAX_CATCHUP_EPOCHS + 1)` = `epoch - 28`.
Nothing can ever claim a key that old, because a resolve clamps its catch-up to 27
epochs. Below epoch 28 the whole thing is a no-op rather than a wrap into negative
epochs, which is tested.

**Which server reaps: exactly one, by lease.** 5 Currents × 64 shards = 320 keys per
epoch. Twenty servers each deleting the same 320 keys is twenty times the request
budget for the same result, so the server that wants the job first takes a MemoryStore
lease — `MemoryAdapter:tryLease(name, token, ttl)`, the same atomic transform as the
post lock — keyed `reap:<epoch>` with a 2-hour TTL. Losers record `reapLeasesLost` and
skip, re-offering at the next epoch. One shard per 5 s clears 320 keys in ~27 minutes,
comfortably inside the 6.2-hour epoch that produces them.

If MemoryStore is **unavailable**, `tryLease` returns false and **nobody** reaps. That
is deliberately the safe direction: a missed reap is growth visible in the metrics,
whereas twenty servers reaping blind during an outage makes the outage worse.

Counters: `shardsReaped`, `reapLeasesWon`, `reapLeasesLost`.

**Status, iteration 10 — ledger history is readable, and the ledger reaper exists
(OD22 closed).** See §9.2.

## 9.2 Ledger pages: numbering, reading, retention (OD22)

Entries evicted past `MAX_LEDGER_RESIDENT` (200) are archived to pages. Until
iteration 10 `loadLedgerPage` was **called by nothing**, so everything older than the
most recent 200 entries was written to DataStore and unreadable forever. The Ledger
carries this game's whole argument — doc 00's first pillar is *absence is content* —
so a Ledger that quietly forgets is the game failing at the one thing it is for.

**There was no way to read it back even in principle.** A page key was
`l:<userId>:<epoch>` and nothing recorded *which* epochs had pages, so a reader would
have had to probe ~700 keys to cover the retention window.

**And the epoch was not a safe key.** `saveLedgerPage` overwrites. Two servers
flushing a page for the same player inside one 6.2-hour epoch — an ordinary server
hop — silently destroyed one of the two pages.

| concern | how it works now |
| --- | --- |
| numbering | `allocLedgerPage` takes the next number from a counter in one index key per player, in a single `UpdateAsync`. Atomic, so it is also the cross-server fix |
| ordering | allocate **first**, then write the page. A failed allocation writes nothing, so no page is ever orphaned under a number the index does not know |
| index | `li:<userId>` → `{next, pages}`. One read lists a player's whole archive |
| retention | `LEDGER_PAGES_KEPT = 32`. Numbers falling out of the window come back from the allocation and their keys are deleted there and then |
| reading | `LedgerService:history(userId, cursor)` → `(entries, nextCursor, total)` |
| cursor | counts **back from the newest** page: 0 is the most recent. A cursor counted from the oldest would slide under a reader every time a page was reaped |
| a hole | a page in the index that will not load reports empty but **keeps the cursor moving**, so one unreadable page cannot hide every older page behind it |
| cost | one index read + one page read per call, which is why `RF_History` is throttled to 2 burst / 10 per minute. Paging is a deliberate tap, not a scroll |

## 9.1 The failed-save recovery queue

When `savePost` abandons a write — a stale session lock, or an exhausted retry budget —
the payload goes to a MemoryStore queue rather than being dropped. This is the last
line of defence against losing a player's session.

Through iteration 7 **nothing drained it**: `pushRecovery` was called, `popRecovery`
was not, so the net caught the blob and let it expire. `PostService:sweepRecovery` now
runs on an idle `slow` tick (only when this server owes no save, so a healthy server
pays one MemoryStore read and nothing more).

The guard is the part that matters. By the time a blob is retried, the server that took
the lock may already have written something newer, so a blind restore would *cause* the
loss the queue exists to prevent. Three outcomes per entry:

| Situation | Action |
| --- | --- |
| The player is resident on this server | **Defer.** We hold the lock and will write something newer ourselves |
| The stored post is newer than the blob | **Drop.** The entry is obsolete; acking it is the correct ending |
| Otherwise | **Restore**, then ack |

The restore is an `UpdateAsync` whose transform returns `nil` — which aborts the write
without consuming a conflict — when the stored value wins. And because `ReadAsync`
returns **one id for the whole batch**, the ack is all-or-nothing: if any entry in a
batch was deferred or failed, the batch is left unacked and the 30 s invisibility
window re-presents it to the next sweep. Slower, and it cannot lose a blob.

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

Iteration 3 shipped this. [`tools/tests/fake-platform.lua`](../tools/tests/fake-platform.lua)
is a fake **DataModel**, not a fake adapter: it implements `DataStoreService`,
`MemoryStoreService`, `Players`, `RunService` and `PolicyService`, and the **real**
`DataStoreAdapter` and `MemoryAdapter` run against it unmodified. Faking the adapter
would have meant faking exactly the code that needed testing — the retry
classification, the budget deferral, the `UpdateAsync` transforms, the lock protocol.

It models:

- request counts per type, and the per-server per-minute budgets
  (`60 + numPlayers × 40`, list `5 + numPlayers × 2`), with `UpdateAsync` decrementing
  both read and write;
- deterministic failure injection using the **error strings Roblox actually
  produces** — `DataUpdateConflict`, `TotalRequestsOverLimit`, `TotalMemoryOverLimit`,
  `RequestThrottled` — because the adapter classifies by matching them;
- a virtual clock, so the real backoff schedule (0, 0.5, 1.5, 4, 9 s) is exercised at
  full speed and a 30-day lifetime runs in 16 seconds;
- MemoryStore hash maps and a queue with TTL expiry on the same clock.

It deliberately does **not** model real concurrency: two "servers" are two adapter
instances over one backend, interleaved explicitly by the test. Real threads would make
the suite nondeterministic, which is the one thing it may not be.

[`tools/tests/session-tests.lua`](../tools/tests/session-tests.lua) runs 14 scenarios
and 72 assertions: cold start, round trip, **a failed read must never look like a new
player**, `DataUpdateConflict` retry, quota errors failing fast, MemoryStore
degradation, two-server lock contention, at-most-once delivery, the Ledger never being
empty, the notification path being disabled, chunk-plan purity, cadence accounting, the
30-day/200-session measurement, and `BindToClose`.

It found three real defects on its first green run; they are tabulated in
[`03-ASYNC-SOCIAL.md`](03-ASYNC-SOCIAL.md) §6.3. Two of them silently destroyed player
history and neither was findable by reading the code.
