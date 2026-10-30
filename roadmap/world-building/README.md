# World Building & Art Direction Plan

Follow-on plan to the 3D conversion (`roadmap/3d-conversion/`). Assumes
`feat/3d-conversion` (Phase 1, the 2.5D port) has merged and the game
plays correctly in the 3D viewport with billboard/planar art.

Goal: turn the functional 2.5D port into a game whose world looks
intentional — coherent low-poly art, a cold post-apocalyptic mood, and
weather that you can *see* — using the asset strategy observed in the
Kimi K3.1 Pro Godot example (Quaternius, Kenney, KayKit packs, shared
rig + retargeted animations, weather-driven lighting).

## What we take from the K3.1 example (and what we don't)

Take: the external-asset sourcing model, the shared-rig animation
workflow, weather-reactive lighting, and shader approaches for animated
liquids. All packs cited are CC0 or similarly permissive.

Don't take: third-person camera/combat, boss encounters, fast travel,
or heightmap terrain generation — this stays an RTS; `GridWorld._cells`
remains the source of truth for all terrain.

## Sequencing overview

| Step | Doc | Depends on |
|---|---|---|
| 0 | [style-guide.md](style-guide.md) | Phase 1 merged |
| 1 | [asset-sourcing.md](asset-sourcing.md) | Step 0 |
| 2 | [animation-retargeting.md](animation-retargeting.md) | Step 1 (KayKit rig imported) |
| 3 | [world-dressing.md](world-dressing.md) | Steps 0–1 |
| 4 | [lighting-atmosphere.md](lighting-atmosphere.md) | Step 3 partial |
| 5 | [juice-and-effects.md](juice-and-effects.md) | Step 4 |

Steps 1–2 (units) and Step 3 (world) can run in parallel tracks once
the style guide exists. Each step is written to be a shippable
increment with the GUT suite green.

## Standing constraints (carry over from the 3D roadmap)

1. Simulation code never reads from the visual layer.
2. All gameplay numbers identical to the 2D version unless a change is
   explicitly proposed, playtested, and logged in `improvements/IDEAS.md`.
3. Every visual feature degrades gracefully on the web
   (`gl_compatibility`) build — define the degradation per feature in
   its doc.
4. Performance budget: 60fps desktop with 200+ visible units; document
   the web preset separately (Potato / Standard / Fancy).
5. A unit must be identifiable by silhouette at max zoom-out. When an
   asset fails this test at the style-guide stage, it doesn't ship.

## Status legend

`[ ]` not started · `[~]` in progress · `[x]` done (same as
`improvements/IDEAS.md`).
