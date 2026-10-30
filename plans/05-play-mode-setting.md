# Plan 05 — Play-mode setting (3D default / 2D legacy)

Status: Not started
Size: S
Depends on: —

## Mission
Turn the branch's one hard-coded behavioral flip — main menu Play always
loads the 3D shell — into an explicit, persisted user setting with a 2D
legacy fallback, and document the merge-decision default.

## Context
- `scripts/ui/main_menu.gd::_on_play()` ends with
  `get_tree().change_scene_to_file("res://scenes/main_3d.tscn")` and a comment:
  *"3D conversion branch: Play enters the main_3d shell... (on main this loads
  main.tscn directly)."* After this branch merges, 3D becomes the only entry
  point.
- `scripts/autoload/settings_manager.gd` persists settings to
  `user://settings.cfg` and already carries a `[video] graphics_quality`
  override (auto/potato/standard/fancy) plus accessibility and remappable
  keys. It emits `setting_changed(what: StringName)` and has the pattern for
  adding a new setting — mirror `graphics_quality` exactly.
- `scripts/ui/settings_panel.gd` is the shared settings popup (main menu +
  pause menu); the main menu itself has an inline Resolution row built in
  `main_menu.gd::_build_card()` — a play-mode dropdown belongs next to it.
- The 2D path must keep working: `scenes/main.tscn` standalone is what the
  whole GUT suite instantiates, and `tools/capture/capture_driver.tscn`
  swaps scenes itself. `run/main_scene` stays `scenes/ui/main_menu.tscn`.
- 2D rendering on this branch: `project.godot` rendering method was switched to
  `forward_plus` for the 3D port; the `.mobile`/`.web` overrides keep
  `gl_compatibility`. A 2D-legacy desktop run therefore renders through
  `forward_plus` — acceptable for a legacy fallback, but note it in the docs.

## Task
1. Read `scripts/autoload/settings_manager.gd`, `scripts/ui/main_menu.gd`,
   `scripts/ui/settings_panel.gd`, and `AGENTS.md` first.
2. Add a persisted `[video] play_mode` setting: `"3d"` (default) or `"2d"`.
   Same storage/accessor pattern as `graphics_quality`
   (`get_play_mode()` / `set_play_mode()`), validated on read (unknown values
   fall back to `"3d"`).
3. `main_menu.gd`: add a "Mode" dropdown ("3D (recommended)" / "2D legacy")
   beside the Resolution row, initialized from the setting, persisting on
   select. `_on_play()` branches on it:
   `"3d"` → `res://scenes/main_3d.tscn`; `"2d"` → `res://scenes/main.tscn`.
   Keep the existing comment, updated to describe the setting instead of the
   branch-only divergence.
4. `settings_panel.gd`: surface the same Mode option in the Display group so
   the pause menu can flip it too (takes effect on next Play — label it so).
5. Tests: extend the settings/accessibility GUT file (or add one) — default is
   `"3d"`, round-trip persists, invalid stored value reads back `"3d"`, and
   `_on_play()` targets the right scene per setting (assert against
   `change_scene_to_file` behavior the same way existing menu tests do —
   read `tests/` for the menu test pattern first).
6. Docs: `AGENTS.md` runtime-architecture note — Play enters `main_3d.tscn`
   by default with a 2D legacy fallback via the Mode setting; update the
   `main_menu.gd` line in the code-organization section.

## Constraints
- Default must be `"3d"` — flipping the default silently is exactly what
  this plan exists to avoid.
- The capture harness and GUT suite load scenes directly and are untouched.
- Settings tests write `user://settings.cfg` for real: restore prior values in
  `after_all` (see `tests/test_settings_volume.gd`).
- No scene-structure changes to `main.tscn` / `main_3d.tscn`.

## Verification
```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_settings_volume.gd -gexit
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
# Both modes launch headlessly (smoke): run the capture driver — it swaps in
# main_3d.tscn by itself, so this verifies the 2D path stays importable:
tools/capture/run_capture.sh /tmp/shots
```

## Acceptance criteria
- [ ] Setting persists across restart; default "3d"; invalid value → "3d"
- [ ] Main-menu dropdown + settings-panel option both wired
- [ ] `_on_play` loads the right scene per mode (GUT-verified)
- [ ] Full GUT suite green; capture smoke run passes
- [ ] `AGENTS.md` updated

## Out of scope
- In-match mode switching (restart required is fine)
- Removing the 3D branch or the 2D code paths
