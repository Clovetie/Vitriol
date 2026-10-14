# M3 route preflight: reuse a measured obstruction, not a guessed one (2026-10-13)

> **Subsequent measured-ray-count preflight:** GarageNavigation now
> skips clearance rays for exact-cost pairs that cannot beat a physically
> verified winner; it still physically checks every potentially winning
> pair. The OLD 13/12-ray example below is the pre-pruning baseline.
> Current analytic center detour is 11/10 rays (without/with prior hit),
> 720/720 exhaustive waypoint parity, 8/8 physical Studio-source parity.
> No Play timing attribution. See
> [`M3-GARAGE-ROUTE-COST-PRUNING.md`](M3-GARAGE-ROUTE-COST-PRUNING.md).


The user asked to keep working while the real `Creature:Think 8.313/1.000 ms` one-off remains unexplained. The existing Garage detour checks an obstructed start→goal ray, then tests six authored exterior nodes from each side. In the selected living-prey and lit garage/station-lure branches, **the exact obstruction has already been physically raycast by that same non-yielding Think**, yet `GarageNavigation:route` cast that initial ray again before its cold fan. The immediately preceding sensory-ray reuse removed a different duplicate: the prey visibility check.

`GarageNavigation:route` now accepts an **optional actual `RaycastResult` from that exact segment**. Only the already-measured selected-prey hit or already-measured light-lure hit is passed by `CreatureService`. With a real `hit.Instance`, route consumes that result and tests the **same existing authored candidate nodes**; with nil/missing hit evidence it performs its original physical start ray. This cannot grant a path from a fabricated boolean, change a visible chase into a hit, turn a solid garage wall transparent, or authorize cover contact. The existing garage-prop/boarded-gate/endpoint distinctions remain in the route. No map/gait change, new ray, cadence, UI/gameplay Instance, public target remote or priority change.

The analytic `tools/vitriol/navigation.luau` now passes **23/23**: a cold detour without prior evidence still costs 13 rays; a physical same-segment hit makes its route fan **12** rays and selects the *same front waypoint*; an invalid `{Instance=nil}` takes all 13; a service-integrated lit-Garage-lure Think costs **one policy ray plus 12 route rays** instead of policy ray + 13. Selected-prey thermal-through-prop continues to route with the real sensed obstruction. The earlier sensing regression is **23/23**. Full quality gate **36/36**, official compiler **61/61**, `git diff --check HEAD` clean.

Before authoring anything, the legacy bridge verified Vitriol place `92448193604950`, **Edit mode**, and exact previous `GarageNavigation`/`CreatureService` Studio Sources and ModuleScript classes. Only those two scripts were guarded-synced; exact final Source/class readback **2/2** (`tools/reports/route-known-hit-sources.json`). A fresh read-only Studio-Source and **actual real-Garage** probe found the user's queryable `Garage_Barrel_2` as the first rear-ray hit; passing that *same* hit produced the original `(-55,-56)` front detour, with no Part mutation (`route-known-hit-live-source.json`, `ok:true`). Static verifier `ok:true` (`route-known-hit-static.json`). The Studio/Edit probe cannot time an active Think; the analytic ray count is not a real Play millisecond measurement.

**Still open:** this removes one repeated obstruction ray only in the identified branches. The unmodified cold detour still has a 12-ray candidate fan; the separate last-known/house reroute call sites are not claimed optimized. Do **not** infer the past 8.313 ms Think overrun was caused or fixed, or that Session/Time overruns were solved. Only active Play can attribute them and verify human fourth-Garage-visit movement, while House_02 exit still lacks its own Play verdict. Budgets and warning thresholds were not raised or suppressed. Save/publish and Git push remain unconfirmed.
