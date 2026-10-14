# M3 Garage habit + server-only AIDebugDump — Edit synced, Play pending (2026-10-13)

> **Newest physical route correction (2026-10-13):** From the actual
> Garage's west/north/south sides a direct front-door ray is blocked by the
> user's wall. The memory habit now uses the existing exterior navigation
> corners as **separately ray-guarded legs**, preserving front→interior
> investigation and next-Think blocked fallback. Higher-priority real cues
> invalidate held legs for fresh clearance. Garage **62/62**, shadow
> **21/21**, gate **35/35**, compiler **61/61**; guarded Edit Source/class
> **2/2 exact** and fresh Studio-Source/real-geometry probe `ok:true`.
> No human Play/cadence verdict. See
> [`M3-GARAGE-FLANK-ROUTE.md`](M3-GARAGE-FLANK-ROUTE.md).


> **Further preflight 2026-10-13:** Service tests now model three continuous
> walks through the Garage's east threshold instead of instantly jumping
> from outside to center. A read-only Studio-Source probe ray-checked **43**
> real-map corridor samples and verified the fourth front→interior lead.
> Garage **47/47**, shadow **21/21**, gate **35/35**, compiler **61/61**.
> This is NOT human Play or normal-cadence evidence. See
> [`M3-EXPLAINABILITY-CORRIDOR.md`](M3-EXPLAINABILITY-CORRIDOR.md).


> **Newest correction 2026-10-13:** An earlier grounded exterior sighting
> no longer survives an unseen Think (or a different player taking sensory
> priority); a roof sample no longer counts as "outside" ground evidence.
> This rejects false Garage visits without changing completed run-local
> evidence or front→interior legs. Garage **46/46**, shadow **19/19**, gate
> **35/35**, compiler **61/61**; guarded Edit Source/class **2/2 exact**, real
> Studio-Source geometry probe `ok:true`. Human Play/cadence still pending.
> See [`M3-GARAGE-WITNESS-CONTINUITY.md`](M3-GARAGE-WITNESS-CONTINUITY.md).


> **Follow-up 2026-10-13:** A separate **shadow-only** location-class
> observer now records genuinely sensed transitions through ten existing
> authored semantic zones. It does not replace the Garage's strict
> outside→inside ground-level proof, issue goals or change priorities.
> Shadow **19/19**, Garage **41/41**, full gate **35/35**, compiler **61/61**;
> guarded Edit Source/class readback **2/2 exact**, real-zone probe `ok:true`.
> No human Play or cadence-budget acceptance. See
> [`M3-SHADOW-PREDICTOR-SLICE.md`](M3-SHADOW-PREDICTOR-SLICE.md).


> **Subsequent offline priority regression:** A new fixture verifies the
> existing authored bell lure **still outranks** a learned Garage preference
> (and the already-tested visible prey still wins at close range). The
> server-only AI dump's displayed priority now states the actual conditional
> lure-radius rule and puts recent genuine clues before habit. Focused fixture
> **41/41**, full gate **34/34**, compiler **60/60**. Guarded Vitriol/Edit
> sync changed only that read-only CreatureService explanatory string after
> prior exact Source guard; exact current Studio Source readback and static
> verifier passed (`tools/reports/m3-ai-dump-priority-source.json`). No
> additional Play request, and no normal-budget claim.

## Latest pre-Play correction — front door is not proof of an empty Garage

User insisted **KEEP WORKING** before another Play request. I caught an epistemic error in the first confidence-decay version: merely arriving at the Garage *outside* door does not prove the inside is unoccupied, especially with walls/cover. A read-only real-map survey showed the authored front approach `(-55,-56)` has a direct clear ground-level line to the actual Garage floor center `(-90,-56)` and nearby interior candidates; the Garage roof is centered at Y=19. The Braid now makes **two physical, separately ray-guarded legs**, road→front then front→interior center, with at most **one new ray in each Think** and zero rays while a leg is held. A merely reached front or an obstructed interior never reduces belief; only arriving physically near the real floor center without a fresh clue softens confidence by one, then the accepted local search continues. This is weak counterevidence, not omniscient proof of no hidden survivor. If direct entry is blocked, fallback waits until the next Think so a failed Garage ray is never stacked with two local patrol rays inside one budgeted call. A core above the authored Garage roof threshold cannot be mistaken for an interior visit by X/Z alone. No map geometry, accepted gait, runtime Instance, public target route or priority changed.

Focused fixture **41/41**, full quality gate **34/34**, compiler **60/60**, `git diff --check HEAD` clean. Existing source parity was rechecked in Vitriol/Edit **2/2**, guarded sync updated ONLY `GarageHabit` and `CreatureService`, and **2/2 exact Studio Source/class** readback passed (`tools/reports/m3-garage-physical-sources.json`). Freshly compiled actual Studio Source physically tested both original front and interior legs, verified no miss at the exterior, recorded a miss only at the interior, rejected a blind repeat next Night, restored confidence after another witnessed entry, and refused a roof-height false check (`tools/reports/m3-garage-physical-live-source.json`, `ok:true`). Post-sync static verifier `ok:true`. **No human Play verdict or cadence-budget measurement for this new candidate.** The earlier single `Time:Publish 0.389/0.050 ms`, Think 8.313/1.000 ms and Session 0.204/0.050 ms overruns remain open. Do not request another Play merely to close this documentation update; user explicitly asked for continued offline work first.

## Pre-Play follow-up: disconfirm wrong predictions (2026-10-13)

The user asked to **keep working before another Play request**. The first candidate would seek the same Garage on every future Night after three witnessed entries, even if it repeatedly found nothing. The habit now keeps a small **bounded actionable confidence** (0–3) separate from capped visit/miss counters (0–12): real witnessed entries raise confidence by one; reaching an empty front approach without a fresh cue lowers it by one. Thus one unsupported Garage check suppresses the next-Night Garage preference until **new witnessed evidence** restores confidence. A merely blocked route does not penalize the belief, and a genuinely witnessed entry while the prediction is active marks it confirmed rather than a miss. This changes ONLY an unaccepted new habit, not the already Play-accepted local/region patrol, geometry or gait. Saturated historical counters cannot trap confidence forever: even after 12 observations a fresh witness can restore it. No timer, DataStore, new ray per held Think or public remote was added.

Focused habit **30/30**, full gate **34/34**, compiler **60/60**. Vitriol/Edit re-guarded both touched Studio Sources **2/2** and synced only `GarageHabit`/`CreatureService`, with **2/2 exact updated Source/class** readback (`tools/reports/m3-garage-habit-miss-sources.json`). A fresh real Studio-source/garage-floor probe witnessed three entries, confirmed a miss at the front, rejected a repeat on the next Night and restored the lead after one new sighting (`tools/reports/m3-garage-habit-miss-live-source.json`, `ok:true`, visits 4, misses 1, effective 3); post-sync static verifier `ok:true`. No additional human Play yet; normal cadence budget remains unverified. The headless session-test runner now synchronously prints its verdict to prevent an occasional falsely red quality gate caused by `process.exit()` racing a piped `console.log()`. This is tooling only; tests still execute normally.

## Roadmap interpretation and sensory boundary

The roadmap M3 exit asks: “make a noise → it investigates. Walk to the same Garage four times → on the fourth it goes there first, and AIDebugDump shows why.” The earlier local-noise and region-hunt candidates are Play-accepted for Night movement/give-up. This follow-up is **instinct-only observed-place memory**, NOT Q-learning/M4, a hidden-survivor tracker or a completed M3 acceptance. Crucially, the Braid cannot count a survivor visiting the Garage if it **did not actually sense that survivor**. A visit is conservatively counted only after the *same* living player has been genuinely sensed **outside** the Garage footprint and subsequently sensed **inside** the actual Garage floor at ground level. First seeing somebody already inside is not evidence of their entry. Seeing them 30 times inside counts zero additional entries; an unseen exit does not fabricate a new entry. Roof-level roots and road-adjacent positions are excluded. Only the already-sensed `root` returned by the bounded `_nearestTarget` is passed to the Garage habit; no new player list scan, global player-location memory, GPS, or DataStore.

After **three witnessed entries**, a clue-less Night search first checks a direct physically clear ray to the Garage's authored **east/front approach**. On the current map this is `(-55,-56)`, derived from existing `Millers_Garage.Floor` and the existing `GarageNavigation.Nodes[1]`; the real floor is centered `(-90,-56)` and is 56×46 studs. A read-only Edit-mode geometry/source probe confirmed the approach from the representative road origin `(0,0)` is clear. A survivor/lure, bounded last-seen prey, nearby emitted noise, and recent genuine clue search all continue to win first. If the approach is blocked by a wall or placed cover, the Braid remains in the already-accepted local/road hunt; no prediction grants furniture-breach or phase-through-wall authority. At most **one new candidate clearance ray per Think** is used at each front/interior leg selection (none while held); interrupted plans are rechecked. Arrival near the **interior floor center** or three seconds without core progress ends that one lead, then the existing local search resumes. An unproductive *physical interior* arrival reduces bounded confidence; a front-door arrival or obstructed approach does not. It may be tried once per Night and needs new witnessed evidence after a miss; run-local evidence survives Day/Dawn, but no DataStore persistence, new cadence job, Path, spawned gameplay/UI Instance or gait/body change was added. This is an anticipatory place preference, not a claim the Braid saw an unseen fourth visit or a guaranteed interior route from every town position.

A deliberate server-only `CreatureService:aiDump()` returns aggregate witnessed entry count/threshold, evidence rule, current goal, active decision reason, search/lead state, and explicit priority order. `jobs/ai_debug_dump_vitriol.lua` reads it **during live Play** through the already-connected server bridge. It is deliberately **NOT exposed to `RF_DebugQuery`**, which presently has rate/schema gating but no per-player secret-location authorization: handing the Braid's live target to every player would defeat the horror loop. This is the bounded “shows why” diagnostic; the broader AIDebugDump designer command UI and full M3 policy remain future work.

## Proof and integration

- `tools/vitriol/garage-habit.luau` **30/30**: sight-derived outside→inside evidence only, no repeated-tick inflation or roof counting, after three entries head toward front Garage first, fresh clue and prey priority, one-ray/held-route budget, cover/wall denial, stall/arrival give-up, next-Night reuse, Day withdrawal, run-local memory, no runtime Instances, and server-only explanation. Existing Night search **19/19**, regions **12/12**, senses **20/20**, house-cover **63/63**, Time publish profile **10/10**; full quality gate **34/34**, official compiler **60/60** (one new ModuleScript), `git diff --check HEAD` clean. Headless simulation proves decision logic, not actual Roblox Play route or 1 ms Think compliance.
- Legacy bridge confirmed Vitriol place ID `92448193604950` in **Edit mode**. Read-only guard verified `MonsterConfig` and `CreatureService` against their previously exact Studio Source readbacks **2/2** (local diffs were the deliberate Garage-habit additions only). Existing `Brain` Folder verified, no prior `GarageHabit` to overwrite. Guarded sync of just `MonsterConfig`, the new `Brain/GarageHabit` **authored ModuleScript**, and `CreatureService`; class checks and **3/3 exact Source** readback (`tools/reports/m3-garage-habit-sources.json`). Post-sync static verifier `ok:true` (7 remotes, 211 Braid parts, 24 blood parts), and fresh-compilation of actual Studio Sources plus real-floor/direct-entry probe `ok:true`, visits=3, entry `(-55,-56)` (`tools/reports/m3-garage-habit-live-source.json`). No map Part or previously approved gait changed.
- **Human Play of the fourth-visit behavior and normal cadence is PENDING.** In a fresh Night Play, let the Braid actually see you *outside then inside* the Garage three separate times (with visible departures in between), then break contact. With no bell/lit-light lure, fresh sound, valid last-seen clue or recent sweep, it should try the front Garage approach before normal patrol; the read-only AI dump should say `witnessed-three-garage-entries`. If the approach is blocked, local hunt should continue. If it never sees an entry, no anticipation is expected. Record any `Creature:Think` warning; the earlier one-off Think 8.313/1.000 ms, Session 0.204/0.050 ms and Time:Publish 0.389/0.050 ms warnings are still real and unresolved. The latest Time:Publish one was reported **once** and now carries a same-sample breakdown *if it recurs*. Save/publish and Git push unconfirmed.
