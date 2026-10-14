# Vitriol roadmap — what we're building now

> **CURRENT OWNER PRIORITY — independent features before Play verdicts (2026-10-14):**
> The owner explicitly deferred House/Garage/church verdict work and chose
> **M6 survival needs**. New pure, workspace-only `SurvivalModel` uses authored
> activity rates, smooth hunger↔thirst coupling, data-driven debuff effects,
> stamina, verified-consumption arithmetic, timed exhaustion and a collapse
> *candidate* predicate: **54/54** focused. A separate pure collapse
> sequence has **24/24** tests for 1.5-second onset, one retrievable
> `VIBRATION 0.9` fall request and eight-second crawl timing (NO live noise).
> A pure **25/25** timed consumption transaction gates food/water effects
> behind uninterrupted action time and one successful owned-item commit.
> An unwired server ownership adapter accepts only server fact samplers,
> drives Health regen, isolates snapshots and can emit into the REAL
> NoiseField when explicitly invoked offline: **57/57** adapter tests.
> A server-only timed-consumption seam with FAKE Inventory and REAL headless
> AIR noise passes **25/25** checks; full gate **49/49**. None is Bootstrapped, Studio-synced, scheduled or live;
> no Instances/UI or HP writes. **Pacing conflict open:** current config
> yields thirst 7.2 after 9 walking minutes versus
> docs/05 Parched≈9min at thirst 80; even 16 continuous baseline sprint
> minutes only reach thirst33.6/hunger15.2, not Collapse. Neither short
> Studio phases nor config were silently retuned. Preserve the two-module
> House-cover candidate as a separate LOCAL-only item; bridge Edit checks
> remain intermittent. Do not request a Play verdict or claim M6 survival
> live. See [`M6-SURVIVAL-MODEL-OFFLINE-2026-10-14.md`](M6-SURVIVAL-MODEL-OFFLINE-2026-10-14.md).
> Older blocks below preserve prior checkpoint history.

> **NEWER HUMAN PLAY / LOCAL-ONLY FOLLOW-UP (2026-10-14):** The
> owner confirms the Braid **entered House_01 AFTER dislodging its
> original closet**; the break Output gives outside core(-72.0,8.6,78.0)
> and genuinely-sensed-prey goal(-87.0,78.0). It needed renewed visibility
> to break a piece it seemed to be pressing. By explicit owner choice,
> a narrow, locally tested recent-genuine-indoor-clue contact rule is now
> pending in CreatureCore + CreatureService (**NOT installed or saved**).
> Local House-cover 69/69, full repeated-Think breach 11/11 at BOTH houses, and gate 44/44; no new Play verdict for that rule.
> The Edit bridge `run_luau` guard intermittently returned
> `loadstring() is not available` despite owner-confirmed Edit. A later
> successful pre-read guard captured EXACT read-only two-Source backup
> `backups/vitriol-studio-edit-cover-pre-2026-10-14.zip`, but a subsequent
> guard again failed. NO Studio Source write occurred; do NOT sync until
> mode checks are reliable. After reconnect, one of four identical
> read-only Edit probes STILL failed; `--check` alone passing does not
> establish reliability. House_01 EXIT remains open, as do
> House_02, Garage habit, church entrance and actual DayPrep/Time budget
> overruns (new Time:Publish 0.557/0.050 ms, attributes 0.530). Do NOT
> claim Edit parity for this local candidate or ask for Play acceptance
> until a verified guarded sync and NEW cloud save. See
> [`PLAY-REPORT-2026-10-14-CLOSET-CONTACT-CADENCE.md`](PLAY-REPORT-2026-10-14-CLOSET-CONTACT-CADENCE.md)
> and [`NEXT-PLAY-SUMMARY-2026-10-13.md`](NEXT-PLAY-SUMMARY-2026-10-13.md).
> Earlier blocks below record earlier checkpoints.

> **CURRENT Play → guarded M2 follow-up (2026-10-13):** The newest
> human Play found the grounded Braid spasming OUTSIDE House_01 at
> X≈−54; it never entered, so this run has NO exit verdict. One `LastKnown`
> target was inside; a later `Prey` target was outside on the Porch. The
> old Source bypassed physical House-door staging for a genuinely stored
> LastKnown goal. A narrow correction was reproduced red→green, guarded-
> synced ONE Module exact, and the owner verified a NEW Save to Roblox
> with Notes/Version History entry. **No Play verdict for that fix; the
> separate Prey spasm remains OPEN.** The owner confirmed Studio-only
> `NightBaseSeconds=70` is intentional; preserve it. Fresh read-only Edit
> audit **PASS 10/10 verifiers, 61/61 Sources/classes, zero drift**, local
> gate **40/40**, House **78/78**. Real Session/DayPrep/BellHoist/Time
> overruns remain OPEN; do not raise budgets. Focus the next Play on
> House ingress before exit, M3 Garage or M6 church. See
> [`NEXT-PLAY-SUMMARY-2026-10-13.md`](NEXT-PLAY-SUMMARY-2026-10-13.md)
> and [`HOUSE-INGRESS-LASTKNOWN-CORRECTION-2026-10-13.md`](HOUSE-INGRESS-LASTKNOWN-CORRECTION-2026-10-13.md).
> Later blocks below describe earlier checkpoints.

> **CURRENT saved / owner-approved Edit state (2026-10-13):** The
> House/Garage `CreatureService` and exact-target `ChurchNavigation` were
> guarded-synced **2/2 exact**; the owner verified the new post-sync
> **Save to Roblox with Notes** in Version History (human confirmation,
> not bridge proof). After read-only preflight, the owner explicitly
> approved the lever’s ALREADY-AUTHORED `(119,2.5,-199)` position in place
> of the former Z=-210; **no geometry or game Source was changed** by that
> decision. Only local verifier/editor jobs and a route fixture were updated.
> Fresh read-only Edit audit **PASS: 10/10 verifiers, 61/61 Sources/classes,
> zero unexpected drift**. Full local gate **39/39**. Braid church route,
> latest House exit, fourth Garage visit and cadence have no fresh human
> Play verdict; no new publish or Git push is confirmed. See
> [`CHURCH-LEVER-CURRENT-POSITION-APPROVED-2026-10-13.md`](CHURCH-LEVER-CURRENT-POSITION-APPROVED-2026-10-13.md)
> and [`HOUSE-CHURCH-GUARDED-EDIT-SYNC-2026-10-13.md`](HOUSE-CHURCH-GUARDED-EDIT-SYNC-2026-10-13.md).
> Status paragraphs below describe earlier checkpoints.

> **New read-only House exit grid:** The installed Studio/Edit Source was
> sampled at 15 grounded seeds per house × 4 temporary original-furniture
> states: **120/120** policy outcomes matched the safe authored-map profile.
> With a table but no closet, 4 direct exits and 11 indoor stage→exit
> rechecks per house succeeded; a placed closet safely denied the ray.
> At most one new candidate ray per synthetic Think. This is **not**
> planted-foot Play egress or a frame-cadence pass; no Studio write. See
> [`HOUSE-EXIT-AUTHORED-GRID-EDIT-2026-10-13.md`](HOUSE-EXIT-AUTHORED-GRID-EDIT-2026-10-13.md).

> **Pre-sync read-only place-data protection (2026-10-13):** A separate selected-
> property ZIP inventories 1,930 Edit Instances across 13 services, with
> per-member SHA-256 hashes and offline integrity/fail-closed tests **5/5**. It
> complements the earlier 75-Source ZIP but is NOT a full place, terrain/
> asset backup, atomic snapshot, Play capture, or cloud save. The two local
> Source changes remain unsynced. The owner confirms the current Vitriol
> **published version is visible in Version History** and explicitly allows
> that version as the pre-sync safety checkpoint. The bridge is not configured
> here, so no sync can run; after any future sync, Save to Roblox with Notes
> and verify the NEW checkpoint. This owner report is not an independent
> Studio/UI verification. See
> [`STUDIO-EDIT-PROPERTY-INVENTORY-2026-10-13.md`](STUDIO-EDIT-PROPERTY-INVENTORY-2026-10-13.md).

> **PRE-SYNC data-safe offline work:** On the actual Edit church map, the
> present queryable lever at Z=-199 terminates the old entrance→bell lure
> ray, while the user's previously approved Z=-210 remains an unresolved
> authored position. A LOCAL `ChurchNavigation` correction accepts only
> the exact authored target lever as endpoint (walls/windows stay solid).
> This and the prior House→Garage `CreatureService` change are **both pending
> Studio**, guarded read-only 2/2 exact old Sources/classes; neither was
> written. Church **10/10**, House **74/74**, full gate **39/39**, compiler
> **61/61**. The owner confirms a published pre-sync version in Version
> History; there is no new post-sync save or bridge access. Do not request
> Play now. See
> [`CHURCH-LEVER-ENDPOINT-READONLY-2026-10-13.md`](CHURCH-LEVER-ENDPOINT-READONLY-2026-10-13.md).

> **PRIOR offline House→Garage interaction:** One local-only
> `CreatureService` fix makes a clue-less Braid finish its House circuit and
> physical lower-first exit before using a genuinely witnessed Garage
> preference. The habit survives and is re-ray-checked outside. House
> **74/74**, Garage **69/69**, full gate **37/37**, compiler **61/61**.
> Read-only guarded Edit check found Studio's exact previous Source; **do
> not call this new behavior Studio-synced or Play-verified**. Current Edit
> audit has exactly one planned local Source difference, plus the unresolved
> church lever. A verified Save to Roblox with Notes checkpoint is still
> a required user Studio action; no publish by default. See
> [`HOUSE-GARAGE-HABIT-EGRESS-PRIORITY-2026-10-13.md`](HOUSE-GARAGE-HABIT-EGRESS-PRIORITY-2026-10-13.md).
>
> **Latest Edit/fixture support preflight:** Actual Floor→Porch support
> crosses a half-stud gap at each door. Both original open closet lanes have
> clear physical ground-height rays, and downward rays contact the real
> Porch from the seam onward. Both House synthetic foot replays now model
> the separate measured surfaces and grip Porch without altering gameplay;
> House **74/74**, full gate **37/37**. Not a Studio sync or human Play pass.
> See [`HOUSE-DOOR-SUPPORT-EDIT-PREFLIGHT-2026-10-13.md`](HOUSE-DOOR-SUPPORT-EDIT-PREFLIGHT-2026-10-13.md).

> **Prior Studio/Edit boundary:** The user's temporary legacy bridge
> allowed a fail-closed sync of four pending House/Garage Modules: final
> Studio Source/class **4/4 exact**. Actual-Studio-Source House/Garage and
> static Edit probes passed; 75 Studio script Sources/classes have a ZIP
> backup. **Save to Roblox is still unconfirmed**; this is not a full place
> or player-data backup, publishing, or live Play acceptance. Preserve short
> Studio phases and extended road. A later OFFLINE House_02 planted-foot
> doorway replay, now including independently placed table/closet cases,
> passed **67/67** House tests and the full gate **36/36**,
> without changing any game script or needing another Studio Source sync.
> It is not a House_02 human Play verdict. The read-only Edit verifier
> inventory is 9/10, with the church lever Z=-199 versus approved Z=-210
> unresolved. A comprehensive read-only Edit audit also checked all 61
> Source/classes: 46 byte-exact, 13 single terminal-LF differences, two
> hash-pinned user differences, zero unexpected drift; it still FAILS on
> the bell lever. See [`HOUSE-02-FOOTED-EXIT-OFFLINE-2026-10-13.md`](HOUSE-02-FOOTED-EXIT-OFFLINE-2026-10-13.md)
> and [`STUDIO-EDIT-SYNC-AND-SOURCE-BACKUP-2026-10-13.md`](STUDIO-EDIT-SYNC-AND-SOURCE-BACKUP-2026-10-13.md).

> **Prior no-Play foot-supported exit:** A low numeric House-exit Y
> did not lower the real planted-foot stance in an offline floor/roof replay.
> The bounded idle sweep now applies a temporary, genome-derived doorway
> crouch until the actual core fits; live prey restores high stance and
> chomp retains its own CROUCH. House fixture **63/63**, Garage **69/69**,
> gate **36/36**, compiler **61/61**. At that earlier checkpoint four
> Sources were workspace-only; they have since been guarded-synced 4/4 in
> Edit. There is still no human House exit Play verdict on this correction. See
> [`HOUSE-EXIT-FOOT-SUPPORTED-LOWERING.md`](HOUSE-EXIT-FOOT-SUPPORTED-LOWERING.md).

> **Prior no-Play House geometry correction:** An angled centerline
> through the authored east door can still graze a pier or currently
> placed original table at its near/far face. The workspace-only sweep
> now checks the radius-expanded full-depth corridor first, without an
> extra ray or altering geometry; House **58/58**, Garage **69/69**, gate
> **36/36**, compiler **61/61**. The earlier lowering/diagnostic changes
> also remain **unsynced** (no bridge credentials). No House/ Garage Play
> or live cadence acceptance. See
> [`HOUSE-EXIT-CORNER-CLEARANCE.md`](HOUSE-EXIT-CORNER-CLEARANCE.md).

> **Prior no-Play House correction:** A raised indoor core no longer
> receives an outward exit target before it has actually descended below
> the door lintel; it first gets a vertical-only waypoint, spending no
> candidate ray. Three seconds without downward progress returns it to
> local patrol. House **51/51**, Garage **69/69**, gate **36/36**, compiler
> **61/61**. This and the previous Garage Output change are **workspace-
> only, not Studio-synced**. See [`HOUSE-EXIT-LOWER-BEFORE-RAY.md`](HOUSE-EXIT-LOWER-BEFORE-RAY.md)
> and the guarded `tools/sync-pending-house-garage.py --offline` plan.
> Live House exits, fourth Garage visit and timing are still open.

> **Newest offline Garage diagnostic:** A genuinely witnessed third entry
> and the first chosen Garage lead now queue limited server-only Output
> **after** the measured Think slot. Garage synthetic fixture **69/69**,
> gate **36/36**, compiler **61/61**. **Workspace only, Studio sync pending:**
> bridge credentials unavailable here. Human fourth-visit, House egress
> and real cadence verdicts remain open; no Play needed now. See
> [`M3-GARAGE-DECISION-OUTPUT.md`](M3-GARAGE-DECISION-OUTPUT.md).

> **Newest offline cadence follow-up:** Real Play showed
> `DayPrep:Pulse 0.418/0.405/0.223 ms` against 0.050, separate Session
> begin-round 0.209 ms and Time:Publish 0.395 ms (attributes 0.235).
> Future exceptional DayPrep Output will distinguish actual prep stage
> before→after, action, bell state and scheduled hum. Synthetic **10/10**,
> gate **36/36**; guarded two Studio/Edit Sources/classes **2/2 exact**.
> This is not a measured performance fix or retrospective attribution.
> Bridge does not support live Play. See
> [`DAYPREP-WARNING-CONTEXT.md`](DAYPREP-WARNING-CONTEXT.md).


*Current as of 2026-10-13 · Vitriol `main` · ✅ accepted/done · 🟨 underway or awaiting Play · ⬜ planned*

> **Newest House_01 follow-up:** User asked for a circular raycast exit
> when trapped and not chasing. A bounded, time-sliced ground-door sweep
> now takes at most one new ray per Think after a completed local circuit,
> checks body-width clearance around actual piers and placed furniture,
> and may stage inside before retrying. Guarded/Edit-synced two Sources/
> classes **2/2 exact**; real-door Studio-Source probe `ok:true`, focused
> HouseAccess **45/45**, gate **36/36**, compiler **61/61**. **Fresh human
> exit Play pending**, no changed gait/map/budget. The new real Play
> Session/DayPrep/Time warnings remain open. Bridge cannot inspect Play.
> See [`HOUSE-IDLE-EXIT-SWEEP.md`](HOUSE-IDLE-EXIT-SWEEP.md).

> **Newest Play correction (2026-10-13):** Only **two** Garage player entries
> were attempted, below the three-witness habit threshold. In House_01 the
> Braid entered and dislodged its closet but did **not** leave in this run;
> paid rebuild worked. The supplied `Prey` stall line describes earlier
> outside→inside contact, not the failed exit. Earlier House_01 exit Play
> succeeded in a different run, so reliability is now **open**. Read-only
> Studio geometry/search probes found one potential tight-pier road ray but
> cannot attribute the actual stopped-Play exit. The one-per-break Output
> line now includes contact core/goal/reason/feet (guarded Edit Source/class
> **2/2 exact**, fixture **64/64**, gate **36/36**), but its richer format
> has not been seen in human Play. The bridge cannot inspect live Play. See
> [`PLAY-REPORT-2026-10-13-HOUSE01.md`](PLAY-REPORT-2026-10-13-HOUSE01.md).

## In one sentence

We're building the **Night-hunting Braid's honest, explainable memory** (M3): it must pursue only genuinely sensed clues, search rather than idle, and learn a Garage preference from *witnessed entries*—without hidden-player GPS or Q-learning—while protecting the survival/Day-prep game that already works.

## The playable loop we're protecting

Survive Night; share Day preparation time and helper voting; withdraw at dawn; respawn with inventory lost and 20 less maximum HP; zero maximum HP ends the run. Preserve the approved Braid gait, pace and lower-then-charge chomp, the bell's actual church entrance, light-repair scope, tap-to-check watch and physical furniture/cover rules. The user Play-confirmed the regional hunt/give-up feel, House_01 entry and one earlier exit after closet contact, and watch repair. **A later run failed to exit House_01 despite dislodgement**, so current exit reliability is open; do not overwrite either observation. **Do not silently change the map, DayNight testing phases, or budgets to make a gate pass.**

## Milestones

| Stage | Plain-English goal | Where it stands |
| --- | --- | --- |
| **M0–M1 · Foundation/authority** | Config, shared contracts, authoritative time/session/health/cadence, preauthored runtime policy | ✅ Implemented and tested. |
| **M2 · The body** | One readable, planted-foot Braid that moves and enters the real world | 🟨 Body/gait and House_01 entry have human Play evidence; one prior House_01 exit succeeded, but a newer run failed after closet break. Exit reliability, wall/ceiling/render and per-frame budget acceptance remain open. |
| **M3 · Instinct-only hunter — current focus** | Limited directional and close thermal sensing; emitted-noise investigation; genuine last-clue sweep then regional patrol; physically witnessed Garage-entry habit; honest server-only explanation | 🟨 Scoped pieces are integrated and locally/Studio-Edit checked. User accepted Night regional hunt/give-up. **Not complete:** human fourth-Garage-visit→first-choice check, Play noise/decision explanation and active Think budget are still open. Zone-transition model observes only; it cannot steer or locate hidden players. Q-learning **off**. |
| **M4 · Learning on** | Later, explicitly enabled Q-learning, persistence and measured A/B capture improvement | ⬜ Deferred. Do not turn it on to satisfy M3. |
| **M5 · The kill** | Lower-then-charge contact, first-person victim sequence, wounds/blood and full presentation | 🟨 Minimum path exists; final choreography/presentation and Studio acceptance remain open. Preserve the approved chomp. |
| **M6 · World interaction** | Full destruction, survival, inventories, vehicle, interaction/audio/VFX systems | 🟨 **Only selected slices** exist: Day prep, church bell, garage/station lights, barricades, watch, and two-house cover. This is not full M6. House_01 exit reliability is newly open after a later no-exit report; House_02 physical exit still needs its own Play check. House_01 paid rebuild worked in the latest run. |

## What we're actually working on this week

1. **M6 survival needs, offline first (owner-selected).** Build the data-driven, pure server-authority math without turning the current `Features.Survival=true` flag into an unbudgeted live service. `SurvivalModel` has **54/54** focused tests, pure collapse **24/24**, pure timed consumption **25/25**, and the unwired server ownership adapter **57/57**, and its fake-Inventory/real-AIR consumption seam **25/25**; full gate **49/49**. The intended Parched≈9min/Collapse≈16min conflicts sharply with the existing per-minute values; preserve the owner's short Studio phases and flag the pacing decision rather than secretly multiplying need gain. See [`M6-SURVIVAL-MODEL-OFFLINE-2026-10-14.md`](M6-SURVIVAL-MODEL-OFFLINE-2026-10-14.md).
2. **Protect pending gameplay edits without a Play request.** The recent-memory House contact candidate is still two local-only Modules, not in Studio. The legacy Edit guard is intermittent. Leave saved Studio unchanged until exact place/mode/source guards become reliable; do not ask for an ingress/exit or Garage/church verdict during this owner-directed feature phase.
3. **Budget truth remains open.** Real Session/DayPrep/BellHoist/Time warnings are over budget; the Night `Time:Publish` 0.557/0.050 ms sample spent 0.530 ms in attribute publication. The headless DayPrep call count does not explain real engine time. Do not raise shares or report compliance without new Play measurements. M4 learning remains deferred; do not activate it to fill this schedule.

## Next proof gates (when a human Play pass is practical)

For the current short hands-on sequence and copy/paste report, use
[`NEXT-PLAY-SUMMARY-2026-10-13.md`](NEXT-PLAY-SUMMARY-2026-10-13.md).
The Studio bridge cannot inspect active Play: rely on the user’s Output
and visible movement for live evidence; Edit-mode source/geometry probes are offline only.

- **Fourth Garage visit:** walk a survivor through three genuinely visible ground-level entries with breaks between them. On the next Night with no fresher clue, does the Braid prefer the **front entrance, then the interior**, from either side without phasing through walls? Does a real prey/lure/noise cue correctly interrupt it? If a future server-side Output diagnostic reports its reason, compare it with the visible decision; the bridge cannot inspect active `aiDump()`, and private targets must not be published to clients. This is the milestone's missing human verdict, not a request to pretend an Edit probe is Play.
- **House_01 now first:** a later Play saw the Braid inside, dislodge the closet, then fail to leave (paid rebuild worked). A first `Prey` stall line was *earlier ingress*, not the exit. During any practical fresh Play, capture the first **post-break Roblox Output warning** and a short view of the Braid relative to the east door/side wall/roof; do not retest the entire Garage setup for this. See [`PLAY-REPORT-2026-10-13-HOUSE01.md`](PLAY-REPORT-2026-10-13-HOUSE01.md).
- **House_02 separately:** observe the Braid dislodging placed cover and actually crossing the exit, then verify a later Day paid rebuild. A read-only geometry probe is not a human Play verdict.
- **Active budgets:** record ordinary and worst-case Think plus Session/Time diagnostics *during Play*. Attribute any new warning to its path before changing code; retain the same measured shares and warnings. Restart Play after Edit-mode source updates. The owner confirmed the post-sync Save to Roblox with Notes; no new post-sync Publish or Git push is confirmed.

Then pursue remaining M2/M5 presentation/world acceptance and M6 systems deliberately. M4 is separate and waits; no full-M3 or overall game-complete claim is warranted yet. The long [`ROADMAP.md`](../ROADMAP.md) contains the original work packages and dated engineering log; its older “newest” blocks describe historical stages, not current acceptance.
