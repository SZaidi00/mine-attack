# Art Direction — Frost Mines 3D Visual Revamp

Governs every visual decision in this revamp. Tokens land in
`scripts/three_d/art_style_3d.gd` (phase R2); this document is the why.

## North star

**A Frostpunk-cold industrial-fantasy RTS that reads like They Are Billions
on the surface and SteamWorld Dig underground.** Not cinematic, not gritty,
not cozy, not toylike. Cold is the default; warmth is earned (lanterns,
windows, braziers, lava).

## Reference analysis

### The Lantern Compact (https://7dhjuvcwxja7k.ok.kimi.link) — the art bar

What it does that the current build doesn't (verified from captures):

1. **Cohesive 2-hue dominant palette.** Everything sits in deep
   indigo-slate (ambient, shadows, foliage masses) + warm cream stone
   (lit surfaces), with oxblood and amber as rare accents. The current
   build's per-object flat colors read as confetti by comparison.
2. **Smooth, painterly materials.** Soft-shaded with subtle texture and
   value variation within a surface — not flat single-albedo faces, not
   noisy PBR realism. Our target: hand-painted-style textures on imported
   models with lambert-ish response.
3. **Warm accents against cold ambient.** Lanterns/braziers carry the only
   saturated warm light; the eye goes straight to them. This is exactly the
   role our lanterns + windows + lava should play.
4. **Environmental density.** Props, ruins, vegetation masses, ground-detail
   variation — the board feels built, not spawned. Our terrain detail pass
   (R3) and structure/prop scattering exist for this.
5. **Elegant UI frame.** Parchment panels, serif display type, thin gold
   rules, dark plum frame — UI that photographs well. Our HUD restyle (R8)
   targets this register without copying it.

### They Are Billions / StarCraft — the readability contract

- At gameplay zoom: every unit identifiable by silhouette; team readable by
  color mass, not inspection.
- Selection, HP, and orders must be legible without looking away from the
  fight.
- The base is the centerpiece of its half of the board — the enemy fortress
  is the win condition and deserves the best silhouette on the map (Minas
  Morgul, §Enemy fortress).

### SteamWorld Dig — the underground contract

- Underground is a *flat X-Y plane* view (owner decision 13): near-top-down,
  dim, with darkness pushed back only where lanterns burn. Readable cell
  grid feel; claustrophobic by default, warm pools of light as relief.

## Palette (reskin proposal — decision 16, ratified in R2)

Dominants (≈80% of any frame): cold indigo-slate ambient + snow blue-white.
Accents (≈15%): warm amber/brass at light sources, team colors.
Rare (≈5%): faction magics, lava, witch-green.

| Role | Hex | Notes |
|---|---|---|
| Night ambient (sky/fog base) | `#232C3A` | deep indigo-slate; distance fog |
| Snow lit | `#DDE8F2` | cold blue-white, subtly warm where lamplight falls |
| Snow shadow | `#8FA3B8` | dune shadow faces, storm-darkened |
| Rock (underground mass) | `#3A3F4A` | cooled from current `#3D404A` |
| Deep rock / unexplored | `#1C2029` | fog-of-war darkness base |
| Timber | `#5C4632` | desaturated from current `#5C4229` |
| Iron / steel | `#4E5A66` | structures; rivet detail via texture |
| Brass (player trim) | `#C9A227` | warm metallic accent |
| Lantern/window glow | `#FFB85C` | the warm hero light |
| Player team | `#4A90F5` | kept; desaturate surroundings rather than lift it further |
| Enemy team | `#E03232` | kept for banners/trim only — NOT the fortress body |
| Enemy witch-light | `#A8E6C8` | pale sickly green windows/spires (Minas Morgul) |
| Ore | `#C45C26` → `#F0B23C` | kept, tiered by richness |
| Lava | `#E8380D` emissive | kept, always emissive |
| Necromancy | `#9EDF9E` | kept, undead only |
| Faction accents | Arcane `#8C5CF6`, Brute `#EE6B1C`, Industrial `#C9A227` | kept |

Storm mood: global desaturate toward `#B9C6D4`, sun flattens — snow cover
brightens (already implemented in `lighting_3d.gd` moods; retune values in R2).
Volcano mood: menace comes from above (kept), but the ambient cools rather
than warms so lava stays the only hot thing on screen.

## Materials

- **Imported GLB models** carry hand-painted-style textures (starter set in
  `frost_mines_assets/models/`, generated with Tripo API — see
  `02-asset-pipeline.md`). Roughness high (0.85–1.0), no metalness maps on
  stylized surfaces; metallic trim faked with brighter albedo + slight
  roughness drop.
- **Team/faction tint on imports:** models are authored near-neutral with
  dedicated accent zones. The import pipeline (R4) assigns
  `ArtStyle3D.team_color()` / `faction_accent_color()` to the accent
  material slots at load time — same reveal rules as today (enemy stays
  greyed "???" until identified).
- **Terrain:** single height-field mesh, vertex-color blended snow/rock/dirt
  with a subtle noise texture overlay (tiled, low contrast) so large
  surfaces don't band. Lit (kept from rework phase 3).
- **Blob units (until R7):** keep current primitive rigs but re-materialed
  onto the new palette + add the soft rim; they must photograph
  acceptably against the new terrain before R7 replaces them.

## Lighting

- **Surface:** overcast cold key light (kept, retuned to the palette), low
  ambient; warmth ONLY from lanterns/windows/braziers/lava. Fancy preset:
  shadow maps on; Standard: blob shadows for units + structure shadow
  blobs; Potato: no shadows.
- **Underground:** near-dark ambient (kept from `lighting_3d.gd`
  "underground" mood), warm pools from lantern PointLights with tight
  falloff. The flat view (R5) drops the pitch to near-vertical so light
  pools read as circles on the plane.
- **Post (kept, retuned):** ACES tonemapping all presets; bloom on
  Standard+ (warm sources only — clamp emissive); depth fog all presets;
  SSAO Fancy-only. Compatibility renderer (web) skips SSAO automatically.

## Surface: height-field snow dunes (decision 10)

- Visual-only displacement: sim stays grid-flat (y ∈ surface band); the
  mesh displaces per-vertex from layered noise + dune ridge lines running
  roughly parallel to the midfield wall. Dune height ≤ one cell so
  readability of rows/structures is unaffected; units/props sample the same
  height function to sit on the snow.
- Dunes soften near structures and the central wall (packed snow), pile at
  map edges.
- Snowstorm: dune normals flatten + albedo brightens toward white gloom
  (existing storm mood hooks).

## Enemy fortress: Minas Morgul (decision 11)

- `frost_mines_assets/models/fortress_enemy.glb` is the target silhouette:
  dark blue-grey weathered stone, one tall central needle spire + flanking
  spires, pointed arches, battlements, light frost on ledges.
- **Witch-light reveal:** authored windows/spire tips emit pale green
  (`#A8E6C8`, low energy). Before faction identification the model loads
  with emissive off and accents greyed; on `FactionManager` reveal the
  emissive and enemy-red banner trim fade in. The re-tint hook exists at
  `structure_proxy_3d.gd:171-179` — R4 extends it to imported models.
- Scale: ~1.6× the current keep footprint height-wise; must remain inside
  its sim footprint (presentation-only rule).

## Player keep (companion piece)

- `keep_player.glb`: squat Frostpunk-industrial citadel — riveted iron,
  brass bands, snow-loaded slate roofs, chimneys, amber windows, blue
  banner. Warm and held vs. the enemy's cold menace: the two bases should
  be tellable apart in silhouette from across the map.

## UI direction (R8)

- Keep the Frosted Steel HUD structure (it works) but restyle: colder panel
  glass, brass key-lines, amber alert accents, serif display face for
  titles/numerals. Target: the HUD in a screenshot looks like it belongs to
  the same game as the Minas Morgul fortress.
- Build-time loaders for units/research (owner answer 4) exist in the HUD —
  restyle them into brass-ringed progress dials; readability first.

## What we are NOT doing

- Photoreal PBR, cinematic grade, film grain.
- Mobile support (decision 23).
- Strategic zoom-out beyond the local area (decision 14).
- Camera shake beyond minimal (decision 21).
- New audio (decision 20).

## Acceptance for the art direction itself

- Owner sign-off on: this document, the R2 token PR's harness screenshots
  (same seeded match, before/after), and the Minas Morgul fortress capture.
