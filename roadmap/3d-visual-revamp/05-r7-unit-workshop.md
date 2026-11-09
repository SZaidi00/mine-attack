# R7 — Unit Model Workshop

This is the R7 silhouette contract, superseding the primitive-unit table in the
old conversion style guide. The first asset-authoring pass is local and
deterministic: `tools/gen_unit_glbs.py` builds sculpted lofts, swept organic
forms, custom blades/wing membranes, and small painted atlases without a model
service. `unit_model_loader.gd` connects these rigs to the live presentation;
rendered faction galleries live under `r7/`. Owner visual acceptance and
real-hardware performance validation remain separate acceptance checks.

## Silhouette table

Identification must survive maximum local zoom-out in surface and underground
views. The prop or negative-space cue is primary; faction trim is secondary.

| Unit | Height | Primary silhouette and negative-space read | Animation pivots | Signature light |
|---|---:|---|---|---|
| Miner | 0.38 | Broad helmet with forward lamp, squared backpack/bedroll, wide asymmetric pickaxe head | Body, ArmL/R, LegL/R, Tool | `glow_lamp` |
| Swordsman | 0.39 | Tall narrow helmet crest, long straight sword opposite a large oval shield | Body, ArmL/R, LegL/R, Tool | None |
| Archer | 0.37 | Soft pointed hood, open crescent bow, diagonal back quiver with three fletchings | Body, ArmL/R, LegL/R, Tool | None |
| Wizard | 0.40 | Continuous robe instead of separated legs, wide hat brim and crooked point, tall orb staff | Body, ArmL/R, Tool | `glow_staff` |
| Dragon | 0.70 | Large barrel body, long neck/snout, paired horns, scalloped bat wings with open bays, curling tapered tail | Body, WingL/R, Tail | `glow_eyes` |
| Pigeon | 0.12 | Compact breast, short beak, tiny fan tail, two thin triangular wings | Body, WingL/R | None |
| Engineer | 0.36 | Low hard hat, oversized tool pack, open-jaw wrench rather than a weapon | Body, ArmL/R, LegL/R, Tool | None |
| Crawler | 0.16 | Low long abdomen, six outward skitter legs, four dorsal spikes, blunt glowing-eyed head | Body | `glow_eyes` |

The neutral base must remain identifiable with every faction attachment group
hidden. Undead use these same rigs and the runtime sickly-green tint; there is
no separate undead asset or prompt.

## Scale bands and authored outputs

Units are Y-up, face -Z, and have their base center at the root origin. After
generation the whole shared rig is uniformly height-normalized, then grounded
so minimum Y is exactly 0. Bounds below include all three attachment sets;
triangle counts likewise include every variant, not just the visible faction.

| Unit | Target humanoid/creature band | Authored height | Authored width × depth | Triangles | Output |
|---|---|---:|---:|---:|---|
| Miner | Humanoid 0.34–0.40 high, ≤0.32 wide | 0.380 | 0.258 × 0.167 | 2,054 | `frost_mines_assets/models/units/miner.glb` |
| Swordsman | Humanoid 0.34–0.40 high, ≤0.32 wide | 0.390 | 0.222 × 0.145 | 1,980 | `frost_mines_assets/models/units/swordsman.glb` |
| Archer | Humanoid 0.34–0.40 high, ≤0.32 wide | 0.370 | 0.214 × 0.153 | 1,986 | `frost_mines_assets/models/units/archer.glb` |
| Wizard | Humanoid 0.34–0.40 high, ≤0.32 wide | 0.400 | 0.222 × 0.165 | 1,648 | `frost_mines_assets/models/units/wizard.glb` |
| Dragon | 0.66–0.74 high; wings may exceed one cell | 0.700 | 1.179 × 1.186 | 2,526 | `frost_mines_assets/models/units/dragon.glb` |
| Pigeon | 0.10–0.14 high; wing read wider than body | 0.120 | 0.240 × 0.172 | 1,033 | `frost_mines_assets/models/units/pigeon.glb` |
| Engineer | Humanoid 0.34–0.40 high, ≤0.32 wide | 0.360 | 0.206 × 0.158 | 1,948 | `frost_mines_assets/models/units/engineer.glb` |
| Crawler | 0.14–0.18 high, ≤0.32 wide; long low body | 0.160 | 0.248 × 0.417 | 1,536 | `frost_mines_assets/models/units/crawler.glb` |

The hard gate is 8,000 triangles per GLB including all variants. The authored
target is approximately 500–2,500; the dragon is 2,526, effectively on that
upper target and far below the hard gate.

## Shared rig contract

The GLB scene root is named for the unit. `Body` is its child and owns the base
meshes, animation pivots, and faction groups. Meshes are rigid-parented rather
than skinned, so no skeleton is required. Plan 08 adds
`scripts/three_d/unit_animation_clips.gd`: original programmatic `idle`, `walk`,
`attack`, and `death` clips target the named pivots on miner and swordsman rigs
at every quality tier, including Potato's procedural models. `UnitModel3D`
selects clips from sim state and advances them manually from visible proxy
syncs; procedural mining, body motion, death topple/sink, and every unclipped or
incomplete rig remain intact. No third-party animation assets are bundled;
retargeting a CC0 clip library is a follow-up.

- Humanoid shoulders are `ArmL`/`ArmR`; arm geometry hangs below local origin.
  Hips are `LegL`/`LegR`, with leg and boot geometry below local origin. X
  rotation therefore swings limbs rather than orbiting the model root. Wizard
  has no leg pivots because its robe is the silhouette.
- `Tool` is at the carrying shoulder/hand line. Handles, blades, bows, and
  staff geometry are authored relative to it, so attack/mining X rotations are
  useful immediately.
- Dragon and pigeon wing origins are hinges. `WingL` geometry extends along
  +X and `WingR` along -X; flapping Z rotation remains mirrored. Dragon `Tail`
  is at the rear body and its geometry extends along +Z.
- Facing is always -Z: noses, lamps, weapons, and eyes establish the front.
  There are no compensating node rotations hidden in the asset.

Every model has exactly these three faction groups under `Body`:

| Group | Geometry language |
|---|---|
| `FactionArcane` | Paired pointed crystals rising from the back/shoulders |
| `FactionBrute` | Curved paired horns plus heavy shoulder plates |
| `FactionIndustrial` | Round brass-tint goggles, bridge, rivets, and a small smokestack |

Attachments reuse the base rig and are scaled per creature. They are real mesh
variants, not material-only swaps. `UnitModelLoader` hides all three for neutral
or unidentified-enemy units and shows only the selected faction; the faction
identification signal updates live enemy proxies.

## Material and texture contract

All models share these lowercase material slots:

| Slot | Purpose |
|---|---|
| `body` | Creature hide, secondary armor, dark mechanical masses |
| `cloth` | Cloth, boots, wings, hood and soft secondary surfaces |
| `steel` | Cold iron helmets, blades, horns and hard trim |
| `skin` | Skin and nose |
| `wood` | Handles, packs, boots and beak/feet |
| `team` | Near-neutral main team-color mass |
| `accent` | Near-neutral faction trim, shield, spikes, crystals and brass goggles |
| `glow_lamp` | Miner helmet lamp only |
| `glow_staff` | Wizard staff orb only |
| `glow_eyes` | Dragon/crawler eyes only |

Every slot has metallic 0 and roughness 0.92. `team` and `accent` atlas tiles
are near-neutral so GDScript multiplication supplies team/faction color. Glow
slots have embedded emissive textures. Each GLB embeds one 256×256 PNG painted
atlas with mottling, broad directional brush marks, and restrained edge value
shifts; there are no external images, metalness maps, terrain planes, or text.

## Reusable generation prompts

For a future concept/model-service pass, use the common prefix and suffix with
one unit subject below. The current local generator does not call a service;
these prompts preserve a repeatable art brief for later replacement or concept
review.

Common prefix:

> Single isolated stylized hand-painted RTS unit for a cold industrial-fantasy
> mine war, smooth sculpted low-poly forms, restrained realistic proportions,
> strong gameplay silhouette, cold desaturated body palette with warm light
> only at the named emissive feature.

Unit subjects:

- **Miner:** “Bulky cold-weather miner, broad steel helmet and warm helmet
  lamp, squared wooden backpack with bedroll, large asymmetric steel pickaxe.”
- **Swordsman:** “Narrow-crested infantry swordsman, tall straight blade held
  on the right, large oval shield on the left, compact armored torso.”
- **Archer:** “Hooded archer with a soft pointed hood, clearly open crescent
  wooden bow, diagonal back quiver and three visible accent fletchings.”
- **Wizard:** “Robed wizard with no separated-leg silhouette, very wide hat
  brim and crooked pointed crown, tall wooden staff topped by a glowing orb.”
- **Dragon:** “Stocky barrel-bodied dragon, long neck and snout, paired horns,
  four short legs, wide scalloped bat wings with readable holes, long curled
  tapering tail, small glowing eyes.”
- **Pigeon:** “Tiny plump scout pigeon, short beak, compact breast, fan tail,
  two thin spread triangular wings, readable as a bird rather than a dragon.”
- **Engineer:** “Compact engineer with a low hard hat, oversized tool backpack,
  open-jaw wrench held like a tool, no sword or combat weapon.”
- **Crawler:** “Underground crawling creature with a low elongated abdomen,
  six splayed skittering legs, four dorsal spikes, blunt head and two glowing
  eyes; no wings and no upright humanoid torso.”

Faction modifier, appended only to the attachment concept:

> Add one interchangeable attachment set on a shared neutral rig: Arcane uses
> paired pointed/crescent crystals; Brute uses curved horns and heavy shoulder
> plates; Industrial uses round brass goggles, rivets, smokestack and mechanical
> trim. Keep the neutral silhouette complete with all attachments removed.

Common suffix:

> Feet/base at Y=0, Y-up, front facing -Z, base center at origin, no ground or
> scenery, no baked text. Humanoids 0.34–0.40 world units high; dragon 0.70,
> pigeon 0.12, crawler 0.16. Humanoid width must fit a 0.32-unit cell. Use one
> small painted atlas, near-neutral team/accent masks, metallic 0, roughness
> 0.92. Target 500–2,500 triangles and never exceed 8,000 including all three
> attachment sets. Preserve named rigid pivots Body, ArmL/ArmR, LegL/LegR and
> Tool as appropriate; WingL/WingR/Tail for dragon; WingL/WingR for pigeon.

A generated replacement must be rigged/normalized to this contract even if the
concept service cannot author pivots directly; silhouette quality does not
excuse a different runtime interface.

## Regeneration and validation

```bash
python3 tools/gen_unit_glbs.py
python3 tools/gen_unit_glbs.py --validate-only
```

The validator parses the actual GLB 2.0 chunks with the standard library. It
checks embedded buffers/images, required pivot/faction names, triangle mode
and count, finite transforms, unit normals, grounded bounds, height bands, and
PBR factors. Run Godot `--import` afterward and commit the generated `.import`
sidecars with the GLBs, then run `tools/check_model_budgets.sh`.

Structural validation does not establish visual identification, animation feel,
200-unit performance, or owner sign-off. Runtime faction toggling and pivot
animation have GUT coverage; surface/underground faction galleries under `r7/`
provide the visual review baseline. Potato remains on the procedural rigs.
