# 09 — The AI Build Pipeline

The user's brief included: *"research on roblox vibe coding AIs that automatically
generate games"*. This is that research, plus the decision about how iterations 2–5
actually use it. Sources are dated; re-verify before relying on any of it, because this
is the fastest-moving part of the platform.

Research date: **2026-09-30**.

---

## 1. The landscape, as of Q3 2026

### 1.1 First-party (Roblox)

| Tool | Status | What it actually does | Verdict for TIDEKEEPER |
| --- | --- | --- | --- |
| **Roblox Studio Assistant** | GA; agentic update April 2026 adding Planning Mode and automated playtesting | In-Studio LLM: writes Luau, plans multi-step tasks, generates assets, runs playtests | **Use** for Studio-side assembly in it5. Not for architecture. |
| **Studio MCP server** | **Built into Studio**; enable via Assistant → Manage MCP Servers → *Enable Studio as MCP server* ([docs](https://create.roblox.com/docs/studio/mcp)) | Exposes the open place to an external agent: read/write the DataModel, `execute_luau` in Edit/Client/Server contexts, run playtests, capture console + screenshots. Quick-connect supports Claude Code/Desktop, Codex CLI, Cursor, Gemini CLI, VS Code, Antigravity. Aug 2026 update added explicit `studio_id` routing for multi-instance work. | **This is the single most important tool for iterations 4–5.** It is how a coding agent closes the loop between headless correctness and actual Studio behaviour. |
| **Cube 3D** | GA since Mar 2025; 1.8 B params, trained on 1.5 M assets; open-sourced; `/generate` in Assistant + in-experience Mesh Generation API | Text → single textured mesh, seconds. In-experience generation limited to 5/min/experience at beta. | **Use** for first-pass blockouts of the 200 finds. Output needs cleanup. |
| **4D generation** | Open beta Feb 2026 | Cube plus *behaviour*: generates functional objects (schemas: four-wheeled drivable car, single-mesh object). ~160 000 objects generated in early access in Wish Master, which reported a 64% play-time increase. Roblox says an "open vocabulary schema system" is the goal. | **Not applicable.** Our objects are inert props; the interesting behaviour is in our simulation, not in the mesh. Revisit if the schema system opens up. |
| **Procedural Models** | Launched 2026 | Parametric 3D assets from text or image, with *parameters you can reshape without regenerating* | **Strong fit.** Colourway/material variants of one find silhouette (doc 07 §5.1) is exactly the parametric use case. |
| **Scene Generator** | Announced RDC 2026, "later this year" for both Build and Studio | Text prompt + reference image → a functional, editable scene layout | **Watch.** Could do the island blockout in it5. Do not plan a dependency on an unshipped tool. |
| **Build** | Public alpha (New Zealand, then Serbia + Singapore); ~9 000 games published; **71% of creators had never used Studio** | Mobile-first prompt-to-game inside the Roblox app; shared backend/models/chat history with Studio | **Not a build tool for us.** It is the competitive context: the floor of "a game" is rising and generic prompt-generated cozy games are about to be abundant. Our moat has to be systems depth, which Build cannot produce. |
| **NPC behaviours / AI playtesting** | "two new behaviours by year-end", incl. NPCs that playtest | Automated playtesting without human testers | **Watch for it5.** Would be genuinely useful for funnel testing. |

### 1.2 Third-party

| Tool | What it is | Verdict |
| --- | --- | --- |
| **Meshy** | Text/image → textured 3D, PBR maps, remesh to Roblox triangle limits, one-click Roblox Bridge to Creator Hub | **Primary asset generator.** Textured output beats Cube's untextured blockouts for shipped props. Free tier is enough for prototyping. |
| **Nilo** | Browser WebGPU engine, natural-language editing, one-click rigging, LOD slider, FBX/glTF export to Roblox | Useful for the *variant* workflow and for LOD. Note that most of the available writing about it is its own marketing; treat performance claims as unverified. |
| **Community MCP servers** (`robloxstudio-mcp`, Vibe Blocks) | Predate the official server; add specialised inspection/debug tooling | **Skip.** Roblox's own docs recommend starting with the built-in server. Fewer moving parts. |
| **Rosebud AI** | Prompt-to-game, largely 2D/Phaser | Not relevant. |

### 1.3 What the landscape actually means for this project

Three conclusions, and they are the reason the iteration plan looks the way it does.

1. **Generative tooling is excellent at assets and mediocre at systems.** Every tool
   above converges on "make me a mesh / a scene / a starter game". None of them will
   produce a deterministic resolve-on-read simulator with a 68-byte wire format. So the
   plan front-loads the systems work into headless iterations where an agent is strong,
   and back-loads asset generation into iteration 5 where the tooling is strong.

2. **The Studio MCP server changes what "done" means.** Before it, an AI agent could only
   claim "the code parses and my mock says it works". With it, the agent can open the
   place, execute Luau in a real DataModel, run a playtest, read the console and take a
   screenshot. Iterations 4 and 5 are therefore allowed to claim Studio-verified
   behaviour — and are *required* to, rather than hand-waving it.

3. **Build is raising the floor, which raises the bar.** With 71% of Build creators never
   having opened Studio and ~9 000 games already published from prompts, "a competent
   cozy game" is about to be free. A 2027 hit has to be something a prompt cannot
   produce. Asynchronous cross-player simulation with a shared deterministic world clock
   is exactly that.

## 2. How each iteration uses AI

### Iteration 2–3 — headless, no Studio, no generative tooling

Pure Luau under a Lua VM harness. The agent's leverage here is writing a lot of correct,
tested, deterministic code fast. Generative asset tools are **forbidden** in these
iterations because there is nothing to put an asset on and it would create the illusion
of progress.

Verification: `tidekeeper/tools/tidekeeper-quality-gate.js`.

### Iteration 4 — Studio MCP enters

The agent connects to a live Studio instance and:

1. builds the Explorer tree from `tidekeeper/code/` (a scripted insert, not hand-clicks),
2. uses `execute_luau` to run the *real* codec against the *real* `buffer` API — this
   catches the class of bug the VM harness cannot,
3. runs a playtest, reads console output, screenshots the Ledger and Chart screens,
4. iterates on UI layout against real screenshots at phone resolution.

**What MCP still cannot tell you:** whether it feels good. Camera feel, audio timing,
the pacing of the Ledger replay, whether the tide's turn is satisfying. Those go in
[`11-HUMAN-AUTHORED.md`](11-HUMAN-AUTHORED.md) and stay there.

### Iteration 5 — generative asset pipeline

The 200 finds and 90 décor pieces, produced as a batch with a fixed recipe:

```
for each find in FindsConfig:
  1. Meshy text→3D from the find's art-direction prompt template
       "{material} {object}, weathered, low-poly game prop, neutral lighting,
        single object, plain background, readable silhouette"
  2. Meshy Remesh → ≤ 900 tris, quad topology
  3. Bake to the family's shared 1024² atlas   (8 families, not 200 textures)
  4. Roblox Bridge → Creator Hub
  5. Procedural Models for colourway/material variants of the same silhouette
  6. HUMAN GATE: silhouette check at 48 px, scale check against a reference stud cube,
     pivot check, and a "does this belong in the world" judgement
  7. Write the FindsConfig row (id, mesh, atlas rect, taste vector, value, zone weights)
```

Step 6 is not optional and is not an AI task. The failure mode of batch generation is
200 individually-acceptable objects that do not look like they came from the same world.
Budget a human day for curation and expect to reject ~35%.

### Iteration 5 — Scene Generator, if it has shipped

Island blockout from a prompt + reference image, refined in Studio. **Contingency
required:** if it has not shipped, the island is hand-built per doc 11. The plan must
not have a hard dependency on an unreleased tool.

## 3. Rules for AI-generated code in this project

Learned from the sibling project's audit history. These are enforceable, not advisory.

| Rule | Enforcement |
| --- | --- |
| No module ships without an executing test, not merely a parsing one | quality gate |
| No config key ships without a real reader or a `@future WPn` annotation | `find-dead-config.js` |
| No claim of Studio behaviour without an MCP transcript or a screenshot in the handoff | handoff review |
| Report the *real* output of every tool, pasted, never paraphrased | handoff template |
| A partial, honest result beats a complete, claimed one | explicit in every iteration prompt |
| Generated prose/templates are reviewed by a human before shipping | doc 13 |
| No runtime LLM calls in gameplay | doc 04 §4.1 — the game must work offline and deterministically |

That last one deserves emphasis: it is tempting to generate Ledger prose with a text
generation API at runtime. **Do not.** It breaks determinism, breaks offline play, costs
money per session, introduces a moderation surface, and is worse than a well-built
template system with 180 entries.

## 4. Verification ladder

What each iteration is allowed to claim.

| Level | Evidence | Available from |
| --- | --- | --- |
| L1 — parses | `check-syntax.js` | it2 |
| L2 — executes correctly | Lua VM harness assertions | it2 |
| L3 — integrates | session harness with faked adapters | it3 |
| L4 — runs in the engine | Studio MCP `execute_luau` transcript | it4 |
| L5 — plays | Studio playtest, screenshots, console clean | it4 |
| L6 — feels right | a human played it | it5 |
| L7 — works at scale | live telemetry from a soft launch | post-it5 |

**Never claim a level you do not have evidence for.** The handoff template in
[`12-ITERATION-PROMPTS.md`](12-ITERATION-PROMPTS.md) requires the level to be stated.
