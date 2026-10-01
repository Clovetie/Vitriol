# 07 — World, Zones and Content

---

## 1. The place

One place, one island, one post per player, instanced by a **plot** model — the sibling
pattern to Grow a Garden's plot-among-plots layout, which is proven to work at scale on
mobile.

```
Workspace
└── Tidepost
    ├── Island            the fixed hub: dock, lighthouse ruin, Chart table
    ├── Plots             12 player plots, radial around the island
    │   └── Plot_01..12   each: a post, a pier, a stretch of flats
    ├── Flats             the tidal zone, shared walkable, zone-tagged
    ├── Water             ONE plane part, driven by TideController
    └── Spawn
```

Server size: **12 players**. Small deliberately. A 12-player server on mobile loads fast,
and because presence is asynchronous, a small server costs nothing socially. This is a
major performance advantage over every other cozy sim on the platform.

## 2. Zones

The flats are divided by distance from the high-water mark. Which zones are walkable is
purely a function of the tide (doc 02 §3) — no gates, no doors, just water.

| Zone | Exposed when | Walk time from post | Find pool | Risk |
| --- | --- | --- | --- | --- |
| **Inner** | `h < 2` (most of EBB/LOW/FLOOD) | 10 s | Common, Uncommon | none |
| **Mid** | `h < -2` | 35 s | Uncommon, Scarce | caught by FLOOD: drop 1 carried item |
| **Outer** | `h < -6` (LOW only) | 75 s | Scarce, Rare | caught: drop up to 4 |
| **The Bar** | `h < -11` (spring LOW only, ~4×/month) | 130 s | Rare, Singular | caught: drop everything carried |

The Bar is the game's spring-tide event. It is open for roughly 40 minutes, four times a
month, and everyone in every server knows exactly when because the tide is public and
deterministic. It is the one moment TIDEKEEPER is a synchronous game, and it needs no
event system at all — it is just arithmetic.

### 2.1 The walk back

Time-to-safety is the tension. The client shows a **countdown to knee-deep** computed
from `Tide.velocity`, and the countdown is honest. Getting caught is never lethal and
never costs progress — only carried, unsecured finds. Death does not exist in this game.

## 3. Beachcombing

Comb nodes are tagged parts in the flats. A node has `(zone, maturity, seed)`.

- Maturity accrues per tide epoch; a mature node yields, an immature one yields nothing
  and says so.
- Node respawn is resolved during `Resolve` (doc 04 §3 step 2) for offline time, and on
  the `think` cadence slot for online time. Same function, different caller.
- Yield is `RNG` seeded by `Hash.mix(nodeId, epoch, postSalt)` — so two players at the
  same node in the same epoch get *different* results, and the same player re-rolling by
  rejoining gets the *same* result. Both properties matter.
- Interaction is a single tap, ~0.8 s, with a satisfying sound. No minigame. Mobile-first.

**Node budget:** 96 per plot, 1 152 in the world at 12 players. These are not parts —
they are `Attachment`-based markers with a shared pooled visual, per the ≤ 1 800 part
budget (doc 01 §6).

## 4. Dockwork

The high-tide counterpart, so the game has something to do in every tide state.

At `HIGH`, deep-draught Drifters that arrived during your absence can be **unloaded** —
a short arrange-and-stow activity that converts pending barter claims into stock, and
lets you inspect what a `DEEPWATER` trader left. It is the calm, tidy, satisfying
activity; beachcombing is the urgent one. Alternating them on a 6-hour rhythm is the
game's texture.

## 5. Content inventory for v1

| Content | Count | Author | Iteration |
| --- | --- | --- | --- |
| Finds (mesh + icon + taste vector + value) | 200 | AI-generated, human-curated (doc 09) | **6 ✅ data** |
| Ledger prose templates | 180 | human-written | **6 ✅** |
| Fixed-phrase letters | 120 | human-written, policy-reviewed | **7 ✅** |
| Seed Drifters (named characters) | 64 | human-written | **7 ✅** |
| Post décor pieces | 90 | AI-generated, human-curated | 7 (needs an engine) |
| Post tier structures | 4 | human-modelled | 7 (needs an engine) |
| Zones | 4 | human-built | 4 |
| Currents | 5 | config only | 3 |
| Achievements / badges | 40 | config only | **7 ✅ data** |
| Music cues | 6 | human/licensed | 7 (needs a human) |
| SFX | ~70 | human/licensed | 7 (needs a human) |

**Iteration 7 status.** Every content line that is pure data is now **done and
pinned by a test to its doc 07 target**: 200 finds, 180 Ledger phrasings, 120
letters, 64 named Seed Drifters, 40 badges. Iteration 7 also found that the 176
finds added in iteration 6 had no display names at all — the data shipped and the
words did not, so every find above id 24 rendered as "something the sea left". The
coverage test now walks the real find table instead of a sample. The rows that
remain all need a running engine (meshes, décor, tier structures) or a human
(music, SFX).

**Iteration 6 status.** The two content lines that are pure data — the 200 finds and
the 180 Ledger phrasings — are **done and enforced by the suite**, not merely
planned. `pure-tests.lua` asserts `#FindsConfig.FINDS == 200` and validates every
row's id uniqueness, group, zone, perishable flag, rarity and all eight taste axes;
session scenario 15 renders *every variant of every template* and asserts zero
unresolved directives, then asserts `totalVariants >= 180`. Both thresholds were
previously pinned to the iteration-2 placeholder values (24 finds, 40 phrasings),
which meant the content could have been deleted wholesale without turning the gate
red. The remaining rows in the table above all need either a running engine
(meshes, décor, tier structures) or a human (music, SFX), and are honestly marked.

### 5.1 The 200 finds — the asset problem, and its answer

200 distinct meshes is the one genuinely asset-hungry part of this design and it is
exactly what 2026's generative tooling is good at. The pipeline is specified in
[`09-AI-BUILD-PIPELINE.md`](09-AI-BUILD-PIPELINE.md). The constraints:

- **≤ 120 unique meshes** (doc 01 §6) for 200 finds → finds share silhouettes across
  colourways and material variants. A "green glass float" and a "blue glass float" are
  one mesh, two `SurfaceAppearance` variants, two Almanac entries.
- ≤ 900 triangles each. Roblox's humanoid budget reference point is 10 742 triangles for
  a whole character; a beach find should be two orders of magnitude cheaper.
- One shared 1024² texture atlas per material family (8 families).
- Every find must read at **48 px** — that is the Almanac grid cell on a phone. Silhouette
  first, detail never.

## 6. Art direction

Recorded so the generative pipeline has a target rather than producing 200 unrelated objects.

- **Palette:** cold greys and wet sand, with saturated accents only on finds. The world
  is desaturated; the things you collect are not. This makes finds pop at 48 px and makes
  a well-stocked post look genuinely different from an empty one.
- **Light:** low sun, long shadows, permanent late-afternoon. The tide is the clock, not
  the sun — so day/night is *cosmetic* and slow (a 24 h real cycle, decoupled from the
  tide's 12 h 25 m). The two clocks drifting against each other is intentional and is
  what makes the world feel like it has weather.
- **Silhouette rule:** everything readable in black at 48 px.
- **No gore, no horror, no threat.** This is the explicit opposite of the sibling project.
  Roblox's audience skews young; the maturity questionnaire answer is "All Ages".

## 7. Audio

Audio carries more of this game's feel than its geometry does.

| Layer | Behaviour |
| --- | --- |
| Sea bed | Continuous, volume and brightness driven by `Tide.height` and `Tide.velocity` |
| Turn of the tide | A one-shot cue at each state change. Players will learn it. |
| Comb | Per-material family; the rarity is audible before it is visible |
| Ledger | Each entry has a footstep-and-door rhythm; the replay is paced, not dumped |
| Music | 6 cues, tide-state-selected, ≤ 25% of the mix, off by default on mobile |

## 8. Seasons

A season is 8 weeks. Each rotates:

- 12 seasonal finds (Almanac entries that stay after the season),
- one Current taste shift,
- the Showcase theme.

Seasons are config-only, written to `Meta m:global` by the nightly Open Cloud tick
(doc 05 §10). No code ships to change a season. This is the live-ops contract and
iteration 3 must build for it.
