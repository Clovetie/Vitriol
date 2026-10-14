# User Play report — house ingress stalls, incomplete church lure, real cadence overruns (2026-10-13)

> **NEWER HUMAN PLAY / LOCAL-ONLY FOLLOW-UP (2026-10-14):** The
> owner confirms the Braid **entered House_01 AFTER dislodging its
> original closet**; the break Output gives outside core(-72.0,8.6,78.0)
> and genuinely-sensed-prey goal(-87.0,78.0). It needed renewed visibility
> to break a piece it seemed to be pressing. By explicit owner choice,
> a narrow, locally tested recent-genuine-indoor-clue contact rule is now
> pending in CreatureCore + CreatureService (**NOT installed or saved**).
> Local House-cover 69/69, full repeated-Think breach 11/11 at BOTH houses, and gate 44/44; no new Play verdict for that rule.
> The Edit bridge `run_luau` guard intermittently returned
> `loadstring() is not available` despite owner-confirmed Edit. A later
> successful pre-read guard captured EXACT read-only two-Source backup
> `backups/vitriol-studio-edit-cover-pre-2026-10-14.zip`, but a subsequent
> guard again failed. NO Studio Source write occurred; do NOT sync until
> mode checks are reliable. After reconnect, one of four identical
> read-only Edit probes STILL failed; `--check` alone passing does not
> establish reliability. House_01 EXIT remains open, as do
> House_02, Garage habit, church entrance and actual DayPrep/Time budget
> overruns (new Time:Publish 0.557/0.050 ms, attributes 0.530). Do NOT
> claim Edit parity for this local candidate or ask for Play acceptance
> until a verified guarded sync and NEW cloud save. See
> [`PLAY-REPORT-2026-10-14-CLOSET-CONTACT-CADENCE.md`](PLAY-REPORT-2026-10-14-CLOSET-CONTACT-CADENCE.md)
> and [`NEXT-PLAY-SUMMARY-2026-10-13.md`](NEXT-PLAY-SUMMARY-2026-10-13.md).
> Earlier blocks below record earlier checkpoints.

> **Later bounded follow-up:** The owner confirmed the Braid was on the
> ground outside and spasming while the player was indoors with cover. A
> narrow genuine-LastKnown House-door policy bypass was reproduced, locally
> corrected, guarded Edit-synced and **saved to Roblox with Notes/Version
> History (owner-confirmed)**. It has **NO fresh Play verdict** and does not
> account for the later `Prey` Porch stall. The owner separately confirmed
> the Studio-only 70-second Night is intentional; do not overwrite it.
> Latest exact-hash read-only Edit audit 10/10 verifiers, 61/61 Sources/
> classes, zero unexpected drift; local gate 40/40. See
> [`HOUSE-INGRESS-LASTKNOWN-CORRECTION-2026-10-13.md`](HOUSE-INGRESS-LASTKNOWN-CORRECTION-2026-10-13.md).

## Returned next-Play summary

The owner says this was a fresh Play after the verified post-sync Save to Roblox with Notes. **House exit was not exercised**: in this run the Braid did not enter the houses. The owner did not report three genuinely witnessed Garage entries or a fourth-visit habit test. The bell rang, but the Braid did **not** reach the main church entrance before the lure ended; it then headed toward the Garage. That is a **partial/negative church timing/route observation**, not a verdict that the installed route is geometrically impossible, nor proof that a witnessed Garage habit caused the next target. The bell audio/flashes had been accepted previously; the Braid's full route remains unverified.

### New live ingress evidence (Server Output)

```text
23:21:23.846  [vitriol] warn: pursuit stall LastKnown core(-54.5,72.2) goal(-84.5,73.5) nav(-84.5,73.5) feet=4 block=none
23:21:48.181  [vitriol] warn: pursuit stall Prey core(-53.6,72.2) goal(-72.1,67.2) nav(-72.1,67.2) feet=4 block=none
```

**Owner follow-up:** The Braid was visibly **on the ground outside and “just started spasming.”** The player was **inside House_01 with original cover placed**. The exact Braid core height, which piece(s) were installed at each warning, and whether its feet contacted ground or the porch are still not logged. These logged core/goal/nav pairs are **X/Z only**, not height Y. Both core positions are east/outside of House_01's authored east door (X≈−79), around the outer porch approach. The `LastKnown` goal at X≈−84.5 is inside House_01; the later `Prey` goal at X≈−72.1 is nearer its outside porch. They are **two different goal types and times** and cannot be stitched into a continuous trajectory. `feet=4` counts anchored feet, not progress or full-body clearance. `block=none` means the diagnostic's **single ground-height** ray from core to lure did not hit a queryable Part; it does not prove ceiling, planted-foot, furniture, body-width or height clearance. At the time of this Play, the Source routed `LastKnown` through garage horizontal navigation, not HouseAccess's inside-prey entry/height staging. That policy gap was later corrected, but it is **not a proven cause** of the visible spasm. A guarded read-only Edit replay of the reported X/Z (`tools/reports/house01-reported-ingress-edit-2026-10-13.json`) found a clear direct Y=4 ray. The *existing* HouseAccess, if asked about the genuinely remembered inside goal, would instead choose the clear doorway staging point `(-73,9,73.5)` at hypothetical core Y=8/10, or the safe exterior lowering point `(-54,7.3,72)` at hypothetical Y=14/20. These Y values are **examples**, not recovered Play measurements. The later Prey goal at `(-72.1,67.2)` is outside the floor footprint, so HouseAccess correctly offers no inside-prey waypoint for it. Neither Edit result establishes why the planted-foot Braid spasmed.

Six client lines were condensed as `[Arena] poll failed: Http requests can only be executed by game server`. This appears separately in Client Output. Its relationship to the bridge/Play tools is not established; it is **not** the Server `pursuit stall` and is not a reason to change gameplay code or expose the temporary token.

### Real, unresolved cadence warnings from this Play

| Slot | Measured warning(s), budget | Context |
|---|---|---|
| `Session:Slow` | **0.245 / 0.050 ms** | begin-round, Running, Day |
| `DayPrep:Pulse` | **0.381, 0.313, 0.458, 0.329, 0.210, 0.350, 0.603 / 0.050 ms** | PrimeBell Day blackout→reveal; Night no prep with bell; Dawn CoverHouse01Closet; Day CoverHouse01Table; Day CoverHouse02Closet vote→blackout and blackout→reveal; Day CoverHouse02Table blackout→reveal |
| `DayPrep:BellHoist` | **0.214 / 0.050 ms** | Bell hoist |
| `Time:Publish` | **0.270 / 0.050 ms** | Dawn sample 121, attributes 0.235 ms, remote 0.030 ms |

These are **measured budget overruns**, including a worst reported DayPrep:Pulse of 0.603/0.050 ms. The Time:Publish warning itemizes an attribute section of 0.235 ms; that is same-sample timing, not proof of a general root cause. Do not raise warning shares or call the budget green. No new `Creature:Think` warning was supplied; that does not establish a Think performance pass.

## Roadmap disposition and next work

- **M2 House physical ingress/exit:** current ingress regression is now the first blocker. Prior Play did show House_01 entry and one exit in a separate session, followed by another failed exit after closet break; preserve all observations. This new run cannot evaluate the 120/120 synthetic **exit** grid because the Braid never got inside. Investigate House_01 outer-porch approach, target/height staging and foot progress first using read-only Edit/static probes. Do not damp the accepted elevated/planted-foot gait or move authored geometry on a guess.
- **M3 Garage habit:** untested this run. Do not attribute the post-bell Garage direction to three witnessed entries without evidence; a generator lure or other normal priority could also explain it.
- **M6 church lure:** bell rang; the Braid did not reach the main entrance within its timed lure in this run. Record as partial; the existing Edit route is not a live traversal verdict. Preserve audio/flash acceptance and the owner-approved lever `(119,2.5,-199)`.
- **Cross-cutting cadence:** all warnings above remain open. Compare future same-path measurements before editing costs; never hide them by raising budgets.

No Studio bridge Play snapshot exists or is possible. This report makes **no Studio Source or geometry write**, publish, cloud-save or Git-push claim beyond the owner's earlier verified save.
