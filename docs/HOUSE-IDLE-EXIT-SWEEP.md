# House idle exit: bounded circular ray sweep (2026-10-13)

> **Subsequent guarded sync:** The newer HouseAccess, CreatureCore and
> Garage diagnostic Modules are now in Vitriol **Edit**, exact Source/class
> **4/4**. Read-only actual-Studio-Source probe passed; **not a Play exit
> verdict or confirmed Save to Roblox**. See
> [`STUDIO-EDIT-SYNC-AND-SOURCE-BACKUP-2026-10-13.md`](STUDIO-EDIT-SYNC-AND-SOURCE-BACKUP-2026-10-13.md).

> **Prior offline frame follow-up:** A low target did not actually lower
> the approved high stance on planted feet. A temporary doorway-only
> supported crouch now passes a Lua-only core/frame replay (House **63/63**),
> still workspace-only; no Studio sync or Play verdict. See
> [`HOUSE-EXIT-FOOT-SUPPORTED-LOWERING.md`](HOUSE-EXIT-FOOT-SUPPORTED-LOWERING.md).

> **Subsequent offline corrections:** This document describes the previously
> Studio-synced version. A later workspace-only HouseAccess first required
> actual descent before any outward ray, then extended doorway/furniture
> checks across each near/far core-radius band so angled rays cannot graze
> the original pier or table corners. Current House fixture **58/58**, gate
> **36/36**, compiler **61/61**. No bridge credentials/Studio sync or live
> Play verdict for these follow-ups. See
> [`HOUSE-EXIT-LOWER-BEFORE-RAY.md`](HOUSE-EXIT-LOWER-BEFORE-RAY.md) and
> [`HOUSE-EXIT-CORNER-CLEARANCE.md`](HOUSE-EXIT-CORNER-CLEARANCE.md).

The user Play-reported that after entering House_01, the Braid still could not leave. Their new contextual contact line was:

`Braid dislodged House_01 Closet; paid Day move required core(-74.4,9.8,76.1) nav(-87.0,78.0) reason=genuinely-sensed-prey feet=4`

At **the break instant**, the core was east/outside of the original House_01 door plane X=`-79`, pursuing genuinely sensed prey inside. The user separately saw it fail to leave **later**. The line does **not** prove its later indoor position, target or blocker. When no fresh chase/distraction/clue remains, the accepted Night regional policy completes one local patrol circuit, then attempts a road region; a thin road ray near the east pier can have only 0.38 studs of clearance—less than the Braid's 1.5-stud core radius. That sample is a physical route risk, **not attribution of this particular Play failure**.

The user requested that when enclosed and not chasing, the Braid cast around itself in a circle to find an exit, then leave through it. Implemented a **scoped, time-sliced circular ground ray fan** in `HouseAccess:sweepExit`, called by `CreatureService:_search` ONLY after no genuinely sensed prey, active higher-priority lure, unexpired last-observed target, real local noise or recent search clue wins, and after **one completed local patrol circuit** has reached `transit`. A grounded core must be inside one of the TWO actual authored houses. No unsensed player's location is read. The headless service regression verifies a no-prey transit branch; no M3/Q-learning or public remote change.

- Test up to **16 evenly spaced spokes around the core**, **at most one NEW physical ray per 6 Hz Think**. Keep a verified exit goal without reraycasting every tick. A stall after three seconds advances to the next spoke; new higher-priority movement invalidates the held goal. There is no extra scheduler, periodic hot-loop ray fan or fixed-time regional abandonment.
- The numeric exit and inner-stage goals also lower an elevated indoor core to the existing under-lintel entry height **before** attempting the door, while the roof-level escape path remains separate. A ray may lead outside only if it goes through the real **east main-door opening**, leaves the house, and has the Braid's actual core-radius clearance from both solid piers and every **currently installed original table/closet** in that house. The original one-stud space remains genuine for a player, but is not misrepresented as Braid-sized. The tested segment must also be physically ray-clear. No windows, solid wall, roof, cover tunneling, manual Night release or furniture resize.
- If all direct spokes are occluded from an interior corner, test one inner-door **staging lane** per later Think (the two original table/closet lanes) and resweep only after physically arriving. If every option is blocked, return to bounded local hunt and try again after another completed circuit. During Day/Dawn the Braid still withdraws. Its approved foot-led locomotion and chase/chomp speeds are untouched; this merely chooses numeric safe waypoints.

**Evidence:** Headless HouseAccess+real-service fixture **45/45**, including one initial spoke on the open-closet lane, held-waypoint zero extra rays, both placed pieces fail-closed, near-pier staging, fresh ray after moving, **pre-lintel lowering and roof exclusion**, ≤1 new spoke/Think and no runtime Instances. Cover **64/64**, Garage habit **63/63**, search **19/19**, full quality gate **36/36**, official Luau compiler **61/61**, `git diff --check HEAD` clean. The legacy bridge was used **in Edit only**, first guarding actual prior full `HouseAccess` and `CreatureService` Studio Sources/classes, then writing ONLY those two ModuleScripts. A subsequent guarded **HouseAccess-only** sync added pre-lintel lowering; final changed HouseAccess and unchanged CreatureService Source/class **2/2 exact** (`tools/reports/house-exit-sweep-final-sources.json`). Local candidate and final freshly compiled **actual Studio Source** were independently probed on the user's unchanged House_01 map: opening Z=`64..80`, open original closet lane yielded outside `(-67,77)` through a real physical ray, both placed pieces denied a body-width route, and a near-pier `(−84,65)` origin staged inside at `(−87,77)` before resweeping. Real furniture was NOT moved in Edit (`house-exit-sweep-local-edit.json`, `house-exit-sweep-live-source.json`, both `ok:true`). Static verifier `ok:true` (`house-exit-sweep-static.json`). Edit probes are **not** live Play movement or timing.

**New concurrent Play warnings, all still open:** `Session:Slow 0.209/0.050 ms` occurred on `begin-round` while Running/Day; `DayPrep:Pulse` reported `0.418`, `0.405`, `0.223` ms against `0.050`; `Time:Publish 0.395/0.050 ms` reported attributes `0.235` ms vs remote `0.022` ms at Night sample 121. These do not measure the new exit fan and are not dismissed or solved by it. The repeated `[Arena] poll failed: Http requests can only be executed by game server` lines were printed by a **client-side Arena poll**, separate from the Braid and these server cadence slots; the Studio bridge does **not** support live Play. No budget/warning threshold was raised.

**Next evidence:** restart Play to load guarded Edit-mode Sources. After a genuine House_01 entry and contact/break, let prey become unavailable and watch whether the Braid completes its local search, chooses the house-exit sweep, reaches the original front door and physically crosses outside. If it does not, provide the first **new** post-break Output stall/warning plus a screenshot/short clip of where the body stops. The newly synced numeric goal still needs a human feet-on-ground verdict; House_02, fourth-Garage-visit and all live budget acceptance remain separate. Save/publish and Git push are unconfirmed.
