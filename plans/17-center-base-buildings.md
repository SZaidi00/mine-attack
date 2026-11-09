# Plan 17 — Center base buildings in the band and their half

Status: Done (2026-11-01; horizontal centering added the same day)
Branch: `kimi-code-plans`
Depends on: 16

## Why

The wide board authored the base cells at `(±40, 0)` and places buildings with
a **cell-corner origin** (`main.gd` `_place_layout_node(..., centered=false)`).
Two visible problems, both reported by the player:

1. **Vertical:** the 6×5-cell body seals rows −5..−1 relative to that origin,
   so on the 10-row band the whole base hugged the **front** rows while rows
   −9..−6 sat empty behind it. (On the legacy 1-row board the same convention
   is the original `main` look — sprite rising behind the single walk row —
   so the legacy profile must not change.)
2. **Horizontal:** the base sat at ±40 — ten columns from the map edge and
   forty from midfield — reading as "on the edge of the map" instead of the
   center of the player's territory.

## Change

- `scripts/resources/maps/default.tres`: `player_building_cell`/
  `enemy_building_cell` `(±40, 0)` → **`(±25, -2)`**. The footprint seals
  x ∓[28..23] × rows −7..−3: the body is centered in the band (visual center
  row −5) and on the half (half center column −25), with two backfield rows,
  three walkable rows in front (−2..0), and the mine entries one jump ahead
  at `(±20,-5)`.
- `scripts/resources/map_definition.gd`: export defaults match.
- `building.gd::_add_deposit_point`: the deposit Marker2D's local Y is
  computed as the offset to the **front walkable row's center**
  (`(Y_MIN + 0.5) * CELL_SIZE - global_position.y`) instead of the hardcoded
  `CELL_SIZE * 0.5`, so the miner deposit point stays on row 0 wherever the
  body sits. On the legacy board the formula yields the identical 32 px.
- `tests/test_map_definition.gd`: wide-cell assertions updated.

## Gameplay consequences (accepted)

- Miners' surface walk to the deposit point shrinks (~17 → ~3 columns):
  both teams' economies flow noticeably faster.
- Enemy marches reach the base ~15 columns sooner: faster, tighter matches.
- Towers may no longer be placed directly in front of the base (the
  grow(2) no-build zone now covers the rows in front of it).

## Out of scope / non-changes

- Legacy profile: untouched (formulas collapse to current behavior).
- Footprint width/height, vision, spawn, and bounds logic: all already
  relative to the node position.

## Full-suite fallout fixed (all test-only)

- `test_tech_branches.gd::test_siege_master_swordsman_bonus_damage_vs_building`
  stood the swordsman on row 0, which no longer touches the moved bounds
  rect — now stands one cell left of the footprint on its bottom body row.
- `test_spawn_point.gd` captured every `unit_spawned`; under suite load the
  buildings' deferred starting-miner spawn can land inside a test window, so
  the tracked unit was a miner (later found dead underground) instead of the
  queued swordsman. Now: starting units are wiped in `before_each` and the
  capture filters by the queued unit's type (the same wipe
  `test_selection_box.gd` uses).
- `test_fog_of_war.gd` layer-lock tests probed the underground cell under
  the **shaft column** and expected it hidden — true only while the starting
  miners hadn't descended, which the closer base invalidated (they now reach
  the shaft mid-suite and legitimately light the tunnels). Both tests now
  probe a far-backfield column (−45) with a loud precondition assert. Also
  corrected the `fog_state_at` enum in `plans/README.md` (2 = visible,
  1 = remembered, 0 = hidden — the contract had it backwards).
- `test_3d_fog.gd::test_built_tower_clears_surface_fog_but_not_the_cell_below`
  (plan 13's sentry-vision test) had the same pattern at column −30 — now
  inside the mining neighborhood, and the tower itself would land in the
  footprint's grow(2) no-build zone. Moved to the −45 backfield column.

## Verification

- Focused: `test_map_definition` (6), `test_world_profile` (8),
  `test_fog_of_war` (28), `test_spawn_point` (5), `test_building_queue`
  (8), `test_surface_band` (22), `test_structures` (25), `test_tech_branches`
  (34), plus the building-position-sensitive suites (`economy`, `welfare`,
  `engineer`, `stance_modes`, `defend_leash`, `volcano`, `factions`,
  `3d_fog`, `minimap`, `capture_driver`, `play_mode_setting`,
  `ai_awareness`, `ai_strategy`, `dynamic_terrain`) — all green.
- Full: `tools/run_checks.sh` → **PASS — 83 scripts, 890 tests, 14,099
  assertions**, exit 0, budget gate clean.
- Visual: `tools/capture` base/surface poses
  (`build/captures/plan17-base/`) — the keep sits in the middle of its
  territory; legacy 2D is pixel-identical (the deposit formula collapses to
  the old 32px there).
