# Garage decision Output — offline instrumented, subsequently Edit-synced (2026-10-13)

> **Subsequent bridge result:** The four pending House/Garage Modules were
> guarded-synced to Vitriol **Edit**, exact Source/class **4/4**. Read-only
> actual-Studio-Source Garage probe passed; **server Output during a live
> fourth visit, Save to Roblox and Play remain unconfirmed**. See
> [`STUDIO-EDIT-SYNC-AND-SOURCE-BACKUP-2026-10-13.md`](STUDIO-EDIT-SYNC-AND-SOURCE-BACKUP-2026-10-13.md).

The user cannot test in Play now. This small follow-up makes the already-existing witnessed Garage habit explain **two genuine transitions** in server Output, without inspecting hidden player locations or claiming a live fourth-visit verdict:

- When a genuinely sensed, grounded outside→inside entry first brings bounded evidence across the three-entry threshold, queue `Garage habit witnessed entries=3 evidence=3/3 misses=0 reason=observed-entry`. This does not choose a destination; freshly sensed prey still wins.
- When a clue-less Night later actually chooses the Garage habit's physically checked front/inside route, queue `Garage habit chose entries=3 evidence=3/3 misses=0 reason=witnessed-three-garage-entries`. A held route does not print on every Think. Each kind of event is capped once per Night. Bell, live prey, relevant noise and recent genuine clues retain priority, so no lead line is expected if one wins.

The service only sets a couple of state labels **inside** the existing 6 Hz measured `Creature:Think` slot. The existing `CadenceService.OnSample` hook emits the line **after** its `os.clock` measurement, for `Creature:Think` only. It logs aggregate entries, bounded evidence, miss count and decision reason; not player ID, player/goal coordinates, hidden prey position or any client remote. The measured Think budget, watchdog, phase durations, authored Instances, physical rays, target priority, gait and Day/Night rules did not change. The server log is a diagnostic, **not** proof that the route succeeds. `aiDump()` remains server-only and can be inspected separately in a legitimate live server; the Edit bridge cannot inspect Play.

**Local evidence:** `tools/vitriol/garage-habit.luau` **69/69** asserts continuous grounded threshold walks, fresh prey priority, deferred callback ordering (an unrelated sample cannot flush a Garage line), one lead line per Night, no ID/seen-or-hidden coordinate in the lead line, held-route behavior, authored bell priority, route safety, Day withdrawal and zero runtime-created gameplay/UI Instances. The harness invokes the same callback Cadence invokes after it stops its timer, but its time and geometry are synthetic. Full quality gate **36/36**, official compiler **61/61**, `git diff --check HEAD` clean. `tools/reports/quality-gate.json` is the local report. **No live performance sample** follows from these tests.

> **Later offline House follow-ups:** Pending workspace changes now include
> lower-before-ray, full-core pier/cover-corner guards and an actual
> supported-foot doorway posture in `CreatureCore` (House **63/63**).
> Four Sources have a fail-closed deployment plan in
> `tools/sync-pending-house-garage.py --offline`; see
> [`HOUSE-EXIT-FOOT-SUPPORTED-LOWERING.md`](HOUSE-EXIT-FOOT-SUPPORTED-LOWERING.md).

**Deployment status:** Only workspace Sources `code/ServerStorage/Vitriol/Services/CreatureService.luau` and `code/ServerStorage/Vitriol/Bootstrap.luau` changed in this follow-up. The bridge credentials are not available in this environment, so this follow-up has **not** been guarded-synced to Studio and no Studio Source/class readback exists for it. Do not interpret the new Output as available in the currently open Studio place until a future guarded Edit-mode sync verifies place `92448193604950`, not-running state, and exact prior Bootstrap/CreatureService/HouseAccess/CreatureCore Sources/classes, then writes only the four pending Modules and checks exact final readback. Do not overwrite unrelated user Studio edits if either prior Source differs. No save, publish or Git push is confirmed.

**Still open:** actual fourth-Garage-visit choice in Play, both House exits (House_01 has one earlier success and later failures), the live `Creature:Think` budget, and real Session/DayPrep/Time overruns. No hands-on Play is requested now.
