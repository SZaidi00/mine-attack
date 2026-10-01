# Mine Attack — 3D Conversion Roadmap

This folder is the working plan for converting Mine Attack from a 2D
CanvasItem game into a 3D-rendered game. It is broken into small phases
so the game stays playable (and shippable) after every step.

## The core decision: 2.5D first, full 3D optionally

We are **not** rewriting the game. The plan is:

1. Keep the entire simulation exactly as it is today — the 2D grid, the
   A* pathfinding, the autoloads, the AI, the GUT test suite.
2. Swap the **renderer** from 2D canvas to a 3D viewport where the world
   is viewed at an RTS-style pitch (~45–60°).
3. Upgrade art incrementally: billboarded sprites first, low-poly models
   later.
4. Only after 2.5D is stable, decide whether to attempt true 3D depth in
   the mine (Phase 3). That phase is explicitly optional and scoped like
   a sequel feature, not a conversion step.

### Why this works for this codebase

| Layer | What it is today | Fate in 2.5D |
|---|---|---|
| Autoloads (`game_manager`, `economy_manager`, `faction_manager`, `research_manager`, `weather_manager`, `match_stats`, `ai_belief_system`, ...) | Pure logic | Unchanged |
| AI controllers (`ai_economy`, `ai_combat`, `ai_crawlers`, `ai_mining`, `ai_difficulty_smoothing`, ...) | Issue orders, no rendering | Unchanged |
| `GridWorld._cells` | Simulation source of truth | Unchanged; re-rendered as 3D terrain |
| Custom A* pathfinding (`find_path_underground`, etc.) | Grid-based | Unchanged for 2.5D; replaced only in Phase 3 |
| Unit stats / research / factions (`.tres` resources) | Data-driven | Unchanged |
| GUT test suite (~55 files) | Headless simulation tests | Keeps passing — the safety net for the whole port |
| HUD / menus (`hud.tscn`, `main_menu.tscn`, radial build menu) | `Control` nodes | Unchanged — Controls overlay 3D viewports identically |
| Tile rendering via `_draw` | CanvasItem per-frame draws | Replaced (GridMap / meshes) |
| `player_camera.gd` | 2D pan/zoom | Rewritten as a 3D rig |
| Effects / weather visuals | 2D particles, `_draw` | Re-created as 3D particles/shaders |
| Fog of war | Fog maps + 2D overlays | Re-implemented as shader/fog-volume |

The rule of thumb: **if a script never calls `_draw`, `CanvasItem`, or
`Sprite2D`, it probably survives untouched.**

## Trade-offs we are accepting

- **Web build performance**: 3D on `gl_compatibility` (the web renderer)
  is materially weaker than our current 2D web build. We accept reduced
  web fidelity until/unless we do the Phase 1 web performance audit.
- **Pixel-art identity**: day one, units render as billboarded sprites in
  a 3D world (keeps current art, including the generated crawler /
  engineer / pigeon sprites). Low-poly models come in Phase 2.
- **Tab layer views stay**: in 2.5D the underground remains a separate
  flat plane per layer; the camera jumps between them. No true vertical
  mine until Phase 3.

## Phases

| Phase | Doc | Goal | Ship-able? |
|---|---|---|---|
| 0 | [phase-0-spike.md](phase-0-spike.md) | Prove the feel: 3D camera looking at the current 2D world on a plane | No (throwaway branch) |
| 1 | [phase-1-25d-port.md](phase-1-25d-port.md) | Full game playable in 2.5D with existing art; ALL sim code + tests unchanged | **Yes** |
| 2 | [phase-2-art-pass.md](phase-2-art-pass.md) | Low-poly units, terrain materials, lighting; Frostpunk mood | Yes (this is a release) |
| 3 | [phase-3-full-3d.md](phase-3-full-3d.md) | Optional: true vertical mine, 3D pathfinding, free-ish camera | Yes, if attempted |

## Hard rules for every phase

1. The game must remain winnable/losable and exportable at the end of
   every phase that ships.
2. No phase may break the GUT suite. If a test breaks, the port — not
   the test — is wrong (unless the test asserted on rendering, which
   none should).
3. Simulation code never reads from the visual layer. The 3D world is a
   projection of `GridWorld._cells` + unit positions, never the other
   way around.
4. Keep a `2d-legacy` tag before merging Phase 1 so we can always diff
   or bail out.
5. One rendering concern per PR. No "while I'm here" refactors of AI or
   economy — that code is battle-tested.
