# QTE — a self-contained quick-time-event package

**68 quick-time events over 34 engine modes**, for Roblox. Drop one folder into
`ReplicatedStorage`, add one script, and you have a QTE system: device-aware, fair
by construction, and executable in a headless test harness without the editor.

This package is **separate from the place it was developed in**. It requires
nothing from it - no remotes, no config, no services, no game code - and it does not
call `task.wait`, `math.random`, `os.clock` or `wait()`. Everything it needs is in
this folder.

```
QTE/
├─ Config/QTEConfig        data: the human input model, presets, grades, devices, word/number banks
├─ Lib/RNG                 deterministic seedable randomness (vendored)
├─ Lib/Signal              minimal observable (vendored)
├─ Lib/QTECatalog          the 68 definitions
├─ Lib/QTEEngine           the 34 modes: timers, judging, widgets, the solution channel
├─ Lib/QTEDirector         picks one, times it, grades it, keeps the stats
├─ Client/QTEStruggle      the only Roblox-aware file: input in, pixels out
├─ Client/QTEStruggleClient  the whole installation, as one LocalScript
├─ Client/QTEPlayground    press F8 for a random QTE (delete whenever)
└─ UI/QTEOverlay           the interface, as a spec; plus a Studio-importable model
```

---

## 1. Install

1. In Studio, create `ReplicatedStorage > QTE` (a Folder) and import `qte/` into it
   as: `QTE.Config`, `QTE.Lib`, `QTE.Client`, `QTE.UI` folders containing the
   modules above. Every file is a **ModuleScript** except the two client scripts,
   which are **LocalScripts**.
2. Create `StarterPlayer > StarterPlayerScripts > QTEStruggleClient` (LocalScript)
   with the contents of `qte/Client/QTEStruggleClient.luau`.
3. Optional: import `qte/UI/QTEOverlay.rbxmx` into `StarterGui` to own the visuals
   (see §7). Skipping this step is fine - the overlay is built at runtime instead.
4. Optional: see §9 for the server contract.

Then, from anywhere on the client or server:

```lua
local QTE = require(game.ReplicatedStorage.QTE.Client.QTEStruggle)

local struggle = QTE.new({ seed = 1, preset = "Normal" })
local task = struggle:StartRandomQTE()          -- the pool decides what you get
struggle:StartQTE("Spam")                       -- or name one
struggle:StartChain({ "React", "Mash", "FlashDigit" })

struggle.resultSignal:connect(function(result)
    print(result.id, result.grade, result.score, result.escapeWeight)
end)
```

`QTEStruggle.new` injects its dependencies, so a test or a different place can pass
its own: `Players`, `RunService`, `Workspace`, `Player`, `UserInputService`,
`GuiService`, and `gui` (your own ScreenGui, if you have one).

### The whole API

| Call | Does |
| --- | --- |
| `new(opts)` | builds the controller; seed, preset, freeze, gui, capabilities |
| `StartRandomQTE(healthFraction?)` | plays a QTE the device can answer |
| `StartQTE(id, healthFraction?)` | plays a named QTE from the catalogue |
| `StartChain(ids)` | plays a list, one after another, stopping on a loss |
| `Cancel()` / `cancel(reason)` | abandons the run; reports `cancelled` |
| `IsActive()` / `isActive()` | is a QTE running |
| `RegisterCustomQTE(def)` | adds a definition (mode must exist); returns false on a duplicate id |
| `SetDifficulty(preset)` | `"Easy"`, `"Normal"`, `"Hard"`, `"Insane"` |
| `SetConfig(partial)` | preset, adaptive floor, pressure, capabilities |
| `GetStats()` / `ResetStats()` | runs, wins, losses, streak, best streak, adaptive, pool size |
| `GetQTEList()` | everything this device can be asked for |
| `ResetAppearances()` | forgets freshness, so nothing is "recently seen" |
| `resultSignal`, `startedSignal` | `Signal` instances: `:connect(fn)` |
| `bind(remote)` | accepts `{ qte = "start" | "beat" | "cancel" }` from a server remote |
| `markBeat()` | a world beat (footstep, animation marker) for beat-driven QTEs |
| `setCapabilities(caps)` | declare the device by hand (e.g. after a controller connects) |
| `destroy()` | disconnects everything and drops the overlay |

`resultSignal` payload:

```lua
{ id, mode, label, state, reason, score, grade, escapeWeight,
  elapsed, misses, streak, timeLimit }        -- plus cancelled = true on a cancel
```

**The client never writes your game's state.** `resultSignal` is a report: damage,
healing and progression are yours to apply (see §9). If you *want* v5-style direct
writes, `new({ applyConsequences = true })` restores them, using
`QTEConfig.Grades[...].damage/heal`.

---

## 2. Why a package and not 2 500 lines

The original (v5) manager was one client file with ~50 hand-written coroutines. It
worked until it did not: two QTEs were the same QTE registered twice, one printed
its own answer during recall, one could hang a player forever, and none of it could
be executed outside Roblox, so none of it was ever tested. This rewrite splits the
problem the way the problem is actually shaped:

* **`Lib/` is pure.** No Instances, no services, no yields, no clock, no
  `math.random`. Time arrives as `dt`; randomness arrives as an injected `RNG`.
  That is what makes a headless suite possible at all.
* **Data is separated from behaviour.** A QTE is a definition (id, mode, weight,
  params built from an RNG); a mode is a state machine. Adding a QTE is usually a
  four-line table entry.
* **One render model.** `engine:tick(sample)` returns everything on screen. The
  client writes it out; it holds no QTE state of its own, so the picture cannot
  desync from the rules.
* **One owner per decision.** `QTEDirector:limitFor` is the only place a time limit
  is computed. If you want a different difficulty curve, that is the whole surface.

Bugs the rewrite fixed, each with a test that would catch it again:

| v5 | Now |
| --- | --- |
| `NoPress` resolved twice through a `task.delay` guard | resolution is first-call-wins |
| `ExactTaps` kept counting inside the grace window after the verdict | the engine latches and ignores later input |
| `PhoneDial` forbade `0` while its own key map contained it | digits are tokens with alias tables; `0` works |
| six QTEs ran private sentinel/Heartbeat watchers | one loop, started with a run, disconnected with the verdict |
| `WaitForChild(name, 10)` inside an `assert` (always true) | direct indexing, with an explicit fallback |
| `Balance`/`BalanceCorrection` both registered | one entry; duplicates cannot exist |
| a flat minimum time limit | the floor is the QTE's own measured cost |
| `Hum:TakeDamage` from a presentation module | the result is a Signal; the game decides |
| `GetMouseLocation()` treated as GUI space | `GuiService:GetGuiInset()` is subtracted |
| `TouchEnabled` alone chose the device | `PreferredInput` + the `*Enabled` flags, re-evaluated on `LastInputTypeChanged` |
| the 55 QTE types were a closed list of copy-pasted coroutines | 68 definitions over 34 shared, tested modes |

---

## 3. The roster (68)

Weight is the base pick weight; freshness divides it by
`1 + appearances * Freshness.AppearancePenalty`, so repeats fade without ever
becoming impossible. `needs` is the device capability the QTE requires, which is
also how a phone is never asked to press `Q`.

### Reflex (9)

see it, answer it. The panic family: short windows, one input, no thinking.

| id | label | mode | weight | needs |
| --- | --- | --- | --- | --- |
| `Press` | Press | `press` | 10 | Key |
| `React` | React | `react` | 10 | Key |
| `Dodge` | Dodge | `react` | 9 | Key |
| `Snap` | Snap | `react` | 7 | Key |
| `QuickDraw` | Quick Draw | `quickdraw` | 7 | Key |
| `DoubleTap` | Double Tap | `exact` | 7 | Key |
| `Ambush` | Ambush | `react` | 6 | Key |
| `ReflexMulti` | Reflex Multi | `hit` | 6 | Click+Pointer |
| `Sequence` | Sequence | `sequence` | 8 | Key |

### Motor (9)

sustained output. Mash, alternate, hold - the family that models being held down.

| id | label | mode | weight | needs |
| --- | --- | --- | --- | --- |
| `Spam` | Mash | `mash` | 10 | Key |
| `MultiSpam` | Alternate | `alternate` | 8 | Key |
| `TripleThreat` | Triple Threat | `alternate` | 6 | Key |
| `Survive` | Survive | `meter` | 6 | Key |
| `Crescendo` | Crescendo | `meter` | 5 | Key |
| `TugOfWar` | Tug of War | `tug` | 5 | Key |
| `ExactTaps` | Exact Taps | `exact` | 6 | Key |
| `Endure` | Endure | `hold` | 6 | Key |
| `Brace` | Brace | `holdAll` | 5 | Key |

### Precision (10)

the pointer family. Aim, trace, spin, hold still; measures steadiness, not speed.

| id | label | mode | weight | needs |
| --- | --- | --- | --- | --- |
| `Aim` | Aim | `aim` | 7 | Pointer |
| `ClickTarget` | Click Target | `hit` | 7 | Click+Pointer |
| `Skeet` | Skeet | `hit` | 4 | Click+Pointer |
| `Shake` | Shake | `shake` | 5 | Pointer |
| `Spin` | Spin | `spin` | 5 | Pointer |
| `SafeCracker` | Safe Cracker | `spin` | 3 | Pointer |
| `Track` | Track | `track` | 4 | Pointer |
| `Trace` | Trace | `trace` | 4 | Pointer |
| `Steady` | Steady | `steady` | 4 | Click+Pointer |
| `HotCold` | Hot / Cold | `search` | 4 | Pointer |

### Timing (7)

cues and releases. Judged against a window, so early is as wrong as late.

| id | label | mode | weight | needs |
| --- | --- | --- | --- | --- |
| `StepTiming` | On the Beat | `timed` | 7 | Key |
| `Metronome` | Metronome | `timed` | 6 | Key |
| `Rhythm` | Rhythm | `timed` | 5 | Key |
| `SlideBar` | Slide Bar | `release` | 7 | Key |
| `FuseCut` | Fuse Cut | `release` | 5 | Key |
| `TimedRelease` | Timed Release | `release` | 6 | Key |
| `PressureGauge` | Pressure Gauge | `gauge` | 4 | Key |

### Memory (15)

encode then recall. The only family whose answer must not be on screen at recall.

| id | label | mode | weight | needs |
| --- | --- | --- | --- | --- |
| `Simon` | Simon | `memorise` | 6 | Key |
| `ReverseSeq` | Reverse | `memorise` | 5 | Key |
| `LastKeyFlash` | Last Key | `memorise` | 6 | Key |
| `PatternMemoryBurst` | Memory Burst | `memorise` | 5 | Key |
| `ColourSequence` | Colour Sequence | `memorise` | 5 | Key |
| `MemoryGrid` | Memory Grid | `grid` | 4 | Click+Pointer |
| `FlashDigit` | Flash Digit | `memorise` | 5 | Key |
| `PhoneDial` | Phone Dial | `memorise` | 5 | Key |
| `MemoryPalace` | Memory Palace | `memorise` | 3 | Key |
| `WordRecall` | Word Recall | `type` | 6 | Key |
| `WordType` | Type It | `type` | 6 | Key |
| `Spelling` | Spelling | `type` | 4 | Key |
| `RapidTyping` | Rapid Typing | `type` | 5 | Key |
| `MorseCode` | Morse Code | `morse` | 3 | Key |
| `CountFlash` | Count Flash | `count` | 5 | Key |

### Cognition (12)

read then decide. Arithmetic, parity, sorting, Stroop interference.

| id | label | mode | weight | needs |
| --- | --- | --- | --- | --- |
| `MathCalc` | Calculate | `type` | 8 | Key |
| `TrueFalse` | True / False | `classify` | 8 | Key |
| `EvenOdd` | Even / Odd | `classify` | 7 | Key |
| `NumberOrder` | Number Order | `sort` | 6 | Key |
| `SortPress` | Alphabetise | `sort` | 5 | Key |
| `StroopWord` | Stroop Word | `classify` | 7 | Key |
| `StroopInk` | Stroop Ink | `classify` | 6 | Key |
| `BiggerOf` | Bigger | `classify` | 5 | Key |
| `NextInSeries` | Next In Series | `classify` | 4 | Key |
| `Tally` | Tally | `classify` | 5 | Key |
| `Mirror` | Mirror | `symbol` | 6 | Key |
| `Opposite` | Opposite | `symbol` | 6 | Key |

### Interoception (6)

your own body as the input: balance, counter-movement, camera alignment, and two QTEs answered by doing nothing at all.

| id | label | mode | weight | needs |
| --- | --- | --- | --- | --- |
| `BalanceCorrection` | Balance | `balance` | 6 | Key |
| `MomentumStabilizer` | Stabilise | `counter` | 6 | Key+Motion |
| `CameraAlignment` | Orient | `align` | 4 | Look |
| `FootstepSync` | Footstep Sync | `timed` | 4 | Key |
| `NoPress` | No Press | `idle` | 5 | nothing |
| `HoldBreath` | Hold Breath | `idle` | 4 | nothing |

**34 modes, all reachable**: `aim align alternate balance classify count counter
exact gauge grid hit hold holdAll idle mash memorise meter morse press quickdraw
react release search sequence shake sort spin steady symbol timed trace track tug
type`. A test fails if a mode is unreachable or a definition names a mode that does
not exist.

### Adding one

```lua
define({
    id = "Slam", label = "Slam", mode = "press", category = "Reflex",
    weight = 6, caps = { Key = true }, accent = { 240, 150, 90 }, baseTime = 1.6,
    build = function(rng, ctx)
        return { prompt = "PRESS E", sub = nil, params = { key = "E" } }
    end,
})
```

Then run the suite (§10). It will tell you immediately if the QTE is unwinnable,
winnable by idling, too tight for a human, or leaking its answer.

---

## 4. Fairness, by construction

```
cost.time = read + think + max(0, keys * Human.KeySeconds - think)
                   + pointer / Human.PointerScreensPerSecond

limit     = clamp(baseTime * preset * adaptive * pressure,
                  max(cost.time, Timing.MinLimit),
                  min(Timing.MaxLimit, baseTime * preset))
```

* `Human` is the input model the whole system prices against: reaction time, a
  discrete-key rate, a pointer speed, a mash floor. **Retune that table and every
  limit in the game moves with it.**
* The lower clamp is the QTE's own cost, so no combination of preset, low health,
  win streak or bad seed can ship a window shorter than the inputs need. The suite
  asserts it for every QTE at every preset at zero health.
* Pressure squeezes a dying player but is floored and bounded, so it can never lock
  anyone out. Adaptive difficulty only ever *removes* time.
* Unpredictable cues (`react`, `quickdraw`) always stay open for at least a human
  reaction time. Rhythm beats may be tighter, never below 0.10 s.

---

## 5. Devices and tokens

The engine speaks **tokens**, never `KeyCode`s: `"E"`, `"Space"`, `"Up"`,
`"Zero"`..`"Nine"`, `"KeypadFour"`, `"Click"`. `QTEConfig.InputMap` maps tokens to
key names per device, and the client inverts it once at construction. The same
token means `E` on a keyboard and `Y` on a gamepad.

Capabilities are `Key`, `Pointer`, `Click`, `Look`, `Motion`. A QTE declares what it
needs; the director only serves QTEs the device can answer. Touch, gamepad and
keyboard/mouse are detected from `PreferredInput` with the `*Enabled` flags as a
fallback, and re-evaluated when `LastInputTypeChanged` fires - so plugging in a
controller mid-session changes the pool instead of failing you.

---

## 6. The view contract

`engine:tick(sample)` returns the entire render model:

```lua
{ id, label, state, reason, score, elapsed, remaining, timeLimit, progress,
  prompt, sub, widgets, accent, answerVisible, expect }
```

Widget kinds - the only kinds a mode may emit - are `text`, `bar`, `track`,
`target`, `path`, `grid`, `chips`. Coordinates are normalised 0..1 of the stage and
colours are `{r, g, b}` triples, so the engine runs headless and the client owns the
only `Color3`/`Vector2` conversions in the package.

`view.expect` is the **solution channel**: the engine stating what a correct player
does next (`{kind="key"|"tap"|"hold"|"release"|"pointer"|"look"|"click"|"none", ...}`).
The player never sees it. It exists so the test harness can play any QTE, so a
tutorial or assist mode has one source of truth, and so a replay/replay-check tool is
possible without screen-scraping.

---

## 7. The interface

`UI/QTEOverlay.luau` describes the interface as data; both the runtime builder and
the generated Studio model come from that one spec, so they cannot drift.

```
ScreenGui "QTEOverlay"        ResetOnSpawn=false, IgnoreGuiInset=true
├─ Scrim (Frame)              darkens the world so the struggle reads as a takeover
└─ QTE (Frame, centered)
   ├─ Title (TextLabel)       the instruction - TextScaled + UITextSizeConstraint
   ├─ Accent (Frame)          a 2 px rule that takes the QTE family's colour
   ├─ Stage (Frame)           widget surface: pooled bars/targets/grids/chips
   ├─ Timer (Frame) > Fill    a thin RULE for the remaining time - never a graph
   ├─ Verdict (TextLabel)     one word, on top, transparent when idle
   └─ Hint (TextLabel)        the secondary line
```

**To own the look:** import `qte/UI/QTEOverlay.rbxmx` into `StarterGui` and restyle
it. `QTEOverlay.ensure` *completes* a tree - it creates only the nodes that are
missing and never overwrites a property on a node it did not create - so your edits
survive, and the code requires no change. A screen without it gets the same layout
built at runtime.

`QTEOverlay.preview.svg` (and `.png`) show the composition at 1280x720; regenerate
both with `node tools/qte-build-ui.js` after editing the spec. (The PNG is rendered
from the generated SVG by `tools/qte-preview-png.py`, which needs Pillow:
`pip install pillow`.)

There is also `QTEOverlay.Theme`: one place for the palette
(`Paper`, `Muted`, `Ink`, `Accent`, `Good`, `Danger`), which the client reads when it
tints the verdict and the widget chrome. The accent rule and the timer fill take the
running QTE's own accent colour.

---

## 8. Performance

* **One loop.** `Heartbeat` is connected when a run starts and disconnected when it
  ends. Idle cost is zero - no per-frame polling, no timers left behind.
* **Pooled widgets.** Instances are created once per pool slot and reused; the run
  loop writes properties, never traverses the tree (the part lookup happens once at
  the start of a run).
* **No allocation storms.** Samples are plain tables reused per frame; the engine
  mutates one state table.
* The package holds **zero** expensive calls on a frame path: no
  `FindFirstChild`, no `table.insert`/`sort`, no `WaitForChild` inside the loop.

---

## 9. Server authority

The client reports; the server decides. The intended contract:

* **Server → client**, on any remote you already have:
  `{ qte = "start", id = "Spam", healthFraction = 0.4, freeze = true }`,
  `{ qte = "beat" }`, `{ qte = "cancel", reason = "released" }`.
  The client's `bind(remote)` handles this.
* **Client → server**, on a remote *you* create: the `resultSignal` payload.
* **Validate it.** Begin your own timer when you send `start`; if a result arrives
  sooner than the QTE's own cost, later than its limit plus a tolerance, or names an
  id you never sent, treat it as a failure. `elapsed` and `misses` are the client's
  claims; `id` is the only field you already know.

A worked example: a grab that the player can fight. The server starts the struggle
QTE, the client reports `grade`/`escapeWeight`, the server adds
`escapeWeight * ProgressPerQTE` to an escape meter and adds `FailureGrip` to the
creature's grip on a loss - so two clean QTEs break a wounded grab and three rough
ones do not. Nothing in this package assumes any of that; it just reports well.

---

## 10. Testing

```
node tools/vitriol-smoke-test.js \
     --modules tools/vitriol/modules-qte.js \
     --tests   tools/vitriol/tests-qte.luau
```

58 assertions, all against the **real** modules (loaded from `qte/`, transformed,
run in a Lua VM - not reimplementations):

* **Shape** - every definition validates against the engine: unique ids and labels,
  real modes, real capabilities, valid accents, base times inside the window;
  every mode is reachable; every QTE draws at least one declared widget kind.
* **Feasibility** - `limit >= cost.time` for all 68 QTEs x 4 presets x 6 seeds at
  zero health; never above the ceiling; sustained QTEs never demand more inputs per
  second than `QTEConfig.Human` allows; unpredictable cues respect reaction time.
* **Playability** - a bot limited to 7.5 inputs/s and 2.2 screens/s of pointer
  travel **wins all 68 QTEs at all 4 presets**; a bot that does nothing loses
  everything except the two `idle` QTEs; a bot that mashes randomly never crashes,
  wedges or emits an undeclared widget.
* **Determinism** - the same seed produces byte-identical tasks; different seeds
  change at least half the catalogue.
* **Director** - 400 weighted draws reach every entry; freshness decays repeats;
  a touch-only pool contains no keyboard QTEs; grading never turns a loss into an
  escape; custom registration rejects unknown modes and duplicate ids.
* **Concealment** - every memory QTE shows its answer during the flash and none
  leaves it on screen once recall starts.

**What the suite cannot prove.** It has never rendered a frame. Widget layout,
legibility at 480p, the feel of the limits on real hardware, and every `Color3` /
`Vector2` conversion in `Client/QTEStruggle` are reviewed by reading, not by
running. Playtest each family, then tune `QTEConfig.Human`.

---

## 11. Invariants when editing

1. `Config/` and `Lib/` stay pure: no services, no Instances, no `task.*`, no
   `os.clock`, no `math.random`. Randomness is injected.
2. Nothing computes a time limit outside `QTEDirector:limitFor`.
3. A new mode needs a cost, a painter (`MODE_WIDGETS`) and an `expect` hint.
4. Answers are tokens at the engine boundary - never characters, never `KeyCode`s.
5. The engine resolves once; every mode must be safe to tick after resolution.
6. `Client/QTEStruggle` is the only file that knows Roblox exists, and it must stay
   free of per-frame allocations and tree traversal.
7. Fix a bug by adding an assertion to `tests-qte.luau` first.
