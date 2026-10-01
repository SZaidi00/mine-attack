# Phase 2 — The Art Pass (make it beautiful)

**Goal:** replace billboarded pixel art with a coherent low-poly 3D look
and lean into the cold, post-apocalyptic Frostpunk-adjacent mood.
Ships as a headline release.

Prerequisite: Phase 1 shipped and stable.

## 2.1 — Art direction first (before any modeling)

- Write a one-page style guide: palette (cold blues/greys surface, warm
  ore oranges, sickly necromancy greens), silhouette rules per unit
  type, texel density, poly budget targets.
- Decide: stylized low-poly with flat colors + gradient ambient, or
  textured low-poly. Flat-shaded stylized is cheaper and reads better
  at RTS zoom.
- Rule: a unit must be identifiable by silhouette at max zoom-out.

## 2.2 — Unit models, in priority order

1. **Miner** — seen most; sets the bar.
2. **Swordsman / Archer** — the bread-and-butter army.
3. **Wizard / Dragon / Pigeon** — signature silhouettes.
4. **Crawler / Engineer** — new units; generated sprites were always
   placeholders, so there's no legacy art to mourn.
5. **Undead variants** — palette-swapped materials on soldier/archer/
   dragon models (desaturated/sickly tint), matching the current 2D
   approach.

Each unit: model + idle/walk/attack/death animations wired to the
existing state machine signals. Faction identity via material accents
(Arcane violet, Brute red, Industrial brass).

## 2.3 — Terrain & structures

- Terrain: from flat GridMap cells to sculpted meshes per archetype
  (fractured / standard / fortress wall profiles already exist as seed
  knobs — `MAP_WALL_HP_MULTS`, `MAP_ORE_CURVES`).
- Snow cover on surface cells that accumulates during storms and melts
  after — pure visual, driven by `weather_manager` signals.
- Structures get real models: the building as the centerpiece (make the
  faction choice visible on the enemy base — it reveals on scout,
  which is already a mechanic), towers, walls with damage states.
- Lanterns become the dynamic-light heroes (see 2.4).

## 2.4 — Lighting & mood (the Frostpunk payoff)
- Time-of-day-neutral but weather-reactive lighting: overcast base,
  storm scenes drop ambient and add wind-blown snow, volcano events
  cast red-orange from above, lava floods tint the underground.
- Lanterns as real dynamic lights with three tiers of radius/color —
  their vision upgrade now *looks* like an upgrade.
- Cheap global illumination: baked lightmaps if the map is static
  enough, else SSAO + good ambient. No real-time GI at RTS scale.

## 2.5 — Effects upgrade
- Replace Phase 1 placeholder particles with art-directed versions.
- Add juice that costs nothing gameplay-wise: screen shake on cave-ins,
  hit-stop on dragon crush, dust motes underground.

## 2.6 — Audio-visual sync check
- `audio_manager.gd` stays as-is; verify 3D positional audio
  (`AudioStreamPlayer3D`) for mining clinks, combat, and weather so the
  underground feels properly claustrophobic.

## 2.7 — Performance gate
- Budget: 60fps desktop with 200+ units on screen; web build degrades
  gracefully (documented settings presets: Potato / Standard / Fancy).
- LODs or imposters for units at zoom-out. `MultiMeshInstance3D` for
  ore/rock/lava cells.

## Definition of done

Screenshots of the 3D game make someone want to play it. All tests still
green; all gameplay numbers identical to the 2D version.
