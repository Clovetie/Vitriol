# House / church two-Module guarded Edit sync — 2026-10-13

> **Later owner-approved rest position:** The owner explicitly revised
> church lever approval from Z=-210 to the already-authored Z=-199. The
> original post-sync audit below (9/10) was accurate at that earlier
> checkpoint; updating only the LOCAL verifier and other tooling produced
> a fresh read-only Edit audit **PASS 10/10, 61/61 Sources/classes, zero
> drift**. No Studio Source/geometry write followed the saved 2/2 sync.
> See [`CHURCH-LEVER-CURRENT-POSITION-APPROVED-2026-10-13.md`](CHURCH-LEVER-CURRENT-POSITION-APPROVED-2026-10-13.md).

**Deployment boundary:** The owner confirmed that the *pre-sync* Vitriol place was published, visible in Version History, and approved that published version as the recovery checkpoint. This is the owner's confirmation, not independent access to the Studio UI. The temporary legacy bridge then connected to place ID `92448193604950` in **Edit**, not Play. Credentials were supplied through process environment only; they were not written to game code or repository files. No lever, geometry, phase config, other Script, UI, or asset was edited. **Later owner update:** After this exact Source readback, the owner confirmed **Save to Roblox with Notes** and verified the *new post-sync Version History entry*. This is a human confirmation, not independent bridge proof of the cloud checkpoint; no new Publish was reported.

## Exact changes and readbacks

The fail-closed `tools/sync-pending-house-church.py --check` verified **both** existing ModuleScript classes and complete prior Studio Sources against the earlier 75-script backup, and checked place ID and `RunService:IsRunning() == false`. The owner-approved `--apply --saved-checkpoint-verified` then rechecked each immediately before writing it and read it back immediately after. Final readback and a separate subsequent read-only `--check` found **2/2 exact**:

- `ServerStorage.Vitriol.Services.CreatureService` — local House exit-before-Garage habit priority through the full radius-expanded doorway seam. Source SHA-256 prefix `f6968a3f7027dac0`.
- `ServerStorage.Vitriol.Creature.ChurchNavigation` — only the exact authored bell lever at its current coordinate may terminate the final otherwise-clear navigation ray. Source SHA-256 prefix `75b95fed03d35894`.

The script performs sequential writes, **not an atomic two-Module transaction**. Both exact readbacks completed this time; an interrupted future apply must never be assumed all-or-nothing.

## Independent read-only post-sync evidence

`tools/reports/vitriol-studio-audit-after-published-checkpoint-sync.json` checked all ten Edit verifiers plus all **61 classes and 61 complete Sources**. Source drift is **zero**: 46 exact, 13 previously classified single terminal-newline differences, and two pinned, user-preserved differences (short `DayNightConfig` phases and Studio `VictimCamera` whitespace). **Nine of ten** content verifiers pass. The sole failure remains `verify_church_bell_vitriol.lua: lever changed at rest`: actual `(119,2.5,-199)` versus previously approved `(119,2.5,-210)`. The audit is correctly **FAIL overall**; do not mark authored-content parity green or relocate/approve the lever by inference.

A fresh read-only probe using the newly **installed Studio `ChurchNavigation.Source`** (`tools/reports/church-route-after-published-checkpoint-sync.json`) routes the reported western starting point through side `(86.25,-130.25)`, main entrance `(119,-130.25)`, and actual lever `(119,-199)`. A hypothetical request for the old Z=-210 coordinate still fails closed against the present lever. The read-only actual-Studio-Source House probe (`tools/reports/house-exit-source-after-published-checkpoint-sync.json`) succeeds for the original open closet lane, denies fully installed furniture, and stages safely from a corner. These are Edit/source/geometry observations, **not live Braid movement**, planted-foot contact, prompt usability, or frame-time evidence.

The local quality gate after this sync is **39/39**; focused House **74/74**, Garage **69/69**, church route **10/10**, bell **19/19**, official Luau compiler **61/61**, sync failure-path tests **6/6**, and selected-property archive tests **5/5**. None is a live Play verdict.

## Essential next boundary

**Owner-confirmed completion of the save boundary:** The owner says they used **Save to Roblox with Notes** and verified the *new post-sync* Version History checkpoint. A subsequent read-only Vitriol/Edit `--check` found the two installed Sources/classes **2/2 still exact**. The bridge cannot independently inspect the Version History UI or prove the cloud checkpoint, so this save is reported as **human-verified**, not bridge-verified. No post-sync Publish was reported; publishing again is not required for a work-in-progress save. Live Play acceptance (House_01/House_02 egress, church lure route, fourth Garage visit), measured cadence pass, and Git push remain unconfirmed. Do not request a Play test now.

A later hypothetical read-only preflight to the previously approved lever Z=-210 finds the original **collidable Bell** across the straight approach after excluding the current lever at Z=-199. Do not move the lever or call that hypothetical route body-clear. See [`CHURCH-APPROVED-LEVER-HYPOTHETICAL-PREFLIGHT-2026-10-13.md`](CHURCH-APPROVED-LEVER-HYPOTHETICAL-PREFLIGHT-2026-10-13.md).
