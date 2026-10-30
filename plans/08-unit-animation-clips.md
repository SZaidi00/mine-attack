# Plan 08 — Unit animation clips on R7 pivots

Status: Not started
Size: L
Depends on: 06 (pipeline conventions; clip sources re-use its acquisition notes)

## Mission
Upgrade units from procedural-only motion to real animation clips driven off
the R7 named-pivot contract, with guaranteed fallback behavior so every
quality tier and every unit kind keeps working with or without external clip
libraries.

## Context
- `scripts/three_d/unit_model_loader.gd::_collect_pivots` binds named pivots
  (`ArmL`, `ArmR`, `LegL`, `LegR`, `Tool`, `WingL`, `WingR`, `Tail` — set
  varies by unit kind; humanoids vs dragon vs pigeon vs crawler) and
  `apply_faction` toggles `Faction<Name>` node visibility for team variants.
  The generated unit GLBs already carry these pivot nodes.
- `scripts/three_d/unit_model_3d.gd` currently animates procedurally
  (movement yaw, attack aim, death topple + sink, undead tint, hit flash).
  `UnitProxy3D` owns placement/ground-snap; the model node lives under it at
  `PROXY_SCALE` 1.4 with counter-scaled accessories.
- Optional clip sources (all CC0, retarget by node-name onto the pivots):
  KayKit "Character Animations 1.1", Quaternius "Universal Animation
  Library". Availability is not guaranteed in the working environment — the
  fallback in Task 2 is a required deliverable, not a nice-to-have.
- House style for state-driven visuals: `unit_model_3d.gd` already resolves
  kind from `UnitData` flags (`_resolve_kind`); animation state should hang
  off the same states the procedural code uses (idle / move / attack / death
  — read the file for the exact state signals it reacts to).
- Budget/perf: clips add no textures (budget gate unaffected), but
  `AnimationPlayer` processing across ~200 units must respect the 60fps
  budget — change-detected updates only (the perf pass already early-outs
  fog-hidden/off-layer proxies).

## Task
1. Read `scripts/three_d/unit_model_3d.gd`, `scripts/three_d/unit_model_loader.gd`,
   `scripts/three_d/unit_proxy_3d.gd`, `tools/gen_unit_glbs.py`, and
   `tests/test_3d_unit_models.gd` first.
2. Implement the animation driver (all tiers, no external dependency):
   - At model build time, create an `AnimationPlayer` on the model root.
   - Author **programmatic clips** as keyframe tracks on the pivot nodes
     (GDScript `Animation` with `track_set_path` to the pivot node names) for
     a minimal set: `idle`, `walk`, `attack`, `death`. Start with miner +
     swordsman (humanoid pivot set); other kinds keep procedural behavior
     until their clips exist.
   - Map the existing procedural state signals to clip playback in
     `unit_model_3d.gd` (move → walk loop, attack → attack one-shot, death →
     death clip then the existing sink). Keep the procedural topple/flash/
     tint behaviors that have no clip equivalent.
   - Potato tier: keep clips (they're cheap) but verify with the BENCH harness;
     if a regression shows, gate playback to Standard+.
3. External clip import (best-effort, same acquisition rules as plan 06):
   - If a CC0 library is available, add `tools/retarget_clips.py` (or extend
     the loader) importing its GLB clips and retargeting tracks by pivot node
     name onto the house pivot set; unknown tracks are dropped with a logged
     warning, never guessed.
   - Document sources/licenses in the PR. If unavailable, ship Task 2 alone
     and record the library import as follow-up.
4. Tests (`tests/test_3d_unit_models.gd` extension or new file):
   - Miner/swordsman proxies expose an AnimationPlayer with the four clips.
   - Playing `walk` for 0.25 s changes at least one pivot's transform; the
     same pivot returns to base pose after the `idle` clip loops once.
   - Death: death clip plays and the existing sink still completes.
   - No-pivot/procedural models (Potato path, crawler/pigeon before their
     clips) behave exactly as before — regression-test one.
5. Visual verification: `tools/capture/run_capture.sh /tmp/shots`, inspect
   `units.png` / `units_underground.png` at two sim timestamps — posed
   differences visible between frames; iterate until true.
6. Docs: `AGENTS.md` `unit_model_3d.gd` paragraph — clip layer + fallback
   policy; roadmap pointer if a doc there tracks R-phases.

## Constraints
- The pivot contract is sacred: never rename pivots or change
  `Faction<Name>` visibility semantics; clips address pivots by name.
- Presentation-only, as always — animation reads unit state, never writes it.
- Fallback-first: with no external library present, miner + swordsman must
  still animate. A plan that only works with pack downloads is a failed plan.
- Keep procedural motion for anything without a clip; do not delete existing
  behavior, layer under it.
- `PROXY_SCALE` 1.4 and HP-bar counter-scaling are unaffected (animation runs
  inside the model root).

## Verification
```bash
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_3d_unit_models.gd -gexit
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
tools/check_model_budgets.sh
tools/capture/run_capture.sh /tmp/shots   # units poses, two timestamps
STRESS_UNITS=100 BENCH=30 SHOTS="" tools/capture/run_capture.sh /tmp/bench
```
Record BENCH numbers (unit-sync section) with animation on vs off; any
Standard-tier regression must be justified in the PR.

## Acceptance criteria
- [ ] AnimationPlayer with idle/walk/attack/death on miner + swordsman, GUT-verified
- [ ] State mapping works: move/attack/death trigger the right clips
- [ ] Procedural fallbacks intact for un-clipped kinds and Potato path (regression test)
- [ ] Capture shots show visibly posed units; two timestamps differ
- [ ] BENCH recorded; no unjustified perf regression
- [ ] Full GUT suite green; budget gate green
- [ ] PR documents clip provenance (authored vs imported) + licenses

## Out of scope
- Structure animations
- Root-motion / locomotion-driven movement (units still move via sim velocity;
  clips are in-place)
- Facial/expression work, LOD for animation
