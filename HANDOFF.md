# Handoff — Vitriol, end of iteration 2

Everything in this file was produced by running a command in this repository, not
recalled. Where a claim is unverified it says so.

---

## 0. Prompt for the next agent

```
You are continuing work on VITRIOL, a Roblox night-survival horror game about an
IK-controlled, blind, tendril-based creature that hunts by vibration, scent and
memory and LEARNS the player's habits. The repository is Explorer-first: there is
NO Rojo project and you must not create one. Work on the branch you were given;
never create or switch branches.

Read first, in this order:
  docs/00-VISION.md          the 7 design pillars; these override everything
  docs/01-ARCHITECTURE.md    Explorer hierarchy, ownership, cadence budgets, §13
                             is the list of known tool exceptions
  docs/03-MONSTER-TECH.md    FABRIK, rig, movement, replication (§7.1 is now
                             corrected - core-relative quantisation)
  docs/08-RESEARCH-NOTES.md  verified engine facts. Do not re-litigate these;
                             they were checked against create.roblox.com and
                             tagged verified / secondary / to-verify.
  docs/09-HANDOFF-PROMPTS.md the WP1-WP10 breakdown and the shared preamble

Roblox docs are available as Markdown: append .md to any create.roblox.com/docs
URL, or fetch https://create.roblox.com/docs/reference/engine/llms.txt for the
API index. Prefer that over searching.

YOUR TASK THIS ITERATION, in order:
  1. Finish WP3. Still owed, per the note at the top of that section in docs/09:
       Shared/Remotes       the ONLY place remotes are created, exactly the set
                            listed in docs/01 §2, WaitForChild + timeout
       Shared/NetContract   declarative payload schemas + server-side validation
                            for every client->server message. Reject and
                            rate-limit; never trust a client.
       Skeleton:reset()     WP3 asks for it; it does not exist yet.
       SkeletonCodec core orientation
                            docs/03 §7.1 lists 4 bytes of quantised quaternion.
                            The codec emits none (header is 9 bytes: creatureId 1
                            + seq 2 + core delta 6). Either add it or delete that
                            row from the doc and correct the ~590 B estimate to
                            ~585 B. Do not leave the doc and the code disagreeing.
       SkeletonCodec buffer adapters
                            encode/decode work on a plain array of numbers so the
                            quantisation stays unit-testable. Add thin
                            buffer.create/writeu8 adapters in the replicator (NOT
                            in the codec) and prove the two agree.
       NoiseField wind advection, rain masking, material coupling
                            docs/02 §2 specifies these. The module currently does
                            decay only, and its header says the rest belongs to
                            the sense modules. Decide which is right, then make
                            the code and docs/02 agree.
       Round-trip test      WP3 asks for max positional error < 0.02 studs over
                            200 RANDOM chains. The current test uses one pose plus
                            a 1,000-snapshot core-feedback test. Add the random
                            sweep - one pose is how the collapsed-noise bug in
                            iteration 2 nearly shipped.
  2. Then WP4: ServerStorage/Vitriol/Services/{SessionService, TimeService,
     ThreatService, HealthService}, ServerStorage/Vitriol/Bootstrap,
     ServerScriptService/Vitriol/Main, and Diagnostics/Profiler.
     Acceptance: a server with ZERO players still runs the full Dawn->Day->Dusk->
     Night cycle correctly and logs one line per phase change with elapsed time.
     TimeService must not touch Lighting (Lighting.ClockTime is Not Replicated;
     clients own Lighting).

HARD RULES (from docs/09 preamble - re-read it, these are load-bearing):
  1. Every source file starts with a header comment giving its Explorer location
     and instance class.
  2. Nothing in Lib/ may call game:GetService, touch an Instance, or yield.
  3. No magic numbers - every tunable goes in a Config module.
  4. Never use .Touched.
  5. Frame-path code allocates zero tables (Lib/Tables has the pool).
  6. Lighting is written by clients only.
  7. Bone.Transform / Motor6D.Transform do not replicate - bones are presentation.
  8. Run the checks below and paste their real output before you say "done".
  9. If a human would do it better (meshes, map, UI, audio, animations) do NOT
     generate it - extend docs/10-HUMAN-AUTHORED.md with a precise spec instead.
 10. Update the ROOT ROADMAP.md when you finish a WP.

BEFORE YOU SAY DONE, run all of these and report the actual output:
  node tools/vitriol-smoke-test.js                 (must stay 0 failed)
  node tools/check-syntax.js code                  (20/22 is the current baseline)
  node tools/metrics.js --src code
  node tools/hot-loop-scan.js --src code           (must stay 0 in a frame path)
  node tools/call-graph.js --src code
  node tools/find-dead-config.js --src code
  node tools/evaluate-models.js --models tools/models.example.json \
       --suite tools/evaluation-suite.example.json
The last one is a gate the user requires; it must print:
  fixture-known-good: ADMIT 100.0%
  candidate-local: REJECT 0.0%

If you are running low on budget, stop cleanly: update ROADMAP.md, commit, and
write the next handoff. A partial iteration that is committed and honest is worth
more than an unfinished one that is not.
```

---

## 1. Verified state at handoff

Commit `5532193` on `arena/01a0810f-vitriol`, working tree clean.

| Check | Output |
| --- | --- |
| `vitriol-smoke-test.js` | `VITRIOL smoke test: 198 passed, 0 failed` |
| `check-syntax.js code` | `2 file(s) failed` — `Lib/RNG.luau`, `Lib/Noise.luau` (see §3) |
| `hot-loop-scan.js --src code` | `Priced calls: 7 \| inside-a-loop: 7 \| in a RunService file: 0` |
| `metrics.js --src code` | `LOC 4602 \| code 3286 \| comments 898 \| exports 152 \| requires 2` |
| `call-graph.js --src code` | `Modules: 22`, `Exports: 152 (used 2, orphaned 150)` |
| `evaluate-models.js` | `fixture-known-good: ADMIT 100.0%` / `candidate-local: REJECT 0.0%` |

The 7 hot-loop flags are all `table.insert` in `Genetics` (181, 220) and
`RegionIntegrity` (46, 105, 106, 108, 160) — one-shot setup and per-sever paths,
none in a frame path. The 2 "used" exports are `NoiseField -> SpatialHash` and
`NoiseField -> Tables`. The 150 orphans are expected: no consumers exist yet.

---

## 2. What exists (all executed by the smoke test, not just parsed)

`code/ReplicatedStorage/Vitriol/`

**Config/** (7, parse clean): `GameConfig`, `SurvivalConfig`, `DayNightConfig`,
`MonsterConfig`, `DestructionConfig`, `GoreConfig`, `VehicleConfig`.

**Lib/** (11, pure — no services, no Instances, no yields):

| Module | Surface |
| --- | --- |
| `MathExt` | `TAU, lerp, damp, smoothstepRange, smoothstep, approach, angleBetweenDeg, clampMagnitude, distSq, remap` |
| `RNG` | xorshift32. `new(seed)`, `:nextInt32/:next/:range/:int/:chance/:pick/:weighted/:gaussian/:gaussianClamped/:gaussian3/:fork/:serialize`, `RNG.deserialize` |
| `Fabrik` | `newChain(count>=2,seg)`, `setLengths`, `totalLength`, `setStraight`, `copyFrom`, `endEffectorError`, `maxBoneError`, `solve(c,tx,ty,tz,opts?)` (tolerance 0.02), `constraintPass`, `blendToRest`, `dampChain` |
| `Genetics` | 21 genes. `new(genes?,opts?)`, `:cost/:project/:roll/:mutate/:crossover/:express/:fitness`, `Genetics.temperament`, `Genetics.logPrior` |
| `Tables` | `newPool(factory,prealloc)`/`:get`/`:release`/`:stats() -> {free,created}`, `shallowCopy/deepFreeze/count/copyArray` |
| `Signal` | `new()`/`:connect/:once/:fire/:disconnectAll/:handlerCount`; conn `:disconnect/:isConnected` |
| `Noise` | `new(seed)`/`:value1/:value3/:v3/:fbm1` — seeded permutation table |
| `SpatialHash` | `new(cellSize)`/`:insert/:move/:remove/:get/:count/:clear/:query/:queryNearest/:sampleDecay/:prune(now,maxAge,onRemove?)` |
| `UtilityAI` | `new()`/`:consider/:clear/:score/:best/:select(rng,temp)/:selectWithBonus` |
| `QLearning` | `new({actions,...})`/`:act/:greedy/:q/:scores/:learn/:currentAlpha/:weightNorm/:resetTraces/:reset/:serialize`, `QLearning.deserialize` |
| `MarkovPredictor` | `new(nStates)`/`:observe/:count/:probability/:observationsFrom/:predict/:entropy/:predictability/:serialize/:deserialize/:reset` |

**Shared/** (4): `RegionIntegrity`, `Skeleton`, `SkeletonCodec`, `NoiseField`.

`tools/vitriol-smoke-test.js` holds a `MODULES` map. **Any new module must be
added to it** or the harness cannot load it — including modules pulled in via
`require`.

---

## 3. Harness constraints (learned the hard way; do not rediscover)

`tools/vitriol-smoke-test.js` transforms Luau to Lua 5.3 (fengari). It handles
type annotations, `continue` (rejects), backtick strings (rejects), compound
assignment, generalized iteration, and now `require(script.Parent.X.Foo)` —
resolved by **last path segment** against the `MODULES` map.

Forbidden in tested code:
- Ternary-style `if a then b else c` **expressions**, backtick interpolation,
  generics, `continue`, `{T}?` annotations (use `any`).
- **Multiplicative hash mixers.** fengari has no exact 32-bit
  multiply-then-mask: `z * 0x85EBCA6B` overflows 2^53 and raises
  `no integer representation`.
- `+ 2^32`-style integer normalizers — large integer sums become floats.
  Normalise in the float domain only.
- `x += f(a, function() ... end)` — both this harness and `check-syntax.js`
  expand `+=` on ONE line. Assign to a local, then accumulate. (The harness now
  tracks the open paren across lines; `check-syntax.js` does not.)

fengari specifics:
- Bitwise ops are **32-bit signed**, so `x & 0xFFFFFFFF` can read negative.
  Normalize with `local u = x; if u < 0 then u = u + 4294967296 end` and never
  feed `u` back into a bitwise op.
- `Lib/RNG.luau` and `Lib/Noise.luau` therefore fail `check-syntax.js` (luaparse
  is Lua 5.1, no bitwise ops). This is expected and documented in
  `docs/01-ARCHITECTURE.md` §13. Both are *executed* under Lua 5.3 instead,
  which is stronger evidence than a parse.

Tests live in `tools/vitriol/tests.luau`. Each section is wrapped in `do ... end`
because the file otherwise exceeds Lua's 200-active-locals limit — keep new
sections wrapped. `--tests <path>` points the harness at a scratch file (path is
relative to the repo root); `--debug-transform` writes transformed sources to
`/tmp/vitriol-*.lua`, which is how the transform bugs were found.

---

## 4. Bugs found in iteration 2 (each now pinned by a regression test)

These are recorded so the next agent trusts the tests and does not "fix" them
back. Full write-up in `ROADMAP.md` and in each module's header.

1. **`Lib/Noise` used xorshift32 as a lattice *hash*.** xorshift32 is a state
   transition; fed the small sequential integers a lattice produces, its high
   bits never fill. `value1(i)` for `i = 0..63` spanned `0.0742..0.0816` — a
   dynamic range of **0.007**. Every tendril would have twitched in unison.
   Replaced with a seeded permutation table.
2. **The Fisher–Yates draw divided by 2⁴⁸ instead of 2³²**, collapsing the
   shuffle to a fixed near-reversal (measured mean 0.64). Now 0.5075, with 256
   distinct high bytes over 256 lattice points.
3. **`SpatialHash:insert` on an existing id** left `entries[id]` pointing at the
   old table with stale coordinates while the cell index used the new ones. A
   `queryNearest` test had been passing *because* of this.
4. **`QLearning` skipped the taken action when decaying traces**, pinning stale
   eligibilities at 1.0. Canonical replacing traces decay ALL pairs, then set
   `e(s,a) = 1`.
5. **`docs/03` specified joints as offsets from their parent joint.** Naive
   parent-relative costs **0.02748 studs** at the tip of a 12-joint chain against
   a 0.00866 budget; core-relative gives **0.00717** on the same pose. The doc is
   corrected. Note precisely what this does *not* prove: parent-relative *with
   feedback* is also bounded — it just needs the server to mirror the decoder's
   whole chain state.

---

## 5. Standing constraints from the user

- **Structure is presented as a real Roblox Studio Explorer tree** with class
  annotations (`ReplicatedStorage (RPS)`, `-ExampleFolder (FL) ;folder`,
  `--Module (MD)`). Explicitly **not** Rojo layout.
- Script Explorer locations are also stated in every file's header comment.
- Anything a human would do better (the environment, the UI) gets a **prompt and
  hierarchy in `docs/10-HUMAN-AUTHORED.md`, not code**.
- **There is no gore module in this repository.** The user referred to "the
  provided gore module"; it does not exist. Stop looking. Its expected interface
  is specified in `docs/04` §3.3 and `docs/10`, with `GoreConfig.Contract` and
  `GoreConfig.Fallback` (asset-free). Keep it an external dependency with a
  working fallback, and keep flagging the gap.
- `tools/validate-project.js` and `tools/audit.sh` are Rojo-specific. Do **not**
  reorganize `code/` to satisfy them. `tools/smoke-test.js` is unrelated legacy —
  do not edit it; `tools/vitriol-smoke-test.js` is ours.
- The `evaluate-models.js` gate above must be run and must pass.

---

## 6. Seven architecture conclusions that gate all later work

1. `Bone.Transform` / `Motor6D.Transform` do not replicate → the server owns a
   logical joint chain and replicates it compactly; clients own the rig and dead
   reckon. Part CFrames *do* replicate → part-chain visuals via `BulkMoveTo` are
   the MVP path.
2. Do not depend on `IKControl`. There is a 2026 `ChainRoot` regression
   (devforum/4391277, fixed 2026-05-08). The owned FABRIK solver is primary.
3. `Lighting.ClockTime` is Not Replicated → the server publishes a clock; a
   per-client `LightingDriver` is the sole Lighting writer.
4. Perception runs in desynced `Actor`s (Write Parallel). `require` before
   desync; one Actor per worker; parallel phases cannot write the DataModel.
5. No `.Touched`: impulse from `AssemblyLinearVelocity` deltas +
   `GetPartBoundsInRadius` + joint-graph BFS. Every break emits into `NoiseField`.
6. AI layering: genome → instinct log-prior + capability gates → Q-learning
   (linear features, Boltzmann, replacing traces) → Utility AI → Behaviour Tree →
   Steering → IK. Cross-night: GA over genomes (DataStore) + aggregated priors
   (MemoryStore, max expiry 45 days).
7. The kill is region-integrity damage from
   `|tendril velocity| x grip x region vulnerability`; zero integrity severs,
   then hands off via `GoreAdapter`.
