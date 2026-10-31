# Phase 1 progress — 2.5D port

Working log for [phase-1-25d-port.md](phase-1-25d-port.md). Updated per
milestone; open items carried forward.

## Milestones

| Milestone | Status | Notes |
|---|---|---|
| M1 — Terrain renders from `_cells`; camera pans/zooms/Tabs | **Done** | Chunked terrain (21×8-cell chunks, 12 total, signal-dirty + 0.15 s throttle, layer-aware rebuild on Tab); camera rig (55° pitch, dolly 3–25, WASD/arrows + edge pan, follows `PlayerController.view_mode_changed`). Renderer switched to `forward_plus` (desktop) with `gl_compatibility` kept for `.mobile`/`.web` overrides. |
| M2 — Units + structures visible as billboards | **Done** | `EntityProxies3D` reconciles the unit/structure groups every 0.2 s (instance-id keyed, `died`/`destroyed`/group-leaving culls). Units: `Sprite3D` FIXED_Y billboards (texture logic mirrors `unit_rendering._get_unit_texture`), blob shadows, HP bars, flight altitude, undead tint, per-frame position/fog/layer sync. Structures: box stand-ins (building/tower/lantern/wall/trap), `mine_entry.png` billboard, ladder rails; construction alpha + fog mirrored at reconcile. |
| M3 — Full control scheme functional | **Done** | Mouse→ground end to end: `player_commands._screen_to_world()` unprojects through the rig camera (zoom-to-cursor safe, 2D fallback standalone); drag-box select projects units through the rig camera (`player_selection.gd`, plan 02 / PR #7); MultiMesh selection/hover rings (`selection_rings_3d.gd`); 3D order markers + red attack telegraphs (`order_marker_3d.gd` / `telegraph_3d.gd`); placement preview `build_ghost_3d.gd` with gold `range_disc_3d.gd`. |
| M4 — Fog + weather + effects re-created | **Done** | `fog_3d.gd` (opaque unexplored void, remembered shadow, lantern OmniLights); `effects_3d.gd` (storm snow, eruption cinders/ash, dust motes, cave-in bursts); `event_proxies_3d.gd` (meteor streaks + impact rings, burning-ground scorch decals, lava-rise shimmer, cave-in warning zone); billboarded damage popups (`damage_popup_3d.gd`); weather moods + eruption sun pulse (`lighting_3d.gd`); pooled projectile tracers (`projectile_proxies_3d.gd`). |
| M5 — Tests green, exports, release | **Partially done** | Suite green headless via `tools/run_checks.sh` (budget gate + full GUT: 72 scripts / 779 tests); 13 `test_3d_*` scripts (12 on `feat/3d-conversion` + box-select from plan 02). Exports configured for Web/macOS/Windows/Linux (`export_presets.cfg`, `tools/export_all.sh`); pre-push checks wired (plan 03 / PR #7). Pending: human playtest; first release off this branch (releases still publish from `main` pushes). |

## Architecture decisions (locked)

- **Sim mount:** the shell instances `scenes/main.tscn` as a direct child of
  the window root at runtime → `/root/Main` resolves exactly as shipped
  (86 references / 57 files). All 2D CanvasItem layers are hidden; the HUD
  CanvasLayer stays visible and overlays the 3D viewport.
- **Ground truth:** `GridWorld._cells` (+ unit/structure node state) is
  read by the presentation layer only; nothing 3D writes back (hard rule 3).
- **Fog/layer mirroring:** the sim already flips `unit.visible` per fog and
  tracks `is_underground`; proxies mirror those instead of re-deriving them.
- **Sim edits stayed presentation-shaped:** all 3D code is new files under
  `scripts/three_d/` + `scenes/world_3d.tscn`, but sim-side edits did land
  after M2 — the surface-band generalization (`SURFACE_ROWS` /
  `is_surface_row()`, wall column seals), the fog revision feed, and one-way
  presentation branches (popups, order markers, rig-camera screen→world;
  `Presentation3D.shell()` null in 2D). The verified per-file list is in
  [phase-0-findings.md](phase-0-findings.md).

## Post-review fixes (M2 follow-up)

- **Scene flow:** the shell no longer hijacks `current_scene` (Play Again
  reloaded plain 2D `main.tscn` and leaked the shell; quit-to-menu leaked
  the sim). The shell stays `current_scene` and frees the root-mounted sim
  in `_exit_tree`; main-menu Play now loads `main_3d.tscn` and
  `run/main_scene` is back to the menu. New existing-file edit:
  `main_menu.gd` (one line).
- **Structure fog honesty:** enemy towers/walls/lanterns/mine entries no
  longer render through fog — proxies check `fog_state_at` themselves (the
  sim only flips `.visible` on buildings/traps); remembered cells dim like
  `building.gd`'s gray modulate.
- **Terrain convergence:** a 0.5 s full sweep covers the signal-less
  changes — fog movement, cave-in restores, ore respawns, depletion tint.
- Minor: HP bar drains from a fixed left edge; edge pan ignores the cursor
  over interactive HUD controls.

## Known gaps carried to M3/M4 — all closed

- Mouse input: rig-camera picking end to end (`player_commands._screen_to_world`,
  `player_selection` drag-box via rig projection — plan 02 / PR #7). — **Done (M3)**
- Screen shake / view slide / reduced-motion: rig shake landed (`main_3d.gd`
  `add_shake`, reduced-motion aware); the 0.25s Tab tween and zoom-to-cursor
  glide cover view motion. — **Done**
- 3D effects: full layer — `effects_3d.gd`, `event_proxies_3d.gd`,
  `damage_popup_3d.gd`, `order_marker_3d.gd`, `projectile_proxies_3d.gd`,
  `telegraph_3d.gd` (see M4). — **Done (M4)**
- Terrain lava / fog: lava is an emissive glow pass with a ~0.6s heartbeat
  (`terrain_3d.gd`); fog is `fog_3d.gd` shader quads, not per-vertex tint. — **Done**
- Structure stand-ins: Phase 2 replaced them with imported GLBs
  (`model_manifest.json` + `structure_model_loader.gd`; see
  [phase-2-progress.md](phase-2-progress.md)). — **Done (Phase 2)**
