# Plan 12 — Wider map and authored surface regions

Status: Done (2026-10-31, branch kimi-code-plans)
Size: M
Depends on: 11

## Mission

Expand the battlefield from 81 to **101 columns** (`x=-50…50`) and make the added space read as an authored world rather than an empty strip. Move bases to `x=±40` and both mine entrances to `(±20,-5)`, preserving the 10 surface rows (`y=-9…0`), underground depth, central wall, and existing models.

Use the existing `MapDefinition` resource for layout markers and new road/region metadata. Reuse the already imported Quaternius/generated props; no new package, asset pack, `CellType`, collision rule, or 3D-to-simulation write is required.

## Explicit decisions and consequences

- `Constants.GRID_X_MIN/MAX` remains the static grid-bounds source used by simulation, minimap, weather, AI, and 3D. `MapDefinition` remains the base/mine marker source and gains optional presentation metadata; grid bounds are not moved into per-match resources in this phase.
- Update both `map_definition.gd` defaults and `maps/default.tres`: buildings `(-40,0)/(40,0)`, mines `(-20,-5)/(20,-5)`.
- Base-to-base and base-to-mine travel grow by 33%. Accept this pacing change; do not compensate with unit-speed/stat changes or silently rescale weather/economy rates.
- Widening underground rows changes ore layouts for a given old seed because generation consumes RNG per added column. Same-seed replay after the change must remain deterministic; no promise is made to preserve old ore positions.
- Preserve existing dune samples and unauthored prop candidates where practical. Roads intentionally remove some props, and authored regions intentionally constrain prop families.
- Roads are **visual compacted snow**, not a movement-speed system. They do not change collision, A*, unit orders, or fog rules. Legacy 2D receives a matching road tint.
- Keep phase-11 work intact. No commit/push unless requested.

## Implementation steps

1. **Widen the grid and make layout markers authoritative.**
   - Change `GRID_X_MIN/MAX` to `-50/50` in `scripts/autoload/constants.gd`; retain `SURFACE_ROWS=10`, `GRID_Y_MIN=0`, and `GRID_Y_MAX=21`.
   - Update base/mine cells in `scripts/resources/map_definition.gd` and `scripts/resources/maps/default.tres`. `scripts/world/main.gd` already applies markers before children initialize; keep bases as cell-corner origins and mines as cell centers.
   - In `scripts/world/grid_map_generation.gd`, replace the hardcoded `carve_shaft(-15/15)` calls with the mine columns read from `/root/Main.map_definition`, falling back to `MapDefinition.new()` for isolated scenes. Keep `MineEntry._ready()`'s authoritative recarve. Do not leave obsolete shafts at `±15`.
   - Reuse existing bounds-driven generation, A*, fog, weather, AI placement, minimap, camera clamps, and backdrop. Only change systems that expose a real fixed-width/base assumption.
   - Increase `Terrain3D.CHUNK_COLS` and matching `TerrainDetail3D.CHUNK_COLS` from 21 to **26**, keeping four horizontal terrain chunks instead of six at the wider bounds. Verify chunk tests and benchmark the result rather than assuming a performance win.

2. **Add authored road and region metadata.**
   - Extend `MapDefinition` with:
     - `surface_roads: Array[Rect2i]` and `is_road(cell)`.
     - `surface_regions: Array[Dictionary]` and first-match `region_at(cell)`, returning `{}` outside authored regions. Region dictionaries carry `id`, `recipe`, `rect`, and `density`; metadata defaults stay empty for isolated callers.
   - Populate `default.tres` with:
     - Front road `Rect2i(-50,0,101,1)`.
     - Player/enemy mine spurs `Rect2i(-20,-5,1,6)` and `Rect2i(20,-5,1,6)`.
     - `west_pinewood`: `Rect2i(-36,-9,8,7)`, recipe `trees`, density `1.25`.
     - `east_rockfield`: `Rect2i(29,-9,8,7)`, recipe `rocks`, density `1.15`.
   - Add compacted-snow and cold region tint tokens to `ArtStyle3D`; do not put rendering colors in the resource or make brown dirt roads in the snow biome.

3. **Render roads and regions without breaking fog or quality tiers.**
   - Pass the existing map resource from `main_3d.gd` into `Terrain3D.setup(grid, map_definition)` and onward to `TerrainDetail3D.setup()`. Use optional null arguments so isolated legacy callers still work.
   - In `Terrain3D._cell_color()`'s `SURFACE_GROUND` branch, apply subtle region tints and a stronger compacted-snow road tint before the existing hidden/remembered fog match. Hidden cells must remain exact `FOG_VOID_TINT`; remembered cells retain the current shadow lerp. Potato keeps these cheap color reads.
   - In `TerrainDetail3D`, reject road cells before scattering. Multiply existing density by the region density, and constrain region recipes to existing `TREE_KINDS`/`ROCK_KINDS` (and `LOW_KINDS` only if needed). Preserve existing salts, cluster noise, offsets, scales, rotations, structure clearances, fog visibility checks, and dune grounding outside authored metadata.
   - Add a matching compacted-snow tint to eligible surface cells in `grid_drawing.gd` for legacy 2D. Do not alter `CellType`, HP, ore, pathfinding, or simulation state for decoration.
   - Leave `HeightField3D` and the model manifest unchanged. Existing generated pines/boulders and curated dead trees/rocks are sufficient.

4. **Migrate gameplay/capture fixtures deliberately.**
   - Update `tests/test_surface_band.gd`: assert 101 columns, walkable `x=±50`, border walls at `±51`, and `101*SURFACE_ROWS` playable cells. Derive base-detour endpoints and underground shaft cells from `MapDefinition`; add an early generation assertion that only the two resource-defined shaft columns are initially carved. Keep the real centered-mine climb roundtrip at the new location.
   - Migrate affected fixtures in `test_fog_of_war.gd`, `test_unit_guards.gd`, and `test_tech_branches.gd`: use actual building/mine cells for base visibility, shaft lanterns, and underground spawns; move tower fixtures that now fall inside the `±40` base clearances; retain meaningful ore/vision/path assertions rather than weakening them.
   - Replace width-limited test scans in `test_grid_world.gd`, `test_dynamic_terrain.gd`, `test_unit_guards.gd`, and `test_factions.gd` with the shared bounds where the whole player half/map is intended. Update `test_3d_camera.gd` to derive the approximately 16.16-world-unit player-half contract. Keep existing minimap tests, now exercising the wider bounds automatically.
   - Update `tools/capture/capture_pilot.gd`'s underground lantern cell to the resource's player mine column. Keep stress teams on their own halves and spread across the expanded lanes.
   - Update direct width/base comments in `main_3d.gd`, `terrain_3d.gd`, and `player_camera.gd`; do not globally replace unrelated combat coordinates.

5. **Add focused metadata/render regressions and useful survey shots.**
   - Add `tests/test_map_definition.gd` for marker positions, road coverage at row 0 and both mine spurs, rejection above the spur, west/east recipes, empty unauthored regions, and validation that every authored rectangle lies within the playable surface.
   - Extend `tests/test_3d_terrain_art.gd` for distinct road/region/open-surface colors and unchanged fog behavior across quality tiers. Extend `tests/test_3d_scatter.gd` to prove roads have no props, western instances use only tree kinds, eastern instances only rock kinds, both regions contain instances on seed 7, unauthored cells retain legacy transforms/kinds, and a region rebuild leaves sim cell/A* snapshots unchanged. Keep existing same-seed, fog, clearance, Potato, and scatter-cost tests.
   - Extend backdrop coverage tests for the wider edges if necessary; preserve height-field, grounding, and deterministic rebuild coverage.
   - Add a `survey:X:Y:Z` capture pose: identical camera semantics to `custom`, but reveal-all for the shot and restore fog afterward. Register/document parsing in `capture_driver.gd`, cover it in `test_capture_driver.gd`, and include the survey pose in the fog-wait/restore path in `capture_pilot.gd`.

6. **Document and verify the delivered phase.**
   - Create `plans/12-wider-authored-world.md`, add it to `plans/README.md`, and update current grid/layout contracts in `AGENTS.md`, the 3D style guide, and capture README. Record actual results and mark Done only if checks pass.
   - Run focused tests first: map definition, surface band, grid world, fog of war, unit guards, tech branches, dynamic terrain, factions, 3D camera/terrain art/scatter/backdrop/minimap, and capture parsing. Then run `tools/run_checks.sh` and `git diff --check`.
   - Capture and inspect Standard/Fancy/Potato at 1920×1080: `start`, `zoomout`, `underground`, `dunes`, `storm`, `volcano`, `survey:-1120:-192:6` (west pinewood), `survey:1104:-192:6` (east rockfield), and `survey:0:-128:16` (road network). Check readable roads, prop-family composition, grounding, base/mine alignment, fog honesty, and quality fallbacks; iterate on actual visual defects.
   - Run the real 200-unit, 30-sim-second Standard BENCH. Compare `unit_sync`, `sim_fog_recompute`, `terrain_rebuild`, `terrain_scatter`, `fog_rebuild`, and sample counts against phase 11 (0.928/8.587/6.312/0.604/3.582 ms respectively). Script timings are regression evidence, not a 60-fps certification.

## Acceptance criteria

- The live map has 101 columns and 10 surface rows. Bases are at `±40`; mines and their only initial shafts are at `±20`, with unchanged underground depth and central wall.
- Units, AI, structures, weather, camera, minimap, and capture poses work at the new positions; same-seed maps and visual scatters rebuild deterministically.
- Roads and mine spurs are readable on every quality tier; the western pinewood and eastern rockfield use their intended existing prop families, remain fog-honest, and never change collision or simulation state.
- Focused/full checks pass, real captures at all quality tiers are inspected, and final performance/documentation report measured results.

## Verification (2026-10-31)

- Fresh Godot import passed. Focused tests passed for map metadata, resource-driven shafts, real miner climbing, base detours, fog, unit guards, research fixtures, dynamic terrain, factions, camera framing, terrain colors, prop regions, simulation integrity, minimap, backdrop, height fields, structures, AI placement, and capture parsing.
- `tools/run_checks.sh`: **PASS — 78 scripts, 840 tests, 11,695 assertions**. Model budget remains **8,903,080 embedded-texture bytes / 64 MB**. `git diff --check` also passes.
- Inspected Standard, Fancy, and Potato galleries in `build/captures/wider-{standard,fancy,potato}/` plus clear-weather region surveys in `build/captures/wider-clear-{standard,fancy,potato}/`. Roads and mine spurs are readable, the west uses tree props and the east rock props, relocated bases/mines and their ladders align, and Potato retains the color composition without decorative props. Survey forces terrain/fog rebuilds and restores reveal-all after each shot.
- Real Standard 200-unit, 30-sim-second BENCH (`build/captures/wider-bench.log`), with 1,930 `unit_sync` and `sim_fog_recompute` samples:

| Probe (average ms) | Phase 11 | Wider authored map |
| --- | ---: | ---: |
| `unit_sync` | 0.928 | 0.947 |
| `sim_fog_recompute` | 8.587 | 6.817 |
| `terrain_rebuild` | 6.312 | 6.067 (45 batches) |
| `terrain_scatter` | 0.604 | 0.582 (132 chunks) |
| `fog_rebuild` | 3.582 | 4.277 (only 2 samples) |
| `ring_hover_scan` | 0.092 | 0.079 (262 samples) |

These are script-time measurements, not a 60-fps certification. The two-sample fog result is not a robust comparison. Existing fog-diff telemetry, GUT/deprecation, and shutdown ObjectDB warnings remain; standard checks exit successfully.
