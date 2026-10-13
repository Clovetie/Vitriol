# Vitriol — first playable town slice (2026-10-12)

This is a **deliberately laid-out, edit-mode-authored playable blockout**, not a procedurally generated runtime map or a claim that the final 600×600 rural town's bespoke art is finished. It is stored in the Vitriol Studio place under `Workspace.Map` and can be reapplied without duplication using `jobs/author_map_vitriol.lua` **only in Edit mode**. The script refuses a different place ID or an unrecognised map version; `jobs/verify_map_vitriol.lua` is read-only.

## Explorer ownership

```text
Workspace
├─ Vitriol/                         Existing time anchor, preauthored Braid and blood pool (untouched)
└─ Map/                             VitriolMapVersion = 1
   ├─ Ground/                        Reused stock Baseplate, resized/recolored as foundation
   ├─ Roads/                         Main quarry road, crossing, shoulder, tracks, faded markings
   ├─ Structures/                    Seven named structural models with Meta configurations
   │  ├─ Millers_Garage/             Open service bay, real roof and a lift
   │  ├─ Filling_Station/            Canopy and two future-use pumps
   │  ├─ House_01/ and House_02/     Open doorways, windows, porches
   │  ├─ Church_BellTower/           Nave, pews, tall tower silhouette
   │  ├─ Riverside_Mill/             Deck, wheel and water crossing
   │  └─ Field_WaterTower/           High field landmark
   ├─ Interiors/                     Workbench, drums, closets, pews, lift, pumps
   ├─ Nature/                        Fixed-position woods cover, rocks, culvert
   ├─ Waterways/                     Mill channel and crossing bridge
   ├─ Lighting_Anchors/              Five static amber PointLight fixtures
   ├─ Zones/                         Nine nonblocking ground tiles + church tower roof
   ├─ NavHints/                      Nonblocking road/woodland cost hints
   └─ Spawns/                        Reused engine SpawnLocation: Spawn_Garage
```

**Layout:** north is `+Z`. Road runs north/south through `X ≈ 0`. Players spawn at `(-54, -55)` by the west garage; the filling station is farther south. Two porch houses sit to either side of the road farther north. The church/tower is southeast, the mill and channel northeast, and the field/water tower beyond. Woods clusters enclose the west and far-north edges. The floor spans `X,Z = -300…300`, with simple solid cover and several playable entries. Zone classes use only the fixed roadmap vocabulary; all nine horizontal ground volumes tile the floor, and all ten zone parts are invisible, anchored, noncolliding and nonqueryable. The authored structure and joint tags are **metadata for later systems**, not a claim that destruction is playable yet.

**Survey before authoring:** the only top-level prototype geometry was a stock 2048×2048 Baseplate, a stock SpawnLocation and an empty TreeBrushFolder; `Workspace.Vitriol` already held the integrated creature/time/effects. The author job relocated/reused the two stock game objects and removed only their stock decal/texture and the empty brush folder. It did not wipe Terrain or user-built content. A second author-job run produced `created=0, reused=206, moved=0, removedPrototype=0`. Studio verification: `ok=true`, 7 structural models, 10 zones, 5 lamps, no defects. The post-build survey shows `Workspace.Map` with 173 Parts and the original `Workspace.Vitriol` separate.

## Honest next passes

- No bespoke meshes, sound IDs, functional generator, searchable containers, loot, vehicles, destroyable porch collapse, usable tower climb or cellar yet. Geometry is authored **blockout**, not final human art.
- The flat water channel is a visible surface over the reused foundation, **not** swimmable water. The culvert and church tower are landmarks pending traversal/interaction work.
- No custom GUI was created. The user-selected night/day loop and existing LightingDriver continue to use preauthored objects only; lighting/audio legibility and collision/pathing require **fresh Studio Play** observation.
- Future assets should replace named pieces *inside these folders* through guarded edit-mode jobs or manual Studio authoring; do not instantiate map or UI objects during gameplay. The next closed-loop handoff is `NEXT-AGENT.md`.
