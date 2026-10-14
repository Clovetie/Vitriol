# Vitriol Edit sync and source backup — NOT a cloud place save (2026-10-13)

> **Later owner-approved church rest position:** Z=-199 was explicitly
> approved after an Edit-only comparison with the collidable Bell at the
> old Z=-210 approach. The updated LOCAL verifier now passes, and fresh
> independent read-only Edit audit is **10/10, 61/61 Sources/classes, zero
> unexpected drift**. The owner confirmed a post-sync Save to Roblox with
> Notes/Version History checkpoint. No lever or other Studio object moved.
> See [`CHURCH-LEVER-CURRENT-POSITION-APPROVED-2026-10-13.md`](CHURCH-LEVER-CURRENT-POSITION-APPROVED-2026-10-13.md).

> **Later guarded House/Church deployment:** The two then-local Sources
> were subsequently Edit-synced **2/2 exact** against their historical full
> Source/class baselines. Independent audit finds no Source drift, 9/10
> verifiers (same unresolved lever), and no post-sync cloud Save. The
> pre-sync published version approved by the owner does not include these
> changes. See [`HOUSE-CHURCH-GUARDED-EDIT-SYNC-2026-10-13.md`](HOUSE-CHURCH-GUARDED-EDIT-SYNC-2026-10-13.md).


> **Later owner update:** The owner reports the Vitriol place was published,
> confirms that published *pre-sync* version in Version History, and approves
> using it as a safety checkpoint. This document's earlier “unconfirmed”
> statements describe the older capture/sync checkpoint. The TWO newer local
> Sources (`CreatureService`, `ChurchNavigation`) remain unsynced; bridge
> credentials are unavailable now. A future successful guarded Edit sync
> would still require a NEW Save to Roblox with Notes and Version History
> check to protect those installed Sources. This is not an independent
> Studio/UI verification or authorization to alter the church lever.

> **Newest offline boundary:** A second local-only game Source,
> `ChurchNavigation`, joined the pending `CreatureService` change. The
> later read-only Edit audit has precisely those two planned local Source
> differences and the unresolved bell lever Z=-199 vs approved Z=-210;
> do NOT claim 4/4 current Studio parity. No further Studio Source write
> or full-place cloud save has been verified. See
> [`CHURCH-LEVER-ENDPOINT-READONLY-2026-10-13.md`](CHURCH-LEVER-ENDPOINT-READONLY-2026-10-13.md).

> **Earlier offline change:** The prior four-script 4/4 exact readback below
> predates a local-only `CreatureService` House→Garage priority correction.
> Its new Source is **not Studio-synced**. The later read-only audit reports
> exactly one pending local Source difference and the same unresolved bell
> lever; see [`HOUSE-GARAGE-HABIT-EGRESS-PRIORITY-2026-10-13.md`](HOUSE-GARAGE-HABIT-EGRESS-PRIORITY-2026-10-13.md).

The user supplied a temporary bridge URL and token to continue work and prevent data loss. **Neither value was put in the Roblox game, any repository file or the ZIP backup.** The legacy bridge uses the token only for authenticated Edit-mode jobs. A Quick Tunnel URL is temporary and may change on restart; it is not data storage or a persistence mechanism [1](https://developers.cloudflare.com/sandbox/api/tunnels/). Do not hardcode credentials in any Script, LocalScript, ModuleScript, Remote or published place.

## What is now in the open Studio Edit place

The fail-closed `tools/sync-pending-house-garage.py --check` first verified place ID `92448193604950`, `RunService:IsRunning() == false`, four existing `ModuleScript` classes and exact prior **full Studio Sources** from the last verified readbacks. All four were guarded and pending; `--apply` rechecked guards before each write and wrote **only**:

- `ServerStorage.Vitriol.Creature.HouseAccess` — lower-first sweep plus full-core pier/original furniture depth clearance and a temporary supported-crouch target.
- `ServerStorage.Vitriol.Creature.CreatureCore` — applies that existing foot-supported crouch only for the idle House exit, not genuine prey or chomp.
- `ServerStorage.Vitriol.Services.CreatureService` — earlier bounded Garage decision-event staging, with House sweep integration unchanged.
- `ServerStorage.Vitriol.Bootstrap` — earlier server-only Garage explanation emitted after measured Think.

Immediate individual post-write and final Source/class readback were **4/4 exact**, and a subsequent read-only `--check` found all four already exact. No map geometry, user furniture, phase durations, UI or other scripts were written. Local code quality gate **36/36**, House fixture **63/63**, Garage fixture **69/69**, official compiler **61/61**. Synthetic fixtures are not live frame-budget or gameplay measurements.

Read-only, freshly compiled **actual Studio Source** House probe `tools/reports/house-exit-foot-supported-live-source.json` returned `ok:true`: the original House_01 door/open closet ray, installed-cover denial, stage, raised-core down-only command, and angled pier/table corner rejection before a physical ray. It statically checked the real `CreatureCore` source uses the supported crouch. It did **not** animate a real Braid in Play. Actual Studio Garage-habit Source/real floor probe `tools/reports/garage-habit-after-guarded-sync.json` returned `ok:true`; static verifier `pending-four-static-after-sync.json` returned `ok:true` (7 remotes, 211 authored Braid parts, 24 blood parts, no defects). The bridge cannot observe live Play.

## Read-only backup and deliberate non-overwrites

`backups/vitriol-studio-edit-sources-2026-10-13.zip` is a **read-only snapshot of all 75 surveyed Studio script Sources and classes**, including 14 Studio-only scripts outside this checkout. The manifest records paths, classes and SHA-256 hashes; all 75 ZIP entries verified, and the four changed Studio Sources match local files byte-for-byte. The ZIP contains about 673 KB of script text. **It is not a full `.rbxl`, a map/asset/attribute backup, a cloud place save, a published version or a player DataStore backup.** No user-authored geometry was touched.

The read-only map verifier used to require `Road_Main.Size.Z == 560`, which falsely rejected the user's longer road. **Only the verifier was corrected** to require that the original 36-by-560 safe corridor remains covered by an anchored collidable Part. The actual Studio road was measured at `Size (36, 0.24, 593)`, `Position (0, 0.12, -16.5)` and now passes; its geometry was **not** edited. An independent read-only inventory of all 10 Edit verifiers found **9 passing**. The church-bell verifier correctly flags the one remaining mismatch: the actual `Church_BellLever` is anchored, noncolliding, unarmed at `(119, 2.5, -199)`, while the previously user-approved position is `(119, 2.5, -210)`. We did **not** move this authored lever or relabel the audit as passing. See `tools/reports/vitriol-edit-verifier-inventory.json` and `tools/reports/bell-rest-edit.json`. The broader audit remains **failed** at this bell guard.

Source-only parity originally normalized terminal newlines and compared all 61 checkout scripts: **59 equivalent**, two deliberate Studio differences preserved in the ZIP: the user's shortened `DayNightConfig` phase seconds (Studio `15/41/10/200/15` vs longer local defaults) and three extra blank lines **before** `return VictimCamera`. No broad sync was run and those Studio Sources were not overwritten. A subsequent **comprehensive read-only Edit audit** (`tools/reports/vitriol-studio-audit-comprehensive-edit-2026-10-13.json`) collected all 10 verifier results, all 61 classes and all 61 full Sources even though the bell guard failed: **46 byte-exact**, **13 missing exactly one final LF in Studio**, **2 explicitly preserved user differences with pinned hashes of BOTH Studio and checkout**, **zero unexpected Source drift**. It still correctly reports **FAIL** due solely to the lever position; neither terminal LF classification nor the two pinned exceptions overwrites or conceals an arbitrary interior edit. Offline audit guard regression tests **9/9**; the read-only report is *not* a cloud save or Play result.

A later **read-only selected-property** inventory of 1,930 Edit Instances across 13 services complements this Source ZIP. It is likewise incomplete and not an atomic/full-place or cloud backup; see [`STUDIO-EDIT-PROPERTY-INVENTORY-2026-10-13.md`](STUDIO-EDIT-PROPERTY-INVENTORY-2026-10-13.md). Two still later local-only Module Sources remain unsynced.

## Still required to avoid loss

**Studio Editor Source parity is not a confirmed Save to Roblox.** The bridge offers no advertised full-place save/publish operation, so the cloud save remains **unconfirmed**. In the still-open correct Vitriol Studio place, use **File → Save to Roblox with Notes**, then verify that checkpoint in **Version History** [Roblox guidance](https://create.roblox.com/docs/projects/version-history). This saves work-in-progress without making it the published player version; do **not** Publish to Roblox unless intentionally releasing the changes [Roblox Studio announcement](https://devforum.roblox.com/t/improved-save-experience-in-studio/1590354). **File → Save to File** `.rbxl` is an optional second, full-place local backup. The script ZIP, tunnel and temporary token cannot substitute for either full-place save. No DataStore or secret-bearing runtime script was added.

House_01/House_02 live egress, fourth-Garage-visit behavior and normal Play cadence remain **unverified**. The real earlier Session/DayPrep/Time warnings remain open. No Play test was requested; Git push also remains unconfirmed.
