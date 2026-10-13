# M3 Night instinct: clue sweep → bounded patrol (2026-10-13)

> **Latest Play verdict (2026-10-13):** After the newer road-region sync,
> the user reported “Everything works perfectly, it knows when to give up as
> well.” The Night hunt/region-change feel is Play-accepted, but earlier
> cadence overruns are unresolved and full M3 remains incomplete. See
> `docs/M3-REGION-PATROL-SLICE.md`; the pending status below is historical.

> **Newer Play feedback and correction:** user saw the Braid keep moving, but
> said it stays in the same region too long. They chose leaving **after one
> completed local circuit**. `docs/M3-REGION-PATROL-SLICE.md` records the
> guarded-synced road-derived region candidate (**3/3 exact Source**), local
> gate **32/32**, compiler **59/59** and pending fresh Play. The measured
> one-off `Creature:Think 8.313/1.000 ms` and separate
> `Session:Slow 0.204/0.050 ms` overruns remain real and UNRESOLVED.

## User decision and exact scope

The user confirmed House_01 closet egress and asked for roadmap work. They then clarified “it should always be hunting” to mean **Night-only search**, not Day/Dawn predation, and chose **search near the last genuine clue, then bounded patrol** when no clue remains. This is a first instinct-only M3 slice; it is NOT the full learned predator, region-to-region routing, semantic memory, Garage-fourth-visit behavior or AIDebugDump.

## Guarded Edit-mode candidate — fresh Play pending

- `Creature/Brain/InstinctSearch` is a numeric-only, per-Braid policy. An actually sensed survivor or a real emitted noise can supply a clue. Once fresh prey/lure/valid LastKnown/noise stops taking priority, a clue within 32 studs and 25 seconds starts a four-point **10-stud** local sweep. Otherwise it follows four **24-stud** patrol waypoints about its current anchor. Arriving advances the route; no progress for three seconds tries the next direction. The authored foundation bounds clamp targets when present. There is no reading of an unseen player's current root, global player lookup, learned guess, or new scheduler/Path/Instance.
- At most **two** new candidate visibility checks happen on one existing `Creature:Think` call; an existing clear waypoint is reused without re-raycasting. A solid wall or installed furniture invalidates a candidate. If physically enclosed with no safe waypoint, the creature fails closed rather than phasing through cover—“always hunting” is an intention, not permission to teleport through a wall.
- Fresh sensed prey, bell/garage/station lures, bounded last-observed prey, real noise and roof recovery retain priority over search. A clue sweep/patrol never sets `CoverExitIntent` or `CoverPreyX`, initiates chomp, damages furniture or changes the approved planted-foot gait. Day/Dawn withdrawal clears clue and patrol state; the same preauthored Braid starts a fresh hunt the next Night.
- `MonsterConfig.InstinctSearch` provides read runtime bounds (25 s, 32-stud clue reach, 10/24-stud route radii, five-stud arrival, three-second no-progress skip). The previous M3 emitted-noise candidate was synced together with this search slice; see `docs/M3-NOISE-INVESTIGATION-SLICE.md`.

## Evidence and pending Play

- Focused `tools/vitriol/instinct-search.luau` **19/19**: real no-clue Night target and Day/Dawn reset, clue-to-sweep-to-patrol, bounds, safe walls/furniture, max two candidate rays/Think, waypoint caching, no-progress fallback, no hidden prey GPS and no runtime Instances. Updated existing `senses.luau` **20/20** and HouseCover **63/63** reflect a low-priority patrol rather than an idle Braid. Garage navigation **19/19**, HouseAccess **37/37**, full gate **31/31**, official compiler **59/59**, `git diff --check HEAD` clean.
- **Guarded Edit sync complete, human Play NOT yet accepted.** User supplied a legacy bridge connection. Health showed Studio connected; ping confirmed Vitriol place ID `92448193604950` and a separate Edit-mode probe returned `false` for `RunService:IsRunning()`. Read-only static and furniture verifiers passed before write. A source guard matched both `CreatureCore` and `CreatureService` against the prior House_01 egress readback and matched `MonsterConfig` and `NoiseField` exactly against their local **pre-M3** versions, so no unknown Studio-only edits were overwritten. `jobs/author_instinct_brain_folder_vitriol.lua` created **1** Folder, idempotent rerun created **0/reused 1**, and an inspect confirmed `Folder`. All **five** affected/new ModuleScripts were guarded-synced in Edit mode, class-checked by the bridge and **5/5 exact current Source readbacks** passed (`tools/reports/m3-sources.json`). Fresh Edit-mode compilation of exact Studio `InstinctSearch.Source` exercised the **actual authored foundation** bounds `[-292,292]` and verified no-clue patrol, recent clue sweep, covered candidate rejection and map-edge clamping (`tools/reports/m3-live-source-probe.json`, `ok:true`). The post-sync static verifier again returned `ok:true` (7 remotes, 211 Braid parts, 24 blood Parts). A second **read-only** fresh-source geometry probe found a clear first 24-stud patrol segment at four real locations: road `(0,0)→(24,0)`, garage bay `(-90,-56)→(-66,-56)`, House_01 inside `(-91,77)→(-67,77)` and House_02 inside `(101,67)→(125,67)` (`tools/reports/m3-patrol-geometry.json`, `ok:true`). This checks those initial rays only, not a whole Night path or cover-installed exit. No Night Play or measured normal cadence budget exists for search, and Studio save/publish and Git push remain unconfirmed. House_01 entry/closet break/exit remain a separate, already Play-confirmed milestone.
- **Next human Play:** Stop/restart Play so Studio loads newly synced Sources rather than an Edit-mode `require()` cache. With all survivors out of sight and no active lure, watch the Night Braid check near a previously sensed location and then keep moving between reachable local patrol points. Confirm Day/Dawn withdrawal, immediate fresh prey/decoy reprioritization, no through-wall/furniture motion or hidden-player GPS, and real `Creature:Think` frame time against its budget. If all directions are physically blocked, report the first stall/obstacle rather than changing the approved gait. Do not call M3 complete: this still lacks region-to-region search, fourth-Garage-visit learning and AIDebugDump.
