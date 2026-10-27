# Technical Plan — Height-Field Terrain, Two-Mode Camera, Rendering

Concrete engineering plan for the revamp's structural pieces. Every claim
about current code has a `file:line` anchor (verified 2026-10-28 against
`feat/3d-conversion` @ 0049f41).

## 1. Rendering setup

Current: desktop defaults to Forward+ (`project.godot` has no explicit
`rendering_method`, so it defaults to Forward+; `.mobile` override is
`gl_compatibility`); the capture harness forces `--rendering-driver
opengl3`, which lands on the Compatibility renderer — the same path the
**web export** takes (`export_presets.cfg` Web preset).

Decisions:
- **Keep Forward+ for desktop** (macOS/Windows exports): SSAO + real shadow
  maps are Fancy-only value.
- **gl_compatibility stays the web path** — verified working end-to-end by
  the harness in this PR's baseline captures.
- Rule: no Forward+-only features without a Compatibility fallback behind
  `ArtStyle3D.apply_quality()`; the harness (opengl3) is the CI check for
  exactly this.
- Export matrix after every phase: Web + macOS + Windows presets must
  export clean (`tools/export_all.sh`).

## 2. Height-field surface terrain (phase R3)

Current terrain: `terrain_3d.gd` rebuilds per-cell quads into 21×8-cell
chunk meshes (signal-dirty, 0.15 s throttle, per-vertex fog). Flat.

Plan:
1. Add a `height_field.gd` (new `scripts/three_d/` module): layered value
   noise + ridged dune bands; **deterministic** (seeded from
   `GameManager.map_seed` so captures replay). Height ≤ 0.4 cells, flattened
   within 1 cell of structures/walls/mine entries (query
   `GridWorld` occupancy) and at the central wall (packed snow).
2. `terrain_3d.gd` displacement: sample the height function per vertex
   (chunk rebuild already batches this); normals recomputed. Underground
   rows stay flat — the flat view (§3) must keep grid readability.
3. Units/props: `unit_proxy_3d.gd` / `structure_proxy_3d.gd` ground-snap
   their Y from the same function (presentation-only; sim untouched).
4. Snowstorm mood flattens dune normals + brightens albedo (hook into
   `lighting_3d.gd` mood targets, already tweened).
5. Performance: height is a pure function → no storage, no sim; chunk
   rebuild cost unchanged (same vertex count).

## 3. Two-mode camera (phase R5)

Current rig: `main_3d.gd` — 55° pitch dolly, FOV 45, dolly 3–16,
`_apply_view()` swaps focus bookmarks on Tab (`view_mode_changed` from
`PlayerController`, the single input authority — this contract stays).

Owner decision 13: **underground = flat X-Y plane view; surface = FOV
perspective.**

Plan:
1. Underground mode: tween pitch 55° → 80–85° (near-top-down plane) and
   dolly range → 3–10 (local area only, decision 14); FOV stays 45. Near-flat
   reads as the SteamWorld Dig plane while keeping the same perspective
   camera (no orthographic switch — keeps one projection, avoids edge cases
   with screen→world mapping in `player_commands._screen_to_world`).
2. Surface mode unchanged (55° dolly) — the TAB toggle keeps its current
   signal path; `_apply_view(underground, initial)` gets the mode tween.
3. Zoom range per decision 14: min dolly 3 (unit close-up), max 16 (local
   area; whole map only at 21:9). No further-out strategic zoom.
4. Camera shake stays minimal (decision 21): keep `add_shake()` but default
   strength halved; cave-in shake unchanged (it's informational).
5. Harness: the pilot drives `_focus`/`_dolly` directly (adapted in this
   PR) — R5 must keep those pseudo-public knobs or add
   `pose_camera(focus, dolly, pitch)` to the shell and switch the pilot to
   it.

## 4. Fog of war & darkness in 3D (phase R6)

Current: `fog_3d.gd` (169 lines) owns the fog treatment;
`terrain_3d.gd` writes per-vertex fog; proxies hide outside vision.

Plan:
1. Surface: keep per-vertex fog but move unexplored cells from "dark tint"
   to **true black-void** (`#10141C`) with a soft noise edge — the TAB
   surface view should read like They Are Billions' unrevealed map.
2. Underground: unexplored = near-black; explored-but-unlit = deep shadow
   (`#1C2029`); lantern radius = warm light pool (existing lantern
   PointLights + fog state). This is the SteamWorld Dig contract.
3. First wall breach (decision 19): one-shot presentation event — dust
   burst + brief ground-crack decal + camera nudge (minimal shake) at the
   wall cell, routed through `effects_3d.gd`'s existing budget.
4. Vision source of truth stays `GridWorld` fog maps (sim-owned); 3D only
   reads.

## 5. Structure GLB pipeline (phase R4)

Current: `structure_proxy_3d.gd` (594 lines) builds procedural models;
re-tint hook at `:171-179`.

Plan:
1. `model_manifest.gd` (autoload-free, `RefCounted`): path → footprint
   cells, height, accent slot names, glow slot names, per-quality fallback
   flag. Entries validated by `tests/test_3d_structure_models.gd`.
2. `structure_proxy_3d.gd`: when manifest has a GLB for the structure type,
   instance it (`PackedScene` from the imported GLB), normalize scale/origin
   per `02-asset-pipeline.md` conventions, rebind accent/glow materials,
   keep procedural recipes for Potato (`detail_enabled() == false`) and as
   damage-state bases.
3. Damage states (tilt/darken/rubble at `:434-452`) apply to imported models
   the same way (root rotation + dark overlay material).
4. Minas Morgul reveal: extend the `:171-179` re-tint to enable `glow_*`
   emissive + enemy banner trim on faction identification.

## 6. Performance budget (decision 24)

- 60 fps desktop, 200+ units, Fancy: textured structures are static
  (≈60k tris on screen worst case) — fine; unit blobs stay cheap until R7.
- Web (Compatibility): Standard preset; shadows off; texture budget
  ≤ 64 MB (`02-asset-pipeline.md` §convention 5).
- Harness frame times under llvmpipe are meaningless (README warning) —
  performance is verified on real hardware by the owner, screenshots by the
  harness.

## 7. Harness integration (this PR, R1)

- `tools/capture/capture_driver.gd` now swaps to `res://scenes/main_3d.tscn`
  on this branch (menu Play flow enters the shell; the driver must too).
- `tools/capture/capture_pilot.gd` drives the 3D rig: `set_view()` still
  toggles surface/underground through `PlayerController`, and poses address
  the shell's `_focus`/`_dolly` (custom pose = focus X:Y + dolly Z).
- New poses this PR: `zoomout` = full-map dolly; `surface` = focused surface
  dolly; weather poses unchanged (storm/volcano moods already tweened in
  `lighting_3d.gd`).
- Baseline captures from the branch pre-revamp are committed under
  `roadmap/3d-visual-revamp/baseline/` — the R2+ before/after reference.
- Note for R5: replace pilot's private-member access with the public
  `pose_camera()` API (§3.5).

## 8. Testing

- Extend `tests/test_3d_port.gd` / `test_3d_structure_models.gd`:
  height-field determinism (same seed → same heights), camera mode tween
  endpoints, manifest load/scale assertions, accent rebind correctness.
- Full GUT suite green per phase; exports green per phase; harness
  screenshots attached per phase.
