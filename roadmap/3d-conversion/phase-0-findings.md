# Phase 0 findings — the spike (draft: feel judgments pending hands-on playtest)

**Branch:** `feat/3d-conversion` (spike branch; `main` tagged `2d-legacy`).
**Scene flow:** boot lands on the main menu as usual; its Play button loads
`scenes/main_3d.tscn` (the shell mounts `main.tscn` itself). On `main`,
Play loads `scenes/main.tscn` directly — that one-line difference in
`main_menu.gd` is the branch's only menu change.

## Rendering approach: per-cell meshes (not a SubViewport plane)

The doc offered both; per-cell meshes won on three counts:

1. **`/root/Main` hard-coding.** 86 references across 57 files resolve the
   live sim via `get_node("/root/Main/...")`. A SubViewport-mounted scene
   would live at `/root/<spike>/SimViewport/Main`, breaking most of the
   game. The spike instead instances `scenes/main.tscn` at runtime as a
   direct child of the window root (path `/root/Main`, exactly like the
   shipped game and the GUT tests), then hides its CanvasItem layers
   (`World`, `Units`, `Projectiles`, `Structures`). The sim runs untouched;
   the HUD CanvasLayer stays visible and overlays the 3D viewport fine.
2. **No Camera2D fight.** A SubViewport would need the 2D `Camera2D`'s
   pan/zoom either disabled (breaking `PlayerController`) or
   two-authority-synced every frame. The mesh approach renders the full
   map with no 2D camera in the loop at all.
3. **It is the Phase 1 direction anyway** — option 2 was labeled the
   cleaner path, and this proves the `GridWorld._cells` → mesh projection
   pipeline (sim → render only, hard rule 3) before any Phase 1 commitment.

Implementation: one unshaded vertex-colored `ArrayMesh` (~1.8k quads,
single draw call) rebuilt from `GridWorld` cells, throttled to 0.2 s and
dirtied by the grid's own signals (`cell_destroyed`, `cells_revealed`,
`wall_hp_changed`, `lava_risen`, `lava_receded`, `cave_in_occurred`).
Colors mirror `grid_drawing.gd`'s flat palette (ice surface, per-layer
dirt, rust ore darkened by depletion, steel wall tinted by the shared
wall-HP pool, lava/magma/fresh-ore). Player fog of war tints every quad
via the existing `fog_state_at()` (0 = `FOG_COLOR`, 1 = lerped by
`FOG_MEMORY_ALPHA`, 2 = full color) — same scheme as the 2D overlay.

One unit hooked: the first player miner renders as a `Sprite3D`
billboard (`frost_mines_assets/units/miner_l1_player.png`) following
`unit.global_position` — sim → render decoupling proven without touching
`unit.gd`.

## Camera rig (scripts/three_d/main_3d.gd)

- `Camera3D` under a ground-pivot rig, fixed **55° pitch**, dolly zoom.
- **Dolly:** 3–25 units (start 12), wheel ±×1.1 (reuses the
  `camera_zoom_in/out` action bindings too).
- **Pan:** WASD/arrows via the existing `camera_up/down/left/right`
  actions, plus edge-of-screen pan (24 px margin); speed scales with dolly.
  Clamped to the same rect `player_camera.gd` uses.
- **Tab:** teleports between saved surface (2D camera start) and
  underground (own `MineEntry.get_underground_position()`) bookmarks,
  remembering where each layer was left — same semantics as
  `player_camera.set_view`, without the slide.
- Mapping: 2D pixel → 3D at 0.01 units/px; 2D +y maps to +z (underground
  sits "south"/toward the camera, matching its on-screen position in 2D).
- FOV left at the 75° default; only a flat dark background environment —
  no lighting (deliberately out of scope).

## Sim changes on this branch

The 3D presentation layer is still new files (`scripts/three_d/`,
`scenes/main_3d.tscn`/`world_3d.tscn`), but the "zero sim changes" claim
did not survive Phase 1. Verified sim-side edits (vs `main`):

- `scripts/autoload/constants.gd` — new `SURFACE_ROWS` (= 6): the surface
  is a walkable band, not a single row.
- `scripts/world/grid_world.gd` — `SURFACE_TOP` + `is_surface_row()`; the
  `player_fog_revision` counter and `consume_player_fog_changes()` change
  feed the 3D fog/terrain rebuilds poll.
- `scripts/world/grid_map_generation.gd` — surface band generation
  (open-ground rows `SURFACE_TOP..0`); the A* region reaches `SURFACE_TOP`.
- `scripts/world/grid_pathfinding.gd` — `find_path_underground()` seals the
  whole surface band for crawler raids; owner wall-seal lifts read the seal
  map.
- `scripts/world/wall_segment.gd` — a built wall seals its entire column
  through the band (`_seal_column`), recorded in
  `GridWorld._wall_sealed_cells`.
- `scripts/world/building.gd` — base footprints seal their full band-row
  height (`_mark_footprint_solid`).
- `scripts/world/grid_fog_of_war.gd` — per-frame diff of the player's fog
  state bumps the revision (with a `PLAYER_FOG_CHANGE_CAP` overflow
  warning; plan 01, PR #7).
- `scripts/world/lantern.gd` / `tower.gd` — attack stand points moved off
  the fixed row-0 ground line onto the structure's own band row.
- `scripts/units/unit_navigation.gd` — building stand point clamped into
  the band; kiting walkability floor at `SURFACE_TOP`; the enemy-wall check
  reads the seal map.
- `scripts/units/unit_combat.gd` (+ `building.gd`, `burning_ground.gd`) —
  damage/fire/immune popups branch to `DamagePopup3D` when the shell runs.
- `scripts/controllers/player_commands.gd` — `_screen_to_world()`
  unprojects through the rig camera; order markers and attack telegraphs
  branch to 3D spawns.
- `scripts/controllers/player_selection.gd` — drag-box selection projects
  units through the rig camera (plan 02, PR #7).
- `scripts/controllers/player_build_placement.gd` — shell-mode placement
  preview (`BuildGhost3D` + `RangeDisc3D`, 2D ghost skipped); tower/wall
  validity accepts any band row.
- `scripts/controllers/player_camera.gd` — pan clamp and default view
  extended to the band.
- `scripts/controllers/ai_awareness.gd` — AI tower/lantern cell picks
  iterate the whole band.
- `scripts/autoload/weather_manager.gd` — meteors target any band row.
- `scripts/ui/main_menu.gd` — Play loads `scenes/main_3d.tscn` (the
  branch's one menu edit).
- `scripts/autoload/settings_manager.gd`, `scripts/ui/debug_overlay.gd`,
  `scripts/ui/minimap.gd` — graphics-quality persistence, Probe3D perf
  readout, minimap camera rect follows the rig.

Every edit is either the surface-band generalization (a sim-side feature in
its own right) or a one-way presentation branch (`Presentation3D.shell()`
is null in 2D, so the 2D path and the GUT suite are untouched). The
sim → render-only rule still holds; nothing 3D writes back.

## Known gaps (deliberate spike scope)

- Player mouse input (selection/orders) still feeds the hidden 2D scene;
  mouse → ground picking for real 3D interaction is a Phase 1 task.
- Screen shake / view slide / reduced-motion handling not ported to the rig.
- Effects (popups, particles, weather visuals) don't render in 3D.
- Terrain is a single flat plane; surface and underground coexist at
  y = 0 as in 2D (Tab separates them).

*Update: all four closed by Phases 1–2 — rig-camera picking (including
drag-box select, plan 02 / PR #7), reduced-motion-aware rig shake in
`main_3d.gd`, the full effects layer (`effects_3d.gd` /
`event_proxies_3d.gd`), and sculpted dune terrain (`height_field.gd`). See
[phase-1-progress.md](phase-1-progress.md).*

## Go / no-go checklist

- [ ] Camera pan/zoom/Tab feels tight (no seasickness, no dead zones). — *pending playtest* (deterministic camera coverage exists in `tests/test_3d_camera.gd`; the feel judgment stays human)
- [ ] The 2D tile data reads clearly from an angled view. — *pending playtest* (deterministic renders via `tools/capture/run_capture.sh`; the readability judgment stays human)
- [ ] Sim still runs at 60fps+ with the 3D viewport open. — *partially verifiable headless*: BENCH mode (`STRESS_UNITS=100 BENCH=30`) prints Probe3D per-section script-time averages after 30 sim-seconds at 200 live units (setup in `tools/capture/README.md`) — real-GPU frame rate stays *pending playtest*; frame times under software GL are meaningless
- [x] No changes were needed in any autoload or AI script to make the camera work.
