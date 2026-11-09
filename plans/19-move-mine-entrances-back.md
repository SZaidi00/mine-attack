# Plan 19 — Move mine entrances back to the original shaft columns

Status: Done (2026-11-01)
Branch: `kimi-code-plans`
Depends on: 17

## Why

Plan 17 centered the base buildings at `(±25,-2)`. On the wide board the mine
entrances had sat at `(±20,-5)` since the plan-12 world widening — so after
plan 17 the shaft read as sitting in the middle of the player's territory
while the base was still perceived as off-center (the two structures cluster
5 columns apart and the tall shaft+ladder silhouette dominates). The player
asked for the mine entrance to go **back** and the main building to be the
centered structure instead.

`x=±15` is the mine entrance's original shaft column on both the pre-wide
board (plans 11/12) and the current legacy profile (`legacy.tres`), so moving
the wide mines there restores the classic base → mine → midfield progression
with an unambiguous centered keep, and reunifies the two profiles' shaft
columns.

## Change

- `scripts/resources/maps/default.tres`: `player_mine_cell`/`enemy_mine_cell`
  `(±20,-5)` → **`(±15,-5)`** (still cell-centered, row −5). The visual
  mine-spur road rectangles follow the columns: `Rect2i(±20,-5,1,6)` →
  `Rect2i(±15,-5,1,6)`.
- `scripts/resources/map_definition.gd`: export defaults match.
- Base buildings stay at `(±25,-2)` (plan 17) — the keep is the centered
  structure; the shaft now stands 8 columns ahead of the base front.
- Tests:
  - `tests/test_map_definition.gd`: wide-mine assertions → `(±15,-5)`.
  - `tests/test_world_profile.gd::test_wide_request_boots_the_authored_world`:
    the stale-shaft pair flips — wide now carves at `x=-15` and asserts no
    stale shaft at the old wide column `−20`. The legacy test is untouched
    (it already boots shafts at `±15` with none at `±20`, which the aligned
    columns keep true).
  - `tests/test_3d_underground_art.gd`: every hard-coded shaft-column fixture
    `±20 → ±15` and the "next to the shaft" offsets `±21 → ±16` (excavated
    floors, strata-color probes, seam scan, seeded-rebuild record).
  - `tests/test_3d_effects.gd`: the mining-dust fixtures that used the shaft
    columns (`(±20, …)`) move to `±15`.
  - `tests/test_3d_underground_detail.gd`: `test_different_seed_grows_a_different_board`
    no longer assumes every seeded board decorates itself — seed 11's
    underground is solid DIRT with no support roll near the shafts, so the
    second boot lays deterministic rubble via forced cave-ins (the pebble
    test's fixture pattern).
  - `tests/test_map_definition.gd`: the road-spur coverage test derives the
    spur columns from the resource's mine cells instead of hard-coding ±20.
  - `tests/test_3d_underground_detail.gd`: cave-in fixture comment de-coupled
    from the shaft position (the fixture itself is position-independent).
- Docs: `AGENTS.md` (play-mode + world-layout paragraphs) and
  `plans/README.md` (global contract line) now say `(±15,-5)`.

## Gameplay consequences (accepted)

- Miners' surface walk base → shaft grows ~5 columns (shaft is now 8 columns
  ahead of the base front instead of 3); the deposit walk is unchanged.
- The mine shaft sits 15 columns from midfield, so it is scouted/contested
  a little earlier; symmetric for both teams.
- The 2D legacy profile is untouched (its mines were already at `x=±15`).

## Out of scope / non-changes

- Underground generation, shaft carving (`MineEntry` re-carves at its own
  column), ore layout, and the central wall: all driven by the same
  `MapDefinition` columns, so they follow automatically.
- Base buildings, camera start, prop regions: unchanged.

## Verification

- Focused: `test_map_definition`, `test_world_profile`, `test_surface_band`,
  `test_3d_underground_art`, `test_3d_underground_detail`,
  `test_3d_effects`, `test_fog_of_war`, `test_3d_fog`, `test_structures`,
  `test_spawn_point`, `test_capture_driver` — green.
- Full: `tools/run_checks.sh` → PASS (budget gate + headless GUT suite).
- Visual: `tools/capture` base/zoomout poses — keep centered in its half,
  shaft clearly ahead of it on the midfield side.
