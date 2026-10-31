# Curated pack provenance

## Quaternius Stylized Nature MegaKit — Standard

- Author: Quaternius (`@Quaternius`)
- Official pages: https://quaternius.itch.io/stylized-nature-megakit and
  https://quaternius.com/packs/stylizednaturemegakit.html
- Downloaded archive: `Stylized Nature MegaKit[Standard].zip`, upload dated
  2024-07-30, 99 MB as listed by the author
- Archive SHA-256: `298f6732b872e4cf7b30e6e7abf9641c7f6dc6b326df37ac089533ed7e3d58c9`
- License: CC0 1.0 Universal; see `LICENSE_Quaternius.txt` and the source
  archive's `License_Standard.txt`
- Selected on: 2026-10-30

Only the seven source models below were curated. The complete archive, engine
projects, and raw downloads are not included in the repository or exports.
`tools/import_kit_props.py` embedded external buffers/images, retained source
geometry/materials, uniformly scaled each model to the listed height, centered
XZ, placed min-Y at 0, and set metallic 0 / roughness 0.92. The existing texture
resize tool then downscaled atlases to a maximum of 512x512.

| Curated key | Source file | Source SHA-256 | Final GLB SHA-256 |
|---|---|---|---|
| `pack_rock_medium_1` | `glTF/Rock_Medium_1.gltf` | `5d1ab1fa03218f4a908728ed0eabe6486344a7e4f510b0d3d6f837fd1d011bd8` | `ed59268fcf718378fcf18dcd9ccb33206e6d11f3a55cff89757af6e949676e31` |
| `pack_rock_medium_2` | `glTF/Rock_Medium_2.gltf` | `fac2d05a05f2d0d2098de59c09b58f42cc875c9caca4fd4c4bd57f3d36e7b12e` | `f90aec788dff19344cfb0f14b45be6c417c02fd3f782e510a233d147f143eef1` |
| `pack_rock_medium_3` | `glTF/Rock_Medium_3.gltf` | `9a575b911372cf91693aa3a56aea8137ec2251c2b99fb34a31272ee64503047f` | `ec313f4bc529cde3ab45994407858e4ccd4b4b67fc2bac0344c0298e5e2acb9d` |
| `pack_dead_tree_3` | `glTF/DeadTree_3.gltf` | `aa74a47c69259f217388d7b3e2871d76c0385449fc1efd92299c2e55417fdffc` | `980c7c4d185bbdae119e77ead0e183a98229ccf8c0c5aa92db62176f9c305675` |
| `pack_dead_tree_5` | `glTF/DeadTree_5.gltf` | `8502cb23774f8771b047053bef8a4a25fbcb30340a160c4b00c0af6ba614284f` | `e7ebba50884e0a6f793ea2e22542a9d8e72d4d209e2fe12b28c4d273776bf8cb` |
| `pack_grass_wispy` | `glTF/Grass_Wispy_Short.gltf` | `3c1d3bdd332420e070abde72d73611d1f13acfbe027e26b2fb943f9bcbd6b1c5` | `5307f92af8c8961870a2b5f842f6a6fd7cd88e04aeb00f33f33e2027fbcc7204` |
| `pack_bush_common` | `glTF/Bush_Common.gltf` | `77811fca92610cb254713d3d49d5029ab6cf13050c3afb61aa942786a7b2ca90` | `442948f59691b14525c080c1797c5b37b107dab9e7279ecf028b976d5b903ce6` |

External images referenced by the source glTF files are embedded in each final
GLB. Godot's normal import also writes extracted PNG sidecars and their
`.import` files; those are generated duplicates of the embedded textures, not
additional source-pack assets. Final dimensions and triangle counts are
recorded in `../model_manifest.json` and gated by
`tools/check_model_budgets.sh`.

## KayKit skeletal humanoids

Selected on 2026-10-31 from the official free downloads by Kay Lousberg
(`www.kaylousberg.com`). The included license files were inspected, not just the
store pages: all three packs are CC0 and permit personal, educational, and
commercial use. Copies are preserved as `LICENSE_KayKit_Adventurers.txt`,
`LICENSE_KayKit_Animations.txt`, and `LICENSE_KayKit_RPGTools.txt`.

- Adventurers 2.0 Free: https://kaylousberg.itch.io/kaykit-adventurers
  (upload 15363167). Archive SHA-256:
  `abe48f4763fba0896bab486ee9e6d08ca6b5b3884b9601f235c8847ae94dc479`.
- Character Animations 1.1: https://kaylousberg.itch.io/kaykit-character-animations
  (upload 15799903). Archive SHA-256:
  `65882f31f905ad2e953819648a59287cdeab8f623908d5ef701971d3758be20f`.
- RPG Tools Bits 1.0 Free: https://kaylousberg.itch.io/rpg-tools-bits
  (upload 15653196). Archive SHA-256:
  `a17c2a54df93d525e90d960baf3c68638defb4f424e204ceead6ea1f89e9c7dd`.

The free archives were saved with their upload IDs in the filename because the
CDN did not provide a filename header. Only the five curated GLBs below, their
embedded textures, and the license notices enter the project. Raw archives and
source packs remain in ignored, `.gdignore`d `build/asset_staging/`. No paid
Engineer/Extra-tier content is used: the engineer is the free Rogue with a
wrench and a small programmatic backpack. The miner uses the free Barbarian,
pickaxe, glowing helmet lamp, team helmet band, and backpack. The wizard's
staff carries a small emissive faction-colored accent. Other procedural
accessories are the three faction badges. `UnitSkeletal3D` attaches equipment
to the native `handslot.r`/`handslot.l`, `head`, and `chest` bones.

`tools/curate_skeletal_units.py` embeds resources, preserves the original skins
and inverse bind matrices, and copies matching `Rig_Medium` tracks by their
native node names. There is no cross-rig or runtime retargeting. All selected
clips were checked to have no root translation. Common aliases are `Idle_A` →
`idle`, `Walking_A` → `walk`, and `Death_A` → `death`. Attacks are
`Melee_1H_Attack_Chop` (miner), `Melee_1H_Attack_Slice_Diagonal` (swordsman),
`Ranged_Bow_Release` (archer), and `Ranged_Magic_Shoot` (wizard). The miner's
`mine` is `Pickaxe` frames 0–2 seconds; the engineer's `repair` is `Hammering`
frames 0–1.333333 seconds, with `Hammer` over the same interval for its unused
combat fallback. Idle/walk/work clips loop; attacks and death do not.

| Curated key | Character (SHA-256) | Hand tool (SHA-256) | Tris | Final GLB SHA-256 |
|---|---|---|---|---|
| `unit_kaykit_miner` | Barbarian `d37824a1d6e8e8af57ef9ae4a87e9271c3986210fbc432fb44670749a577ccac` | pickaxe `4f3777249fdb9551a546ba66b997f948992787e4b5394ebe13cc1d7bf344a98b` | 7631 | `e5c1d0f2c5eaeb61c9807f46e973e730fc14ebdb305cf30eac7078ad8804b48f` |
| `unit_kaykit_swordsman` | Knight `e484370733824a0740683e7f6040aae0d20e5efd4107dde1175d6a2ad7e2f199` | sword `2a6074d46c3e337f84f0295d0ea862b116fec7d816db8d027d75a464311228b6`; shield `dd052a109d5a003fa7ebe4641c31e89a5189ad8d606ee8fc969d05e2d99dab38` | 6384 | `1889941a8fb87bfe65233989884ca0f5180885652a8ffcdd2ecb9890ec8ad498` |
| `unit_kaykit_archer` | Ranger `3a0b0166b9d61d58dcaaa739c3cc0538be46e00d2928dd5cb513d9a41770d2e9` | bow `de978d50afcc66ba30edb42e8d040bf932ae7308942b1b4e1400d252ccb8e1fb` | 7146 | `17d57be54c513187714a79bb684e2e3762cc6474d2f5c00cb2befbfe1c3db41c` |
| `unit_kaykit_wizard` | Mage `1f7d891bde50b879c70965f155b7b765b166dc3f8518e5abb86c0002f191a26e` | staff `25646537632555f2a4e5ae90320bce251bbc5af541e8897960ad4514122110b9` | 7108 | `80e9eb483b5c134d10cb671e92359ea7859e984834c3db5c7dc28279bc26848d` |
| `unit_kaykit_engineer` | Rogue `cae5d9b2f08d53f7b4ab2617d9f42f021c546eb10920455fdcd82a110867fae4` | wrench `7895c3709a3fbd4bb2d459bcba6398c4e9231c184a9590ca8de8d9ada91c9358` | 7918 | `474ab1ed237e6f755348dcf9670955e3c18cb6a12e7a825691737209974eeb47` |

The Ranger was reduced from 8,900 body triangles using bounded vertex
clustering on the body meshes (cape/quiver retained), preserving positions,
normals, UVs, and dominant bone assignments; its final model including the bow
is 7,146 triangles. Every model is below the existing 8,000-triangle gate.
All embedded atlases were reduced to at most 512x512 with
`tools/resize_glb_textures.py --max=512 --only=unit_kaykit_`. Each character's
body parts are merged into one skinned mesh with the original material, UVs,
and bone weights, reducing draw calls without further geometry reduction.

Animation-library source hashes: General
`5f725c0f745f36078c7238968cd5c04843cbc6260689eb6e7f5e2bbd7ffdd7ad`;
MovementBasic `11422afd50abf7e8c92ea107e2e0bc94abd38023d6d15f55ad580347efbfa29e`;
CombatMelee `c55e6ec1c79e83ae21d46fe1cd921c1b64be8b9a524a24517e51c6ba99231459`;
CombatRanged `7fef1fc0e7b0feafd34b8e12d23f514c8c1f9d068047a691b854b56f1774dff5`;
Tools `e3b62dc122c5073373376a846e354137add2088ddcce8731c389fc5c20734aad`.

`unit_palette_3d.gdshader` recolors only the source-atlas garment rectangles
listed in `model_manifest.json`; skin and equipment are not tinted wholesale.
Generated models and the original named-pivot clips remain registered and are
used on Potato or if a skeletal import fails validation. Quaternius UAL was
not imported: its current rig differs from KayKit's native `Rig_Medium`.
