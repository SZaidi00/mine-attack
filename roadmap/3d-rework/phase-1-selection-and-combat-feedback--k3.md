# Phase 1 — Selection & Combat Feedback in 3D

**Parent plan:** `roadmap/3d-rework/README.md` (read it first for rules).
**Priority: highest gameplay impact.** Today a player cannot see what is
selected, what is being shot, or where they clicked in 3D mode.

## Current state (verified)

- The 2D sim scene is mounted at `/root/Main`; its CanvasItem layers are
  hidden in 3D mode (`scripts/three_d/main_3d.gd:78-81`). All 2D `_draw`
  feedback is invisible.
- Selection ring: 2D texture drawn in `Unit._draw`
  (`scripts/units/unit_rendering.gd:21,97-100`). Nothing replaces it in 3D.
- HP bars DO exist in 3D (`scripts/three_d/unit_proxy_3d.gd:14-16, 82-100,
  121-131`): unshaded quads, 0.6×0.07 world units, green→red, yaw-billboarded
  — but only visible while `hp_ratio < 1.0` (line ~124).
- Projectiles: 2D only (`scripts/units/projectile.gd` on the hidden
  `Projectiles` layer). `EntityProxies3D` mirrors only `units` and structure
  groups (`scripts/three_d/entity_proxies_3d.gd:13-15`).
- Order markers (move/attack/mine rings) and damage popups are 2D canvas
  items added to the Node3D shell at 2D world coordinates
  (`scripts/controllers/player_commands.gd:244-249`,
  `scripts/units/unit_combat.gd:241-246`) — they draw misaligned in 3D mode.
- Coordinate conversion: `WORLD_SCALE = 0.01`, cell = 0.32 world units
  (`scripts/three_d/main_3d.gd:20`). 2D world pos → 3D is
  `Vector3(x * 0.01, terrain_height, y * 0.01)`; see how `unit_proxy_3d.gd`
  already maps positions, and `terrain_3d.gd` for per-cell heights.

## Goals

1. **3D selection rings.** A team-colored (player blue / enemy red, but
   selection ring is always the player's accent — e.g. bright blue/white)
   flat ring mesh on the terrain under every selected unit, plus one under
   the hovered unit (dimmer). Implementation: a `MultiMeshInstance3D` or a
   small pool of ring meshes in a new `scripts/three_d/selection_rings_3d.gd`,
   fed each frame from `PlayerController`'s selection (read-only). Ring
   radius from the unit's model footprint; unshaded material so it reads at
   any lighting; slight Y-offset + `no_depth_test` OFF so terrain occludes
   honestly, or ON if z-fighting proves ugly — pick one and document.
2. **HP-bar rework** (`unit_proxy_3d.gd`): show bars when selected OR damaged
   (current: damaged only); shrink to ~0.28 world units wide; add a dark
   border quad behind the fill; keep green→red fill. Bars must face the
   camera (existing yaw-billboard is fine).
3. **3D projectiles.** Mirror `projectile.gd` nodes the same way units are
   mirrored: a `ProjectileProxies3D` (extend the reconcile pattern in
   `entity_proxies_3d.gd:13`) with a small glowing tracer mesh per projectile
   (arrow: thin elongated quad; fireball: small emissive sphere). Cheap:
   pool ~64 meshes, unshaded + emissive.
4. **Projected order markers.** Re-parent or replace the 2D order markers
   with 3D equivalents in 3D mode: an expanding flat ring on the terrain at
   the click position (blue move / red attack / gold mine, same colors as
   now), plus a damage-popup equivalent (small unshaded numbers as
   billboarded `Label3D` or a pooled quad texture — pick the cheaper). The 2D
   path must remain for the 2D scene (`main.tscn` used standalone, tests).
   Gate on `get_tree().current_scene` being the 3D shell, the same way
   `main_3d.gd` detects its mount.
5. **Range discs.** A selected tower's attack-range disc and the placement
   ghosts' range/vision discs (currently 2D `_draw` in `tower.gd` /
   `player_build_placement.gd`) get flat unshaded 3D disc meshes. If this
   balloons the phase, split it into a follow-up — but selection rings and
   projectiles are non-negotiable.

## Non-goals

- No changes to how selection/orders work in the sim.
- No outlines/shaders (that's phase 4), no bloom tuning (phase 3).

## Steps

1. Add `selection_rings_3d.gd` + register in `world_3d.tscn`; hook to
   `PlayerController` selection-changed signals (find them in
   `scripts/controllers/player_selection.gd`).
2. Rework HP-bar visibility/size in `unit_proxy_3d.gd`.
3. Add `projectile_proxies_3d.gd`; register the `Projectiles` group in
   `entity_proxies_3d.gd`'s reconcile list.
4. Add 3D order markers; branch at spawn points in `player_commands.gd:244`
   and `unit_combat.gd:241` (keep the 2D branch for 2D mode/tests).
5. Add tower/placement range discs in `structure_proxy_3d.gd` /
   `player_build_placement.gd` 3D branch.
6. Update `AGENTS.md` (the `scripts/three_d/` description and the 3D-mode
   paragraph) and `roadmap/3d-conversion/phase-2-art-pass.md` status notes.

## Acceptance criteria

- In 3D mode: selecting units shows rings instantly; box-selecting 30 units
  shows 30 rings without frame drops; hover shows a pre-selection ring.
- Selected full-HP unit shows its HP bar; damaged unselected units still do.
- Archers/wizards/towers visibly shoot tracers in 3D mode.
- Right-click, attack-move (Q+click), and Shift-queued orders all show
  terrain-projected markers at the correct 3D position.
- 2D mode (`main.tscn` run directly) is pixel-identical to before.
- `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests
  -gexit` green; add a `tests/test_3d_selection.gd` covering ring visibility
  wiring and projectile proxy reconcile.
- Still 60 fps with 200+ units on Fancy.
