# Dormant manual barricade Tool (2026-10-12)

**Status:** authored and wired in the open Studio Vitriol place, but intentionally **unavailable in normal Play until crafting/unlock exists**. The user requested both placement at authored openings and nearby free placement. No Tool is in StarterPack and none is granted to a player by runtime code. The Tool, its Handle, two socket markers, eight reusable board Parts and their removal prompts were all authored in **Edit mode**. Gameplay only moves/configures these existing Instances; it never calls `Instance.new` or `Clone`.

## Authored hierarchy

```text
ServerStorage.Vitriol
├─ Tools/BarricadePlankTool (Tool)/Handle (Part)
└─ BarricadePool/Board_01..Board_08 (Part)/ReleaseBoard (ProximityPrompt)
Workspace.Map
├─ BarricadeSockets/House_01_Door, House_02_Door (invisible metadata Parts)
└─ PlacedBarricades/ (empty in Edit mode)
```

The guarded, idempotent `jobs/author_barricade_tool_vitriol.lua` created **24** authored objects on the first run and **0** on the second (24 reused). Its read-only verifier checks that the Tool is **still in ServerStorage**, no copy is in StarterPack/Workspace, eight boards are idle in storage, both sockets are nonblocking metadata and the placed folder is empty in Edit mode. Existing garage gate and day-prep props are not changed.

## Prepared behavior when a later crafting system equips the one existing Tool

The server binds the stored Tool's `Activated` event, but it will only place a board when the Tool has been moved (not copied) into a living player's character during Day/Dawn. It validates ownership, phase, distance/facing and the finite pool. **Aim with the character's facing direction**, not the mouse cursor: within 12 studs and a forward cone, an unclaimed authored house doorway socket wins. Otherwise, it raycasts seven studs forward to nearby, relatively level, queryable Map geometry; rejects interactions, existing boards and unsupported surfaces; and positions a free-standing board there. No ClientIntent or new remote is required. This is a first manual placement pass; mouse-precise aiming and arbitrary surface/ceiling placement are not claimed.

A placed board has a preauthored removal prompt. A nearby living player can noisily remove it, returning the *same* board to ServerStorage. A pursuing Braid is prevented from moving or starting a chomp through a placed board and can breach it after bounded pressure; at Dawn all boards return to the finite pool. There are **eight** slots; a ninth placement fails rather than cloning. The original service-bay gate remains its own one-use/day defense and is not replaced by the Tool. There is no crafting, distribution, persistence, cross-server inventory or visual placement preview yet. `HealthService` does reclaim the single preauthored Tool to storage **before** wiping ordinary carried Tools on death, and `PlayerRemoving` reclaims it on disconnect; the player still loses it. These paths are headless-tested, not Play-confirmed.

## Verification and next step

Local quality gate **15/15**: smoke **366/366**, original session **145/145**, day-prep **14/14**, garage barricade **15/15**, dedicated stored-Tool/placement test **17/17**, client boot **1/1**, official Luau compile **49/49**. With the Tool dormant, the creature now skips 60 Hz crossing checks unless a preauthored board is active; a test proves the idle fast path and the active frame interception. This is not a measured Studio performance result. The placement test simulates equipping the pre-existing Tool, validates server activation, socket priority, free placement/raycast rejection, removal/range checks, Braid interception/breach, Dawn reset, death/disconnect reclaim of the unique Tool, destruction of ordinary Tools, and zero game-created Instances. This is headless evidence, **not** a live Tool Play verdict. Studio author/verifier jobs compile; static/map/day-prep/barricade/tool verifiers passed, and guarded source parity **49/49 zero drift**. The existing visible fuel/night/barricade loop has not been given new Tool access. Save/publish and Git push are unconfirmed.

**When crafting is implemented:** move one *authored* Tool from ServerStorage to the rewarded player's Backpack/character (never clone it), test the existing death/disconnect recovery and placement in a fresh Roblox Play session. To support multiple simultaneous crafters, explicitly author more Tool slots and update the verifier/tests; do not allocate them at runtime.
