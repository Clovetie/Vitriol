# TIDEKEEPER — Roadmap

Iteration tracker. Status legend: ⬜ not started · 🟨 in progress · ✅ done.

Separate from the VITRIOL roadmap at the repository root. The two games share a
repository and nothing else.

---

## Iteration 1 — research, design, tooling fork ✅

| Deliverable | Status |
| --- | --- |
| Web research: 2026 Roblox platform, RDC 2026, data-service limits, policy | ✅ |
| Web research: Roblox generative / "vibe coding" AI tooling survey | ✅ |
| Web research: 2026 charts, genre performance, retention benchmarks | ✅ |
| Concept selection and lock | ✅ |
| `docs/00-VISION.md` — pitch, pillars, loop, scope, idea bank, titles | ✅ |
| `docs/01-ARCHITECTURE.md` — layering, Explorer tree, authority, cadence, budgets | ✅ |
| `docs/02-TIDE-AND-TIME.md` — constants, states, epochs, 12 test vectors | ✅ |
| `docs/03-ASYNC-SOCIAL.md` — the Drifter Exchange, two-tier storage, fairness | ✅ |
| `docs/04-SIMULATION-MODEL.md` — resolve-on-read, determinism rules, invariants | ✅ |
| `docs/05-PERSISTENCE.md` — key map, wire formats, budgets, locking, retries | ✅ |
| `docs/06-ECONOMY-PROGRESSION.md` — currencies, Currents, standing orders, pacing | ✅ |
| `docs/07-WORLD-AND-CONTENT.md` — island, zones, content inventory, art direction | ✅ |
| `docs/08-CLIENT-UX-MOBILE.md` — six screens, first 60 s, mobile, accessibility | ✅ |
| `docs/09-AI-BUILD-PIPELINE.md` — AI tool survey + per-iteration usage + rules | ✅ |
| `docs/10-RESEARCH-NOTES.md` — 40+ sourced facts, confidence levels, unknowns | ✅ |
| `docs/11-HUMAN-AUTHORED.md` — briefs for everything an AI must not judge | ✅ |
| `docs/12-ITERATION-PROMPTS.md` — prompts for it2–it6+, handoff template | ✅ |
| `docs/13-RISKS-AND-COMPLIANCE.md` — 15-risk register, safety, monetisation | ✅ |
| `tools/` — forked analysis tooling scoped to `tidekeeper/` | ✅ |
| `tools/tidekeeper-doc-gate.js` — new, validates the docs themselves | ✅ |
| `tools/tidekeeper-quality-gate.js` — new, degrades honestly while `code/` is empty | ✅ |
| Gameplay code | ⬜ **deliberately none — iteration 2** |

## Iteration 2 — the pure core ✅

| Deliverable | Status |
| --- | --- |
| `Lib/{Tide,RNG,Hash,MathExt,Tables,Signal,Codec,Schema}` | ✅ 8 modules |
| `Domain/{Post,Drifter,Orders,Visit,Resolve,Ledger,Almanac,Standing}` | ✅ 8 modules |
| `Shared/{DrifterCodec,PostCodec,Version}` | ✅ 3 modules |
| `Config/{Game,Tide,Economy,Drifter,Orders}Config` + `FindsConfig` | ✅ 6 modules |
| `tools/tidekeeper-smoke-test.js`, ≥ 300 executed assertions | ✅ **858**, 0 failed |
| Both determinism proofs (doc 04 §5.1) green | ✅ plus a third, on the clamped path |
| `Visit.resolve` benchmarked against the 18 µs budget | 🟨 measured, **not verified** — see below |
| `tools/tidekeeper-determinism-scan.js` (tools/README §5) | ✅ 8 rules, clean |
| Zero-allocation claim for `Visit.resolve` | ✅ two proofs, neither a heap profiler |
| Doc corrections found by executing the spec | ✅ 5 (docs 02, 04, 05, 06) |

**The benchmark caveat, stated plainly.** `Visit.resolve` runs at a **1.73 ms median /
2.36 ms p99** inside fengari. fengari is a Lua interpreter written in JavaScript; the
same harness measures 1e6 integer additions at ~94 ms, i.e. ~94 ns per addition against
Luau's ~1–2 ns. Dividing through puts the real figure somewhere in the 20–60 µs band —
which straddles the 18 µs budget and therefore **proves nothing**. The budget is an
iteration-3 task, measured in Studio via the MCP `execute_luau` tool (doc 09 §3). The
harness number is a regression tripwire, not a verdict.

## Iteration 3 — the server exists ✅

| Deliverable | Status |
| --- | --- |
| **First task:** verify the shipped async-notification API and correct doc 10 §6 | ✅ it has **not** shipped; doc 10 §6.1 |
| `Adapters/{DataStore,Memory,Notify,Policy}Adapter` | ✅ |
| `Services/{Cadence,Player,Post,Exchange,Ledger,Notify,Showcase}Service` | ✅ |
| `Bootstrap`, `Main`, `RemoteHandlers/*`, `Diagnostics/{Profiler,BudgetMeter}` | ✅ |
| `Shared/{Remotes,NetContract,ReceiptCodec}`, `Config/NotifyConfig` | ✅ |
| Fake platform with injected failures (doc 05 §11) | ✅ a fake **DataModel**, not a fake adapter — 705 lines |
| `tools/tidekeeper-session-test.js` — 30-day / 200-session simulated lifetime | ✅ 14 scenarios, 72 assertions |
| Economy invariants green across that lifetime | ✅ `Post.checkInvariants` after every chunk |
| Measured request cost vs. the 5/session budget | ✅ **5.64 DataStore, 5.24 MemoryStore** per session |
| Determinism scan extended, never weakened | ✅ 8 rules → 12; three of them stricter replacements |
| `tools/lib/harness.js` extracted, smoke test unchanged at 858 | ✅ |
| `fixture-blobs/` + migration tests | ⬜ **deferred to it4** — folded into OD16, which needs schema v2 anyway |

**Three defects found by the harness, all fixed** (doc 03 §6.3): locks were never
released, 27 Drifters per simulated month were delivered twice, and a MemoryStore
outage blocked every join. The first two were the same platform fact — returning `nil`
from an `UpdateAsync` transform aborts the update, it does not delete the key.

## Iteration 4 — it plays 🟡

| Deliverable | Status |
| --- | --- |
| `Client/` layer: bootstrap + six views, all integer-driven | ✅ 8 modules + 1 LocalScript |
| `Client/Strings` — every word the player reads, keyed by template id | ✅ |
| The Ledger replay, re-running the real `Visit.resolve` | ✅ `LedgerView` |
| ≥ 40 Ledger prose templates | ✅ 21 ids × 3–4 variants |
| **OD16: `S.publishedAt` in PostCodec v2, with a real migration through `Shared/Version`** | ✅ doc 05 §6.1 |
| Migration test: load a v1 blob, assert it upgrades | ✅ committed 249-byte fixture |
| Localisation-coverage test: every template id and slot arity renders | ✅ scenario 15 |
| **OD12 settled** | ✅ — by **real Luau**, not MCP. doc 04 §6.1, L3.5 |
| Studio MCP connection; `execute_luau` | ⬜ **no Studio reachable** — deferred to it5 |
| `execute_luau` verification: buffer/base64 round trip, MemoryStore, `Tide.height` cost | ⬜ deferred to it5 |
| Playtest with console output + screenshots | ⬜ deferred to it5 |
| **R1: the Ledger in front of five real humans** | ⬜ deferred to it5 |

The half of iteration 4 that needed a running Roblox Studio did not happen, because
none is reachable from this environment — the same wall iterations 2 and 3 hit. What
changed is that **one of those blocked items turned out not to need Studio at all**:
OD12 was closed by building the standalone Luau VM (doc 10 §7.4). The remaining
Studio-shaped work is genuinely Studio-shaped and is restated in iteration 5.

## Iteration 5 — the harness tells the truth 🟡

Triage (doc 10 §8) found Studio unreachable for the fourth iteration, so iteration 5
took the no-Studio branch of its own prompt: tooling truth first, then content.

| Deliverable | Status |
| --- | --- |
| **OD17: the correctness suite runs in real Luau, zero shims** | ✅ 887 = 887, cross-checked |
| **Scenario 16: the client driven against the real server** | ✅ found 2 load-time crashes |
| Module list deduplicated into `lib/module-map.js` | ✅ |
| 200 finds via the generative pipeline + human curation gate | ⬜ **not started** |
| 180 Ledger templates, 120 letters, 64 Seed Drifters, 90 décor, 4 tiers, 40 badges | ⬜ **not started** |
| Island finished (Scene Generator if shipped, hand-built otherwise) | ⬜ **not started** |
| Economy tuned against 8 simulated play patterns | ⬜ **not started** |
| **R4: cold-start playtest at < 200 DAU** | ⬜ needs humans |
| Shipping title chosen against live search data | ⬜ |
| Thumbnail + 3 Moments clips | ⬜ |
| Pre-launch checklist (doc 13 §6) complete | ⬜ |
| Telemetry + soft-launch region + rollback plan | ⬜ |

**This iteration did not ship the game.** It is named for what it actually did: made
the test harness trustworthy, and ran the client for the first time. Content volume,
economy tuning and everything requiring a human or an engine move to iteration 6.

## Iteration 6 ✅ — the client could never have worked, and the content was a placeholder

| Goal | Status |
| --- | --- |
| Audit the only never-executed file (`Main.client.luau`) | ✅ found it fatally broken |
| Fix remote acquisition | ✅ now uses `Remotes.await(30)` |
| A check for the recurring bug class (cross-module member typos) | ✅ `tidekeeper-member-scan.js`, 14th gate check |
| Finds 24 → 200 (doc 07 §5) | ✅ data complete, validated row by row |
| Ledger prose 67 → 180 variants (doc 07 §5) | ✅ every variant render-tested |
| Re-pin content assertions from it2 placeholders to v1 targets | ✅ |
| OD7 notification re-check (beta window opened October 2026) | ✅ still not shipped |
| Letters, Seed Drifters, badges, décor | ⬜ iteration 7 |
| Economy tuning against the 200-find table | ⬜ iteration 7 |

**The headline is a bug, not a feature.** `Main.client.luau` looked for the seven
remotes under `ReplicatedStorage/Tidekeeper`; `Remotes.build` parents them under the
sibling `ReplicatedStorage/TidekeeperRemotes`. Every lookup returned nil. The game
was **100% non-functional for every player** and had been for two iterations, while
all 13 gate checks stayed green — because nothing in the toolchain constructs an
Instance, so no Instance-path bug is visible to any of it. That limit is now
written down rather than discovered again.

## Iteration 7 ✅ — four features that did not work, and the content to fill them

| Goal | Status |
| --- | --- |
| 120 letters, pinned to target | ✅ |
| 64 Seed Drifters as named characters | ✅ |
| 40 badges (config only) | ✅ |
| Economy tuning against the 200-find table | ✅ measured, 12 seeds × 70 days |
| Close OD14 (warmth into price) | ✅ closed **no** |
| Re-check OD7 once | ✅ closed **not available for v1** |
| Display names for the 176 finds added in it6 | ✅ they had none |
| Awarding badges | ⬜ iteration 8 |
| Client UI for upgrade / letters | ⬜ iteration 8 |

**Four things were shipped-but-inert, all found by asking what nothing reads:**

1. **`RF_Dispatch` was decoration.** `S.dispatchCargo` and `S.dispatchLetter` were
   written by the handler and read by nothing; `ExchangeService` recomputed cargo
   and hard-coded `letterId = 0`. No letter had ever reached a player.
2. **No post could ever be promoted.** `S.tier` was set to 1 at creation and never
   changed by any code. Every tier-gated system — 24 shelves, the four currents,
   passive caps, the order-rule limits, the whole of doc 06 §7 — was unreachable.
3. **Shelf density was a comment, not a rule.** A client-supplied slot could leave
   a gap, and a gap makes the post **unsaveable**: remotely triggerable data loss.
4. **`app.logger` could be nil** while seven handler rejection paths called it
   unconditionally, so every validation failure threw instead of returning a status.

All 14 checks were green while all four were true. Two new scans now close both
directions of the cross-module field contract: `member-scan` (read, never written)
and `dead-write-scan` (written, never read).

## Iteration 8 ✅ — the safety net that caught nothing, and the scan that finds its kind

| Goal | Status |
| --- | --- |
| Hunt a fifth dead feature before building anything | ✅ found **four** |
| Drain the failed-save recovery queue | ✅ `PostService:sweepRecovery` |
| Award the 40 badges | ✅ schema v3, earned in play, survives a relog |
| A scan for the class of defect behind all of it | ✅ `orphan-scan`, gate check 16 |
| Capture a v2 fixture before the ability vanished | ✅ `post-v2.b64`, 238 B |
| Client UI for upgrade / letters | ⬜ iteration 9 |

**Four more shipped-but-inert features, all invisible to the then-15 green checks:**

1. **The failed-save recovery queue was write-only.** `DataStoreAdapter:savePost`
   pushes an abandoned write to MemoryStore — the last-resort net against losing a
   player's session — and `popRecovery`/`ackRecovery` were **called by nothing**.
   The net caught the blob and dropped it. The comment above `pushRecovery` had
   said "so the next join can retry it" since iteration 4.
2. **The proof of the main security invariant never ran.**
   `NetContract.hasNoStringFields` — doc 13 §2, no remote accepts a string — was
   uncalled, while three separate comments claimed the smoke test asserted it.
3. **Ledger history is archived and never read back** (`loadLedgerPage`, OD22).
4. **The drifter pool is never reaped** (`reapPoolShard`, OD21).

3 and 4 are documented and allowlisted rather than half-fixed.

**The pattern is now three iterations old and has a name.** Iterations 6, 7 and 8
each lost features in the *seam* between two individually-correct modules, and each
time the existing checks were green. The scans have followed the defect up one level
each time: `member-scan` (a field read, never written) → `dead-write-scan` (a field
written, never read) → **`orphan-scan` (a function defined, never called)**. The
orphan scan's allowlist is verified in both directions: an entry that stops being an
orphan fails the scan too, so the list cannot rot into stale excuses.

It found dead code **in the badge module I wrote in the same session** — two helpers
I had defined and not used. They were deleted, not allowlisted.

**Badges (schema v3).** `S.stats` grew six lifetime counters and `S.badges` is a
40-bit mask; `Version.migrate` carries v1 and v2 saves up, filling the new fields
with zeroes rather than backfilling achievements nobody earned. Wiring the table up
immediately exposed a design defect in it: **a brand-new post earned three badges**,
because `shelvesUnlocked` is `tier * 6` and the ladders had been written against the
English of the names rather than the values the stats can take. Ids 11–15 and 34–37
were repurposed — safe only because nothing had ever been awarded. Two rules are now
pinned by tests: a new post earns nothing, and every threshold is reachable.

## Iteration 9 ✅ — the client could not do anything, and the pool was never reaped

| Deliverable | Status |
| --- | --- |
| Client action layer: `arrange`, `comb`, `setOrders`, `dispatch`, `upgrade`, `upgradeOffer` over one `act()` seam | ✅ |
| `PostView.arrangePayload` and `DispatchView.payload` made conformant to the real strict specs | ✅ |
| `nextCost` sent by `SessionHandler`; the client displays prices, never computes them (D46) | ✅ |
| `statusText` maps codes 3 and 4, and takes the remote name to disambiguate code 4 | ✅ |
| `LetterView` — 120 letters, 7 categories, ids over the wire | ✅ |
| **`tidekeeper-remote-scan.js`** — gate check 17, no allowlist | ✅ |
| **OD21 closed** — pool reaper scheduled on the IO slot behind a MemoryStore lease | ✅ |
| Bench made best-of-3 so it fails on code, not on machine load | ✅ |
| Session scenarios 21–23 | ✅ |

**The find.** Six client → server remotes existed. All six were bound, rate-limited,
schema-checked and session-tested on the server. The client invoked exactly **one** of
them and then listened. Every verb in the game — arrange, comb, orders, dispatch,
upgrade — had a complete server half and no way for a player to reach it, with sixteen
checks green. Two of the three client payload builders also produced payloads the
server would have rejected outright, which is only possible because none had ever been
sent. Full account in doc 08 §8.4; the ladder of scans in doc 10 §12.

**OD21.** `reapTick` deletes one pool shard per IO tick from epoch `now - 28`, and only
on the server holding a `reap:<epoch>` MemoryStore lease — 5 Currents × 64 shards
deleted once, not once per server. If MemoryStore is down nobody reaps, which is the
safe direction. Doc 05 §9.

---

## Iteration 10 ✅ — the Ledger remembers, and 18 labels no player could read

| Deliverable | Status |
| --- | --- |
| **`tidekeeper-dead-content-scan.js`** — gate check 18, level six of the ladder | ✅ |
| **OD22 closed** — ledger history readable: page index, `RF_History`, client pager, 32-page retention | ✅ |
| Page numbers allocated atomically, fixing a silent cross-server page overwrite | ✅ |
| The ledger reaper, finally written — and it costs nothing extra | ✅ |
| **OD23 closed** — one status enum in `NetContract`; `statusText` is a pure mapping again | ✅ |
| `ChartView` and `AlmanacView` — two screens that had rendered nothing since iteration 5 | ✅ |
| The navigation bar, which had never existed | ✅ |
| `Strings.PHRASE` deleted — a superseded content table still wired to the renderer | ✅ |
| `ERR_BUSY` given a meaning: one action in flight at a time | ✅ |
| Session scenarios 24–26 | ✅ |

**The find.** The first five scans are all about code. This one is about what the
player experiences, and on its first run 18 of 51 UI labels were unreachable —
including the **entire navigation bar**, and the furniture of two screens that had
been rendering nothing but a tide header since iteration 5. Following the dead
`DISPATCH_PHRASE` label uncovered `Strings.PHRASE`: 12 canned lines superseded by 120
letters in iteration 7 and still handed to the renderer three iterations later.
Doc 08 §8.5; the parsing lesson in doc 10 §13.

**OD22.** `loadLedgerPage` was called by nothing, so everything past the most recent
200 entries was archived and unreadable forever — the worst available bug for a game
whose first pillar is *absence is content*. Underneath it, pages were keyed by epoch
and `saveLedgerPage` overwrites, so two servers flushing in one epoch destroyed one
of the two pages. Doc 05 §9.2.

---

## Iteration 11 ✅ — 54 of 86 config constants were verified by nothing

| Deliverable | Status |
| --- | --- |
| **`tidekeeper-mutation-scan.js`** — gate check 19, level seven of the ladder | ✅ |
| 18 economy constants + the blob budget pinned; guarded set 28 → 47 | ✅ |
| **OD15 closed, with numbers** — and a wrong first answer caught and corrected | ✅ |
| The dispatch/letters path read end to end; scenario 27 drives the whole chain | ✅ |
| The shore screen draws the tide dial; the orders editor previews a change | ✅ |
| Orphan allowlist 23 → 20; the "client UI not built" category is **empty** | ✅ |
| Session scenarios 27–28, `EconomyPinning` and `BlobBudget` sections | ✅ |

**The find.** Changing every scalar in `Config/` by one and re-running all 1 755
assertions: 54 of 86 could be changed with the suite still green — including every
number in the economy table. Doc 06 is the longest design document in the project and
nothing verified its numbers.

**The trap worth knowing:** `eq(delta.warmth, EconomyConfig.WARMTH_BASE_SERVED)` pins
nothing, because mutating the config moves both sides together. That *is* a vacuous
test. A pin needs a literal plus a behavioural link. Doc 10 §14.3.

**Two cheaper questions came back clean** and are recorded so nobody re-spends the
hours: assertions that never run (3 of 1130, all legitimate failure branches) and
tests asserting on non-existent fields (1615 refs, 0 problems).

---

## Iteration 12 ✅ — the fake platform was lying, and it hid a data-loss bug

| Deliverable | Status |
| --- | --- |
| `fake-platform.lua` audited against the real DataStore/MemoryStore APIs | ✅ |
| **Five divergences fixed**, all in the more-forgiving direction | ✅ |
| **A real data-loss bug found and fixed** in `allocLedgerPage` / `drainReceipts` | ✅ |
| Transform re-runs are now the **default**, not opt-in | ✅ |
| `Saturation` section — five ceilings actually reached; guarded 47 → 52 | ✅ |
| **OD19 closed** — keep fengari; it is the only VM running smoke and session | ✅ |
| Session scenario 29 | ✅ |
| **Studio (L4/L5)** | ❌ no access — unchanged since iteration 4 |

**The find.** Roblox re-runs an `UpdateAsync` transform on contention, discarding
earlier results. The fake called every transform exactly once, so two adapters that
accumulated into upvalues — resetting in the retry wrapper instead of inside the
transform — were correct against the suite and would have deleted ledger pages that
were still in the index in production. Doc 05 §9.3, doc 10 §15.

---

## Iteration 13+ ⬜

**Studio verification (L4/L5) is now the largest gap by a wide margin** — no Instance
has ever been created, no DataStore call has ever been real, no frame has ever been
drawn. Otherwise: shrink the 37 known-unguarded constants, the idea bank in doc 00 §9,
and whatever level eight turns out to be. Scope is defined by `HANDOFF.md`, not by
this table.

---

### Decisions D53–D54 (iteration 12)

**D53 — an `UpdateAsync` transform must be re-entrant.** Roblox may run it several
times within one call and discard the losers. Anything the transform accumulates into
is reset as the transform's first statement, never in the surrounding retry wrapper.
Doc 05 §9.3.

**D54 — a test double must never be more permissive than the thing it doubles.** A
stricter fake produces false alarms, which get noticed; a looser fake produces false
confidence, which does not. Where the real API errors, the fake errors. Doc 10 §15.2.

### Decisions D50–D52 (iteration 11)

**D50 — a pinned constant needs a literal and a behavioural link.** Asserting
behaviour against the constant alone is vacuous: mutate the config and both sides
move together. The literal is the tripwire; the behavioural assertion stops the
literal becoming a lie. Doc 10 §14.3.

**D51 — test a new scan against a legitimate but unusual idiom before trusting it.**
Iteration 10 predicted this and iteration 11 proved it twice: a trailing comment on a
config line made the mutation scan report a constant as missing, and the same
brittleness had hidden two constants from the scan entirely.

**D52 — a measurement must compare like with like, and say what it excluded.** The
first OD15 answer was 3.6× too flattering because it serialised data the packed form
does not store. A flattering number from an unfair comparison is worse than no number.

### Decisions D47–D49 (iteration 10)

**D47 — a scan must blank whatever can lie to it and keep whatever carries meaning.**
Iteration 9's rule ("parse from raw, detect in stripped") was the special case, not
the principle: when the thing being detected *is* a string literal, stripping erases
every call site and raw text lets comments vote. `dead-content-scan` carries
`stripComments()` for exactly this. Doc 10 §13.2.

**D48 — content is reachable or it does not exist.** A string, a prose row or a
template that no code path can put in front of a player is not "content for later",
it is a thing that will be translated, reviewed and paid for and never read. Both
directions: a label nothing displays, and a `Format.label` naming a key that is not
there (which renders as an empty string and counts a silent miss).

**D49 — one action in flight at a time.** `invoke` yields, so a second tap races the
first reply into the snapshot. Refusing locally with `ERR_BUSY` is both truthful and
kinder than letting the server's rate limiter call it a rejection.

## Open decisions

Recorded rather than guessed. Each has an owning iteration.

| # | Decision | Owner | Current lean |
| --- | --- | --- | --- |
| OD1 | Shipping title (doc 00 §10) | it5 | "Keep a Tidepost" |
| OD2 | Currents geographic or thematic (doc 03 §12) | it5 | Thematic, with a geographic bias in shard selection |
| OD3 | Drifter TTL — is 7 days right? | it5 | Instrument it; do not guess |
| OD4 | Do Echoes read as dishonest? (doc 03 §8) | it5 | Playtest; the Ledger marker must be prominent |
| OD5 | Is `warmth` ever public? (doc 03 §12, doc 08 §9) | it5 | No, aggregate colour only. Reopen only with a policy review |
| OD6 | Can a player see whose Drifter it was? (doc 03 §12) | it4 | Display name only, no link, no join |
| OD7 | Does the daily notification cap really reset on visit? (doc 10 §1.2) | ~~it3~~ | **Moot for now (doc 10 §6.1): the API has not shipped.** The shipped docs describe a flat 1/user/day static throttle and that is what `NotifyService` enforces |
| OD8 | Does Scene Generator ship in 2026? (doc 09 §2) | it5 | Assume no; hand-build contingency is the plan of record |
| OD9 | Do MemoryStore keys count toward the memory quota? (doc 10 §6) | ~~it3~~ | **Answered (doc 10 §6.2): documented as counting for sorted maps, unstated for hash maps.** `MemoryAdapter` charges for them |
| OD10 | Offline-play reconciliation policy (doc 04 §11) | it5 | Last-write-wins on post, union on ledger, conflict noted |
| OD11 | Rewarded Video Ads at all? (doc 13 §4) | post-it5 | Not at launch; the tone is fragile |
| OD12 | Is `Visit.resolve` actually inside 18 µs in Luau? | ~~it4~~ | **Closed at L3.5 (doc 04 §6.1).** Real Luau 0.700, median **15.9 µs** against an 18 µs budget — inside, but only 1.1×. p99 26.3 µs and full catch-up 2.9 ms both have room. `--codegen` is *slower*, so the hot path is table-bound, not arithmetic-bound |
| OD13 | Arrival scheduling is window-width dependent (see below) | ~~it3~~ | **Closed.** `CadenceService.planChunks` and `chunkForDrifter` are pure; at-most-once is asserted by session scenario 8 |
| OD14 ✅ | Should `warmth` feed the price a Drifter will accept, not just the prose? | **it7** | **CLOSED: no.** Held for three iterations waiting for a playtest that six iterations without Studio access make clear is not coming soon. Deciding it costs nothing to reverse and leaving it open was costing a decision every iteration. The reasoning has not changed and is not really empirical: wiring warmth into price turns it into a stat to farm, makes every visitor an optimisation problem, and contradicts doc 00's pillars directly. Warmth stays prose-only — it is something you notice, not something you optimise. Re-open only if a playtest shows players cannot tell warmth does anything at all, and fix that with better prose first. |
| OD15 ✅ | DataStore compresses values itself; does our base64 packing still pay? | ~~it11~~ | **Closed with numbers (doc 10 §14.6).** On a heavy post, comparing only the fields `PostCodec` persists: binary+base64 **1 252 B raw / 474 gzipped**, naive JSON **3 836 / 772**. So 3.06× raw and **1.63× after compression** — keep the packing, but the honest margin is 1.6×, not the 6× the first attempt claimed (that run serialised a resident ledger the post blob does not contain, and the round-trip assertion caught it). The stronger argument is the one the ratio hides: packing gives a **hard bound** on blob size, which is what makes the 6 144-byte budget enforceable at all |
| OD17 | Run the correctness suite in real Luau instead of transformed Lua 5.3 | ~~it5~~ | **Closed (doc 10 §8.4), and without Lute.** `tidekeeper-luau-test.js` runs the suite shim-free; 887 = 887 against fengari, 0.7 s vs 72 s. Lute release binaries remain unreachable and turned out not to be needed — it would have added a test runner and a profiler, not a different measurement |
| OD18 | Adopt **LibMP** to measure the client frame budget on real devices (doc 10 §7.2) | it6 | Yes for the Ledger replay, sampled on a fraction of sessions — Roblox warns it raises memory. **Blocked on Studio**, like L4/L5 |
| OD19 ✅ | Delete fengari now that real Luau runs the suite? | ~~it12~~ | **Closed: keep it, for a reason nobody had stated.** The two-VM cross-check is the *secondary* benefit. The decisive fact is that smoke (1 267) and session (634) run **only** under fengari — real Luau runs only the bundled pure suite — so deleting fengari would delete 1 901 assertions, including the entire server-against-fake-platform layer. The real question for a later iteration is the inverse: port the session harness to bundled Luau so the fake platform runs on the actual target VM |
| OD20 | The three dispatch fields are session-scoped, not persisted | it8 | Left as is, deliberately. A dispatch choice that does not survive a relog is a small loss; persisting it costs a schema field and a migration for something the player re-picks in one tap. Revisit only if telemetry shows players dispatching and relogging inside one epoch |
| OD21 ✅ | `DataStoreAdapter:reapPoolShard` is never scheduled, so the drifter pool only grows | ~~it9~~ | **Closed (doc 05 §9).** `ExchangeService:reapTick` on the IO slot, one shard per tick, targeting `epoch - 28` — nothing can claim a key that old, because resolve clamps catch-up to 27. *Which* server was the real question: exactly one, by a `reap:<epoch>` MemoryStore lease via the new `MemoryAdapter:tryLease`. 320 keys per epoch deleted once rather than once per server; losers count `reapLeasesLost` and skip. If MemoryStore is unavailable **nobody** reaps — a missed reap is visible growth, twenty blind reapers during an outage is a quota fire. Proved by session scenario 23, including a negative control where removing the lease makes a second server duplicate 284 deletes |
| OD22 ✅ | Ledger history is written and never read | ~~it10~~ | **Closed (doc 05 §9.2).** `loadLedgerPage` had no caller and no way to be called: page keys were `l:<user>:<epoch>` and nothing recorded which epochs had pages. Pages are now numbered from an atomic counter in a per-player index key — which also fixed a silent data loss, since `saveLedgerPage` overwrites and two servers flushing inside one 6.2-hour epoch destroyed one of the two pages. `RF_History` (2 burst, 10/min) + `HistoryHandler` + a client pager whose cursor counts back from the newest page. Retention 32 pages, with the falling-out keys deleted as they fall — the ledger reaper, which costs nothing extra because it runs where the information already is |
| OD23 ✅ | Handler status code `4` means two different things | ~~it10~~ | **Closed.** `NetContract` owns one enum; `E_ALREADY_OUT` moved from 4 to 5; all three handlers read it; `ClientBootstrap:statusText` lost its remote-name parameter and is a pure mapping again. Session scenario 26 walks every status and asserts each has a distinct, non-empty sentence that is not the offline message, and that an unknown code still degrades to offline — the right default for a client talking to a newer server |
| OD16 | `S.publishedAt` is not persisted, so one-Drifter-per-epoch holds only per server (doc 10 §6.4) | ~~it4~~ | **Closed.** Schema v2 appends it at the blob tail with a real migration and a committed v1 fixture (doc 05 §6.1). Shipped a sentinel bug en route — see **D28** |

### OD13 in full — the one non-commuting property

Iteration 2 found and **pinned** a property that iteration 3 must respect. A Drifter's
arrival epoch is `firstEpoch + (Hash.mix(id, salt, 7) mod epochCount)`. `epochCount` is
the width of the window being resolved, so feeding the *same* inbound list to a 1-epoch
resolve and then a 2-epoch resolve does **not** produce the state of a single 3-epoch
resolve. With no inbound drifters the resolver commutes exactly (asserted); with inbound
drifters it does not (also asserted, as a negative test, so it cannot silently change).

This is correct behaviour, not a bug: in the live game the exchange hands each Drifter
to exactly one resolve. But it makes *at-most-once delivery* a hard requirement on
`ExchangeService`, not a nicety, and a retry that re-delivers a batch would corrupt
history rather than duplicate it.

## Validation snapshot — end of iteration 5

| Check | Real output |
| --- | --- |
| `tidekeeper-quality-gate.js` | **13/13** checks passed |
| `tidekeeper-doc-gate.js` | **172/172** checks passed |
| `check-syntax.js` | all **57** Luau files parsed |
| `tidekeeper-determinism-scan.js` | **clean** — 13 rules, 5 allowances, **2/2** RunService connections |
| `tidekeeper-smoke-test.js` (fengari) | **888 passed, 0 failed**, 3/3 static proofs |
| `tidekeeper-luau-test.js` (real Luau) | **887 passed, 0 failed, agrees with fengari** — 0.7 s |
| `tidekeeper-session-test.js` | **167 passed, 0 failed** — 16 scenarios |
| `tidekeeper-luau-bench.js` | **within budget** — median 15.5 µs, p99 23.8 µs, catch-up 2.87 ms |
| Executed assertions | **1 055** (888 + 167), plus 887 cross-checked in a second VM |
| Verification level claimed | **L3.5** — correctness *and* timings now in a real Luau VM. Still not L4: no engine |

## Validation snapshot — end of iteration 4

Full command output is pasted in [`HANDOFF.md`](HANDOFF.md) §2.

| Check | Real output |
| --- | --- |
| `tidekeeper-quality-gate.js` | **12/12** checks passed (11/12 + 1 skip without a local `luau` binary) |
| `tidekeeper-doc-gate.js` | **172/172** checks passed |
| `check-syntax.js` | all **57** Luau files parsed |
| `tidekeeper-determinism-scan.js` | **clean** — 57 files, **13** rules, 5 explicit allowances, **2/2** RunService connections |
| `tidekeeper-smoke-test.js` | **888 passed, 0 failed**, 3/3 static proofs |
| `tidekeeper-session-test.js` | **117 passed, 0 failed** — 15 scenarios against a fake DataModel |
| `tidekeeper-luau-bench.js` | **within budget** — median 15.9 µs, p99 22.3 µs, catch-up 2.95 ms |
| Measured platform cost | **5.64 DataStore / 5.24 MemoryStore requests per session** (unchanged) |
| Gameplay code | **57** modules, **12 222** lines, layers L0–L5 |
| Verification level claimed | **L3.5 — runs in a real Luau VM** (doc 09 §4). Not L4: no Roblox engine was involved |

## Validation snapshot — end of iteration 3

Full command output is pasted in [`HANDOFF.md`](HANDOFF.md) §2.

| Check | Real output |
| --- | --- |
| `tidekeeper-quality-gate.js` | **11/11** checks passed |
| `tidekeeper-doc-gate.js` | **159/159** checks passed |
| `check-syntax.js` | all **48** Luau files parsed |
| `tidekeeper-determinism-scan.js` | **clean** — 48 files, 10 594 lines, **12** rules, 5 explicit allowances |
| `tidekeeper-smoke-test.js` | **858 passed, 0 failed**, 3/3 static proofs |
| `tidekeeper-session-test.js` | **72 passed, 0 failed** — 14 scenarios against a fake DataModel |
| `find-dead-config.js` | **no dead keys** — the five reserved keys are now consumed or display-only |
| Measured platform cost | **5.64 DataStore / 5.24 MemoryStore requests per session** over 200 sessions, 8 posts, 30 virtual days |
| Gameplay code | 48 modules, 10 546 lines, layers L0–L4 |
| Verification level claimed | **L3 — runs against a simulated platform** (doc 09 §4) |

### Iteration-2 snapshot, kept for the record

| Check | Real output |
| --- | --- |
| `tidekeeper-doc-gate.js` | 148/148 |
| `tidekeeper-quality-gate.js` | 10/11 passed, 1 not applicable yet |
| `check-syntax.js` | all 25 Luau files parsed |
| `tidekeeper-determinism-scan.js` | clean — 25 files, 5 288 lines, 8 rules |
| `tidekeeper-smoke-test.js` | 858 passed, 0 failed |
| Gameplay code | 25 modules, 5 263 lines, layers L0/L2 only |
| Verification level claimed | L2 — executed in a Lua VM outside Roblox |

### Iteration-1 snapshot, kept for the record

| Check | Real output |
| --- | --- |
| `tidekeeper-doc-gate.js` | 137/137 |
| `tidekeeper-quality-gate.js` | 3 pass, 7 N/A, 0 fail |
| Gameplay code | none — deliberately |
| Verification level claimed | none (docs only) |
