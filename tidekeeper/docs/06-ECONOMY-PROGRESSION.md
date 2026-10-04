# 06 — Economy, Standing Orders and Progression

---

## 1. Currencies

Three, and only three. Adding a fourth requires a written decision.

| Name | Symbol | Earned by | Spent on | Integer |
| --- | --- | --- | --- | --- |
| **Coin** | `¤` | selling to Drifters, passive income | tier upgrades, restock, décor | yes |
| **Standing** | — | serving Drifters well, per Current | gates *which* Drifters reach you | yes, 0..65535 per Current |
| **Renown** | — | Showcase ratings from other players | cosmetics, Beacon polish, board placement | yes |

Coin is the only fungible one. Standing and Renown cannot be bought, traded, or
converted — this is a deliberate integrity line and it is what keeps the async social
layer honest.

**There is no premium currency.** Robux purchases buy capability and cosmetics directly
(doc 13 §4). This avoids an entire regulatory and trust surface and costs very little
revenue in a game whose monetisation is capacity, not consumption.

## 2. The five Currents

Currents are the trade routes your post sits on. Each has a taste bias, which means
each pulls a different Drifter population and rewards a different post.

| # | Current | Taste bias (doc 03 §5 axes) | Unlocks at | Character |
| --- | --- | --- | --- | --- |
| 0 | **The Shallows** | 0:−40 salvage, 2:−30 cheap | start | Everyone starts here. Forgiving, low value, high volume. |
| 1 | **Coldwater** | 1:−60 plain, 6:+50 steady | tier 2 | Regulars. Low variance, rewards consistency. |
| 2 | **The Glass Road** | 1:+70 ornate, 2:+60 dear | tier 2 | High value, brutally picky. |
| 3 | **Longrun** | 5:+65 deep, 3:+40 spend | tier 3 | Outer-zone finds only. Big budgets, rare arrivals. |
| 4 | **The Lantern Line** | 4:+70 social, 7:+60 kind | tier 4 | Warmth matters more than price. Renown engine. |

Standing is per-Current and decays toward a **band floor**, not toward zero. Bands are
250 / 1 000 / 4 000 / 12 000 / 30 000. Once you cross a band you can never fall below
it. This means a two-week absence costs you progress but never *erases* an achievement —
the single most important retention decision in the whole economy.

Decay: `2.5% of (current − bandFloor)` per tide epoch, i.e. ~9.4%/day. A player at
11 000 in a band whose floor is 4 000 falls to **5 798** after a fortnight (54 epochs).
Painful, recoverable, never catastrophic.

> **Corrected in iteration 2.** This paragraph originally said "~4 700", which is what
> you get if you decay toward zero. Decaying toward the band floor leaves
> `4000 + 7000 × 0.975^54 = 5 790`, and the integer `floor()` inside the per-epoch step
> makes the exact shipped answer **5 798**. Asserted in `tools/tests/pure-tests.lua`.

## 3. Price and value

Every find has a **base value** `V` and a **taste vector**. The price *you* set is the
lever.

```
pricePressure(p, V, dearTaste) =
    let r = p / V                                -- your markup
    let ideal = 1.0 + 0.006 * dearTaste          -- dear-tasting drifters expect markup
    return clamp(1.6 - 2.2 * |r - ideal|, -1, 1)
```

> **Corrected in iteration 2.** The signature was written `pricePressure(p, budget,
> dearTaste)`, but the body never uses `budget` — it uses the find's base value `V`.
> The shipped function is `Visit.pricePressure(price, baseValue, dearTaste)`. Budget is
> applied in the purchase stage, where it belongs.

- Price at exactly `V` and you sell to almost anyone, for almost nothing.
- Price at 1.6×`V` and only Glass Road buyers bite, but each is worth four Shallows sales.
- Price above ~2.2×`V` and warmth drops even on a successful sale.

There is no "correct" price, because the Drifter population is not stationary — it is
literally other players, and it drifts. The skill is reading your own Ledger.

## 4. Passive income

Standing orders generate coin while you are away, capped hard so that idling can never
beat playing.

| Tier | Passive cap per epoch | Per day (3.87 epochs) | As % of an active session's earnings |
| --- | --- | --- | --- |
| 1 | 40 ¤ | 155 ¤ | ~35% |
| 2 | 130 ¤ | 503 ¤ | ~33% |
| 3 | 420 ¤ | 1 625 ¤ | ~30% |
| 4 | 1 200 ¤ | 4 644 ¤ | ~28% |

The percentage deliberately *declines* with tier: the game gets less idle as you get
better at it, which is the opposite of most simulators and is what gives it a ceiling
worth climbing.

## 5. Standing orders — the language

This is the game's depth. It must be simple enough for a nine-year-old to set one rule
and rich enough that a good player's program is a meaningful artefact.

### 5.1 Form

A program is an **ordered list of rules**, evaluated top to bottom, first match wins.
Maximum 24 rules at tier 4 (6 / 10 / 16 / 24 by tier). Stored as bytecode, ≤ 1 024 B.

```
WHEN <condition> THEN <action>
```

### 5.2 Conditions (tier-gated)

| Condition | Tier | Notes |
| --- | --- | --- |
| `always` | 1 | |
| `class is X` | 1 | SKIFF / LAUNCH / LUGGER / DEEPWATER |
| `current is X` | 1 | |
| `standing >= N` | 2 | the *visitor's* standing with you |
| `tide is X` | 2 | LOW / EBB / FLOOD / HIGH / SLACK |
| `wants something I have` | 2 | |
| `budget >= N` | 3 | |
| `beacons >= N` | 3 | |
| `taste.<axis> > N` | 3 | one axis at a time |
| `<cond> and <cond>` | 3 | max 2 terms |
| `visits >= N` (a returning face) | 4 | |
| `<cond> or <cond>` | 4 | max 2 terms |

### 5.3 Actions

| Action | Tier | Notes |
| --- | --- | --- |
| `serve` | 1 | normal |
| `refuse` | 1 | Standing cost, warmth cost |
| `serve at +N%` / `-N%` | 2 | per-visitor price adjustment, ±40% |
| `hold berth` | 3 | reserve a slot for a higher class this epoch |
| `offer only <shelf group>` | 3 | |
| `gift <find>` | 4 | big warmth, big Renown, zero coin |
| `accept barter` | 2 | |

### 5.4 Worked example (a good tier-3 program)

```
1  WHEN class is DEEPWATER            THEN hold berth
2  WHEN current is Glass Road
      and taste.ornate > 40           THEN serve at +25%
3  WHEN wants something I have        THEN serve
4  WHEN budget >= 800                 THEN serve at +10%
5  WHEN standing >= 4000              THEN serve
6  WHEN class is SKIFF                THEN serve at -10%
7  always                             THEN refuse
```

Rule 1 costs you volume all epoch for a chance at one big sale. Rule 7 is brutal and
tanks warmth. A kinder player replaces it with `always THEN serve at -20%` and earns
less coin and far more Renown. **Both are correct.** That is the design.

### 5.5 UI

Never a text editor. A vertical list of card rows, each row a dropdown-condition +
dropdown-action, drag to reorder, with a **live preview panel** that runs the program
against the last 20 Drifters from your Ledger and shows what *would* have happened.
That preview is only possible because `Visit.resolve` is pure and client-runnable
(doc 04 §7). It is the strongest argument for the whole determinism discipline.

## 6. Finds and the Almanac

200 finds at v1, in 5 rarity tiers and 8 material families.

| Rarity | Count | Base value | Where |
| --- | --- | --- | --- |
| Common | 80 | 4–15 ¤ | all zones, any tide |
| Uncommon | 58 | 18–60 ¤ | inner + mid zones |
| Scarce | 36 | 70–260 ¤ | mid + outer, EBB/LOW only |
| Rare | 20 | 300–1 200 ¤ | outer zone, LOW only, spring tides favoured |
| Singular | 6 | 4 000+ ¤ | spring LOW only, one per player per season |

Drop weight is a function of `(zone, tideState, springNeapPhase, playerTier, almanacGaps)`.
The `almanacGaps` term is a gentle **pity mechanic**: finds you have never seen get a
modest weight bonus. It is not a paid random item and it is not advertised — it just
makes collection feel fair. Odds for anything purchasable remain fully disclosed
(doc 13).

The Almanac is the long game: 200 entries, each with a discovery date, the tide it was
found on, and — for finds acquired via a Drifter — **who brought it to you**. The
Almanac is a record of other people.

## 6.1 These numbers are pinned, as of iteration 11

Until iteration 11 **every number in this document was verified by nothing**.
The mutation scan changed each scalar in `Config/` by one and re-ran all
1 755 assertions: `STANDING_ON_SERVED`, `RENOWN_ON_GIFT`,
`WARMTH_BASE_SERVED`, `SPOIL_PER_MILLE`, `PASSIVE_RATE_PER_MILLE` and the
rest could each be changed with the suite still green. The iteration-7
balance pass tuned values that no test would have noticed being wrong.

They are now pinned in `tools/tests/pure-tests.lua`, section
`EconomyPinning`, in two halves — a **literal** assertion of the value, and a
behavioural assertion that the code uses it. Asserting the behaviour against
the constant alone pins nothing, because mutating the config moves both sides
together.

**If you are changing a number in this document, the pinning test will fail,
and that is the point.** Update both, deliberately, in the same commit.

Pinned relationships, not just values:

- a gift is warmer than a sale, which is warmer than a partial;
- a gift earns more standing *and* more renown than a sale;
- `WARMTH_MAX` is 127 because warmth is stored in one signed byte — if these
  ever disagree the codec truncates a player's reception silently;
- the warmest reachable visit (`WARMTH_BASE_GIFT` + `WARMTH_PER_WANT_MET` ×
  `MAX_WANTS`) reaches the clamp, so the clamp is exercised rather than
  theoretical;
- spoilage rounds to **zero** on a small holding — a post with two things on
  the shelf is not taxed into nothing while its owner is away;
- the long-absence cache is worth returning for but cannot buy a tier;
- `MAX_PRICE` × `MAX_BERTHS` cannot overflow the coin ceiling.

## 7. Progression pacing

**Measured in iteration 7.** These were targets with no mechanism behind them for
six iterations: `S.tier` was set to 1 when a post was created and *nothing in the
game ever changed it*, so every tier-gated system below was unreachable and this
table described a game that could not be played. Iteration 7 added
`EconomyConfig.TIER_COST`, `Post.promote`, the `RF_Upgrade` remote and
`PostHandler.upgrade`, then calibrated the costs against the targets.

`tools/tests/economy-sim.lua` simulates 12 seeds × 70 days of a
diligent-but-not-optimal player (2 sessions/day, naive base-value pricing, buys the
next tier as soon as it can afford it) and reports the day each seed arrived:

| Tier | Cost | p10 | **median** | p90 | Target |
| --- | --- | --- | --- | --- | --- |
| 2 | 320 | 3 | **3** | 5 | day 3 |
| 3 | 3 400 | 14 | **17** | 20 | day 16 |
| 4 | 15 500 | 49 | **50** | 55 | day 52 |

All 12 seeds reach tier 4. Three rounds of calibration were needed because
**promotion compounds** — a promoted post has more shelves, a higher passive cap and
richer currents, so each tier makes the next arrive sooner. The first costs were read
off a curve measured with every post locked at tier 1 (the only curve obtainable at
the time) and put tier 4 at day 22 instead of 52. *A progression curve cannot be
calibrated against a simulation that cannot progress.*

The model is the **fast end** of the distribution: it never hesitates and never
spends on anything else, so these are a floor on time-to-tier, not a promise.

Re-run after any change to income, find values or passive caps:

```
node tidekeeper/tools/tidekeeper-session-test.js --tests tools/tests/economy-sim.lua
```

The original targets, for comparison:

| Milestone | Target time | Sessions |
| --- | --- | --- |
| First Drifter served | 0:45 | 1 |
| First standing order set | 4:00 | 1 |
| Tier 2 | day 3 | ~7 |
| First Glass Road sale | day 5 | ~12 |
| Tier 3 | day 16 | ~40 |
| Almanac 100 | day 34 | ~85 |
| Tier 4 | day 52 | ~130 |
| First Beacon | day 90 | ~230 |

At 2.4 sessions/day × 9 min, tier 4 is ~19.5 hours of play. That is a real game, and
Beacon-chasing is open-ended past it.

## 8. Retention design

Explicitly engineered against the known numbers.

| Mechanism | Target metric | Design |
| --- | --- | --- |
| Ledger on arrival | first-30-seconds churn | The first screen contains named humans and a changed number. No tutorial gate before it. |
| 3-step onboarding | D1 | Community data: 5 steps → 3 steps moved D1 6%→15%. Ours is exactly 3: comb one node, price one shelf, dispatch one Drifter. |
| Tide schedule | D7 | The spring tide fortnight gives a genuine calendar event with no energy meter. |
| Standing band floors | D30, returning players | §2. Absence never erases. |
| Notification | reactivation | One per day, always with a *time* and a *reason* (doc 03 §10). |
| Seed Drifters as characters | early-population loneliness | doc 03 §8 |
| Weekly Showcase | social pull | Renown board resets weekly; low stakes, high frequency. |

Targets: **D1 30%, D7 12%, D30 5%**, median session 9 min, 2.4 sessions/day.

## 9. Anti-patterns, forbidden

- Energy / stamina meters.
- Timers you can pay to skip on the *core* loop (the tide is the timer and it is free).
- Any mechanic that punishes absence beyond decay-to-band-floor.
- Power sold for Robux. Capacity and cosmetics only.
- Loot boxes, crates, eggs, spins, or any paid random item (doc 13 §3).
- A leaderboard of coin. Coin leaderboards make economies toxic; the boards are Renown
  and Almanac completion.
