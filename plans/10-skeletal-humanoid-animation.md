# Plan 10 — Skeletal humanoid animation

Status: Done (2026-10-31, branch kimi-code-plans)
Size: L
Depends on: 08, 09

## Mission

Replace the five humanoids' rigid-pivot-only presentation with curated,
professionally authored skeletal models and clips. Keep simulation ownership,
unit scale/readability, material/faction semantics, and every existing fallback.
World expansion remains the following phase.

## Asset decision

Use the official, free **KayKit Adventurers** characters and **KayKit Character
Animations 1.1** as a compatible pair: Knight/swordsman, Ranger/archer,
Mage/wizard, a free humanoid plus pickaxe/miner, and Engineer (or a free
humanoid plus wrench/backpack if Engineer is not in the downloaded free tier).

Official sources:
- https://kaylousberg.itch.io/kaykit-adventurers
- https://kaylousberg.itch.io/kaykit-character-animations
- Optional CC0 hand tools: https://kaylousberg.itch.io/rpg-tools-bits

KayKit advertises matching `Rig_Medium` characters/clips and native mining,
bow, spell, and work animations. Quaternius UAL uses a different rig; its
in-place exports remain a possible later source after an editor-time BoneMap /
SkeletonProfileHumanoid retarget. Do not add a fragile runtime retargeter or
make UAL a prerequisite for this slice. Prefer explicitly in-place clips;
otherwise remove only the inspected root-motion track in a repeatable import,
never arbitrary bone tracks. Use exact clip names discovered in the archives,
not names guessed from product listings.

## Implementation

1. **Acquire, inspect, and curate the licensed sources.**
   - Use the official no-cost download flows into ignored, `.gdignore`d
     `build/asset_staging/`; never bypass a purchase or access gate. Inspect
     included license files, rig/rest pose, actual clip names, source scale,
     facing, mesh bounds, materials, and triangle counts before integration.
   - Curate only the required characters, props, and clips into self-contained
     GLBs under `frost_mines_assets/models/packs/`. Keep raw packs and whole
     animation collections out of exports. Reuse/extend the standard-library
     GLB tooling only where native import is insufficient; preserve skins,
     inverse bind matrices, and matching native animation tracks. No new
     package dependency or guessed cross-rig bone-name conversion.
   - Record archive/source/final hashes, processing, exact clip aliases, and
     included CC0 notices in `packs/SOURCES.md` and pack license files. Register
     each visual model in `model_manifest.json` without weakening the existing
     8,000-triangle or texture gates; downscale atlases appropriately with the
     existing resize tool.

2. **Add an optional native skeletal path, not a replacement rig contract.**
   - Extend `UnitModelLoader` to return a skeletal model contract alongside
     the existing root/instance/material/pivot contract: validated Skeleton3D,
     compatible imported AnimationPlayer/library, normalized grounded wrapper,
     and explicit facing correction if visual inspection requires it.
   - Copy or reference only imported clips under stable aliases (`idle`,
     `walk`, `attack`, `mine`, `repair`, `death`), configure looping, and set
     `ANIMATION_PROCESS_MANUAL`; hidden proxies must remain cheap. Validate a
     real skeleton and required clip set before selecting this path.
   - Handle bind-pose/skinned-mesh bounds deliberately; the current static
     MeshInstance AABB scan is not sufficient proof of correct animated
     grounding. Preserve the manifest's height/footprint and HP-bar contract.
   - On missing/invalid assets, skeletons, or clips, retain the generated GLB,
     `UnitAnimationClips` named-pivot path, or existing procedural motion as
     applicable. Potato and dragon/pigeon/crawler must not regress.

3. **Drive authored motion from the existing simulation states.**
   - Extend `UnitModel3D.sync_animation()` to choose idle/walk/role action/death
     clips without writing any unit state or advancing hidden players.
   - Use `Unit.State.MINE` for a real pickaxe loop, `ATTACK` for the appropriate
     melee/bow/spell clip, and `REPAIR` for engineer work. Continue walking
     while repair/mining commands are still traversing their paths. Aim mining
     with `_mine_target_angle`; preserve attack-target yaw and sim-derived
     locomotion. No root motion may move the proxy.
   - Scale action playback to `data.attack_cooldown` and
     `data.mining_swings_per_sec`; reset one-shots on actual timer/state edges
     rather than every frame. Use the actual repair target for facing and keep
     repair/idle behavior correct during lockout or insufficient coin.
   - Preserve death sink/cleanup, hit flash, undead tint, per-instance material
     isolation, colorblind team colors, faction reveal, and all `Faction<Name>`
     visibility semantics. Curate garment/accent material slots rather than
     recoloring the whole shared atlas (skin and equipment must remain legible).
     A hidden enemy faction must not leak through a unique attachment.

4. **Add executable coverage and useful visual poses.**
   - Expand `tests/test_3d_unit_models.gd` and add focused manifest/skeletal
     tests as needed: real Skeleton3D and bound skins, exact required clips,
     loop settings, manual advancement, bone-pose changes, no locomotion track,
     action timing/restart, mining and repair state selection, grounding and
     facing, material/faction/undead/flash behavior, and all fallbacks.
   - Test the real loader and live proxy sync, not only resource imports. Keep
     existing generated-model tests to prove backward compatibility.
   - Extend the presentation-only capture lineup with deterministic humanoid
     action poses (including mining and repair), without enabling unit AI or
     changing match rules. Inspect surface and underground galleries at more
     than one timestamp, plus Standard/Fancy/Potato comparisons; check feet,
     hand/tool attachment, silhouette, clipping, team readability, and no
     skating/root drift.

5. **Verify, measure, and document.**
   - Record a current-code Standard 200-unit BENCH before comparison; the
     previous slice's reference `unit_sync` was 0.797 ms, not a current run.
     Compare the same seeded 30-sim-second load after integration, investigate
     regressions, and do not claim hardware 60-fps certification from captures.
   - Run focused GUT, `tools/check_model_budgets.sh`, full `tools/run_checks.sh`,
     and `git diff --check` on the deliverable. Use the macOS OpenGL capture
     driver and isolated capture settings, not the user's real settings.
   - Save this plan as `plans/10-skeletal-humanoid-animation.md`, update its
     status/verification only from actual results, and synchronize
     `plans/README.md`, `AGENTS.md`, and the style guide's animation/material
     sections. Keep map dimensions, monster replacements, and broad retargeting
     explicitly out of scope.

## Acceptance criteria

- [x] Five humanoids use inspected, licensed skeletal models and appropriate
      native clips on Standard/Fancy; no paywalled content is required.
- [x] Mining, melee/ranged/magic attacks, and engineer repair are visibly
      distinct and synchronized to simulation timing without root motion.
- [x] Generated/pivot/procedural fallbacks, Potato, non-humanoids, faction
      reveal, team/accent/glow, undead, hit flash, and death behavior survive.
- [x] Focused and full tests, budget gate, and whitespace checks pass.
- [x] Action galleries are visually inspected and current BENCH results recorded.
- [x] Exact asset provenance and project documentation are updated.

## Reviewed contracts

- `unit_model_loader.gd`: manifest, normalization, material/pivot discovery.
- `unit_animation_clips.gd`: original four-clip rigid-pivot fallback.
- `unit_model_3d.gd`: presentation-only state/timing/yaw/death driver.
- `unit_proxy_3d.gd`: manual visible-only advancement, ground snap, HP scale.
- `unit.gd`, `unit_mining.gd`, `unit_repair.gd`: actual states and countdowns;
  `REPAIR` is a real state, not just an attack alias.
- `tools/capture/capture_pilot.gd`: idle and deterministic action galleries.
- `ModelManifest` + `tools/check_model_budgets.sh`: shared asset/budget gate.

## Implementation notes

- Official free KayKit Adventurers 2.0, Character Animations 1.1, and RPG
  Tools Bits 1.0 provide the five humanoids and hand tools. Included CC0
  licenses, source/final hashes, and exact clips are recorded in
  `frost_mines_assets/models/packs/SOURCES.md`. Quaternius UAL was not imported
  because its rig differs; matching native `Rig_Medium` sources avoid runtime
  retargeting and paid Extra-tier content.
- `tools/curate_skeletal_units.py` curates self-contained GLBs, preserves native
  skins and in-place clips, trims mining/repair cycles, validates required bones
  and no root translation, and merges body parts into one skinned mesh per unit
  without changing triangle counts. Atlases are capped at 512² and every model
  remains below 8,000 triangles. Generated models remain registered fallbacks.
- `UnitModelLoader` selects the optional skeletal contract on Standard/Fancy;
  `UnitSkeletal3D` validates the rig and mounts tools, signature glow, backpacks,
  and faction badges. Garment-region shaders preserve skin/equipment colors,
  per-instance materials, faction reveal, and undead tint. Legacy pivot clips
  and procedural non-humanoids/Potato behavior remain intact.
- The presentation-only driver reads actual unit states, paths, targets, and
  timers. It includes native mining and repair, travel detection, attack and
  mining cooldown scaling, explicit one-shot restart, visible-only manual
  advancement, and death sink without a duplicate topple. Capture galleries add
  deterministic role actions without enabling frozen unit AI.
- An initial unmerged stress capture timed out at 300 seconds. A five-second
  diagnostic took 84.258 seconds; merging the skinned body draws reduced the
  same diagnostic to 26.518 seconds. The final 30-sim-second OpenGL Standard
  stress run then completed in 128.879 seconds with 1,846 samples:
  `unit_sync` 1.167 ms (baseline 0.797 ms), `sim_fog_recompute` 7.899 ms,
  `ring_hover_scan` 0.093 ms; `terrain_rebuild` 3.348 ms over 51 batches,
  `terrain_scatter` 0.607 ms over 105 chunks, `fog_rebuild` 2.576 ms. These
  are script timings and capture wall times, not a 60-fps hardware claim.
- Visual review covered Standard and Fancy action galleries at distinct
  timestamps, underground views, and Potato fallback. Final images are in
  ignored `build/captures/skeletal-final/` and
  `build/captures/skeletal-final-fancy/`; isolated capture profiles avoided
  changing the user's graphics settings.

## Out of scope

- Surface rows, width, base/mine placement, and underground-depth changes.
- Monster-pack replacements and broad Quaternius/retargeting support.
- Runtime root motion, simulation changes, or animation-driven combat outcomes.

## Verification

- Final `tools/run_checks.sh`: PASS — 77 scripts, 818 tests, 8,531 assertions.
  Model budget: 8,903,080 bytes (8.5 MB) of the 64 MB embedded-texture limit.
  `git diff --check`: PASS; Python curator compilation and `--validate-only`
  pass for all five GLBs with the documented final hashes and triangle counts.
- Focused GUT: skeletal 8/8 (153 assertions), legacy unit models 19/19,
  capture parsing 10/10, props 3/3. Native clip restart, mining/repair,
  root stability, material isolation, undead reveal, and death sink are covered.
- Final Standard captures at 5.33 and 6.58 sim-seconds plus the underground
  gallery were inspected in `build/captures/skeletal-final/`; the final Fancy
  gallery was inspected in `build/captures/skeletal-final-fancy/`. Potato was
  also rendered and retains the procedural models. No script errors occurred.
- Final optimized 200-unit BENCH: 1,846 samples, `unit_sync` 1.167 ms versus
  the measured pre-skeletal 0.797 ms. Other probe numbers and the earlier
  unmerged/merged diagnostic comparison are in Implementation notes above.
- The known fog-diff warnings, two GUT warnings, one deprecation, and
  exit-time ObjectDB leak warnings remain; the suite exits successfully.


