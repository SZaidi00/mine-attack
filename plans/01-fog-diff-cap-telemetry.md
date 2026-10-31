# Plan 01 — Fog-diff-cap telemetry

Status: Not started
Size: S
Depends on: —

## Mission
Make the fog-of-war change-detection cap observable, and guarantee fog
visuals recover fully when the cap is exceeded, so a large reveal burst can
never leave stale fog tint on the 3D board.

## Context
- `scripts/world/grid_fog_of_war.gd` diffs the player's per-cell fog state
every frame and accumulates changed cells into a change list on `GridWorld`
(consumed via `GridWorld.consume_player_fog_changes()`), bumping
`GridWorld.player_fog_revision`. The accumulator is **capped (≈512 cells per
revision)** — read the actual constant in code.
- `scripts/three_d/fog_3d.gd` and `scripts/three_d/terrain_3d.gd` poll the
revision at their refresh cadence and apply incremental updates from the
consumed change list. `Terrain3D` also has a ~5 s full-rebuild backstop;
`Fog3D` is revision-gated only.
- Consequence: if more cells change in one frame than the cap allows (big
lantern reveal, mass identify, wall breach opening sight lines), the overflow
cells are silently dropped. `Fog3D` then never learns they changed and their
tint stays stale indefinitely.
- Today nothing logs or flags the overflow, so the failure mode is invisible.

## Task
1. Read `scripts/world/grid_fog_of_war.gd`, `scripts/world/grid_world.gd`,
   `scripts/three_d/fog_3d.gd`, `scripts/three_d/terrain_3d.gd` first.
2. When a frame's diff exceeds the accumulator cap, record the overflow:
   expose a public flag on `GridWorld` (e.g.
   `player_fog_overflow: bool`, cleared on consume) and log once per revision
   via `DebugLog.log_reject(...)` + `push_warning(...)`, including the dropped
   cell count. Follow the file's existing style for public API.
3. Make the recovery path explicit: when `Fog3D` consumes changes and the
   overflow flag is set, fall back to a **full fog refresh** (the same path a
   reveal-all uses) instead of an incremental one, then clear the flag.
   `Terrain3D`'s existing backstop can stay as-is.
4. Add a GUT test (extend `tests/test_3d_fog.gd` or add a focused new file):
   force more changed cells in one revision than the cap (drive the internal
   reveal/diff path directly or place enough T3 lanterns to blow past the cap
   — follow how existing tests force reveals), then assert (a) the overflow
   flag/log fired, and (b) after one `Fog3D` refresh every changed cell's
   visual state matches `fog_state_at`.

## Constraints
- Do not raise the cap and call it done — the cap exists to bound per-frame
  work. The task is observability + guaranteed recovery.
- Sim → render only: the flag lives on the sim (`GridWorld`), the 3D side
  only reads it. No 3D→sim writes.
- `Fog3D` full-refresh fallback must reuse its existing full-refresh path, not
  a second one.

## Verification
```bash
# Single-file run (do NOT add -gdir — GUT 9.7 union bug)
godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/test_3d_fog.gd -gexit
# Whole suite stays green
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit
```

## Acceptance criteria
- [ ] Overflow produces a visible warning (DebugLog + push_warning) with counts
- [ ] Overflow triggers a full `Fog3D` refresh; no stale tint after one refresh
- [ ] New/updated GUT test fails if the fallback is removed (verify by briefly
      reverting the fallback in the working copy and watching it go red)
- [ ] Full GUT suite green

## Out of scope
- Changing the cap value, chunking the diff, or any perf rework
- The 2D fog overlay (it redraws from state, unaffected)
