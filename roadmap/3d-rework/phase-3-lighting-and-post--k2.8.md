# Phase 3 — Lighting & Post-Processing

**Parent plan:** `roadmap/3d-rework/README.md` (read it first for rules).
This is the "make screenshots sell the game" phase: bloom, tonemapping, lit
terrain, real depth cueing.

## Current state (verified)

- `scenes/world_3d.tscn:6-23`: WorldEnvironment with background color
  (0.04, 0.055, 0.07), flat ambient (0.32, 0.38, 0.46) @ 0.5. **No glow, no
  tonemap (default Linear), no SSAO/SSIL, no fog, no sky.** One
  DirectionalLight3D (0.82, 0.87, 0.96) @ 1.1, **shadows off in the scene**.
- `scripts/three_d/lighting_3d.gd`: shadows enabled only on Fancy (:75);
  depth fog only on Fancy, color (0.09, 0.11, 0.15), density 0.012 — over a
  26-unit map that's nearly invisible (:79-81). Mood system tweens between
  overcast/underground/storm/volcano targets (:22-47).
- **Terrain albedo pass is UNSHADED** (`scripts/three_d/terrain_3d.gd:62-65`)
  — it ignores sun, ambient moods, and fog, and **cannot receive shadows**.
  All the mood lighting only affects units/structures/props. The separate
  emissive lava glow pass (terrain_3d.gd:66-68) is fine and stays.
- Emissive accents already exist (miner lamps @2.2, wizard orbs @1.8, dragon
  eyes, lantern heads @1.4, lava pulse 0.7→1.6) but nothing blooms.
- Quality presets: Potato/Standard/Fancy switch shadows, particle counts,
  decorative detail (`scripts/three_d/art_style_3d.gd:56-77`).

## Goals

1. **Glow/bloom** (`Environment.glow_enabled`): threshold low enough that
   only real emissives bloom (~1.0), strength subtle (SC2 bloom is a halo,
   not a smear). Gate: Standard and Fancy ON, Potato OFF. This single change
   transforms lanterns, lava, wizard orbs, and tracer projectiles (phase 1).
2. **Tonemapping:** ACES (or AgX on 4.7) with slight exposure compensation;
   whitepoint tuned so snow (#EEF4F8) stays snow and doesn't clip. Verify
   team colors still read — ACES desaturates brights, so phase 4 may need to
   re-saturate.
3. **Lit terrain.** Switch the terrain albedo pass from unshaded to a lit
   `StandardMaterial3D` with `vertex_color_use_as_albedo`
   (`terrain_3d.gd:62-65`), roughness 1.0. This makes the ground receive the
   mood system, directional shadows, and fog. Risks to handle: vertex-color
   fog-of-war darkening must still work (it will — it's baked into vertex
   colors), and terrain normals must be sane after height sculpting (they
   are — check the normal generation in terrain_3d.gd).
4. **Shadows that land:** with terrain lit, DirectionalLight3D shadows now
   matter on the ground. Fancy: shadows on (already wired,
   `lighting_3d.gd:75`); tune shadow distance to cover the visible board,
   not the whole map. Keep blob shadows as the Standard/Potato fallback.
5. **Depth cueing at every tier:** fog is Fancy-only today — move a cheap
   version to all presets (fog is nearly free). Increase density enough to
   actually separate near/far board edges (start ~0.02 and eyeball). Keep
   the Fog-of-War darkening visually distinct from atmospheric fog — one
   hides information, the other adds depth; playtest that they're not
   confused.
6. **SSAO on Fancy only** (`Environment.ssao_enabled`), gentle radius;
   measure fps on the 200-unit stress case.

## Non-goals

- No palette changes (phase 4), no new VFX (phase 5), no baked lightmaps
  (map is dynamic — lava/cave-ins change it).

## Steps

1. `world_3d.tscn`: enable glow + tonemap + SSAO (SSAO default off; toggled
   by quality).
2. Extend `ArtStyle3D.apply_quality()` with the new toggles:
   glow (Standard+), SSAO (Fancy), fog (all), shadow distance tuning.
3. Flip terrain material to lit vertex-color albedo; delete nothing — keep
   the unshaded path behind a const for easy A/B.
4. Retune `lighting_3d.gd` mood targets after tonemapping lands (ambient
   energies will feel different under ACES; the underground mood
   (sun @0.4, ambient @0.22) likely needs a lift).
5. Playtest all four moods + snowstorm + volcano + lava flood; screenshot
   each for before/after.
6. Update `AGENTS.md` (three_d description) and the style guide's quality
   preset table (`roadmap/3d-conversion/style-guide.md`).

## Acceptance criteria

- Lanterns, lava, and emissive accents visibly bloom on Standard/Fancy;
  Potato unchanged in fps.
- Terrain darkens under storm mood and tints under volcano/lava moods;
  shadows from keeps/towers land on the ground on Fancy.
- Fog-of-War unexplored cells remain unmistakably "hidden" vs merely
  "far away".
- Full test suite green
  (`godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests
  -gexit`); extend `tests/test_3d_lighting.gd` for the new quality toggles.
- 60 fps with 200+ units on Fancy; Standard stays above 60 on a mid GPU.
