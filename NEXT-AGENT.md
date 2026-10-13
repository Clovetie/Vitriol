# Vitriol — closed-loop prompt for the next iteration

## 2026-10-13 NEWEST — DayPrep warning path context, Play unavailable

User cannot test now. Investigated real recent server warnings:
`DayPrep:Pulse 0.418/0.050` at House_01 closet move,
`0.405/0.050` at table move, `0.223/0.050` at Night; separate
`Session:Slow 0.209/0.050 (begin-round)` and `Time:Publish
0.395/0.050 (attributes 0.235, remote 0.022)` remain real OPEN overruns.
Client `[Arena] poll failed` is not a Vitriol server cadence timing. New
same-slot DayPrep path labels (action, before→after stage, hum branch) are
set in its **existing** 0.25s slot; Bootstrap formats only an exceptional
>4× warning AFTER cadence timing. No budget/threshold/clock/prep-vote
change. Focused synthetic **10/10**, full gate **36/36**, compiler **61/61**.
Guarded Vitriol/Edit prior Bootstrap + DayPrepService full Sources/classes,
wrote only those two, final Source/class **2/2 exact**. Fresh actual Studio
Source compiled/ran real DayPrep callback against Lua-only fixture `ok:true`;
static `ok:true`. Bridge **cannot** inspect Play. Neither labels nor fixture
attribute cause to a specific engine call or fix the historical warnings.
See `docs/DAYPREP-WARNING-CONTEXT.md`; current exit sweep still needs human
Play. Do not ask for a new test until user is ready.


## 2026-10-13 NEWEST — time-sliced circular House exit, Play pending

User reported **again** House_01 Braid could not leave. Existing contextual
break Output `core(-74.4,9.8,76.1) nav(-87.0,78.0)
reason=genuinely-sensed-prey feet=4` was at contact while core was
**outside/east** of door X=-79; it does not explain later exit. User asked
for a circular raycast when enclosed and NOT chasing. Added bounded radial
HouseAccess:sweepExit only for grounded Braid inside House_01/02 after one
completed no-clue local patrol circuit: 16 spokes TIME-SLICED, ≤1 new ray
per Think, hold clear exit waypoint, real physical ray + core-radius pier and
placed-table/closet aperture checks, inner-stage if corner-blocked, fail
closed if both pieces leave only 1-stud gap. Same gait/map; no hidden GPS,
new scheduler/Instance or budget change. HouseAccess **45/45**, cover
**64/64**, Garage habit **62/62**, full gate **36/36**, compiler **61/61**;
guarded Vitriol/Edit prior HouseAccess and CreatureService Source/class,
changed only those two, final Source/class **2/2 exact**. Current Studio-
Source read-only actual House_01 door and cover-state branch `ok:true`,
static `ok:true`; see `docs/HOUSE-IDLE-EXIT-SWEEP.md`. **No human Play/feet
exit or normal Think budget acceptance yet.** The user's real new
Session:Slow **0.209/0.050** (begin-round), DayPrep:Pulse **0.418,
0.405,0.223/0.050**, Time:Publish **0.395/0.050** (attributes 0.235,
remote 0.022) warnings remain OPEN. Studio bridge cannot inspect live Play;
request Roblox Output/visible motion, never `PLAY LIVE` bridge probe.


## 2026-10-13 NEWEST — Roblox Output at actual furniture break, no live bridge

User corrected: **Studio bridge does not support live Play**. Removed the
proposed live-bridge snapshot job and changed the Play checklist to request
Roblox Output and visual movement only. To avoid another informationless
post-break report, appended `core(X,Y,Z) nav(X,Z) reason=... feet=N` to the
**existing single** `Braid dislodged House_01 Closet; paid Day move required`
Output line, only at a real break. No new ray, cadence slot, runtime Instance,
route, geometry, gait, warning share or periodic logging. House-cover
**64/64**, gate **36/36**, compiler **61/61**. Legacy bridge used ONLY in
Edit, verifying prior full `CreatureCore` (m3-region source) and
`HouseCoverService` (house-egress source) exact, then guarded-synced those
two Sources; final Source/class **2/2 exact**. Fresh real Studio-Source
read-only Lua-table branch probe logged exactly once without touching
furniture (`house-break-output-live-source.json`, `ok:true`); static `ok:true`.
No active Play verdict yet; this line describes CONTACT, not a later failed
exit. Read `docs/PLAY-REPORT-2026-10-13-HOUSE01.md` and the revised
`docs/NEXT-PLAY-CHECKLIST.md`. If post-break failure recurs, user sends
new break line + any subsequent Output warning and visible location; do NOT
ask for a bridge Play probe.


## 2026-10-13 NEWEST — new House_01 no-exit Play report, no guessed fix

User attempted Garage player entries **2/2** (three genuine witnessed entries
required for habit); no fourth-choice verdict. In House_01, Braid entered and
physically dislodged original closet (`13:50:44.900`), paid rebuild worked,
**but it did NOT exit this run** despite an earlier successful House_01
Play exit. Supplied `pursuit stall Prey core(-73.5,78.3) goal(-88.7,77.4)
nav(-87.0,77.4) feet=4 block=...House_01_Closet` is an earlier **outside
→inside** crossing of marker X=-81.5, not post-break exit evidence. Play
stopped; no post-break pose/reason/timing available. Two READ-ONLY Studio/Edit
source/real-geometry probes `ok:true`: sampled inside (-91,77) gave clear
road transit (0,54.66), while one different near-pier sample had a thin
clear ray only 0.38 studs from the east pier, below nominal core radius.
That risk is **not** attributed to user's actual post-break pose. No game
source/map/gait/budget changed. **User corrected that the Studio bridge does
NOT support live Play**. The proposed bridge live-snapshot job was removed;
request actual Roblox Output and visual position after the closet break,
never a `PLAY LIVE` bridge request. Read
`docs/PLAY-REPORT-2026-10-13-HOUSE01.md` and updated
`docs/NEXT-PLAY-CHECKLIST.md`; do NOT declare current House_01 exit
reliable, and do NOT treat 2/2 Garage entries as habit failure. Last full
quality gate from prior unchanged game source **36/36**, compiler **61/61**.


## 2026-10-13 NEWEST — cold Garage route exact-cost lazy clearance

The six-node Garage route now prunes clearance rays **only after** a cheaper
physically verified pair wins; each rejected pair has an exact graph cost
that cannot beat that winner. Original order, strict-tie selection, endpoint,
boarded-gate, cache and no-path behavior remain. Independent 720-case
exhaustive oracle: **720/720 identical waypoints**, **5,336→4,093** analytic
rays total, none increased; center cold route 13→11 (prior real-hit route
12→10). Navigation **25/25**, senses **23/23**, Garage habit **62/62**, full
gate **36/36**, compiler **61/61**. Guarded Vitriol/Edit prior Source/class,
only GarageNavigation changed, final Source/class **1/1 exact**. Fresh Studio-
Source probe compares **8/8 physical Garage** start/goal cases with exhaustive
baseline, including generator endpoint and actual rear barrel → front door;
static verifier `ok:true`. See
[`docs/M3-GARAGE-ROUTE-COST-PRUNING.md`](docs/M3-GARAGE-ROUTE-COST-PRUNING.md).
This is a ray count, **not** a real Play Think ms verdict. All three earlier
one-off cadence overruns, human fourth Garage visit and House_02 exit remain
open; save/publish and Git push unconfirmed.


## 2026-10-13 NEWEST — selected-prey/light detour reuses physical hit

`GarageNavigation:route` used to reray the exact **blocked** start→goal
segment already measured in the same selected-prey or lit-light lure Think.
It now optionally consumes that **actual RaycastResult**; missing evidence
uses the original physical ray, and all twelve authored-node candidate rays
remain guarded. The established front detour/cover/endpoint rules are
unchanged. Navigation **23/23**: cold 13 rays without prior hit; cold 12
with real hit, same waypoint; invalid hit fails closed. Senses **23/23**,
Garage habit **62/62**, shadow **21/21**, full gate **36/36**, compiler
**61/61**. Guarded Vitriol/Edit prior and final GarageNavigation/
CreatureService Source/class **2/2 exact**. Fresh Studio-Source probe hit
the real Garage barrel then reproduced the identical front detour; static
verifier `ok:true`. See
[`docs/M3-ROUTE-HIT-REUSE.md`](docs/M3-ROUTE-HIT-REUSE.md).
This is NOT measured Think compliance. The earlier 8.313/1.000 ms warning,
other one-off cadence warnings, fourth-Garage-visit Play and House_02 exit
remain open; no warning/budget was hidden or changed.


## 2026-10-13 NEWEST — one redundant sensed-prey ray removed

`_nearestTarget` already ray-checks its selected, genuinely sensed living
root. The immediate prey branch had cast the **same** ray again. It now
reuses the actual clear/blocked result (including close thermal-through-prop
being blocked for contact); a missing fourth return takes the old safety ray.
Headless real-service senses **23/23**, navigation **20/20**, Garage habit
**62/62**, shadow **21/21**, full gate **36/36**, compiler **61/61**.
Guarded Vitriol/Edit `CreatureService` previous Source/class then single-script
exact readback, actual Studio-Source compile/door ray and static verifier
`ok:true`. Cold `GarageNavigation:route` is separately measured at **13 rays
in its analytic first-detour case**; no claim the old 8.313/1.000 ms Think
warning is fixed or that normal Play meets budget. No map/gait/priority change.
See [`docs/M3-SENSED-RAY-REUSE.md`](docs/M3-SENSED-RAY-REUSE.md).


## 2026-10-13 NEWEST — rare Think/Session warnings get same-sample context

The real past one-offs `Creature:Think 8.313/1.000 ms`,
`Session:Slow 0.204/0.050 ms` and `Time:Publish 0.389/0.050 ms` remain
UNATTRIBUTED. Future **exceptional** Think warnings now append server-side
phase/decision/attack; Session warnings append the measured tick's own path
(`begin-round` vs `running`, etc.), post-tick state and phase. Formatting is
AFTER Cadence clocks the original whole-slot cost. No player coordinates,
new ray/job, budget increase or warning suppression. Synthetic exceptional
fixture **7/7**, unchanged Time profile **10/10**, full gate **36/36**,
compiler **61/61**; guarded Vitriol/Edit old Sources then changed
Bootstrap/SessionService **2/2 exact Source/class**, fresh Studio-Source
branch probe/static `ok:true`. See
[`docs/CADENCE-EXCEPTION-CONTEXT.md`](docs/CADENCE-EXCEPTION-CONTEXT.md).
No actual Play timing acceptance, fourth-Garage-visit verdict, House_02
human exit, save/publish or Git push is claimed. User asked to keep working.


## 2026-10-13 NEWEST — independent House_02 Edit preflight

User requested continued work. A **read-only** freshly compiled Studio
`HouseCoverService.Source` probe used the user's original House_02 closet,
table and markers: original Part locations unchanged; inside→outside closet
contact/bracing recognized, wrong-direction lure rejected, table independently
recognized, real one-stud gap remains open, and a ground-height ray through
the original east-door lane is structurally clear. The Studio/Edit result and
static verifier returned `ok:true`; no Source or map write was made. This
strengthens the existing headless House_02 cover case but is NOT a human
footed exit/paid rebuild Play verdict. See
[`docs/HOUSE-02-EGRESS-EDIT-PREFLIGHT.md`](docs/HOUSE-02-EGRESS-EDIT-PREFLIGHT.md).
Latest game-source work remains Garage flank **62/62**, shadow **21/21**,
full gate **35/35**, compiler **61/61**. House_01 exit is Play-accepted;
House_02 is not. Three real one-off cadence overruns remain open.


## 2026-10-13 NEWEST — Garage remembered approach from actual map sides

A read-only Vitriol/Edit survey found that a fourth-visit lead begun west,
north or south of the user's Garage would hit a solid wall and give up.
`GarageHabit` now follows separately ray-guarded **existing exterior nav
corners**, then the original front→physical interior leg. One new habit ray
per Think, none on a held leg; obstruction defers local patrol to the next
Think and never counts as a miss. Real prey, lure, last-known/noise, recent
clue and roof recovery invalidate a cached leg so resumption rechecks it.
Garage **62/62**, shadow **21/21**, full gate **35/35**, compiler **61/61**.
Guarded Edit `GarageHabit`/`CreatureService` Source/class **2/2 exact**;
untouched shadow exact; actual real-wall Studio-Source probe `ok:true`
(13 exterior/interior legs, blocked House_01 wall); original three-entry
witness corridor and static verifier still `ok:true`.
Read [`docs/M3-GARAGE-FLANK-ROUTE.md`](docs/M3-GARAGE-FLANK-ROUTE.md).
No human fourth-visit or cadence acceptance. Do not modify Play-accepted gait,
regional hunt, House_01 egress or user's geometry. Earlier three overruns,
save/publish and Git push remain open. User asked to continue working, not
another immediate Play request.


## 2026-10-13 NEWEST — diagnostic freshness and real door preflight

Continued offline M3 work without asking for Play. A trained shadow row no
longer displays a "trusted" possible-next class after its survivor is hidden;
`lastClass` is explicitly historical and `lastSampleAt` marks its sample.
The fourth-Garage-visit headless service fixture now walks each entry across
the actual floor threshold instead of teleporting its fake player, and a
**read-only Studio/Edit** Source/geometry probe found all 43 representative
east-door corridor rays clear for three walking visits. Garage **47/47**,
shadow **21/21**, full gate **35/35**, compiler **61/61**. Guarded Edit
shadow-only sync with **3/3 exact Source/class readback** (two dependencies
untouched), Studio-Source trained-hidden regression and static verifier
`ok:true`. Details: [`docs/M3-EXPLAINABILITY-CORRIDOR.md`](docs/M3-EXPLAINABILITY-CORRIDOR.md).
Still NO human fourth-visit or measured cadence verdict, no Q-learning, no
new in-game ray; earlier overruns and save/publish/Git push remain open.


## 2026-10-13 NEWEST — reject unwitnessed Garage entries (Play pending)

Garage evidence now **requires consecutive grounded, genuinely sensed**
outside→inside samples from the same player. Losing sight even one Think,
switching to another prey, or seeing a roof-level survivor clears only the
*unfinished* entry witness; learned completed visits remain run-local. This
closes a false positive in the still-unaccepted Garage preference without
changing physical front→interior routing, lure/prey precedence, accepted
Night search, map, gait or rays. Garage **46/46**, shadow **19/19**, gate
**35/35**, compiler **61/61**; guarded Vitriol/Edit changed-script Source/class
**2/2 exact**, fresh actual Garage Studio-Source probe and static verifier
`ok:true`. Details: [`docs/M3-GARAGE-WITNESS-CONTINUITY.md`](docs/M3-GARAGE-WITNESS-CONTINUITY.md).
The user requested continued work, not another Play request yet. Human
fourth-visit and cadence-budget verdicts remain open; do not claim M3 complete.


## 2026-10-13 NEWEST — authored-zone shadow predictor, no steering or Play claim

User said **KEEP WORKING**, not to ask for Play yet. Ten existing tagged semantic
Zones were surveyed in Vitriol/Edit. `ShadowPredictor` now records only
consecutively *genuinely sensed*, per-player 8-location-class transitions and
reports guarded Markov probabilities via **server-only** `aiDump`, after at least
12 transitions *from* the sampled class. It does not infer posture, inspect
hidden roots, supply a target, change Garage or patrol priorities, add rays,
cadences or gameplay Instances. Focused shadow **19/19**, Garage **41/41**,
full gate **35/35**, compiler **61/61**; guarded new ModuleScript + service
Studio Source/class readback **2/2 exact**, actual ten-zone Studio-Source probe
and static verifier `ok:true`. Read [`docs/M3-SHADOW-PREDICTOR-SLICE.md`](docs/M3-SHADOW-PREDICTOR-SLICE.md).
Human fourth-visit Play and real Think/Session/Time budget attribution remain
OPEN; save/publish/Git push unconfirmed. Preserve all accepted behavior.


## 2026-10-13 NEWEST — M3 diagnostic priority checked; user still wants work first

The Garage-habit headless fixture now explicitly verifies an authored bell
lure outranks the learned Garage route; focused **41/41**, gate **34/34**,
compiler **60/60**. Server-only `aiDump` priority prose was corrected to the
actual conditional lure radius and recent-clue-before-habit order (previous
string implied all sensed prey always outranks lures, which was inaccurate).
Guarded Vitriol/Edit previous `CreatureService.Source` exact before this
one-script change; final exact Source/class readback and static verifier
passed (`tools/reports/m3-ai-dump-priority-source.json`). No movement, gaze,
geometry, budget or public debug remote changed. Earlier physically tested
Garage front→interior Source/readback still valid. User has said KEEP
WORKING rather than requesting Play. Human acceptance of this new habit and
normal cadence budgets remain pending; one-off real Think/Session/Time
warnings unresolved. `docs/M3-GARAGE-HABIT-SLICE.md` is current.

## 2026-10-13 NEWEST — Garage physical interior evidence, not exterior guess

User: “KEEP WORKING.” A read-only actual Studio survey found front Garage
`(-55,-56)`→inside floor center `(-90,-56)` physically clear, Roof at Y=19.
The prior newly added negative-memory candidate treated reaching the FRONT
as evidence the room was empty; that was unjustified. Replaced with two
separately cleared legs (road→front→actual interior). Front arrival, a solid
inner barrier or a roof-height Braid do **not** count as a miss. Only an
unproductive physical interior check softens bounded confidence. Each leg
uses ≤1 NEW ray on selection, zero while held; blocked fallback is deferred
one Think so no 1+2-ray burst. Fresh prey/lure/noise, cover, Day withdrawal,
user gait and existing region patrol unchanged. Test fixture **40/40**, full
gate **34/34**, compiler **60/60**, Vitriol/Edit prior exact Source guard
**2/2**, guarded final `GarageHabit`/`CreatureService` readback **2/2 exact**;
fresh actual Studio Source tested BOTH clear legs, roof refusal, no exterior
miss, miss only inside, later witnessed recovery. Post-sync static `ok:true`.
**Human Play of this new habit and normal cadence NOT requested/verified**;
user explicitly wants further work first. Single Think, Session, Time:Publish
measured overruns remain unresolved. See `docs/M3-GARAGE-HABIT-SLICE.md`.
Older “empty front check” notes below are superseded.

## 2026-10-13 NEWEST — Garage habit now learns from an empty guess; Play still pending

User explicitly asked **KEEP working on things first**, not another immediate
Play ask. The newly authored M3 Garage habit initially rechecked Garage every
Night after three witnessed entries even if repeated visits were fruitless.
A narrow follow-up adds bounded (0–3) actionable confidence: witnessed entry
raises it; reaching an empty Garage front lowers it; merely blocked access
does not. A newly sensed entry during a lead confirms it without a miss. One
bad guess prevents repeated future Night trips until new **actually seen**
evidence restores confidence, even after visit counters cap at 12. Accepted
search/gait and prey/lure priority unchanged. New tests **30/30**; gate
**34/34**, compiler **60/60**. The session-test harness now writes its final
summary synchronously (preventing an intermittent false gate failure from
console.log immediately preceding process.exit). Vitriol/Edit prior Source
re-guard **2/2**, only `GarageHabit`/`CreatureService` updated, **2/2 exact
Studio Source/class** readback; fresh Studio-source real Garage probe confirmed
miss→no next-Night retry→new witnessed entry restores preference, static
verifier `ok:true`. **No human fourth-visit Play or normal-budget evidence**.
See `docs/M3-GARAGE-HABIT-SLICE.md`. Do not ask for Play before doing any
more locally available roadmap work unless user decides; save/publish/push
unconfirmed. Older entry below predates this follow-up.

## 2026-10-13 NEWEST — M3 witnessed Garage habit Edit-synced; Play pending

User chose “Continue roadmap.” Built one bounded instinct-only M3 slice:
`Creature/Brain/GarageHabit` counts ONLY genuine sensed outside→inside
Garage-floor transitions (not hidden player GPS); after **three** witnessed
entries, clue-less Night search tries the existing Garage **front approach**
`(-55,-56)` before ordinary patrol, with one new safety ray on selection,
none while held, safe fallback for cover/wall/stall, and preserved prey/lure,
last-seen, real-noise and fresh-clue priority. Evidence survives Day only
for this run, not DataStore. A read-only `CreatureService:aiDump()` explains
visits, threshold, decision reason and goal. Access it only via server-side
`jobs/ai_debug_dump_vitriol.lua` DURING Play; do not expose hidden route via
rate-only public RF_DebugQuery. No gait, map or runtime Instance changes.

Garage test **25/25**, region **12/12**, senses **20/20**, cover **63/63**,
full gate **34/34**, compiler **60/60**, diff check clean. Vitriol/Edit
preflight matched `MonsterConfig`/`CreatureService` prior Studio Sources
**2/2**, Brain Folder existed and new ModuleScript did not. Guarded sync of
ONLY `MonsterConfig`, new authored `GarageHabit`, and `CreatureService`, then
**3/3 exact Source/class readback**. Read-only fresh Studio-source/actual
Garage geometry probe passed: floor center `(-90,-56)` size 56×46, safe
road→front approach `(-55,-56)`; static verifier `ok:true`.

**Human fourth-visit Play NOT YET DONE**, full M3 policy/AIDebugDump designer
UI not complete, normal cadence budgets not proven. Latest Time:Publish warning
once 0.389/0.050 ms, earlier Think/Session warnings still open; no warning
suppression/budget raise. Fresh Play must confirm three genuinely *seen*
Garage entries (visible departures between), then no higher-priority cues and
front Garage preference; server-only AI dump may explain. See
`docs/M3-GARAGE-HABIT-SLICE.md`. Save/publish/Git push unconfirmed.

## 2026-10-13 NEWEST — one Time warning; rare-spike log now self-describes

User clarified the reported `Time:Publish 0.389/0.050 ms` warning appeared
**ONE time** in that Play, not every second. It remains a real 7.78× budget
overrun, source unknown. Because Studio was stopped before live cadence probing,
I added a narrow `Bootstrap` exceptional-warning suffix **only for
Time:Publish**: the next original >4× warning will include the same slot's
attribute/remote section times, phase and sample count. The warning is logged
after Cadence times the slot; threshold, budget and all other warning messages
are unchanged. Headless synthetic remote spike proved the full original warning
and suffix appear; focused attribution **10/10**, gate **33/33**, compiler
**59/59**. Vitriol/Edit **2/2 prior Source parity** before Bootstrap-only
guarded sync, exact Studio Source/class readback, fresh Studio Source compile
and final static verifier `ok:true`. **Do not claim the warning is fixed**:
user's earlier 0.389 ms line predates the suffix, and no fresh Play latency
measurement exists. Next real warning can be copied after Play stops, or leave
Play active to use `jobs/probe_creature_cadence_live_vitriol.lua`.
See `docs/TIME-PUBLISH-DIAGNOSTIC-2026-10-13.md`. Accepted Night roaming/give-up
still stands. Save/publish/Git push unconfirmed. Older entries historical.

## 2026-10-13 NEWEST — Time:Publish 0.389/0.050 ms diagnostic synced

The user reported `01:36:11.219 [vitriol] warn: cadence Time:Publish took
0.389 ms against a 0.050 ms budget - Server - Bootstrap:74` and asked to
keep working. It is a real 7.78× overrun; recurrence in this session and cause
unknown. A read-only cadence probe returned `playing:false`, so no Play
measurements were captured. Edit-only attribute-read and pure-model microbench
calls were tiny (~0.00018/0.00027 ms each) but cannot measure engine writes,
network broadcast, or scheduler stalls. Do NOT "fix" by raising budget,
suppressing warnings, removing required time sync or assuming the Braid caused
it. Prior Think/Session overruns remain unresolved.

A narrow, allocation-free 1 Hz **section diagnostic** was added ONLY to
`TimeService`: scheduled publish now records attribute and remote timings,
peak's paired components, samples and over-budget count; immediate prep/fade
publication is unaffected. Existing 9-argument sync and 0.050 ms Cadence
share unchanged. Focused virtual-time profile **9/9**, full gate **33/33**,
official compiler **59/59**. Vitriol/Edit prior entire TimeService Source
matched exactly before guarded write, then final Studio Source/class exact
readback, fresh Studio-source compile/probe and final static verifier passed.
**Live latency cause/performance improvement UNPROVEN.**
`jobs/probe_creature_cadence_live_vitriol.lua` reads `timePublish` Cadence
stats and `timeSections` while human Play is ACTIVE; ask user to leave Play
running ~30–60 s / across a warning and capture both, plus Think/Session.
`docs/TIME-PUBLISH-DIAGNOSTIC-2026-10-13.md` has evidence and next actions.
Regional hunt/give-up human acceptance still stands. Save/publish/Git push
unconfirmed. Older newest entries below are historical.

## 2026-10-13 NEWEST — region hunt Play-accepted; timing unmeasured

After the guarded region-patrol sync, user reported **“Everything works perfectly, it knows when to give up as well.”** Treat Night regional roaming and give-up feel as **human Play-accepted**. Do not extrapolate this to every road/House_02 interior route, full M3 learning or normal frame-budget compliance. A read-only bridge call to `jobs/probe_creature_cadence_live_vitriol.lua` found `playing:false` (Play already stopped), so live slot average/peak/skipped counts were NOT collected. Prior user logs contain genuine `Creature:Think 8.313/1.000 ms` (one observed) and `Session:Slow 0.204/0.050 ms` overruns; they remain unresolved, not suppressed. On next ordinary Play, if still running, get read-only cadence stats before any new performance claim. No new code or Studio writes after this Play verdict. `docs/M3-REGION-PATROL-SLICE.md` is the current evidence. Save/publish and Git push unconfirmed. Older “Play pending” below is historical.

## 2026-10-13 NEWEST — road-derived region patrol guarded-synced; Play pending

User Play-confirmed the Night Braid **keeps moving**, but said it stays in one
region too long. They chose **switch regions after one completed local four-point
circuit**. User also supplied measured `Creature:Think 8.313/1.000 ms` (only
one such warning observed) and `Session:Slow 0.204/0.050 ms`; both are real
budget overruns, cause not established, NOT suppressed. Client
`Unknown class "UIInlineLayout"` is a separate warning, not yet attributed.

Read-only live road survey found Road_Main center `(0,-16.5)`, `Size.Z=593`
(the user's intentional edit). New InstinctSearch derives four road goals
Z≈-212.19/-87.66/54.66/179.19 from that actual Part and leaves the local
region after one circuit. Candidate selection costs ≤2 new rays/Think,
never crosses a solid wall or placed furniture, and caches an active route.
After reaching a road region it starts a new local hunt. When all legs are
blocked it patrols locally rather than wall-phasing; sampled House_02 inside
has NO clear direct road line, so do not claim cross-town exit from there.
No hidden-player GPS, new scheduler, geometry, manual Night release or gait
change. Local region fixture **12/12**, search **19/19**, senses **20/20**,
cover **63/63**, full gate **32/32**, compiler **59/59**. Guarded Vitriol
Edit-mode sync of ONLY `MonsterConfig`, `CreatureCore`, `InstinctSearch`
after prior exact-source guard; **3/3 exact Source/class readback**.
Fresh Studio Source probe traversed first road region Z=-87.66 then Z=54.66;
post-sync static verifier `ok:true`. See `docs/M3-REGION-PATROL-SLICE.md`.

**Human Play of regional travel and frame budgets PENDING.** Next Play observe
one local circuit→road destination→new local sweep; note the current region,
especially House_02 interior, and first stall line if any. A read-only
`jobs/probe_creature_cadence_live_vitriol.lua` can report avg/peak/sample
counts for Creature:Think and Session:Slow while Play is active; do NOT call
budgets green without measurement. UIInlineLayout is unresolved but not
assumed to be the cause of server timing. Studio save/publish and Git push
unconfirmed. Older M3 entries below are historical.

## 2026-10-13 NEWEST — M3 Night hunt + vibration guarded Edit-synced; Play pending

User-provided legacy bridge reconnected to **Vitriol place ID `92448193604950`**, Studio connected and `RunService:IsRunning()==false`. Read-only static verifier and four-piece cover verifier passed. Before mutation, exact live `CreatureCore`/`CreatureService` matched the prior House_01 readback; `MonsterConfig` and `NoiseField` matched local pre-M3 source after stripping only the new M3 lines. No unrelated user Studio edits overwritten. Guarded `jobs/author_instinct_brain_folder_vitriol.lua` created 1 Folder; rerun 0 created/1 reused, inspect confirmed Folder. Five new/changed sources (`MonsterConfig`, `NoiseField`, `InstinctSearch`, `CreatureCore`, `CreatureService`) guarded-synced and **5/5 exact Source/class readbacks**; current Studio `InstinctSearch.Source` fresh-compiled in a read-only probe against actual foundation bounds `[-292,292]` (no-clue patrol, clue sweep, cover avoidance, edge clamp `ok:true`). Post-sync static verifier `ok:true` (7 remotes, 211 Braid parts, 24 blood parts). Separate read-only real-geometry rays verified a clear FIRST patrol leg at road, garage bay, House_01 inside and House_02 inside (`tools/reports/m3-patrol-geometry.json`, `ok:true`); this is not proof of a full Night route. Local search **19/19**, senses **20/20**, cover **63/63**, full gate **31/31**, official compiler **59/59**, diff check clean.

**Human Play and normal `Creature:Think` frame-budget compliance are STILL PENDING.** Fresh Play (not cached Edit `require`) should verify Night-only last-clue sweep→reachable bounded patrol, real emitted-noise response, Day/Dawn withdrawal, fresh prey/decoy precedence, and no wall/cover phasing or hidden live GPS. If physically stuck, capture first stall/obstacle and whether it kept a patrol goal; do not change approved gait or geometry on a guess. Studio save/publish and Git push unconfirmed. Full M3 learning, region-to-region patrol, Garage-fourth-visit and AIDebugDump remain future work. See `docs/M3-NIGHT-HUNT-SEARCH-SLICE.md`. The earlier *local-only* blocks below are historical.

## 2026-10-13 Night-only always-hunting requirement — LOCAL candidate only

User clarified they want the Braid hunting at **Night**, not during Day/Dawn;
when no valid target/clue remains, **sweep around the last genuine clue then
follow a bounded patrol**. Implemented local numeric `Creature/Brain/InstinctSearch`
plus `CreatureService` fallback and `MonsterConfig.InstinctSearch` readers,
with a dormant-state reset in `CreatureCore`. Fresh prey, server decoys, valid
last-seen memory, emitted noise and roof recovery have priority; patrol cannot
read hidden live player position, damage installed furniture, chomp, cross
solid walls, change approved gait or add runtime game objects/schedulers.
Candidate selects no more than two new rays per Think. Search **19/19**,
senses **20/20**, cover **63/63**, full gate **31/31**, compiler **59/59**,
whitespace clean. Guarded, idempotent Edit-mode Brain-folder author job is
written but **UNRUN**. No legacy bridge URL/token in this shell: **five** local
game sources are NOT in Studio; no exact readback, Play acceptance, publish,
normal-frame budget verdict or Git push. Next safe boundary: verify place and
Edit mode, run `jobs/author_instinct_brain_folder_vitriol.lua` (rerun 0 created),
guarded-sync/read back the five scripts listed in
`docs/M3-NIGHT-HUNT-SEARCH-SLICE.md`, and request fresh Night Play for actual
search movement, Day withdrawal, obstruction safety and measured budget. Do
not claim region-to-region hunting or full M3's fourth-Garage-visit learning.

## 2026-10-13 M3 first roadmap candidate — local only, NOT Studio-synced

The user requested roadmap features after confirming House_01 egress. A bounded
instinct-only noise investigation is implemented in local `NoiseField`,
`MonsterConfig`, `CreatureService` with tests: only an emitted, recent VIBRATION
within 32 studs can redirect the otherwise idle Night Braid to a coarse
8-stud cell. Sensed prey, bell/light, and unexpired last-observed target win;
blocked/reached impulses are ignored, no hidden player live GPS, manual Night
cover breach, wall phasing, chomp, gait changes or new Instances/scheduler.
Focused senses **20/20**, cover **63/63**, full gate **30/30**, official compiler
**58/58**, diff check clean. **No legacy Studio bridge URL/token in this shell**:
none of these three game sources was synced/read back, and there is NO Play
verdict or normal-budget verdict. Before any Play request, confirm Vitriol place
ID and Edit mode, guarded-sync only the three Source changes and read them back
exactly. Do not claim full M3 (Garage-fourth-visit, semantic memory/policy debug
remain). See `docs/M3-NOISE-INVESTIGATION-SLICE.md` for bounded scope/checklist.

## 2026-10-13 accepted exit; start roadmap work cautiously

After the earlier death-limited observation, the user explicitly confirmed **they saw the Braid EXIT House_01 after it dislodged the closet** (“It works” → “Yes, I saw it exit”). This closes that specific Play acceptance criterion. It does **not** prove House_02 Play, paid Dawn rebuilding, normal frame-budget compliance, Studio save/publish or Git push. Focused house-cover **63/63**, full gate **30/30**, compiler **58/58**; no new game or Studio changes since the 3/3 source sync. User next said “Let's start working on the roadmap features.” Start with one bounded roadmap slice rather than free drag/weld, general pathfinding, Q-learning or a runtime asset batch. `docs/HOUSE-EGRESS-CLOSET-SLICE.md` has full context. No bridge URL/token is configured in this workspace shell; do not claim another Studio sync without confirmed bridge/place/Readback.

## 2026-10-13 partial Play update — furniture moved; Braid exit unobserved

After the guarded-synced reverse-egress fix, user reported: “It dislodges itself and im pretty sure it can exit now; I couldn't test it cause I died before getting to.” Record the closet/furniture dislodgement as observed, **not** the Braid's completed exit. In follow-up the user explicitly confirmed **Braid visible contact before the closet moved**; contact→dislodgement has Play evidence. No new stall line or error was provided. When feasible, observe the Braid actually cross outside after the piece returns home (from safe/teammate viewpoint if available). Test-only follow-up: House_01 next Think and three deterministic Core steps continue outward toward valid memory; an independent House_02 inside→outside remembered-goal case breaks only its own original closet and leaves both tables intact through Dawn. Cover **63/63**, full gate **30/30**, compiler **58/58**. **No game-source or Studio edits** in this follow-up. Preserve code; do not invent a movement fix on partial evidence. `docs/HOUSE-EGRESS-CLOSET-SLICE.md` has the evidence and checklist. The 2026-10-12 section below is the prior state.

## NEWEST — House_01 reverse closet egress, guarded-synced; fresh Play pending (2026-10-12)

User Play-confirmed that the Braid **can enter** after the prior height work, but said House_01's closet did not seem to break and it was hard for the Braid to LEAVE. Two verbatim server `pursuit stall LastKnown` warnings have core `(-91.7,79.4)`→goal `(-57.5,78.9)` and core `(-90.9,78.3)`→goal `(-63.9,77.9)`, each blocking on `Workspace.Map.Interiors.House_01_Closet`, feet=4. Guarded real-geometry reconstruction showed both paths start INSIDE the house and cross the placed original closet's marker plane X=-81.5 at Z≈79.25/78.16 (within the actual Z=74..80 span), only 10.2/9.4 studs away. The old `HouseCoverService` allowed outside→inside contact only, so the anchored body could not ghost out yet never built breach pressure. **No gait or house geometry problem was proven by these lines.**

`HouseCoverService` now intercepts/physically braces from either side. Freshly sensed prey allows either direction; an existing server light/bell lure or **unexpired LAST-OBSERVED** position may authorize a sustained **inside→outside-only** 2.4-second push when the exact furniture is within 12 studs. No remote closet damage, no far hidden live GPS, no player Night release, no new Instance/scheduler. The damaged original Part returns home and alone can be rebuilt via paid Day prep; other furniture survives Dawn. See `docs/HOUSE-EGRESS-CLOSET-SLICE.md`.

Focused cover **63/63** (both exact user log rays, real CreatureService Think and Core step through breach/exit), house access **37/37**, full gate **30/30**, official compiler **58/58**. Guarded Edit-mode sync of **3** affected modules, **3/3 exact Source/class readback**. Fresh Studio Source compiled read-only and reproduced both reverse contacts; four-piece geometry verifier passed. **At this 2026-10-12 sync, Night Play of Braid EXIT/break was pending; the newer 2026-10-13 update above confirms contact→dislodgement, but NOT the completed exit.** If it remains stuck later, get the FIRST new `pursuit stall` line and whether the closet actually moved. The earlier roof-to-door candidate has only partial Play acceptance (“can enter now”); visible roof descent and both houses were not explicitly judged. Preserve accepted church/light/watch behavior, fast test phases, user Road_Main=593 and station switch Z=-111. Save/publish, Git push, normal frame time unconfirmed. Older sections below are historical.

## NEWEST — Braid house roof/doorway height fix, guarded Edit synced; Play pending (2026-10-12)

User's first house-cover Play finding: **“They can enter through the entrance but the monster cannot physically enter; its too high ... climbed up onto the roof and couldnt get down.”** A guarded real Studio geometry survey measured both houses' doorway lintel bottom Y=12, porch underside Y=12.5, house roof underside Y≈16.3, and verified clear roof→outside/porch/doorway and west-flank rays plus an exterior vertical descent. New `Creature/HouseAccess.luau` derives body-radius-aware low clearance from authored geometry, recovers a roof-bound Braid to clear sky before bounded descent, stages a real east-entry route, allows normal height again under the higher indoor roof, prevents roof phasing and rooftop sensing of a hidden indoor player's live coordinates. Existing Locomotion's **horizontal planted-foot gait/chase pace and high-prey response are unchanged**; only an under-ceiling vertical cap/overhead-anchor filter activates locally. Bracing now targets the actual entrance waypoint for sensed prey behind cover. No geometry or gameplay Instances were created in Play. `docs/HOUSE-ACCESS-HEIGHT-SLICE.md` has the scope and checklist.

Focused HouseAccess **37/37**, HouseCover **50/50**, prep integration **43/43**, full gate **30/30**, official compiler **58/58**. Four modules guarded-synced in Edit mode with **4/4 exact Source/class readback**; a near-door edge follow-up initially returned write done while readback still held old Source, then a guarded re-sync and final **4/4 exact** readback passed. Freshly compiled Studio Source (not cached Edit-mode `require()`), real geometry probes and furniture verifier passed both houses. **User has NOT tested this fix in fresh Play**. Ask for Night Braid rooftop descent and physical entrance/indoor-height verdict at either/both houses before calling it solved. If it still climbs or stalls, request FIRST `pursuit stall` line and visible Braid height/location, then stop Play for a narrow fix. Never claim general pathfinding, normal frame budget green, save/publish or Git push. Older house-cover section below records the pre-fix state.

## CURRENT house-furniture slice — Edit mode integrated, HUMAN PLAY PENDING (2026-10-12)

After user Play acceptance of the watch, garage light repair/refuel loop, fair
unobstructed/thermal sensing and the bell-to-lights sequence (a brief three-second
pause still exists), the user chose a new run-long project at **both houses**:
move each ORIGINAL table and closet separately to its east-facing doorway.
Use the existing three-real-second prep vote and shared Day charge (table 8,
closet 12 main seconds), retain their actual sizes so the low table and a real
one-stud gap do not become a fake sealed room, keep cover through Dawn/death
until that specific item is broken by a nearby prey-driven Braid, then allow a
new paid Day move. The user **rejected a manual Night release** and explicitly
reserved player dragging/welding for future work. No runtime game/UI Instances.
`docs/HOUSE-COVER-SLICE.md` records source, geometry, full test and Play checklist.
Guarded Edit-mode author first 13 created, idempotent rerun 0 created/12
reused; read-only verifier `ok:true`; six changed/new game sources synced with
exact Source/class readback, focused fixture **49/49** (including actual
CreatureCore interception, lost-prey/charge solidness, non-accumulating contact and occupied-doorway cancellation), full local gate **29/29**, compiler **57/57**. After the first six-module sync, a separate guarded two-module CreatureCore/HouseCoverService hardening sync received **2/2 exact Source/class readback** and the live read-only house verifier passed again. An additional headless-red/green test exposed a low-table through-cover contact kill even when body motion was blocked; a guarded **single-module CreatureService** sync now gates actual frame-contact kills by the existing piece footprint, while preserving the real gap. Exact readback of all three relevant scripts and a further live read-only geometry verifier passed.
**No fresh human Play verdict yet.** Ask for one table and closet in Day at both
houses, Braid approach to sensed player inside at Night, Dawn persistence and
paid rebuild after break. Never claim general dragging, sealed safety, smooth
house routing or proof of physical doorway traversal. User-selected station
switch Z=-111; fast Studio phases and Road_Main=593 remain untouched. Cadence
slot overruns, measured normal frame time, save/publish and Git push unconfirmed.
Older headings below are historical and include superseded Play-pending claims.

You are continuing **Clovetie/Vitriol `main`**, not Tunneling. The user approved the Braid’s foot-led gait and crouch-charge-chomp. Build the game **slowly**, in testable roadmap slices, using `docs/10-HUMAN-AUTHORED.md` for bespoke map/UI/audio requirements. **Do not create Vitriol UI or game objects during runtime.** Roblox engine-owned player characters are the exception; Vitriol’s geometry, GUI, effects and props must be authored in Studio Edit mode. Do not invent mesh/sound asset IDs.

## Latest user-bell visual request — EDIT MODE SYNCED, PLAY-ACCEPTED

The user Play-confirmed the previous prep/floodlight slice: **“Everything works now, awesome.”** New request: their bell is on the ground, and its existing Rope must **rise with the user-owned Bell model toward HoistPos only AFTER the prep fade**. Read `docs/USER-BELL-HOIST-SLICE.md`. Read-only Studio survey found exact paths `Workspace.Map.Interactions.Bell.{Bell (nested Model with Bell MeshPart + bering), Rope (Part), HoistPos (Part)}`. The old generated `Church_Bell` Part is no longer in Studio; do not recreate it. Guarded Edit-mode authoring added only accepted Sound/PointLight onto the user's MeshPart (2 created, rerun 2 reused), preserving geometry/finish. Runtime code captures authored ground CFrames, uses a temporary 20-Hz slot in existing Cadence to ease the nested model **and rope by identical offset** to fixed HoistPos over 2.4 seconds after `PrepCoordinator` fade-clear; Dawn lowers both, Night ringing waits if the bell is still rising. The accepted SoundId `130139735590457`, three pulses and Braid lure priority remain. Temporary frame share 0.05 ms. Local gate **25/25**, compiler **55/55**, old bell **19/19**, hoist **9/9**, full prep path **42/42**, original session **145/145**. Guarded sync/readback **4/4 exact class/source** for GameConfig, DayPrepService, PrepCoordinator and Bootstrap; all nine non-map Edit-mode verifiers pass. Full audit still blocks on unrelated Road_Main 593 vs old 560; 55-script parity only Studio fast DayNightConfig and whitespace-only VictimCamera drift. **Fresh Play verdict:** the user said **“Works perfectly.”** Preserve the user-owned bell/rope animation and accepted earlier prep/floodlight/watch behavior. This is not a measured FPS, individually counted sound strikes or save/publish result. Save/publish, Git push and measured frame time remain unconfirmed.

## Latest station/shared-prep slice — Edit-mode synced, FRESH PLAY PENDING

The user accepted the hold-T wristwatch, then requested a repairable station floodlight and a 3-real-second nearby-helper window on **every** Dawn/Day prep, including fuel pickup, with up to 2 main-pacing seconds saved, all-client fade and one authoritative shared Day charge. Garage boarding costs 20 s at main's 210-s Day. Earlier switch was `(-62,4.2,-110)`; the user later explicitly chose to keep the live `(-62,4.2,-111)`; bell lever is `(119,2.5,-210)`. `docs/STATION-PREP-WATCH-PLAN.md` has the full current behavior, evidence and fresh Play checklist.

**Completed this turn:** Five original action prompts now call the server-owned `PrepCoordinator`; five preauthored helpers volunteer only during the matching vote. Server checks living/nearby/registration, specific action availability and changes at commit, uses absolute `Workspace:GetServerTimeNow()` for three real seconds despite Cadence skips, and clamps scaled cost at Dusk or reserves it from upcoming Day at Dawn. Existing `RE_TimeSync` carries an optional ninth timestamped fade-stage field; the new client `PrepFadeController` changes only the authored Frame, with no runtime UI/Camera/Tween. One authorized world effect and clock skip happen at blackout. `FloodlightService` repairs preauthored switch/beam, turns it on at Night, hums in EM/AIR and supplies a weaker fallback Braid lure than accepted bell/generator; close prey overrides it. Dawn resets it; Night garage emergency unboarding remains instant/free. No new heartbeat, remotes or runtime game Instances.

**Evidence:** local gate **24/24**, compiler **55/55**, original session **145/145**, coordinator **40/40**, real prompt integration **39/39**, 11-second-Day **8/8**, clock/transport **20/20**, fade client **18/18**, delayed boot **1/1**. User **explicitly approved restoring the accepted local WatchController source** after Studio had reverted to the old infinite-wait script; GUI layout was not changed. Guarded Edit-mode sync completed for **11** changed/new scripts, all **11/11 exact sources and classes** read back. Updated client-boot and other **nine** independent structural verifiers passed. Full audit still stops at `Road_Main.Size.Z=593` versus 560-stud map baseline; do not change user geometry. Separate parity for all **55** scripts finds only intentional Studio `DayNightConfig` and two blank lines in Studio `VictimCamera`. Studio test pacing Source currently **45/11/30/30**, NightPerThreatSeconds 15 (local main 45/210/60/240, 45), unchanged here. Edit-mode require() has returned stale timing/controller modules; **fresh Play is essential**. Do not claim fresh Play acceptance, frame time, save/publish or Git push. **First fresh Play of this slice failed before the vote:** Studio Output reports `FindFirstPlayerByUserId is not a valid member of Players` from `PrepCoordinator:48`, also found in `FloodlightService`. Both now use the real `Players:GetPlayers()` identity scan; the fake API was removed from the headless harness. Focused integration **39/39**, fast Day **8/8**, coordinator **40/40** and official compiler **55/55** reran green; after user stopped Play, guarded Edit-mode sync/readback passed for both corrected ModuleScripts. The `[Arena] poll failed: Http requests can only be executed by game server` warning is bridge-plugin client Output, separate from Vitriol. **Next action:** ask user to start another fresh Play session and report watch, fuel/helper vote, both-client fade, Day clock cost, station Night beam/AI and any client/server Output. Do not claim success from the failed first Play.

## Previous bounded day-prep choice: church bell (2026-10-12) — PLAY-ACCEPTED PRESENTATION

The user **confirmed the garage barricade gets broken now** in Play, chose **one new daytime preparation choice**, selected the church bell, and supplied audio asset `130139735590457` (the clip itself has three strikes). `DayPrepService` now primes exactly one signal during Dawn/Day, then after a three-second Night delay plays the preauthored Sound **once**, flashes the authored light three times and lures a distant Braid for twelve seconds. Living prey within 30 studs overrides it; the accepted garage generator lure resumes afterward. The approved gait and Tool-storage rule are unchanged. Guarded Edit-mode `jobs/author_church_bell_vitriol.lua` authored five existing-use objects at the church (second run **0 created/5 reused**); read-only verifier `ok:true`; no runtime Vitriol Instances. Focused bell tests **19/19**, full gate **18/18**, official compiler **50/50**, editor jobs compiled. Vitriol place `92448193604950` was verified in Edit mode; guarded sync of `DayPrepService` and `CreatureService` completed, **2/2 ModuleScript classes and exact sources** read back, and a fresh-Source read-only Studio probe bound the authored bell and user-provided SoundId. Full audit ran **seven** verifiers and checked all 50 classes but correctly fails on the **one user-approved Studio-only `DayNightConfig` fast-test timing difference** (5/10/10/30 vs local main 45/210/60/240). Do not overwrite it until the user says Play testing is finished; do not claim full parity. **Fresh Play verdict:** “The bell is audible and it flashes properly, everything works perfectly.” Preserve the accepted presentation and gameplay; exact pulse counts, garage-generator fallback, Dawn reset and measured frame time were not separately reported. Save/publish and Git push unconfirmed. For future regression checks, observe Night one-time activation, far-Braid diversion and close-player priority, generator fallback, Dawn reset, Output and `DayPrep:Pulse` profiler. See `docs/CHURCH-BELL-SLICE.md`.

## Previous gate-foot-contact fix (2026-10-12) — BREACH PLAY-CONFIRMED

The user confirmed the garage path detour works, but the first near-core gate-breach repair **still failed in Play**: tendrils hold the Braid's body farther than five studs from the boarded gate. `Locomotion` now records each existing raycast anchor's hit Instance; `BarricadeService` accepts pressure from a more distant core ONLY if a tendril anchors to the **exact authored gate** while pursuing a live target through the bay. `CreatureCore` passes these cached footholds without moving the body or changing the approved foot-led gait/pace. A floor/wall foothold, no target or same-side/side-wall target cannot break the gate. Headless barricade **23/23** proves real Locomotion anchor caching and sustained zero-translation CreatureCore breach from >10 studs back; local gate **17/17**, Luau compiler **50/50**. Bridge checked Vitriol place `92448193604950` and Edit mode, then guarded-synced ONLY `Locomotion`, `CreatureCore` and `BarricadeService`; **3/3 exact classes and sources** read back. A read-only Edit-mode source probe against the real authored gate confirmed gate-foot positive and remote/same-side negatives. Full Studio audit ran six authored verifiers and checked all 50 classes, then refused the **one intentional Studio-only DayNightConfig source difference**: fast Play phases 5/10/10/30 versus local main 45/210/60/240. User said leave short test phases until testing ends, then return them. Do not overwrite them or claim full parity; stale green report was removed. **The user subsequently confirmed the barricade gets broken in Play**, a narrow breach verdict. Exact timing, inside exit and Dawn reset remain individually unobserved; frame time, save/publish and Git push unconfirmed. Further garage checks can accompany bell Play rather than blocking the next chosen slice. Check server Output for the **once-per-breach** `Braid bracing boarded garage gate` line followed by `Braid breached the garage barricade`; also check inside exit and Dawn reset. If still stuck, observe whether an actual tendril is on the gate versus a side post/floor before adjusting the gate rule. Do not alter the approved gait or grant the stored Tool. Read `docs/BARRICADE-SLICE.md`.

## Previous near-core breach fix (2026-10-12) — SYNCED, BUT INSUFFICIENT IN PLAY

The user confirmed **the garage detour no longer gets stuck** in Play, but reported that the **boarded garage barricade would not breach**. The old CreatureCore only built pressure if its *core translation* crossed the gate plane; foot-led motion can stall short of the gate with zero translation. `BarricadeService:pressing` now admits only a nearby (within 5 studs), through-bay, opposite-side chase target; `CreatureCore` builds pressure on that idle foot-led frame while still blocking any step through the boarded gate. Distant/same-side/side-wall targets do not accrue pressure. No gait, approved pace, Tool grant, new Instance or authored geometry was changed. Focused garage barricade **18/18** includes zero-delta CreatureCore frames breaching after ~2.4 seconds and no-target pause; full local gate **17/17**, official compile **50/50**. The bridge confirmed place `92448193604950` in Edit mode; guarded-synced **only** `CreatureCore` and `BarricadeService`, then read their ModuleScript classes and exact sources back. A read-only predicate check against the actual gate geometry passed. The full Studio audit **failed on one unrelated, intentional source difference**: Studio `DayNightConfig` uses 5/10/10/30-second phases for rapid Play testing, while local main uses 45/210/60/240. The user said **keep the short Studio phases until testing is finished, then return them**. Do not overwrite that edit now or misreport 50/50 full parity; the prior green report was removed. The six authored verifiers and 50 script-class checks completed before the parity failure. **Subsequent Play showed this near-core fix was insufficient: the tendrils hold the body too far back.** The gate-foot-contact fix above is now the pending Play experiment; no measured frame-time evidence, save/publish or Git push. Keep the Tool stored pending an agreed unlock. See `docs/BARRICADE-SLICE.md`.

## Previous garage-navigation fix (2026-10-12) — SYNCED AND PLAY-CONFIRMED

The user played and found that the Braid went *inside* the garage while chasing them *outside behind it*, then repeatedly pushed into the rear wall. `GarageNavigation.luau` and `CreatureService.luau` now route grounded prey around that authored garage, with wall-height line-of-sight checks preventing through-wall chomp preparation/contact. They read the existing map and create **no runtime Instances, PathfindingService Paths or new map assets**; the approved foot-led gait and Night pace code are untouched. The gate and placement services still own boarding/breach. A **real Edit-mode geometry probe** found `Garage_Barrel_2` is the first ray hit before `RearWall`, so the initial module missed this obstruction. Corrected/resynced it. A read-only probe compiled the final synced Source (not cached `require()`) and confirmed targets open front `(-55,-56)` → north `(-55,-86)` → rear `(-125,-86)` → direct player `(-145,-56)`. Focused garage and service-think tests **16/16**, full local gate **17/17**, official compiler **50/50**. The bridge verified Vitriol place ID `92448193604950` and stopped Play; guarded sync completed. Read-only Studio audit **six verifiers `ok:true`, 50/50 script classes and 50/50 sources, zero drift** (`tools/reports/studio-audit.json`). This is garage-specific, not town-wide pathfinding or measured performance. **The user later confirmed the Braid no longer gets stuck in that garage chase.** The separate boarded-gate breach initially failed; the later gate-foot repair was narrowly confirmed to break the gate in Play. Save/publish and Git push remain unconfirmed. Read `docs/GARAGE-NAVIGATION.md`; keep the Tool in storage pending an agreed unlock.

## Previous budget-scoped change (2026-10-12)

Added a read-only, fail-closed `tools/vitriol-studio-audit.py` for the exact Studio place in Edit mode: six authored verifiers, every Vitriol game script class and full source readback. Its previous live run passed **six verifiers, 49/49 classes, 49/49 sources, zero drift** (`tools/reports/studio-audit.json`). Added five credential-free success/failure-path tests to the local gate and documented the command in `tools/README.md` and `.agents/skills/vitriol-studio/SKILL.md`. After restoring generated dependencies, the full local gate passed **16/16**, including those **5/5** offline tests, placement **17/17** and official compile **49/49**. The live audit was **not rerun after the documentation/tooling changes**; no game source or Studio object changed during this follow-up. This is not fresh Play or save/publish evidence. Next: fresh human Play of the separate garage gate, with Output and collision/breach/inside-exit/Dawn-reset observations; then agree a small unlock/crafting slice before granting the still-stored Tool. Avoid a speculative gait change or a claim of measured frame-time improvement. Git push and Studio save/publish remain unconfirmed.

## Previous budget-scoped change (2026-10-12)

Normal Play has zero manually placed boards while the Tool stays in storage, so the Braid should not pay 60 Hz board-intersection calls. `CreatureCore` and `CreatureService` now guard against the empty placement pool (and idle garage gate) before intersection; focused placement regression **17/17** asserts no idle frame-path call and an actual active-board CreatureCore frame still blocks movement/starts breach pressure. Full gate **15/15**, official compile **49/49**, guarded Edit-mode Studio parity **49/49 zero drift**. This is *not* measured Studio frame-time evidence. Do not change the approved gait or claim the isolated earlier cadence overrun fixed. Fresh Play of the standalone garage gate remains next, then ask the user before a bounded crafting/grant slice. No Tool has been granted. Save/publish and Git push unconfirmed.

## Immediate continuation / budget boundary (2026-10-12)

The user asked to keep working **without overbudgeting**, and to pass the work to the next agent/iteration if necessary. Rather than starting a broad crafting system, the latest small change secures the *single preauthored, still-dormant* `BarricadePlankTool`: `HealthService:wipeInventory` invokes a pre-wipe callback that returns that exact Tool to `ServerStorage.Vitriol.Tools` before destroying ordinary carried Tools; `BarricadePlacementService` also reclaims it on disconnect. Focused placement test **17/17** covers death and disconnect (plus socket/free placement); full gate **15/15**, official compile **49/49**, Edit-mode static/tool verifiers and Studio source parity **49/49 zero drift**. No crafting grant or live Tool Play verdict exists. User's previous visible garage fuel/night loop was praised; standalone garage barricade is synced but has **not** had a fresh Play verdict. Next agent: start with a fresh Play check of that gate (boarding, inside exit, Braid brace/breach, dawn reset) and exact client/server Output. Only then agree one bounded crafting recipe or other small slice with the user; the user skipped a prior priority selector, so do not assume permission for a full crafting/inventory system. Preserve no-runtime-object policy and approved Braid motion. The place is not confirmed saved/published, and Git has no configured remote. Read `docs/BARRICADE-TOOL.md` and `docs/BARRICADE-SLICE.md`.

## Current continuation: stored manual barricade Tool (2026-10-12)

The user chose a Tool version supporting **both authored openings and free placement**, with the Tool **kept in storage until crafting**. One Tool/Handle and eight board Parts with release prompts are preauthored under `ServerStorage.Vitriol`, with two house-doorway sockets and an empty placed-board folder under `Workspace.Map`. `BarricadePlacementService` is wired to the dormant Tool, validates ownership/phase/range and moves existing Parts from the finite pool, prioritizing authored sockets then short-range level Map surfaces. Boards can be released or breached by the Braid and reset at Dawn. The Tool is **not** in StarterPack and no runtime grant/crafting exists. Read `docs/BARRICADE-TOOL.md`. Do not clone Tools/boards or claim a live Tool Play verdict; the headless fixture's test-only equip is not Roblox Play. Local gate **15/15** (366 smoke, 145 original session, 14 day-prep, 15 garage barricade, 17 placement, 1 client boot, 49 official compiler). Author job idempotent (second run 0 created/24 reused), Studio tool/static/map/day-prep/barricade verifiers passed, guarded parity **49/49 zero drift**. The current standalone garage gate still needs a fresh Play verdict (breach, tendrils, inside exit). Save/publish and Git push remain unconfirmed. Next: observe that gate; when the user chooses to build crafting, add a *server-owned* grant of the existing Tool and live-test Tool.Activated, sockets/free placement, board collision and death/disconnect recovery before expanding the pool.

## Current continuation: barricade Play check (2026-10-12)

The user accepted the visible day/night and fuel-generator loop (“everything is working amazing”), then selected **garage barricade** for the next slice. `Workspace.Map.Interactions` now also holds an Edit-mode-authored `Garage_BoardedGate` and `Garage_BoardingLatch.BoardGarage`. Server `BarricadeService` boards the bay by day at a three-second/noise cost; a pursuing Braid cannot cross/chomp through it, presses ~2.4 seconds to breach, then resumes chase. The inside latch also allows a loud one-way emergency opening at Night, avoiding a player trap. Dawn resets it. No runtime UI/game Instances; no general destruction/pathfinding is claimed. `docs/BARRICADE-SLICE.md` has the exact hierarchy and limitations.

Local gate **14/14** (366 smoke, 145 original session, 14 day-prep, 15 barricade, 1 client boot, 48 official Luau compile). Barricade authoring was idempotent (second run 0 created/3 reused); static/map/day-prep/barricade verifiers passed; guarded Studio parity **48/48 zero drift**. **No Play verdict exists for the new defense.** First ask the user to board by day, test the inside emergency exit and one-use cost, observe the Braid's gate pause/breach and restored chase at Night, and confirm Dawn reset. If its tendrils stretch, collision traps a player or the Braid teleports through, treat that as the first bug rather than expanding the system. Exact `RE_TimeSync` queue-free Output and save/publish remain unconfirmed despite the user's positive overall Play verdict. Preserve approved monster movement.

## Current continuation: observe the new day-prep slice in Play (2026-10-12)

The user corrected the monster report: it was stationary at **Dusk**, and **does work** at Night. They selected the next first day-preparation choice. `Workspace.Map.Interactions` now contains a preauthored fuel can, generator and powered lamp, plus two preauthored prompts; `DayPrepService` owns the one-can inventory, daytime spending, death/disconnect drop, dusk/night noise and distant Braid lure, and Dawn restock. Read `docs/DAY-PREP-SLICE.md`. The author job was idempotent (second run 0 created/7 reused), local quality gate **13/13** (366 smoke, 145 original session, 14 day-prep, 1 client boot, 47 official Luau compile), Studio structural/map/day-prep verifiers passed, guarded source parity **47/47 zero drift**. The user subsequently reported **“everything is working amazing”** in Play. Preserve this accepted visible slice. Detailed two-player/death-restock observations and warning-free `RE_TimeSync` Output are not individually documented; only headless coverage establishes those narrow paths. Before a new large feature, agree on one small next priority with the user. Preserve the approved night gait and no-runtime-object policy. Do not start the next large feature before this Play verdict.

## Verified baseline and current blocker (2026-10-12)

- Studio place **Vitriol / ID `92448193604950`**. Latest local quality gate **19/19** (bell **19/19**, cost rules **16/16**, watch eight scenarios, navigation **16/16**, five offline Studio-audit scenarios); smoke **366/366**; session **145/145**; day-prep **14/14**; barricade **23/23**; placement **17/17**; delayed-client-boot **1/1**; official compiler **52/52**. Latest guarded Studio audit ran nine verifiers and checked all 52 classes/sources before reporting the one intentional DayNightConfig timing source difference; see the newest section. Existing static verifier: `ok:true` (7 remotes, 211 authored Braid parts, 24 blood parts). **Save/publish and Git commit/push are unconfirmed.** Tests and Edit-mode checks do **not** prove Studio Play appearance.
- `Workspace.Map`, authored in Edit mode via `jobs/author_map_vitriol.lua`, is a playable **first slice**, not finished art. Its second run created **0** new objects and reused **206**. `jobs/verify_map_vitriol.lua` returned `ok:true`: **7** named structures, **10** tagged zone volumes, **5** authored lamps. It reuses the former stock Baseplate and SpawnLocation in organized `Map/Ground` and `Map/Spawns` folders, preserving the separate `Workspace.Vitriol` assets. Read `docs/MAP-SLICE.md` for positions, hierarchy and gaps.
- User-selected loop: Day/Dawn are safer (the same authored Braid withdraws); at Dusk it appears but does not hunt; at Night it hunts. Death removes character/Backpack/StarterGear Tools; players wait until Dawn and lose **20 max HP** (100→80→60→40→20→0). Zero is permadeath for the **server run**; all exhausted ends that run. No next-run reset or full custom inventory exists yet. `LightingDriver` paints *existing* client Lighting from the authored clock/keyframes.
- **Current Play blocker / newly repaired authored class:** previous Play exhausted `RE_TimeSync`'s queue through 256 drops. Studio inspection then found `LightingDriver` was a **LocalScript**, although `ClientMain` requires it before binding `RE_TimeSync`. The guarded Edit-mode `jobs/repair_client_modules_vitriol.lua` replaced only this wrong-class controller with a **ModuleScript**, preserving its source; the second run was idempotent. The bridge sync helper now distinguishes client entry scripts from controller modules and verifies class after writing. Updated `jobs/verify_static_vitriol.lua` checks client script classes; it and the map verifier passed. A read-only `jobs/verify_client_boot_vitriol.lua` also required all four pre-bind modules in Studio Edit mode successfully (no failures); it does **not** execute the LocalScript in Play. The replicated-root wait and one-time startup/bind diagnostics are also synced; Current Studio parity is **47/47 zero drift** after the day-prep integration. After the client repair, the user reports the **day/night cycle works properly**; a still-floating Braid was observed at **Dusk**, then the user clarified that it **does work**. Dusk is the intended reveal without a hunt; don't change the approved night chase based on that report. A warning-free `RE_TimeSync` Output verdict has not been explicitly supplied. Request client Output with `[vitriol.client] ClientMain started` and `[vitriol.client] RE_TimeSync listener bound` and any queue warnings when convenient. If warnings persist with both diagnostics, investigate remote identity/listener lifetime; never suppress server broadcasts to hide the warning.
- User confirmed **no collision issues**, dawn death wait/80-HP penalty/Tool loss. One `Creature:Frame` took **13.670 ms** against a **1.200 ms** budget; profile if reproducible. `[Arena] poll failed: Http requests can only be executed by game server - Client` persists and has no Vitriol source match; its exact origin is unproven. Do not loosen game HTTP permissions to hide it.

## Closed loop: observe → one small change → verify → observe again

1. **Observe the new garage barricade in fresh Studio Play; the visible fuel/lighting loop was accepted.** Ask the user to traverse `Spawn_Garage`, the garage/filling station, both houses, church, mill bridge and woods; watch Day→Dusk→Night→Dawn, Braid pathing/chomp, dusk reveal, dark/light readability, death wait, 80-HP dawn return and Tool loss. Record exact **client and server Output**, collision snags, Braid footholds and a human visual verdict. Confirm whether the time-sync queue warning is gone and include the two one-time `[vitriol.client]` diagnostics. The legacy bridge’s `run_luau` uses `loadstring`, which is unavailable in Play; do not pretend a Play probe through it worked.
2. **Fix the first reproducible Play blocker.** Change only the affected `code/<Explorer path>.luau` scripts or the named authored objects in `Workspace.Map`. Keep the earlier Braid behavior the user praised. For any geometry/UI edits, update a guarded, idempotent **Edit-mode** job and its read-only verifier; never create new map/UI Instances during Play. Preserve all unrelated user-authored content and the top-level `Workspace.Vitriol` assets. Existing art is a deliberately laid-out blockout, not final bespoke meshes.
3. **Run evidence gates before sync:** `npm --prefix tools ci` and `bash tools/install-luau.sh` if generated dependencies disappeared; then `node tools/vitriol-quality-gate.js --src code --report tools/reports/quality-gate.json`, the official Luau compiler and static-content check. Verify Editor jobs compile too. Use the legacy `tools/studio_bridge.py` (not the modern `/api/tool` contract): `ping` place ID; ensure Play is stopped; run the relevant author job only in Edit mode; run `jobs/verify_static_vitriol.lua` and `jobs/verify_map_vitriol.lua`; guarded `sync` changed scripts; `parity` across all game files. Credentials are environment-only; never copy the URL/token into repo files or logs. Then ask for **fresh Play** and repeat until the chosen acceptance is met.
4. **The first garage day-prep choice is visible-Play-accepted; the barricade is not.** Verify the barricade’s crossing, Braid breach and inside emergency exit in Play before another feature. Specific two-player/death-restock details of the fuel choice remain headless-only. All prompts and geometry are Edit-mode-authored; do not invent art/audio IDs or claim general destruction, a full inventory, usable basement, tower climb or polished art.
5. **Stop/report honestly:** give a compact table of goal → observed Play result → change → gate/static/parity evidence → unresolved risks → next experiment. Request that the user **save/publish** the Studio place when satisfied. GitHub `main` changes have not been confirmed committed/pushed; never equate a local checkout or Edit-mode parity with a published place.

### Suggested exit for the next slice

Two consecutive day/night transitions on the new map without Vitriol errors or `RE_TimeSync` queue warnings; readable Braid traversal and safe dawn respawn; one meaningful authored day-prep choice affecting the next Night; server validation and inventory loss on death; zero Vitriol runtime `Instance.new`/`Clone`; full gate, static map verifier, official compile and source parity green. If any condition is unobserved in Play, say so explicitly and continue the loop rather than marking it done.

Read `AGENTS.md`, `INTEGRATION.md`, `docs/MAP-SLICE.md`, `ROADMAP.md`, `docs/00-VISION.md`, `docs/01-ARCHITECTURE.md` and `docs/10-HUMAN-AUTHORED.md` before implementing. Use **Vitriol `main` only** as reference. Current authored map/zone tags are reserved for future AI/destruction; their presence does not make those mechanics functional.

## 2026-10-12 — user Arms watch, local-only implementation; bridge access missing
The user Play-accepted the prep/floodlight/watch and bell/rope in the earlier slice; they now want their `Workspace.Arms` plus animation `CheckWatch` (`119603256128899`) instead of the hold-T viewport: **tap T** plays one shot, smoothly returns, wears the player's shirt and skin, and displays the authoritative Day countdown on a screen welded with the watch to the right upper arm. Their future "permanent changes" should last within the current run through death/cycles but **not** across sessions. No particular world project has been chosen; ask rather than invent. Play was stopped for the guarded read-only Arms survey; it found a 313-descendant user rig, anchored/collidable unwelded watch pieces and editor-only keyframes. Local WatchController/ClientMain, editor author/verifier jobs, focused 14-scenario harness and `docs/PLAYER-WATCH-ARMS-SLICE.md` are written. Full local gate **25/25**, official compiler **55/55**, editor jobs compile. **Not integrated in Studio:** bridge ping/author were attempted but stopped before network/mutation because `BRIDGE_URL` and `BRIDGE_TOKEN` are absent in this session. Do not tell user to Play the new watch yet. Restore environment-only bridge access, ping/place/mode guard, author, verify, sync two scripts with exact readback, then ask for fresh Play. Original `Workspace.Arms` was unchanged by this turn. Keep accepted world gameplay and Studio fast Day values intact; save/publish, Git push, and frame time remain unconfirmed. See `docs/PLAYER-WATCH-ARMS-SLICE.md`.

**2026-10-12 watch integration update:** User restored environment-only bridge access. `ping` verified Vitriol place `92448193604950`; the guarded Edit-mode author ran once (template created, user source archived unmodified) and a second time idempotently (`reused:true`). Read-only Arms verifier `ok:true`/61 template descendants/0 defects, static verifier `ok:true`. Guarded sync of only ClientMain (LocalScript) and WatchController (ModuleScript), **2/2 exact source and class readbacks**; studio-only timing and extended road untouched. **Fresh human Play not yet done**; ask user to tap T, inspect animation/physical Screen/shirt/skin/smooth return and affected prep fade/bell, capture Output. The user selected run-persistent repairs lasting until monster breakage; if a "light garrage" breaks they must repair it before fueling again. Clarify which physical light/monster-break trigger before implementing. See `docs/PLAYER-WATCH-ARMS-SLICE.md`. No save/publish, push or frame timing confirmation.

**2026-10-12 run-lasting lights follow-up:** User selected BOTH station and garage lights for run-persistent repairs, dedicated Night Braid attacks when prey is distant, and **garage light alone** must be fixed before using a fuel can to power it. New `docs/RUN-LIGHTS-SABOTAGE-SLICE.md` documents bounded implementation, tests, Studio author/sync and first Play log. Guarded author added two disabled garage repair/helper prompts (rerun idempotent); 5 scripts guarded-synced with **5/5 exact source readbacks**, source class checked; structural/static verifier `ok:true`. Full local gate **26/26**, run-lights fixture **26/26**, prep integration **43/43**, compiler **55/55**. User asked to hide character arms and left viewmodel arm while watch is up; WatchController change synced with exact Source, **Play follow-up not yet confirmed**. User Play Output proves garage fuel, station repair and bell still executed, **not** monster damage or repeat-cycle persistence; DayPrep:Pulse warned at 0.236–0.858 ms vs 0.050 ms share on several transactions. Do not claim sabotage Play-approved or budget green. User explicitly chose to **keep** their live station switch `(-62,4.2,-111)` instead of old -110; editor jobs/verifier updated, no geometry moved. Request specific visual/attack/repair verdict, arm visibility, and visible frame-time impact. Save/publish, push and measured normal frame time unconfirmed.

**2026-10-12 diagnosis/follow-up:** User's first new Play reported Braid stopped at bell and then at lit fixtures, resuming only when a player approached; no sabotage verdict. They also saw the avatar surf/fly when the watch arm lowered under legs/torso; the new arm hiding otherwise looked right, and no visible hitch was noticed despite real DayPrep:Pulse slot overrun warnings. Guarded Edit-mode watch physics survey found all 9 template Parts noncollidable but still queryable/touchable/massful and Humanoid state machine standing. Guarded one-shot repair made all 9 nonqueryable/nontouchable/massless, disabled visual-only Humanoid state machine/standing/autorotation; original source untouched. Watch verifier `ok:true`; **fly fix awaits Play**. Bell now marks a single ring investigated upon arrival (12-stud radius), so it no longer camps bell; light sabotage uses actual tendril reach up to 16 studs rather than unreachable 8-stud core contact, retaining garage wall guard and nearby-player precedence. Run-lights **27/27**, full gate **26/26**, compiler **55/55**; guarded resync of ONLY CreatureService/DayPrepService and 2/2 exact Source readback, all four focused Studio verifiers `ok:true`. **Freeze/light break fix awaits fresh Play.** User selected live station switch -111, no geometry moved, old verifier updated and passed. See docs/PLAYER-WATCH-ARMS-SLICE.md and docs/RUN-LIGHTS-SABOTAGE-SLICE.md.

**2026-10-12 second Play correction:** Watch physics fix Play-confirmed (“Surfing is fixed”); user earlier said arm hiding “Looks right.” Braid **still** stops between the station and garage and near the church after bell distraction, so do **not** claim the bell/light lure correction accepted or the sabotage loop observed. No Vitriol stack trace in provided excerpt; several 0.2–0.4 ms slow-slot budget warnings and bridge `[Arena]` HTTP-poll errors are real/separate, neither proves permanent Braid freeze. Added bounded `CreatureService:_probeLure` server warning at most every 8 s when a fixed lure target remains >18 studs away and core moved <1 stud in 2.5 s; it prints core/lure/nav coordinates, anchor count and first blocking ray hit. No objects/scheduler/visual behavior changed by the diagnostic. Local full gate **26/26**, run-lights **27/27**, compiler **55/55**, guarded sync/exact Source readback for only CreatureService. User says Play stopped. **Next:** fresh Play; request exact `lure stall` line and visible Braid position before further changes to accepted gait or geometry. See docs/RUN-LIGHTS-SABOTAGE-SLICE.md.

**Diagnostic refinement:** User says freeze is between the station and garage and near the church, not necessarily at the fixtures. Expanded the same capped 2.5-second probe to nearby-prey pursuit as well as bell/lights, renamed log prefix to `pursuit stall`, raised no scheduler or Instance cost. Full gate **26/26**, guarded single-module CreatureService sync/exact Source readback completed. Ask for the FIRST `pursuit stall` line with coordinates/feet/block from fresh Night Play. Avoid geometry/gait guesses until then.

**2026-10-12 exact garage-lure stall diagnosed:** User Night Output repeated `pursuit stall GarageLight core(45.5,-137.4) goal(-112,-60) nav(0,0) feet=4 block=Workspace.Map.Structures.Millers_Garage.BackNorth`. Guarded real Studio six-node ray probe showed only the east entrance `(-55,-56)` safely connects, but its final ray hits the queryable `Garage_Generator` endpoint itself; old router wrongly treated that as an obstruction and returned nil, clearing the target. Narrow `GarageNavigation:routeClear` optional endpoint allowance ONLY for garage-light target legs; ordinary player and true wall blocks unchanged. Analytic navigation **18/18** reproduces nil before fix and entrance waypoint after, run-lights **27/27**, full gate **26/26**, compiler **55/55**. Guarded sync/2 exact Source readbacks passed; fresh compiled Studio source/real geometry returned `(-55,-56)`. **Actual Night Braid movement/destruction not yet Play-verified; separate church stop awaits its own diagnostic.** See docs/RUN-LIGHTS-SABOTAGE-SLICE.md.

**2026-10-12 Play progress:** User: garage path “worked; doesnt freeze anymore” after generator-endpoint route fix. New Night warning `pursuit stall StationLight core(-86.1,-71.4) goal(-88,-125) nav(-88,-125) feet=4 block=...Millers_Garage.BackNorth` exposed direct station aiming through garage north wall. Guarded real Studio source/geometry probe returned safe first waypoint `(-55,-56)`. CreatureService now detours around that wall for both garage and station lure kinds, with generator endpoint exception only for garage. Local navigation **19/19**, lights **27/27**, full gate **26/26**, official compiler **55/55**; guarded one-module sync/exact readback passed. **Station follow-up and full break/repair cycle not yet Play-confirmed; do not claim.**

**2026-10-12 accepted garage/full loop and church/sense candidate:** User answered “Everything works now yes” to explicit garage lamp break → fuel blocked → paid repair → repower checklist; this **garage loop is Play-accepted**. New `pursuit stall Bell core(83.8,-207.5) ... block=Church_BellTower.Body` remains; user chose REAL CHURCH MAIN ENTRANCE, NOT exterior check/windows. Read-only Studio surveys confirmed solid Body west wall and passable front x113..125; guarded, pure ChurchNavigation route from west via (86.25,-130.25) → doorway (119,-130.25) → Bell (119,-210). Actual side direct ray hit unrelated ChurchWindows.Union10; fixed staged waypoint precedence. Real Studio fresh Source read-only probe `{ok:true}`. User also rejected monster's omniscient GPS after all lures and clarified no literal eyes, just LOS-like directional sensing and local THERMAL. Config ranges 90 direct, 22 thermal (solid walls block), 8 s last-sensed location; no far-hidden live root tracking. Dedicated tests church **6/6**, senses **10/10**, run-lights **27/27**, garage nav **19/19**, full gate **28/28**, compiler **56/56**; guarded sync/exact sources/classes of ChurchNavigation, MonsterConfig, CreatureService. **Church movement and sensory feel NOT Play-confirmed**; request fresh Night test without altering accepted chase speed/gait. Save/publish, Git push, measured normal frame time still unconfirmed. See docs/RUN-LIGHTS-SABOTAGE-SLICE.md.

**2026-10-12 sensing Play accepted / church follow-up:** User judged eye-less LOS+thermal behavior “Feels fair now” after Play. Garage full repair loop already Play-accepted. Church still stopped farther out: `pursuit stall Bell core(-38.4,-48.1) goal(119,-210) nav(0,0) feet=4 block=Workspace.ChurchWindows.Union11`. Real Studio read-only rays from that point: direct bell hits top-level ChurchWindows union, but main doorway `(119,-130.25)` is clear. ChurchNavigation now treats only that authored ChurchWindows Model as church-related for routing; distant southern approach goes to door, prior west-wall corridor remains, unrelated cover still fails closed. Headless church **8/8**, full gate **28/28**, compiler **56/56**; guarded single-module sync/class/exact Source and fresh live geometry probe passed both distant and near routes. **Church fix awaits fresh human Night Play**; do not claim yet.

**2026-10-12 final human Play verdict:** After the church window/main-door routing fix the user said **“Everything works, it still stops but it doesnt freeze; after 3 seconds it moves to destroy the lights.”** This confirms the bell-distraction-to-light sequence now RESUMES rather than permanently freezing; a brief three-second pause remains. Do not claim smooth continuous locomotion or that the Braid physically crossed the church threshold—the user did not explicitly say either. The garage full break/repair/refuel loop was independently Play-accepted (“Everything works now yes”), the watch surfing bug was Play-confirmed fixed, the arms looked right, and eye-less LOS+thermal was described as fair. Final local gate **28/28**, compiler **56/56**, guarded exact readback/probes for latest church code; no further behavior edits after this verdict. Measured normal frame time, Studio save/publish, Git push remain unconfirmed. See docs/RUN-LIGHTS-SABOTAGE-SLICE.md.
