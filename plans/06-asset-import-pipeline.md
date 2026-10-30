# Plan 06 — Prop GLB import pipeline + first batch

Status: Done (2026-10-30, branch kimi-code-plans)
Size: M
Depends on: 03 (budget gate must be enforced; this plan adds entries)

## Mission
Extend the R4/R7 model pipeline from structures/units to a third category —
surface **props** — and land a first batch of prop GLBs (manifest-registered,
budget-green) ready for plan 07's scatter system.

## Context
- Manifest: `frost_mines_assets/models/model_manifest.json`, validated by
  `scripts/three_d/model_manifest.gd`. Per entry: `key`, `path`, `origin`
  (center|corner), `footprint` (w,h > 0), `height` (> 0), `tri_gate` (∈
  [6000, 8000, 12000, 25000, 60000]), slot arrays. The Godot loaders and
  `tools/check_model_budgets.sh` both read the same file — it is the single
  source of truth.
- Loaders: `scripts/three_d/structure_model_loader.gd` (AABB scan, uniform
  scale to footprint XZ binding, wrapper "Model" node with min-y at 0, XZ
  centered, per-proxy material duplication, warn+recenter when origin isn't
  at base) and `scripts/three_d/unit_model_loader.gd` (team/accent/glow
  slots matched by lowercase material-name substring, `_collect_pivots`
  named-pivot contract). Props need only the structure-style path minus
  gameplay — a plain loaded model is enough for plan 07.
- House GLB workshop: `tools/gen_unit_glbs.py` deterministically writes
  textured GLBs in pure Python (embedded PNG atlas, glTF 2.0, no external
  URIs, PBR convention metallic 0 / roughness 0.92) and self-validates
  (triangle bounds, base min-y == 0, height bands, unit normals). Read it
  before writing anything — `GLBWriter`/`validate()` are the templates.
- Budget gate: `tools/check_model_budgets.sh` (per-entry `tri_gate`, ≤2048²
  per image, 64 MB total embedded textures). `tools/resize_glb_textures.py`
  downsizes over-cap embedded textures.
- Reference packs (all CC0, same flat-color stylized family as the house
  units): Quaternius "Stylized Nature MegaKit" / "Medieval Village MegaKit",
  Kenney "Survival Kit". These are *optional inputs* — see Task.

## Task
1. Read `tools/gen_unit_glbs.py`, `scripts/three_d/model_manifest.gd`,
   `scripts/three_d/structure_model_loader.gd`, and the manifest JSON first.
2. New tool `tools/gen_prop_glbs.py`, modeled directly on `gen_unit_glbs.py`
   (reuse its GLBWriter approach; do NOT import from it — keep tools
   standalone): generate a first prop batch, deterministic, no external URIs,
   painted 256² atlases, PBR convention identical to house GLBs:
   - `prop_boulder` (~150–400 tris), `prop_pine` (~200–500),
     `prop_stump` (~100–250), `prop_crate` (~100–200).
   - Output to `frost_mines_assets/models/props/`. Base min-y == 0, height
     bands you choose and document (props ≈ 0.15–0.45 world units at
     `WORLD_SCALE` 0.01 — read how structures' heights relate to `CELL 0.32`
     before picking bands).
   - `--validate-only` mode like the unit tool. Print a per-prop report line.
3. If CC0 packs are downloadable in the working environment, ALSO (not
   instead) import 2–3 pack props into `frost_mines_assets/models/packs/`
   (document exact source + license in the PR; strip external texture URIs by
   re-embedding or run them through the resize tool). If not downloadable,
   state that in the PR and ship the generated batch — the pipeline, not the
   provenance, is the deliverable.
4. Register every prop in `model_manifest.json` with unique keys
   (`prop_boulder`, ...), `origin: "center"`, real measured footprint/height,
   and the LOWEST valid `tri_gate` that passes (6000 unless a pack prop
   genuinely exceeds it). Run `tools/check_model_budgets.sh` until PASS —
   with plan 03 landed this gate is push-blocking, so it must be green.
5. Loading smoke test: extend `tests/test_3d_structure_models.gd` (or a new
   file) asserting `ModelManifest.validate()` accepts the new entries and that
   `StructureModelLoader` instantiates each prop within footprint budget and
   with min-y at 0 — follow the existing manifest-validation test pattern.
6. Docs: `AGENTS.md` tools paragraph — `gen_prop_glbs.py` exists and what it's
   for; manifest conventions unchanged.

## Constraints
- Never weaken `ModelManifest.validate()`, the gate script, or manifest data to
  force a pass.
- Every GLB must pass the same conventions the unit workshop enforces:
  embedded textures only, glTF 2.0, unit normals, metallic 0 / roughness 0.92,
  base at min-y 0. `--validate-only` must fail a deliberately corrupted copy
  (test this locally).
- Do NOT wire props into gameplay/scatter yet — that is plan 07.
- Generated props must be visually consistent with the house style: read
  `roadmap/3d-conversion/style-guide.md` and sample the existing unit/structure
  GLB palette before choosing colors.

## Verification
```bash
python3 tools/gen_prop_glbs.py
python3 tools/gen_prop_glbs.py --validate-only
tools/check_model_budgets.sh
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_3d_structure_models.gd -gexit
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
# Visual: props are not yet placed in the world, so verify geometry/materials
# via the loading test; plan 07 adds screenshot verification.
```

## Acceptance criteria
- [ ] `gen_prop_glbs.py` generates + self-validates ≥4 prop kinds; `--validate-only` catches a corrupted copy
- [ ] All props registered in the manifest; `tools/check_model_budgets.sh` PASS
- [ ] GUT loading test covers every new entry
- [ ] PR documents prop sources/licensing (generated vs pack)
- [ ] Full GUT suite green

## Out of scope
- Scattering props into the world (plan 07)
- Prop LODs, collision, or interaction
- Structure/unit model replacement
