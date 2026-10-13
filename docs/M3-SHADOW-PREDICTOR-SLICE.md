# M3 location-only shadow predictor — Edit synced; Play/cadence pending (2026-10-13)

> **Newer diagnostic correction:** After a player is hidden, even a trained
> location row is only historical evidence: `trusted`, `predictability` and
> `possibleNextClasses` are withheld until genuinely re-sensed; `lastSampleAt`
> records when `lastClass` was sampled. Shadow **21/21**, Garage **47/47**,
> gate **35/35**, compiler **61/61**. Guarded shadow-only Studio sync and
> actual Studio-Source hidden-player test passed. See
> [`M3-EXPLAINABILITY-CORRIDOR.md`](M3-EXPLAINABILITY-CORRIDOR.md).


> **Follow-up:** The separate Garage witness now ALSO breaks partial entry
> evidence on an unseen Think or roof/high observation. Its existing learned
> visits survive; the shadow predictor remains observation-only. Garage
> **46/46**, shadow **19/19**, gate **35/35**, compiler **61/61**. See
> [`M3-GARAGE-WITNESS-CONTINUITY.md`](M3-GARAGE-WITNESS-CONTINUITY.md).


The user asked to **keep working** before another Play request. A read-only Edit survey of `Workspace.Map.Zones` found ten **existing** `Vitriol_Zone`-tagged Parts, each with an authored `ZoneClass`: Road, Woods ×2, Garage, House ×2, Open ×2, Water and a raised Roof. Their axes are unrotated, their dimensions/height are readable, and the corresponding eight location names are already in `MonsterConfig.Prediction.LocationClasses`. No Part, road, building, furniture, tag or attribute was changed. These are *broad semantic districts*: `Zone_Garage` does **not** prove a survivor entered the actual garage; that remains the separate physical `GarageHabit` witness rule. `Zone_House_02`'s authored display name is Church Crossroads; its semantic class is simply House. No un-authored basement region is invented.

Added `Brain/ShadowPredictor` using existing pure `Lib/MarkovPredictor` as an **observation-only, per-player, eight-location-class** transition matrix. During Night, the service passes only the nearest **already genuinely sensed living** player's coordinates into it; the usual limited, ray-checked eye-less sensing gate is unchanged. Classification uses the cached bounds of *tagged*, axis-aligned authored ZoneClass Parts; a smaller volume takes precedence if they overlap. Positions outside these bounds and rotated/unlabelled/untagged zones fail closed. This does **not** derive the six posture states, all 48 combined states, an interior check, or any physical target. A transition requires successive actually sensed classifications; even one Think with no sensed player breaks continuity, as does an out-of-zone sample. The service samples regions at most once per actual second, does no new raycast or cadence work item, and clears a departing player's model. The model has constant-size state space; no DataStore, runtime Instance, Q-learning or new client remote.

`CreatureService:aiDump().shadowPrediction` is **server-only** and marks `mode="observation-only"`, `steers=false`, `postureObserved=false`, authored-zone count, witnessed transition count, last sampled class, whether the player is *currently sensed*, and (only after **12 transitions from that same class**) a per-class distribution and predictability. `MarkovPredictor:predict` allocates only when this diagnostic is explicitly requested, **not in Think**. No guessed class is converted to a coordinate or selected as a hunting goal. Sensed prey, authored bell/light lure, bounded last-known clue/noise, recently searched clue, witnessed Garage leg and patrol retain their original priorities. `RF_DebugQuery` still does not expose secret locations. The human fourth-visit and `AIDebugDump` exit is **not complete**; this is a narrower truthful diagnostic foundation.

## Evidence / remaining risk

- `tools/vitriol/shadow-predictor.luau`: **19/19** including actual service-only sensing, hidden movement/reacquisition exclusion, authored geometry/tag/height, 1 Hz sampling, per-row trust gate, disconnect cleanup, no instances. Existing Garage regression **41/41**; full quality gate **35/35**, official compiler **61/61**, `git diff --check HEAD` clean.
- Guarded Vitriol place `92448193604950` in **Edit mode**. Before writing, `CreatureService.Source` matched the prior exact readback; `MarkovPredictor` and `MonsterConfig` matched local Source ignoring *only* Studio's missing terminal newline. `Brain.ShadowPredictor` was absent and its parent was a Folder. Only the new authored ModuleScript and `CreatureService` were written. Both final Sources and classes read back **2/2 exact** (`tools/reports/m3-shadow-final-sources.json`). Studio-Source read-only probe against all ten actual authored zones returned `ok:true` with Garage/Road/Roof geometry, one witnessed transition and no crossing through unseen movement (`m3-shadow-live-source.json`). Post-sync static verifier `ok:true` (`m3-shadow-static.json`). This probe does not execute real Play AI.
- **Still open:** the user's human fourth-Garage-visit/normal-schedule Play verdict and actual cadence profiling. Earlier *measured* one-offs `Time:Publish 0.389/0.050 ms`, `Creature:Think 8.313/1.000 ms`, and `Session:Slow 0.204/0.050 ms` remain unattributed. No budget share or warning threshold changed. Save/publish and Git push are unconfirmed. Do not assert full M3 acceptance or enable M4/Q-learning. Preserve the already Play-accepted Night regional hunt/give-up, House_01 exit, both-house cover, accepted Braid gait, sensing and security boundaries.
