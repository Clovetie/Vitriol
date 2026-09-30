# 13 — Risks, Safety and Compliance

---

## 1. The three decisions that remove most of the risk surface

Made now, at iteration 1, because they are cheap now and expensive later.

### D1 — No paid random items. None.

No crates, eggs, spins, mystery seeds, gacha, or "random find" purchasable with Robux or
with any currency purchasable with Robux.

This single decision removes: the odds-disclosure requirement for every outcome, the
`ArePaidRandomItemsRestricted` policy branch and its alternative purchase path, the
`IsPaidItemTradingAllowed` branch on peer trading, the Content Maturity questionnaire
declaration, and the entire regulated-jurisdiction compliance surface described in
Roblox's May 2026 clarification
([source](https://devforum.roblox.com/t/clarifying-requirements-for-paid-random-items/4654622)).

The design does not need it. Monetisation is capacity and cosmetics (§4).

*Note:* the in-game `almanacGaps` weighting on **free** beachcombing drops (doc 06 §6) is
not a paid random item — nothing about it is purchasable. Keep it that way. If any
iteration proposes selling a random anything, it must reopen this decision in writing.

### D2 — No Robux-for-item peer trading, and no free-text communication.

Selling in-experience items to other players for Robux is not permitted (doc 10 §5.3).
TIDEKEEPER's barter is **item-for-item, or gift, and always within the game's own
economy**, never Robux. Cargo is a *claim* the recipient accepts, not a transfer
(doc 03 §9), which also removes the duplication exploit class.

There is **no free-text input anywhere in the game**. Letters are fixed phrases selected
from a curated, reviewed table (doc 08 §9). This is the biggest single safety decision
in a game whose premise is player-to-player contact.

### D3 — `PolicyService` is wired from day one anyway.

Even though D1 and D2 mean nothing currently depends on it, `Adapters/PolicyAdapter`
ships in iteration 3, loads on `PlayerAdded` before anything monetised, and caches:

- `ArePaidRandomItemsRestricted`
- `IsPaidItemTradingAllowed`
- `IsSubjectToChinaPolicies`
- `AllowedExternalLinkReferences`

Cost: ~30 lines. Benefit: if any future feature needs a policy branch, the plumbing and
its Player Emulator test path already exist. Studio's Player Emulator can toggle these
flags for testing without being in a regulated region.

## 2. Safety review — the async social layer

This is the part of the design a platform safety review will look at hardest, so it is
specified defensively.

| Surface | Risk | Mitigation |
| --- | --- | --- |
| Showing another player's display name in your Ledger | contact / targeting | Display name only. **No** profile link, join, follow, friend or DM affordance anywhere. |
| Letters | grooming, harassment, coded speech | Fixed-phrase only, from a curated table of ~120, human-reviewed, no numbers, no names, no external references. Table is data, so it can be amended without a code deploy. |
| Post names / shelf labels | free text via a side door | There are none. Posts are named from a generated two-word table; shelves are labelled by item. |
| Cosmetic arrangement | building offensive shapes for others to see | Arrangement is slot-based on a fixed grid with a fixed part set. No freeform CFrame placement. |
| `warmth` shown publicly | shaming / bullying dynamic | Never shown per-named-player. Aggregate colour on the Chart only (doc 08 §9). |
| Repeated unwanted contact | harassment | One-tap permanent per-pair exclusion on any Ledger entry, no explanation, no report flow, takes effect immediately in the exchange. |
| Showcase / Renown boards | ranking harm | Top 100 only. **Never a bottom board.** Weekly reset. |
| Under-13 exposure | policy | The whole surface above is designed to be safe by default for all ages. Content Maturity target: **All Ages**. |

**Escalation rule for later iterations:** any proposal that adds a new channel through
which one player's authored content reaches another must be reviewed against this table
and recorded in `ROADMAP.md`. "It's just a small thing" is how these games get taken down.

## 3. Risk register

Ordered by expected damage.

| # | Risk | Likelihood | Impact | Mitigation | Owner |
| --- | --- | --- | --- | --- | --- |
| R1 | **The async loop is not actually fun.** The Ledger reads as a spreadsheet and nobody cares about strangers. | Medium | Fatal | The Ledger-as-replay design (doc 08 §3) exists for exactly this. **Prototype the Ledger screen in iteration 4 and put it in front of real humans before building iteration 5's content.** If it does not land, the whole concept is wrong and it is better to know at it4. | it4 |
| R2 | **Duplication / inflation bug in the exchange.** Fatal to a trading economy, hard to reverse. | Medium | Severe | Economy invariants proven by the harness (doc 04 §9), claim-removal inside a single `UpdateAsync`, barter as claim not transfer, 30-day simulated lifetime test (doc 05 §11). | it2–it3 |
| R3 | **MemoryStore quota exhaustion at success.** | Low (by design) | Severe | Finding A (doc 10 §3). Pool in DataStore; index only in MemoryStore; hard degradation path (doc 01 §8). `BudgetMeter` must alert. | it3 |
| R4 | **Cold-start still fails** — not enough players for live Drifters, and Echoes/Seeds feel fake. | Medium | Severe | Three-tier fallback with the transition designed to be invisible (doc 03 §8). Seed Drifters are written as characters, not statistics. Playtest the sub-200-DAU case explicitly. | it5 |
| R5 | **The notification API ships differently than announced**, or slips. | Medium | Moderate | The game must be fully playable with **zero** notifications. Notifications are an accelerant, never load-bearing. Verify the API in iteration 3 as the first task. | it3 |
| R6 | **Determinism breaks in a subtle way** (a `pairs()` iteration, a float accumulation) and offline replay diverges from the server. | High if undisciplined | Severe | The determinism rules (doc 04 §5) are enforced by the quality gate, and the 1 000-run replay proof (§5.1) runs every gate. | it2 |
| R7 | **Asset generation produces 200 unrelated objects.** | High | Moderate | The human curation gate in the pipeline (doc 09 §2), the shared-atlas constraint, and the 48 px silhouette rule. Budget a 35% rejection rate. | it5 |
| R8 | **Discovery failure.** A systems-depth game with a quiet thumbnail dies unseen. | High | Severe | The Chart is designed as the thumbnail (doc 03 §11). Title chosen against live search data in it5 (doc 00 §10). Moments clips of the Ledger replay. Plan paid discovery. | it5 |
| R9 | **Build-generated competitors flood the cozy genre.** | High | Moderate | Accepted. The moat is systems depth a prompt cannot produce (doc 09 §1.3). |  — |
| R10 | **Safety incident via the social layer.** | Low | Severe | §2. No free text, no links, no contact affordances. | all |
| R11 | **Session-lock race duplicates a post.** | Medium | Severe | doc 05 §7. Never load without the lock; abandon writes with a stale token. | it3 |
| R12 | **DataStore shared request budget starves live servers** during a migration or reaper run. | Medium | Moderate | doc 05 §9/§10: reapers are rate-limited to one shard per slow tick; no Open Cloud work at peak. | it3 |
| R13 | **Scope creep into a real-time multiplayer game.** | High | Severe | The forbidden list (doc 01 §10, doc 00 §8) is binding. Every iteration prompt restates it. | all |
| R14 | **Long-absence return feels punitive** and returning players churn. | Medium | Moderate | Standing band floors (doc 06 §2), the `LONG_ABSENCE` entry, the "found while you were away" cache (doc 04 §3.1). | it3 |
| R15 | **Clock skew / device clock manipulation** to farm tides. | Medium | Low | Server recomputes from `os.time()` for every award, ±90 s tolerance (doc 02 §7). A wrong client clock only breaks that client's visuals. | it3 |

## 4. Monetisation, and why it is compliant by construction

| Product | Type | Robux | What it does | Why it is safe |
| --- | --- | --- | --- | --- |
| Second Post | Gamepass | ~399 | A second plot, separately configured | Capacity |
| Wide Shelves | Gamepass | ~199 | +6 shelf slots at every tier | Capacity |
| Ledger Digest | Gamepass | ~149 | Auto-summary + search over your ledger history | Convenience |
| Lantern Oil | Dev product | ~49 | Cosmetic light on your post, seen by visitors | Cosmetic |
| Post Kits | Dev product | ~99–299 | Named décor sets, **contents shown before purchase** | Cosmetic, deterministic |
| Express Dispatch | Dev product | ~79 | Your Drifter reaches its target one epoch sooner | Convenience, not power |
| Season Pass | Subscription (Robux) | ~349/mo | Seasonal cosmetics + Ledger Digest | Cosmetic |

**Nothing here sells power, stock, coin, Standing, or Renown.** Nothing is random.
Everything's contents are visible before purchase. Regional Pricing enabled on all of it.

Rewarded Video Ads: **not at launch.** Revisit at it5+ with care; a cozy game's tone is
fragile.

## 5. Legal / content

| Item | Position |
| --- | --- |
| Content Maturity | **All Ages.** No violence, no gore, no romance, no gambling, no paid random items, no free text. |
| AI-generated assets | Permitted by Roblox's terms. All generated assets pass a human curation gate (doc 09 §2) and are uploaded under the project's own account. |
| Third-party model licences | Any imported asset's licence is recorded in `tidekeeper/docs/ASSETS.md` (to be created in it5) with source, licence and date. |
| IP | No licensed IP, no references to real brands, no real place names. The world is invented. |
| Music | Original or clearly licensed; licence recorded as above. |
| Player-generated content | None, by construction (§2). |

## 6. Pre-launch checklist (iteration 5 owns)

- [ ] Content Maturity questionnaire completed and accurate
- [ ] `PolicyService` branches exercised via Studio Player Emulator
- [ ] Fixed-phrase letter table reviewed by a human against Community Standards
- [ ] Ledger prose templates reviewed for reading age and tone
- [ ] Per-pair exclusion verified end-to-end in the exchange
- [ ] No free-text input path exists — grepped, not assumed
- [ ] Economy invariants green over a simulated 30-day lifetime
- [ ] Session-lock race tested with two simulated servers
- [ ] Notification opt-in copy reviewed; game verified fully playable with notifications off
- [ ] Data deletion request path implemented (post + ledger + drifters + receipts)
- [ ] Soft-launch region chosen; telemetry for D1/D7 and first-30-seconds churn in place
- [ ] Rollback plan: schema version floor, and a refusal path for newer blobs (doc 04 §10)
