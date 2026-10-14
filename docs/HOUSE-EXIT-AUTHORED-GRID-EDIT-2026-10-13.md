# Both authored houses: bounded exit-grid Edit preflight — 2026-10-13

**Scope:** The owner confirmed the post-sync Save to Roblox with Notes and approved the church lever's *already authored* Z=-199 position. This separate House check used the installed Studio/Edit `HouseAccess.Source` and real original floor, door/pier, porch, furniture-part and target-marker geometry. It was strictly **read-only**: `jobs/probe_house_exit_grid_edit_vitriol.lua` guards the exact Vitriol place and Edit mode; its temporary `Placed` flags live only in Lua test tables. It creates or moves no Instance and does not call the bridge during Play. Full result: `tools/reports/house-exit-grid-edit-after-approval.json`.

For **each** house, the probe sampled 15 grounded, Y=8 starting centers on a 3×5 indoor grid (X center ±12 and Z center ±12/±6/0). At each seed it advanced the actual bounded `sweepExit` decision over consecutive synthetic Think calls, using the installed physical GarageNavigation ray check, core radius 1.5 and four *hypothetical* original-furniture states. It checked **no more than one new navigation candidate ray per synthetic Think**. If a safe indoor staging waypoint was offered, the probe re-evaluated from an **idealized arrival** at that already-tested stage; it did not animate a body there.

| Hypothetical original cover | House_01 (15 seeds) | House_02 (15 seeds) |
|---|---:|---:|
| Neither piece placed | 15 direct exit rays | 15 direct exit rays |
| Table placed, closet dislodged | 4 direct; 11 indoor stage → exit ray | 4 direct; 11 indoor stage → exit ray |
| Closet placed, table dislodged | 15 safely blocked | 15 safely blocked |
| Both placed | 15 safely blocked | 15 safely blocked |

**All 120/120 cases** matched this fail-closed authored-map profile. The sampled decisions used 82 new physical navigation rays in total; no individual synthetic Think spent more than one. A blocked doorway is **not** treated as a reason to phase through installed furniture; real contact/dislodgement remains a separate requirement. The table-only stage results show that the *ray policy* has a tested exit after an idealized arrival in the open closet lane; they do **not** demonstrate that the planted-foot Braid reaches that stage or crosses the half-stud Floor→Porch gap in Play.

This preflight does **not** measure real frame cost, multiple Think timing under animation, actual cover movement or collisions, prey/chomp priority, or a human House_02 egress verdict. One earlier House_01 exit was seen in Play; later House_01 failures were also reported and remain unresolved until new Play evidence. The bridge cannot capture live Play, and none was requested. No game Source changed, no Studio write/save/publish occurred during this check. The owner-verified post-sync cloud checkpoint remains the last reported saved place state.
