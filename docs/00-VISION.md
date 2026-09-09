# VITRIOL — Vision & Design Bible

> **Iteration 1 deliverable.** This document is the creative and systemic north star.
> It is deliberately opinionated: every later document inherits the decisions made here.
> If a later document contradicts this one, **this one wins** until it is deliberately revised.

---

## 1. The pitch

**Vitriol** is a co-op night-survival horror game. By day you scavenge, barricade,
repair and drive across a dying rural town. At dusk the light fails and **the
creature** wakes — a blind, eyeless knot of tendrils that hunts by vibration,
scent, heat and *memory*. It learns how your group behaves. It gets better every
night. It does not spawn from a list: it **evolves**.

The player's fantasy is not "shoot the monster". It is:

> *"We made it to 4 a.m. because I remembered that it checks the garage second,
> not first — and it only learned that from us."*

**One-line design goal:** every system exists to either **emit information** the
creature can read, or **consume information** the creature has produced.

---

## 2. Design pillars (use these to reject features)

### P1 — The creature is the game
Everything else is stagecraft. If a feature does not change how the creature is
perceived, avoided, wounded or survived, it is decoration. Decoration is allowed,
but it is never the priority.

### P2 — Blindness is symmetry
The creature has no eyes, so it builds a picture of the world from **non-visual
channels**. The player should be pushed into the same discipline: you survive by
*listening*, by reading dust and vibration, by noticing that the birds stopped.
Sight is the *least* reliable sense in Vitriol for both sides.

**Consequence:** no glowing red eyes, no visible "aggro cone", no outline through
walls. Presence is communicated through **audio, physics, and environmental
response** (dust falling, water rippling, lights browning out, dogs barking).

### P3 — Every action is a broadcast
Footsteps, gunfire, engine impacts, breaking planks, generators, radios, bleeding,
even *falling over from exhaustion* — all of it is signal on the creature's
channels. The destruction and vehicle systems are not a side-show: they are the
loudest microphones in the game. **Fun that is loud must cost something.**

### P4 — Adaptation must be legible
A monster that silently becomes smarter feels like a cheat. Every adaptation
ships with a **tell** the player can read:

| What it learned / gained | The tell the player sees |
| --- | --- |
| Learned your hide spots | Checks them first; you can *watch* it walk to the attic on night 4 |
| Evolved more tendril mass | Visibly thicker, slower to fit through vents |
| Evolved speed | Audibly different gait (higher-pitch scrape cadence) |
| Learned to breach walls | Wall dust pre-falls before it comes through |
| Learned to lure | Its lure uses a *voice cadence* you have heard before |

### P5 — The night is a pressure dial, not a timer
Night length, creature count and creature capability are all driven by a single
**Threat Level** number. Content is balanced against Threat Level, not against
clock time.

### P6 — Death is a scene, not a screen
Being caught is a 6–12 second **procedural event** (see `04-KILL-CHOREOGRAPHY.md`).
It is the game's signature moment and it is never a canned animation: the
creature tenderizes, coils, consumes and discards based on its own genome, the
victim's body integrity, and how the grab happened.

### P7 — Systems compound, they don't stack
Hunger is not a bar; hunger raises your scent and lowers your sprint, which
changes your route, which changes what you see, which changes what the creature
learns. If a mechanic can be tuned without touching another system, it is
probably under-designed.

---

## 3. Core loop

### 3.1 Macro loop (the whole game)

```
        ┌──────────────────────────────────────────────────────────┐
        │                                                          │
   DAY (scavenge/fortify/repair/drive)                             │
        │  ── emit information (noise, scent, EM) ─────────────┐   │
        ▼                                                      │   │
   DUSK (transition; creature surfaces)                        │   │
        ▼                                                      ▼   │
   NIGHT (hide / flee / wound it / survive)          CREATURE MEMORY
        │                                                      │   │
        ▼                                                      ▼   │
   DAWN (survivors, wounds persist, resources consumed)   EVOLUTION PASS
        │  ── species genome mutates, Q-priors update ────────────┘
        └──────────────────────────────────────────────────────►
```

### 3.2 Micro loop (60-second scale, at night)

```
perceive threat → decide (hide / move / bait / fight / drive) → act (make noise)
      ▲                                                              │
      └──────────── creature reacts to the noise you just made ◄──────┘
```

### 3.3 Player verbs (what players actually *do*)

- **Move** (walk / crouch / sprint / crawl) — noise & stamina cost ladder.
- **Carry & haul** (supplies, planks, bodies of the dead, fuel).
- **Barricade** (planks over doors/windows; the plank system is the same one cars smash).
- **Drive** (cars are both transport and weapons; they are also the loudest thing in the game).
- **Consume** (eat / drink / treat wounds).
- **Sense** (hold still and listen; a dedicated "attune" input boosts your own perception).
- **Hide** (containers, under floors, in water — water masks scent *and* vibration).
- **Wound** (traps, fire, vehicles, falling structures — you rarely kill it outright).
- **Signal** (radio/flare: coordinate with teammates, but it emits EM the creature reads).
- **Die loudly** (your corpse keeps emitting scent for the rest of the night; your last
  known position enters the creature's memory and biases it *tomorrow*).

---

## 4. The creature — creative brief

- **Name in-fiction:** the Vitriol / "the sour thing" / "the braid".
- **Form:** no head, no eyes, no face. A knotted **core** of compressed tendril
  muscle, from which 6–12 tendrils radiate. It has no fixed silhouette: it
  reconfigures constantly (a tripod one second, a flat carpet the next).
- **Locomotion:** it does not walk. It **anchors and pulls** — tendrils find
  purchase on walls, ceilings, cars, trees, then the core is hauled forward. It can
  hang from ceilings, flow down stairs like rope, and (if its genome allows) flatten
  under doors.
- **Hunting:** it is an apex ambush predator with the patience of a spider and the
  burst of a mantis shrimp. It will wait 90 seconds. It will also come through a
  wall at 40 studs/second. Which one depends on its **genome** and its **learned
  policy**.
- **Feeding:** it does not bite. It **coils**, then **tenderizes** — rapid,
  high-frequency shear from the tendril friction ruptures tissue inside the skin
  (exactly the constrictor-snake analogy). Then it draws the remains into the core.
  Limbs that come loose during tenderizing are sometimes **taken** and carried off.
- **Voice:** wet rope under tension, cartilage popping, a low sub-bass that players
  feel before they hear. When it lures, it produces *approximations* of human
  speech — close enough to make you hesitate, wrong enough to make your skin crawl.

### 4.1 Why "cunning" is achievable, not marketing
"Cunning" = the player can construct a sentence of the form *"it knew that I would
…"*. Three mechanisms deliver that:

1. **Prediction** — a per-player Markov model of behaviour→destination
   (`docs/02-MONSTER-DESIGN.md` §7). It intercepts instead of chasing.
2. **Policy learning** — feature-based Q-learning with eligibility traces, so it
   learns *sequences* ("stalk → wait at the door → charge" beats "charge" against
   this group).
3. **Species memory** — across nights, successful genomes and aggregated action
   priors persist. On night 5 the creature checks the place your last group died.

---

## 5. Idea bank (propose, prototype, cut freely)

Ranked by *(impact ÷ cost)*. Marked **[CHEAP]**, **[MID]**, **[COSTLY]**.

### 5.1 High impact, low cost
1. **[CHEAP] The Attune input.** Hold a key to stop moving, kill your own footstep
   audio, and boost a visual "vibration" overlay (screen-space dust/ring pulses
   from recent noise events, reusing the creature's own noise field). Turns the
   creature's perception system into a *player* tool for free — one shared
   `NoiseField` module, two consumers.
2. **[CHEAP] Corpses keep emitting.** A dead player's body is a scent source that
   decays over ~6 minutes and a permanent entry in the creature's spatial memory.
   Players must decide whether to drag bodies away (loud, slow) or leave bait.
3. **[CHEAP] Rain as a stealth resource.** Weather modulates sound propagation.
   Heavy rain halves vibration range. Players who learn this will *wait for rain*.
4. **[CHEAP] Generators are dinner.** Powered lights/safe-houses emit EM that
   passes through walls. Safety and visibility are literally the same cost.
5. **[CHEAP] Wounds persist.** A wounded creature limps / loses a tendril for the
   rest of the night *and* starts the next night with a `Scar` entry in its genome
   that biases its policy (it avoids the trap type that hurt it). Readable,
   memorable, nearly free (one flag + a utility weight).
6. **[CHEAP] Silence budget HUD-less.** No meters on screen — your breath, heart
   rate and stomach audio tell you your state. Debuffs arrive as *sounds* before
   they arrive as numbers.

### 5.2 High impact, medium cost
7. **[MID] The Lure.** One specialised tendril can hold a "bait" — a dropped
   backpack, a ringing phone, an approximation of a teammate's voice (built from
   pre-recorded phoneme-free syllables, never real chat). Lure quality scales with
   the `Cunning` gene.
8. **[MID] Structural collapse as a weapon.** Players can topple a water tower or
   a porch onto the creature (big damage, big noise). Uses the same joint-graph
   destruction system as cars smashing planks.
9. **[MID] The Burrow.** At high `Cunning`, the creature travels under the terrain
   between anchor points and erupts. Telegraphed by ground dust + sub-bass.
10. **[MID] Cars as barricades.** A car pushed into a doorway is the strongest
    barricade in the game and the creature must either breach it (loud, slow) or
    find another way. Emergent fortification with no new code.
11. **[MID] Blood trails.** Damage leaves persistent decal+scent markers; the
    creature follows them with visibly higher confidence (faster, less searching).
12. **[MID] The Mimic Body.** At very high Threat Level it wears a coat of
    *previous victims'* clothing/gear as camouflage. Purely cosmetic but the
    storytelling is enormous, and it is one skinned-mesh swap.

### 5.3 High impact, higher cost
13. **[COSTLY] Cross-server species evolution.** MemoryStore-backed genome pool +
    action priors shared between servers of the same experience. "The Vitriol on
    your server is genuinely different from mine."
14. **[COSTLY] Multiple species/archetypes** with different sensory emphasis (a
    "Screamer" that hunts by air-sound only, a "Root" that never moves but extends
    tendrils through the whole map).
15. **[COSTLY] Player-side adaptation.** Tools that specifically blind one channel
    (vibration dampeners, scent masks, Faraday bags) — an arms race against the
    creature's evolving sensory emphasis.

### 5.4 Explicitly rejected (do not build)
- **Visible health bars on the creature.** It is not a boss fight. Use posture,
  tendril count and recoil flinches.
- **A "monster vision" outline through walls.** Violates P2.
- **Safe rooms that are simply un-enterable.** Violates P4/P7. Safe rooms must be
  *expensive*, not absolute.
- **Random jump-scare spawns unconnected to player behaviour.** If it appears, the
  player must be able to reconstruct *why*.
- **Chat-recording mimicry.** Privacy and moderation risk; use authored audio.

---

## 6. Reference DNA

| Reference | What we take | What we refuse |
| --- | --- | --- |
| **Carrion** | Body horror, tendril physics, the *kill* as spectacle, gore as vocabulary | Player-as-monster framing; we keep the player human and vulnerable |
| **Alien: Isolation** | A single persistent, learning predator; hiding as a resource; audio legibility | Its scripted "Director" reveals; ours must be reconstructable |
| **Left 4 Dead AI Director** | Pacing pressure, tension/release, threat-level dial | Spawning enemies from nothing; ours is always the same persistent animal |
| **The Thing / Annihilation** | Body reconfiguration, wrongness, "it is still in here" | Cosmic hand-waving; our rules are legible and consistent |
| **Rain World** | Ecology that runs without you, procedural creature motion, ecosystem simulation | Punishing opacity; ours must be *learnable* by the player |
| **Project Zomboid / Green Hell** | Survival meter coupling, food/water/debuff economy, craft-and-fortify | Spreadsheet depth; ours stays readable in a 20-minute session |

---

## 7. Tone & art direction (brief for human-authored assets)

- **Palette:** sodium-vapour amber by day, cyan-moonlight blue-black by night, and a
  single accent colour reserved **exclusively** for the creature: a sick
  yellow-green (vitriol). Nothing else in the game uses it.
- **Silhouette:** the creature should be identifiable as a *2D silhouette only* —
  no lighting, no colour. Design the tendril count/curve so the outline reads at
  100 studs.
- **Audio rule:** the creature never uses a stock roar. Its sound set is
  **organic friction** (rope, wet cloth, cartilage, suction) plus sub-bass.
- **UI rule:** diegetic first. Meters are sound and screen effects; numbers appear
  only in a "Field Notes" menu the player opens deliberately.

---

## 8. Session shape & scope

### 8.1 Target session
- **8–14 minutes** per full day→night cycle for a 1–4 player server.
- Day: **~4 minutes** (scavenge). Night: **~4–8 minutes**, scaling with Threat Level.
- A "run" is 3–5 cycles. Death is permanent for the run (corpse persists).

### 8.2 MVP scope (what the first playable must contain)
1. One creature archetype ("The Braid"), 8 tendrils, genome-driven.
2. Day/night with seamless transitions and a Threat Level.
3. Hunger/thirst with **Parched**, **Starved**, **Collapse**.
4. One destructible structure type (planked house) + one drivable car.
5. The full kill choreography (grab → coil → tenderize → consume → discard).
6. Noise emission → creature perception → hunting. This is the spine; nothing else
   is MVP if this isn't right.

### 8.3 Anti-scope for MVP
No cross-server evolution, no multiple archetypes, no weather, no radios, no
base-building beyond planks, no player animations beyond Roblox defaults.

---

## 9. What AI builds vs what a human builds

**Hard rule (from the project owner):** where a human will produce a better
result, do **not** generate it with code — specify it precisely instead.

| Built by AI (code) | Built by human (spec only — see `10-HUMAN-AUTHORED.md`) |
| --- | --- |
| Creature simulation: skeleton, IK, FABRIK, physics | Creature **meshes & rigs** (skinned mesh + bone chains) |
| Perception, prediction, genetics, RL, behaviour | The **map / environment** (town, interiors, roads) |
| Day/night time model + lighting driver | **Skyboxes** (day/dusk/night), textures, terrain |
| Survival meters, debuffs, item effects | **UI** (menus, HUD, Field Notes) |
| Destruction joint-graph, debris pooling, debris physics tuning | **Debris/prop meshes**, plank & furniture models |
| Vehicle controller, impulse/damage model | **Car meshes** and their wheel/suspension setups |
| Kill orchestration, region integrity | **BloodEngine/Blood visuals and optional limb presentation** (supplied module) |
| Replication, remotes, session flow, persistence | **All audio** (creature voices, ambience, foley) |
| Config, tuning, tooling, tests | **Player animations** (crawl, carry, bandage) |

> **Integration dependency:** the supplied BloodEngine/Blood v1.1.3 source and
> `Assets.rbxm` are checked into `code/ReplicatedStorage/VModules/BloodEngine` under
> its MIT license. `04-KILL-CHOREOGRAPHY.md` §3 records the adapter contract, and
> `BloodAdapter` still degrades gracefully until the source is imported into the
> matching Studio Explorer hierarchy and its real visuals are verified.

---

## 10. Success criteria for the whole game

1. A player can, after three nights, correctly **predict the creature's next move**
   more often than chance — and explain why.
2. The creature's behaviour across two nights is **visibly different**, and the
   difference is attributable to something the players did.
3. A kill is watchable by the *other* players and is **never identical twice**.
4. Server frame cost stays inside the budgets in `01-ARCHITECTURE.md` §9 with 4
   players and 2 creatures on a 4-core small server.
5. Every adaptation is reconstructable by the player from information the game
   already gave them.
