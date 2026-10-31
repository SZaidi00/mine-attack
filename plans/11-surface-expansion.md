# Plan 11 — Expanded surface battlefield

Status: Done (2026-10-31, branch kimi-code-plans)
Size: M
Depends on: 10

## Scope and decisions

Expand the walkable surface from **6 to 10 rows**: `SURFACE_TOP = -9`, with row 0 retained as the front lane and underground remaining `y >= 1`. The surface grows by 324 cells (67%), while total tracked grid/fog cells grow by about 15%. Ten rows adds meaningful maneuvering space without the doubled presentation/fog workload and lower unit/map readability of 12 rows.

Keep these behaviors explicit:
- Grid width (`x ∈ [-40, 40]`), underground depth (`y ∈ [1, 21]`), base positions/footprints, and all model/animation work remain unchanged.
- At the user's request, move both mine entrances from the front edge to centered cells on row `-5`, preserving their shaft columns and underground endpoints. Introduce `MapDefinition` plus `scripts/resources/maps/default.tres` as the source of truth for base/mine layout markers before applying this placement change; `scripts/world/main.gd` applies them before the children initialize. The imported/procedural headframes use the same cell center as the ladder.
- Bases still seal their five-row footprints and leave row 0 open. With the larger band, paths may go **above a base or in front of it**; do not artificially enlarge the bases or force the old row-0-only detour.
- A placed wall still seals its whole column through the expanded surface and dug cells below. Extra lanes do not bypass that wall column.
- Keep total eruption meteor count/rate unchanged for this phase; meteor targets already span the full dynamic band. Per-area eruption pressure therefore decreases rather than silently doubling damage.
- Do not expand underground progression in this phase.
- Leave the phase-10 skeletal assets and all other existing work intact. No commit/push unless requested.

## Implementation steps

1. **Expand the shared surface bounds.**
   - Change `Constants.SURFACE_ROWS` in `scripts/autoload/constants.gd` from 6 to 10.
   - Reuse the existing derived `GridWorld.SURFACE_TOP`, generation, A* region, vision/memory arrays, structure placement, wall sealing, fog projection, height field, terrain chunks, prop scatter, backdrop, and minimap transforms; only modify those systems if focused tests expose a real fixed-row assumption.
   - Preserve the dedicated map RNG and existing seeded underground layout: surface generation consumes no random values.

2. **Center gameplay and capture framing from the band.**
   - Derive `PlayerController._last_surface_cam_pos` using the existing band-center formula in `scripts/controllers/player_camera.gd`; align the authored `Camera2D` in `scenes/main.tscn` to the resulting 10-row center, world Y **-128** (3D Z **-1.28**).
   - Keep the existing FOV, dolly limits, pitches, and 3D `_clamp_focus()` unless actual framing tests/captures demonstrate a crop. The shell will inherit the corrected bookmark.
   - In `tools/capture/capture_pilot.gd`, replace the unused fixed surface-camera constant and hardcoded surface/dunes/weather `z=-1.5` with the computed band-center focus. Preserve `zoomout` as the whole-board overview. Update custom-pose examples in `capture_driver.gd` and `tools/capture/README.md` to the new surface center.

3. **Cover the added lanes with weather and scouting.**
   - In `scripts/world/grid_ambience.gd`, anchor ambient/storm snow emitter Y positions and visibility rectangles to `SURFACE_TOP`, rather than the fixed `y=-300`; retain full horizontal coverage and the underground dust behavior.
   - In `scripts/units/unit_pigeon.gd`, sample enemy patrol Y targets across the expanded surface band instead of only `[-24,24]`; keep tower/base home-return behavior unchanged.
   - Verify existing meteor targeting, storm exposure, lava/cave-in constraints, and 3D camera-local weather without scaling damage or adding new hazards.

4. **Strengthen boundary, movement, determinism, and presentation tests.**
   - Update `tests/test_surface_band.gd` to pin 10 rows/`SURFACE_TOP=-9`, exact surface-cell generation, and the unchanged row-0/underground boundary. Replace the mandatory row-0 base-detour expectation with destination plus footprint-avoidance assertions, and explicitly exercise the new above-base route.
   - Exercise actual unit movement to `SURFACE_TOP`, steering rejection above it, top-row tower/wall/lantern placement and (with Guerrilla enabled) trap placement, local lantern vision at both band extremes, full-column wall seals, and crawler inability to cross the surface. Reuse existing helpers and clean up structures between tests.
   - Verify `MapDefinition` applies the base/mine markers before initialization, both mine entrances and ladders use exact cell centers on row `-5`, their underground endpoints stay fixed, and a real miner completes a climb-down/climb-up round trip. Check centered imported/procedural headframes, terrain clearances, AI placement, and waypoint behavior.
   - Extend `tests/test_map_seed.gd` to compare complete cell type/layout data (not just ore counts) on repeated pinned seeds, confirming that expansion preserves deterministic generation.
   - Add focused regression coverage in existing tests for snow emitters above the expanded band, pigeon patrol targets within its full Y range, top-row storm exposure with underground immunity, and meteor target bounds. Keep total meteor-rate tests unchanged.
   - In `tests/test_3d_camera.gd`, derive the pan-clamp expectation from `SURFACE_TOP`; assert the shell's default bookmark is the band center and both surface band edges project within the default gameplay viewport. Keep the 45-degree FOV and existing dolly/unit-scale contracts.
   - In `tests/test_3d_scatter.gd`, normalize front/rear prop density by `SURFACE_ROWS - 2`, not the old four rear rows. Existing minimap/fog/height/backdrop tests should remain parameterized; extend only if needed to assert the new top edge.
   - Spread capture stress units across `maxi(1, SURFACE_ROWS - 2)` rows while retaining the two excluded extreme lanes, so the benchmark measures the expanded board.

5. **Document and verify the delivered phase.**
   - Create this plan, add it to `plans/README.md`, and update current six-row contracts in `AGENTS.md` and `roadmap/3d-rework/README.md`. Historical plans remain historical records. Record actual verification results and mark this plan Done only if checks pass.
   - Run focused GUT scripts first (`test_surface_band`, `test_map_seed`, `test_pigeon`, `test_weather`, `test_volcano`, `test_3d_camera`, `test_3d_scatter`, `test_minimap`, `test_3d_fog`, `test_3d_backdrop`, `test_capture_driver`), then `tools/run_checks.sh` and `git diff --check`.
   - Capture and inspect `start`, `surface`, `zoomout`, `underground`, `dunes`, `storm`, and `volcano` at 1920×1080 using the real capture scene, first Standard and then Fancy/Potato. Check both new outer lanes, base/mine placement, terrain/backdrop continuity, fog, unit readability, minimap, and Tab return framing. Iterate on actual defects rather than relying only on projection math.
   - Repeat the real 200-unit, 30-sim-second Standard BENCH with units distributed across the expanded band; report `unit_sync`, `sim_fog_recompute`, `terrain_rebuild`, `terrain_scatter`, and `fog_rebuild` against the phase-10 baseline. Script timings are a regression signal, not a 60-fps certification.

## Acceptance criteria

- The live match has 10 playable surface rows (`y=-9…0`), with unchanged width, underground, bases, and deterministic seed behavior. `MapDefinition` centers both mine entrances on row `-5`; their shaft columns and underground endpoints stay unchanged, and real miners can climb down and back up.
- Real units can move and fight through the new top lanes; all surface structures place correctly at the new boundary, and crawler/wall/base-obstacle rules still hold.
- Default 2D/3D framing, minimap navigation, fog, weather, and deterministic captures cover the expanded battlefield without regressions at any quality tier.
- Focused and full standard repo checks pass, visual galleries are inspected, and final performance/documentation reflect measured results.

## Verification (2026-10-31)

- Focused GUT coverage passed for surface bounds, movement and combat, structure placement, full-grid seed replay, weather and meteor targeting, scouting, camera projection, fog, minimap, backdrop, scatter, centered-mine climbing, AI placement, waypoints, imported headframes, and capture parsing.
- `tools/run_checks.sh`: **PASS — 77 scripts, 829 tests, 9,285 assertions**. Model budget: **8,903,080 embedded-texture bytes / 64 MB**. `git diff --check` and manifest JSON validation also pass.
- Inspected seven 1920×1080 poses (`start`, `surface`, `zoomout`, `underground`, `dunes`, `storm`, `volcano`) on each quality tier in `build/captures/expanded-centered-{standard,fancy,potato}/`. The expanded terrain, fog, weather, centered headframes, aligned ladders, and quality fallbacks render correctly.
- Real Standard 200-unit, 30-sim-second BENCH (`build/captures/expanded-bench.log`), with 1,800 `unit_sync` and `sim_fog_recompute` samples:

| Probe (average ms) | Phase 10 baseline | Expanded map |
| --- | ---: | ---: |
| `unit_sync` | 1.167 | 0.928 |
| `sim_fog_recompute` | 7.899 | 8.587 |
| `terrain_rebuild` | 3.348 | 6.312 (45 batches) |
| `terrain_scatter` | 0.607 | 0.604 (143 chunks) |
| `fog_rebuild` | 2.576 | 3.582 (only 2 samples) |
| `ring_hover_scan` | 0.093 | 0.092 (439 samples) |

These are script-time measurements, not a 60-fps certification. The two-sample fog result is not a robust performance comparison. Existing fog-diff telemetry, GUT/deprecation, and shutdown ObjectDB warnings remain; the standard checks exit successfully.
