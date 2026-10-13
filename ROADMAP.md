# VITRIOL — Roadmap

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
> live. See [`docs/M6-SURVIVAL-MODEL-OFFLINE-2026-10-14.md`](docs/M6-SURVIVAL-MODEL-OFFLINE-2026-10-14.md).
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
> [`docs/PLAY-REPORT-2026-10-14-CLOSET-CONTACT-CADENCE.md`](docs/PLAY-REPORT-2026-10-14-CLOSET-CONTACT-CADENCE.md)
> and [`docs/NEXT-PLAY-SUMMARY-2026-10-13.md`](docs/NEXT-PLAY-SUMMARY-2026-10-13.md).
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
> [`docs/NEXT-PLAY-SUMMARY-2026-10-13.md`](docs/NEXT-PLAY-SUMMARY-2026-10-13.md)
> and [`docs/HOUSE-INGRESS-LASTKNOWN-CORRECTION-2026-10-13.md`](docs/HOUSE-INGRESS-LASTKNOWN-CORRECTION-2026-10-13.md).
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
> [`docs/CHURCH-LEVER-CURRENT-POSITION-APPROVED-2026-10-13.md`](docs/CHURCH-LEVER-CURRENT-POSITION-APPROVED-2026-10-13.md)
> and [`docs/HOUSE-CHURCH-GUARDED-EDIT-SYNC-2026-10-13.md`](docs/HOUSE-CHURCH-GUARDED-EDIT-SYNC-2026-10-13.md).
> Status paragraphs below describe earlier checkpoints.

> **New read-only House exit grid:** The installed Studio/Edit Source was
> sampled at 15 grounded seeds per house × 4 temporary original-furniture
> states: **120/120** policy outcomes matched the safe authored-map profile.
> With a table but no closet, 4 direct exits and 11 indoor stage→exit
> rechecks per house succeeded; a placed closet safely denied the ray.
> At most one new candidate ray per synthetic Think. This is **not**
> planted-foot Play egress or a frame-cadence pass; no Studio write. See
> [`docs/HOUSE-EXIT-AUTHORED-GRID-EDIT-2026-10-13.md`](docs/HOUSE-EXIT-AUTHORED-GRID-EDIT-2026-10-13.md).

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
> [`docs/STUDIO-EDIT-PROPERTY-INVENTORY-2026-10-13.md`](docs/STUDIO-EDIT-PROPERTY-INVENTORY-2026-10-13.md).

> **PRE-SYNC LOCAL/EDIT boundary (2026-10-13):** Two local-only Modules
> pending, NOT in Studio: House/Garage-safe `CreatureService` and the exact-
> target church-lever `ChurchNavigation` correction. The actual lever at
> Z=-199 (previously approved -210) itself stops the old ground-height
> lure ray after the main entrance. The new candidate is validated against
> the real Edit geometry **in memory only**, not Play or Studio-written.
> Read-only two-Module guarded check passed; **no post-sync cloud
> save, Studio write or Play verdict**. House **74/74**, Church **10/10**, full gate
> **39/39**, compiler **61/61**. See
> `docs/CHURCH-LEVER-ENDPOINT-READONLY-2026-10-13.md`.

> **PRIOR OFFLINE priority fix (2026-10-13):** An actual witnessed Garage
> habit could preempt the grounded House exit after the local circuit. One
> LOCAL `CreatureService` correction now finishes House patrol/door egress
> before resuming the preserved Garage lead on a fresh exterior ray. House
> **74/74**, Garage **69/69**, gate **37/37**, compiler **61/61**. This Source
> is **not yet in Studio**: the legacy Edit bridge readback confirms its
> exact prior Studio Source, and the guarded future one-Module sync is
> intentionally not applied until a human verifies a Save to Roblox with
> Notes checkpoint. Cloud save, Play and real cadence remain unconfirmed.
> See `docs/HOUSE-GARAGE-HABIT-EGRESS-PRIORITY-2026-10-13.md`.

> **Prior Edit sync / data-safety boundary (2026-10-13):** With the
> user's temporary bridge, four previously pending House/Garage Modules
> were guarded against exact prior full Sources/classes, synced in Edit,
> and verified **4/4 exact**. Actual-Studio-Source House/Garage and static
> probes passed; read-only ZIP backs up 75 Studio script Sources/classes.
> This is **NOT a cloud Save to Roblox, published version, full place
> backup, player data store, or Play test**. Preserve the user's short
> phases and extended road. The read-only road verifier now accepts the
> extended original corridor; 9/10 Edit verifiers pass, with the church
> lever at actual Z=-199 versus approved Z=-210 still unresolved. Save the
> place through Studio and verify Version History before further geometry
> decisions. A later *offline* House_02 actual-foot replay passed: House
> **67/67**, full gate **36/36**; no game Source, map geometry or Studio
> object was changed. See `docs/HOUSE-02-FOOTED-EXIT-OFFLINE-2026-10-13.md`.
> See
> `docs/STUDIO-EDIT-SYNC-AND-SOURCE-BACKUP-2026-10-13.md`.

> **Prior no-Play foot-supported House exit (2026-10-13):** A low
> stationary goal did not actually lower the elevated, anchored core; a
> Lua-only floor/roof frame replay plateaued above the door lintel. The
> clue-less House sweep now applies a genome-derived temporary supported
> crouch until its actual core fits and the verified outward route crosses.
> Sensed prey and chomp retain their approved stance priority. House
> **63/63**, Garage **69/69**, gate **36/36**, compiler **61/61**. **Four
> workspace-only Sources, Studio sync pending; no Play/cadence verdict.**
> See `docs/HOUSE-EXIT-FOOT-SUPPORTED-LOWERING.md`.

> **Prior offline House corner guard (2026-10-13):** The radius-1.5
> Braid could pass an angled thin ray and the door/cover CENTER-plane
> checks yet clip a solid pier or placed original table at its near/far
> X face. Numeric full-core guards now reject those false candidates
> before the existing ≤1 new physical ray per Think. A valid indoor stage
> survives from farther west. House **58/58**, Garage **69/69**, gate
> **36/36**, compiler **61/61**. **Workspace-only**, no current Studio sync
> or Play/cadence verdict. See `docs/HOUSE-EXIT-CORNER-CLEARANCE.md`.

> **Prior no-Play House correction (2026-10-13):** A low Y on a distant
> outward exit target did not guarantee that the planted-foot core descended
> first. Grounded high indoor Braid now receives ONLY a downward waypoint
> and no outward ray until actually lowered; a three-second no-progress
> descent falls back to local patrol. House **51/51**, Garage **69/69**,
> gate **36/36**, compiler **61/61**. **Workspace only, Studio sync pending**
> for this and previous Garage Output change. No Play verdict. Guarded
> four-script offline plan `tools/sync-pending-house-garage.py --offline`.
> See `docs/HOUSE-EXIT-LOWER-BEFORE-RAY.md`.

> **Newest no-Play M3 instrumentation (2026-10-13):** A real witnessed
> third Garage entry and the first actually chosen clue-less Garage lead
> each queue an aggregate server-only explanation after the measured Think
> slot, at most once per Night per kind. Garage fixture **69/69**, gate
> **36/36**, compiler **61/61**. **Workspace only; Studio sync pending**
> because bridge credentials are unavailable in this environment. Neither
> a Play fourth-visit verdict nor a Think budget clearance. No test request
> now. See `docs/M3-GARAGE-DECISION-OUTPUT.md`.

> **Newest no-Play cadence context (2026-10-13):** Recent REAL
> DayPrep:Pulse 0.418/0.405/0.223 ms warnings now have a future same-slot
> exceptional Output label for prep action, stage before→after, bell and
> generator hum; the original measured slot, shared Day prep and 0.050 ms
> budget remain. Session begin-round 0.209 ms and Time:Publish 0.395 ms
> (attributes 0.235 ms) are still OPEN. Synthetic **10/10**, gate **36/36**,
> compiler **61/61**; guarded Edit two-script Source/class **2/2 exact**,
> current Studio Source fake slot/static probes `ok:true`. Bridge cannot
> inspect Play; no historical cost or fix attribution. See
> `docs/DAYPREP-WARNING-CONTEXT.md`.


> **Newest House exit candidate (2026-10-13):** Following the user's
> repeated no-exit House_01 Play, an unoccupied Braid indoors now scans
> circular physical rays **one per Think**, only after a completed local
> circuit, and exits solely through the authored main doorway with core-
> radius clearance from solid piers/placed original furniture. Real-map
> Edit Source probe `ok:true`, guarded changed Studio Source/class **2/2
> exact**, HouseAccess **45/45**, gate **36/36**, compiler **61/61**.
> **Human Play/actual timing pending.** New real Session:Slow (0.209 ms),
> DayPrep:Pulse (0.418/0.405/0.223 ms), Time:Publish (0.395 ms,
> attribute component 0.235 ms) warnings remain OPEN. See
> `docs/HOUSE-IDLE-EXIT-SWEEP.md`.

> **Newest human Play correction (2026-10-13):** Two Garage player entries
> are below the three-witness habit gate, not a fourth-visit verdict.
> House_01 Braid entry and closet dislodgement occurred; it **did not exit**
> this time, although the original furniture could be rebuilt on Day.
> The logged `Prey` stall was an earlier outside→inside closet crossing,
> not proof of the later exit blocker. Prior House_01 Play exit was real;
> current reliability is open. Read-only Studio follow-up found one narrow
> road ray close to an east pier, but cannot attribute the live no-exit.
> Subsequently, ONLY the existing once-per-cover-break Output line gained
> contact core/goal/reason/feet context (guarded two-script Edit sync,
> Source/class **2/2 exact**; cover **64/64**, gate **36/36**). No route,
> gait, furniture geometry or budget change; no human Play verdict on the
> contextual line. The bridge **cannot** inspect active Play. See
> `docs/PLAY-REPORT-2026-10-13-HOUSE01.md`.

**Start here for the current, readable plan:**
[`docs/ROADMAP-NOW.md`](docs/ROADMAP-NOW.md) separates verified local/Studio
work from human Play acceptance. Older chronological blocks below are a
build log; their test counts and "newest" labels are historical.

> **Newest Garage detour cost work (2026-10-13):** Six-node route still
> selects the same safe waypoint and same tie priority; rays for strictly
> noncompetitive exact-cost candidates are skipped. 720/720 cold analytic
> oracle waypoints match original exhaustive routing, 5,336→4,093 sampled
> rays with no per-case increase; 8/8 real-Garage Edit Studio-Source oracle
> parity. Navigation **25/25**, gate **36/36**, compiler **61/61**;
> guarded one-script Source/class **1/1 exact**. This is NOT measured Think
> budget compliance or fourth-visit human Play. See
> `docs/M3-GARAGE-ROUTE-COST-PRUNING.md`.


> **Newest bounded Think work (2026-10-13):** Lit-light and selected
> prey route branches now pass their actual same-Think obstruction hit into
> GarageNavigation rather than repeating the initial ray. Missing evidence
> still raycasts; all exterior-node safety tests remain. Navigation
> **23/23** shows cold detour 13→12 rays with a genuine known hit and same
> waypoint, senses **23/23**, full gate **36/36**, compiler **61/61**.
> Guarded Edit Source/class **2/2 exact**, real Garage-Barrel Studio-Source
> waypoint probe `ok:true`. Prior Think 8.313/1.000 ms remains unassigned;
> Play/budget acceptance OPEN. See `docs/M3-ROUTE-HIT-REUSE.md`.


> **Newest Think-cost preflight (2026-10-13):** Reuse the genuine
> selected prey's existing sensor clearance result in its immediate chase
> branch, rather than casting an identical segment twice. A missing result
> still triggers the original safety ray. Senses **23/23**, navigation
> **20/20**; its cold detour fan remains **13 rays** in the analytic fixture.
> Full gate **36/36**, compiler **61/61**; guarded Edit single-script exact
> Source/class and real Garage Source/door/static probes `ok:true`. Prior
> `Creature:Think 8.313/1.000 ms` is still real and **unattributed**, not
> declared fixed. See `docs/M3-SENSED-RAY-REUSE.md`.


> **Newest budget diagnostic (2026-10-13):** Future rare >4×
> `Session:Slow` warnings distinguish begin-round from ordinary running; rare
> `Creature:Think` warnings append server-only phase/decision/attack, no
> player coordinates. Detail is formatted AFTER the unchanged measured slot;
> the previous Time:Publish sections/budgets/warnings are untouched. Synthetic
> **7/7**, full gate **36/36**, compiler **61/61**, guarded Edit Source/class
> **2/2 exact**, actual Studio-Source branch probe `ok:true`. Historical
> 8.313/1.000, 0.204/0.050 and 0.389/0.050 ms overruns remain REAL and
> unassigned until active Play. See `docs/CADENCE-EXCEPTION-CONTEXT.md`.


> **Additional 2026-10-13 House_02 preflight:** Actual original closet,
> table and marker geometry were checked read-only in Studio/Edit against
> freshly compiled HouseCoverService Source. Valid reverse bracing, separate
> table lane, a genuine one-stud gap and clear original doorway returned
> `ok:true`; no Studio write or geometry adjustment. This is **not** a human
> House_02 exit or paid rebuild verdict. See
> `docs/HOUSE-02-EGRESS-EDIT-PREFLIGHT.md`.


> **Newest M3 side-route (2026-10-13):** Read-only real-map survey found
> a west/north/south Garage approach hit solid walls before reaching the
> east entrance. The witnessed Garage habit now takes separately guarded
> *existing exterior* corners before its original front→interior check;
> prey/lure/clue interruptions invalidate a held leg. One new habit ray per
> Think, zero on a held leg; blocked approaches defer safe patrol. Garage
> **63/63**, shadow **21/21**, gate **35/35**, compiler **61/61**. Guarded Edit
> changed Source/class **2/2 exact**; real Studio-Source 13-leg flank probe,
> old witness corridor and static verifier `ok:true`. Human Play and measured
> budget still OPEN. See `docs/M3-GARAGE-FLANK-ROUTE.md`.


> **Newest M3 preflight (2026-10-13):** A trained shadow transition row
> no longer presents possible-next classes for a **hidden** player. Last
> sampled class/time remain historical diagnostics. The Garage fixture now
> walks three continuous east-door visits rather than teleporting fake prey;
> a read-only Studio-Source probe checked 43 representative *offline* rays
> through the real entrance, then the fourth front→interior lead. Garage
> **47/47**, shadow **21/21**, gate **35/35**, compiler **61/61**, guarded Edit
> shadow module/dependency Source/class **3/3 exact**. Human Play and measured
> budgets still OPEN. See `docs/M3-EXPLAINABILITY-CORRIDOR.md`.


> **Newest M3 correction (2026-10-13):** Garage evidence can no longer
> bridge an **unseen** interval or interpret a roof→inside drop as a witnessed
> ground entry. Only consecutive sensed outside→inside samples train;
> learned run-local visits and accepted hunt remain unchanged. Garage
> **46/46**, shadow **19/19**, gate **35/35**, compiler **61/61**. Guarded Edit
> Source/class **2/2 exact** and real-Garage Studio-Source probe `ok:true`.
> Human fourth-visit Play and cadence budget still OPEN. See
> `docs/M3-GARAGE-WITNESS-CONTINUITY.md`.


> **Newest M3 foundation (2026-10-13):** An 8-location-class, **shadow-only**
> Markov observer is wired to *genuinely sensed* prey and ten existing tagged
> semantic map Zones; undertrained guesses are withheld in server-only AI dump.
> No posture inference, hidden GPS, steering or Q-learning. Shadow **19/19**,
> Garage **41/41**, gate **35/35**, compiler **61/61**, guarded Edit Source/class
> **2/2 exact**, real-zone Source probe `ok:true`. The fourth-visit human Play
> and measured budgets remain OPEN. See `docs/M3-SHADOW-PREDICTOR-SLICE.md`.


Iteration tracker. Status legend: ⬜ not started · 🟨 in progress · ✅ done.

> **Latest M3 safety regression:** Actual authored bell lure still
> preempts Garage habit; tested directly. Server-only AI dump priority prose
> now matches conditional lure radius and recent-clue order. No gameplay
> change. Garage fixture **41/41**, gate **34/34**, compiler **60/60**;
> guarded single-script exact Studio Source/class and static verifier passed.
> User still wants work before Play; habit acceptance/budgets pending.
> See `docs/M3-GARAGE-HABIT-SLICE.md`.

> **Newest pre-Play correction:** A Garage FRONT visit is not evidence
> its interior is empty. Read-only live map showed a real front→interior
> lane. Guarded-synced two physical waypoint legs (≤1 new ray per Think,
> blocked fallbacks deferred), lowered habit confidence only after an
> unproductive INSIDE check, never from a roof projection/blocked wall.
> Focused **40/40**, full gate **34/34**, compiler **60/60**. Vitriol/Edit
> previous Sources **2/2 exact**, final guarded readback **2/2 exact**;
> actual Studio-source interior/roof probe and static verifier passed.
> User said KEEP WORKING before another Play request. No fourth-visit Play or
> normal cadence acceptance; earlier real Think/Session/Time overruns open.
> See `docs/M3-GARAGE-HABIT-SLICE.md`. Older front-only text historical.

> **Newest pre-Play M3 hardening:** User said KEEP working on things first.
> A fruitless Garage prediction now lowers bounded witnessed-entry confidence,
> so the Braid does not recheck an empty Garage every Night; new genuinely
> witnessed evidence restores it, even after diagnostic counters saturate.
> Blocked access is not penalized; a sensed entry during a lead is a confirmed
> clue. Focused **30/30**, full gate **34/34**, compiler **60/60**. Vitriol/Edit
> prior affected Sources **2/2**, guarded updated Source/class **2/2 exact**;
> fresh Studio-source floor probe and static verifier passed. Session harness
> verdict made synchronous to avoid intermittent false-red gate summaries.
> Human fourth-visit Play and normal budgets still PENDING; existing one-off
> timing overruns open. See `docs/M3-GARAGE-HABIT-SLICE.md`.

> **Newest M3 roadmap slice (2026-10-13, Play PENDING):** User chose
> “Continue roadmap.” After three **genuinely witnessed** outside→inside
> Garage entries, clue-less Night Braid attempts the existing Garage front
> `(-55,-56)` before patrol; actual prey/lure/noise/recent clue retains
> precedence. One selection ray; no hidden-player GPS, wall phasing, gait or
> gameplay Instance changes. Server-only `CreatureService:aiDump()` explains
> witnessed evidence and goal; NOT leaked over rate-only public debug remote.
> Guarded Vitriol/Edit new ModuleScript + two affected scripts **3/3 exact
> Source/class** after **2/2** prior Source guard; fresh Studio-source real
> Garage ray probe and static verifier passed. Focused **25/25**, full gate
> **34/34**, compiler **60/60**. Human fourth-visit Play/full M3/normal cadence
> still PENDING; prior one-off Think/Session/Time overruns open. See
> `docs/M3-GARAGE-HABIT-SLICE.md`. Older notes below historical.

> **Latest one-off warning follow-up:** User saw the latest Time:Publish
> **0.389/0.050 ms only once**. A guarded Bootstrap-only Edit sync extends
> the existing >4× Time:Publish warning with same-sample attribute/remote
> timings, phase and sample number AFTER Cadence measures the cost; no budget,
> threshold or clock behavior change. Prior Source parity **2/2**, final exact
> Studio Source/class, static verifier and compiled Studio Source passed;
> focused synthetic **10/10**, gate **33/33**, compiler **59/59**. Next rare
> warning can be diagnosed even after Play stops. NOT a proven fix; prior
> measured overruns are not dismissed. See
> `docs/TIME-PUBLISH-DIAGNOSTIC-2026-10-13.md`. Previous block historical.

> **Newest budget investigation (2026-10-13):** User reported a REAL
> `Time:Publish 0.389/0.050 ms` overrun. Play had already stopped at the
> read-only probe. The frequency/cause is not established and no budget,
> warning or authoritative clock contract changed. A guarded TimeService-only
> Edit sync added 1 Hz attribute-vs-remote **section diagnostics**, including
> paired components of the peak sample; next Play may read them via
> `jobs/probe_creature_cadence_live_vitriol.lua`. Focused **9/9**, gate
> **33/33**, compiler **59/59**, exact Studio Source/class and fresh-compiled
> Studio source probe passed. This is NOT a performance fix and normal budget
> remains unproven; earlier Think/Session warnings also open. See
> `docs/TIME-PUBLISH-DIAGNOSTIC-2026-10-13.md`. Region/give-up Play acceptance
> remains valid; older notes below are historical.

> **Newest Play verdict (2026-10-13):** After regional patrol sync the user
> said **“Everything works perfectly, it knows when to give up as well.”**
> Accept the Night region-search/give-up feel in Play, **not** full M3,
> House_02-inside road egress or frame budgets. A read-only cadence probe
> returned `playing:false` before stats could be collected. Previously
> measured Creature:Think **8.313/1.000 ms** and Session:Slow
> **0.204/0.050 ms** overruns remain open; no budget change/suppression.
> Save/publish/Git push unconfirmed. See `docs/M3-REGION-PATROL-SLICE.md`.
> The pending candidate paragraph below is historical.

> **Newest M3 regional candidate (2026-10-13, Play PENDING):** User Play says
> the Braid keeps moving but circles one area too long. They selected changing
> regions after ONE local circuit. Four waypoints now derive from the current
> user-extended Road_Main (center Z=-16.5, Size.Z=593), not a hardcoded old
> road; safe direct legs only, max two new candidate rays/Think. Three
> affected scripts guarded Edit-synced with **3/3 exact Source/class**;
> fresh Studio Source walked road regions Z=-87.66→54.66; static verifier
> `ok:true`. Focused region **12/12**, full gate **32/32**, compiler **59/59**.
> **Not Play-accepted.** User saw ONE `Creature:Think` overrun 8.313/1.000 ms
> and separate Session:Slow 0.204/0.050 ms; both count as budget failures,
> cause unproven. Client UIInlineLayout warning attribution unclear. Next:
> fresh Play observe region transition AND real slot averages/peak; never
> suppress warnings or revise the accepted gait on a guess. See
> `docs/M3-REGION-PATROL-SLICE.md`. Older M3 blocks below are historical.

> **Newest M3 integration (2026-10-13, Play PENDING):** Legacy bridge verified
> connected Vitriol ID `92448193604950` in Edit mode. Guarded Brain Folder
> author 1 created, idempotent rerun 0/1; five game scripts guarded-synced,
> **5/5 exact Source/class checks**. Fresh compiled Studio search source plus
> real foundation `[-292,292]` passed read-only patrol/sweep/cover/edge probe;
> static post-sync verifier `ok:true`. Local search **19/19**, senses
> **20/20**, cover **63/63**, gate **31/31**, compiler **59/59**. User-confirmed
> Night-only always-hunting policy is now integrated as a candidate, **NOT
> visually Play-accepted or frame-budget-verified**. Save/publish and Git push
> unconfirmed. See `docs/M3-NIGHT-HUNT-SEARCH-SLICE.md`; the earlier local-only
> sections below describe history, not present sync status.

> **M3 Night hunt clarification and local follow-up (2026-10-13, Studio/Play
> PENDING):** User specified that the Braid should **always hunt at Night**,
> while remaining withdrawn during Day/Dawn. On losing valid prey, decoy,
> LastKnown and sound, it first checks around a genuine recent clue, then
> cycles a bounded patrol instead of standing idle. New numeric-only
> `Creature/Brain/InstinctSearch`, no live hidden GPS, through-wall/cover
> movement, chomp authority, new scheduler or gameplay Instances. No more
> than two new candidate rays per Think; authored foundation bounds when
> present. Focused search **19/19**, senses **20/20**, house-cover **63/63**,
> full gate **31/31**, compiler **59/59**. A guarded idempotent Brain-folder
> author job is prepared but NOT run. Legacy Studio bridge is unconfigured:
> **five game sources NOT synced or Play-tested**; frame budgets unmeasured.
> See `docs/M3-NIGHT-HUNT-SEARCH-SLICE.md`. This is NOT full M3 or a
> region-to-region patrol. Earlier 30/30 noise-only text below is historical.

> **M3 WP6 first local candidate (2026-10-13, Studio/Play PENDING):** The
> next code-owned milestone begins with real nearby VIBRATION investigation,
> *not* the full learning/predictor/policy milestone. Existing NoiseField now
> selects an emitted, unexpired, masked/thresholded signal within 32 studs;
> only an idle Night Braid targets its coarse eight-stud cell when sensed prey,
> lures and valid last-observed destinations have lost priority. A reached or
> inaccessible signal is ignored; no hidden live root GPS, wall phasing,
> chomp, furniture break, gait change or extra scheduler/Instances. Local
> senses **20/20**, cover **63/63**, full gate **30/30**, compiler **58/58**.
> No bridge connection in this shell: **not Studio-synced, Play-tested, saved
> or published**. See `docs/M3-NOISE-INVESTIGATION-SLICE.md`. Do not mark M3
> complete; its Garage-fourth-visit and AIDebugDump exits are still future.

> **House_01 exit accepted; roadmap continuation (2026-10-13):** User explicitly
> confirmed seeing the Braid leave after its closet dislodged. House_01
> entry/contact/break/exit is Play-confirmed; House_02 and paid rebuilding are
> not. Focused cover **63/63**, full gate **30/30**, compiler **58/58**.
> User requests roadmap features next; select one bounded M3/M5/M6 slice and
> preserve the accepted gait, doorway geometry and sensing limits. No bridge
> connection configured for the current shell; Studio changes require guarded
> Edit sync/readback and fresh Play. Older partial verdict below is historical.

> **Partial Play feedback (2026-10-13):** After reverse-egress sync, the user
> saw the furniture dislodge, but died before they could observe the Braid
> leave. On follow-up, they confirmed the Braid visibly reached/pushed the
> closet before it moved. **Contact→dislodgement is Play-observed; exit remains
> unverified.** Observe actual crossing when convenient; do not change code on
> an assumed defect. Added post-breach Think→Step control-flow regression
> for House_01 and a separate House_02 reverse closet/paid-Dawn regression;
> cover **63/63**, full gate **30/30**, compiler **58/58**; no game/Studio
> source changed. Earlier 2026-10-12 status below is historical.

> **Newest, Play pending (2026-10-12):** User confirmed Braid can ENTER the
> house after the height work, but it could not leave past House_01's moved
> closet; two `LastKnown` stall lines were geometry-probed as inside→outside
> crossings of that original 6-stud closet with four footholds. Narrow
> bidirectional cover contact now allows a nearby sustained exit breach for
> sensed prey or server-owned lure/unexpired last-observed destination,
> WITHOUT granting hidden-player GPS or a player Night release. Headless
> cover **63/63**, full gate **30/30**, compiler **58/58**, three guarded exact
> Studio source/class readbacks and fresh Studio-source reverse-contact probe.
> Exit/break requires fresh human Night Play; do not claim it solved.
> See `docs/HOUSE-EGRESS-CLOSET-SLICE.md`; older top blocks are historical.

> **Newest candidate, fresh Play needed (2026-10-12):** User Play found both-house
> cover entrance is passable for players, but the tall Braid climbed a roof and
> could not descend/enter. Geometry-driven `HouseAccess` now stages outside
> roof recovery, safe lowering beyond the eave, radius-aware Y≤10 clearance
> beneath the porch/lintel and east-door entry; main room restores normal
> height. Ceiling anchors are ignored only in the measured low passage, the
> approved horizontal foot-led gait/high-prey response remain. Roof slabs
> also block false sensing through roof and cannot be phased through by the
> anchored core. Local gate **30/30**, compiler **58/58**, focused access
> **37/37**, cover **50/50**; guarded Studio sync/readback **4/4 exact**;
> both houses' real geometry and fresh Studio-source probe passed. **Do not
> claim Play resolution** until user retests Night roof descent and doorway.
> See `docs/HOUSE-ACCESS-HEIGHT-SLICE.md`; prior current-state blocks are
> historical context.

> **Latest, Play pending (2026-10-12):** User chose individual run-long
> furniture cover at **both** houses: move the ORIGINAL table and closet to
> each main entrance through separate helper-voted Day prep (8/12 main seconds).
> Each retains its dimensions; cover is partial, not a sealed safe room. The
> nearby prey-driven Braid can dislodge only the contacted piece after 2.4 s;
> that piece can be moved back with a new paid action next Day. No manual Night
> release or current drag/weld system, per user choice. Editor-only authoring
> 13 created, rerun 0/12; read-only geometry verifier `ok:true`; guarded sync
> and **6/6 exact Source/class checks**; local gate **29/29**, compiler **57/57**,
> focused fixture **49/49**, including no-prey/charge anti-phasing,
> sustained-only pressure reset and occupied-doorway cancellation. The
> two-module follow-up was guarded-synced with exact readback. A further
> `CreatureService` frame-contact fix blocks kills through a low table without
> sealing the real gap; exact three-script readback and geometry verification
> passed. **Fresh Play
> has not happened**: inspect actual
> furniture movement, low table traversal and Braid contact before acceptance.
> See `docs/HOUSE-COVER-SLICE.md`. The bell/watch/light/church verdicts below
> remain historical Play-accepted context, not a Play verdict for house cover.

> **Current state (2026-10-12):** The user Play-confirmed the complete
> shared prep/floodlight/watch slice works. They next requested that the
> **user-owned** grounded Bell Model and its Rope rise together to the
> existing HoistPos **after** the bell prep fade; never recreate the old
> generated cylinder or alter their bell finish/tower. A guarded Edit-mode
> job attached only accepted bell Sound/PointLight (2 created, rerun 2 reused)
> to their MeshPart. A temporary 20-Hz, 2.4-s Cadence hoist moves their
> nested Bell Model and Rope together after fade clear; Dawn resets both.
> Guarded sync/readback **4/4 exact scripts**, nine non-map Studio verifiers
> pass. Local gate **25/25**, official compiler **55/55**, focused hoist **9/9**,
> full shared prep integration **42/42**. **Fresh Play verdict: “Works perfectly.”**
> Preserve the accepted bell/rope presentation; save/publish and measured
> frame time remain unconfirmed.
> Studio fast phases remain 45/11/30/30 (main 45/210/60/240); full audit
> separately blocks on Road_Main=593 vs old 560-stud baseline. Preserve both.
> See `docs/USER-BELL-HOIST-SLICE.md`; older milestones below are historical.

## Iteration 1 — foundations  ✅

Brainstorming, deep research, architecture, and a verified pure-code foundation.

| Deliverable | Status |
| --- | --- |
| `docs/00-VISION.md` — pillars, core loop, idea bank, scope | ✅ |
| `docs/01-ARCHITECTURE.md` — Explorer-first hierarchy, ownership, budgets | ✅ |
| `docs/02-MONSTER-DESIGN.md` — senses, memory, prediction, genetics, RL | ✅ |
| `docs/03-MONSTER-TECH.md` — FABRIK, rig, movement, replication | ✅ |
| `docs/04-KILL-CHOREOGRAPHY.md` — kill states, body integrity, gore contract | ✅ |
| `docs/05-SURVIVAL.md` — meters, coupling, debuffs | ✅ |
| `docs/06-DAY-NIGHT.md` — time model, keyframes, client-authoritative lighting | ✅ |
| `docs/07-DESTRUCTION-VEHICLES.md` — joint graph, integrity BFS, vehicles | ✅ |
| `docs/08-RESEARCH-NOTES.md` — sourced engine facts + gotchas | ✅ |
| `docs/09-HANDOFF-PROMPTS.md` — WP1–WP10 prompts | ✅ |
| `docs/10-HUMAN-AUTHORED.md` — specs for map/UI/meshes/audio (no code) | ✅ |
| `Lib/{MathExt,RNG,Fabrik,Genetics}` + `Shared/RegionIntegrity` | ✅ |
| `Config/{Game,DayNight,Monster,Survival,Destruction,Vehicle,Gore}Config` | ✅ |
| `tools/vitriol-smoke-test.js` + 78 runtime assertions | ✅ |

## Iteration 2 — pure layer, shared layer  ✅

Building the verified foundation outward, one work package at a time. Every module
below is *executed* by `tools/vitriol-smoke-test.js`, not merely parsed.

| Deliverable | Status |
| --- | --- |
| WP1 `Lib/Tables` — object pool (zero-allocation hot paths) | ✅ |
| WP1 `Lib/Signal` — connect/once/fire, safe disconnect during fire | ✅ |
| WP1 `Lib/Noise` — seeded value noise (permutation table) | ✅ |
| WP1 `Lib/SpatialHash` — fixed-cell spatial index + decay sampling | ✅ |
| WP1 `Lib/UtilityAI` — softmax option selection | ✅ |
| WP1 `Lib/QLearning` — linear Q, replacing traces, Boltzmann + instinct prior | ✅ |
| WP1 `Lib/MarkovPredictor` — player-pattern prediction + predictability | ✅ |
| WP3 `Shared/Skeleton` — flat-array joint chain, Fabrik-compatible | ✅ |
| WP3 `Shared/SkeletonCodec` — core-relative quantisation, DPCM feedback | ✅ |
| WP3 `Shared/NoiseField` — 6-channel decaying impulse field | ✅ |
| Harness: `require()` shim + multi-line `+=` support | ✅ |
| Runtime assertions at the end of iteration 2: 198 | ✅ |

## Iteration 3 — the server exists  ✅

The server foundation is complete and remains covered by the session harness. The
creature slice below is the current continuation.

The shared layer closed (WP3) and the server started (WP4), with both harnesses
executing real code. Everything below is *run*, not parsed.

| Deliverable | Status |
| --- | --- |
| WP3 `Shared/Remotes` — the only place a remote is created; `WaitForChild` + timeout on the client; polices `Comms` for strays | ✅ |
| WP3 `Shared/NetContract` — declarative schema per client→server message, token-bucket admission, monotonic-sequence replay guard; 400-payload fuzz | ✅ |
| WP3 `Skeleton:reset()` + rest pose (and a default chain built straight, not knotted) | ✅ |
| WP3 codec core orientation — 4×int8 quaternion, header 13 B, Braid snapshot 589 B; `docs/03` §7.1 corrected to agree | ✅ |
| WP3 buffer adapters in `Creature/Replicator` (not the codec) + executed array⇄Buffer parity proof | ✅ |
| WP3 `NoiseField` wind advection, weather masking, surface coupling — and `docs/02` §2 rewritten to match the ownership split | ✅ |
| WP3 round-trip test over **200 random chains**, max error 0.00820 studs vs the 0.02 budget | ✅ |
| WP4 `Services/CadenceService` — one Heartbeat-driven scheduler for all four cadences, staggered, slot-measured | ✅ |
| WP4 `TimeService` — clock *derived* from the phase machine (`DayNightConfig.RateCurve` deleted: an integrated clock and a paced phase machine drift apart) | ✅ |
| WP4 `SessionService` / `ThreatService` / `HealthService` + `Bootstrap` + `Main` | ✅ |
| WP4 `Diagnostics/Profiler` — per-cadence budget watchdog, auto-degrade one LOD tier | ✅ |
| WP4 `RemoteHandlers/{ClientIntentHandler,DebugHandler}` — validation applied; `RF_DebugQuery` is read-only by schema | ✅ |
| New gate: `tools/vitriol-session-test.js` (fake DataModel + virtual clock), 87 assertions | ✅ |
| 366 runtime assertions in the smoke test (was 198) | ✅ |
| WP2 remainder — `find-dead-config` still reports blocks whose readers arrive in WP5–WP10 (`Genes`, `Memory`, `Prediction`, `CollisionGroups`, `Tags`, `AnimationIds`, …) | ⬜ |

### Bugs found by writing the code (iteration 3, all fixed, all regression-tested)

| Where | What was wrong |
| --- | --- |
| `TimeService` | `clockMinutes` was computed with `minutesToClock(phaseClock(...))` — hours in, hours out, divided by 60 twice. A 6.66 h dawn reported as 0.11. The attribute contract (docs/06 §6, `0..1440`) is minutes, so the conversion is `clockToMinutes`. Found only by executing the service. |
| `TimeService` | called `noise:setWeather(kind, entry)` against a one-argument API; the entry landed in the wrong slot and the mask was indexed off a string. |
| `TimeService` | read `DayNightConfig.PhaseHours[phase]`, but that table is keyed `DayStart`/`DuskStart`/… — every lookup was nil. Fixed by routing all phase↔hour naming through `TimeModel.phaseSpan`, which also now *refuses* an unknown phase instead of silently answering Night. |
| `SessionService` | the injected logger field and the method were both called `log`, so the method resolved to the field and the field to the method: every log line became `[[vitriol]]` or a crash. The method is `emit` now, and the double-prefix bug it hid is gone. |
| `HealthService` | `killRegistered()` on a *player* death would have made dying make the hunt harder; the dial counts creatures the group killed. |
| `Bootstrap` | `stop()` left the noise-prune slot registered, so "stop cancels everything" was false. Asserted now (0 enabled slots after stop). |
| `DayNightConfig` | `RateCurve`'s mean 2.5 min/s (576 s/day) contradicted `Pacing`'s 555–735 s cycle: the sky and `PhaseName` would have disagreed within a minute of start. The table is deleted and the pace is `Pacing.Ease` instead. |
| `NoiseField` | advection sampled with a search window of wind × the channel's whole audibility lifetime — O(radius³) cells, and it hung the harness for 180 s (SCENT: 7 644 studs of span, 478³ cells). Now capped by `AdvectedMaxAge`, with the memory layer owning older evidence. |
| harness | the transform wrapped `for x in string.gmatch(...)` in `pairs(...)`, and stripped `: Type` annotations across a *call* line so `conn:disconnect()` became `conn()`. Both fixed in `tools/lib/luau-transform.js`, which is now shared by the two harnesses so they cannot disagree about what legal Luau is. |

### Bugs found by writing the code (all fixed, all now regression-tested)

| Where | What was wrong |
| --- | --- |
| `Lib/Noise` | xorshift32 used as a *lattice hash* collapsed to a near-constant (`value1(i)` spanned 0.0742–0.0816 over 64 samples — a dynamic range of 0.007). Replaced with a seeded permutation table. |
| `Lib/Noise` | the Fisher–Yates draw divided by 2⁴⁸ instead of 2³², so the shuffle was a fixed near-reversal. |
| `Lib/SpatialHash` | re-`insert`ing an existing id left `entries[id]` pointing at the old table with stale coordinates, while the cell index used the new ones. |
| `Lib/QLearning` | trace decay skipped the taken action, so stale eligibilities stayed pinned at 1.0 and credit flowed back at full strength forever. |
| `Shared/SkeletonCodec` | parent-relative quantisation (as originally specified in `docs/03` §7.1) costs 0.02748 studs at the tip vs a 0.00866 budget; switched to core-relative and corrected the doc. |

## Current continuation — playable procedural creature slice  🟨

This slice resolves the product decisions that were previously open: the Braid is
**woundable-only**, Threat 1 owns **one** creature, there is no cross-server species
evolution, and a victim watches the authoritative kill scene from their own head in
first person. The server remains single-authority and all gameplay cadence is still
owned by `CadenceService`.

| Deliverable | Status |
| --- | --- |
| `Creature/Body/TendrilRig` — numeric chains + constrained FABRIK + rest/noise pose | ✅ |
| `Creature/Body/Locomotion` — bounded ray fan, anchors, wall/ceiling up vector, open-ground glide | ✅ |
| `Creature/CreatureCore` — generated Braid Model/Parts, wound state, guarded `BulkMoveTo` | ✅ |
| `Services/CreatureService` — one-creature lifecycle, genome expression, cadence registration, target bridge | ✅ |
| `Creature/Body/KillChoreography` — cadence-stepped bounded victim scene | ✅ |
| `HealthService` — creature grab, player-only kill, optional dismemberment hook, Blood emission | ✅ |
| `Shared/BloodAdapter` + `BloodConfig` — LOW gate, bounded preauthored 24-part blood pool; BloodEngine inactive | ✅ source / ⬜ Play |
| `StarterPlayerScripts/.../VictimCamera` — local first-person victim presentation | ✅ |
| Replicator stream wiring / preauthored Braid parts | 🟨 — real `buffer`/Studio verification remains |
| Studio climb/ceiling proof, camera/audio/post-process polish | ⬜ — human verification required |
| Keyboard debug pilot | ⬜ — not needed for the one-player playable slice yet |

The Braid is posed by code but its **211 parts are authored in Studio Edit mode**,
not generated during Play. BloodEngine v1.1.3 source and `Assets.rbxm` remain
checked in but are inactive under the static-object policy; the adapter reuses
24 authored blood parts instead. Optional limb hiding is disabled by default
behind `BloodConfig.Dismemberment.Enabled`. See `INTEGRATION.md` for evidence.

### M2 — The body, no brain  🟨
`TendrilRig`, `Locomotion`, `CreatureCore`, part-mode renderer, and server spawn are
implemented. Studio acceptance is still open: a human must verify wall/ceiling
purchase, visual readability, and the 1.2 ms frame budget in a real place.

### M5 — The kill  🟨
The minimum server/client path now exists: a ground-level prey target triggers a
crouch/charge, and only verified post-charge contact starts `KillChoreography`;
`HealthService` owns player damage/death, BloodAdapter emits LOW/FULL
visuals, and `VictimCamera` is local-only. Full region-integrity choreography,
Grapple interactions, audio/post-process, and a real BloodEngine/Studio pass remain.

## Milestones

### M0 — Foundations ✅ (this iteration)
Design locked, pure math core executing under test, all tunables in Config.

### M1 — Shared layer + services skeleton (WP1–WP4) ✅ (iteration 3)
`Skeleton`, `SkeletonCodec`, `NoiseField`, `Remotes`, `NetContract`;
`CadenceService`, `SessionService`, `TimeService`, `ThreatService`, `HealthService`,
`Bootstrap`, `Profiler`, `ClientIntentHandler`, `DebugHandler`.
**Exit — met, and executed:** `node tools/vitriol-session-test.js` boots the real
`Bootstrap` on a fake DataModel with a virtual clock and asserts that a zero-player
server runs a full cycle, logs exactly one line per phase change with the elapsed time,
never touches `Lighting`, and registers exactly two `Heartbeat` connections (the
cadence pump and the watchdog). 87 assertions, 0 failures.

### M2 — The body, no brain (WP5) 🟨
The single-creature body uses a preauthored 211-part Braid model; server wiring is
present. The two-creature keyboard-pilot Studio exit is intentionally not claimed.
See `INTEGRATION.md` for the newer Edit-mode source/object parity evidence;
Studio Play remains unverified. See the continuation table
above for the verified headless scope.

### M3 — Instinct-only creature (WP6) 🟨
Bounded sensing/noise, last genuine clue → one local patrol circuit → new
region, a run-local Garage-entry habit, and a server-only explanatory dump
have scoped implementations and tests. A separate semantic-zone predictor
observes only genuinely sensed positions; it does not steer or enable Q.
This is **not** the complete `Senses`/`Memory`/`Predictor`/`Steering`/
`BehaviorTree`/`Tactics`/`Policy` milestone. **Exit still open:** make a
noise → it investigates in human Play; walk to the same Garage four times →
on the fourth it goes there *first*, with `AIDebugDump` explaining why;
verify normal Think budgets. See [`docs/ROADMAP-NOW.md`](docs/ROADMAP-NOW.md).

### M4 — Learning on (WP7) ⬜
`QLearning` wired in, episode serialization, species priors, A/B measurement.
**Exit:** capture rate over 20 simulated nights is measurably higher with learning
ON, and still below 1.0.

### M5 — The kill (WP8) 🟨
A minimum `KillChoreography`/`HealthService`/`BloodAdapter`/`VictimCamera` path is
implemented. Full Grapple, region-integrity choreography and Studio presentation are
still open; see the continuation table above.

### M6 — World interaction (WP9–WP10) 🟨 (selected slices only)
Day prep, the bell/light loops, barricade and two-house furniture-cover slices
exist; the approved Night/Day/dawn run rules are preserved. They do **not**
complete the original `DestructionService`, `VehicleService`,
`InventoryService`, `InteractionController`, `SurvivalService`,
`CreatureAudio` or `VibrationFx` work packages. The House_02 egress and
paid rebuild still need a separate human Play verdict.
**Exit still open:** all criteria in `docs/05` §7, `docs/06` §9 and
`docs/07` §6. See [`docs/ROADMAP-NOW.md`](docs/ROADMAP-NOW.md).

## Resolved product decisions

1. Monsters are **never killable**; they are woundable until `Threatening=false`.
2. Threat 1 owns **one** creature for the readable MVP.
3. Cross-server species evolution is **not** implemented.
4. A victim watches their own kill in **first person**; spectators retain third-person.
5. BloodEngine/Blood is the integration seam. The v1.1.3 source is checked in, but
   runtime still tolerates a Studio place that has not imported it; LOW stylised
   fallback remains bounded.
6. Limb dismemberment is optional and disabled by default through
   `BloodConfig.Dismemberment.Enabled`.

The only remaining decision is the human Studio/content pass, not the gameplay
authority or scope.

## Known gaps in this iteration

- The headless server path is live, but Roblox Studio has not been run here. A human
  must verify actual Part rendering, wall/ceiling raycasts, `BulkMoveTo`, real Buffer
  replication, the client camera, and audio/post-process presentation.
- BloodEngine v1.1.3 source and `Assets.rbxm` are now checked in under
  `code/ReplicatedStorage/VModules/BloodEngine` with its MIT notice. `BloodAdapter`
  probes `ReplicatedStorage/VModules/BloodEngine` first and accepts either a root
  ModuleScript or a Folder containing `init`; Studio import/layout and real visuals
  remain unverified.
- Full `Grapple`, region-integrity sever ordering, predator AI (`Senses`/`Memory`/
  `Steering`), survival, destruction, vehicles, and human-authored UI/audio remain
  later roadmap work. The current kill scene is intentionally a minimal playable seam.
- `tools/find-dead-config.js --src code` now audits all eight Vitriol config modules.
  It reports planned future-WP tables such as `MonsterConfig.Memory`/
  `Prediction`, `GameConfig.AnimationIds`/`Tags`, and destruction/vehicle/survival
  tables as dead until their readers land; verify before removing them.
- `tools/check-syntax.js` fails on `Lib/RNG.luau` and `Lib/Noise.luau`: luaparse is a
  **Lua 5.1** parser and cannot read bitwise operators. Both files, plus the new
  choreography, are executed for real by the smoke/session harnesses. The new
  quality gate allowlists exactly those two paths and fails on any new one.
- `tools/vitriol-quality-gate.js` is the strict future-agent command; it runs the
  smoke/session tests, all requested reports, model evaluation, and `git diff --check`.
- The project remains Explorer-first. `tools/validate-project.js` is retained for
  legacy Rojo checkouts but `tools/audit.sh` skips it when no `default.project.json`
  exists; no Rojo project is to be created merely for tooling.

## Latest validation snapshot — 2026-09-09 UTC

- `node tools/vitriol-smoke-test.js`: **366 passed, 0 failed**.
- `node tools/vitriol-session-test.js`: **87 passed, 0 failed**; includes creature
  spawn, bounded victim scene, first-person event payload, player-only death, wound-only
  creature disablement, and no extra scheduler.
- `node tools/check-syntax.js code`: **43 files parse**; the two known Lua 5.1 parser
  exceptions remain `Lib/RNG.luau` and `Lib/Noise.luau` (bitwise `&`).
- `node tools/metrics.js --src code`: **45 files; LOC 10993 | code 8001 | comments
  2125 | exports 381 | requires 35**.
- `node tools/hot-loop-scan.js --src code`: **Priced calls 31 | inside-a-loop 8 | in
  a RunService file 0**; the extra loop flag is the kill-only limb lookup.
- `node tools/call-graph.js --src code`: **45 modules | 381 exports | 35 require
  edges**; includes the BloodAdapter/CreatureService/kill/camera edges.
- `node tools/find-dead-config.js --src code`: audits all eight Vitriol config modules;
  reports planned future-WP keys such as `MonsterConfig` AI/memory/prediction,
  `GoreConfig` body-integrity, `GameConfig` animation/tag settings, and
  destruction/vehicle/survival tables as verify-before-removing candidates.
- `node tools/vitriol-quality-gate.js --src code`: **9/9 checks passed**, including
  both harnesses, all static reports, model evaluation, and `git diff --check`.
- `node tools/evaluate-models.js --models tools/models.example.json --suite
  tools/evaluation-suite.example.json`: `fixture-known-good: ADMIT 100.0%`,
  `candidate-local: REJECT 0.0%`.
