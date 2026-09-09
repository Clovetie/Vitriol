# VITRIOL — Human-Authored Assets (spec, not code)

Per the project owner's rule: **where a human will do better, do not generate it.**
This document is the complete brief. Each section states the Explorer hierarchy,
the hard technical constraints the code depends on, and a prompt you can hand to an
artist/designer (or to an AI art tool for concepting).

Nothing in this file should be replaced by generated Luau.

---

## 1. The map / environment

### 1.1 Why a human must build this
The map is the game's readability layer. The creature's intelligence is only
impressive if the space supports *prediction*: distinct, memorable, nameable
places. Procedurally generated greybox would make the AI's learning invisible.

### 1.2 Required hierarchy

```
Workspace
└─ Map (FL)
   ├─ Zones (FL)                       ← the creature's LocationClass vocabulary
   │  ├─ Zone_Garage (PT, anchored, CanCollide=false, CanQuery=false, Transparency=1)
   │  │     [CS: Vitriol_Zone]  Attributes: ZoneClass="Garage", ZoneName="Miller's Garage"
   │  ├─ Zone_House_01 (PT)            ZoneClass="House"
   │  ├─ Zone_Basement_01 (PT)         ZoneClass="Basement"
   │  ├─ Zone_Road_Main (PT)           ZoneClass="Road"
   │  ├─ Zone_Woods_North (PT)         ZoneClass="Woods"
   │  ├─ Zone_Roof_01 (PT)             ZoneClass="Roof"
   │  ├─ Zone_Water_Mill (PT)          ZoneClass="Water"
   │  └─ Zone_Open_Field (PT)          ZoneClass="Open"
   ├─ Structures (FL)                  ← destructibles (see 1.4)
   ├─ Interiors (FL)                   ← searchable containers, doors, windows
   ├─ Roads (FL)
   ├─ Nature (FL)
   ├─ Lighting_Anchors (FL)            ← lamp posts (EM emitters when powered)
   └─ NavHints (FL)
      └─ PathfindingModifier_* (PT)    ← Label + cost regions (docs/08 §5)
```

### 1.3 Hard constraints
- **`ZoneClass` values are fixed**: `Open, Road, House, Garage, Basement, Roof,
  Woods, Water`. The predictor's state space (`docs/02` §4.1) is built from these
  eight. Adding a ninth requires a config change *and* invalidates learned models.
- Zone parts must be `CanCollide = false`, `CanQuery = false`, `Transparency = 1`,
  `Anchored = true`. They are pure metadata volumes.
- Zones must **tile the playable space with no gaps** — a player standing somewhere
  with no zone breaks prediction silently.
- Every zone should have a distinct **acoustic identity** (see §4) so players can
  localise by ear.

### 1.4 Destructible structure authoring
Follow `docs/07-DESTRUCTION-VEHICLES.md` §2.1 exactly. Key points repeated because
they are the ones that get missed:
- Tag the model `Vitriol_Structure`; structural parts `Vitriol_Joint`.
- Structural parts start **anchored**.
- Glass/trim live under `Skin/` and never affect integrity.
- `Meta` (a `Configuration`) declares material class and adjacency.
- **Build at least one porch whose two corner posts, when removed, bring the roof
  down.** That is the acceptance test for the integrity system.

### 1.5 Brief / prompt

> Build a small, hand-crafted rural American town for a night-survival horror game
> (Roblox, ~600×600 studs playable). Mood: *annihilation-of-the-ordinary* —
> everyday places made wrong by darkness. Palette: sodium amber by day, cyan-blue
> night, and one reserved accent (sick yellow-green) that appears **only** on
> creature-related objects.
>
> Required places (each must be a distinct, nameable, memorable location — the AI
> learns these by name): a main road with a filling station, a garage with a
> working lift, two two-storey houses with porches (destructible corner posts), a
> church with a bell tower (climbable, great vantage), a mill by a water channel,
> a woods edge with a drainage culvert (the creature can burrow through it), a
> field with a water tower (topplable), and a basement with a generator.
>
> Design for **sound**: hard surfaces on the road (vibration carries), soft soil in
> the woods (it doesn't), a covered porch that makes noise *louder*, and one long
> sightline from the church tower so players can watch the creature cross the
> field at night.
>
> Design for **hiding that isn't safe**: under-floor crawlspaces, a storm cellar,
> a car boot, the mill's grain silo. Each must be enterable and each must have a
> cost (you can't see out, you can't hear well, or you're trapped).
>
> Deliverables: the `Workspace.Map` hierarchy in §1.2 with all zone volumes, zone
> tags and attributes; destructible structures per §1.4; and a one-page map with
> the zone labels so the AI/config author can wire `PathfindingModifier` costs.

---

## 2. UI

### 2.1 Why a human must build this
`docs/00-VISION.md` §7 forbids HUD bars. That is an *art direction*, and the
resulting UI is unusual enough that generating it from code would produce exactly
the wrong thing (a bar).

### 2.2 Required hierarchy

```
StarterGui
└─ VitriolGui (ScreenGui)                ResetOnSpawn=false, IgnoreGuiInset=true
   ├─ FieldNotes (Frame)                 ← the only place numbers appear; closed by default
   │  ├─ Title (TextLabel)
   │  ├─ Meters (Frame)                  Hunger/Thirst/Health as *text + thin rules*
   │  ├─ Notes (ScrollingFrame)          ← creature observations the player has earned
   │  └─ Close (TextButton)
   ├─ Cues (Frame, BackgroundTransparency=1)
   │  ├─ InteractionPrompt (Frame)       ← diegetic "hold E" near world objects
   │  ├─ CarryIndicator (Frame)
   │  └─ SubtitleHint (TextLabel)        ← for the creature's lure vocalisations
   ├─ Vignette (ImageLabel)              ← driven by PostProcessDriver, not by UI code
   └─ Menus (FL)
      ├─ MainMenu (Frame)
      ├─ PauseMenu (Frame)
      └─ Settings (Frame)                ← including Gore Intensity (docs/04 §5)
```

### 2.3 Hard constraints
- `StarterGui` is **not** where logic lives. `SurvivalHud` (LocalScript) only
  tweens existing elements; it never creates GUI.
- `FieldNotes` is closed by default and opened deliberately — it is a *menu*, not a
  HUD.
- The `Settings` menu **must** expose Gore Intensity (`LOW`/`FULL`) —
  `docs/04` §5.
- All text must be legible at 480p (mobile) and support text-size scaling.

### 2.4 Brief / prompt

> Design a diegetic horror-survival UI for Roblox. **No health/hunger bars on the
> HUD, ever.** State is communicated by audio and post-processing. The only numbers
> live inside a "Field Notes" journal the player opens on purpose — a
> handwriting/typewriter aesthetic, like a survivor's notebook, with hand-drawn
> sketches of the creature that fill in as the player learns its habits.
>
> Deliver: `StarterGui.VitriolGui` per §2.2, with 9-slice frames, a 3-state
> interaction prompt (idle / hover / hold-progress ring), a settings panel with a
> gore-intensity toggle, and a pause menu. Style: muted paper, ink, one accent
> colour used *sparingly*. Motion: everything eases; nothing snaps.

---

## 3. Creature meshes & rigs

### 3.1 Why a human must build this
Skinned-mesh authoring with correct joint scale and weight painting is a
craft skill, and the *silhouette* is the game's identity (`docs/00` §7). Generated
geometry will not read at 100 studs.

### 3.2 Required hierarchy (per archetype)

```
ServerStorage
└─ Vitriol
   └─ Assets
      └─ CreatureRigs (FL)
         └─ Braid (MO)                       ← the archetype rig
            ├─ Meta (CFG)                    ← joint counts, taper table, material refs
            ├─ Core (MP)                     ← skinned mesh, bones below
            │  ├─ Bone_Core (BN)
            │  └─ Bone_Heart (BN)
            └─ TendrilTemplate (MP)          ← ONE tendril, cloned/posed at runtime
               ├─ Bone_00 (BN)
               │  └─ Bone_01 (BN)
               │     └─ ... Bone_15 (BN)
               ├─ Tip_NONE (MP)
               ├─ Tip_SPEAR (MP)
               ├─ Tip_ANCHOR (MP)
               ├─ Tip_LURE (MP)
               └─ Tip_FEEDER (MP)
```

### 3.3 Hard technical constraints (from `docs/08` §2)
- **Bones must be unscaled at bind time** and must not be scaled when posing.
  Non-uniform joint scale breaks Roblox skinning. Use translation for
  squash/stretch.
- Bone **names** are the skinning contract. Use `Bone_00 … Bone_NN`, zero-padded,
  in root→tip order. `TendrilRig` looks them up by name.
- The chain must be at least 8 bones for `NEAR` LOD and the first 4 must be
  usable alone for `FAR` LOD (`docs/03` §8.3).
- Do **not** put `Motor6D`s in the creature rig — it is bone-driven.
- Bones are not serialized: author them in the asset, they will load, but runtime
  code must not assume any authored `Transform` persists.
- Provide the tendril at a **neutral rest pose** (straight, +Y along the chain) so
  `Fabrik.blendToRest` has a clean reference.
- Scale: core ≈ 1.5 studs diameter; tendril length ≈ 10–14 studs at
  `TendrilLength = 0.5`.
- LOD: ship 3 mesh LODs per tendril (high / mid / impostor).

### 3.4 Brief / prompt

> Sculpt and rig a blind, eyeless tendril organism for Roblox: a knotted core of
> compressed muscle, ~1.5 studs across, with 8–14 organic tendrils radiating from
> it. **No head, no face, no eyes, no front.** It should read as a *braid*, not a
> spider.
>
> The silhouette must be identifiable as a pure black 2D silhouette at 100 studs.
> Surface language: wet rope, sinew, and cartilage — not insect, not tentacle-monster
> cliché. Reserve a sick yellow-green accent for the tips only.
>
> Technical: one skinned `MeshPart` per tendril with a 16-bone chain
> (`Bone_00…Bone_15`, root→tip), bones unscaled at bind, neutral straight rest pose
> along +Y. Swappable tip meshes (NONE / SPEAR / ANCHOR / LURE / FEEDER). Three
> LODs. Export via FBX 7.4 with the Roblox AvatarImporter "Custom" preset.

---

## 4. Audio

### 4.1 Why a human must build this
`docs/00` §7 forbids stock roars. The creature's entire presence is audio, and
audio is the sense the game is built around (P2).

### 4.2 Required hierarchy

```
ServerStorage/Vitriol/Assets/Audio (FL)
├─ Creature (FL)
│  ├─ Scrape (Sound)         ← per-material variants: concrete/dirt/wood/metal
│  ├─ Tension (Sound)        ← rope under load (approach tell)
│  ├─ Coil (Sound)
│  ├─ Tenderize (Sound)      ← wet friction + cartilage
│  ├─ Consume (Sound)
│  ├─ SubBass (Sound)        ← felt before heard; the "it's near" signal
│  ├─ Flinch (Sound)
│  ├─ Lure_Syllables (FL)    ← authored phoneme-free syllables (NEVER recorded chat)
│  └─ Gait (FL)              ← cadence variants keyed to the Speed gene
├─ Ambience (FL)             ← Day / Dusk / Night / Rain beds (cross-faded)
├─ Foley (FL)                ← footsteps per surface, plank breaks, glass, car impacts
└─ Player (FL)               ← breathing (rate-driven), swallow, stomach, dry-mouth
```

### 4.3 Hard constraints
- **Gait cadence must be mappable to the `Speed` gene** — the code changes playback
  rate and interval; supply loops/one-shots that survive ±40% rate change.
- `SubBass` must be a separate `SoundGroup` so it can duck everything else.
- Every footstep surface in the map needs a matching foley set (the creature
  localises by them).
- Lure syllables must be **authored**, never recorded from players
  (`docs/00` §5.4).

### 4.4 Brief / prompt

> Design the sound of a blind organism that hunts by vibration. No roars, no
> growls, no stock monster library. The vocabulary is **friction**: wet rope under
> tension, sinew stretching, cartilage giving, suction releasing, and a sub-bass
> presence players feel in their chest before they hear it.
>
> Deliver: per-material scrape one-shots (concrete, dirt, wood, metal) that read at
> ±40% playback rate; a tension loop; a coil sound; a wet-friction tenderize loop;
> a "swallow"; a flinch; 6–8 phoneme-free lure syllables that are *almost* human;
> and three cross-fadeable ambience beds (Day / Dusk / Night) plus a Rain variant
> that audibly masks footsteps.

---

## 5. Skyboxes, lighting presets, post-processing looks

```
Lighting
├─ Sky_Day   (Sky)   CelestialBodiesShown=true,  StarCount=0
├─ Sky_Dusk  (Sky)   long amber horizon band — the money shot
└─ Sky_Night (Sky)   StarCount ~3000, MoonAngularSize tuned to the MoonPhase system
```

- Provide **overcast** variants of each if the weather system ships.
- Night skybox must stay legible at `Brightness 0.30` — the darkest keyframe
  (`docs/06` §3.1). Test it, don't assume.
- Set `Lighting.Technology`/`LightingStyle` to `Future` **in the Properties window**
  (`docs/06` §7) — it must not be scripted.

---

## 6. Debris & prop meshes

```
ReplicatedStorage/Vitriol/Assets/DebrisTemplates (FL)
├─ Wood_Splinter (MP)     ← 3 variants
├─ Wood_Plank (MP)
├─ Glass_Shard (MP)       ← 4 variants
├─ Masonry_Chunk (MP)     ← 3 variants
└─ Metal_Scrap (MP)       ← 2 variants
```

- Must be **small** (< 1 stud), low-poly (< 120 tris), and share one material atlas
  so the debris pool doesn't thrash materials.
- They are used by the pooled debris system (`docs/07` §2.5) — do not put
  `ParticleEmitter`s inside them; the code attaches those.

---

## 7. Player animations

```
ReplicatedStorage/Vitriol/Assets/Animations (FL)   (or ServerStorage — animator-safe)
├─ Crawl (Animation)
├─ Carry_Box (Animation)
├─ Carry_Plank (Animation)
├─ Bandage (Animation)
├─ Eat (Animation)
├─ Drink (Animation)
├─ Barricade (Animation)
├─ Crank_Generator (Animation)
└─ Collapse (Animation)        ← the fall from docs/05 §3.2
```

- Standard R15 rigs. Upload and record the asset IDs in a config
  (`GameConfig.AnimationIds`) — **IDs go in config, never hard-coded**.
- `Collapse` must read as *involuntary*. It is the scariest animation in the game
  because it is loud (`docs/05` §3.2).

---

## 8. The BloodEngine/Blood module (the outstanding dependency)

The supplied BloodEngine v1.1.3 source is checked into
`code/ReplicatedStorage/VModules/BloodEngine` with its MIT notice and `Assets.rbxm`.
For the Roblox place, import it so the Explorer path is
`ReplicatedStorage > VModules > BloodEngine`. The source checkout may appear as a
Folder whose `init` child is the ModuleScript; a root ModuleScript named
`BloodEngine` is also accepted by `BloodAdapter`.

Human Studio work still required:

1. Import the four ModuleScripts and `Assets.rbxm` without renaming `Operator`,
   `Settings`, `Functions`, or `Assets`.
2. Confirm the server can require the module and that `BloodAdapter` can construct
   it with the LOW settings; verify `Vitriol_Blood` is the intended replicated
   effect folder.
3. Check real droplet/pool visuals, collision filtering, cleanup, and the optional
   limb-presentation gate. Do not enable FULL or limb dismemberment by default.

If the real module's signature differs in the place, **only `BloodAdapter` changes**;
that is the point of the adapter. If Studio import is deferred, the bounded fallback
in `docs/04` §3.3 keeps the kill choreography playable.
