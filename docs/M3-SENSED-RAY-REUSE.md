# M3 Think-cost preflight: reuse the genuine prey sensor ray (2026-10-13)

> **Later route-cost work:** The 13-ray Garage detour and navigation
> **20/20** figures below are historical for this slice. The current
> exact-cost lazy route passes **25/25**, with center detour 11 rays or
> 10 with a known obstruction, 720/720 original-waypoint parity, and
> 8/8 physical Studio-Source parity. No active Play timing conclusion.
> See [`M3-GARAGE-ROUTE-COST-PRUNING.md`](M3-GARAGE-ROUTE-COST-PRUNING.md).

> **Subsequent bounded reuse:** An actual selected-prey sensor obstruction
> (or lit-light-lure hit) now also replaces GarageNavigation's duplicate
> **initial detour ray**. Its 12 authored-node tests and fail-closed missing
> evidence remain. Navigation **23/23**, full gate **36/36**; guarded two
> Studio Sources and real-barrel/source probe passed. No Play timing
> attribution. See [`M3-ROUTE-HIT-REUSE.md`](M3-ROUTE-HIT-REUSE.md).


The user asked to keep working while the real one-off `Creature:Think 8.313/1.000 ms` overrun remains open. A static path audit found that, on a **sensed living prey** Think, `_nearestTarget` already casts one horizontal clearance ray to the selected root, but the immediate chase branch used to cast that **identical** core→root segment again before making its visible-vs-thermal/route decision. This is redundant engine work even when the predator is chasing unobstructed prey.

`_nearestTarget` now returns its already-computed **clear/blocked** boolean alongside the already-sensed root/player/distance. Within the same non-yielding Think, the chase reuses that value: clear prey stays visible, close body heat behind a nonstructural prop remains **blocked** for direct contact, and building walls still prevent acquisition. For an injected/older sensor that does not return the fourth value, the branch takes its **original** clearance ray; absence of a value never grants visibility. The change does not read any unsensed player's position or make an interception prediction. It does **not** change the user's solid map, eye-less range/thermal rules, lure priority, route geometry, accepted chase pace/gait, Night regional hunt, House_01 exit, house cover or fourth-Garage-visit habit. At most **one redundant ray is removed per selected sensed-prey Think**; the four-player sensory candidate scan, cold navigation pathfinding and other safety rays are untouched.

### What was and was not measured

- `tools/vitriol/senses.luau` now **23/23**: in the real headless `CreatureService:think` branch, a clear exposed target uses **one** sensor ray, not two; thermal-through-prop also reuses its blocked ray without falsely calling it visible. A second-player test proves that closer blocked thermal prey never inherits a farther clear player’s visibility flag. Wall-occluded and distant-hidden prey tests still pass. Garage navigation **20/20** records that its separate **cold garage detour fan costs 13 rays** in the analytic fixture; a cached detour is already cheaper. This is a remaining potential Think-cost contributor, **not** an attribution of the user's 8.313 ms warning. Garage habit **62/62**, shadow **21/21**, and the earlier exceptional-cadence context **7/7** still pass. Full gate **36/36**, official Luau compiler **61/61**, `git diff --check HEAD` clean.
- Guarded Vitriol place `92448193604950` in **Edit mode**. Before writing **only** `CreatureService`, its previous full Studio Source and ModuleScript class matched `tools/reports/m3-garage-flank-sources.json` exactly; final Source/class readback exact (`sensed-ray-reuse-source.json`). A read-only fresh-Studio-Source compile/real-door probe verified the actual Garage east-door ground-level ray is clear and the Source contains the fail-closed missing-result fallback (`sensed-ray-reuse-live-source.json`, `ok:true`). Post-sync static verifier `ok:true` (`sensed-ray-reuse-static.json`). The Edit probe did **not** execute live sensing; the headless integrated test proves the return-value reuse logic.

**Still open:** real steady-state or worst-case `Creature:Think` time in human Play, the distinct `Session:Slow 0.204/0.050 ms` and `Time:Publish 0.389/0.050 ms` one-offs, fourth-Garage-visit human movement and House_02 footed exit. Do not present this one-ray reduction as a measured budget fix, raise shares, suppress warnings, or change the accepted planted-foot body to chase a number. Save/publish and Git push remain unconfirmed.
