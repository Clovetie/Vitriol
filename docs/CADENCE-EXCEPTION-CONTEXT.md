# Rare Think / Session cadence warning context — diagnosis, not a performance fix (2026-10-13)

> **Later DayPrep warning context:** New real DayPrep:Pulse overruns at
> 0.418/0.405/0.223 ms triggered same-slot action/stage/hum context for
> *future* exceptional Output. Session begin-round 0.209 ms and Time:Publish
> 0.395 ms are still real open warnings. Synthetic **10/10**, guarded Edit
> two-script Source/class **2/2 exact**, Studio fake slot/static `ok:true`.
> Neither the prior warnings nor their causes are resolved. See
> [`DAYPREP-WARNING-CONTEXT.md`](DAYPREP-WARNING-CONTEXT.md).


> **Later route-cost work:** The 13-ray figure below is historical.
> The current analytic center Garage detour is **11 rays**, or **10** with
> a genuinely measured prior hit; 720/720 exhaustive-waypoint parity and
> 8/8 actual-Garage Studio-Source parity passed. This is still NOT a Play
> timing verdict. See
> [`M3-GARAGE-ROUTE-COST-PRUNING.md`](M3-GARAGE-ROUTE-COST-PRUNING.md).

> **Subsequent bounded work:** A duplicate selected-prey sensor ray was
> removed from the same Think, with a missing-result safety fallback;
> the separate cold Garage detour fan still uses 13 rays in an analytic
> fixture. Senses **23/23**, gate **36/36**. This is NOT a measured Play fix
> for any of the three warnings. See
> [`M3-SENSED-RAY-REUSE.md`](M3-SENSED-RAY-REUSE.md).


The user asked to keep working, with real but unattributed one-off Play warnings: `Creature:Think 8.313/1.000 ms`, `Session:Slow 0.204/0.050 ms`, and `Time:Publish 0.389/0.050 ms`. We cannot retroactively explain those samples after Play stopped. The earlier Time:Publish warning already had a same-sample attribute-vs-remote context added for a *future* exceptional sample; this slice makes future **Think and Session** >4× logs more informative without altering measured budgets or warnings.

- `SessionService:tick()` records the **path it actually took during its own measured slot**: `intermission`, `begin-round`, `running`, or `ended`. On a future exceptional `Session:Slow` warning, Bootstrap appends that path plus post-tick state and phase **after Cadence has timed the slot**. `begin-round` is distinct from a normal running tick. That label can establish which code path ran; it alone does not establish why 0.204 ms elapsed (e.g., logging, engine scheduling or something else).
- On a future exceptional `Creature:Think` warning, Bootstrap reads the server-side current phase, the Braid's decision reason and attack phase **after slot timing**. It does not include private coordinates or player IDs, and adds no raycast, cadence job or UI/gameplay Instance. This can correlate a recurrence with prey, lure, Garage flank, patrol or attack without pretending that the displayed reason accounts for all the slot time.
- Existing `Time:Publish` same-sample sections, the original whole-slot timing, `0.050`/`1.000` ms shares and >4× warning threshold are **unchanged**. No exceptional context is formatted on ordinary ticks. `Session` has only a tiny per-slow-tick branch-label assignment; no extra clock calls inside the 6 Hz Think or 1 Hz Session slots.

**Evidence:** `tools/vitriol/cadence-warning-context.luau` **7/7** uses *synthetic* 0.210 ms Session and 5.000 ms Think overshoots and checks the original warning plus its same-sample path/decision fields, unchanged Cadence measured peaks/budgets and zero runtime Instances. The pre-existing Time:Publish virtual warning fixture still passes **10/10**. Full quality gate **36/36**, official Luau compiler **61/61**, `git diff --check HEAD` clean. Before authoring only `Bootstrap` and `SessionService`, the legacy bridge verified Vitriol place `92448193604950`, Edit mode, and both prior full Studio Sources/classes against the last exact readbacks; final changed Source/class **2/2 exact** (`tools/reports/cadence-warning-context-sources.json`). A read-only freshly compiled actual-Studio-Source Edit probe independently exercised Session's begin-round/running/ended labels and compiled the Bootstrap warning code (`cadence-warning-context-live-source.json`, `ok:true`). Post-sync static verifier `ok:true` (`cadence-warning-context-static.json`).

**Still open:** those three past Play overruns are genuine and unassigned; the synthetic values above are not Play observations. Only a future **active Play** recurrence (or a sustained Play profile) can attribute cost and justify any performance change. Do not raise shares, suppress warnings, claim timing compliance, or change the already accepted Night regional hunt/give-up, House_01 exit, both-house cover, Braid gait, sight/thermal security or Day-prep contracts. Human fourth-Garage-visit and House_02 exit remain unverified. Save/publish and Git push unconfirmed.
