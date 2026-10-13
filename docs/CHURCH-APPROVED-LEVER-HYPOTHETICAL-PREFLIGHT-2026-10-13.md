# Approved church lever Z=-210: read-only hypothetical preflight — 2026-10-13

> **Later owner decision:** The owner explicitly approved keeping the
> already-authored lever at `(119,2.5,-199)` instead of restoring the former
> Z=-210. This document records the **earlier hypothetical** comparison,
> not an open relocation request. No geometry was moved; the updated read-
> only Edit audit passes 10/10. See
> [`CHURCH-LEVER-CURRENT-POSITION-APPROVED-2026-10-13.md`](CHURCH-LEVER-CURRENT-POSITION-APPROVED-2026-10-13.md).

**Status:** The owner confirms the *post-sync* Save to Roblox with Notes and its new Version History entry. A fresh guarded Edit-only `--check` still finds the two installed House/Church ModuleScript Sources and classes **2/2 exact**. No further Studio Source or geometry write occurred. The lever is still physically at `(119,2.5,-199)`, **not** the previously approved `(119,2.5,-210)`; this report does not approve the current location or move anything. The bridge cannot provide live Play movement/cadence evidence.

## Read-only geometric finding

`jobs/probe_church_approved_lever_hypothetical_edit_vitriol.lua` guards the Vitriol place and Edit mode, asserts the unchanged actual lever, and asks a *hypothetical* question: what do physical rays see on the straight main-entrance `(119,-130.25)` → previously approved `(119,-210)` route **if only the currently intervening lever is excluded from the query**? The complete report is `tools/reports/church-approved-lever-hypothetical-edit-after-save.json`. Exclusion changes only those probe ray filters; it does not reposition or disable the actual lever.

- Without exclusion, the first Y=4 ray hits the original lever at Z≈-199. With only that lever and the Braid model excluded, the first hit is the **original Bell MeshPart** centered at `(119,5.03,-205.01)`. It is anchored, **CanCollide=true** and CanQuery=true; size is about `(9.38,9.02,9.38)`.
- Across seven lateral offsets X=`−2,−1.5,−1,0,1,1.5,2`, all **7/7 Y=4 rays** hit the Bell, and **5/7 Y=9 rays** hit it. Thus **12/14 rays are obstructed**; unlike the existing-lever Z=-199 corridor, there is no straight body-width two-height clearance to hypothetical Z=-210. This says nothing about an untested side detour.
- A downward ray at Z=-210 hits the original collidable **NaveFloor**, top around Y=0.8. Ground support at the target is present, but support alone does not grant a clear approach. Downward probes at Z=-203 and -207 contact the original Bell before reaching floor.
- The **installed** `ChurchNavigation.Source`, evaluated in memory using that hypothetical filter, returns `(119,-210)` even though its ray hits the *collidable* Bell. This is the pre-existing `bellModel`-descendant endpoint allowance, not the new exact-lever exception. It permits a waypoint but **does not prove the elevated core or planted feet can pass through the Bell**. No through-wall/body-clearance claim is made.

The current actual-lever route `(119,-199)` remains separately supported by the installed-source Edit probe and 14/14 adjacent clear rays to that *current* position when the lever itself is excluded as endpoint. If the lever were later moved back to the approved Z=-210, a straight final approach would need further safe-route reasoning; simply editing its Position while keeping the existing waypoint policy could direct the Braid toward the collidable Bell. Conversely, `CreatureService` counts a bell investigation when within 12 studs of the lever, so reaching the lever center might not be necessary for the Night lure; **whether the real Braid safely stops or detours is untested in Play**. The preflight does not establish player prompt usability after a move, nor justify changing the bell, church UnionOperation, lever, gait, or clickability.

**Decision boundary:** The user-approved coordinate is still Z=-210, yet current authored geometry is Z=-199. Do not silently accept Z=-199 or move the lever to Z=-210 on the basis of this hypothetical ray check. An explicit geometry/route decision and a separate guarded save are needed before changing the place. The latest full Edit audit remains **9/10** because of the lever-position mismatch; **61/61** Sources/classes and zero unexpected Source drift were found at the post-sync audit. The owner has since verified the post-sync Save to Roblox with Notes. House/Garage live egress, actual church lure, fourth Garage visit, and measured cadence still have no fresh Play verdict.
