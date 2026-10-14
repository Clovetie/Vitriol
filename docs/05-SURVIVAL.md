# VITRIOL — Survival: Hunger, Thirst, Debuffs

> **Implementation status (2026-10-14):** The pure, locally tested
> `SurvivalModel` implements the *currently authored* real-minute config,
> timed exhaustion and post-validation consumable meter math. A pure
> `SurvivalConsumeAction` now verifies authored action time/interruptions
> and a one-use server inventory-commit callback, but no InventoryService
> or live item prompts are wired. A separate headless server adapter now
> uses fake ownership callbacks and the real NoiseField for AIR on successful
> commit; it is not a live InventoryService or active gameplay. An offline
> `SurvivalService` adapter owns per-player models and Health regen flags;
> `SurvivalCollapse` models the one-shot fall event; the explicitly invoked
> adapter has now emitted it into a **real headless NoiseField** in tests.
> None is Bootstrapped, scheduled, Studio-synced or running in-game. Section 7's
> Parched≈9min / Collapse≈16min acceptance targets conflict with these rates:
> nine walking minutes give thirst **7.2**, not Parched's **80**; even sixteen
> uninterrupted baseline sprint minutes give thirst **33.6**, hunger **15.2**,
> not Collapse. Do **not** silently speed up the meters or the owner's short
> Studio Day/Night phases. The mismatch needs an explicit pacing decision.
> See [`M6-SURVIVAL-MODEL-OFFLINE-2026-10-14.md`](M6-SURVIVAL-MODEL-OFFLINE-2026-10-14.md).

The survival layer exists for one reason: **to force the player out of hiding.**
A hiding-only game is a boring game. Hunger and thirst are the clock that makes
staying still a losing strategy — and because they raise your scent and lower your
speed, they are also the creature's best ally.

---

## 1. The meters

Two meters, both `0..100`, both **rising = worse** (they measure *need*, not
fullness). Server-authoritative (`SurvivalService`), replicated to the owning
player only via `RE_SurvivalSync`.

| Meter | Drain at rest | Drain walking | Drain sprinting | Drain carrying | Drain driving |
| --- | --- | --- | --- | --- | --- |
| **Thirst** | 0.55 /min | 0.80 /min | 2.10 /min | 1.10 /min | 0.70 /min |
| **Hunger** | 0.30 /min | 0.42 /min | 0.95 /min | 0.60 /min | 0.35 /min |

Modifiers (multiplicative, all in `SurvivalConfig.Modifiers`):

| Condition | Thirst | Hunger |
| --- | --- | --- |
| Bleeding (any wound) | ×1.35 | ×1.10 |
| Hot (near fire / engine) | ×1.25 | ×1.05 |
| Cold (night, unsheltered, raining) | ×1.10 | ×1.25 |
| In water (immersed) | ×0.90 | — |
| `Starved` | ×1.20 (thirst worsens when starving) | — |
| `Parched` | — | ×1.15 (hunger worsens when parched) |

**That last pair is the coupling the design requires:** the two meters accelerate
each other. A player who neglects one loses the other faster. Neither can be
ignored indefinitely.

---

## 2. Coupling formula (single source of truth)

```lua
-- SurvivalConfig.Coupling
thirstRate = base_thirst * activity * cond
             * (1 + Coupling.ThirstFromHunger * unitStep(hunger, 70))
hungerRate = base_hunger * activity * cond
             * (1 + Coupling.HungerFromThirst * unitStep(thirst, 70))

-- shared stamina drain is the third leg of the stool
staminaRegen *= (1 - Coupling.StaminaPenaltyPerMeter * (hunger/100 + thirst/100) * 0.5)
```

`unitStep(x, t)` is a smoothstep over 5 units around `t` — **never a hard cliff**;
players must not be able to feel an exact threshold (P4 legibility, but smoothly).

---

## 3. Debuffs

Debuffs are **declared as data** in `SurvivalConfig.Debuffs` — never `if` chains in
service code. Each debuff is a table of modifiers + effects + cues, applied by
`SurvivalService` from a single `apply()` path.

### 3.1 The three the project owner named, plus their lead-ins

| Debuff | Trigger | Effects | Player-facing cue |
| --- | --- | --- | --- |
| **`Dry`** (lead-in) | thirst ≥ 55 | `WalkSpeed ×0.97`, stamina regen ×0.9 | dry-mouth audio, subtle |
| **`Parched`** | thirst ≥ 80 | `WalkSpeed ×0.88`, `JumpPower ×0.85`, stamina regen ×0.65, screen desaturate, **scent emission ×1.5**, aim/interact sway | cracked-lip audio, screen thirst pulse, throat sound on sprint |
| **`Desiccated`** | thirst = 100 | `WalkSpeed ×0.70`, stamina regen ×0.35, `Health` −0.4/s, **scent ×2.0**, vision tunnel | heavy breathing, audio muffle |
| **`Peckish`** (lead-in) | hunger ≥ 55 | `WalkSpeed ×0.98`, stamina regen ×0.92 | stomach audio (audible to the creature at close range!) |
| **`Starved`** | hunger ≥ 80 | `WalkSpeed ×0.85`, `JumpPower ×0.80`, carry capacity ×0.6, `Health` −0.25/s, **region integrity ×0.85** (kills are faster), stamina regen ×0.5 | shaking hands, screen vignette, stomach growl — a *noise source* |
| **`Collapse`** | see §3.2 | see §3.2 | see §3.2 |
| **`Bleeding`** | any wound | `Health` −rate, **scent ×1 + 6·rate**, leaves blood trail markers | drip audio, screen blood |
| **`Sick`** | spoiled food / dirty water | all drains ×1.5 for 90 s, `WalkSpeed ×0.9` | nausea camera roll, vomit audio (loud!) |
| **`Exhausted`** | stamina 0 for > 3 s | `WalkSpeed ×0.75` for 6 s, forced heavy breathing (noise) | gasping |

### 3.2 `Collapse` — the signature failure state

**Trigger** (any of):
- `thirst = 100` **and** `hunger ≥ 80`
- `hunger = 100` **and** `thirst ≥ 80`
- `Health < 15` while both meters ≥ 60

**Onset:**
1. Stamina forced to 0, sprint disabled.
2. Vision tunnels hard; audio ducks to a low-pass; controls get a 0.4 s input lag.
3. After 1.5 s the player **falls** (ragdoll-lite: `Humanoid:ChangeState(Ragdoll)`
   or a scripted slump) — and the fall emits a **`VIBRATION` noise burst of
   intensity 0.9**. *Collapsing is loud.* This is the mechanic that makes the
   survival layer part of the horror rather than a parallel system.
4. For 8 s the player can only crawl (`WalkSpeed ×0.25`) and cannot interact,
   barricade, or drive.
5. Recovery requires consuming **both** food and water within the window; partial
   recovery leaves `Weakened` for 60 s.

**`Collapse` is not death.** It is a *summons*. The design intent is that the
player hears themselves fall, and then hears the creature change direction.

### 3.3 Effect vocabulary (what a debuff may modify)

```lua
{
    WalkSpeed      = 0.88,   -- multiplier
    JumpPower      = 0.85,
    StaminaRegen   = 0.65,
    HealthDrain    = 0.0,    -- per second
    ScentScale     = 1.5,
    CarryCapacity  = 1.0,
    InteractSpeed  = 1.0,
    NoiseScale     = 1.0,    -- footsteps etc.
    RegionIntegrity= 1.0,    -- kill speed
    ScreenFx       = {"ThirstPulse"},   -- handled by PostProcessDriver
    AudioCues      = {"dry_mouth"},     -- handled by SurvivalHud
    Duration       = math.huge,         -- or seconds
    Stacks         = false,
    Priority       = 50,                 -- for cue arbitration
}
```

`SurvivalService` composes them multiplicatively per key, with `ScreenFx`/`AudioCues`
deduplicated by `Priority`. One code path, infinitely many debuffs.

---

## 4. Consumption

| Item class | Restores | Notes |
| --- | --- | --- |
| Clean water | thirst −35 | rare, valuable |
| Dirty water | thirst −25, 35% `Sick` | boil it (fire = light = EM = detectable) |
| Canned food | hunger −40 | needs no prep; noisy to open (`AIR` 0.4) |
| Raw meat | hunger −20, 50% `Sick` | from… sources |
| Cooked meat | hunger −45 | requires fire |
| Spoiled food | hunger −15, `Sick` guaranteed | better than starving |
| Medkit / bandage | stops `Bleeding`, +25 `Health` | loud to apply |

Rules:
- Consumption takes **time** (1.5–3 s) and is **interruptible** by a grab — eating
  at night is a genuine risk decision.
- Eating/drinking emits a small `AIR` noise. Chewing is not free.
- Items are validated **server-side** by `InventoryService`; the client sends an
  intent, never a result.

---

## 5. Why no HUD bars

`00-VISION.md` §7: diegetic first. State is communicated by:
- **Audio**: breathing rate, swallow, stomach, dry-mouth clicks. Each debuff owns
  a cue; cues are arbitrated by `Priority` so they don't stack into noise.
- **Post-processing**: desaturation, vignette, tunnel, roll — driven by
  `PostProcessDriver` from the same debuff table.
- **Movement feel**: the speed/stamina multipliers *are* the feedback.
- **Field Notes** (a menu the player opens deliberately) shows numbers for players
  who want them.

No bar is ever drawn on the HUD. This is a hard art-direction rule and it is why
`SurvivalHud` is a *cue player*, not a widget drawer.

---

## 6. Systemic links (the compounding table)

| From | To | Effect |
| --- | --- | --- |
| `Parched`/`Desiccated` | creature `Senses` | scent emission ×1.5–2.0 |
| `Starved` | `KillChoreography` | region integrity ×0.85 → faster severs |
| `Starved` | `Interaction` | carry capacity ×0.6 → fewer planks → weaker base |
| `Collapse` | `NoiseField` | `VIBRATION` 0.9 burst → summons |
| `Bleeding` | `NoiseField` + persistence | scent trail + ground decals that persist |
| `Sick` | everything | drains ×1.5, and vomiting is *loud* |
| Cooking (fire) | `NoiseField.EM` + `THERMAL` | safety and detectability are the same knob |
| Cold (night/rain) | `Hunger` | the night itself makes you hungrier |

---

## 7. Acceptance criteria

1. With zero consumption, a player reaches `Parched` at ~9 min and `Collapse`
   at ~16 min of mixed activity. (Headless-testable: `SurvivalService` math is pure
   given a dt sequence — assert it in `tools/vitriol-smoke-test.js`.)
2. Neglecting thirst measurably accelerates hunger (assert the coupling term).
3. `Collapse` always produces a `VIBRATION` emission of the configured intensity.
4. Removing any debuff from `SurvivalConfig.Debuffs` requires **no** code change.
5. `find-dead-config.js` reports no unread keys in `SurvivalConfig`.
