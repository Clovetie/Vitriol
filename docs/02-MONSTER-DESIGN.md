# VITRIOL — Monster Design (mind, memory, genetics, learning)

This is the most important document in the project. The creature is the game
(`00-VISION.md` P1). Everything here is specified to be **implementable in Luau
within the budgets in `01-ARCHITECTURE.md` §9** — no hand-waving, no "AI magic".

---

## 1. The organism

### 1.1 Body plan

```
                    ┌──────────────┐
        tendril 1 ◄─┤              ├─► tendril 5
                    │              │
        tendril 2 ◄─┤    CORE      ├─► tendril 6
                    │  (knotted    │
        tendril 3 ◄─┤   muscle,    ├─► tendril 7   (specialised: SPEAR)
                    │  ~1.5 studs) │
        tendril 4 ◄─┤              ├─► tendril 8   (specialised: FEEDER)
                    └──────────────┘
```

- **Core**: the mass, the "body". Kinematically driven (see `03-MONSTER-TECH.md`).
  Holds the stomach (consumption), the heart (damage/vitals), and the brain state.
- **Tendrils**: kinematic chains of 8–16 joints. Count, length, thickness, tip type
  and specialisation are **genome-driven** (6–14 for the MVP archetype).
- **Specialisations** (rolled per tendril from the genome, max 1 per tendril):
  | Type | Function | Cost gene |
  | --- | --- | --- |
  | `NONE` | general anchor / coil | — |
  | `SPEAR` | hardened tip, puncture, can breach weak joints | `Armour` |
  | `ANCHOR` | high-friction tip, wall/ceiling grip, climb | `Adhesion` |
  | `LURE` | thin, expressive tip; carries the mimic bait | `Cunning` |
  | `FEEDER` | wide, high-friction; the tenderizing limb | `Metabolism` |
  | `SENSE` | dense vibration hairs; +range on the Vibration channel | `SenseVibration` |

- **No eyes, no face.** There is no "front". Orientation is a *behavioural* choice,
  not an anatomical one — which is exactly why it can come from any direction.

### 1.2 The creature has needs too

The predator is on the same survival clock as the players (P7 — systems compound):

| Need | Mechanic | Consequence |
| --- | --- | --- |
| **Metabolism** | drains with movement ∝ mass × speed² | at 0 it is **Desperate** |
| **Injury** | accumulates from cars, collapse, fire, traps | reduces speed, adds a limp tell, persists into next night as a `Scar` gene |
| **Exposure** | being hit by bright light / fire for long | flinch, brief disorientation (players can buy time, not kill) |
| **Confidence** | rises with successful hunts, falls with lost trails | modulates ε (exploration) and risk appetite |

**Desperate** creatures take stupid risks: ε jumps, `Charge` prior doubles, they
ignore injury. This is real predator ecology (a starving animal is a dangerous and
*dumb* animal) and it gives players a strategic lever: **starve it across nights**.

---

## 2. Senses (the perception model)

Six channels. Each has an acuity gene, a range model, and its own failure modes.
All channels are **sampled by `NoiseField`**, one shared module used by both the
creature *and* the player's Attune UI (see `00-VISION.md` §5.1.1).

| Channel | Emitted by | Range model | Blocked by | Boosted by |
| --- | --- | --- | --- | --- |
| `VIBRATION` | footsteps, impacts, breaks, vehicles, collapse, falling | `r = Rv · √(I) · coupling` | water (decouples), soft ground absorbs | hard surfaces (road/concrete ×1.6), rain mask ×0.5 |
| `AIR` | voice, gunfire, radios, engine | inverse-square + occlusion raycast | walls (occlusion raycast), distance | open ground |
| `SCENT` | players (base), blood (×6), sprint sweat (×2), corpses (×4, decaying) | diffusion: `I(t) = I₀·e^(−t/τ)`, advected by wind | water immersion (masks) | wind downwind ×1.5, heat |
| `THERMAL` | living bodies, engines, fires | short: `r = Rt` (~14 studs) | thin walls only (×0.4), thick walls block | fire, engine heat |
| `EM` | generators, powered lights, radios, flares | `r = Re · P` | **nothing** (passes through walls) | higher power draw |
| `PRESSURE` | fast-moving bodies very close | `r = Rp` (~6 studs) | nothing | relative velocity |

Implementation notes (all verified API in `08-RESEARCH-NOTES.md`):
- Occlusion is **one** `workspace:Raycast` per candidate per tick, budgeted
  (`MonsterConfig.Senses.MaxOcclusionRaysPerTick`).
- Broad-phase candidate discovery is **one** `workspace:GetPartBoundsInRadius`
  with a cached `OverlapParams` per tick — never `.Touched`.
- `NoiseField` is a **`SpatialHash`** of decaying impulses; `sample()` sums
  contributions in the relevant cells. O(1)-ish, allocation-free.

**Who owns which term** (settled in WP3 — the module and this table must agree):

| Term | Owner | Why there |
| --- | --- | --- |
| exponential decay, half-life per channel | `Shared/NoiseField` | propagation, observer-independent |
| **wind advection** of `SCENT` | `Shared/NoiseField` | the plume moves in the world; every observer sees the same shift |
| **rain / storm masking** of `VIBRATION`, `AIR` | `Shared/NoiseField` (`setWeather(DayNightConfig.Weather.X)`) | the Attune overlay must show what the creature hears (P2); a multiplier per sense module would let them disagree |
| **surface coupling** (`×1.6` concrete, `×0.1` water) | `Shared/NoiseField` at **emit** time, from `MonsterConfig.Senses.VibrationCoupling` | the surface is a property of the event, and it is stored once instead of multiplied per sample |
| acuity thresholds, localisation error, the downwind `×1.5` sniff boost, water-immersion masking of the *smeller* | `Creature/Brain/Senses` | these describe a nose, not a world |
| advection search window | `MonsterConfig.Senses.AdvectionMaxAgeSeconds` | see below |

Advection is evaluated at **sample** time by tracing the query point backwards along
the wind by the age of each impulse, so nothing is ever re-inserted or moved — the
field stays write-cheap, parallel-safe and unit-testable. The cost of doing it
honestly is that the cell search has to widen by the largest drift it could miss, so
the search is capped at `AdvectionMaxAgeSeconds` of drift (20 s ⇒ 60 studs at a
brisk wind, versus 344 studs for the scent's full audibility lifetime). An impulse
older than that is skipped rather than sampled at a clamped position, which is the
right split anyway: *old* evidence is episodic memory (`§3`), stored in interest
cells, not a live field.

### 2.1 From sensation to perception

```lua
-- pseudo-code, ServerStorage > Vitriol > Creature > Brain > Senses
local raw = NoiseField.sample(corePos, channel)      -- 0..N intensity
if raw < threshold(gene.acuity, channel) then return nil end

-- Localization: the better the acuity, the smaller the positional error.
local errScale = (1 - acuity) * CHANNEL_ERROR[channel]
local estimate = truePos + rng:gaussian3() * errScale * dist
return {
    channel    = channel,
    position   = estimate,
    confidence = clamp(raw / threshold - 1, 0, 1) * acuity,
    time       = now,
}
```

Key design consequence: **a low-acuity creature gets the *fact* of a noise but a
bad *location*.** It investigates the wrong door. That is the difference between a
monster that feels dumb and one that feels fallible — and fallible is what makes
"cunning" legible.

---

## 3. Memory

Three tiers, all in `Brain/Memory`.

### 3.1 Working memory (seconds)
A ring buffer of the last 12 perceptions. Drives immediate reactions.

### 3.2 Episodic / spatial memory (the night)
A `SpatialHash` grid (8-stud cells) of **interest scores**:

```
interest(cell) += w_kill·[kill here] + w_catch·[grabbed here]
               + w_sight·[perceived prey here] + w_noise·[loud noise here]
interest(cell) *= decay^dt          -- τ ≈ 90 s
```

Uses: patrol-route weighting, "check the last place", choosing ambush spots.

### 3.3 Semantic memory (across nights — the scary part)
| Record | Content | Written when |
| --- | --- | --- |
| `PreyModel[playerKey]` | Markov transitions over `LocationClass × PostureClass` | continuously, per player |
| `TimeHeatmap[bucket]` | where prey tend to be per sixth-of-night | continuously |
| `Hazards[type]` | "cars hurt", "fire hurts", "the porch collapses" | on taking damage |
| `Dens[]` | quiet, dark, central spots it has rested in | on resting |
| `Scar[]` | injury records that bias tactics | on injury |

`Hazards` is what makes it *stop* walking into your trap on night 3.

---

## 4. Prediction — how it "knows what you'll do"

### 4.1 The model
Per player, a **first-order Markov chain** over abstract states:

```
state = LocationClass × PostureClass
LocationClass ∈ {Open, Road, House, Garage, Basement, Roof, Woods, Water}   -- 8
PostureClass  ∈ {Idle, Scavenging, Fleeing, Hiding, Driving, Fighting}      -- 6
→ 48 states, 48×48 = 2304 counts per player. Trivial memory.
```

`LocationClass` is **authored**, not computed: the human-authored map tags regions
with `PathfindingModifier`/`CollectionService` tags (`Vitriol_Zone_Garage`, …).
This is one of the "human makes it better" items in `10-HUMAN-AUTHORED.md`.

### 4.2 Prediction query

```lua
-- Lib/MarkovPredictor
function MarkovPredictor.predict(self, fromState, k)
    -- returns up to k most probable next states with probabilities
end
```

`Predictor` then maps probable states → concrete world anchors (region centroid or
the specific door the player always uses) and hands `Policy` a list of
**intercept candidates**.

### 4.3 Predictability score (the mechanic players will feel)

```
H(player) = −Σ p_i · log p_i            -- entropy of their transition row
predictability = 1 − H / log(n_states)
```

- `predictability > 0.6` → the creature gets a large bonus on `AMBUSH` and
  `INTERCEPT`, and a **tell** is exposed (it stops searching and walks *directly*;
  its scrape cadence changes).
- `predictability < 0.3` → it falls back to searching and sweep patterns.

**This is the single most important teaching mechanism in the game:** players who
vary their behaviour survive; players with a routine get caught. It must be
discoverable (Field Notes + the tell), never hidden.

---

## 5. Genetics — the genome

### 5.1 Genes (MVP archetype `Braid`)

Every gene is a float in `[0,1]` unless marked `int`.

| Gene | Range | Effect | Metabolic cost |
| --- | --- | --- | --- |
| `Speed` | 0–1 | core haul speed, tendril retraction | 0.14 |
| `Strength` | 0–1 | grip force, breach damage, throw power | 0.13 |
| `Endurance` | 0–1 | sprint duration, metabolism drain | 0.09 |
| `Mass` | 0–1 | size, collision mass, damage soak | 0.12 |
| `Adhesion` | 0–1 | wall/ceiling grip, climb | 0.07 |
| `Softness` | 0–1 | squeeze under doors, through vents | 0.06 |
| `SenseVibration` | 0–1 | Vibration channel acuity | 0.05 |
| `SenseAir` | 0–1 | Air channel acuity | 0.05 |
| `SenseScent` | 0–1 | Scent channel acuity + trail half-life | 0.05 |
| `SenseThermal` | 0–1 | Thermal range | 0.04 |
| `SenseEM` | 0–1 | EM range (reads your generators) | 0.04 |
| `Cunning` | 0–1 | lure quality, planning depth, prediction use | 0.10 |
| `Patience` | 0–1 | willingness to wait/stalk | 0.04 |
| `Aggression` | 0–1 | burst commitment, ε floor (lower ε = more decisive) | 0.05 |
| `Metabolism` | 0–1 | feed efficiency, hunger rate | 0.08 |
| `Regeneration` | 0–1 | injury recovery rate | 0.06 |
| `Armour` | 0–1 | damage resistance | 0.09 |
| `TendrilCount` | 6–14 `int` | more limbs = parallel actions | 0.02/each over 6 |
| `TendrilLength` | 0–1 | reach (segments × length) | 0.05 |
| `ShearRate` | 0–1 | tenderizing damage rate | 0.06 |
| `GripTenacity` | 0–1 | how hard to break a coil (button-mash threshold) | 0.05 |

### 5.2 The metabolic budget (why there are no super-monsters)

```
Σ (gene_value × gene_cost) + tendril_overhead  ≤  BUDGET(threatLevel)
```

`BUDGET` grows slowly with Threat Level (night 1 ≈ 0.85, night 5 ≈ 1.15).
`Genetics.roll()` samples genes then **projects** them onto the budget simplex, so
a fast creature is necessarily a fragile or dim one. This is the single most
important balance lever in the game and it is one line of code.

### 5.3 Mutation / crossover / fitness

```lua
-- Lib/Genetics
mutate(g, rng):
    for each gene: g[i] += rng:gaussian(0, σ)         -- σ = 0.06 baseline
    if rng:next() < P_STRUCTURAL: TendrilCount ± 1     -- visible! players notice
    re-project onto budget
    occasionally (P_SCAR) copy a Scar from the parent

crossover(a, b, rng):
    uniform crossover per gene, biased toward the fitter parent (dominance 0.6/0.4)

fitness(g, record):
    = 3.0·kills + 1.0·grabSeconds/60 + 0.5·damageDealt/100
    − 1.5·damageTaken/100 − 0.8·nightsDied + 0.3·survived
```

`EvolutionService` at dawn:
1. Collect all genomes + fitness records from the night.
2. Keep the top `K=12` (elite), plus 2 random immigrants (drift).
3. Fill the next pool by crossover+mutation of elites.
4. Persist to `Vitriol_Species_v1`.
5. **Also** aggregate every creature's learned action priors into a species-level
   prior (mean weights, exponentially smoothed) → new creatures inherit "folk
   knowledge" but **not** the full Q table. Learned behaviour is not inherited;
   the *capacity* for it is. (Baldwin effect — biologically correct and it avoids
   the runaway-feedback problem of inheriting learned weights.)

### 5.4 Species drift is a *feature* to surface
Tendril count, mass class and colour shift are **visible**. Players should be able
to say "the thick one is back".

---

## 6. Genome → temperament (the "AI decides its best form of hunting")

This is the mechanism the project owner asked for explicitly: *if speed and
strength are abundant, be aggressive — unless it has learned that stalking pays*.

### 6.1 Instinct prior (from stats)

```lua
-- raw instinct scores, 0..1
instinct.CHARGE   = 0.45*Speed + 0.35*Strength + 0.20*Aggression
instinct.STALK    = 0.35*Patience + 0.30*Cunning + 0.20*(1-Aggression) + 0.15*(1-Mass)
instinct.AMBUSH   = 0.40*Patience + 0.30*Cunning + 0.20*Speed + 0.10*Adhesion
instinct.BREACH   = 0.55*Strength + 0.30*Mass + 0.15*Armour
instinct.LURE     = 0.65*Cunning + 0.20*Patience + 0.15*(1-Aggression)
instinct.BURROW   = 0.50*Softness + 0.30*Adhesion + 0.20*Cunning
instinct.FLUSH    = 0.40*Strength + 0.35*Aggression + 0.25*Speed
instinct.CIRCLE   = 0.45*Speed + 0.30*Cunning + 0.25*Adhesion
instinct.FEIGN    = 0.60*Cunning + 0.30*Patience + 0.10*(1-Mass)
instinct.RETREAT  = 0.40*(1-Endurance) + 0.30*injury + 0.30*(1-Confidence)
instinct.CONSUME  = 1.0 when holding prey (not selectable otherwise)

logPrior(a) = log(clamp(instinct[a], 0.02, 1))
```

### 6.2 Instinct vs experience

```lua
score(a) = Q(s, a) + κ · logPrior(a)
```

- `κ` starts high (`Config.KappaNewborn = 2.5`) — a newborn trusts its body.
- `κ` anneals toward `Config.KappaVeteran = 0.6` as the creature accumulates
  successful decisions (`κ = lerp(Kv, Kn, e^(−experience/τ))`).
- A **fast, strong** creature therefore *starts* aggressive. If charging keeps
  failing against a coordinated group (cars, collapse, fire), Q drops and it
  **switches to stalking anyway** — exactly the "or maybe stalks people anyways!"
  case. The switch is observable: it stops committing and starts circling.

---

## 7. The action set (tactics)

| Action | Requires | What it does | Typical duration |
| --- | --- | --- | --- |
| `SEARCH` | — | sweep patrol weighted by spatial memory + time heatmap | 10–40 s |
| `STALK` | prey perceived | approach using cover, low noise, break line of… *vibration* | until within `commitRange` |
| `AMBUSH` | prediction + a cover spot | move to predicted destination, go still, wait | up to 90 s |
| `CHARGE` | prey within `commitRange` | full-speed pursuit + grab attempt | 3–8 s |
| `CIRCLE` | prey at mid range | strafe to flank/ herd toward a hazard | 4–12 s |
| `FLUSH` | prey hiding, known cell | slam/bang the structure to force them out (loud!) | 2–5 s |
| `BREACH` | obstacle + `Strength` gate | smash through a wall/plank/door | 3–10 s |
| `LURE` | `Cunning` gate + a LURE tendril | drop/emit bait near prey | 5–20 s |
| `BURROW` | `Softness`/`Adhesion` gate | travel under terrain between anchors (telegraphed) | 2–6 s |
| `FEIGN` | `Cunning` gate | go limp/partially withdraw, look defeated, then strike | 3–15 s |
| `INTERCEPT` | prediction confidence > 0.5 | move to cut off predicted route | 4–10 s |
| `RETREAT` | injured / low confidence | disengage, hide, recover | 10–30 s |
| `CONSUME` | holding prey | the kill choreography | 6–12 s |

Each action is a **parameterised behaviour tree** (`Brain/Tactics`), executed by
`Brain/BehaviorTree`, moving via `Brain/Steering`.

---

## 8. Learning — the RL specification

### 8.1 Algorithm
**Linear-function-approximation Q-learning with replacing eligibility traces**
(SARSA(λ) variant), Boltzmann action selection, reward shaping that is
**potential-based** (so it cannot distort the optimal policy — Ng, Harada & Russell,
1999).

Why not a deep network: Luau has no GPU, no autodiff, and a 16 ms frame. A linear
model over ~200 binary features is ~200 multiply-adds per decision — effectively
free — and it is **inspectable**, which matters because we must be able to explain
the creature's behaviour to players (`00-VISION.md` P4) and debug it (`AIDebugDump`).

### 8.2 State features (binary vector, ~200 dims)

| Group | Features | Count |
| --- | --- | --- |
| Night phase | 6 buckets | 6 |
| Light level at creature | 4 buckets | 4 |
| Distance to best prey | 5 buckets | 5 |
| Prey count perceived | 0/1/2/3+ | 4 |
| Prey posture | 6 classes | 6 |
| Prey predictability | 3 buckets | 3 |
| Last perception channel | 6 channels + none | 7 |
| Time since last perception | 4 buckets | 4 |
| Trail state | {none, cold, warm, hot} | 4 |
| Self injury | 4 buckets | 4 |
| Metabolism | 4 buckets | 4 |
| Confidence | 3 buckets | 3 |
| In structure / outdoors / on wall | 3 | 3 |
| Hazard nearby (from `Hazards` memory) | 4 types | 4 |
| Noise in last 3 s | 4 buckets | 4 |
| Prey in vehicle | bool | 1 |
| **Total** | | **66** |

Action-conditioned features = `66 × 13 actions = 858` weights worst case; in
practice we use a shared trunk + per-action bias (~79 weights). Keep it simple
first, grow only if telemetry says the policy is under-fitting.

### 8.3 Update rule

```
Q(s,a)  = w[a] · φ(s) + b[a]
δ       = r + γ·max_a' Q(s',a') − Q(s,a)          γ = 0.94
e(a)    = φ(s)                                     (replacing traces)
e(·≠a) *= γλ                                       λ = 0.80
w(a)   += α·δ·e(a)                                 α = 0.09, decaying 1/(1+n/n₀)
```

Action selection:

```
p(a) ∝ exp( (Q(s,a) + κ·logPrior(a)) / τ )         τ anneals 1.4 → 0.35
```

### 8.4 Rewards

| Event | r |
| --- | --- |
| Grab / initiate coil | **+8** |
| Complete consumption | **+25** |
| Newly localise prey (info gain) | +1.2 |
| Within 5 studs of prey (per second) | +0.10 |
| Lose a hot trail | −2.0 |
| Take damage | −0.10 per HP |
| Damaged by a *trap type already in `Hazards`* | extra −4.0 (it should have learned) |
| Prey flees away from an attempted ambush | −1.5 (revealed itself) |
| Energy spent | −0.008 per unit |
| Elapsed | −0.02 per second (must resolve the hunt) |
| Potential shaping | `+γΦ(s′) − Φ(s)`, `Φ(s) = −dist_to_best_known_prey / 100` |

### 8.5 Episode & persistence
- Episode = one night. `QLearning:serialize()` at dawn → a compact weight table.
- Per-server weights persist in `Vitriol_Species_v1` per genome lineage, so a
  creature lineage that keeps returning to the same server gets genuinely better.
- The **species prior** (aggregate `b[a]`) is what new creatures inherit.

### 8.6 Guardrails (do not skip)
1. **Reward clamping** at ±30 to stop trace explosion.
2. **Weight norm cap**; if `‖w‖` exceeds a bound, scale down (prevents blow-ups).
3. **Exploration floor**: ε never below 0.05 — a creature that stops exploring stops
   being surprising.
4. **Never learn from a frame that errored.**
5. **Determinism**: all randomness comes from `Lib/RNG` seeded per creature so
   replays/debug dumps reproduce exactly.

---

## 9. Layered brain (how it all composes)

```
GENOME ──express──► STATS ──► INSTINCT PRIOR ─┐
                                              │
PERCEPTION ─► MEMORY ─► PREDICTION ─┐         │
                                    ▼         ▼
                               ┌─────────────────────┐
                               │  POLICY             │  UtilityAI ⊕ Q-learning
                               │  (4–8 Hz, staggered)│  → picks a TACTIC
                               └─────────┬───────────┘
                                         ▼
                               ┌─────────────────────┐
                               │  BEHAVIOR TREE      │  execute/abort/retry
                               └─────────┬───────────┘
                                         ▼
                               ┌─────────────────────┐
                               │  STEERING           │  seek/pursue/avoid/anchor-seek
                               └─────────┬───────────┘
                                         ▼
                               ┌─────────────────────┐
                               │  LOCOMOTION + IK    │  anchors, haul, FABRIK solve
                               └─────────────────────┘
```

### 9.1 Why *utility* on top of *Q*, not instead of
Utility AI gives designers a **readable, tunable** layer (curves you can reason
about in a spreadsheet); Q-learning supplies the **learned correction** that makes
it adapt. Utility alone = predictable; Q alone = opaque and unbalancable. Together:
tunable *and* adaptive. `UtilityAI` computes base scores from needs/perception;
`Policy` adds `Q` and the instinct prior.

### 9.2 Interruption & arbitration
- `CONSUME` and `RETREAT` are **high-priority interrupts**; anything else can be
  preempted by a stronger stimulus (`|Δscore| > 0.25` and a 0.4 s refractory to
  stop flapping).
- **Commitment**: once `CHARGE` starts, a minimum commitment timer (0.8–2 s from
  `Aggression`) prevents instant flip-flop. Predators commit.

---

## 10. Archetypes

### 10.1 `Braid` — MVP
8–14 tendrils, generalist, all channels, all actions. Described above.

### 10.2 `Screamer` (post-MVP, data-only addition)
- Extreme `SenseAir`, poor `SenseVibration`. Hunts by sound only.
- Emits a piercing call that **masks** players' ability to hear (disables the
  Attune overlay) — a channel-warfare archetype.
- Action set: `SEARCH, STALK, CHARGE, FLUSH, LURE` (no `BURROW`, no `FEIGN`).

### 10.3 `Root` (post-MVP)
- Never relocates its core. Extends extremely long tendrils (24 joints) through the
  whole map. `SenseVibration` extreme. `Speed` ~0.
- Players must **map** it and route around it. It is a territory, not a pursuer.

Adding an archetype = one MD in `ServerStorage/Vitriol/Creature/Archetypes` +
genome ranges + a rig asset. **No changes to `CreatureCore`.**

---

## 11. Legibility contract (every adaptation gets a tell)

| Adaptation | Tell (must be authored) |
| --- | --- |
| High `predictability` exploit | Stops searching; moves in a straight line; scrape cadence quickens |
| Learned `Hazards` | visibly reroutes around the trap/collapse site |
| High `Speed` gene | higher-pitch, faster scrape cadence; shorter coil wind-up |
| High `Strength` gene | wall dust pre-falls 0.6 s before a breach |
| `LURE` tendril | bait object has a subtly wrong geometry; audio is 1 semitone flat |
| Injury / `Scar` | permanent limp on one anchor cycle; fewer usable tendrils |
| High `TendrilCount` | silhouette change, visible at 100 studs |
| Desperate (starving) | erratic, over-commits, ignores injury; audible wheeze in sub-bass |
| High `SenseEM` | generators flicker as it "tastes" them (0.3 s brown-out tell) |

If an adaptation has no tell, **cut the adaptation**. That is the rule.

---

## 12. Difficulty curve

| Night | Threat | What the player experiences |
| --- | --- | --- |
| 1 | 0.20 | Naive, high ε, no memory. It blunders. Players learn the rules. |
| 2 | 0.35 | It returns to where it caught someone. First "how did it know?" |
| 3 | 0.50 | Ambushes predicted destinations. Avoids known hazards. |
| 4 | 0.70 | Genome visibly shifted. Multiple creatures may coordinate loosely. |
| 5+ | 0.85+ | Species priors kick in. It plays *your group*, not the average group. |

Coordination between multiple creatures is deliberately **loose** (shared spatial
memory only, no telepathy) — coordinated monsters read as cheap unless the player
can see the information channel.

---

## 13. Open questions for the project owner

1. Should a creature be **killable**, or only woundable/driven off? (Design
   recommendation: woundable only for MVP; a kill should be a rare, engineered
   event — collapse a tower on it.)
2. How many creatures at Threat 1.0? (Recommendation: 1 at night 1, 2 by night 4.)
3. Is cross-server species evolution (`SpeciesPersistence`) in scope for the first
   playable? (Recommendation: no — ship per-server first.)
4. Should dead players be able to **watch** their own kill in first person?
   (Recommendation: yes, and then spectator-follow the creature.)
