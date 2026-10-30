# Plan 07 — Seeded surface prop scattering

Status: Not started
Size: M
Depends on: 06 (prop GLBs + manifest entries must exist)

## Mission
Dress the 6-row surface band with deterministic, seed-replaying,
fog-honest, clearance-aware prop scatter — the surface equivalent of the
underground's ore/lava visual variety.

## Context
- `scripts/three_d/terrain_detail_3d.gd` is the template. It renders per-chunk
  decorations (ore crystals, lava embers, snow drifts) as one
  `MultiMeshInstance3D` per decoration type per chunk, rebuilds right after
  its chunk via `rebuild_chunk(key, x_start, y_start, underground_view,
  snow_level, ground)`, pools chunk holders, shares materials, gates on
  `ArtStyle3D.detail_enabled()`/`particle_mult()`, places deterministically per
  cell via `ArtStyle3D.cell_hash(pos, salt)`, rides the dune field through
  `HeightField3D.height_at`, and skips cells by fog state (read the exact
  predicate in code and mirror it — do not guess).
- Chunks: `CHUNK_COLS × CHUNK_ROWS` = 21×8, cells outside
  `[GridWorld.SURFACE_TOP, ...]` skipped; surface cells are
  `GridWorld.CellType.SURFACE_GROUND` when `not underground_view`.
- Determinism contract: map generation is seeded from `GameManager.map_seed`
  (pinned seeds replay the same map; see `grid_map_generation.gd`). `cell_hash`
  alone is seed-independent, so mixing `map_seed` into the scatter salt is
  REQUIRED for "same seed → same board" (Play Again promise in
  `GameManager`).
- Clearances: `scripts/three_d/height_field.gd` stamps structure clearances
  (`CLEAR_RADIUS` ~2.0, `refresh_clearances()` over live structure groups)
  and bumps a `revision`; `Terrain3D.notify_structures_changed()` re-stamps.
  Scatter must not place props where structures stand — read how
  `height_at`/`refresh_clearances` represent clearance and reuse that query
  (or the structure-group check) rather than inventing a second source.
- Prop loading: plan 06 registers props in the manifest and proves
  `StructureModelLoader` can instantiate them. For MultiMesh scatter you need
  the prop's raw `Mesh` (the loader's wrapper or the imported scene's mesh) —
  read `structure_model_loader.gd` and pick the cleanest extraction; shared
  meshes + per-instance colors, exactly like `_make_multimesh`.

## Task
1. Read `scripts/three_d/terrain_detail_3d.gd`, `scripts/three_d/height_field.gd`,
   `scripts/three_d/terrain_3d.gd`, `scripts/three_d/art_style_3d.gd`,
   `scripts/three_d/structure_model_loader.gd`, and the manifest first.
2. Extend `TerrainDetail3D` with a surface-scatter pass (a sibling node is
   acceptable if the `extends MeshInstance3D` port-test constraint makes
   extension awkward — document the choice):
   - Only when `not underground_view`, cell type SURFACE_GROUND, same
     fog predicate as existing details.
   - Per-cell, deterministic: `ArtStyle3D.cell_hash(pos, salt + map_seed_mix)`
     decides prop kind (or none), sub-cell offset, rotation, and scale within
     bands you define. Density scales with quality tier (Potato: near-zero or
     none; Standard/Fancy: full).
   - Dune-grounded: `ground.height_at(x, z)` like the drifts path.
   - Clearance: skip cells occupied by or within clearance radius of any live
     structure (same groups `refresh_clearances` tracks); re-run the clearance
     filter on `notify_structures_changed()` — scatter rebuilds piggyback on
     the existing chunk-rebuild triggers, no new timers.
   - One MultiMeshInstance3D per prop kind per chunk (share meshes/materials;
     per-instance tint from the prop palette if desired).
3. Seed behavior test (new GUT file, e.g. `tests/test_3d_scatter.gd`):
   - Same pinned `GameManager.set_map_seed(n)` → identical transform lists
     across two rebuilds; different seed → different lists.
   - A wall/tower placed on a band cell → no prop instance within its clearance
     after `notify_structures_changed()`.
   - Fog: a cell with `fog_state_at == 2` (hidden) carries no props while a
     visible neighbor does (mirror the exact fog constants from
     `terrain_detail_3d.gd`).
4. Visual verification with the capture harness:
   `tools/capture/run_capture.sh /tmp/shots` — inspect `dunes.png` and
   `base.png` (surface poses): props sit on the ground, none float over dips,
   none intersect structures. Iterate until true.
5. Perf: `STRESS_UNITS=100 BENCH=30 SHOTS="" tools/capture/run_capture.sh /tmp/bench`
   — compare the terrain/section script-time averages against a run with
   scatter disabled (temporary env/flag is fine for the measurement); scatter
   overhead must be a small fraction of the terrain section, and instance
   counts must respect the 200-unit/60fps budget context. Record both numbers
   in the PR.

## Constraints
- Determinism is a hard requirement: never `randf()`/`randi()` directly in
  scatter code; only seeded hashes (house style: `cell_hash`, map RNG).
- Presentation-only: scatter reads the grid and structure groups; it never
  writes sim state, never affects walkability/pathfinding/sealing (purely
  decorative, visually smaller than a cell's playable read — keep props low).
- Fog honesty identical to existing details (no props on hidden cells).
- Potato tier must not regress: `ArtStyle3D.detail_enabled()` gate like the
  existing paths.

## Verification
```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_3d_scatter.gd -gexit
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
tools/check_model_budgets.sh
tools/capture/run_capture.sh /tmp/shots           # visual pass
STRESS_UNITS=100 BENCH=30 SHOTS="" tools/capture/run_capture.sh /tmp/bench
```

## Acceptance criteria
- [ ] Seeded determinism proven by GUT (same seed identical, diff seed differs)
- [ ] Clearance: no props under/inside structures, reactive to new construction
- [ ] Fog predicate matches existing details; hidden cells bare
- [ ] Capture shots show grounded, non-intersecting props at dunes/base poses
- [ ] BENCH numbers recorded, overhead small vs terrain section
- [ ] Full GUT suite green; budget gate green

## Out of scope
- Underground scatter (ore/embers already covered)
- Prop destruction/damage states
- Editor tooling or procedural prop generation (plan 06)
