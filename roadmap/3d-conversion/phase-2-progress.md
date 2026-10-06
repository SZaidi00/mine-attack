# Phase 2 — Art Pass: implementation notes

Status: **implemented** (2026-10-05), pending visual sign-off (screenshots/playtest).

What landed, per §:

- **§2.1 Art direction** — `roadmap/3d-conversion/style-guide.md` (palette,
  silhouette rules, poly budgets, quality presets). Tokens in code:
  `scripts/three_d/art_style_3d.gd` (palette, faction accents, cached
  flat-shaded materials, primitive builders, `Quality` presets).
- **§2.2 Unit models** — `unit_model_3d.gd`: procedural low-poly rigs for
  every unit type (miner → crawler priority order honored), state-driven
  animation (idle bob / walk swing phased by real movement / attack lunge on
  the sim's cooldown timer / mine swing / death topple / hit flash), faction
  accent trims (Arcane violet, Brute red, Industrial brass), undead sickly
  tint. `unit_proxy_3d.gd` now renders models instead of sprite billboards.
- **§2.3 Terrain & structures** — terrain: per-cell sculpted heights
  (deterministic hash), border-wall ridges, emissive pulsing lava pass,
  snow cover accumulating/melting with snowstorms (`get_snow_level()`),
  MultiMesh ore crystals / lava embers / snow drifts
  (`terrain_detail_3d.gd`). Structures: building centerpiece with
  faction-reveal accents (grey "???" until `faction_identified`), tower/wall
  damage states (tilt, darken, rubble), lanterns as OmniLight3D heroes with
  tier-scaled radius/energy (`upgraded` signal), modeled mine-entry
  headframe, ladders, traps.
- **§2.4 Lighting & mood** — `lighting_3d.gd`: overcast base, underground
  gloom (lava-flood warm tint), snowstorm dim, volcano red-orange cast;
  tweens at 2/s; shadows/fog gated on Fancy.
- **§2.5 Effects** — `effects_3d.gd`: underground dust motes, wind-swept
  storm snow, volcano embers, cave-in dust bursts (pooled); camera shake on
  cave-ins/lava rise in `main_3d.gd` (reduced-motion aware).
- **§2.6 Audio-visual** — `AudioListener3D` on the camera rig; the sim's
  positional `AudioStreamPlayer2D` pool pans against the live 2D camera,
  which mirrors the rig, so positional audio stays correct. `audio_manager.gd`
  untouched, as specified.
- **§2.7 Performance** — `ArtStyle3D` presets: Potato (no shadows, 35%
  particles, no decorative detail) / Standard (web default) / Fancy (desktop
  default). Ore crystals via `MultiMeshInstance3D`; decorative detail gated
  per-preset. 200+ units: models are ≤ ~25 primitives with shared cached
  materials; far-dolly LOD = detail gating (documented in the style guide).

Verification: full GUT suite green (including new `test_3d_unit_models`,
`test_3d_structure_models`, `test_3d_terrain_art`, `test_3d_lighting`,
`test_3d_effects`); headless 600-frame run of `scenes/main_3d.tscn` clean.

Known follow-ups:

- Visual sign-off needs real screenshots — run the editor/player and eyeball
  surface/underground/storm/volcano moods (headless can't render).
- Death topple is cut short by the proxy reconcile cull (~0.2–0.4 s of the
  0.5 s animation is visible); extending it needs an `entity_proxies_3d.gd`
  grace-period change (deliberately out of scope).
- No runtime UI for switching quality presets (auto-detect only: web →
  Standard, desktop → Fancy).
