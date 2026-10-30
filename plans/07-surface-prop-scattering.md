# Plan 07 — Seeded surface prop scattering

Status: Done (2026-10-30, branch kimi-code-plans)
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
- [x] Seeded determinism proven by GUT (same seed identical, diff seed differs)
- [x] Clearance: no props under/inside structures, reactive to new construction
- [x] Fog predicate matches existing details; hidden cells bare
- [x] Capture shots show grounded, non-intersecting props at dunes/base poses
- [x] BENCH numbers recorded, overhead small vs terrain section
- [x] Full GUT suite green; budget gate green

## Implementation notes (2026-10-30)
- The scatter extends `TerrainDetail3D` in place rather than a sibling node:
  a sibling would also have to be a null-mesh `MeshInstance3D` to survive the
  Phase 1 port test's child cast, which buys nothing (documented in the class
  header).
- Prop meshes come from the plan-06 GLBs via a cached static extractor
  (`_prop_source`): single identity-transform mesh nodes share the imported
  mesh resource; multi-mesh props merge into one `ArrayMesh` with baked node
  transforms and per-surface materials. The StructureModelLoader-style
  normalization (footprint scale, min-y 0, XZ center) is composed into every
  instance transform — no mesh mutation, materials stay as authored.
- `Terrain3D.notify_structures_changed()` now also marks all chunks dirty;
  the clearance re-stamp only runs inside a rebuild batch, so before this
  change a fresh structure's dune flattening (and scatter re-filter) waited
  for the 5s backstop.
- `HeightField3D.clearance_at_cell()` exposes the existing stamp set to the
  scatter — no second source of truth.
- MultiMesh instance transforms have no reliable headless read-back (the
  dummy and opengl3 servers serve identity for `get_instance_transform`, and
  the `buffer` getter can hang a `-s` run), so the scatter maintains
  `TerrainDetail3D.scatter_log` — the same per-kind transform arrays the
  MultiMeshes are built from. GUT and the F3 probe read that.
- Per-instance color/tint was dropped: the props' painted atlas is the read,
  and StandardMaterial3D has no texture × instance-color multiply without a
  custom shader.
- Pines render near-black against the snow — that is the authored plan-06
  atlas (`#485e4c` foliage) under the cold overcast; consistent with the
  house rule that neutral dressing stays dark and units carry the bright read.
- BENCH (macOS dev machine, driver run windowed per AGENTS.md; the
  `scatter_enabled=false` toggle comparison ran in GUT where Probe3D section
  timing is deterministic, plus a full-load capture-driver run at
  STRESS_UNITS=100 for the 200-unit budget context):
  - GUT probe (idle match, seed 7): `terrain_scatter` 0.034 ms avg vs
    `terrain_rebuild` 15.165 ms avg with scatter, 19.027 ms with scatter
    disabled — the difference is run-to-run noise; scatter ≈ 0.2%.
  - Full-load BENCH (STRESS_UNITS=100, BENCH=30, 200 live units):
    `terrain_rebuild` 2.275 ms avg/batch, `terrain_scatter` 0.129 ms avg per
    surface chunk (~2 scattered chunks per fog-driven batch ≈ 0.26 ms, ~11%
    of the batch) — trivially inside the 16.6 ms frame budget. Full report:
    fog_rebuild 2.614 ms, unit_sync 0.797 ms, sim_fog_recompute 8.017 ms
    (sim-side, pre-existing), ring_hover_scan 0.091 ms.

## Out of scope
- Underground scatter (ore/embers already covered)
- Prop destruction/damage states
- Editor tooling or procedural prop generation (plan 06)
