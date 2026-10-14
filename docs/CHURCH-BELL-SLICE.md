# One-use church-bell decoy — Play-accepted (2026-10-12)

> **Later owner revision (2026-10-13):** After a guarded two-Module
> Edit sync and a human-verified Save to Roblox with Notes, the owner
> explicitly approved the ALREADY-AUTHORED lever at `(119,2.5,-199)`
> rather than the former Z=-210 coordinate recorded below. No Studio
> geometry moved. The fresh read-only verifier and full audit pass **10/10**
> with 61 Sources/classes checked; see
> [`CHURCH-LEVER-CURRENT-POSITION-APPROVED-2026-10-13.md`](CHURCH-LEVER-CURRENT-POSITION-APPROVED-2026-10-13.md).

The user selected **one more daytime preparation choice** after confirming the garage gate now breaches in Play. They supplied bell audio asset ID `130139735590457` and said the clip already rings three times. The server plays that clip **once**, with three visible light pulses; it must not call `Sound:Play()` three times. **Fresh Play verdict:** “The bell is audible and it flashes properly, everything works perfectly.” Treat the visible/audio bell loop as accepted, preserving its behavior. The user did not separately report precise pulse counts/timing, the generator fallback, Dawn reset, or measured frame time; headless coverage is not a substitute for those observations.

## Authored content

Under `Workspace.Map.Interactions`:

- `Church_BellLever` — anchored, noncolliding Part at `(119, 2.5, -210)` by the tower base; authored `PrimeBell` ProximityPrompt (two-second hold, ten-stud reach). The user later confirmed **keep this relocated lever position**; author/verifier jobs now use it rather than restoring the earlier `(119, 2.5, -136)` entrance blockout.
- `Church_Bell` — anchored, noncolliding, nonqueryable bronze cylinder at `(119, 51.4, -205)` above the existing church tower platform; authored `BellPulse` PointLight and `BellRing` Sound. SoundId is the user's `rbxassetid://130139735590457`, not an invented ID. The service only changes properties of these existing objects.

`jobs/author_church_bell_vitriol.lua` refuses Play, wrong place, changed Map version/tower footprint or duplicate/wrong-class objects. First guarded Edit-mode run created **five** Instances; the second created **zero** and reused **five**. The read-only `jobs/verify_church_bell_vitriol.lua` passed (`ok:true`, five authored objects, no defects). Both editor jobs compile with official Luau. No game/UI Instance is created during Play.

## One-night rule

During Dawn/Day a living player near the lever can prime it **once per Night**. The priming is world state, not an inventory Tool; death/disconnect cannot grant another prime. At Night start, the existing DayPrep cadence waits about **three seconds**, plays the user-provided three-strike clip **one time**, pulses the bell light three times during the first three seconds, and emits one server-owned AIR/VIBRATION signal. For **twelve seconds**, the bell lever's accessible tower-base position becomes the Braid's distant lure. When a living player is within **30 studs** of the Braid, that player wins immediately; the approved close chase pace and gait code are unchanged. If the accepted garage generator was also powered, its original **70-stud** distant lure resumes after the bell window. At Dawn the bell and generator reset for the next cycle. There is no continuous bell loop, permanent safe zone, new PathfindingService Path, crafting grant or new custom UI.

The light pulse is a blockout visual cue, not bespoke bell animation. The supplied audio asset **was audible in the user's fresh Play session**; asset access for other experiences or users is not established by that test. The current Studio-only accelerated phases (5/10/10/30 seconds) were user-approved for tests and **must remain until testing finishes**; local main stays at 45/210/60/240.

## Evidence and Play checklist

- Local full gate **18/18**; church-bell scenario **19/19**, existing day-prep **14/14**, garage barricade **23/23**, navigation **16/16**, official game-script compiler **50/50**, no runtime constructors.
- Focused tests cover server distance/life/phase validation, two-player contention, prime surviving inventory loss, coexistence with the garage generator, delayed single Sound:Play, three pulses, distant lure versus 30-stud living prey, return to generator, Dawn reset and no runtime-created Instances.
- Bridge checked Vitriol place `92448193604950` in Edit mode, authored/verified the five objects, guarded-synced `DayPrepService` and `CreatureService`, and read back **2/2** ModuleScript classes and exact sources. A fresh-source, read-only Studio probe bound the new service to the authored lever/bell/light and user-provided SoundId. The full read-only audit ran **seven** verifiers and checked all **50** script classes, but intentionally **failed source parity on Studio-only `DayNightConfig`**; do not claim full 50/50 parity or overwrite the user's fast-test timing.

The user has now **Play-confirmed audible bell audio and visible flashes** and reported that the slice works perfectly. No need to change the accepted presentation. When convenient, separately observe the precise pulse count and one-time Night activation, distant diversion versus close-player priority, garage-generator lure resumption after roughly 12 seconds, and Dawn reset. Capture server/client Output and `DayPrep:Pulse` frame timing if a regression appears. Save/publish and Git push remain unconfirmed.
