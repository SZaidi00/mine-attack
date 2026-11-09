# Plan 09 — Environment visual vertical slice

Status: Done (2026-10-30, branch kimi-code-plans)
Size: M
Depends on: 06, 07

## Mission

Improve the 3D world's richness and sense of place without changing the RTS
simulation: curated external nature props, composed deterministic scatter,
subtle terrain detail, and a distant noninteractive backdrop. Skeletal unit
animation and larger map dimensions remain separate later stages.

## Implementation

- `tools/import_kit_props.py` converts selected glTF/GLB props into
  self-contained GLBs, embedding resources and applying uniform scale, XZ
  centering, min-Y 0 grounding, and the house PBR convention. Seven models were
  curated from the official CC0 Quaternius Stylized Nature MegaKit Standard
  pack: three rocks, two lower-poly dead trees, wispy grass, and a bush.
  `frost_mines_assets/models/packs/SOURCES.md` records exact source/final
  hashes and processing; `LICENSE_Quaternius.txt` records provenance/license.
  Raw archives live only in ignored, `.gdignore`d staging under `build/`.
- All seven GLBs are manifest-registered with measured dimensions and the
  6,000-triangle gate. Texture atlases were reduced to a maximum of 512² for
  sub-cell RTS rendering. The complete model set uses 8.3 MB of the 64 MB
  embedded-texture budget.
- `Terrain3D` adds a seamless near-white world-triplanar detail texture on
  Standard/Fancy while vertex colors remain authoritative for cell palette and
  fog. Shared surface corners produce smooth dune normals; underground stays
  faceted. Potato disables the additional texture and triplanar samples.
- `TerrainDetail3D` combines per-cell hashes with map-seeded low-frequency
  cluster noise. Base density remains near the old 12% baseline, high-noise
  pockets reach 42%, front rows and midfield are restrained, and trees favor
  outer clusters. Generated and curated props share the same MultiMesh,
  clearance, fog, grounding, and `scatter_log` contracts. The multi-node merge
  now preserves transformed normal-map tangents.
- `Backdrop3D` builds a seeded ground skirt, three distant ridge layers, and
  Standard/Fancy pine silhouettes outside playable cells. It never rebuilds
  per frame, hides underground, and retains only the cheap large forms on
  Potato. Framing was iterated through the capture harness to keep mountains
  and snow caps subordinate to the battlefield.
- GUT coverage discovers all generated/pack props, checks terrain quality
  behavior and composed scatter, and verifies backdrop determinism, placement,
  Tab visibility, and quality fallback. Scatter tests allow initial fog/terrain
  setup to settle before sampling and reveal the full board for the dedicated
  composition assertion.

## Verification

- Curated importer `--validate-only`: 7/7 pass; final hashes match SOURCES.md.
- `tools/run_checks.sh`: PASS — budget gate plus 76 scripts, 809 tests,
  8,374 assertions. Embedded textures: 8.3 MB / 64 MB. `git diff --check`: PASS.
- Focused GUT: props and every manifest model load; terrain art 6/6;
  scatter 8/8; backdrop 3/3; shell port 6/6.
- Captures inspected: baseline, terrain-only, first backdrop, refined backdrop,
  and final palette. Final Standard/Fancy captures covered dunes, surface,
  zoomout, and underground; Potato covered dunes and underground. Isolated
  capture profiles selected quality without changing the user's settings.
  Curated props are grounded, underground has no backdrop, and Potato drops
  scatter/pines while retaining the cheap horizon forms.
- Standard 200-unit, 30-sim-second OpenGL BENCH (1,800 samples):
  `unit_sync` 0.797 ms, `sim_fog_recompute` 8.380 ms,
  `ring_hover_scan` 0.094 ms; `terrain_rebuild` 3.532 ms over 56 batches,
  `terrain_scatter` 0.649 ms over 112 chunks, `fog_rebuild` 2.673 ms.
  Plan-07's scatter was 0.129 ms and plan-08's unit sync 0.839 ms; the richer
  11-kind clustered scatter costs more but remains a small fraction of the
  16.67 ms frame budget, and unit sync is slightly cheaper than the clip baseline.

## Out of scope

- Skeleton/rig replacement or external animation retargeting
- Surface-row, width, or underground-depth changes
- Playable water, roads, collision, or interactive backdrop objects
- Medieval village and monster pack imports
