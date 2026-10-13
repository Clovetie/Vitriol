# M3 first instinct-only slice — emitted vibration investigation (2026-10-13)

> **Newer LOCAL candidate:** The user clarified that the Night Braid must keep
> hunting when no clue exists: sweep near a real clue, then bounded patrol.
> `docs/M3-NIGHT-HUNT-SEARCH-SLICE.md` contains that follow-up. The combined
> combined candidate is now **guarded-synced in Edit mode (5/5 exact sources)**
> but **NOT Play-confirmed**; full gate **31/31**, official compiler **59/59**. The 30/30 and 58/58 figures below describe this
> earlier noise-only stage.

## Why this first

The user Play-confirmed the House_01 Braid closet exit and asked to start roadmap features. `ROADMAP.md` M2 still needs human visual/performance evidence; M3 is the next code-owned milestone. Its full WP6 (six-channel senses, episodic/semantic memory, prediction, tactics, utility policy, fourth-Garage visit) is **not** delivered here. This small first part answers the first M3 demonstration: can an otherwise idle Braid become interested in a real nearby noise without learning an unseen survivor's live position?

## Local candidate — NOT Studio-synced or Play-tested

- `NoiseField:strongestNearby` reads only already-emitted **VIBRATION** impulses within 32 studs using the existing spatial hash. It applies the channel's weather mask, exponential decay, distance attenuation and existing vibration threshold. It rejects future, stale, weak, masked, removed and out-of-range impulses. A single constructor-cached visitor avoids per-Think closure allocations; an empty hash exits before scanning cells.
- Only on the existing Night `Creature:Think` cadence, when fresh sensed prey, authored bell/light lures and valid last-observed prey have *not* won, `CreatureService` can investigate one such event. The target is rounded to the existing eight-stud memory cell, not a live hidden-player root. Within seven studs it considers the impulse investigated and can pursue a **different** real impulse; a blocked direct line is ignored rather than pulling through a wall. No noise may set `CoverExitIntent`, initiate a chomp, grant a player Night furniture release, change the Braid's accepted gait or add a scheduler/Instance.
- `MonsterConfig.Senses.NoiseInvestigationStuds` (32) and `NoiseInvestigationStopStuds` (7) are read at runtime. Q-learning, saved memory and full WP6 policy remain off.

## Evidence and limits

- Focused `tools/vitriol/senses.luau` **20/20**: hearing range/threshold, event-only coarse target, hidden silent player moves without target updates, removed/stale impulses, wall block, one-time investigation and second event, plus fresh living prey priority. Existing HouseCover **63/63** and HouseAccess **37/37** remain in the full gate.
- Full local gate **30/30**, official compiler **58/58**, `git diff --check HEAD` clean. **Local-only candidate**: the current shell has no legacy Studio bridge URL/token. No guarded Edit-mode sync, exact Studio Source readback, Studio save/publish, human Play verdict or normal measured frame-budget result was performed for M3. The previous House_01 house-cover Studio sync is separate and already Play-confirmed.
- This first step does **not** create footsteps or thrown-noise items, infer noise through inaccessible walls, navigate arbitrarily around houses, pick from all six channels, learn repeat Garage routines, produce the full `AIDebugDump`, or meet M3's final exit criteria. Existing server-owned effects can emit vibration, and the test emits a real `NoiseField` event. In Play, validate a deliberately produced **nearby** vibration while no living prey/lure/last-seen target is active; watch the Braid investigate without revealing a distant hidden player's exact position. A failed Play or measured budget overrun blocks acceptance and calls for a narrow correction, not a gait change.

## Next safe step

Once the legacy bridge is configured, check its place ID and Edit mode, then guarded-sync **only** `ReplicatedStorage.Vitriol.Shared.NoiseField`, `ReplicatedStorage.Vitriol.Config.MonsterConfig`, and `ServerStorage.Vitriol.Services.CreatureService`; read back all three exact Sources/classes. Start fresh Night Play for the specific emitted-noise investigation and collect Output/performance. Until then, leave M3 **local-only** and do not claim players can hear or see this new behavior in the current Studio place.
