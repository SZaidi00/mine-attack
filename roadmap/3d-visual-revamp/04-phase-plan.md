# Phase Plan — Implementation Order & Acceptance

Each phase is self-contained (repo convention): restates current state with
`file:line` refs, lists steps, defines acceptance. Judgment-heavy phases are
marked K3; mechanical ones K2.8 (see parent README §Model guidance).

## R1 — Harness 3D adaptation + baselines ✅ (this PR)

**Done in this PR:** driver swaps to `main_3d.tscn`; pilot poses the 3D rig;
baseline captures committed under `baseline/`.

Acceptance: captures render non-blank under opengl3 + llvmpipe; all five
poses (start / zoomout / underground / storm / volcano) land; GUT suite
green.

## R2 — Art tokens in code (palette + materials + mood retune) ✅ (accepted; final polish deferred)

**Model:** K3. **Depends:** R1.

Steps:
1. Re-skin `ArtStyle3D.PALETTE` + team/faction colors onto
   `01-art-direction.md` §Palette (values in one commit, screenshots in the
   PR — the before/after is the argument).
2. Retune `lighting_3d.gd` mood targets (overcast/storm/underground/
   volcano) to the new palette; clamp bloom so only warm sources glow.
3. Blob units: re-material onto new palette + keep rim.
4. Terrain colors re-graded (snow/rock/dirt rows).

Acceptance: harness before/after at identical poses shows the new palette;
units still pop; storm/volcano moods read; owner sign-off.

## R3 — Height-field surface with rolling snow dunes ✅ (implemented; captures pending)

**Model:** K2.8. **Depends:** R2.

Per `03-technical-plan.md` §2: deterministic height function, displaced
chunk meshes, ground-snapped proxies, structure/wall clearances, storm
flattening. Landed as `scripts/three_d/height_field.gd` — map-seeded value
noise + ridged dune bands (peaks ≤ 0.4 cells), bilinear structure clearances
(WALL cells + live structure groups), storm-driven relief flattening via the
terrain's snow tween; surface quads displace at the same vertex count, and
units/structures/rings/markers/decals/ghosts ground-snap through
`Presentation3D.ground_height()`. Tests: `tests/test_3d_height_field.gd`.

Acceptance: harness captures at start/zoomout show dunes; structures sit
clean; no sim test changes; GUT green; 200-unit scene renders on owner
hardware at 60 fps.

## R4 — Structure GLB pipeline + Minas Morgul fortress + player keep ✅ (implemented; captures pending)

**Model:** K2.8 (pipeline) + K3 (final look). **Depends:** R2.

Per `03-technical-plan.md` §5 using the starter GLBs from
`02-asset-pipeline.md`; manifest + budget script + tests; faction reveal
extends the `:171-179` hook. Landed as
`frost_mines_assets/models/model_manifest.json` (JSON source of truth shared
with `tools/check_model_budgets.sh`), `scripts/three_d/model_manifest.gd`,
and `scripts/three_d/structure_model_loader.gd` (scale/origin normalization,
per-proxy material duplication, accent/glow slot rebind);
`structure_proxy_3d.gd` builds the imported keep/fortress/tower/surface
lantern/headframe on Standard/Fancy with the procedural recipes kept as the
Potato fallback, `CapPivot`/`Rubble`/`LanternLight` contracts intact. The
starter GLBs ship one material with window glow baked into the albedo (no
emissive slot), so the pre-reveal "???" read damps the enemy base's body
color until identification; textures arrived 4096² and are downscaled to the
2048² import cap by `tools/resize_glb_textures.py` (verified by the budget
script, 16.7 MB total). Tests: `tests/test_3d_structure_models.gd`.

Acceptance: enemy fortress reads as Minas Morgul at default dolly; witch-glow
windows hidden until reveal; keep fits footprint; Potato fallback = existing
procedural recipes; budgets verified; GUT green.

## R5 — Two-mode camera (perspective surface / flat underground) ✅ (implemented; captures under `r5/`)

**Model:** K3. **Depends:** R2.

Per `03-technical-plan.md` §3: pitch/dolly tween per view mode; local-area
zoom limits; `pose_camera()` public API + pilot switch. Landed in
`scripts/three_d/main_3d.gd`: the surface keeps its 55° pitch and 3–16 dolly,
underground tweens to 82.5° with a 3–10 local-area dolly, and focus/pitch/
dolly glide between bookmarks in 0.25 s. `pose_camera()` cancels active
transitions and synchronously updates the camera; the capture pilot uses it
instead of private fields. Ordinary shake is halved while cave-ins retain
their informational impulse. Tests: `tests/test_3d_camera.gd`.

Acceptance: underground reads as a flat X-Y plane with light pools; surface
unchanged feel; Tab toggle smooth (<0.3 s); harness poses still land.

## R6 — Fog-of-war/darkness treatment + first wall breach ✅ (implemented; captures under `r6/`)

**Model:** K3. **Depends:** R3, R4.

Per `03-technical-plan.md` §4. `fog_3d.gd` now corner-averages full RGBA:
unexplored cells are opaque `#10141C`, remembered cells are deep-rock shadow,
and edge-only shader noise cannot reduce hidden opacity. `terrain_3d.gd` uses
matching fallback tints. Underground lanterns keep their warm OmniLights and
add a compatibility-safe radial ground pool at the sim vision radius. The
first terminal central-wall `cell_destroyed` signal triggers a per-shell
one-shot dust burst, fading crack decal, and reduced-motion-aware camera
nudge below cave-in strength. The capture harness gained deterministic
lantern-backed `underground` and `breach` poses. Tests:
`tests/test_3d_fog.gd`, `test_3d_effects.gd`, `test_3d_structure_models.gd`,
and `test_capture_driver.gd`.

Acceptance: unexplored reads as void at both views; breach moment plays
once, reads clearly, respects minimal-shake; GUT green.

## R7 — Unit model workshop ✅ (implemented; captures under `r7/`; owner/performance review pending)

**Model:** K3, with owner concept review. **Depends:** R4.

Landed as eight deterministic, sculpted/textured GLBs from
`tools/gen_unit_glbs.py` (1,033–2,526 tris each including every faction
attachment, 256² painted atlases), with the silhouette/pivot/material contract
and reusable prompts in `05-r7-unit-workshop.md`. `unit_model_loader.gd`
normalizes/grounds imports, duplicates per-proxy materials, rebinds
team/accent/glow slots, exposes named pivots to the existing sim-state
animator, and switches geometric Arcane/Brute/Industrial attachments on the
shared rig. Enemy attachments/accents stay neutral until faction
identification; undead retain the green material pass and Potato retains the
procedural recipes. `tests/test_3d_unit_models.gd` covers imports, budgets,
material isolation, variants/reveal, animation, and fallback. The capture
harness gained `units` / `units_underground` gallery poses; review captures
for all three player factions live under `r7/`.

Acceptance: every unit identifiable by silhouette at max local zoom in both
views; ≤8k tris/unit; 200-unit scene still 60 fps; owner sign-off. Structural,
capture, and triangle-budget checks are implemented; owner sign-off and
real-hardware 200-unit/60-fps validation remain external acceptance checks.

## R8 — UI restyle + screenshot pass ✅ (implemented; captures under `r8/`; owner review pending)

**Model:** K3 (restyle) + K2.8 (screenshot pipeline). **Depends:** R2–R7.

Landed as cold-glass panels, brass key-lines, amber alerts, and bundled OFL
Cinzel display type in `ui_theme_tokens.gd`; `ui_progress_dial.gd` provides
brass-ringed active-training and active-research loaders without changing
queue/pause behavior. The capture harness adds `base` / `dunes` / `fortress`
poses, configurable `RESOLUTION`, and `run_showcase.sh` for the six seeded
showcase moments at 1080p and 4K. Final PNGs live under `r8/1080p/` and
`r8/4k/`; the local macOS window clamp required normalizing the 4K exports to
3840×2160, while the Linux harness requests native 4K directly. Tests:
`tests/test_r8_ui.gd`, `test_capture_driver.gd`; full GUT suite 770/770,
model-budget gate, and Web/macOS/Windows/Linux exports all green.

Acceptance: a stranger wants to play from screenshots; exports all green.
Owner visual sign-off remains an external acceptance check.

## Standing rules per phase

- Presentation-only; presets all work; GUT green; exports green; harness
  screenshots in the PR; owner accept-and-iterate (decision 27).
