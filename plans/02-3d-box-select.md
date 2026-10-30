# Plan 02 — 3D box-select via the rig camera

Status: Not started
Size: M
Depends on: —

## Mission
Fix drag-box selection in the 3D shell so a drag rectangle selects the units
it visually encloses, instead of units projected through the hidden 2D sim
camera.

## Context (the bug)
- `scripts/controllers/player_commands.gd::_screen_to_world()` is 3D-aware:
  when the `main_3d` shell runs it ray-marches the click through the rig
  (`Presentation3D.shell(tree)._terrain_point_at(screen_pos)`) and only falls
  back to the 2D canvas transform when there is no shell. Single-click select
  and all right-click commands route through it, so they work in 3D.
- `scripts/controllers/player_selection.gd::_box_select()` does **not**. It
  projects every unit's feet/combat position with the raw
  `get_viewport().get_canvas_transform()` — the hidden sim `Camera2D`'s
  transform — and tests screen-space inclusion in the drag rect.
- In shell mode that 2D camera diverges from the 3D rig: the rig owns dolly
  zoom (3–16, underground 3–10), zoom-to-cursor, edge pan, and a 55°/82.5°
  perspective pitch, while the sim camera keeps its own 2D zoom (0.65–2.0)
  and orthographic projection. Result: drag-box selects the wrong units in
  3D mode from the very first drag.
- The shell detection idiom to reuse:
  `Presentation3D.shell(pc.get_tree()) != null` (see `_screen_to_world`).
- The rig camera is a `Camera3D` in `scripts/three_d/main_3d.gd`; world
  conversion helpers live in `scripts/three_d/presentation_3d.gd`
  (`to_3d(...)`, `WORLD_SCALE`). `pose_camera()` exists for deterministic
  harness shots.

## Task
1. Read `scripts/three_d/main_3d.gd`, `scripts/three_d/presentation_3d.gd`,
   `scripts/controllers/player_selection.gd`, and
   `scripts/controllers/player_commands.gd` first.
2. Add a shell-side projection helper, e.g.
   `Presentation3D.screen_position(tree, world2d: Vector2) -> Vector2`
   (return `Vector2.INF` when no shell), implemented with the rig
   `Camera3D.unproject_position()` on the unit's 3D ground/combat point —
   mirror how `unit_proxy_3d.gd` places units on the dune field
   (`Presentation3D.ground_height(...)` is the ground query).
3. In `_box_select`, branch exactly like `_screen_to_world` does: when the
   shell is present, map each candidate unit's feet **and** combat position
   (flying dragons — the 2D path tests both) through the helper and test
   screen-space inclusion against the drag rect; keep the existing 2D canvas
   path byte-for-byte for standalone `main.tscn`.
4. Tests: follow `tests/test_3d_port.gd`'s shell-loading pattern. Pose the rig
   with `pose_camera()`, spawn player units at known cells, call `_box_select`
   with a screen rect that encloses a known subset, assert exactly that subset
   is selected — in shell mode AND standalone 2D mode (both must stay
   correct). Include one case where the rig has been dollied/zoomed away from
   the 2D camera's view to prove the projections are independent.

## Constraints
- Presentation-only: selection reads sim state; it already does — don't
  write anything back.
- The 2D standalone path (and every existing GUT test using it) must be
  untouched in behavior.
- Reuse `Presentation3D` for shell detection/conversion — do not add a second
  shell-detection idiom.
- If `unproject_position` lands behind a unit (infinite/negative w), treat
  that unit as outside the rect — never as a crash.

## Verification
```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_3d_selection.gd -gexit
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
# Eyeball: capture shots with the shell posed, drag-select region known
tools/capture/run_capture.sh /tmp/shots   # then compare units/base poses
```

## Acceptance criteria
- [ ] Shell-mode box select matches visual truth (test asserts exact set)
- [ ] Rig zoom/dolly no longer affects which units a drag selects wrongly
- [ ] Standalone 2D box select unchanged; all pre-existing selection tests pass
- [ ] Full GUT suite green

## Out of scope
- Selection rings, hover highlighting, shift-modifier semantics (unchanged)
- Any camera-rig behavior change
