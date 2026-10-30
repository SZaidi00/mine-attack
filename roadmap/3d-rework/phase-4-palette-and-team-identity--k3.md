# Phase 4 — Palette & Team Identity

**Parent plan:** `roadmap/3d-rework/README.md` (read it first for rules).
**Depends on phase 3** (tonemapping changes how every color reads; tune
palette after it lands).

## Current state (verified)

- Palette tokens: `scripts/three_d/art_style_3d.gd:20-39`; terrain colors
  `scripts/three_d/terrain_3d.gd:31-38`; dirt layers from
  `GameManager.COLOR_DIRT_1..3` (`#8B6F47` / `#6B5637` / `#4A3B26`).
- Team colors: player `#3B82F6`, enemy `#B91C1C`
  (`scripts/autoload/game_manager.gd:62-71`), used as full-body albedo
  (`art_style_3d.gd:146-147`). Faction accents: Arcane violet, Brute red,
  Industrial brass (`art_style_3d.gd:42-46`); hidden enemy faction falls back
  to grey (:157).
- Materials: `StandardMaterial3D`, roughness 1.0, metallic 0, **no rim, no
  specular tuning** (`art_style_3d.gd:88-104`).
- Known weaknesses:
  - Enemy `#B91C1C` (luminance ~0.15) on underground rock (~0.18–0.22) has
    almost no value contrast — enemy units vanish in the mine.
  - **Brute accent red ≈ enemy team red**: a Brute player's army carries
    enemy-colored trims.
  - Snow cover is a ~4% value shift (ice `#DCECF5` lerped 85% toward snow)
    — effectively invisible (`terrain_3d.gd:339`).
  - Colorblind palette only rewrites 2D UI tokens
    (`scripts/ui/ui_theme_tokens.gd:91-98`); 3D keeps red/blue.

## Reference

SC2: team color is carried on the unit's *largest readable surfaces*, with a
neutral body so the team color never fights the base palette; terrain sits
~20–30% lower in value than units. TAB: desaturated world, saturated units;
at max zoom the map reads as colored blobs and threat zones.

## Goals

1. **Value separation pass.** Establish a luminance ladder: terrain darkest,
   structures mid, units brightest. Concretely: darken/cool the underground
   rock and dirt tokens ~15%, lift unit team colors in value (player blue
   toward a cleaner `#4A90F5`-ish, enemy red toward `#E03232`-ish scarlet —
   pick under ACES from phase 3, these are starting points).
2. **Fix the Brute/enemy red collision.** Shift Brute's accent from red to a
   warm orange/ember (fits "raw power" and the lava world) or a dark crimson
   clearly darker than the enemy scarlet. Update `art_style_3d.gd:42-46`, the
   style guide, and check the 2D faction icon usage in
   `scripts/ui/hud_updates.gd` for consistency.
3. **Rim lighting.** Add `rim_enabled` + rim tint to `ArtStyle3D.get_material`
   for unit/structure materials (not terrain): a subtle cool rim from the
   sky side to separate dark units from dark ground. Keep roughness 1.0.
4. **Colorblind parity in 3D.** Route team colors for 3D through a single
   accessor (e.g. `ArtStyle3D.team_color(team)`) that consults
   `SettingsManager`'s colorblind preference and mirrors
   `UIThemeTokens.apply_colorblind_palette()` swaps (blue/red →
   blue/orange or the existing palette). React to
   `SettingsManager.setting_changed` live.
5. **Snow cover visibility.** Increase the snow-cover lerp and add a slight
   blue-white value lift so storms visibly whiten the board
   (`terrain_3d.gd:339`); melt path likewise.
6. **Undead/necro tint check** under the new post: sickly green must not be
   confused with Arcane violet or the enemy color in any palette mode.

## Non-goals

- No new models or animations; no UI restyle beyond the accent-color
  consistency check.
- No palette tokens outside `art_style_3d.gd`/`terrain_3d.gd` unless a
  hard-coded color escapes the token system (then fix the escape).

## Steps

1. After phase 3 lands, screenshot the board in all four lighting moods as
   the baseline.
2. Retune tokens in `art_style_3d.gd:20-46` and `terrain_3d.gd:31-38` on the
   luminance ladder; screenshot-compare each mood.
3. Change Brute accent; grep for hard-coded duplicates of the old accent.
4. Add rim support in `get_material`; apply to entity materials only.
5. Add `ArtStyle3D.team_color(team)` + settings hookup; migrate
   `art_style_3d.gd:146-147` and any direct `GameManager.COLOR_*` uses in
   `scripts/three_d/`.
6. Buff snow-cover visibility; verify storm in/out transitions.
7. Update `roadmap/3d-conversion/style-guide.md` palette table + faction
   accent list, and `AGENTS.md` if it names the colors.

## Acceptance criteria

- Enemy units are distinguishable from underground rock at a glance in the
  underground mood; player vs enemy is unambiguous at max zoom-out.
- Brute accents no longer read as "enemy".
- Colorblind mode swaps 3D team colors live (toggle in settings, no restart).
- Snowstorms visibly change the board.
- Full test suite green
  (`godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests
  -gexit`); add a small test for `team_color()` under colorblind on/off,
  following the settings-restore pattern in `tests/test_settings_volume.gd`.
