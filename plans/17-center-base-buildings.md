# Plan 17 — Center base buildings in the surface band

Status: Done (2026-11-01)
Branch: `kimi-code-plans`
Depends on: 16

## Why

The wide board authors the base cells at `(±40, 0)` and places buildings with
a **cell-corner origin** (`main.gd` `_place_layout_node(..., centered=false)`).
The 6×5-cell body seals rows −5..−1 relative to that origin, so on the 10-row
band the whole base hugs the **front** rows while rows −9..−6 sit empty behind
it — next to mine entries deliberately centered on row −5, the base reads as
pushed to the near side. (On the legacy 1-row board the same convention is
the original `main` look — sprite rising behind the single walk row — so the
legacy profile must not change.)

## Change

- `scripts/resources/maps/default.tres`: `player_building_cell`/`enemy_
  building_cell` `(±40, 0)` → `(±40, -2)`. The footprint then seals rows
  −7..−3: body centered in the band (visual center row −5), two backfield
  rows (−9..−8), three walkable rows in front (−2..0).
- `scripts/resources/map_definition.gd`: export defaults match.
- `building.gd::_add_deposit_point`: the deposit Marker2D's local Y is
  computed as the offset to the **front walkable row's center**
  (`(Y_MIN + 0.5) * CELL_SIZE - global_position.y`) instead of the hardcoded
  `CELL_SIZE * 0.5`, so the miner deposit point stays on row 0 wherever the
  body sits. On the legacy board the formula yields the identical 32 px.
- `tests/test_map_definition.gd`: wide-cell assertions updated.

## Out of scope / non-changes

- Horizontal position (±40): unchanged — the base back-loads its half on
  purpose (maximize the contested front field), matching the original 2D
  board's proportions.
- Legacy profile: untouched (formulas collapse to current behavior).
- Footprint width/height, vision, spawn, and bounds logic: all already
  relative to the node position.

## Verification

- Focused: `test_map_definition` (6), `test_world_profile` (8),
  `test_fog_of_war` (28), `test_spawn_point` (5), `test_building_queue`
  (8), `test_surface_band` (22), `test_structures` (25), plus the
  building-position-sensitive suites (`economy`, `welfare`, `engineer`,
  `stance_modes`, `defend_leash`, `volcano`, `factions`, `3d_fog`,
  `minimap`, `capture_driver`, `play_mode_setting`, `ai_awareness`,
  `ai_strategy`, `dynamic_terrain`) — all green.
- Full-suite fallout fixed (two tests, both pinned to the old base row):
  - `test_tech_branches.gd::test_siege_master_swordsman_bonus_damage_vs_building`
    stood the swordsman on row 0, which no longer touches the moved bounds
    rect — now stands one cell left of the footprint on its bottom body row.
  - `test_spawn_point.gd` captured every `unit_spawned`; under suite load
    the buildings' deferred starting-miner spawn can land inside a test
    window, so the tracked unit was a miner (later found dead underground)
    instead of the queued swordsman. Now: starting units are wiped in
    `before_each` and the capture filters by the queued unit's type (the
    same wipe `test_selection_box.gd` uses).
- Full: `tools/run_checks.sh` → **PASS — 83 scripts, 890 tests, 14,099
  assertions**, exit 0, budget gate clean.
- Visual: `tools/capture` base/surface poses
  (`build/captures/plan17-base/`) — the keep is band-centered with
  walkable rows in front and behind; legacy 2D is pixel-identical (the
  deposit formula collapses to the old 32px there).
