# House_01 closet: Braid inside-to-outside egress (2026-10-12)

> **Independent House_02 Edit preflight (2026-10-13):** Read-only Studio
> Source/real-geometry probe found the original closet/table and markers,
> validated reverse bracing specifically on the closet, preserved the real
> one-stud uncovered gap and found the original east-door lane structurally
> clear. No Studio write. This is NOT human House_02 footed exit evidence;
> House_01's Play acceptance remains as stated below. See
> [`HOUSE-02-EGRESS-EDIT-PREFLIGHT.md`](HOUSE-02-EGRESS-EDIT-PREFLIGHT.md).


## Latest human Night Play acceptance and bounded follow-up (2026-10-13)

The user reported **“It dislodges itself and im pretty sure it can exit now; I couldn't test it cause I died before getting to.”** In follow-up, the user clarified that the Braid **visibly reached/pushed against the closet before it moved**. This is Play evidence of Braid contact followed by dislodgement; the Braid's completed exit was not observed during that run because the user died. In the next Play verdict, the user explicitly confirmed **seeing the Braid leave after dislodging the closet** (“It works,” clarified as “Yes, I saw it exit”). **House_01 contact→dislodgement→exit is human Play-confirmed.** No new error log was supplied. The 2026-10-13 follow-up added **test-only** post-breach Think→Step continuity plus a second independent House_02 inside→outside closet case (cover **63/63**, full gate **30/30**, compiler **58/58**); no game source or Studio object was changed or re-synced. House_02 exit and paid Dawn rebuilding have only headless evidence; do not infer their Play acceptance or modify the accepted House_01 geometry/gait without a new defect.

## User Play report and real geometry

The user confirmed the new Braid can **enter the house**, but it struggled to leave and the House_01 closet did not appear to break. They supplied two Night `pursuit stall LastKnown` warnings:

- `core(-91.7,79.4) goal(-57.5,78.9) ... feet=4 block=Workspace.Map.Interiors.House_01_Closet`
- `core(-90.9,78.3) goal(-63.9,77.9) ... feet=4 block=Workspace.Map.Interiors.House_01_Closet`

Their clarification: the object was likely House_01's closet, **the Braid** was the one having difficulty leaving, and Play was stopped. Guarded Edit-mode reconstruction against the user's existing marker showed the Braid was already **inside** the house in both logs; the goal was **outside**. At the closet doorway plane X=`-81.5`, the two direct paths cross at Z≈`79.25` and `78.16`, both inside the actual unchanged closet's six-stud span Z=`74..80`. Core-to-plane distance was `10.2`/`9.4` studs, within bounded tendril bracing reach. Four footholds were planted; this was not evidence to alter the accepted gait or house geometry.

## Narrow correction

`HouseCoverService` had treated contact as **outside→inside only**. The anchored Braid could not physically phase through the placed closet, but its reverse crossing never counted as contact or built breach pressure. It now checks the *same original furniture footprint in either direction*. A freshly sensed living prey target can authorize physical bracing from either side. When there is no sensed prey, a valid **server-owned light/bell lure or unexpired last-*observed* position** may authorize **inside→outside only**, after the Braid reaches and actually presses the item within 12 studs. Such a destination cannot break house cover from outdoors and never consults a hidden player's live coordinates. On sustained contact the specific original Part dislodges home after the existing 2.4-second tell, while other installed pieces remain. Interrupted contact resets pressure; after Dawn that piece alone is eligible for a new paid Day move. No player-operable Night release was added, per the user's explicit choice. No geometry, accepted locomotion, extra scheduler, UI or runtime Instances changed.

## Executed evidence and next observation

- Focused `tools/vitriol/house-cover.luau` **63/63**: reproduces **both exact logged rays**, rejects distant/wrong-side egress, prevents exit-phasing without a valid intent, rejects expired LastKnown memory, drives real `CreatureService:think` on the captured outside destination, then drives actual `CreatureCore:step` for 23 not-yet-broken contacts plus the 24th breaking **only House_01_Closet**. The new test drives the **next real Think and three deterministic Core steps**: the Braid continues outward toward the still-valid last-observed point and the other three pieces remain installed. House_02 then runs its own original closet and valid last-observed outside goal through real Think and 24 Core contact steps: only that closet breaks, the House_01 closet stays broken, both tables remain installed, and both closets become independently rebuildable after Dawn. The fixture overrides locomotion displacement, so this is control-flow evidence, **not** a visible gait or human Play exit verdict for either house. Existing helper-voted time charges, roof/door height and ingress tests remain covered by the full gate.
- Full local quality gate **30/30**, official Luau compiler **58/58**, `git diff --check HEAD` clean. Three changed game ModuleScripts were guarded-synced in Edit mode and **3/3 exact Source/class readbacks** passed. A fresh Edit-mode compile of actual Studio `HouseCoverService.Source` reproduced the reverse bracing for BOTH user logs without moving any furniture; the four-piece read-only Studio furniture verifier returned `ok:true`.
- **House_01 Play-accepted:** user confirmed seeing the Braid exit after the closet dislodged. House_02, paid Dawn rebuild, normal frame time and cadence budget compliance remain unconfirmed. Studio save/publish and Git push remain unconfirmed.

### Optional remaining Play checks

During Night, move House_01's closet into its original-size doorway via the normal Day action. Let the Braid enter and then follow a recently observed survivor OUT through the same entrance. Observe a brief physical push, the **closet alone** returning to its home spot, and the Braid moving out rather than repeating `LastKnown ... block=...House_01_Closet` stall lines. Its table should remain installed. Repeat with House_02 if practical. If the Braid still stops, provide the first new `pursuit stall` warning and whether the closet actually moved; do not use the old one-way diagnosis for a different blocker. If it loses every target before reaching the door, it may idle rather than omnisciently chase a hidden survivor—that behavior remains an explicit sensing limitation, not a claim of continuous patrol.
