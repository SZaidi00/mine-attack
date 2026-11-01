# Plan 14 — Mode-specific world profiles (legacy 2D / expanded 3D)

Status: Done (2026-10-31, branch kimi-code-plans)
Size: M
Depends on: 13

## Mission

Preserve the user's preferred original **legacy 2D** experience while keeping the expanded authored world for **3D** only:

- `play_mode="2d"` → `scenes/main.tscn` loads the `main`-style legacy world: **81 columns**, a **single surface row**, bases at `x=±30`, mine entrances at `x=±15` on row 0, camera bookmark `(0,-150)`, and no Plan-12 road/region dressing.
- `play_mode="3d"` (default) → `scenes/main_3d.tscn` and the capture harness keep the current Plan-12/13 world: **101 columns × 10 surface rows**, bases at `±40`, centered mines at `(±20,-5)`, authored roads/regions, and the underground visual slice.
- Keep the existing main-menu/settings Play Mode option. Do not remove 2D or force it through the 3D shell.
- Do not change unit stats, economy, tower vision, underground visuals, or other balance/content rules in this phase.

## Context and evidence

- The Play Mode flow already forks scenes: `scripts/ui/main_menu.gd:763-780` loads `main_3d.tscn` for `"3d"` and `main.tscn` for `"2d"`. The 3D shell mounts that same `main.tscn` sim at `/root/Main`.
- `main` branch had `GRID_X_MIN=-40`, `GRID_X_MAX=40`, no multi-row `SURFACE_ROWS`, surface ground only at `y=0`, shafts at `x=±15`, building positions `(-960,0)/(960,0)`, mine positions `(±480,0)`, and camera `(0,-150)` (`git show main:scripts/autoload/constants.gd`, `git show main:scripts/world/grid_map_generation.gd`, `git show main:scenes/main.tscn`).
- The current code naturally degenerates to that legacy shape when `X_MIN=-40`, `X_MAX=40`, and `SURFACE_ROWS=1`: `SURFACE_TOP` becomes row 0, generation/fog/A*/minimap loops collapse to the single row, and the building footprint loop's `has_cell` guard becomes a no-op just like `main`.
- Current wide values live in `Constants.GRID_X_MIN/GRID_X_MAX/SURFACE_ROWS` and are mirrored as `GridWorld` consts (`scripts/world/grid_world.gd:86-97`). Only four values need to vary per profile: `X_MIN`, `X_MAX`, `SURFACE_ROWS`, and derived `SURFACE_TOP`; `Y_MIN`, `Y_MAX`, and `CELL_SIZE` stay unchanged.
- `scripts/world/main.gd:6-12` already runs before child initialization and is the correct injection point for per-match layout markers. `GridMapGeneration._layout()` already reads the resource-defined mine columns before carving shafts.
- The only compile-time consumer that would break when `GridWorld.SURFACE_TOP/SURFACE_ROWS` stop being `const` is `tools/capture/capture_pilot.gd:15`; all other runtime call sites can keep their existing syntax if the four fields become `static var`.

## Explicit decisions and consequences

- Keep one shared `scenes/main.tscn` and one shared `GridWorld` implementation. Select a `MapDefinition` world profile before `GridWorld` initializes; do not fork scenes or copy grid scripts.
- Convert `GridWorld.X_MIN`, `X_MAX`, `SURFACE_ROWS`, and `SURFACE_TOP` from `const` to `static var`, with current wide defaults. Add a single `GridWorld.apply_world_profile(definition: MapDefinition)` static API that assigns all four together and derives `SURFACE_TOP`. Document that these are per-match live values, re-applied on every sim `_enter_tree`; no individual field writes elsewhere.
- Keep `scripts/autoload/constants.gd` as the wide/default source. It remains useful for capture-wide assumptions, but the live grid bounds for the current match are the `GridWorld` statics after profile application.
- Add a launch-intent request to `GameManager`, defaulting to `"wide"` and intentionally **not** cleared by per-match `reset()`:
  - Main menu Play sets `"legacy"` when loading `main.tscn`, `"wide"` when loading `main_3d.tscn`.
  - Capture driver sets `"wide"` before loading the 3D shell.
  - Existing GUT tests therefore remain wide by default even on a developer machine whose persisted user setting is `"2d"`.
  - A dedicated legacy test can explicitly pin `"legacy"` and restore `"wide"` afterward.
- Extend `MapDefinition` with world-profile metadata: `grid_x_min`, `grid_x_max`, `surface_rows`, `mine_entries_centered`, and `camera_start`. Keep existing base/mine/road/region marker fields.
- Add `scripts/resources/maps/legacy.tres` with the exact `main`-branch layout:
  - `grid_x_min=-40`, `grid_x_max=40`, `surface_rows=1`.
  - Buildings `(-30,0)` and `(30,0)`.
  - Mines `(-15,0)` and `(15,0)`, `mine_entries_centered=false` (corner-origin like `main`).
  - `camera_start=(0,-150)`.
  - Empty `surface_roads` and `surface_regions`.
- Keep `scripts/resources/maps/default.tres` as the wide 3D resource with its current markers/roads/regions and add explicit matching profile fields.
- Same-seed determinism remains per profile. A legacy seed does not need to reproduce the ore layout of a wide seed because generation consumes a different column count; document this in `AGENTS.md`.
- This phase is presentation/layout scope only. It does not attempt to restore every historical `main`-branch behavior outside the world (for example, newer units/research/tower vision remain active in both modes).

## Implementation steps

1. **Finalize Plan 13 bookkeeping first.**
   - Mark `plans/13-underground-and-sentry-vision.md` Done using the already completed verification: full `tools/run_checks.sh` passed **80 scripts / 867 tests / 12,009 assertions**, model budget passed at **9,740,104 bytes / 64 MB**, and final captures/BENCH logs are in `build/captures/plan13-*`.
   - Keep that bookkeeping separate from the Plan 14 code changes.

2. **Make grid bounds live per match.**
   - In `scripts/world/grid_world.gd`, change `X_MIN`, `X_MAX`, `SURFACE_ROWS`, and `SURFACE_TOP` to `static var` initialized from the current wide `Constants` values. Keep `Y_MIN`, `Y_MAX`, and `CELL_SIZE` const.
   - Add `static func apply_world_profile(definition: MapDefinition = null) -> void` that validates/sanitizes profile bounds (non-empty X range, `surface_rows >= 1`), assigns all four fields together, and derives `SURFACE_TOP`.
   - Add a clear comment that these statics are match-scoped live values and must only be changed through this API.
   - In `scripts/controllers/player_controller.gd`, remove the eager bounds-dependent initializer for `_last_surface_cam_pos` (use a neutral default); `_camera_helper._init_view_positions()` already recomputes it from the authored camera position after profile application.

3. **Carry the profile in `MapDefinition` and select it before child setup.**
   - Extend `scripts/resources/map_definition.gd` with:
     - `grid_x_min: int = -50`
     - `grid_x_max: int = 50`
     - `surface_rows: int = 10`
     - `mine_entries_centered: bool = true`
     - `camera_start: Vector2 = Vector2(0, -128)`
   - Populate the same explicit values in `scripts/resources/maps/default.tres` while preserving its current roads/regions/markers.
   - Create `scripts/resources/maps/legacy.tres` exactly as specified above.
   - In `scripts/world/main.gd`:
     - Resolve the resource from `GameManager.world_profile_request`: `"legacy"` → `legacy.tres`, otherwise the exported/default wide resource.
     - Call `GridWorld.apply_world_profile(resolved_definition)` before any child `_ready`.
     - Apply `camera_start` to `/root/Main/Camera2D`.
     - Use `mine_entries_centered` when positioning both `MineEntry` nodes; keep building placement corner-origin.
   - Add the `GameManager.world_profile_request` launch-intent field and setter/validation (`"wide"` / `"legacy"`, default `"wide"`), explicitly preserved by `reset()`.

4. **Set the request at real entry points.**
   - In `scripts/ui/main_menu.gd:_on_play()`, set `GameManager.world_profile_request` to `"legacy"` for `"2d"` and `"wide"` for `"3d"` immediately before changing scene.
   - In `tools/capture/capture_driver.gd`, set `"wide"` before loading `main_3d.tscn` so capture and BENCH remain deterministic.
   - In `tools/capture/capture_pilot.gd`, replace the `SURFACE_CAM_POS` const with a runtime helper or instance value computed after profile setup (capture remains wide-only).
   - In `scripts/ui/minimap.gd`, replace `_COLS/_Y_TOP/_ROWS` consts and `Constants.GRID_*` reads with instance fields computed from the live `GridWorld` bounds in `_ready`; preserve drawing/input behavior exactly.
   - Update comments in `scripts/autoload/constants.gd`, `scripts/world/main.gd`, and play-mode docs to state that wide values are defaults and the live profile comes from `MapDefinition`.

5. **Add profile and legacy-mode coverage.**
   - Extend `tests/test_map_definition.gd`:
     - `default.tres` explicitly carries wide bounds, centered mines, and current camera start.
     - `legacy.tres` carries 81 columns, one surface row, corner-origin mines at `±15`, buildings at `±30`, camera `(0,-150)`, and empty roads/regions.
     - Validation rejects inverted/degenerate profile bounds.
   - Add `tests/test_world_profile.gd`:
     - `GridWorld.apply_world_profile(default.tres)` restores the wide statics and derives `SURFACE_TOP=-9`.
     - `GridWorld.apply_world_profile(legacy.tres)` sets `X_MIN=-40`, `X_MAX=40`, `SURFACE_ROWS=1`, `SURFACE_TOP=0`.
     - With `GameManager.world_profile_request="legacy"`, instantiate `scenes/main.tscn` and assert before teardown: only row `0` has surface cells, 81 surface cells exist, no playable cells at `y<0`, border walls at `x=±41`, buildings/mines/camera use legacy positions, and shafts are carved only at `x=±15`.
     - Restore `"wide"` and force a fresh wide sim once afterward so static state cannot leak to later tests.
   - Extend play-mode coverage (`tests/test_play_mode_setting.gd` or a focused new test) to assert Play sets the wide/legacy request alongside the scene path, without persisting or requiring a real scene switch.
   - Keep existing tests wide by default. Do not edit dozens of tests to request wide; the `GameManager` default should provide that.

6. **Update documentation and verify both modes.**
   - Add `plans/14-mode-specific-world-profiles.md` to `plans/README.md`.
   - Update `AGENTS.md` play-mode/map contracts: 3D is wide 101×10 with authored roads/regions and centered mines; 2D legacy is 81×1 with `main`-style markers/camera and no road/region dressing; same-seed ore layouts are only deterministic within one profile.
   - Update the style guide or MapDefinition notes if they currently imply the wide board applies to both modes.
   - Run focused tests: map definition, world profile, play mode, surface band, grid world, fog, minimap, camera, capture parsing, plus a representative 3D terrain/scatter test.
   - Run `tools/run_checks.sh` and `git diff --check`.
   - Manually smoke the two menu paths if feasible: 3D Play reaches the wide shell; 2D legacy Play reaches the single-row board with original base/mine spacing. Capture harness remains 3D-only.

## Acceptance criteria

- The existing Play Mode option remains intact.
- Legacy 2D Play creates a genuinely 81-column, one-surface-row world with `main`-branch base/mine/camera placement and no authored road/region tint; it does not merely hide the extra wide-map cells.
- 3D Play, capture, BENCH, and the default test suite continue to use the 101×10 authored world and Plan-13 underground slice.
- A persisted `"2d"` setting on a development machine does not silently flip the GUT suite to legacy; only explicit launch intent does.
- `GridWorld` bounds are applied atomically per match through one API, with no scene/script fork and no broad call-site refactor.
- Focused/full checks pass, docs match behavior, and `git diff --check` is clean.

## Verification

All checks run with `~/Downloads/Godot.app/Contents/MacOS/Godot` (Godot 4.7.1) on macOS, 2026-10-31.

Focused runs (each `-gtest=<file>` alone, no `-gdir`):

- `tests/test_world_profile.gd` — 8/8 passed, 2,029 asserts (new)
- `tests/test_map_definition.gd` — 6/6 passed, 153 asserts (extended)
- `tests/test_play_mode_setting.gd` — 11/11 passed, 21 asserts (extended)
- `tests/test_surface_band.gd` — 22/22 passed, 745 asserts
- `tests/test_grid_world.gd` — 6/6 passed, 45 asserts
- `tests/test_fog_of_war.gd` — 28/28 passed, 104 asserts
- `tests/test_minimap.gd` — 4/4 passed, 17 asserts
- `tests/test_3d_camera.gd` — 16/16 passed, 59 asserts
- `tests/test_capture_driver.gd` — 11/11 passed, 39 asserts
- `tests/test_3d_scatter.gd` — 12/12; `test_3d_fog.gd` — 11/11; `test_3d_underground_detail.gd` — 8/8; `test_3d_height_field.gd` — 7/7; `test_3d_backdrop.gd` — 3/3 (representative Plan-13 3D terrain/scatter/fog layer, all green)

Full repo checks: `tools/run_checks.sh` exited 0 — GLB budget gate passed and the headless GUT suite ran **81 scripts / 878 tests / 14,060 assertions, all passing** (Plan 13 ended at 80/867/12,009; Plan 14 adds one script and 11 tests). `git diff --check` is clean. The degenerate-profile test deliberately triggers two expected `push_error`s (asserted with `assert_push_error`); the exit-time "6 ObjectDB instances were leaked" warning pre-exists on unrelated single-file runs.

Manual smoke: not run (macOS dev machine, no capture harness session started); both Play paths are covered at the sim level instead — `test_world_profile.gd` boots the real `scenes/main.tscn` under explicit `"legacy"` and `"wide"` requests and asserts the full board shape (81 vs 101×10 cells, border walls, base/mine/camera placement, shaft columns), and the 3D shell tests keep passing with the sim mounted under the wide profile. Capture/BENCH pin `"wide"` in `capture_driver.gd` before loading the shell.
