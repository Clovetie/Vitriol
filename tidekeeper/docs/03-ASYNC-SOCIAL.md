# 03 — The Drifter Exchange

This is the game's differentiator and its hardest engineering problem. Everything else
in TIDEKEEPER is a well-understood cozy simulator. This is the part that has not been
built on Roblox before.

---

## 1. The claim

> Every visitor to your post is a real player, and that player gets a real consequence
> back — **without either of you ever being online at the same time.**

Not "an NPC modelled on player data". Not "a ghost replay". A specific account's
specific preferences, budget, cargo and letter, arriving at your post, being served or
refused by *your* rules, producing a receipt that lands in *their* Ledger.

## 2. Why this is worth the complexity

| Problem it solves | How |
| --- | --- |
| **Cold start** — new games feel dead | The Ledger is full from session one. Population is felt, not seen. |
| **Idle games are lonely** | Grow a Garden's loop is excellent and solitary. This is that loop with people in it. |
| **Trading economies need liquidity** | Adopt Me needs two people online and negotiating. Async trade needs neither. |
| **Judgement games need co-presence** | Dress to Impress needs a full lobby. Showcase ratings accumulate asynchronously. |
| **Mobile sessions are short** | 40% shorter on mobile per community analytics. A 4-minute session is a *complete* async turn. |
| **Timezone fragmentation** | A player in Bangkok and a player in Ohio interact properly for the first time. |

And the platform reason: Roblox is shipping a notification system specifically for
turn-based asynchronous multiplayer (Studio Beta October 2026, full release by end of
2026). Being the flagship use of a brand-new platform affordance is a discovery
advantage that does not come around often.

## 3. The Drifter

A Drifter is the compact, serialisable snapshot of a player as a *visitor*. It is built
**on the server at logout** from authoritative state — never from a client payload.

```
Drifter = {
  v        : uint8      -- schema version
  id       : uint64     -- (userId, epoch) packed; globally unique
  owner    : uint64     -- userId, for receipt routing
  epoch    : int32      -- tide epoch of publication (doc 02 §5)
  current  : uint8      -- which of the 5 Currents this drifter travels
  class    : uint8      -- SKIFF | LAUNCH | LUGGER | DEEPWATER  (see §4)
  tier     : uint8      -- owner's post tier, 1..4
  standing : uint16     -- owner's Standing in `current`, banded
  renown   : uint16     -- owner's Renown, banded
  budget   : uint32     -- spendable, in the trade unit
  taste    : int8[8]    -- the taste vector, §5
  wants    : uint16[4]  -- up to 4 specific find IDs sought
  cargo    : uint16[4]  -- up to 4 find IDs offered in barter
  letterId : uint16     -- index into the fixed-phrase table
  beacons  : uint8      -- prestige count, shown to the host
  look     : uint32     -- packed cosmetic descriptor for the visual
}
```

**Wire size: 68 bytes** packed (`DrifterCodec`). See [`05-PERSISTENCE.md`](05-PERSISTENCE.md)
§4 for the exact bit layout. 68 bytes is the number the whole storage design hangs on.

### 3.1 What a Drifter is not

- It is not the player's inventory. Cargo is at most 4 items and is **copied, not moved**
  in v1 — a Drifter spends *budget*, and barter is resolved as a claim the owner accepts
  or declines on return. This removes an entire class of duplication exploits.
- It is not live. A Drifter is a snapshot; if the owner logs back in and changes
  everything, the already-published Drifter is unaffected. Stale is fine and is part of
  the fiction: they are *at sea*.
- It is not persistent forever. TTL is **7 days** or until consumed, whichever first.

## 4. Drifter classes and the tide

The class is assigned from the owner's post tier and the tide state at publication. This
is what couples the async system to the world clock, and it is the mechanic that makes
the tide matter socially rather than just decoratively.

| Class | Owner tier | Can dock when host tide is | Budget band | Frequency |
| --- | --- | --- | --- | --- |
| `SKIFF` | 1+ | any | 1× | 55% |
| `LAUNCH` | 2+ | not `LOW` | 2.2× | 25% |
| `LUGGER` | 3+ | `SLACK` or `HIGH` | 5× | 14% |
| `DEEPWATER` | 4 | **`HIGH` only** | 14× | 6% |

Consequence: a `DEEPWATER` trader can only ever be served if their arrival lands in your
high-water window. Your standing orders can hold a berth open for one. This is the
single most interesting decision in the standing-order language, and it is why the tide
is not decoration.

## 5. Taste — how a visit becomes interesting

`taste` is an 8-dimensional `int8` vector, each axis in `[-100, 100]`. It is derived
from what the owner has *actually done*, not from a questionnaire.

| Axis | Derived from |
| --- | --- |
| 0 `Salvage↔Craft` | ratio of found to made items sold |
| 1 `Plain↔Ornate` | Almanac entries by ornateness tag |
| 2 `Cheap↔Dear` | median price the owner sets |
| 3 `Hoard↔Spend` | stock retained vs. sold, 14-day window |
| 4 `Solitary↔Social` | dispatch rate and letters sent |
| 5 `Shallow↔Deep` | fraction of beachcombing in outer zones |
| 6 `Steady↔Erratic` | variance in session timing |
| 7 `Kind↔Shrewd` | rate of accepting unprofitable barters |

A visit's **satisfaction** is a function of how well your shelf offer matches the
Drifter's taste. Match well and you earn Standing and a warm receipt; match badly and
they leave a cold one. Because taste is derived from real behaviour, the population of
Drifters is genuinely heterogeneous in a way a designer could not hand-author — and it
drifts as the playerbase's behaviour drifts.

Taste is **never shown as numbers**. It surfaces as prose in the Ledger ("she turned the
ornate lamp over twice and put it back") and as a fuzzy 3-band hint in the Chart.

## 6. The exchange — storage architecture

This is where the platform's real limits bite, and the design is shaped entirely by one
number.

### 6.1 The binding constraint

MemoryStore's memory quota is **`64 KB + 1.2 KB × [number of users]`**, per *universe*,
not per server ([Roblox creator docs](https://github.com/Roblox/creator-docs/blob/main/content/en-us/cloud-services/memory-stores/index.md)).

At 1 000 CCU that is ~1.2 MB total. At 68 bytes per Drifter that is ~17 600 Drifters
*if MemoryStore held nothing else*, which it must not. **MemoryStore cannot be the
Drifter pool.** Any design that puts the pool there falls over at exactly the moment the
game succeeds.

### 6.2 The two-tier design

```
        publish (logout)                          claim (login)
             │                                          ▲
             ▼                                          │
   ┌───────────────────┐                     ┌──────────────────────┐
   │  HOT: MemoryStore │  index only         │  ExchangeService     │
   │  HashMap          │  ~26 B/entry        │  claim(current,      │
   │  key: cur:epoch:sh│  TTL 2 epochs       │        epochs[],     │
   │  val: packed ids  │                     │        n)            │
   └─────────┬─────────┘                     └──────────┬───────────┘
             │                                          │
             ▼                                          ▼
   ┌────────────────────────────────────────────────────────────────┐
   │  WARM: DataStore  `DrifterPool`                                │
   │  key: "c{current}:e{epoch}:s{shard}"   shard = id % 64         │
   │  value: array of up to 200 packed Drifters (~13.3 KB)          │
   │  TTL: deleted after epoch+28 by the reaper                     │
   └────────────────────────────────────────────────────────────────┘
```

- **HOT** holds only *which shards are non-empty and roughly how full*, so a claim knows
  where to look without scanning. ~26 bytes per shard entry, 64 shards × 5 currents ×
  2 live epochs = 640 entries ≈ **17 KB**. Comfortably inside quota at any CCU.
- **WARM** holds the Drifters themselves in DataStore, which as of **29 July 2026** has a
  baseline of **500 MB + 1 MB per lifetime user**
  ([limit change](https://bloxbot.ai/guide/roblox-datastore-limits-july-2026)). At
  13.3 KB per shard and 640 live shards that is ~8.5 MB of live pool. Trivial.
- **Claim is a single `UpdateAsync`** on one warm shard: read the array, take `n`
  Drifters from the tail, write back the remainder. Atomic, no duplication, no lock.

### 6.3 Request budget

The important 2026 change: in-game and Open Cloud DataStore requests now share **one
per-experience budget**. Any Open Cloud backfill competes with live servers. Budget
accordingly and never run a migration during peak.

Per player session the exchange costs:

| Operation | Calls | When |
| --- | --- | --- |
| claim inbound | 1–3 `UpdateAsync` | join |
| read hot index | 1 `GetAsync` (MemoryStore) | join |
| publish drifter | 1 `UpdateAsync` | leave |
| write hot index | 1 `UpdateAsync` (MemoryStore) | leave |
| deliver receipts | batched into the post save | leave |

**5 requests per session.** A 30-player server cycling every 12 minutes costs ~150
requests / 12 min = ~12/min. Far inside budget.

## 7. Receipts — closing the loop

A receipt is what makes this a *social* system rather than a clever NPC generator.

```
Receipt = {
  v, drifterId, hostId, epoch,
  outcome   : SERVED | REFUSED | PARTIAL | MISSED_TIDE | NO_BERTH,
  spent     : uint32,
  got       : uint16[4],      -- find IDs received
  hostTier  : uint8,
  hostBeacons : uint8,
  warmth    : int8,           -- -100..100, how well the host treated them
  noteId    : uint16          -- fixed-phrase reply, optional
}
```

**28 bytes packed.** Receipts are delivered by writing into the *owner's* pending-receipt
list, which lives in the owner's own DataStore key — so delivery costs nothing extra: it
is folded into a write that was going to happen anyway.

Delivery path: the host's server, having resolved the visit, appends the receipt to
`Receipts:{ownerShard}` (a DataStore key sharded by `ownerId % 256`). On the owner's next
join, they read their shard once and take their own entries. One extra `UpdateAsync` per
session, amortised across everyone in the shard.

**`warmth` is the killer detail.** It is the number that makes players care about being
good hosts to strangers they will never meet, and it feeds Renown. A player who
systematically refuses low-value visitors makes money and loses warmth, and other
players' Charts start showing their post as cold.

## 8. Seeding, liquidity, and never showing an empty Ledger

Three tiers of fallback, in order:

1. **Live Drifters** from the current + adjacent epoch shards. Preferred always.
2. **Echoes** — real Drifters from up to 6 epochs ago, replayed with a decayed budget
   and a marker in the Ledger ("word travels slowly out here"). Honest, not fake.
3. **Seed Drifters** — 64 hand-authored, named characters with fixed tastes, used when
   the pool is genuinely empty (launch day, tiny regions, 4 a.m. in a small Current).
   They are *characters*, not statistics: they recur, they remember, and they get
   Almanac entries. Players will grow fond of them, and when the real population
   arrives they simply become rarer.

**The Ledger is never empty. This is a hard invariant** and iteration 2's harness must
assert it against an empty exchange.

### 8.1 Liquidity target

| Population | Expected inbound Drifters per session | Source mix |
| --- | --- | --- |
| < 200 DAU | 3–6 | 20% live / 30% echo / 50% seed |
| 200–5 000 DAU | 6–12 | 65% live / 25% echo / 10% seed |
| > 5 000 DAU | 8–24 (tier-capped) | 92% live / 8% echo / 0% seed |

Iteration 3 must implement the mix as a *target* the exchange reaches for, not a fixed
ratio, so the transition is invisible.

## 9. Fairness

An async economy has one obvious exploit shape: a large player farming small players, or
a player dispatching to the same friendly target forever.

| Rule | Why |
| --- | --- |
| A Drifter may not be claimed by the same host twice within **6 epochs** | prevents farming a single generous post |
| Dispatch targets are **chosen by the exchange**, not by the player, except for **1 of 3** slots which may be a friend | preserves the stranger-encounter core while allowing friend play |
| A host may serve at most **3 Drifters from one owner per day** | anti-collusion |
| Standing gained from a single owner is capped at **8% of daily total** | anti-collusion |
| Budget is derived server-side from the owner's *economy*, never declared | anti-inflation |
| Cargo is a **claim**, not a transfer, until accepted | anti-duplication |

## 10. Notifications

Design against the **current, conservative** limit and treat the announced relaxation as
upside, not as a dependency.

- Experience Notifications require the user to be **13+ and opted in**, and are capped at
  **1 per user per day per experience**
  ([rate limit update](https://devforum.roblox.com/t/updates-to-notification-rate-limits/3007106)).
- Roblox's creator roadmap lists **Developer Push Notification Support** for late 2026,
  explicitly to enable "async turn based play", including resetting the daily cap when
  the user visits and allowing an additional silent notification
  ([Creator Roadmap](https://create.roblox.com/updates/roadmap)).

**Policy:** exactly one notification per player per day, chosen by priority, and it must
be *worth it*:

| Priority | Kind | Copy shape |
| --- | --- | --- |
| 1 | A `DEEPWATER` trader will reach your dock at the next high water | "The big one is coming in at 7:40." |
| 2 | Spring tide — the lowest water of the fortnight | "Lowest water in two weeks tonight." |
| 3 | A named/recurring Drifter is inbound | "Marren is on her way back." |
| 4 | Your inbox has ≥ 8 unread receipts | "Eleven people came by." |

Scheduling is exact because the tide is a pure function: `Tide.nextHighWater(t)` gives
the precise second. Never send "something happened" — always send *when* and *what*.

## 11. The Chart — making async legible

The async layer only works if the player can *see* it. The Chart is a 2D orthographic
screen (using the RDC 2026 orthographic camera / sprite-sheet support) showing:

- the five Currents as flowing bands,
- your post, and the posts your Drifter has visited, as lights,
- inbound Drifters as marks with an ETA in tide-epochs,
- warmth of hosts you have visited, as colour temperature,
- the tide curve for the next 48 h along the bottom.

This screen is the game's identity shot. It is the thumbnail. Iteration 4 owns it.

## 12. Open questions for later iterations

Recorded rather than guessed.

| Question | Owner | Notes |
| --- | --- | --- |
| Should Currents be geographic (region-locked) or thematic? | it5 | Geographic improves latency and timezone overlap; thematic improves identity. Leaning thematic with a geographic *bias* in shard selection. |
| Is 7 days the right Drifter TTL? | it5 | Depends on real DAU. Instrument it. |
| Do Echoes feel dishonest? | it5 | Playtest. The Ledger marker must be prominent. |
| Should `warmth` be public on the Chart? | it5 | Powerful, but risks a shaming dynamic with under-13 players. Policy review required. |
| Can a player *see* whose Drifter it was? | it4 | Display name only, no profile link, no join. Safety-first default is yes-name/no-link. |
