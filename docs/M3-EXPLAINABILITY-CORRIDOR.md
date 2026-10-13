# M3 honest shadow diagnostics + physical Garage witness corridor (2026-10-13)

> **Subsequent route correction:** Read-only geometry showed the existing
> front-only habit gave up west/north/south of the Garage. The new safe
> exterior-corner legs have passed Studio-Source/real-wall probing. Garage
> **62/62**, shadow **21/21**, gate **35/35**, compiler **61/61**. See
> [`M3-GARAGE-FLANK-ROUTE.md`](M3-GARAGE-FLANK-ROUTE.md). The 43-ray
> entrance-witness preflight below remains accurate and was rerun.


The user asked to keep working before another Play request. Two pre-Play gaps were closed without changing the Braid's hunting decisions or adding an in-game sensor.

## 1. A trained row is not a hidden survivor's current location

The previous server-only shadow dump could display a high-confidence `possibleNextClasses` distribution after a player was **no longer sensed**, provided its last-sampled class had 12+ historical transitions. The counts were real, but the class might be stale; presenting it as a current guess could mislead a designer and tempt a future route to follow hidden-player history as live GPS. `ShadowPredictor:dump()` now retains `lastClass` and `observationsFromLastClass` explicitly as historical evidence, adds `lastSampleAt`, and **withholds `trusted`, `predictability` and `possibleNextClasses` while the player is unseen**. On a new genuine sighting, trained statistics become readable again; neither loss nor reacquisition invents a transition. No probabilities are computed on the Think cadence; they remain only on an intentional server-only `aiDump()` request. No steering, posture inference, client remote or data persistence was added.

Focused shadow tests **21/21** include a fully trained model becoming hidden and subsequently sensed again; a freshly compiled actual Studio Source probe over the ten authored semantic zones likewise withheld a trained hidden player's guesses (`tools/reports/m3-shadow-freshness-live-source.json`, `ok:true`). A guarded Vitriol/Edit sync checked the old shadow module, Garage habit and Creature service Sources against their respective prior exact readbacks before writing **only** `ShadowPredictor`; final new Source and unchanged dependencies/class readback **3/3 exact** (`tools/reports/m3-shadow-freshness-sources.json`). Post-sync static verifier `ok:true`.

## 2. A walk through the existing Garage door, not fixture teleports

The earlier headless Garage fixture jumped from the authored exterior approach `(-55,-56)` directly to the center `(-90,-56)` between Think calls. It tested outside/inside semantics but not the *intermediate threshold*. The revised service-integrated fixture walks each visit through nine short observed points along the existing east-door corridor, exits visibly between visits, checks there is no count at X=-63, one count exactly at X=-64 (inside the inset floor footprint), and no repeated-inside inflation. It still asserts fresh prey priority and the fourth-visit front→interior investigation. Focused Garage suite **47/47**; **no gameplay script changed for this test**.

A new **read-only Edit-mode**, freshly compiled actual-Studio-Source probe (`jobs/probe_garage_witness_corridor_vitriol.lua`) used the original user's Garage and one preauthored Braid exclusion to confirm every one of the 43 sampled corridor rays from the entrance to three walking/exit routes was unobstructed at the ground-level sensor height. Three numeric, grounded, ray-qualified witness walks counted exactly three entries, then selected the authored front and physically checked interior leg (`tools/reports/m3-garage-witness-corridor.json`, `ok:true`, front `(-55,-56)`, interior `(-90,-56)`). Those **43 rays are an offline Edit probe**, not 43 new runtime rays or proof the live Braid sees every sample. A real player, Braid motion, cover, scheduling and frame cost still require human Play.

Full quality gate **35/35**, official compiler **61/61**, `git diff --check HEAD` clean. Human fourth-Garage-visit/AIDebugDump acceptance and normal cadence remain open. Prior single real overruns `Creature:Think 8.313/1.000 ms`, `Session:Slow 0.204/0.050 ms`, `Time:Publish 0.389/0.050 ms` remain unassigned; none was suppressed or given a higher budget. Preserve the Play-accepted Night hunt/give-up, House_01 exit, two-house cover, approved planted-foot gait and sensory/security rules. Save/publish and Git push unconfirmed.
