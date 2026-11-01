# Plan 15 — Building spawn point

Status: Done (2026-11-01)
Branch: `kimi-code-plans` (repo convention; plans say `feat/3d-conversion` but
the queue actually lives on `kimi-code-plans`)
Depends on: 14

## Goal

Let the player set a **spawn point** on the map so newly trained units head
there directly instead of piling up in front of the building. Classic RTS
building rally, scoped to what this game needs.

## Semantics (decisions locked)

- The spawn point lives on the **building** (`scripts/world/building.gd`).
  One per team; only the player gets UI to set it. The AI never sets one
  (its controller already micromanages spawned units).
- **Which units obey it:** fighters and engineers — i.e. everything the
  building spawns except miners and crawlers, which keep their hard-wired
  auto-descend into the mine shaft (`climb_down_ladder` at spawn). Pigeons
  spawn from towers, not the building, so they are out of scope.
- **Precedence:** the building issues the spawn-point move BEFORE emitting
  `unit_spawned`, so the existing stance hook (`PlayerController.
  _on_fighter_spawned`) can override it: Attack stance still charges the
  enemy building, Garrison still recalls home, Defend (no order) leaves the
  spawn-point move standing. Explicit stance beats spawn point.
- **Where it can be placed:** surface cells only
  (`GridWorld.is_surface_row`). An underground click is rejected with the
  standard reject popup — surface units cannot path to underground targets.
  The validation lives in the player command layer, not the building, so the
  building API stays team-agnostic.
- **Persistence:** match-scoped like everything else on the building node;
  a new match / Play Again rebuilds the scene and drops it.
- Armed-mode UX mirrors attack-move: left-click places, right-click or
  Esc/Space cancels, all input swallowed while armed. Arming cancels the
  other armed modes (fighter rally, attack-move, build placement) and vice
  versa.

## Files

### New
- `scripts/three_d/spawn_point_marker_3d.gd` — persistent 3D marker (gold
  ground ring + pole + pennant) parented under
  `Presentation3D.effects_parent()`. Static, unshaded via `FlatGeo3D`
  materials, depth-tested, ground-snapped like `OrderMarker3D`. No-op when
  no shell runs (2D mode / tests keep the 2D flag).
- `tests/test_spawn_point.gd` — GUT suite (see Verification).
- `plans/15-spawn-point.md` — this file.

### Modified
- `scripts/world/building.gd`
  - `signal spawn_point_changed(has_point: bool)`.
  - `_spawn_point: Vector2`, `_has_spawn_point: bool`;
    `set_spawn_point(world_pos)`, `clear_spawn_point()`,
    `has_spawn_point()`, `get_spawn_point()`.
  - `_spawn_front()`: after `add_child`, before `unit_spawned.emit`, if a
    spawn point is set and the unit is not a miner/crawler, call
    `unit.move_to(_spawn_point)`.
  - `_draw()`: gold pole + pennant at the spawn point (local coords via
    `to_local`), skipped once destroyed; `queue_redraw()` on set/clear.
  - 3D marker lifecycle: rebuild on set/clear, free on `tree_exiting`.
- `scripts/controllers/player_controller.gd`
  - `_spawn_point_armed: bool`; `_unhandled_input` block routing to
    `_commands._handle_spawn_point_input(event)` (after the `_rally_armed`
    block, before control-group digits).
  - `is_spawn_point_armed()` getter.
  - `_toggle_attack_move_arm()` cancels `_spawn_point_armed`.
- `scripts/controllers/player_commands.gd`
  - `toggle_spawn_point_armed()`: toggles; on arm cancels rally/attack-move
    armed + build placement.
  - `_set_spawn_point(screen_pos)` → `_set_spawn_point_at(world_pos)`:
    surface validation, reject popup otherwise, sets the building point,
    flashes a gold order marker (`_spawn_order_marker`).
  - `_handle_spawn_point_input(event)`: place on lmb, cancel on rmb/pause.
  - `_player_building()` helper.
  - Cancel `_spawn_point_armed` in `set_stance`, `_issue_command`
    (belt-and-braces), `attack_move_order`, and `_set_rally_point`.
- `scripts/controllers/player_build_placement.gd` — `start_build_placement`
  cancels `_spawn_point_armed` (sits next to the existing rally cancel).
- `scripts/ui/hud.gd` — runtime-created toggle `Button` ("Set\nSpawn")
  inserted before Kill in `CommandRow` (same pattern as the Raise button),
  armed-state sync in `_process`, tooltip documents miner/crawler exception.
- `plans/README.md` — index row.
- `AGENTS.md` — building bullet + HUD button note.

## Acceptance criteria

1. With no spawn point set, behavior is byte-identical to today.
2. Set a point → newly trained swordsman/engineer moves there and holds.
3. Miners and crawlers still auto-enter the mine with a point set.
4. Attack/Garrison stance still overrides the point for fighters; Defend
   uses it.
5. Underground click rejected with popup; no state change.
6. 2D mode shows the flag via `_draw`; 3D shell shows the marker only
   (2D canvas hidden).
7. Full `tools/run_checks.sh` green.

## Verification

- Focused: `godot --headless --path . -s addons/gut/gut_cmdln.gd
  -gtest=res://tests/test_spawn_point.gd -gexit`
  → **5/5 passed, 12 asserts** (after one `--import` pass to register the new
  `SpawnPointMarker3D` global class — a fresh script referenced by class name
  needs the class cache rebuilt before headless GUT runs).
- Full: `tools/run_checks.sh`
  → **PASS — 82 scripts, 883 tests, 14,072 assertions**, exit 0, plus the GLB
  budget gate. `git diff --check` clean.
- Not run: interactive GUI smoke (button placement in the CommandRow at
  minimum window size); headless suite covers the sim behavior end to end.
