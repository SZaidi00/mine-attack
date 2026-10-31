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
