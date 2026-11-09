# Phase 2 Style Guide — Frost Mines 3D art direction

One-pager governing every 3D asset decision (roadmap §2.1). All tokens live in
code: `scripts/three_d/art_style_3d.gd`.

## Look

**Flat-shaded stylized low-poly.** Procedural fallbacks use flat albedo
colors; imported units, structures, and curated props use small painted
atlases with metallic 0 / roughness 0.92. Terrain combines lit vertex-color
cell/fog grading with a subtle world-triplanar detail texture on Standard+.
No real-time GI (SSAO + tuned ambient only, Fancy preset). This reads cleanly
at RTS zoom distances and keeps the web build cheap.

Mood: cold, post-apocalyptic, Frostpunk-adjacent. Overcast base light;
weather is the drama. Distant ground, ridges, and pine silhouettes frame the
battlefield without entering playable cells; backdrop detail stays subdued.

Roads use compacted cold-gray snow (`ArtStyle3D.PALETTE.compacted_snow`), never
brown dirt. `MapDefinition.surface_roads` and `surface_regions` author the
front road, mine spurs, western pinewood, and eastern rockfield. Roads suppress
scatter; region recipes restrict existing tree/rock families without changing
collision. Region/road vertex tints apply before fog, so hidden cells remain
opaque void and remembered cells keep their shadow treatment. Potato keeps the
color composition while dropping decorative props.

## Underground & mine (Plan 13)

The underground reads as a flat X-Y plane, never vertical 3D — excavated
space is a readable floor, tunnels stay top-down, and presentation never
writes the sim grid.

- **Excavated floors** — mined-out cells get presentation-only floors in the
  cold shallow/mid/deep depth-strata tokens, with sparse deterministic seam
  décor (lifts stay under the lava glow pass and the fog overlay).
- **Fog is authoritative** — floors inherit normal-cell fog tint semantics;
  unexplored cells stay the opaque void and remembered cells keep their
  deep-rock shadow regardless of dressing.
- **Supports & rubble** — timber frames on DIRT cells bordering an excavated
  floor and sparse dark pebble rubble (`pack_pebble_*`) on cave-in/magma rock
  and depleted ore are seed-deterministic decorative MultiMeshes: no
  collision, no support mechanic, no sim writes, fog-visible cells only.
- **Warm light has owners** — lanterns and lava stay the only warm
  underground sources (see the warm-emission policy above); supports and
  rubble never carry light. The cool underground ambient is a readability
  floor for visible strata only — never daylight, and never strong enough to
  dilute the opaque unexplored void.
- **Quality tiers** — Potato drops supports, rubble, and the mining-dust
  burst while keeping floors, fog, and lava; Standard/Fancy run the full
  detail pass.

## Palette

3D rework phase 4 tuned this onto a luminance ladder — terrain darkest,
structures mid, units brightest — so team color pops off the board at every
zoom.

| Role | Color | Notes |
|---|---|---|
| Snow / ice surface | `#F5FAFF` / `#DCECF5` | cold blue-grey desat; storm cover lerps to the brighter snow |
| Deep ice / shadow | `#3E5A6E` | distance fog, crevices |
| Rock / coal | `#3D404A` / `#1E1E23` | underground mass (phase 4: darkened + cooled ~15%) |
| Dirt layers | `GameManager.COLOR_DIRT_1..3` × `0.82/0.83/0.90` | deeper = darker/warmer; the 3D pass darkens/cools via `DIRT_GRADE` |
| Ore | `#C45C26` rust → `#F0B23C` bright | tier brightness by richness |
| Lava | `#E8380D` emissive | always emissive, pulses |
| Necromancy | `#9EDF9E` sickly green | undead tint only |
| Wood / steel | `#5C4229` / `#5A6570` | structures, mine supports |
| Team colors | player `#4A90F5` / enemy `#E03232` | value-lifted 3D variants via `ArtStyle3D.team_color()`; colorblind swaps enemy to `#E88A2E` live |

## Faction accents (material trims, banners, lamps)

- **Arcane** — violet `#8C5CF6`
- **Brute** — ember `#EE6B1C` (phase 4: moved off red — it collided with the
  enemy team scarlet; ember fits "raw power" and the lava world)
- **Industrial** — brass `#C9A227`

Bodies stay team-colored (`ArtStyle3D.team_color()`; player blue / enemy
scarlet, enemy ember-orange under the colorblind palette). The accent is the
identifier. Enemy faction accents stay neutral grey `"???"` until
`FactionManager.is_faction_identified(ENEMY)` — the reveal is already a game
mechanic, the art honors it. Entity materials (unit/structure bodies, not
terrain) carry a subtle sky-side rim (`ArtStyle3D.RIM_*`) so dark units
detach from dark ground even on Potato, where no shadows/SSAO exist.

## Silhouette rules (must read at max zoom-out)

R7 and plan 10 supersede the original primitive-rig implementation below:
Standard/Fancy use curated KayKit skeletal humanoids with native clips and
bone-mounted equipment; generated models remain available as fallbacks and for
non-humanoids. Potato retains the procedural fallback. Team/accent colors use
atlas garment regions, preserving skin and equipment. See
`roadmap/3d-visual-revamp/05-r7-unit-workshop.md` and
`frost_mines_assets/models/packs/SOURCES.md`. The signature silhouettes remain
the readability contract.

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

- Units: small painted atlases (512² for KayKit) on sculpted GLBs, ≤8k tris
  per model including hand tools and faction attachments. Team/accent/glow
  slots or garment-region shader parameters are rebound per proxy. Potato
  uses the old <1k-tri primitive recipes.
- Terrain: chunked mesh, one draw per chunk + one emissive pass for lava;
  subtle world-triplanar detail on Standard+, smooth surface normals, and
  MultiMesh ore/clustered prop detail. Distant backdrop geometry stays cheap.
- Budget: 60 fps desktop with 200+ units; LOD = decorative detail off +
  limb-swing amplitude reduction at far dolly, not mesh swapping.

## Quality presets (§2.7)

| Preset | Shadows | Particles | Decorative detail | Bloom | Depth fog | SSAO |
|---|---|---|---|---|---|---|
| Potato | off | 35% | off | off | on | off |
| Standard | off | 70% | on | on | on | off |
| Fancy | on | 100% | on | on | on | on |

`ArtStyle3D.apply_quality()` is the single switch; desktop defaults to Fancy,
web to Standard (`auto_detect_quality()`). 3D rework phase 3 added the post
stack on top of the scene's Environment (ACES tonemapping at every preset,
emissive bloom gated by `glow_enabled()`, depth fog on all presets, SSAO on
Fancy); `Lighting3D.apply_quality_settings()` lands the toggles on the live
light rig, and the terrain albedo pass is lit, so shadows/fog/moods reach
the ground.

## Animation

Driven by sim state (never writes sim). Five humanoids use matching-rig
KayKit `Skeleton3D` / `AnimationPlayer` clips for idle, walking, role-specific
attacks, mining, repair, and death. Actions stay in place and scale to sim
cooldowns; visible proxy syncs advance playback manually. Generated models and
original named-pivot clips remain fallbacks, while non-humanoids retain
procedural motion. Death sink, hit flash, undead tint, and faction reveal work
across both paths. Juice (§2.5): camera shake on cave-ins, hit-stop, dust
motes, storm drift, volcano embers.
