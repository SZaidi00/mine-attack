# Phase 1 — The 2.5D Port (the real conversion)

**Goal:** the complete, existing game — every unit, structure, weather
event, AI behavior — playable in a 3D viewport with current art, with
**zero changes to simulation code** and **all GUT tests green**.

This is the longest phase and the only mandatory one. It ships.

## 1.1 — Project & renderer setup

- Switch project renderer: Forward+ for desktop; keep a
  `gl_compatibility` export preset for web with reduced settings.
- Decide the ground truth: `GridWorld._cells` remains the only state.
  The 3D scene is rebuilt/refreshed from it; it never writes back.
- Add a `World3D` scene (`scenes/world_3d.tscn`): terrain mesh, unit
  container, structure container, effects container, lights.

## 1.2 — Terrain from the grid

- Replace per-frame `_draw` tile rendering with a `GridMap` (or chunked
  `ArrayMesh` rebuilt on cell change) sourced from `GridWorld._cells`.
- Cell states to represent visually: solid rock, dug/empty, ore (by
  richness tier), lava (animated), wall segments, the central wall.
- **Incremental strategy:** render only the visible layer for the
  current Tab view, exactly like today. Layer switching re-builds the
  chunk around the camera.
- Acceptance: mining a tile, lava flooding a cell, and a cave-in all
  update the 3D terrain with no sim changes.

## 1.3 — Units & structures as billboards

- Every unit/structure scene gets a 3D counterpart: a `Sprite3D`
  billboard (current pixel art) on a `Node3D` whose position is driven
  by the existing script's logical position.
- Approach: add a tiny "visual proxy" node per entity that subscribes to
  the entity; **do not** edit movement/combat code.
- Structures (building, tower, wall, lantern, trap, ladder, mine entry)
  become flat meshes or box stand-ins with billboard decals.
- Shadows: cheap blob shadows (decal quad) instead of real shadow maps
  for now.

## 1.4 — Camera & controls

- Port `player_camera.gd` per the Phase 0 findings.
- Selection box, right-click orders, radial build menu, hotkeys: all work
  by unprojecting mouse rays onto the ground plane. Selection logic in
  `player_selection.gd` and orders in `player_commands.gd` keep their
  logical API; only the screen→world coordinate transform changes.
- Acceptance: full control scheme (select, orders, train hotkeys,
  build placement, stances, disband, research, Tab, pause) works in 3D.

## 1.5 — Fog of war

- Replace 2D fog overlays with a shader on the terrain: a fog texture
  (from the existing fog maps) sampled per-fragment, darkening
  unexplored cells and tinting explored-but-unseen ones.
- Keep the existing fog logic (what is revealed, by what, vision radii)
  untouched — only the visual representation changes.
- Acceptance: `test_fog_of_war.gd` passes unmodified; fog looks correct
  from the pitched camera.

## 1.6 — Effects & weather visuals

Re-create as 3D equivalents, gameplay numbers unchanged:
- Snowstorm: 3D particles + screen-edge vignette + fog density.
- Volcano meteors: 3D projectiles + burning-ground decals.
- Cave-ins: falling rock meshes with real bounce (juice upgrade — same
  damage/push rules).
- Lava: emissive, slowly pulsing material on flooded cells.
- Necromancy raise channel, trap triggers, projectile tracers.

## 1.7 — UI pass

- `Control`-based HUD needs almost nothing; verify anchoring over the
  3D viewport at multiple resolutions/aspect ratios.
- Add a subtle ground-target marker for right-click orders (helps depth
  perception on the pitched plane).

## 1.8 — Performance & web audit

- Profile with a large army: draw calls, chunk rebuild frequency,
  billboard count. Instancing for repeated meshes (`MultiMeshInstance3D`
  for ore/rock cells is the likely win).
- Web export (`gl_compatibility`): document what degrades (shadows off,
  particle counts down, chunk draw distance). This was flagged in
  IDEAS.md and must land **before** any further visual features.

## 1.9 — Test & ship

- Full GUT suite green, headless.
- Play all 5 difficulties × 3 factions end-to-end.
- Export macOS/Windows/Linux + web via `tools/export_all.sh`.
- Ship as a release (pre-push hook handles it), with release notes that
  say plainly: "same game, new camera."

## Milestones within Phase 1

| Milestone | Done when |
|---|---|
| M1 | Terrain renders from `_cells`; camera pans/zooms/Tabs |
| M2 | Units + structures visible & animated as billboards |
| M3 | Full control scheme functional |
| M4 | Fog + weather + effects re-created |
| M5 | Tests green, exports built, release shipped |

## Definition of done for the whole phase

A player who knows the 2D game can play the 3D one without a manual and
not notice any missing feature.
