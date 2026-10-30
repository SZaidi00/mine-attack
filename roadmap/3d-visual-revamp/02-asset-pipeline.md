# Asset Pipeline — Textured GLB Imports

How textured models enter the project, how they're normalized and tinted,
and the full asset manifest (what exists, what to generate next, with
prompts). Starter models in this PR were generated with **Tripo API**
(text-to-3D, v3.1, textured).

## Directory layout

```
frost_mines_assets/
├── models/            # .glb imports live here (this PR adds the starter set)
│   ├── structures/    # buildings, towers, walls, lanterns, mine entry
│   └── units/         # R7 sculpted unit GLBs + faction attachment rigs
└── …                  # existing 2D sprite dirs unchanged
```

Godot imports `.glb` on project open (no manual import step); commit the
`.glb` + the generated `.glb.import` sidecar together.

## Import conventions (enforced in phase R4)

1. **Scale normalization.** Generation services don't know our world units
   (1 unit = 100 px of sim space, humanoid ≈ 0.35 units tall). Every import
   gets a `model_manifest.tres`-style entry (plain Dictionary resource is
   fine) recording target footprint (cells) and height; the loader
   (`structure_proxy_3d.gd` extension) scales the GLB root so its XZ bounds
   match the sim footprint and its origin sits on the ground plane.
2. **Y-up, origin at base center.** The loader asserts this and logs a
   warning + auto-fixes (recenter via AABB) when violated.
3. **Accent-slot tinting.** Models are authored near-neutral; material
   names containing `accent` (case-insensitive) are rebound at load time to
   `ArtStyle3D.team_color()` / `faction_accent_color()` materials, honoring
   the hidden-faction "???" reveal (greyed until identified). Emissive
   materials named `glow_*` get their energy from the mood system
   (`Lighting3D`) so storm/volcano can dim them globally.
4. **Face budgets.** Hard gates, verified by script (`tools/check_model_budgets.sh`
   — trimesh/pygltflib count, runs in CI):
   - Fortress/keep: ≤ 25k tris
   - Towers/walls/mine entry: ≤ 12k tris
   - Lanterns/props: ≤ 6k tris
   - Units (R7): ≤ 8k tris each, ≤ 60k for all units on screen at once
   - Over-budget models go through `decimate` (Tripo API) before landing,
     never committed raw.
5. **Texture size.** Cap 2048² per model (resize at import if larger); web
   build total texture budget ≤ 64 MB — checked by the same script.

## Starter set (generated with Tripo API, delivered alongside this PR)

The GLB binaries ride with this PR in `frost_mines_assets/models/` (they are
binary, so if the diff view doesn't render them, check the branch directly).

| File | Verified tris | Gate | Role |
|---|---|---|---|
| `structures/fortress_enemy.glb` | 19,154 | ≤25k ✓ | Enemy base — Minas Morgul (art direction §Enemy fortress) |
| `structures/keep_player.glb` | 18,794 | ≤25k ✓ | Player base — Frostpunk-industrial citadel |
| `structures/tower_watch.glb` | 10,958 | ≤12k ✓ | Player tower (faction caps land in R4) |
| `structures/lantern_post.glb` | 5,666 | ≤6k ✓ | Lantern T1; T2/T3 = emissive + scale variants of the same mesh |
| `structures/mine_headframe.glb` | 9,585 | ≤12k ✓ | Mine entry headframe |

Triangle counts measured with trimesh at generation time; per-model
previews in `frost_mines_assets/models/previews/`. The GLBs were delivered
with 4096² textures; the R4 import pass downscales them to the 2048² cap
(`tools/resize_glb_textures.py`, per §convention 5) — they now run 3.4–4.8 MB
per GLB, 16.7 MB of embedded textures total (web budget ≤ 64 MB verified by
`tools/check_model_budgets.sh`).

## Generation prompt recipes (reusable)

The prompts that produced the starter set follow one template — keep it for
future generations so the set stays cohesive:

```
<subject + role in game>, <silhouette-defining features>,
<materials/weathering>, <lighting behavior (emissive/glow)>,
"stylized hand-painted game asset texture, cold desaturated palette
[Frostpunk-industrial | gothic dark fantasy], isolated <building|structure|
prop>, no terrain"
```

Cohesion rules: always "stylized hand-painted", always cold desaturated
base, warmth only at light sources, snow/frost dusting on upward faces,
no terrain/ground plane in the mesh, no baked text.

## Next-generation manifest (do NOT generate until its phase lands)

Prompts are pre-written so a generation pass is mechanical. Units stay
blobs until R7 (owner decision 14).

**R4 batch (structure set completion):**
- `wall_segment.glb` — "Chunky defensive wall segment of riveted dark iron
  and stone for a cold-region RTS, crenellated cap, brass player-trim band,
  frost on the capstones, stylized hand-painted game asset texture,
  Frostpunk-industrial, isolated structure, no terrain"
- `lantern_underground.glb` — "Sturdy iron bracket lantern for underground
  mines in a cold-region RTS, warm amber glowing cage head on a wall-mount
  bracket, soot and frost, stylized hand-painted game asset texture,
  isolated prop, no terrain"
- `trap.glb` — "Spiked bear-trap mechanism half-hidden in snow for a
  cold-region RTS, dark sprung iron jaws, subtle frost, stylized
  hand-painted game asset texture, isolated prop, no terrain"
- Faction crown variants for the keep (Arcane crystal spire / Brute horned
  gate / Industrial smokestack) — generate as separate small GLBs and swap
  on faction pick.

**R7 batch (unit workshop — with owner review of concept screenshots):**
- Miner (pickaxe + helmet lamp, bulky cold-weather gear)
- Swordsman / Archer / Wizard (faction-variant helmets per style-guide
  silhouette table)
- Dragon / Pigeon / Engineer / Crawler / Undead
- The landed silhouette/material/pivot contract and reusable prompts live in
  `05-r7-unit-workshop.md`; `tools/gen_unit_glbs.py` regenerates the set locally.
  Undead reuse the living GLBs with the runtime sickly-green material pass.

## Failure modes & fixes

- **Over budget** → Tripo API `decimate` (v1.0 for >20k targets), re-verify.
- **Style drift** (too realistic / too bright) → regenerate with tighter
  palette language; do not hand-fix textures in an image editor — cohesion
  comes from one generator + one prompt template.
- **Wrong orientation/origin** → loader auto-fix (§convention 2); if the
  mesh itself is broken, regenerate — no manual mesh surgery.
- **Import regressions** → GUT test `test_3d_structure_models.gd` asserts
  every manifest entry loads, fits its footprint, and exposes accent slots.
