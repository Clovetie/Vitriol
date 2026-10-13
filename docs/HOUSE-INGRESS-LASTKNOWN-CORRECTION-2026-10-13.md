# Genuine LastKnown House ingress staging — guarded Edit correction (2026-10-13)

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

## What the user actually reported

The newest human Play had **no House exit verdict**: the Braid was visibly **on the ground outside House_01 and spasming**, while the player was inside with original cover placed. Server Output had `LastKnown core(-54.5,72.2) goal(-84.5,73.5) nav(-84.5,73.5) feet=4 block=none` and later `Prey core(-53.6,72.2) goal(-72.1,67.2) nav(-72.1,67.2) feet=4 block=none`. The first remembered goal is inside the real east door X≈−79; the second live-prey goal is on the **outside Porch**, not inside the floor footprint. The lines contain **X/Z, not core Y**. `block=none` is the one diagnostic Y=4 center ray only; four anchors are not proof of forward motion. This run does not erase earlier House_01 entry and one prior exit, or a separate later failed exit after dislodgement. See [`PLAY-REPORT-2026-10-13-INGRESS-CHURCH-CADENCE.md`](PLAY-REPORT-2026-10-13-INGRESS-CHURCH-CADENCE.md).

## Narrow diagnosed policy gap, not a full spasm diagnosis

The actual installed `CreatureService` used GarageNavigation's clear horizontal ray for `LastKnown` and sent the core directly toward `(-84.5,73.5)`, **skipping HouseAccess's existing porch-height and authored main-door stages**. This was true even when the remembered position was genuinely inside a house. The read-only Edit probe `tools/reports/house01-reported-ingress-edit-2026-10-13.json` confirmed a clear thin Y=4 direct ray; if asked to route this *stored* inside goal, the existing HouseAccess would instead choose the clear door approach `(-73,9,73.5)` from hypothetical core Y=8/10, or the outside lowering point `(-54,7.3,72)` at hypothetical Y=14/20. The unknown live core Y cannot be reconstructed. The `Prey` goal `(-72.1,67.2)` was on the Porch, so the inside-house router properly offered no inside-prey stage; **this correction does not diagnose or fix that separate Prey stall**.

A second read-only Edit probe (`tools/reports/house01-ingress-foot-support-edit-2026-10-13.json`) found the original Ground_QuarryFoundation top Y=0 under the logged exterior core coordinates, an overhead-clear approach up to the porch eave, the original Porch top Y=1 at X≈−65/−73, and the original PorchRoof underside Y=12.5 there. The original floor top inside is Y≈0.8. An offline stable-target planted-foot replay incorporating those separately measured support surfaces crossed from exterior ground onto the Porch without a spasm; that simplified replay **did not reproduce the user's dynamic live stall** and cannot identify its cause.

## Correction, tests and guarded installation

Only `code/ServerStorage/Vitriol/Services/CreatureService.luau` changed: while pursuing a **genuinely last-seen, stored** goal, it now asks the existing HouseAccess for a physical entry waypoint *before* the usual one clearance ray and garage detour. If the stored goal is not grounded inside a house, the House policy returns nil and the prior target is unchanged. No current hidden-player coordinates, global locator, authored geometry, runtime Instance, gait, prey/chomp priority or budget share were added. The existing roof recovery retains higher priority. A new regression **failed before** the change (direct target inside), then passed after it for both authored houses; a stored outside Porch target still uses its original path. Focused House fixture **78/78** includes the measured-support exterior→Porch replay; Garage **69/69**, church route **10/10**, full local quality gate **40/40**, official Luau compiler **61/61**. These are not live frame measurements.

Before deployment a **read-only** exact Source/class snapshot of the *previously owner-saved* Studio CreatureService was placed in `backups/vitriol-studio-edit-creature-pre-ingress-2026-10-13.zip` (one Module only; **not a full place backup**). `tools/sync-house-ingress-lastknown.py --check` verified correct Vitriol place ID, Edit mode, class, and exact prior full Studio Source against that ZIP. Five offline fail-closed sync tests passed. With the owner's earlier verified Save to Roblox with Notes as the pre-write checkpoint, guarded `--apply --saved-checkpoint-verified` wrote **only that existing ModuleScript**, then exact Source/class readback and a second read-only `--check` passed (new Source SHA-256 prefix `7621678c1f4ade79`). No House/Church Parts, furniture, phases, UI, gait Source or other script was written. **The owner subsequently confirmed a NEW Save to Roblox with Notes and verified its Version History entry for this latest Source**. This cloud checkpoint is human-reported, not independently visible through the bridge; no new Publish is claimed.

The immediately following read-only full Edit audit saw **10/10 authored verifiers but flagged one unrelated Studio Source drift**: `DayNightConfig.NightBaseSeconds` was now **70** instead of the older pinned Studio value 200. The owner explicitly confirmed **70 is intentional**. We preserved it unchanged, independently read back and hash-archived *that one Source* at `backups/vitriol-studio-edit-daynight-70-2026-10-13.zip` (not a full place), then updated only the audit's **exact pair of local/Studio hash pins** and its offline regression test. The fresh read-only audit `tools/reports/vitriol-studio-audit-after-ingress-owner-70-confirmation.json` now passes **10/10** verifiers and **61/61** Source/class checks (46 exact, 13 one-terminal-LF differences, two explicitly pinned owner-preserved Studio differences, **zero unexpected drift**). The local `DayNightConfig` was **not** synced over the user's 70-second test Night. The abbreviated Night may end before an entire local patrol or distant church arrival; mark such Play trials incomplete, not failed.

## Roadmap and next practical evidence

**M2 ingress is still OPEN.** This guarded fix addresses the LastKnown doorway-policy bypass, not proven locomotion causality; the later Prey/Porch spasm remains unaccounted for in live movement. On one fresh Play after the newest owner-verified save, observe whether the grounded Braid can now move from X≈−54 across exterior ground, get under the Porch eave and enter House_01 while the player is inside with cover. If it stalls, record **which goal kind** (`LastKnown` vs `Prey`), whether it actually reached the Porch, visible body/foot height and a short clip if possible. Do not interpret a stationary or timed-out Night as an exit verdict, especially at intentionally short `NightBaseSeconds=70`. M3 fourth Garage entry, full church lure route and real cadence remain separately open; do not hide measured Session/DayPrep/BellHoist/Time overruns by raising budgets. No bridge snapshot of Play is possible.
