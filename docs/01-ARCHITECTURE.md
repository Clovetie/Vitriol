# VITRIOL — Architecture (Explorer-first)

This document defines **where everything lives in Roblox Studio's Explorer**, who
owns what, how data flows, and the rules every later iteration must obey.

> **Convention (project owner's instruction):** the hierarchy below is a **Roblox
> Studio Explorer tree**, *not* a Rojo `src/` layout. There is no
> `default.project.json` in this project and there must not be one. On disk,
> copy-paste-ready sources live under `code/`, mirroring Explorer paths so a
> developer can see at a glance where each file goes. Every source file also
> carries its Explorer path in a header comment (see §12).

---

## 1. Class legend

| Tag | Instance class | Tag | Instance class |
| --- | --- | --- | --- |
| `SVC` | built-in service (not created by us) | `MD` | ModuleScript |
| `FL` | Folder | `SC` | Script (server) |
| `MO` | Model | `LS` | LocalScript |
| `PT` | Part | `RE` | RemoteEvent |
| `MP` | MeshPart | `RF` | RemoteFunction |
| `ATT` | Attachment | `BE` | BindableEvent |
| `BN` | Bone | `BF` | BindableFunction |
| `MO6` | Motor6D | `AE` | Actor |
| `CFG` | Configuration | `BSC` | BallSocketConstraint |
| `RE_CONST` | RigidConstraint | `TSC` | TorsionSpringConstraint |
| `HNG` | HingeConstraint | `AP` | AlignPosition |
| `AO` | AlignOrientation | `LV` | LinearVelocity |
| `AV` | AngularVelocity | `VF` | VectorForce |
| `RC` | RopeConstraint | `IKC` | IKControl |
| `CS` | CollectionService tag *(not an instance)* | | |

---

## 2. The tree

```
game
├─ Workspace (SVC)
│  ├─ Vitriol (FL)                      ← everything the runtime creates at play time
│  │  ├─ World (FL)                     ← server-authoritative world state anchors
│  │  │  └─ TimeAnchor (ATT parented to a 0-size part) : holds replicated clock attrs
│  │  ├─ Creatures (FL)                 ← one (MO) per live creature
│  │  ├─ Debris (FL)                    ← pooled debris parts (CS tag "Vitriol_Debris")
│  │  ├─ Gore (FL)                      ← gore module output lands here (CS "Vitriol_Gore")
│  │  ├─ Vehicles (FL)                  ← drivable vehicle assemblies
│  │  ├─ Structures (FL)                ← destructible structures authored in the map
│  │  ├─ NoiseMarkers (FL)              ← OPTIONAL debug-only visualisation (never in ship)
│  │  └─ CorpseCache (FL)               ← persistent corpses / detached limbs
│  ├─ Map (FL)                         ← HUMAN AUTHORED (see 10-HUMAN-AUTHORED.md)
│  ├─ Terrain (SVC)
│  └─ ... (streaming containers)
│
├─ Lighting (SVC)                       ← client-side driven; see 06-DAY-NIGHT.md
│  ├─ Atmosphere (Atmosphere)
│  ├─ ColorCorrection (ColorCorrectionEffect)
│  ├─ Bloom (BloomEffect)
│  ├─ SunRays (SunRaysEffect)
│  ├─ DepthOfField (DepthOfFieldEffect)
│  ├─ Sky_Day (Sky)     ┐
│  ├─ Sky_Dusk (Sky)    ├ HUMAN AUTHORED skyboxes
│  ├─ Sky_Night (Sky)   ┘
│  └─ (Technology/LightingStyle set manually in Studio — see 06 §7)
│
├─ ReplicatedStorage (SVC)
│  └─ Vitriol (FL)
│     ├─ Types (MD)                     ← shared type aliases & enums (no side effects)
│     ├─ Config (FL)
│     │  ├─ GameConfig (MD)             ← session shape, tick budgets, feature flags
│     │  ├─ DayNightConfig (MD)         ← 24h keyframes, pacing, weather
│     │  ├─ MonsterConfig (MD)          ← genome ranges, archetypes, senses, action set
│     │  ├─ SurvivalConfig (MD)         ← meters, drain curves, debuff definitions
│     │  ├─ DestructionConfig (MD)      ← materials, joint HP, impulse thresholds
│     │  ├─ VehicleConfig (MD)          ← chassis/wheel/drivetrain tuning
│     │  └─ GoreConfig (MD)             ← region integrity, sever rules, contract defaults
│     ├─ Lib (FL)                       ← PURE modules: no services, no instances, no yields
│     │  ├─ RNG (MD)                    ← deterministic seeded RNG (PCG-ish / xorshift)
│     │  ├─ Fabrik (MD)                 ← constrained FABRIK solver (the tendril spine)
│     │  ├─ Genetics (MD)               ← genome roll / mutate / crossover / express
│     │  ├─ MathExt (MD)                ← lerp, damp, smoothstep, angle helpers
│     │  ├─ Noise (MD)                  ← deterministic value/simplex noise for idle motion
│     │  ├─ SpatialHash (MD)            ← fixed-cell hash for noise sources & prey lookup
│     │  ├─ UtilityAI (MD)              ← scored-action selection w/ softmax
│     │  ├─ QLearning (MD)              ← linear function approximation + eligibility traces
│     │  ├─ MarkovPredictor (MD)        ← per-player behaviour→destination model
│     │  ├─ Signal (MD)                 ← tiny observable (no BindableEvent needed)
│     │  └─ Tables (MD)                 ← freeze/clone/pool helpers
│     ├─ Shared (FL)                    ← modules that MAY touch instances, both sides
│     │  ├─ Remotes (MD)               ← creates/looks up every remote, one place only
│     │  ├─ NetContract (MD)            ← payload schemas + validation (server never trusts)
│     │  ├─ NoiseField (MD)             ← shared vibration/scent/EM channel model
│     │  ├─ Skeleton (MD)               ← joint-chain data structure (server & client)
│     │  ├─ SkeletonCodec (MD)          ← pack/unpack joint CFrames for replication
│     │  ├─ RegionIntegrity (MD)        ← body-region damage model for kill choreography
│     │  ├─ GoreAdapter (MD)            ← wraps the supplied Gore module (see 04 §6)
│     │  └─ TimeModel (MD)              ← pure clock math shared by server & client
│     ├─ Comms (FL)                     ← the ONLY remotes in the game
│     │  ├─ RE_TimeSync (RE)            ← server→all: clock/threat snapshot (low rate)
│     │  ├─ RE_SkeletonStream (RE)      ← server→all: creature joint payload (Buffer)
│     │  ├─ RE_CreatureEvent (RE)       ← server→all: roar/impact/kill beats (event, not state)
│     │  ├─ RE_SurvivalSync (RE)        ← server→owner: meter/debuff deltas
│     │  ├─ RE_ClientIntent (RE)        ← client→server: attune/consume/interact intents
│     │  ├─ RE_Destruction (RE)         ← server→all: joint break + debris spawn
│     │  └─ RF_DebugQuery (RF)          ← server-authorised debug introspection only
│     └─ Assets (FL)                    ← shared *replicated* assets (small only)
│        └─ DebrisTemplates (FL)        ← HUMAN AUTHORED small debris meshes
│
├─ ServerStorage (SVC)
│  └─ Vitriol (FL)
│     ├─ Services (FL)                  ← long-lived singletons, one MD each
│     │  ├─ CadenceService (MD)         ← THE ONLY GAMEPLAY LOOP: one Heartbeat driver for every
│     │  │                                 cadence in §4, staggered, self-measuring
│     │  ├─ SessionService (MD)         ← round/nite state machine, Threat Level
│     │  ├─ TimeService (MD)            ← owns the clock; publishes to TimeModel/attrs
│     │  ├─ ThreatService (MD)          ← Threat Level curve + director
│     │  ├─ CreatureService (MD)        ← spawn pool, lifecycle, LOD budgets, actor mgmt
│     │  ├─ PerceptionService (MD)      ← runs senses for all creatures (parallel actors)
│     │  ├─ MemoryService (MD)          ← creature memory + species persistence
│     │  ├─ EvolutionService (MD)       ← end-of-night selection/mutation/prior update
│     │  ├─ SurvivalService (MD)        ← meters, debuffs, consumption validation
│     │  ├─ InventoryService (MD)       ← carried items, food/water/fuel
│     │  ├─ DestructionService (MD)     ← joint graph, integrity BFS, debris pooling
│     │  ├─ VehicleService (MD)         ← vehicle lifecycle, ownership, damage
│     │  ├─ GoreService (MD)            ← server-side gore/dismemberment authority
│     │  ├─ PersistenceService (MD)     ← DataStore + MemoryStore, retries, budgets
│     │  ├─ TelemetryService (MD)       ← analytics + the RL episode log
│     │  └─ HealthService (MD)          ← humanoid health, wounds, bleeding
│     ├─ Creature (FL)
│     │  ├─ CreatureCore (MD)           ← the per-creature object (state + subsystems)
│     │  ├─ Brain (FL)
│     │  │  ├─ Senses (MD)              ← channel sampling → perceptions
│     │  │  ├─ Memory (MD)              ← short/long-term memory records
│     │  │  ├─ Predictor (MD)           ← wraps MarkovPredictor for this creature
│     │  │  ├─ Policy (MD)              ← UtilityAI + QLearning arbitration
│     │  │  ├─ Tactics (MD)             ← tactic definitions (the action set)
│     │  │  ├─ BehaviorTree (MD)        ← execution layer (sequencer/selector/decorator)
│     │  │  └─ Steering (MD)            ← seek/arrive/pursue/avoid/anchor-seek
│     │  ├─ Body (FL)
│     │  │  ├─ TendrilRig (MD)          ← builds/holds the joint chains for one creature
│     │  │  ├─ Locomotion (MD)          ← anchor-find + core haul
│     │  │  ├─ Grapple (MD)             ← grab, coil, drag, throw
│     │  │  └─ KillChoreography (MD)    ← grab→coil→tenderize→consume→discard
│     │  ├─ Replicator (MD)             ← encodes skeleton → RE_SkeletonStream
│     │  └─ Archetypes (FL)
│     │     └─ Braid (MD)              ← the MVP species definition
│     ├─ Actors (FL)                     ← parallel execution shells
│     │  ├─ CreatureWorker (AE)         ← contains CreatureActor (SC)
│     │  │  └─ CreatureActor (SC)       ← task.desynchronize() perception + IK math
│     │  └─ PhysicsWorker (AE)
│     │     └─ PhysicsActor (SC)       ← raycast/spatial-query offload for destruction
│     ├─ Assets (FL)                     ← HUMAN AUTHORED, never replicated
│     │  ├─ CreatureRigs (FL)           ← skinned meshes + bone chains per archetype
│     │  ├─ GoreAssets (FL)             ← limb chunks, blood, viscera
│     │  └─ Audio (FL)                  ← creature voices, foley, ambience
│     └─ Bootstrap (MD)                   ← starts services; ServerScriptService's Main
│                                          (SC) is the only thing in the tree that runs
│
├─ ServerScriptService (SVC)
│  └─ Vitriol (FL)
│     ├─ Main (SC)                       ← thin: requires ServerStorage Bootstrap, runs it
│     ├─ RemoteHandlers (FL)
│     │  ├─ ClientIntentHandler (SC)     ← validates & routes RE_ClientIntent
│     │  └─ DebugHandler (SC)            ← RF_DebugQuery (gated by permission)
│     └─ Diagnostics (FL)
│        ├─ Profiler (SC)                ← microprofile scopes + budget watchdog
│        └─ AIDebugDump (SC)             ← writes creature decision traces (opt-in)
│
├─ StarterPlayer (SVC)
│  └─ StarterPlayerScripts (SVC)
│     └─ Vitriol (FL)
│        ├─ ClientMain (LS)              ← boots all client controllers
│        ├─ Controllers (FL)
│        │  ├─ LightingDriver (LS)      ← applies TimeModel to Lighting *locally*
│        │  ├─ CreatureRenderer (LS)    ← consumes skeleton stream → parts/bones
│        │  ├─ CreatureAudio (LS)       ← 3D audio, sub-bass, doppler, occlusion
│        │  ├─ VibrationFx (LS)         ← the "Attune" overlay + dust/shake
│        │  ├─ SurvivalHud (LS)         ← diegetic only: no bars (see 10-HUMAN-AUTHORED)
│        │  ├─ VictimCamera (LS)        ← the victim-side kill presentation
│        │  ├─ InteractionController (LS) ← carry, barricade, enter vehicle, consume
│        │  ├─ VehicleController (LS)   ← input → RE_ClientIntent; local prediction
│        │  ├─ DebrisRenderer (LS)      ← cosmetic client debris for remote breaks
│        │  └─ PostProcessDriver (LS)   ← screen effects for debuffs/kill states
│        ├─ Client (FL)
│        │  ├─ SkeletonInterpolator (MD) ← snapshot lerp + dead reckoning
│        │  ├─ LocalRigDriver (MD)       ← writes Bone.Transform / part pivots
│        │  └─ ClientNoiseField (MD)     ← client copy of NoiseField for the Attune UI
│        └─ Comms (FL)
│           └─ ClientRemotes (MD)      ← cached remote refs + rate limiting
│
├─ StarterCharacterScripts (SVC)
│  └─ Vitriol (FL)
│     ├─ CharacterSetup (SC)            ← collision groups, attributes, ragdoll prep
│     └─ GrabTarget (SC)                ← the per-character surface the creature grabs
│
├─ SoundService (SVC)                    ← HUMAN AUTHORED SoundGroups
└─ ServerStorage/ReplicatedStorage ... (see above)
```

### 2.1 Why this shape

- **`Lib` is pure.** No `game:GetService`, no instance reads, no `task.wait`. This
  is what makes the simulation **parallel-safe** (`task.desynchronize()` cannot
  `require()` — so everything an actor needs must be required *before*
  desynchronising; keeping `Lib` pure means actors can require it in serial and use
  it in parallel without surprises) and it is what makes the whole thing unit
  testable outside Roblox (see §13).
- **`Shared` may touch instances but is side-effect-light and deterministic.**
- **`Services` own state.** Exactly one writer per piece of state. Anything that
  needs to change another service's state calls a function on it; no service pokes
  another's data.
- **`Creature` is a *composition*, not an inheritance tree.** `CreatureCore` holds
  `Brain`, `Body`, `Memory`. Archetypes are **data + hooks**, never subclasses.
  Adding a species = a new MD in `Archetypes/` + genome ranges. No new plumbing.
- **One `Remotes` folder, one `Remotes` module.** No remote is ever created ad hoc.
- **Actors are shells.** `CreatureWorker` holds a `Script` that does the parallel
  work; the *logic* lives in `Lib`/`Brain` so it stays testable.

---

## 3. Ownership & authority

| Domain | Authority | Replicated by |
| --- | --- | --- |
| Clock / time of day | **Server** (`TimeService`) | attributes on `Workspace.Vitriol.World` + `RE_TimeSync`; **applied locally on each client** (see §5) |
| Threat Level | Server (`ThreatService`) | attribute + `RE_TimeSync` |
| Creature genome | Server (`EvolutionService`) | attribute summary only (tendril count, mass class) |
| Creature skeleton | Server (`CreatureCore`) | `RE_SkeletonStream` (packed `Buffer`) |
| Creature decisions | Server | **never replicated** except as *tells* (see `02` §8) |
| Player meters | Server (`SurvivalService`) | `RE_SurvivalSync` to owner only |
| Vehicle driving | Server physics, client prediction | normal physics replication + ownership auto-assign |
| Joint breaks | Server (`DestructionService`) | `RE_Destruction` + actual part destruction |
| Gore | Server (`GoreService`) | `GoreAdapter` calls; debris replicates normally |
| Lighting values | **Client** (`LightingDriver`) | not applicable — derived from replicated clock |

---

## 4. Tick architecture & budgets

The game runs on **four explicit cadences**. Nothing is allowed to invent its own
`while true do` loop.

| Cadence | Driver | Runs | Budget (server, 4 players, 2 creatures) |
| --- | --- | --- | --- |
| **Frame** (every `RunService.Heartbeat`) | `CreatureWorker` actors | IK solve, steering, secondary motion | **≤ 1.2 ms** total across actors |
| **Think** (4–8 Hz per creature, staggered) | `CreatureCore:Think()` | Utility/Q decision, tactic change | **≤ 0.8 ms** total |
| **Sense** (10 Hz, staggered, parallel) | `PerceptionService` | raycasts, spatial queries, channel sampling | **≤ 1.0 ms** total |
| **Slow** (1 Hz) | `SurvivalService`, `TimeService`, `ThreatService`, debris GC | meters, clock publish, pooling | **≤ 0.4 ms** |

Rules:
1. **Stagger** every per-creature tick by `index * (period / count)` so spikes
   don't align.
2. **Distance LOD** (`GameConfig.LOD`):
   - `NEAR` (≤ 60 studs of any player): full solve, every frame.
   - `MID` (≤ 140): half-rate solve, joints > 6 skipped, no audio-occlusion raycasts.
   - `FAR`: 4 Hz solve, joints collapse to a 4-joint proxy.
   - `OFFSCREEN` (no player has it in frustum): 2 Hz, no secondary motion.
3. **Never** allocate inside the frame cadence. All vectors/tables are pooled
   (`Tables.newPool`) and reused. `hot-loop-scan.js` will flag violations.
4. **Raycasts are batched**: one `GetPartBoundsInRadius` + a capped raycast fan, not
   N separate queries.

**The driver.** These four cadences are not four loops. `Services/CadenceService` is
the one scheduler: `Bootstrap` binds `RunService.Heartbeat` exactly once and hands the
cadence service a `dt`; every service registers a slot (`{Name, PeriodSeconds,
BudgetMs, Run}`) and gets staggered, pcall-guarded, and measured by the same code
path. Consequences that matter:

- A service cannot get its own `while true do` loop *or* its own `task.spawn` timer,
  because then the budget table above is fiction and `stop()` is a lie.
- Slots that fall behind by more than `GameConfig.Ticks.CadenceSlopSeconds` **skip** a
  beat instead of running a catch-up burst. Four creature decisions landing in one
  frame after a hiccup is read as cheating; the frame budget exists to protect the
  player's sense of fairness, not the profiler's numbers.
- The budgets in the table are per-row totals, so `GameConfig.Budgets` carries
  `SlowShares` / `FrameShares`: the split of a row across the services that use it.
  `Bootstrap` asserts the shares still fit the row at boot — a config that silently
  exceeds the documented budget is a bug in the config, and it should say so at
  startup rather than in a stutter at 3 a.m.
- Because the pump receives `dt`, the scheduler measures its own cost with `os.clock`
  only *per slot dispatch* (a 1 Hz job does not deserve a syscall per frame), and the
  file that touches `RunService` — `Bootstrap` — contains no priced call at all, which
  is what keeps `hot-loop-scan.js`'s "in a RunService file" count at zero.
- **to verify in Studio:** that measurement cost. The ~190 µs figure for `os.clock()`
  that this rule was written around is a `tick()`-in-a-Script measurement; from a
  ModuleScript `os.clock()` is a `workspace.DistributedGameTime` read, which is very
  probably cheaper. `CadenceService:summary()` prints peak and mean per slot, so the
  difference is visible: if `TimePublish`'s peak at 1 Hz is anywhere near a tenth of
  its 0.30 ms budget while doing nothing, sampling every Nth dispatch (one counter in
  `_runSlot`) is the fix.

---

## 5. Replication rules (the non-obvious ones)

These are the rules that come from the actual engine behaviour, verified in
`08-RESEARCH-NOTES.md`:

1. **`Lighting.ClockTime` is flagged *Not Replicated*.** Server changes do not
   reach clients. Therefore the clock is published as data (attribute + `RE_TimeSync`)
   and **each client sets Lighting locally** in `LightingDriver`. This is the single
   most commonly broken part of a Roblox day/night system.
2. **`Bone.Transform` and `Motor6D.Transform` are not replicated.** Procedural bone
   animation is therefore a **client-side presentation layer** fed by a server
   snapshot. `CreatureRenderer` + `LocalRigDriver` do this.
3. **Part CFrames DO replicate** (via assemblies/network ownership). So the
   fallback renderer (`parts` mode) works with zero extra plumbing — that's the MVP
   path; bones are the upgrade path.
4. **Attributes replicate** and are cheap. Use them for scalar state
   (`ClockMinutes`, `ThreatLevel`, `NightIndex`, `CreatureMassClass`). Never use
   attributes for per-frame data.
5. **`TorsionSpringConstraint.CurrentAngle` is not replicated** — do not read it on
   clients for gameplay decisions.
6. **Bones are not serialized** (`can_save: false`): anything authored in Studio on
   a bone transform will not persist. Bones are runtime-only.
7. **One snapshot stream, not N remotes.** Creature skeletons ship as a single
   `Buffer` per creature at a capped rate (12–20 Hz), never as per-joint attributes.

---

## 6. The data flow (one picture)

```
                        ┌──────────────────────── SERVER ────────────────────────┐
 Players ──actions──►   │ CharacterSetup / GrabTarget                             │
 (input)                │        │                                                │
      │                 │        ▼                                                │
      │                 │  NoiseField  ◄── DestructionService (breaks)            │
      │                 │  (vibration / scent / EM / heat)  ◄── VehicleService    │
      │                 │        │                          ◄── HealthService     │
      │                 │        ▼                                                │
      │                 │  PerceptionService ──► Senses ──► Perception            │
      │                 │                                      │                  │
      │                 │  MemoryService ◄── Memory ◄──────────┤                  │
      │                 │        │                             ▼                  │
      │                 │        └──────────────► Predictor ─► Policy (Utility+Q) │
      │                 │                                          │              │
      │                 │                                          ▼              │
      │                 │                                   Tactics → BehaviorTree│
      │                 │                                          │              │
      │                 │                                          ▼              │
      │                 │   CreatureCore ◄── Steering ──► Locomotion / Grapple    │
      │                 │        │                                                │
      │                 │        ▼                                                │
      │                 │   TendrilRig (Fabrik + secondary motion) ─► Skeleton    │
      │                 │        │                                    │           │
      │                 │        ▼                                    ▼           │
      │                 │   KillChoreography ─► GoreService      Replicator       │
      │                 │        │            └► HealthService       │            │
      │                 └────────┼────────────────────────────────────┼───────────┘
                                 │                                    │
                        RE_CreatureEvent                 RE_SkeletonStream (Buffer)
                                 │                                    │
┌────────────────────────────────┼────────────────────────────────────┼───────────┐
│                                ▼                                    ▼           │
│                     CreatureAudio / VibrationFx      SkeletonInterpolator        │
│                                                              │                  │
│                                                              ▼                  │
│                                            LocalRigDriver → Bone.Transform      │
│                                                        or → Model:PivotTo       │
│                                CLIENT                                           │
└─────────────────────────────────────────────────────────────────────────────────┘
                                 ▲
                     LightingDriver ◄── TimeModel ◄── attrs / RE_TimeSync
```

---

## 7. Module responsibilities (contract summary)

| Module | Public surface (intended) | Must NOT |
| --- | --- | --- |
| `Lib/RNG` | `new(seed)`, `:next()`, `:range(a,b)`, `:int(a,b)`, `:pick(t)`, `:weighted(t)`, `:gaussian()`, `:fork()` | touch `math.random` global |
| `Lib/Fabrik` | `solve(joints, lengths, target, opts) -> boolean`, `solveChain(...)` | touch instances |
| `Lib/Genetics` | `roll(rng, archetype)`, `mutate(g,rng)`, `crossover(a,b,rng)`, `express(g) -> stats`, `fitness(g, record)` | do I/O |
| `Lib/UtilityAI` | `select(options, ctx, rng) -> action`, `score(...)` | mutate the creature |
| `Lib/QLearning` | `new(cfg)`, `:q(feats, action)`, `:act(feats, rng)`, `:learn(feats, a, r, feats2)`, `:serialize()` | persist directly |
| `Lib/MarkovPredictor` | `observe(from,to)`, `predict(from, k)`, `serialize()` | allocate per call |
| `Shared/NoiseField` | `new(cfg)`, `:emit(channel, x, y, z, i, now, opts?)`, `:emitAt(...)`, `:sample(channel, x, y, z, radius, now)`, `:sampleAll`, `:loudestChannel`, `:setWind(x, y, z)`, `:setWeather(entry)`, `:remove`, `:prune(now)`, `:count`, `:clear` | raycast (perception does); move/re-insert impulses (advection is sampled backwards from `now`) |
| `Shared/Skeleton` | `new(count, opts)`, `:setJoint(i, x, y, z)`, `:straighten`, `:setRestPose`, `:reset`, `:copyFrom`, `:totalLength`, `:radiusAt`, `:setUp`, `:markDirty/:isDirty/:clearDirty` | allocate per frame; change lengths or taper (genome data, replicated once) |
| `Shared/SkeletonCodec` | `encode(out, skels, core, ref, seq, id, quat) -> count, reconCore`, `decode(bytes, skels, ref) -> core, seq, quat`, `byteCount`, `normaliseQuat`, `coreDisplacement` | use JSON; touch a `buffer` (the adapters live in `Creature/Replicator`) |
| `Shared/Remotes` | `init()`, `get(name)`, `await(name, timeout)`, `bindAll(timeout)`, `names()`, `clientToServer()`, `definition(name)`, `coverageProblems(schemas)` | create a remote on a client; create anything not in `Definition` |
| `Shared/NetContract` | `validate(schema, payload)`, `admit(gate, key, schema, payload, now)`, `newGate()`, `allow`, `forget`, `limits`, `stats`, `.Schemas`, `.Reject`, `.Actions` | coerce a bad payload into a plausible one (reject instead); trust any field it did not declare |
| `Shared/TimeModel` | `phaseOf`, `phaseClock`, `phaseSpan`, `phaseProgress`, `phaseWeight`, `phaseSeconds`, `cycleSeconds`, `nextPhase`, `minutesToClock`, `clockToMinutes`, `skyKey`, `sunElevation`, `nextMoonPhase`, `moonBrightnessDelta` | write Lighting (clients only); invent a phase boundary that is not in `DayNightConfig` |
| `Services/*` | `init()`, `start()`, `stop()`, plus domain API | be required by `Lib` |
| `CreatureCore` | `new(genome, spawn)`, `:step(dt)`, `:think()`, `:sense()`, `:destroy()` | call remotes directly |

Dependency direction (enforced by `tools/call-graph.js`):

```
Lib  ◄──  Shared  ◄──  Services / Creature  ◄──  Bootstrap / Controllers
```

Nothing in `Lib` may require `Shared`. Nothing in `Shared` may require `Services`.

---

## 8. Naming & coding conventions

1. Files: `PascalCase.luau`. One primary export per file.
2. Modules return either a table of functions (stateless) or a table with `.new()`
   (stateful). Never both.
3. Types live **only** in `Types.luau`; other modules `require` it for annotations.
4. No magic numbers in code. Every tunable goes into a `Config/*` module. This is
   enforced socially *and* by `tools/find-dead-config.js` (which catches config that
   nothing reads).
5. Config keys are `PascalCase` and every key must be read somewhere (the audit
   flags orphans).
6. Signals use `Lib/Signal`, never `BindableEvent`, unless crossing an actor
   boundary.
7. Errors: services `pcall` all external boundaries (DataStore, remotes, path
   finding). A creature that errors is **despawned with a diagnostic**, never left
   half-alive.
8. Every `while`/`task.spawn` loop must be tracked so `stop()` can cancel it.

---

## 9. Performance budget (hard numbers)

Target: **60 Hz server** on a 4-core small instance, 4 players, 2 creatures.

| Subsystem | Frame budget | Notes |
| --- | --- | --- |
| All creature actors (IK + steering) | 1.2 ms | ~60 joints × 2 creatures solved per frame |
| Perception | 1.0 ms | ≤ 24 raycasts + 8 spatial queries per tick |
| Destruction | 0.5 ms | amortised; integrity BFS capped at 64 nodes/step |
| Survival/slow | 0.4 ms | 1 Hz |
| Replication encode | 0.3 ms | Buffer packing only |
| **Total server logic** | **≤ 3.4 ms / 16.6 ms** | leaves ≥ 13 ms for physics + engine |

Client: `CreatureRenderer` ≤ 0.5 ms/frame/creature.

Watchdogs (built in `ServerScriptService/Vitriol/Diagnostics/Profiler`):
- If a cadence exceeds 2× budget for 10 consecutive samples, it **auto-degrades**
  one LOD tier and reports to `TelemetryService`. Self-preservation over fidelity.

---

## 10. Feature flags

`GameConfig.Features` gates every in-progress system so partial builds are always
playable:

```
Features = {
    CreatureIK        = true,
    CreatureLearning  = true,   -- Q-learning on/off (A/B the "cunning")
    SpeciesPersistence= false,  -- MVP off; cross-server evolution
    Destruction       = true,
    Vehicles          = true,
    Weather           = false,
    DebugNoiseMarkers = false,
    DebugDecisionDump = false,
}
```

A flag that ships `false` for two iterations gets **deleted**, not left rotting
(`find-dead-config.js` will surface it).

---

## 11. Persistence layout

| Store | Kind | Key | Contents |
| --- | --- | --- | --- |
| DataStore `Vitriol_Species_v1` | `UpdateAsync` | `species:{universeSlot}` | genome pool (top 12), aggregated action priors, night count |
| DataStore `Vitriol_Players_v1` | `UpdateAsync` | `p:{userId}` | run stats, unlocks, last death |
| MemoryStore `VitriolSession` | SortedMap, 45 d max expiry | `session:{jobId}` | live session handshake, server-to-server species exchange |

Rules: all writes go through `PersistenceService` (one place), all calls are
`pcall`'d with retry/backoff, and **nothing blocks the frame loop** — persistence
runs on `task.spawn` with rate limiting. See `08-RESEARCH-NOTES.md` §7 for the
verified API constraints.

---

## 12. File header convention (mandatory)

Every source file begins with its Explorer location and class, e.g.

```lua
--!strict
-- Fabrik.luau
-- Location: ReplicatedStorage > Vitriol > Lib > Fabrik  (ModuleScript)
-- Purpose:  Constrained FABRIK inverse-kinematics solver. Pure: no instances.
-- Requires: (none)
-- Used by:  ServerStorage > Vitriol > Creature > Body > TendrilRig
```

This is required by the project owner and makes the on-disk `code/` tree
unambiguous even without Studio open.

---

## 13. How this repo is verified

| Command | What it proves |
| --- | --- |
| `node tools/check-syntax.js <paths>` | the Luau parses (missing `end`, typos) |
| `node tools/metrics.js --src code` | LOC / complexity / require counts per file |
| `node tools/hot-loop-scan.js --src code` | expensive calls inside loops/frames |
| `node tools/call-graph.js --src code` | dependency direction + orphaned exports |
| `node tools/find-dead-config.js --src code` | config keys nothing reads |
| `node tools/vitriol-smoke-test.js` | **executes** the pure `Lib`/`Shared` modules in fengari and asserts real behaviour |
| `node tools/vitriol-session-test.js` | **executes** the server: a fake DataModel + virtual clock, the real `Bootstrap` and services, and the WP4 acceptance criteria (a zero-player cycle, one log line per phase change, `Lighting` untouched, no second scheduler) |
| `bash tools/audit.sh` | all of the above (note: `validate-project` expects a Rojo `default.project.json`, which this project deliberately does not have — that one check is expected to report the missing project file) |

Both harnesses share `tools/lib/luau-transform.js`, and that is load-bearing: the
transform is *stricter* than a Lua parser on purpose (it throws on `continue`, on a
backtick anywhere in a line of code — including inside a comment — and on a multi-line
function head), because a harness that silently mangles a file tests something other
than what was written. `task.wait`, `task.spawn` and `task.delay` are poisoned in the
session harness for the same reason: a service that invents a scheduler should fail
loudly, and it does.

`find-dead-config.js` scans two paths by default; to check a config you just changed,
pass both flags — `--src code --file code/ReplicatedStorage/Vitriol/Config/X.luau` — or
it will report every top-level block as dead.

`tools/validate-project.js` is Rojo-oriented by design; this project is
Explorer-first, so treat its "missing project file" output as expected rather than
a failure. Everything else must be green.

Three documented exceptions, all verified by running the tools:

- `tools/check-syntax.js` uses **luaparse (Lua 5.1)**, which cannot parse bitwise
  operators or `{T}?` optional type annotations. `Lib/RNG.luau` (xorshift32) and
  `Lib/Noise.luau` (permutation-table indexing) legitimately use bitwise ops and
  will always fail this one tool; both are instead *executed* for real by
  `vitriol-smoke-test.js` under Lua 5.3, which is stronger evidence than a parse.
  Prefer `any` over `{T}?` elsewhere so the parser stays useful.
- Both `check-syntax.js` and `vitriol-smoke-test.js` expand the Luau compound
  assignment operators (`+=` and friends) **on one line**. A multi-line
  right-hand side — `total += f(x, function() ... end)` — therefore breaks them.
  Assign to a local first, then accumulate. (`vitriol-smoke-test.js` now tracks
  the open paren across lines; `check-syntax.js` does not, so treat the one-line
  form as the rule.)
- `Shared/NoiseField.luau` and any other module that `require`s a sibling is only
  testable because `vitriol-smoke-test.js` rewrites `require(script.Parent.X.Foo)`
  to a lookup of the last path segment in its `MODULES` map. **A new module with a
  dependency must be added to that map** or the harness cannot load it.
- The backtick rule in `vitriol-smoke-test.js` fires on the **raw line**, before
  comments are masked. A prose comment that quotes an identifier in backticks
  therefore fails the harness exactly as an interpolated string does. Use 'single
  quotes' in the comment text of any module under test.
- `buffer` is shimmed in the harness preamble with the documented Roblox semantics
  (0-based offsets, fixed size, out-of-range access errors, `writeu8` requires an
  integer in `[0,255]`). That is what lets `Creature/Replicator`'s byte-array ⇄
  Buffer adapters be *executed* here: it proves the adapter's indexing arithmetic
  and byte fidelity, not Roblox's allocator. Anything else about buffers must still
  be checked in Studio.
- A module under test must resolve its dependencies through `require(script.Parent…)`
  or an injected `cfg` field — never a service lookup at load time. `Replicator`,
  `Remotes` and `TimeService` therefore take their dependencies from Bootstrap and
  only fall back to `game:GetService` lazily, inside a function.
- Two harnesses, two purposes: `tools/vitriol-smoke-test.js` runs the **pure** layer
  (`Lib/`, `Shared/`) and its `MODULES` map is hand-kept, while
  `tools/vitriol-session-test.js` boots the **whole server** (Bootstrap + services + the
  two handler Scripts) on a fake DataModel with a virtual clock, resolving `require`
  against every file in `code/` by basename. That is why the session harness has no
  module map — a service can be added without touching tooling, and adding a slot
  cannot silently skip the cadence accounting, because the harness asserts against
  `CadenceService:summary()` rather than a hand-written expectation.
- Luau forms that the harness **rejects** rather than mangling: backtick strings,
  `continue`, `{T}?` generics, multiplicative hash mixers (overflow 2^53 in fengari
  → `no integer representation`), `x + 2^32` integer normalisers, and any multi-line
  function head whose close is not `,)`. Prefer `any` over `{T}?`; prefer `local q =
  ...; x = x + q` over a multi-line `+=`. Shared transform (both harnesses):
  `tools/lib/luau-transform.js`.
- `tools/call-graph.js` and `tools/find-dead-config.js` will report every
  `Lib`/`Shared` export and Config key as unused until WP1–WP10 build their
  consumers. That is the expected state of a foundations iteration, not a defect —
  but it must trend to zero.
- **Citations follow one house style:** `docs/NN §A.B` means heading `A.B` where the
  target has sub-headings, and item `B` of `§A`'s numbered list where it does not
  (`docs/01 §5.1` = rule 1 of §5; `docs/02 §9.2` = a real sub-heading; `docs/06 §5.6` =
  rule 6 of §5). A third form letters a sub-option: `docs/07 §3.1A` is option A inside
  §3.1. Check both readings before "fixing" a pointer — and never leave a citation to a
  section that resolves under neither (docs/03's §9 is collision groups; an audio contract
  does not live there, it is `docs/06 §5.6`).
