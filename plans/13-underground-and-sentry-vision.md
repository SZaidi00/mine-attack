# Plan 13 — Underground mine visual slice and sentry fog vision

Status: Done (2026-10-31, branch kimi-code-plans)
Size: M
Depends on: 12

## Mission

Make the underground read as an authored mine instead of a dark, flat cell mosaic, while preserving the current 2D-plane simulation. In parallel, restore built sentry towers as fog-of-war vision sources so they lift surface fog within their dedicated vision radius.

This phase has two independent deliverables that should be verified separately:

1. **Sentry vision:** built player and enemy towers reveal surface fog using `Constants.TOWER_VISION` (currently 10 cells), not tower attack range (8 cells).
2. **Underground presentation:** excavated cells gain readable floors, cold depth-strata variation, sparse mine framing/rubble, and restrained mining dust feedback. All changes are sim → render only and remain fog-honest.

## Explicit decisions and consequences

- **Do not convert underground to continuous vertical 3D.** Keep seven depth layers, the flat X/Y mine plane, A*, unit navigation, lava, fog, and camera behavior unchanged. `Terrain3D.world_height_at()` intentionally remains flat underground.
- A mined-out cell is represented by absence from `GridWorld._cells`; never recreate a `Cell` or mutate A* for presentation. Underground floor meshes are drawn only for in-bounds, underground, missing cells.
- Tower reveal uses `tower.vision_radius` and `GridWorld.VISION_LAYER_SURFACE`. Under-construction towers reveal nothing; destruction removes their source on the next fog update. Snowstorm scaling uses the existing global `WeatherManager.get_vision_multiplier()` behavior that towers had before removal; Surface War/Sentry Network still modify attack range only, not fog radius.
- Enemy tower vision affects enemy fog and therefore AI belief input. That is the intended symmetrical behavior, not a rendering-only player cheat.
- Decorative mine supports and rubble have **no collision, support-collapse mechanic, resource meaning, or AI meaning**. Tunnel centers stay clear enough for unit silhouettes.
- Use the already licensed local Quaternius Nature Standard staging assets for a tiny curated pebble set. Do not add plants, mushrooms, roads, loot, or another external package.
- Preserve the luminance hierarchy: dark cold rock/floors, warm practical lantern/lava light, units brightest. No per-cell lights, volumetric fog, bright emissive rubble, or daylight-style brightening; the underground ambient may be lifted only enough for visible strata and floors to read at RTS zoom while hidden fog remains opaque.
- Potato keeps floors, depth colors, fog, and lava, but skips pebbles/supports and mining dust. Standard/Fancy use the same composition, with existing particle/detail multipliers.
- No balance changes, grid-depth changes, tower stat changes, new trainable/placeable content, commit, or push unless separately requested.

## Current evidence

- Commit `e1d83fc` (“fix sentry”) removed built towers from `GridFogOfWar._get_vision_sources()`. `tower.gd` still carries `vision_radius`, the build UI still advertises tower vision, and the current test explicitly asserts that a built tower must not reveal fog.
- `Terrain3D._rebuild_chunk()` skips missing cells (`scripts/three_d/terrain_3d.gd:345-353`). Mining erases cells from `_cells`, so excavated tunnels currently have no floor mesh.
- `TerrainDetail3D` only adds ore crystals and lava embers underground; there are no floor details, supports, or rubble families.
- `Effects3D` has pooled dust bursts for cave-ins but no ordinary mining-destruction feedback.

## Implementation steps

### 1. Restore built sentry towers as fog sources

1. In `scripts/world/grid_fog_of_war.gd`, extend `_get_vision_sources(team)` after the lantern loop:
   - Iterate `grid.get_tree().get_nodes_in_group("towers")`.
   - Require `tower.team == team` and `tower.is_built()`.
   - Append `[grid.world_to_grid(tower.global_position), maxi(1, roundi(tower.vision_radius * WeatherManager.get_vision_multiplier())), GridWorld.VISION_LAYER_SURFACE]`.
   - Keep building and lantern behavior unchanged.
2. Update the stale comments in `grid_fog_of_war.gd` and the tower class header in `scripts/world/tower.gd` to state that built towers are surface-only vision sources.
3. Do not use `attack_range`; do not apply Surface War/Sentry Network to vision; do not reveal underground cells.
4. Repair coverage:
   - `tests/test_structures.gd`: while under construction, no reveal; once built, cells at 9 and 10 cells are visible and an 11th cell outside all other sources remains hidden. Remove the test’s `set_reveal_all()` from the firing portion so tower vision proves the target is shootable.
   - `tests/test_fog_of_war.gd`: built player tower contributes exactly `[tower cell, Constants.TOWER_VISION, VISION_LAYER_SURFACE]` in clear weather; player reveal does not appear in enemy fog; a built enemy tower reveals enemy fog without revealing player fog; a top-band surface row is revealed while the underground cell below remains hidden; removal stops live reveal with normal memory behavior.
   - `tests/test_weather.gd`: storm tower radius equals `maxi(1, roundi(Constants.TOWER_VISION * Constants.SNOWSTORM_VISION_MULT))` and returns to base after the storm.
   - `tests/test_tech_branches.gd`: Surface War/Sentry Network change `attack_range` while the fog-source radius remains `TOWER_VISION`.
   - `tests/test_3d_fog.gd`: place/finish a player tower, refresh `Fog3D`, and assert a previously hidden surface cell in radius becomes clear while the underground cell below remains opaque.

### 2. Curate three tiny underground pebbles from the existing local kit

Use the already present, `.gdignore`d Quaternius Nature Standard staging sources and the established importer contract:

```bash
python3 tools/import_kit_props.py --source build/asset_staging/nature_standard/glTF \
  --prop Pebble_Round_1.gltf=pack_pebble_round_1=0.12 \
  --prop Pebble_Round_3.gltf=pack_pebble_round_3=0.12 \
  --prop Pebble_Square_2.gltf=pack_pebble_square_2=0.12
python3 tools/import_kit_props.py --validate-only
python3 tools/resize_glb_textures.py --max=512 --only=pack_pebble_
```

- Register the three generated GLBs in `frost_mines_assets/models/model_manifest.json` using the importer’s actual footprint/height/triangle report and the existing 6000-tri prop gate.
- Update `frost_mines_assets/models/packs/SOURCES.md` with source filenames, source/final SHA-256 values, target height, license reference, and a note that these are underground rubble, not surface road/path pieces.
- Run `tools/check_model_budgets.sh`; record the new embedded-texture total. Current baseline is 8,903,080 bytes under the 64 MB budget.
- Do not weaken the manifest/budget gate. If a selected pebble is visually unreadable or has unsuitable geometry, choose another existing pebble and document the substitution.

### 3. Give excavated cells floors and restrained strata variation

1. In `scripts/three_d/terrain_3d.gd`, handle a missing cell before the existing `continue`:
   - Only when `_underground_view`, `pos.x`/`pos.y` are in the real grid bounds, and `pos.y > GridWorld.Y_MIN`, draw a presentation-only floor quad at the existing flat underground height.
   - Use a private predicate such as `_is_excavated_floor(pos)` so tests can distinguish genuine tunnels from missing data outside the underground area.
   - Apply the same visible/remembered/hidden fog tint path as normal cells; hidden floors must remain covered by the opaque fog overlay.
2. Add three cold mine-floor tokens to `ArtStyle3D` (shallow/mid/deep) derived from the existing seven-layer mapping `(pos.y - 1) / 3 + 1`. Blend with the established dirt/rock/coal palette; add only a small deterministic `ArtStyle3D.cell_hash()` variation so seeded maps remain stable.
3. Add subtle deterministic seam/crack quads no higher than `0.002` world units. Keep lava glow at its existing `0.004` lift and the fog overlay at `0.06`; avoid Z-fighting with either.
4. Leave `_corner_heights()` flat underground, leave lava/magma emissive behavior unchanged, and never draw a floor for a missing surface or out-of-bounds cell.
5. Extend `tests/test_3d_terrain_art.gd` or add `tests/test_3d_underground_art.gd` to cover:
   - Initial mine shafts contain floor quads where cells are absent.
   - Floor color changes by depth band and deterministic cell hash, but is distinct from dirt, solid rock, and void.
   - Visible/remembered/hidden fog tints still apply to floors.
   - Rebuilding underground chunks leaves `_cells` and A* solid-state snapshots unchanged.
   - The same pinned map seed yields identical floor colors and seam decisions after forced rebuilds.

### 4. Add fog-honest underground supports and rubble in `TerrainDetail3D`

Keep this in the existing `TerrainDetail3D` class so the Phase 1 child-cast contract remains intact.

1. Add a separate `underground_log: Dictionary` and, if useful, `UNDERGROUND_PROP_KEYS` containing only the three pebble keys. Do not mix these instances into `scatter_log`, which existing surface-region tests interpret as surface props.
2. For visible underground cells only:
   - Existing ORE keeps its crystals; FRESH_ORE joins the crystal treatment.
   - LAVA keeps its low-priority embers; MAGMA_ROCK/SOLID_ROCK may carry very sparse dark pebble rubble.
   - Depleted ore may gain a small pebble/rubble accent, but rich ore remains dominated by readable crystals.
3. Add deterministic timber mine framing:
   - Only on existing visible DIRT cells directly adjacent to an excavated floor.
   - Use a low probability and distinct hash salts; avoid every tunnel cell becoming a support.
   - Build each support as shared unit-box MultiMesh posts plus a lintel, using existing wood/steel palette tokens. Keep it below/around unit silhouette height and visually decorative rather than structural.
   - Skip supports in tunnel-center cells (which have no remaining cell), near ore crystals when they would obscure readability, and anywhere they imply an alternate path or collision.
4. Use pebble MultiMeshes near cell edges, not unit-center spawn points. Keep target pebble heights around the imported 0.12 world-unit band so they read as debris, not blockers.
5. Preserve `detail_enabled()`/Potato gating, `particle_mult()` behavior, fog-visibility exclusion, chunk-local MultiMeshes, and shared meshes/materials. Instrument the new placement section separately in Probe3D (for example `underground_detail`) rather than hiding it inside surface scatter.
6. Add `tests/test_3d_underground_detail.gd`:
   - Same seed produces identical transforms/logs across forced rebuilds; different seeds produce different boards.
   - Every logged support/pebble is on a visible underground cell and outside missing floor centers.
   - Supports require adjacency to an excavated cell; pebbles use only the curated pebble keys.
   - No underground decoration appears on hidden/remembered cells, surface rows, roads, or Potato.
   - Detail rebuilds do not mutate sim cells/A* and keep supports/rubble inside their cell bounds.
   - Extend `tests/test_3d_props.gd` for the shorter 0.12 pebble height band and manifest loadability.

### 5. Add restrained mining dust feedback

1. Add a sim-side `cell_mined(grid_pos: Vector2i)` signal to `GridWorld` and emit it only when ordinary mining erases a non-wall cell in `scripts/world/grid_mining.gd`; keep the existing generic `cell_destroyed` signal for current consumers and wall-breach behavior.
2. In `scripts/three_d/effects_3d.gd`, connect `cell_mined` alongside the cave-in signal:
   - Spawn only in underground view, only when the player fog state is visible, and only at `ArtStyle3D.detail_enabled()` quality or above.
   - Reuse the existing pooled dust bursts and particle multiplier; do not allocate a new emitter family.
   - Add a short global/chunk throttle so several miners finishing cells in one frame do not spam every pool slot.
   - Keep cave-in bursts and the emphasized first-breach treatment distinct.
3. Extend `tests/test_3d_effects.gd` to verify the handler ignores surface cells, hidden cells, and Potato, and emits/reuses pool bursts for visible underground mining.

### 6. Update documentation, captures, and performance evidence

- Create `plans/13-underground-and-sentry-vision.md` from this plan; add it to `plans/README.md`.
- Update `AGENTS.md` and `roadmap/3d-conversion/style-guide.md`: tower vision is restored; underground floors/supports/rubble are presentation-only; pebbles are curated underground rubble; Potato/Standard/Fancy behavior and the no-vertical-mine constraint are recorded.
- Capture at 1920×1080 and inspect all three tiers. Include at least:
  - `underground`
  - `units_underground`
  - `unit_actions_underground`
  - `breach`
  - `survey:-640:96:6` (player shaft/shallow tunnels)
  - `survey:-640:288:8` (deep tunnel composition)
- Inspect actual pixels for floor continuity, depth-band readability, lantern warmth, support scale, unit readability, fog honesty, lava dominance, and Potato fallbacks. Iterate on visual defects rather than declaring success from passing tests.
- Run the focused tests listed above, the existing 3D scatter/fog/terrain tests, model validation/budget gate, full `tools/run_checks.sh`, and `git diff --check`.
- Run the real 200-unit/30-sim-second Standard BENCH plus an underground-active comparison such as `STRESS_UNITS=100 BENCH=30 SHOTS="1:underground"`. Record sample counts and averages for `unit_sync`, `sim_fog_recompute`, `terrain_rebuild`, `terrain_scatter`, `underground_detail` (if added), `fog_rebuild`, and `ring_hover_scan` against Plan 12 (`0.947`, `6.817`, `6.067`, `0.582`, new, `4.277`, `0.079` ms respectively). Treat these as script-time regression evidence, not FPS certification.

## Acceptance criteria

- Built towers lift fog symmetrically for their own team within `Constants.TOWER_VISION`, including upper surface-band rows; construction, destruction, team isolation, storm scaling, attack-range research separation, and underground exclusion are covered by tests.
- 3D fog follows the restored sim state without renderer-specific duplicate vision logic.
- Excavated underground cells have stable, fog-tinted floor geometry with subtle depth variation; tunnels no longer read as holes in the board.
- Underground supports/rubble are deterministic per seed, sparse, visible-only, quality-aware, non-colliding, and never change sim cells/A*.
- New pebble GLBs are imported, normalized, licensed, manifest-registered, and pass the budget gate.
- Mining destruction gives readable but restrained dust feedback without compromising cave-in or first-breach emphasis.
- Focused/full tests pass, actual captures at all tiers are inspected, performance is measured and reported, and documentation matches shipped behavior.

## Verification (2026-10-31)

- Focused GUT scripts all passed: tower vision (`test_structures` 25/25, `test_fog_of_war` 28/28, `test_weather` 15/15, `test_tech_branches` 34/34, `test_3d_fog` 11/11), pebble props (`test_3d_props` 4/4), underground art/detail (`test_3d_underground_art` 7/7, `test_3d_underground_detail` 8/8), effects (`test_3d_effects` 16/16), terrain/scatter (`test_3d_terrain_art` 7/7, `test_3d_scatter` 12/12), lighting (`test_3d_lighting` 9/9), and sim integrity (`test_grid_world` 6/6, `test_dynamic_terrain` 12/12).
- `tools/run_checks.sh`: **PASS — 80 scripts, 867 tests, 12,009 assertions**. Model budget: **PASS — 9,740,104 embedded-texture bytes / 64 MB**. `git diff --check`: PASS.
- `python3 tools/import_kit_props.py --validate-only`: 10 static kit props validated; 5 skeletal rigs explicitly delegated to `tools/curate_skeletal_units.py --validate-only` (also passed).
- Final inspected galleries: `build/captures/plan13-final-{standard,fancy,potato}/` with `underground`, `units_underground`, `unit_actions_underground`, `breach`, and corrected surveys `survey:-640:96:6`, `survey:-640:288:8`. Standard/Fancy show readable revealed strata, warm lantern pools, supports/rubble, and unit readability; Potato keeps the color composition without decorative supports/rubble.
- Standard 200-unit / 30-sim-second BENCH (`build/captures/plan13-bench.log`): `unit_sync` 1.000 ms (1800 samples), `sim_fog_recompute` 7.299 ms, `terrain_rebuild` 5.346 ms (58 batches), `terrain_scatter` 0.521 ms (157 chunks), `fog_rebuild` 4.376 ms (2 samples — still not a robust comparison), `ring_hover_scan` 0.082 ms.
- Underground-active 200-unit BENCH (`build/captures/plan13-bench-underground.log`): `underground_detail` **0.255 ms** over 180 samples; `terrain_rebuild` 5.072 ms, `unit_sync` 0.347 ms, `sim_fog_recompute` 8.558 ms, `fog_rebuild` 2.949 ms (3 samples).
- These are script-time regression measurements, not FPS certification. Existing fog-diff overflow telemetry, model-origin recentering notices, and shutdown ObjectDB warnings remain; checks exit successfully.
