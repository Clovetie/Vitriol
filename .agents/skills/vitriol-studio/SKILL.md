---
name: vitriol-studio
summary: Safely synchronize Vitriol main Luau and preauthored objects with the connected legacy Roblox Studio bridge; close the test/debug loop.
---

# Vitriol Studio skill

## When to use
Any Vitriol script edit, Explorer object/UI authoring, Studio debug, test, asset/content addition, or handoff. This skill uses the **actual connected legacy bridge**; merta-studios/arenarobloxbridge was studied as an example of tool contracts and verification, but its modern `Get-BridgeGuides`, UI Engine, mesh tools and `/api/tool` are NOT advertised by this older bridge. Do not call nonexistent endpoints.

## Connection and scope

- Work from `Clovetie/Vitriol` **main**. Check `git rev-parse HEAD`, `git status -sb`, `INTEGRATION.md`, and identify place by `ping` before any mutation. At the recorded integration, place was *Place2*, ID `92448193604950`; re-check rather than assuming it persists.
- Supply `BRIDGE_URL` (HTTPS trycloudflare) and `BRIDGE_TOKEN` from the user **only in process environment**. Never write to repo, documentation, command examples, reports or source. The token passed to `/api/jobs` is a bearer secret. If Studio disconnected or a different game is open, stop and ask; don't write to a wrong place. Use `python tools/studio_bridge.py health`, `ping`, `state`.
- `tools/studio_bridge.py`: `runfile FILE`, `read PATH`, `reads PATH1,PATH2`, `inspect PATH`, `survey --out tools/reports/studio.json`, `parity`, `sync comma,separated,relative/paths`. `sync` writes from local `code/` using existing parent and correct class. Changes to `.Source` are not reliably observed by modules required earlier in the same Studio session; restart Play/Studio or rebuild modules for behavioral checks.

## Static-object authoring contract

1. **Edit mode only**: existing `jobs/author_static_vitriol.lua` checks `not RunService:IsRunning()`, then creates/repairs exact named objects. It is a Studio editor job, not game code. Add new classes/paths to this idempotent job or a new guarded editor job. Avoid replacing whole folders or deleting user-built map content. Mutations should be undoable in a single bridge job.
2. **Never create/clone a UI or game Instance while Play is running.** For UI, author `StarterGui` ScreenGui/Frames in Studio and change properties of copied `PlayerGui` instances only. For models/effects, author bounded pools with fixed maximums and reuse/hide; if capacity is exhausted, degrade explicitly. Third-party BloodEngine is installed but **not initialized** because it spawns droplets.
3. Game module calls `Instance.new`/`Clone` fail `node tools/static-content-check.js`. Keep static Braid max at 14 tendrils × 15 segments (plus core), Gore pool 24; update job, `MonsterConfig`, tests and verification together if limits change. Server `Remotes.init()` validates exactly seven preauthored remotes; there is no runtime recovery.
4. Run `jobs/verify_static_vitriol.lua`, verify exact classes, counts, duplicate-free names, source parity, and `StarterGui` design. Never claim static policy verified merely from grep; Studio tree must match.

## Closed loop

1. Read `ROADMAP.md` and list one small target with pass/fail criterion. Inspect live Studio subtree/source and compare `main`; avoid the unrelated Tunneling monster backlog.
2. Code in the correct `code/<Explorer path>.luau`. If adding world/UI assets, write Edit-mode guarded job and a read-only verification job. Test idempotency; no runtime constructors/clones.
3. Run `npm --prefix tools ci`, `bash tools/install-luau.sh`, then `node tools/vitriol-quality-gate.js --src code --report tools/reports/quality-gate.json`; this now **requires official `luau-compile`**. The older luaparse/Fengari transforms missed real Studio parse errors. Never waive syntax/undefined global/test errors. Run Studio `runfile jobs/verify_static_vitriol.lua` before code sync.
4. `python tools/studio_bridge.py sync Path1,Path2` for changed code only, then `python tools/vitriol-studio-audit.py` for a **read-only, fail-closed Edit-mode** check of the place ID, ten authored verifiers, all game script classes and source readback. The older `python tools/studio_bridge.py parity` checks sources only, not classes. Audit credentials belong in process environment; its credential-free offline tests run in the local gate. A pass is not a Play verdict. Use fresh Play (Edit-mode require cache can lie), capture Studio Output, FPS/network and client/server behavior, and change only one diagnosed issue at a time. Get human confirmation for visuals and input feel.
5. Record exact evidence in `INTEGRATION.md`; update `NEXT-AGENT.md` with achieved/not achieved and next experiment. Commit/push to main only with available authorization, and ask user to save/publish the Studio place; never equate live edits with a saved published place.

## Failure signatures

- `studio_connected=false`: Studio/plugin offline. Wrong `placeId`: stop.
- `/api/status` 404: this is a legacy bridge; use `/api/state`. No modern `/api/tool` here.
- readback mismatch: only source newline differences may be normalized; any other drift blocks handoff. Duplicate same-name modules can make the bridge read/write the wrong instance; inspect duplicates first.
- Preview/play differs from source immediately after `write_script`: Studio `require` cache; fresh Play/instance before judging.
- Any new runtime-created Instance: reauthor its bounded pool in Edit mode and update the static gate/test.
