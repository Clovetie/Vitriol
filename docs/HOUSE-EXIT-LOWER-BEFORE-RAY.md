# House exit: lower inside before casting an outward route (offline follow-up, 2026-10-13)

> **Subsequent bridge result:** Four pending House/Garage Modules were
> guarded-synced to Vitriol **Edit**, Source/class **4/4 exact**. Read-only
> Studio-Source House probe passed; **Save to Roblox and live Play remain
> unconfirmed**. See
> [`STUDIO-EDIT-SYNC-AND-SOURCE-BACKUP-2026-10-13.md`](STUDIO-EDIT-SYNC-AND-SOURCE-BACKUP-2026-10-13.md).

> **Prior offline movement correction:** The down-only numeric command
> below did NOT actually lower a supported high core in the new frame
> replay. A scoped supported crouch now does so without normal chase/chomp
> changes (House **63/63**), still unsynced and untested in Play. See
> [`HOUSE-EXIT-FOOT-SUPPORTED-LOWERING.md`](HOUSE-EXIT-FOOT-SUPPORTED-LOWERING.md).

> **Subsequent offline corner-clearance follow-up:** A door-plane or original
> furniture center-plane check was not sufficient for an angled radius-1.5
> core. Whole near/far X-band guards are now workspace-only; House **58/58**,
> gate **36/36**, compiler **61/61**. This report's **51/51** describes the
> earlier lowering-only candidate, not current complete local evidence. No
> Studio sync or Play verdict. See
> [`HOUSE-EXIT-CORNER-CLEARANCE.md`](HOUSE-EXIT-CORNER-CLEARANCE.md).

The user cannot run Play now. I found a gap in the earlier exit preflight: it accepted an outward numeric goal for a grounded indoor core at Y=14, while only setting that far-away target's Y below the lintel. In the foot-led locomotion, lowering and horizontal hauling are concurrent; a low target **does not establish that the core has already lowered before it reaches the doorway**. The previous synthetic/Studio-Edit probes proved the target Y, not the order of the body's motions. This gap does **not** establish the cause of the earlier live House_01 no-exit report.

`HouseAccess:sweepExit` now returns the creature's **own current X/Z** and an under-lintel Y with reason `physical-house-exit-lowering` when the grounded indoor core is elevated. It spends **zero candidate rays** while that Y has not been reached. Once the actual core is sufficiently low, the pre-existing bounded circular door sweep starts or resumes, still with at most one new physical candidate ray per 6 Hz Think. The existing three-second no-progress rule releases an unlowerable core back to a local patrol circuit rather than leaving it indefinitely committed to a vertical waypoint. Roof-level traversal still uses its separate escape path; a live prey, real clue or lure can interrupt the idle sweep. No map geometry, furniture, runtime Instance, hidden-player lookup, locomotion mechanics, cadence share or client disclosure changed. A stationary numeric command does not by itself prove the planted feet can successfully lower the body in Play.

**Offline checks:** `tools/vitriol/house-access.luau` **51/51** now covers House_01 and House_02 high-core downward-only commands, zero rays before lowering, a progressing descent, a stalled descent, an outward physical ray only after lowering, and the actual `CreatureService._search` branch. It retains tests for the installed original table/closet, blocked lanes, one-ray-per-Think staging, held-route zero-ray reuse, roof exclusion and no runtime Instances. Full quality gate **36/36**, official Luau compiler **61/61**, `git diff --check HEAD` clean. `tools/probe-house-exit-sweep-local.py` and `jobs/probe_house_exit_sweep_source_vitriol.lua` were updated to assert the new **order** on a future real-geometry Edit probe; **neither was run against Studio in this follow-up**.

**Deployment guard, not deployment:** Legacy bridge credentials are absent here. This correction to `HouseAccess` and the previous unsynced Garage diagnostic in `CreatureService` + `Bootstrap` therefore remain **workspace-only**. The new `tools/sync-pending-house-garage.py --offline` now checks four prior exact full-source readbacks after the later core change and prints only hashes; it ran successfully. With bridge access later, `--check` is read-only, and an explicit `--apply` first guards Vitriol place `92448193604950`, Edit mode, all four *full* old-or-already-new Sources and ModuleScript classes, then writes only pending exact Modules with post-write and final readback. It must abort on unrelated Studio edits; never use a broad sync or Play snapshots. The script has **not** contacted Studio or been exercised against a live bridge here.

**Open:** Human House_01/House_02 exit behavior, actual lower/door foot motion, fourth-Garage-visit choice, and measured live cadence overruns. House_01 had an earlier successful exit and later failures; neither observation is erased. No hands-on Play requested now. Save/publish and Git push unconfirmed.
