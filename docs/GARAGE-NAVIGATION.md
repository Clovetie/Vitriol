# Braid navigation around the garage — synced in Studio Edit mode

**Play finding (2026-10-12):** The player stood outside behind the garage; the Braid went inside and repeatedly pushed into its rear wall. After the fix, the user confirmed **it no longer gets stuck** in Play. The separate boarded-gate breach then failed and has a new synced, Play-pending fix in `docs/BARRICADE-SLICE.md`.

## Bounded fix

`Creature/GarageNavigation.luau` reads the existing authored `Map/Structures/Millers_Garage/Floor` and `RearWall`. It computes a six-node ring in ordinary Lua coordinates: open east/front entry, north/south corners, and the west/rear side. At Think cadence a horizontal ray at wall height checks whether an authored garage wall **or a named garage interior prop** blocks the direct target. If so, `CreatureService` selects a visible perimeter waypoint; once direct sight clears, immediate prey chase resumes. The existing planted-foot gait, tendril control, speed, charge, and night timing are unchanged. Gameplay creates no `PathfindingService` Path, UI, or game Instance; no new map objects were authored.

The interior-prop case is essential: a real Edit-mode ray from the garage center toward a player behind it hits `Workspace.Map.Interiors.Garage_Barrel_2` **before** `RearWall`. The first synced candidate only recognized parts under the structural garage model; a real-geometry probe exposed this flaw, and it was corrected and resynced. If no waypoint is visible, the Braid clears its target instead of blindly pressing a garage wall. Dynamic preauthored defenses remain governed by existing crossing/press/breach authority. Ground-level wall visibility also gates chomp preparation and charge contact; high unreachable prey keeps the previously approved response. Route work is cached for half a second while the waypoint is distant. **No Studio frame-time gain has been measured.**

This is **garage-specific routing, not town-wide pathfinding**. Other structures, trees, arbitrary clutter, vertical routes, and actual physical traversal by the anchored procedural Braid still need Play verification. Do not claim the monster can navigate the entire map.

## Evidence (2026-10-12)

- Local `node tools/vitriol-session-test.js --tests tools/vitriol/navigation.luau`: **16/16**, including the first-hit garage barrel, existing boarded gate, wall-side chomp refusal and the real `CreatureService:think` target selection in a headless fixture.
- Full local gate: **17/17**; official compiler **50/50**, no-runtime-constructor check **50/50**.
- Bridge verified place ID `92448193604950` and Edit mode, then guarded-synced `ServerStorage/Vitriol/Creature/GarageNavigation` and `ServerStorage/Vitriol/Services/CreatureService`. The navigation module was resynced after the garage-barrel correction.
- At the time of the navigation sync, read-only `python tools/vitriol-studio-audit.py` passed **six verifiers, 50/50 script classes and 50/50 sources, zero drift**. Since then the user intentionally shortened *Studio* `DayNightConfig` for Play tests; the current full audit fails on that one known source difference (see `docs/BARRICADE-SLICE.md`). Credentials remained in process environment.
- Read-only *real map* probe compiled the freshly synced module Source to avoid Edit-mode `require()` cache: a ray from `(-90,-56)` toward `(-145,-56)` first hit `Garage_Barrel_2`, yet the route targets were `(-55,-56)` (open front) → `(-55,-86)` (north corner) → `(-125,-86)` (rear corner) → direct `(-145,-56)`.

## Remaining Play checklist

The user confirmed the behind-garage chase no longer gets stuck and that the separately repaired **boarded gate breaks** in Play. Exact gate timing, inside exit and post-breach chase remain to be observed individually. Also check an unobstructed outdoor chase (approved pace), a player close to the wall (no through-wall chomp), and return to Dawn. Capture client/server Output and `Creature:Think`/`Creature:Frame` timings. Save/publish and Git push remain unconfirmed.
