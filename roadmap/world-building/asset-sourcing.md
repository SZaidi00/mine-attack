# Step 1 — Asset Sourcing & Import Pipeline

Where every model comes from, and the checklist each one passes before
it enters the project. External packs are CC0; design-library assets are
internal. Prefer editing generation code over hand-fixing meshes.

## Sources

| Source | License | Use for |
|---|---|---|
| KayKit Character Pack + Animations 1.1 | CC0 | Humanoid units: miner, swordsman, archer, wizard, engineer |
| Quaternius Universal Animation Library | CC0 | Extra animations retargeted onto the KayKit rig |
| Quaternius Medieval Village MegaKit | CC0 | Base structures (building, towers) |
| Kenney Survival Kit | CC0 | Mine props: carts, crates, ladders, lanterns, trap dressing |
| Quaternius Stylized Nature MegaKit | CC0 | Surface dressing: dead trees, rocks, snow drifts |
| Quaternius Ultimate Monsters | CC0 | Dragon body (verify silhouette against style guide) |
| Kimi design asset library | internal | Structure/prop candidates (see below) |

## Design-library candidates already screened

- **箭塔 / Limestone arrow tower** (`02-G5-0009`), **Castle Tower**
  (`02-G5-0007`) — tower structure candidates.
- **Medieval half-timber brick wall** (`02-G4-0001`) — modular wall
  piece for wall segments / central wall dressing.
- **铁匠铺 / Village Smithy** (`02-G5-0002`) — forge props for the mine
  entry or Industrial faction base.
- **Blue crypt structural kit** (`02-G4-0008`) — modular stone pieces
  for underground mine dressing.
- Fetch with `fetch_design_asset`, inspect `preview.png`, import the
  GLB via the same pipeline as external packs.

## Import checklist (every asset, no exceptions)

- [ ] License recorded in `assets/CREDITS.md` (pack name, author, URL).
- [ ] Scale normalized to the style-guide metre standard.
- [ ] Texel density normalized (re-UV or material-adjust, don't hand-edit
      geometry).
- [ ] Origin at feet-center for units; base-center for structures.
- [ ] Forward axis verified (the library notes `forwardAxis` is
      unconfirmed — verify against world bounds, don't guess).
- [ ] Silhouette test at max zoom-out camera — pass/fail recorded.
- [ ] Poly count under budget — if over, reduce via the pack's LOD
      tooling rather than remeshing.
- [ ] Material slots remapped to project materials (palette + faction
      accents) — no per-asset unique materials.
- [ ] Web-build spot check (renders + animates on `gl_compatibility`).

## Where things live

```
assets/
  models/units/        # by unit type, LOD0 (+ LOD1 for web)
  models/structures/
  models/props/
  materials/           # shared: palette, faction accents, emissive
  CREDITS.md
```

## Unit coverage matrix (Step 1 outcome)

| Unit | Source plan | Fallback if silhouette fails |
|---|---|---|
| Miner | KayKit rig + pickaxe prop (Kenney) | Quaternius character |
| Swordsman / Archer | KayKit rig + weapon props | — |
| Wizard | KayKit rig + hat/robe mesh variant | — |
| Engineer | KayKit rig + hard-hat + wrench props | keep sprite |
| Crawler | Quaternius Monsters | — |
| Dragon | Quaternius Monsters (verify!) | original model |
| Pigeon | Kenney animal or keep sprite | keep sprite |
| Undead | palette-swapped soldier/archer/dragon materials | — |

Status: `[ ]` (begin after style guide)
