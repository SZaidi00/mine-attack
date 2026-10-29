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

## R5 — Two-mode camera (perspective surface / flat underground)

**Model:** K3. **Depends:** R2.

Per `03-technical-plan.md` §3: pitch/dolly tween per view mode; local-area
zoom limits; `pose_camera()` public API + pilot switch.

Acceptance: underground reads as a flat X-Y plane with light pools; surface
unchanged feel; Tab toggle smooth (<0.3 s); harness poses still land.

## R6 — Fog-of-war/darkness treatment + first wall breach

**Model:** K3. **Depends:** R3, R4.

Per `03-technical-plan.md` §4: black-void unexplored surface, lantern-lit
underground pools, breach moment.

Acceptance: unexplored reads as void at both views; breach moment plays
once, reads clearly, respects minimal-shake; GUT green.

## R7 — Unit model workshop

**Model:** K3, with owner concept review. **Depends:** R4.

Blobs → sculpted GLBs per the R7 silhouette table (written when this phase
starts, superseding `roadmap/3d-conversion/style-guide.md`'s primitive
table). Generation prompts per `02-asset-pipeline.md` §Next-generation
manifest. Faction variants on shared skeletons.

Acceptance: every unit identifiable by silhouette at max local zoom in both
views; ≤8k tris/unit; 200-unit scene still 60 fps; owner sign-off.

## R8 — UI restyle + screenshot pass

**Model:** K3 (restyle) + K2.8 (screenshot pipeline). **Depends:** R2–R7.

HUD restyle per `01-art-direction.md` §UI; then the decision-22 pass:
seeded harness captures at the game's best moments (surface base at dawn-
overcast, dune field, underground lantern pools, storm, volcano, Minas
Morgul reveal) exported at 1080p/4K for store pages.

Acceptance: a stranger wants to play from screenshots; exports all green.

## Standing rules per phase

- Presentation-only; presets all work; GUT green; exports green; harness
  screenshots in the PR; owner accept-and-iterate (decision 27).
