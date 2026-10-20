# Phase 2 — Camera & Scale (RTS framing)

**Parent plan:** `roadmap/3d-rework/README.md` (read it first for rules).
Cheap, high-impact: reframing the shot so units stop being specks.

## Current state (verified)

- Camera rig: `CameraRig` Node3D, Camera3D child at
  `Vector3(0, dolly*tan(55°), dolly)`, fixed −55° pitch, yaw never changes
  (`scripts/three_d/main_3d.gd:119-124`).
- Dolly: start 12.0, min 3.0, max 25.0, wheel step ×1.1
  (`main_3d.gd:22-25, 200-211`). Pan clamps to the grid rect.
- **FOV is never set** — Godot default 75° vertical
  (`scenes/main_3d.tscn:13-14`). Near/far defaults.
- Consequence: a humanoid unit (0.34 world units tall,
  `scripts/three_d/unit_model_3d.gd`) occupies ~11 px of a 1080p frame at
  default dolly and ~5 px at max zoom-out. The style guide's rule "a unit
  must be identifiable by silhouette at max zoom-out"
  (`roadmap/3d-conversion/style-guide.md`) is unachievable at that size.
- `WORLD_SCALE = 0.01`; the whole map is ~26×8 world units
  (`main_3d.gd:20`).

## Reference

SC2 runs a ~30–35° vertical FOV equivalent with a low dolly range; They Are
Billions allows deep zoom-out but compensates with exaggerated unit scale and
saturated team blobs. We can get most of the win without touching a single
model: narrow the FOV and scale up unit/structure proxy roots.

## Goals

1. **Narrow the FOV** to ~45° (try 40–50, pick by feel). This is roughly a
   1.6× apparent-size increase at the same dolly and also reduces the
   perspective distortion that makes the board look like a diorama.
2. **Retune dolly range** so default view shows ~10–12 world units of ground
   height (units ~25–30 px tall at 1080p) and max zoom-out still shows the
   full width of a player's half. After FOV change, recompute
   `DOLLY_START/MIN/MAX` and pan clamp accordingly.
3. **Scale up proxies** ~1.4× via the proxy root scale (one place:
   `unit_proxy_3d.gd` / `structure_proxy_3d.gd` root `scale`), NOT by
   editing model dimensions in `unit_model_3d.gd`. Verify: blob shadows
   scale along (they're children), HP bars must be counter-scaled or
   re-sized, lantern OmniLight ranges stay in world units (do NOT scale
   those). Walls/towers must still fit their cell footprint — a 1.4× scale
   may overflow single-cell walls; cap structure scale at whatever keeps a
   wall inside its 0.32-unit cell.
4. **Slight pitch option:** consider raising pitch from 55° to ~60° for a
   more top-down TAB-like read. Optional; only if playtest says so. Keep the
   rig API unchanged.
5. **Zoom-to-cursor:** wheel zoom should dolly toward the cursor's terrain
   point, not the screen center (SC2/TAB behavior). The rig has the focus
   point + pan clamp already; extend `_unhandled_input` zoom handling
   (`main_3d.gd:200-211`).

## Non-goals

- No free camera rotation/pitch control (the fixed rig is a design choice).
- No minimap changes.

## Steps

1. Add `fov` to the Camera3D in `main_3d.tscn` (or set from
   `ArtStyle3D.apply_quality` if presets should differ — default: same for
   all presets).
2. Recompute dolly constants; adjust pan clamp and Tab bookmarks
   (`main_3d.gd:217-232`) if focus positions shift.
3. Add a `PROXY_SCALE` const; apply at proxy root; counter-scale HP bars;
   audit every place that assumes model size (ring radii from phase 1,
   emissive orb positions, blob shadow radius `unit_proxy_3d.gd:44-70`).
4. Implement zoom-to-cursor with terrain height lookup from `terrain_3d.gd`.
5. Update `AGENTS.md` camera-rig description.

## Acceptance criteria

- At default dolly, a swordsman is ≥ 24 px tall at 1080p and its silhouette
  (sword) is identifiable; at max zoom-out, units read as team-colored blobs
  and structures are unmistakable.
- Wheel zoom lands on the cursor point; pan clamps still bound the map; Tab
  bookmarks still frame surface/underground correctly.
- No proxy visually overlaps adjacent cells incorrectly (walls especially).
- Full test suite green
  (`godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests
  -gexit`); update `tests/test_3d_port.gd` if it asserts camera constants.
