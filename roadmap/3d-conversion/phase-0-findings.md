# Phase 0 findings — the spike (draft: feel judgments pending hands-on playtest)

**Branch:** `feat/3d-conversion` (spike branch; `main` tagged `2d-legacy`).
**Scene to run:** `scenes/main_3d.tscn` (set as `run/main_scene` on this
branch only — revert to `scenes/ui/main_menu.tscn` to go back).

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

## Script changes needed: none

Zero changes to autoloads, AI, units, world, or UI scripts. All spike code
is new files under `scripts/three_d/` plus `scenes/main_3d.tscn`; the only
edit to an existing file is `run/main_scene` in `project.godot`.

## Known gaps (deliberate spike scope)

- Player mouse input (selection/orders) still feeds the hidden 2D scene;
  mouse → ground picking for real 3D interaction is a Phase 1 task.
- Screen shake / view slide / reduced-motion handling not ported to the rig.
- Effects (popups, particles, weather visuals) don't render in 3D.
- Terrain is a single flat plane; surface and underground coexist at
  y = 0 as in 2D (Tab separates them).

## Go / no-go checklist

- [ ] Camera pan/zoom/Tab feels tight (no seasickness, no dead zones). — *pending playtest*
- [ ] The 2D tile data reads clearly from an angled view. — *pending playtest*
- [ ] Sim still runs at 60fps+ with the 3D viewport open. — *pending playtest (watch the 0.2 s terrain rebuild hitch under lava/cave-in bursts)*
- [x] No changes were needed in any autoload or AI script to make the camera work.
