# Phase 2 Style Guide — Frost Mines 3D art direction

One-pager governing every 3D asset decision (roadmap §2.1). All tokens live in
code: `scripts/three_d/art_style_3d.gd`.

## Look

**Flat-shaded stylized low-poly.** Untextured primitives with flat albedo
colors, roughness 1.0, lambert shading. No texture maps, no PBR maps, no
real-time GI (SSAO + tuned ambient only, Fancy preset). This reads cleanly at
RTS zoom distances and keeps the web build cheap.

Mood: cold, post-apocalyptic, Frostpunk-adjacent. Overcast base light;
weather is the drama.

## Palette

| Role | Color | Notes |
|---|---|---|
| Snow / ice surface | `#EEF4F8` / `#DCECF5` | cold blue-grey desat |
| Deep ice / shadow | `#3E5A6E` | distance fog, crevices |
| Rock / coal | `#4A4F57` / `#1E1E23` | underground mass |
| Dirt layers | `GameManager.COLOR_DIRT_1..3` | deeper = darker/warmer |
| Ore | `#C45C26` rust → `#F0B23C` bright | tier brightness by richness |
| Lava | `#E8380D` emissive | always emissive, pulses |
| Necromancy | `#9EDF9E` sickly green | undead tint only |
| Wood / steel | `#5C4229` / `#5A6570` | structures, mine supports |

## Faction accents (material trims, banners, lamps)

- **Arcane** — violet `#8C5CF6`
- **Brute** — red `#DC2626`
- **Industrial** — brass `#C9A227`

Bodies stay team-colored (player blue / enemy red). The accent is the
identifier. Enemy faction accents stay neutral grey `"???"` until
`FactionManager.is_faction_identified(ENEMY)` — the reveal is already a game
mechanic, the art honors it.

## Silhouette rules (must read at max zoom-out)

| Unit | Signature shape |
|---|---|
| Miner | rounded body + **pickaxe** + glowing helmet lamp |
| Swordsman | upright + long **sword** blade |
| Archer | slim + **bow** arc |
| Wizard | wide-brim **pointed hat** + staff |
| Dragon | big wingspan, **wings + tail**, flies |
| Pigeon | tiny, flapping wings, fast bob |
| Engineer | **backpack + wrench**, no weapon |
| Crawler | low, long, spiky (underground) |
| Undead | same skeleton as troops, sickly green tint |

Structures: the building is the centerpiece (tall, banner, faction-trimmed);
towers are squat cylinders with a cap; walls are chunky segments; lanterns
are thin posts with a warm glowing head — the dynamic-light heroes.

## Texel density / poly budget

- No textures → texel density N/A; color-block fidelity instead.
- Units: ≤ 60 primitives each, target < 1k tris; decorative detail gated
  behind `ArtStyle3D.detail_enabled()` (hidden on Potato).
- Terrain: chunked mesh, one draw per chunk + one emissive pass for lava;
  ore crystals via `MultiMeshInstance3D`.
- Budget: 60 fps desktop with 200+ units; LOD = decorative detail off +
  limb-swing amplitude reduction at far dolly, not mesh swapping.

## Quality presets (§2.7)

| Preset | Shadows | Particles | Decorative detail |
|---|---|---|---|
| Potato | off | 35% | off |
| Standard | off | 70% | on |
| Fancy | on | 100% | on |

`ArtStyle3D.apply_quality()` is the single switch; desktop defaults to Fancy,
web to Standard (`auto_detect_quality()`).

## Animation

Procedural, driven by sim state (never writes sim): idle breathing bob, walk
limb-swing phased by actual movement, attack lunge keyed on the sim's attack
cooldown timer, mine swing on the sim's swing timer, death topple on `died`.
Juice (§2.5): camera shake on cave-ins, hit-stop already exists, dust motes
underground, storm snow drift, volcano embers.
