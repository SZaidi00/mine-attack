# Plan 16 — Chained walls and a raised wall cap

Status: Done (2026-11-01)
Branch: `kimi-code-plans`
Depends on: 15

## Goal

Turn placed walls from a handful of isolated chunks into a **chain system**:
raise the placed-wall cap so players can actually build a line, and make
adjacent walls render as a connected fence — a **post** at each wall cell and
**shorter rails** spanning to the neighboring posts (2D and 3D).

## Semantics (decisions locked)

- **Cap:** base `PLACED_WALL_MAX_COUNT` 2 → **8**; `FactionData.wall_max_count`
  default 2 → 8; Industrial keeps its specialty at **10** (was 3, +2 over
  default). Research `wall_max_count_bonus` (+1 Stone Masonry, +1 Total War)
  stacks on top, unchanged. Costs/HP/build time untouched. The AI never
  places walls (player-only structure), so no AI changes.
- **Link rule:** same-team walls on 4-adjacent cells (x±1 or y±1) link.
  Built state is irrelevant — a chain forms as it builds, and construction
  alpha already communicates the per-segment state. Mixed teams never link.
- **Sim state:** each `WallSegment` computes `_connections =
  {"left","right","up","down"}` (`up` = y-1 toward SURFACE_TOP) in
  `refresh_connections()`, refreshed by a static
  `WallSegment.refresh_group(tree)` helper called from `_ready` (a freshly
  placed wall updates the whole group) and from `_destroy()`/`demolish()`
  (after `remove_from_group`, so the dying wall excludes itself). Gameplay
  never frees walls outside those two paths, so this covers every case.
- **2D look** (`WallSegment._draw`): the existing 32px texture becomes a
  16px-wide **post**; per connected x-neighbor two steel rails
  (`GameManager.COLOR_STEEL`) run from the post edge to the cell boundary
  (meeting the neighbor's rails at the border), each with a thin team-color
  stripe; unconnected x-sides get short stubs so a lone wall still reads as
  a barrier; y-neighbors get vertical rails. Construction alpha, selection
  outline, and HP bars unchanged.
- **3D look** (`StructureProxy3D._build_wall`): post = stone box 0.34 CELL
  wide (was 0.9) + team capstone 0.40; per direction a shorter, thinner
  stone beam (0.24 tall vs the 0.5 post) runs from the post to the cell
  boundary — x-stubs (0.2 CELL) fill unconnected x-sides, z-sides stay
  flush. All link meshes live in a `WallLinks` container under
  `WallPivot`, registered via `_add_body` so damage tilt, construction
  alpha, fog memory, and damage darkening apply. Beams stay inside the
  1.08 PROXY_SCALE footprint budget (max reach 0.5 CELL * 1.08).
- **Connection changes at runtime:** the proxy re-reads
  `entity.get_connections()` at reconcile time in `refresh()` and rebuilds
  the link container only when the set changed (then re-tints). Sim →
  render only, same contract as the rest of the proxy layer.

## Files

### New
- `tests/test_wall_chain.gd` — sim + 3D proxy link behavior.
- `plans/16-chained-walls.md` — this file.

### Modified
- `scripts/world/wall_segment.gd` — `_connections`, `refresh_connections()`,
  `refresh_group()`, `get_connections()`, `_draw` post+rails restyle,
  destroy/demolish refresh.
- `scripts/autoload/constants.gd` — `PLACED_WALL_MAX_COUNT` 2 → 8.
- `scripts/resources/faction_data.gd` — `wall_max_count` default 8.
- `scripts/resources/factions/industrial.tres` — 3 → 10.
- `scripts/three_d/structure_proxy_3d.gd` — `_build_wall` post+links
  refactor, `_wall_links`/`_wall_conns`, refresh-time rebuild.
- `scripts/ui/hud_menus.gd` — wall card tooltip mentions chaining.
- `tests/test_structures.gd` — `test_wall_max_count` updated to the cap of 8.
- `plans/README.md`, `AGENTS.md` — index + docs; test count 82 → 83.

## Acceptance criteria

1. Cap: 8 walls place for a factionless team (9th rejected); Industrial 10.
2. Three adjacent walls: middle links both sides, ends link inward; vertical
   band neighbors link; mixed teams do not.
3. Destroying/demolishing a wall updates its neighbors' connections.
4. 3D proxy: link meshes appear for connected sides and disappear after the
   neighbor goes away (via `refresh()`), damage tilt still works.
5. Full `tools/run_checks.sh` green.

## Verification

- Focused: `-gtest=res://tests/test_wall_chain.gd` → **7/7 passed, 33
  asserts**; `-gtest=res://tests/test_structures.gd` → **25/25, 86**;
  `-gtest=res://tests/test_3d_structure_models.gd` → all passed (wall damage
  states survive the post/links rebuild — `WallPivot`/`Rubble` names kept).
- Full: `tools/run_checks.sh` → **PASS — 83 scripts, 890 tests, 14,111
  assertions**, exit 0, budget gate clean.
- Test-authoring note: placed walls are invulnerable until construction
  finishes, so destruction tests must jump `_build_progress` first
  (`_finish` helper in test_wall_chain.gd).
- Not run: interactive GUI smoke; the 3D link meshes are covered via
  `StructureProxy3D.refresh()` in the suite.
