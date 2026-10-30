# Kimi Code Implementation Plans

This directory is a self-contained work queue for Kimi Code (or any coding
agent). **To implement something, attach this README plus exactly one plan
file to the agent and say "implement plan NN".** The README carries the global
repo contract; each plan carries everything else — context, exact files,
acceptance criteria, and verification commands. No other document is needed,
though `AGENTS.md` is worth a skim for deeper background.

Every plan is written to be executed **standalone on branch
`feat/3d-conversion`** (the 3D conversion branch, which PR #6 tracks).

## Global repo contract (applies to every plan)

### Stack
- Godot 4.7 (standard, not .NET), GDScript with static typing on function
  signatures. `forward_plus` on desktop; `gl_compatibility` for web/mobile
  overrides. No external package manager.
- Language for code/comments/docs: English. Naming: `snake_case` files,
  functions, variables; `PascalCase` classes/scenes; `_` prefix for privates.

### The one hard rule: presentation-only
The 3D shell mounts the untouched `scenes/main.tscn` sim at `/root/Main` and
renders from it. **Sim → render only; the 3D layer never writes back to the
sim.** Any plan that seems to require writing sim state from 3D code is
misreading the architecture — find the sim-side hook instead.

### Contracts you must not break
- `/root/Main/...` hard-coded paths: 86 references across 57 files resolve the
  live sim. Never rename `Main` or its children.
- Surface band: the walkable surface is 6 rows, `y ∈ [GridWorld.SURFACE_TOP,
  GridWorld.Y_MIN]` = `[-5, 0]`; underground is `y >= 1`. Use
  `GridWorld.is_surface_row(y)` — never `y == 0` checks.
- Quality tiers: `ArtStyle3D` POTATO / STANDARD / FANCY. New visual work must
  degrade (fewer instances, no shadows, skipped effects on Potato). Check
  `ArtStyle3D.detail_enabled()` / `particle_mult()` patterns.
- Fog honesty: anything rendered from sim state the player can't see must gate
  on `GridWorld.fog_state_at(GameManager.Team.PLAYER, pos)` (0 = visible,
  1 = remembered, 2 = hidden). Mirror the existing patterns rather than
  inventing new ones.
- GLB asset contract (R7/R4): all imported models are registered in
  `frost_mines_assets/models/model_manifest.json` and validated by
  `scripts/three_d/model_manifest.gd` (origin base at min-y 0, footprint/height
  > 0, `tri_gate ∈ [6000, 8000, 12000, 25000, 60000]`, slot arrays).
  `tools/check_model_budgets.sh` gates tri counts, ≤2048² textures, and a 64 MB
  total embedded-texture web budget. Never commit a GLB without a manifest entry.

### Commands (from `AGENTS.md`; re-verify paths still exist before relying on them)
- Full GUT suite headless:
  `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
- Single test file (IMPORTANT GUT 9.7 gotcha: do NOT pass `-gdir` with
  `-gtest`; they union and run everything):
  `godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/<file>.gd -gexit`
- Model budget gate: `tools/check_model_budgets.sh` (exit 0 pass / 1 fail / 2 tooling error)
- Resize over-cap textures: `python3 tools/resize_glb_textures.py [--max=N] [--only=SUBSTR]`
- Regenerate unit GLBs: `python3 tools/gen_unit_glbs.py [--validate-only]` (Pillow required)
- Exports: `tools/export_all.sh` (GODOT=/path/to/Godot to override)
- Deterministic screenshots + perf bench (needs xvfb on Linux):
  `tools/capture/run_capture.sh /tmp/shots`
  `STRESS_UNITS=100 BENCH=30 SHOTS="" tools/capture/run_capture.sh /tmp/bench`

### Testing conventions (gotchas that bite)
- Tests that instantiate `scenes/main.tscn` must `_main.free()` in `after_all`,
  not `queue_free()` (node-name collisions on the next test script).
- Deterministic tests call `seed(12345)`; `GridWorld` map generation uses its
  own RNG seeded from `GameManager.map_seed` (does NOT follow the global
  stream). Pin a map with `GameManager.set_map_seed(n)` in setup and
  `GameManager.clear_map_seed()` in teardown when a fixed map matters.
- Tests that flip settings write `user://settings.cfg` for real — restore
  prior values in `after_all` (see `tests/test_settings_volume.gd`).
- Weather/dynamic events: disable random scheduling and force triggers
  (`WeatherManager.set_weather_events_enabled(false)`,
  `set_volcano_events_enabled(false)`, `GridWorld.set_dynamic_events_enabled(false)`).

### Repo automation reality
There is **no CI**. `.githooks/pre-push` runs `tools/export_all.sh` and
publishes macOS/Windows/Linux GitHub releases on pushes to `main` only. All
test/budget verification today is manual — plan 03 changes that.

## Plan index

| # | Plan | Size | Depends on |
|---|------|------|------------|
| 01 | Fog-diff-cap telemetry | S | — |
| 02 | 3D box-select via rig camera | M | — |
| 03 | Pre-push checks (budget gate + GUT) | S | — |
| 04 | Roadmap docs refresh | S | — |
| 05 | Play-mode setting (3D default / 2D legacy) | S | — |
| 06 | Prop GLB import pipeline + first batch | M | 03 |
| 07 | Seeded surface prop scattering | M | 06 |
| 08 | Unit animation clips on R7 pivots | L | 06 |

Sizes: S ≈ a focused day, M ≈ 2–4 days, L ≈ a week+. "Depends on" is a soft
ordering for humans; each plan is still self-contained for the agent.

## Workflow rules for the implementing agent
1. Branch per plan: `plan/NN-slug` cut from `feat/3d-conversion`; PR back into
   `feat/3d-conversion`.
2. Read the files the plan's Context section names **before** writing code —
   the plan states intent and contracts, the code is the source of truth for
   mechanics.
3. Run the plan's Verification commands yourself; paste outputs into the PR.
4. Update the plan file's `Status:` header (Done / Blocked + why) in the same
   PR that implements it.
5. If a plan's assumption turns out wrong (file moved, contract changed),
   stop and reconcile the plan text instead of silently improvising.
6. Never touch `addons/gut/` or `frost_mines_assets/models/model_manifest.json`
   gates to make checks pass — fix the assets or the code instead.
