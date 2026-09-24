# VITRIOL — QTE System (design, roster, integration)

Status: **code complete and gate-green** (`tools/vitriol-quality-gate.js` 9/9).
The server-side struggle hook (§8) is specified here and **not yet implemented** —
it is the next work package.

This document is the authority for the QTE system. `docs/02`/`docs/03` own the
creature's grip and escape maths; this file owns the skill checks that feed it.

---

## 1. What this replaces

The supplied `QTEManager.lua` (v5.0 "Major Expansion") was a single 2 500-line
client file with 55 QTE types, its own difficulty maths and its own GUI. It was
rewritten rather than patched. The rewrite keeps the *roster* and the *feel*, and
fixes the bugs the read-through found:

| v5 behaviour | Why it was wrong | Now |
| --- | --- | --- |
| `task.delay` guarded `QTE_NoPress` twice, so "do nothing" could resolve twice | resolution was not idempotent | `resolve()` in `Lib/QTEEngine` is first-call-wins |
| `QTE_ExactTaps` resolved inside a grace window after later presses arrived | counting continued past the verdict | the engine latches the verdict and ignores later input |
| `QTE_PhoneDial` forbade `0` while `NUM_MAP` included it | the dial could not answer its own answer | digits are tokens (`Zero`..`Nine`) with `DigitAliases`/`DigitTokens`; `0` works |
| Six QTEs ran their own sentinel + `Heartbeat` watchers | per-frame cost with no owner; qtes never cleaned up | one loop, started on `start()` and disconnected on `finish()` |
| `WaitForChild(name, 10)` inside `assert` | 10 is a timeout, not a boolean; the assert was always true | direct indexing with an explicit fallback (`QTEStruggle:findGui`) |
| `Balance`/`BalanceCorrection` registered twice | two entries, one behaviour, double weight | one entry (`BalanceCorrection`); duplicates are impossible (§5) |
| Time limits clamped to a flat `minTimeLimit` | "Insane + low HP" could produce an unanswerable limit | the floor is the QTE's own measured cost (§4) |
| `Hum:TakeDamage` / health writes from a presentation module | in Vitriol, `HealthService` alone writes player health (docs/01 §6) | the shell fires a `Signal`; consequences are opt-in |
| `GetMouseLocation()` treated as GUI space | it includes the topbar inset (docs/08 §10) | `GuiService:GetGuiInset()` is subtracted |
| `TouchEnabled` alone chose the device | a laptop with a touchscreen got phone prompts | `PreferredInput` + `*Enabled` flags, re-evaluated on `LastInputTypeChanged` |
| Sort orders and answers printed on screen during recall | memorise QTEs leaked their answer | the view carries `answerVisible`, `chips` masks the hidden half, and a test proves it |

---

## 2. Module map

| Explorer path | File | Responsibility |
| --- | --- | --- |
| `ReplicatedStorage > Vitriol > Config > QTEConfig` | `Config/QTEConfig.luau` | pure data: human input model, presets, pressure, grades, capability sets, input maps, word/number/colour/morse banks |
| `ReplicatedStorage > Vitriol > Lib > QTECatalog` | `Lib/QTECatalog.luau` | the 68 QTE definitions (id, label, mode, category, weight, caps, accent, generator) |
| `ReplicatedStorage > Vitriol > Lib > QTEEngine` | `Lib/QTEEngine.luau` | the 34 modes: cost, state machine, judging, widgets, `expect` solver channel |
| `ReplicatedStorage > Vitriol > Lib > QTEDirector` | `Lib/QTEDirector.luau` | picking, freshness, feasibility-correct time limits, grading, stats, custom registration |
| `StarterPlayer > StarterPlayerScripts > Vitriol > Controllers > QTEStruggle` | `Controllers/QTEStruggle.luau` | the only Roblox-aware file: input sampling, widget rendering, freeze, verdict, result signal |

The four `Config`/`Lib` modules are **pure**: no services, no Instances, no yields,
no `os.clock`, and every random draw comes from an injected `Lib/RNG`. That is what
lets the headless harness play all 68 QTEs (§9).

Requires are one-directional: `QTEConfig` → `QTECatalog` → `QTEEngine` →
`QTEDirector` → `QTEStruggle`. Nothing in `Lib/` may require a controller.

---

## 3. Input model

* The engine speaks **tokens**: `"E"`, `"Space"`, `"Up"`, `"Zero"`..`"Nine"`,
  `"KeypadFour"`, `"Click"`. It never sees a `KeyCode`, a `Vector2` or a `Color3`.
* `QTEConfig.InputMap` maps tokens to `Enum.KeyCode` names per device, and
  `QTEStruggle:buildInputMaps()` inverts it once at construction. A token may map
  to different keys per device (on gamepad, `E`/`R`/`F`/`Q` are `Y`/`B`/`A`/`X`).
* Typed answers convert characters to tokens in exactly one place:
  `QTEConfig.DigitTokens` + `QTEConfig.DigitAliases`, read through the engine's
  `tokenForChar`/`digitOf` helpers. A shell that sends `"4"`, `"Four"` or
  `"KeypadFour"` is understood; this is the class of bug that broke v5's dial pad.
* **Capabilities** (`Key`, `Pointer`, `Click`, `Look`, `Motion`) are declared per
  QTE and per device. `QTEDirector:pool()` filters on them, so a phone is never
  offered a keyboard QTE and a keyboard is never offered a "drag the cursor" QTE.
  A QTE answered by doing nothing declares `caps = {}`; a test enforces exactly
  that correspondence.

---

## 4. Time model (why no QTE is impossible)

```
cost.time = read + think + max(0, keys * Human.KeySeconds - think)
                              + pointer / Human.PointerScreensPerSecond

limit     = clamp(baseTime * preset.timeMult * adaptive * pressure,
                  max(cost.time, Timing.MinLimit),
                  max(floor, min(Timing.MaxLimit, baseTime * preset.timeMult)))
```

* `read` is "how long the instruction takes to read", `think` is the window the
  mode gives the player (a mash window, a hold, a flash sequence), `keys` is how
  many discrete presses are required, `pointer` is screens of pointer travel.
  Presses made *inside* the window are already paid for by `think`, which is why a
  four-second mash is not priced as "stand still for four seconds **and** mash
  thirty times".
* The lower clamp is the QTE's own cost, so **no combination of preset, health,
  streak or a bad seed can ship a limit shorter than the inputs require**. This is
  a property of the code, not a claim: a test runs all 68 QTEs × 4 presets × 6
  seeds at zero health and asserts `limit >= cost.time`.
* Pressure: `HealthFloor + HealthWeight * healthFraction` times a win-streak term,
  both floored, both bounded. A dying player is squeezed, never locked out.
* Adaptive difficulty steps down per win to `Adaptive.Floor` and snaps back to
  `Adaptive.OnLoss` on a loss.
* Cue windows have a fairness floor: an *unpredictable* cue (`react`, `quickdraw`)
  must stay open at least `Human.ReactionSeconds`; a regular beat may be tighter
  (rhythm), but never below 0.10 s.

---

## 5. Roster (68)

Families follow `docs/03` §3's taxonomy. Weight is the base pick weight; freshness
divides it by `1 + appearances * Freshness.AppearancePenalty`, so repeats fade.

**Reflex (9)**

| id | label | mode | weight | caps |
| --- | --- | --- | --- | --- |
| Press | Press | press | 10 | Key |
| React | React | react | 10 | Key |
| Dodge | Dodge | react | 9 | Key |
| Snap | Snap | react | 7 | Key |
| QuickDraw | Quick Draw | quickdraw | 7 | Key |
| DoubleTap | Double Tap | exact | 7 | Key |
| Ambush | Ambush | react | 6 | Key |
| ReflexMulti | Reflex Multi | hit | 6 | Click+Pointer |
| Sequence | Sequence | sequence | 8 | Key |

**Motor (9)**

| id | label | mode | weight | caps |
| --- | --- | --- | --- | --- |
| Spam | Mash | mash | 10 | Key |
| MultiSpam | Alternate | alternate | 8 | Key |
| TripleThreat | Triple Threat | alternate | 6 | Key |
| Survive | Survive | meter | 6 | Key |
| Crescendo | Crescendo | meter | 5 | Key |
| TugOfWar | Tug of War | tug | 5 | Key |
| ExactTaps | Exact Taps | exact | 6 | Key |
| Endure | Endure | hold | 6 | Key |
| Brace | Brace | holdAll | 5 | Key |

**Precision (10)**

| id | label | mode | weight | caps |
| --- | --- | --- | --- | --- |
| Aim | Aim | aim | 7 | Pointer |
| ClickTarget | Click Target | hit | 7 | Click+Pointer |
| Skeet | Skeet | hit | 4 | Click+Pointer |
| Shake | Shake | shake | 5 | Pointer |
| Spin | Spin | spin | 5 | Pointer |
| SafeCracker | Safe Cracker | spin | 3 | Pointer |
| Track | Track | track | 4 | Pointer |
| Trace | Trace | trace | 4 | Pointer |
| Steady | Steady | steady | 4 | Click+Pointer |
| HotCold | Hot / Cold | search | 4 | Pointer |

**Timing (7)**

| id | label | mode | weight | caps |
| --- | --- | --- | --- | --- |
| StepTiming | On the Beat | timed | 7 | Key |
| Metronome | Metronome | timed | 6 | Key |
| Rhythm | Rhythm | timed | 5 | Key |
| SlideBar | Slide Bar | release | 7 | Key |
| FuseCut | Fuse Cut | release | 5 | Key |
| TimedRelease | Timed Release | release | 6 | Key |
| PressureGauge | Pressure Gauge | gauge | 4 | Key |

**Memory (15)**

| id | label | mode | weight | caps |
| --- | --- | --- | --- | --- |
| Simon | Simon | memorise | 6 | Key |
| ReverseSeq | Reverse | memorise | 5 | Key |
| LastKeyFlash | Last Key | memorise | 6 | Key |
| PatternMemoryBurst | Memory Burst | memorise | 5 | Key |
| ColourSequence | Colour Sequence | memorise | 5 | Key |
| MemoryGrid | Memory Grid | grid | 4 | Click+Pointer |
| FlashDigit | Flash Digit | memorise | 5 | Key |
| PhoneDial | Phone Dial | memorise | 5 | Key |
| MemoryPalace | Memory Palace | memorise | 3 | Key |
| WordRecall | Word Recall | type | 6 | Key |
| WordType | Type It | type | 6 | Key |
| Spelling | Spelling | type | 4 | Key |
| RapidTyping | Rapid Typing | type | 5 | Key |
| MorseCode | Morse Code | morse | 3 | Key |
| CountFlash | Count Flash | count | 5 | Key |

**Cognition (12)**

| id | label | mode | weight | caps |
| --- | --- | --- | --- | --- |
| MathCalc | Calculate | type | 8 | Key |
| TrueFalse | True / False | classify | 8 | Key |
| EvenOdd | Even / Odd | classify | 7 | Key |
| NumberOrder | Number Order | sort | 6 | Key |
| SortPress | Alphabetise | sort | 5 | Key |
| StroopWord | Stroop Word | classify | 7 | Key |
| StroopInk | Stroop Ink | classify | 6 | Key |
| BiggerOf | Bigger | classify | 5 | Key |
| NextInSeries | Next In Series | classify | 4 | Key |
| Tally | Tally | classify | 5 | Key |
| Mirror | Mirror | symbol | 6 | Key |
| Opposite | Opposite | symbol | 6 | Key |

**Interoception (6)**

| id | label | mode | weight | caps |
| --- | --- | --- | --- | --- |
| BalanceCorrection | Balance | balance | 6 | Key |
| MomentumStabilizer | Stabilise | counter | 6 | Key+Motion |
| CameraAlignment | Orient | align | 4 | Look |
| FootstepSync | Footstep Sync | timed | 4 | Key |
| NoPress | No Press | idle | 5 | – |
| HoldBreath | Hold Breath | idle | 4 | – |

**34 modes, all reachable**: `aim align alternate balance classify count counter
exact gauge grid hit hold holdAll idle mash memorise meter morse press quickdraw
react release search sequence shake sort spin steady symbol timed trace track tug
type`. A test asserts that no mode is dead code and that no definition names a mode
that does not exist.

### 5.1 Adding a QTE

1. Add a `define({...})` to `Lib/QTECatalog.luau` — unique `id` and `label`, an
   existing `mode`, a `category`, `weight > 0`, `caps`, an rgb `accent`, a
   `baseTime` inside `Timing.MinLimit..MaxLimit`, and a `build(rng, ctx)` that
   returns `{prompt, sub?, params}`. Use only `rng:pick/:int/:chance` and the
   file's helpers, so the definition stays reproducible for a seed.
2. If it needs a new *behaviour*, add a mode to `Lib/QTEEngine.luau` (cost, init,
   tick/onPress/onRelease/onClick, expect) **and** a painter to `MODE_WIDGETS`.
   A mode with no painter fails the test "every QTE draws at least one widget".
3. Run `node tools/vitriol-smoke-test.js`. The suite will immediately tell you if
   the QTE is unwinnable, winnable by idling, over budget, rate-impossible, or
   leaking its answer.

---

## 6. View, widgets, and the solver channel

`engine:tick(sample)` returns the whole render model:

```
{ id, label, state, reason, score, elapsed, remaining, timeLimit, progress,
  prompt, sub, widgets, accent, answerVisible, expect }
```

Widget kinds (declared in `QTEEngine.WIDGET_KINDS`, and the only kinds a test
allows a mode to emit): `text`, `bar`, `track`, `target`, `path`, `grid`, `chips`.
Coordinates are normalised 0..1 of the QTE surface and colours are `{r,g,b}`
triples, so the engine can be driven headless.

`view.expect` is the **solver channel**: the engine states what it wants next
(`{kind="key"|"tap"|"hold"|"release"|"pointer"|"look"|"click"|"none", token, at,
atEnd, x, y, dir, holdFor}`). It exists so the harness can play any QTE without
screen-scraping, and it is the same information the player reads off the widgets.
The shell never displays it.

---

## 7. Client shell (`Controllers/QTEStruggle`)

* **One loop.** `Heartbeat` is connected on `start()` and disconnected when the
  verdict finishes. There is no idle cost and no second scheduler.
* **Input.** `InputBegan`/`InputEnded` (skipping `gameProcessedEvent`),
  `InputChanged` for pointer motion, `LastInputTypeChanged` to re-filter the pool
  when the player picks up a different device. Key transitions are derived from
  the held-key set, so a mode never needs to know how the platform reported them.
* **Sampling.** Pointer position is `GetMouseLocation() - GetGuiInset()`,
  normalised by the camera viewport; travel is measured in screens so `Shake` and
  `Trace` work at any resolution. `look`/`velocity` are plain `{x,y,z}` tables.
  `markBeat()` is the hook for world beats (`FootstepSync`).
* **Rendering.** A pooled instance set per widget kind under `VitriolGui.QTE.Stage`,
  created at most once per pool slot. Colours are the only `Color3` conversion in
  the system. Nothing is tweened; values are written per frame.
* **Safety.** `Cancel()` restores the frozen character and hides the overlay;
  `CharacterAdded` cancels any run; the engine's own deadline (plus grace) always
  ends the QTE even if the player never touches anything.
* **Results.** `resultSignal:fire(payload)` carries
  `{id, mode, state, reason, score, grade, escapeWeight, elapsed, misses, streak,
  timeLimit}`. Damage/heal are **not** applied unless the game opts in with
  `applyConsequences = true`; Vitriol does not, because `HealthService` owns health.
* **v5 API preserved 1:1** on the object: `StartRandomQTE`, `StartQTE`,
  `StartChain`, `RegisterCustomQTE`, `SetDifficulty`, `SetConfig`, `GetStats`,
  `ResetStats`, `GetQTEList`, `ResetAppearances` (plus `cancel`, `isActive`,
  `markBeat`, `bind`, `resultSignal`, `startedSignal`, `destroy`).

`ClientMain` constructs it exactly like `VictimCamera` and binds it to
`RE_CreatureEvent`, which is where a server-driven struggle arrives.

---

## 8. Server integration (specified, not implemented)

The server owns the kill choreography, so the server starts struggles. The
contract to add in the next work package:

1. **Server → client**, over the existing `RE_CreatureEvent`:
   `{ qte = "start", id = "<catalogue id>", healthFraction = <0..1>,
   freeze = <bool> }`, `{ qte = "beat" }` for world-driven beats, and
   `{ qte = "cancel", reason = "..." }`. No new remote is created (docs/01 §5).
2. **Client → server**, over `RE_ClientIntent` (`NetContract` gains an intent,
   e.g. `"qte_result"`), the payload the shell already fires:
   `{ id, state, reason, score, grade, escapeWeight, elapsed, misses }`.
3. **Server validation.** The server times the struggle itself and clamps the
   reported score to what the elapsed window allows; a result that arrives before
   its QTE's own cost, or after the limit plus a tolerance, is treated as `fail`.
   The client is never trusted for progress.
4. **Escape maths** stays in `docs/03` §6.3's model. A struggle QTE contributes to
   the grip meter as
   `mashProgress += grade.escapeWeight * Struggle.ProgressPerQTE`, and a failure
   adds `Struggle.FailureGrip` to grip instead of instantly killing. Suggested
   starting values (tune in playtest, keep them in `GoreConfig.Escape`):
   `ProgressPerQTE = 0.45`, `FailureGrip = 0.15`, so a `wounded` escape needs
   ~2 clean QTEs and a `healthy` one needs a clean plus a rough.
5. **Chain.** Dragging a still-struggling victim plays a short chain
   (`StartChain({...})`), escalating the family as the grip falls: Reflex →
   Motor → Memory. The chain lives on the server; the client just reports.

Until this lands, `QTEStruggle` is fully usable for scripted scenes (a debug
handler or a Studio test can call `struggle:start("Spam")`).

---

## 9. Testing and evidence

`tools/vitriol/tests.luau` runs the real modules inside the headless harness
(`node tools/vitriol-smoke-test.js`). The QTE block adds 58 assertions:

* **Shape**: catalogue validates against the engine; unique ids/labels; valid
  accents, caps, categories and base times; the v5 classics are still present.
* **Feasibility**: no preset at zero health cuts a limit below the QTE's cost; no
  limit exceeds the ceiling; sustained QTEs never demand more presses per second
  than the human model allows; unpredictable cue windows never fall below reaction
  time; `cost()` is a pure read.
* **Playability**: a bot with a 7.5 inputs/s rate and a 2.2 screens/s pointer wins
  all 68 QTEs at all 4 presets; a bot that does nothing loses everything except the
  two `idle` QTEs; a bot that mashes randomly never crashes, wedges or emits an
  undeclared widget, and every QTE draws something.
* **Fairness**: difficulty only ever removes time; being nearly dead and having a
  40-win streak never grants extra time and never breaches the cost floor.
* **Determinism**: identical seeds produce byte-identical tasks; different seeds
  change at least half the catalogue.
* **Director**: 400 weighted draws reach every entry; freshness decays repeats;
  touch-only pools contain no keyboard QTEs; stats, streaks, reset, `lastN` order;
  grading (a loss is always `fail`, a perfect run escapes better than a rough one);
  custom registration rejects unknown modes and duplicate ids and joins the pool.
* **Concealment**: every memory QTE shows its answer during the flash and none of
  them leaves it on screen once recall starts.

**What the harness cannot prove.** It has never rendered a frame: widget layout,
legibility at 480p, the feel of the time limits on real hardware, and the
`Color3`/`Vector2` conversions in `QTEStruggle` are verified by reading, not by
running. Playtest the seven families in Studio and tune `QTEConfig.Human` — every
limit in the game moves with that table.

---

## 10. Human-authored work

`docs/10` §2.2 owns the UI hierarchy. The QTE overlay is the one addition:

```
VitriolGui (ScreenGui)
└─ QTE (Frame)                       AnchorPoint 0.5,0.5; Position 0.5,0.45; Size 0.66,0.42
   ├─ Title (TextLabel)              TextScaled + UITextSizeConstraint (12..34)
   ├─ Hint (TextLabel)               TextScaled + UITextSizeConstraint (12..34)
   ├─ Stage (Frame)                  widget surface; bars/targets/grid/chips are pooled here
   ├─ Timer (Frame)                  thin rule, not a bar-graph: the fill is the remaining time
   │  └─ Fill (Frame)
   └─ Verdict (TextLabel)            brief WIN/FAIL word, TextTransparency 1 when idle
```

If the subtree is missing, the shell builds exactly this shape at runtime and
warns once (`[vitriol.qte]`), so the game is playable before the art exists. The
authored version wins: the shell uses whatever it finds under `VitriolGui.QTE`.

Audio and animation (per `docs/10` §4/§7): a per-widget tick for `chips`, a rising
tone for `gauge`/`track` markers, a "miss" thud, and a struggle animation whose
existing footstep marker drives `markBeat()`.

---

## 11. Invariants for future edits

1. `Config/` and `Lib/` stay pure. No services, no `task.wait`, no `os.clock`, no
   `math.random` — inject `Lib/RNG`.
2. Nothing may compute a time limit outside `QTEDirector:limitFor`.
3. A new mode needs a painter, an `expect` hint, a cost, and a line in this
   document's roster table.
4. Answers are tokens, never characters or `KeyCode`s, at the engine boundary.
5. The engine resolves once; every mode must be safe to tick after resolution.
6. `QTEStruggle` is the only file allowed to know about Roblox UI, and it must
   keep zero priced calls so `tools/hot-loop-scan.js` stays at zero for
   RunService-wiring files.
