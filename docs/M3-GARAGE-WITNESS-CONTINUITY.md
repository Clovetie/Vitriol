# M3 Garage witness continuity — Edit synced; human Play pending (2026-10-13)

> **Newer preflight:** The service Garage fixture now walks the existing
> east-door threshold instead of teleporting a fake player; an independent
> read-only Edit-mode Studio-Source probe checked **43** actual corridor rays
> and three threshold crossings on the user's real Garage. Garage **47/47**,
> shadow **21/21**, gate **35/35**, compiler **61/61**. No human Play or frame
> budget verdict. See [`M3-EXPLAINABILITY-CORRIDOR.md`](M3-EXPLAINABILITY-CORRIDOR.md).


While continuing roadmap work before another Play request, I found two ways a previously *sensed* survivor could be counted as a Garage entry without a witnessed **ground-level outside→inside** crossing:

1. After seeing a survivor outside, the Braid could lose contact for arbitrarily long, then reacquire them already inside. The old per-player exterior boolean survived the unseen interval.
2. A roof-level survivor at the Garage X/Z footprint was treated as “outside”; subsequently seeing them below the roof, already inside, could count as an entry. Height was checked for *inside*, but not for a valid *outside ground witness*.

The new `GarageHabit` clears the partial exterior/inside observation whenever its player is **not the genuinely sensed nearest living prey at the end of a Think**, including a Day/Dawn/nonthreatening Think or another player taking priority. It also clears the partial observation for a roof/high or below-ground sample. Only uninterrupted sensory samples from the **same player**, outside and then within the actual floor at grounded height, increase the existing run-local visit counter and confidence. A later legitimately seen outside→inside crossing still trains. Completed evidence survives clue loss and Day/Dawn; only the *unfinished witness* is reset. This deliberately prefers missed evidence to invented knowledge; it may make three entries harder to witness across occluding walls, which requires human Play feedback rather than weakening the sensory rule sight unseen.

This is a narrow fix to the **new, not-yet-Play-accepted** Garage preference, not a change to the accepted Night regional hunt, clue sweep, House_01 exit, both-house cover, planted-foot gait, prey/lure priorities, or authored map. No added ray, cadence, runtime gameplay Instance, DataStore, player-secret remote, Q-learning or public target. It adds at most one tiny per-Think cleanup pass over the current per-player witness set (co-op cap four); **real cadence cost remains unmeasured**.

## Evidence

- `tools/vitriol/garage-habit.luau` **46/46**: new roof→inside refusal, unseen exterior→interior refusal (pure and integrated service), second player's sight interruption, fresh continuous crossing still counted. Shadow-only predictor **19/19**; quality gate **35/35**, official compiler **61/61**, `git diff --check HEAD` clean.
- Guarded Vitriol place `92448193604950` in Edit mode. Old `GarageHabit.Source` and `CreatureService.Source` were both checked **exactly** against their respective last verified readbacks before modifying just these two ModuleScripts; final Source and class readback **2/2 exact** (`tools/reports/m3-garage-continuity-sources.json`). Read-only, freshly compiled Studio-Source test against the user's **real Garage** confirmed unseen gaps and roof drops do not count, real consecutive grounded entries do, and the two original physically checked front→interior legs still work (`tools/reports/m3-garage-continuity-live-source.json`, `ok:true`, visits 4, misses 1). Post-sync static verifier `ok:true` (`m3-garage-continuity-static.json`). Edit-mode probes are **not** a human Play verdict.
- Still open: fourth-Garage-visit Play observation, regular measured `Creature:Think`/`Session:Slow`/`Time:Publish` attribution. Prior single warnings **8.313/1.000 ms**, **0.204/0.050 ms**, **0.389/0.050 ms** respectively remain real and unresolved; no budget/warning threshold was raised or silenced. Save/publish and Git push remain unconfirmed.
