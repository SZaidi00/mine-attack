# Phase 1 progress — 2.5D port

Working log for [phase-1-25d-port.md](phase-1-25d-port.md). Updated per
milestone; open items carried forward.

## Milestones

| Milestone | Status | Notes |
|---|---|---|
| M1 — Terrain renders from `_cells`; camera pans/zooms/Tabs | **Done** | Chunked terrain (21×8-cell chunks, 12 total, signal-dirty + 0.15 s throttle, layer-aware rebuild on Tab); camera rig (55° pitch, dolly 3–25, WASD/arrows + edge pan, follows `PlayerController.view_mode_changed`). Renderer switched to `forward_plus` (desktop) with `gl_compatibility` kept for `.mobile`/`.web` overrides. |
| M2 — Units + structures visible as billboards | **Done** | `EntityProxies3D` reconciles the unit/structure groups every 0.2 s (instance-id keyed, `died`/`destroyed`/group-leaving culls). Units: `Sprite3D` FIXED_Y billboards (texture logic mirrors `unit_rendering._get_unit_texture`), blob shadows, HP bars, flight altitude, undead tint, per-frame position/fog/layer sync. Structures: box stand-ins (building/tower/lantern/wall/trap), `mine_entry.png` billboard, ladder rails; construction alpha + fog mirrored at reconcile. |
| M3 — Full control scheme functional | Not started | Needs mouse-ray unprojection feeding `player_selection`/`player_commands`, selection rings/box in 3D, build-placement ground snapping. |
| M4 — Fog + weather + effects re-created | Not started | Fog: per-vertex tint placeholder in place; §1.5 fog-texture shader still owed. No weather/effects visuals yet (snowstorm/volcano/cave-ins/lava pulse/projectile tracers/popups). |
| M5 — Tests green, exports, release | Not started | GUT suite green at M1+M2 (incl. new `test_3d_port.gd`). Exports not attempted. |

## Architecture decisions (locked)

- **Sim mount:** the shell instances `scenes/main.tscn` as a direct child of
  the window root at runtime → `/root/Main` resolves exactly as shipped
  (86 references / 57 files). All 2D CanvasItem layers are hidden; the HUD
  CanvasLayer stays visible and overlays the 3D viewport.
- **Ground truth:** `GridWorld._cells` (+ unit/structure node state) is
  read by the presentation layer only; nothing 3D writes back (hard rule 3).
- **Fog/layer mirroring:** the sim already flips `unit.visible` per fog and
  tracks `is_underground`; proxies mirror those instead of re-deriving them.
- **Zero sim-code changes so far:** all Phase 1 code is new files under
  `scripts/three_d/` + `scenes/world_3d.tscn`; the only edited existing file
  is `project.godot` (main scene + rendering method).

## Known gaps carried to M3/M4

- Mouse input still targets the hidden 2D viewport; no picking in 3D.
- Screen shake / view slide / reduced-motion not ported to the rig.
- No 3D effects yet: popups, order markers, projectiles, weather particles.
- Terrain lava is a static bright color (pulse/emissive owed in §1.6);
  fog is per-vertex (quad granularity), §1.5 shader pending.
- Structure stand-ins are untextured boxes; decals owed in the art pass (§1.7/Phase 2).
