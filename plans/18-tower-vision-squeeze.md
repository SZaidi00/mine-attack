# Plan 18 — Squeeze tower vision below the surface-band height

Status: Done (2026-11-01)
Branch: `kimi-code-plans`
Depends on: 17

## Why

`TOWER_VISION` was 10 cells — as tall as the entire 10-row surface band
(`y ∈ [-9,0]`) and then some. One tower placed anywhere (worst case: a
central row) lifted fog over the **whole band width**, so a single structure
substituted for the lantern network the fog system was built around (the
lantern comment in `constants.gd` already states the intent: no single
structure may light everything). The player asked for towers to cover less,
forcing a second tower and/or lanterns ("lightposts") for full-width
coverage.

## Change

- `scripts/autoload/constants.gd`: `TOWER_VISION` 10 → **4** (surface only).
  4 is the largest integer radius that cannot cover the 10-row band from any
  single row: at row −4 it misses row −9 (Euclidean check 25 > 16), at row −5
  it misses row 0. Two sources (e.g. towers at rows 0 and −9, or a tower plus
  a T2 lantern) are needed for full-height coverage. Comments rewritten:
  vision is now deliberately **shorter than attack range** (8) — a lone tower
  out-shoots its own sight and depends on the team's lanterns/pigeons/units
  to spot far targets, mirroring the lantern-coverage rationale.
- `scripts/world/tower.gd` class docstring and the `grid_fog_of_war.gd`
  tower-source comment: same "shorter than attack range since plan 18"
  wording (the mechanics code is unchanged — vision already flowed through
  the dedicated `vision_radius`).
- Tests (probes that sat 9–10 cells out, inside the old radius):
  - `tests/test_structures.gd::test_tower_invulnerable_while_building_then_fires`:
    under-construction probe and the 9/10/11-cells assertions moved to
    4/5 cells out (`(-8,0)` edge lit, `(-7,0)` hidden). The firing check is
    untouched (the intruder stands 2.5 cells out, inside vision 4).
  - `tests/test_fog_of_war.gd`: the three tower team-isolation/remember tests
    probed `(-20, SURFACE_TOP)` — 9 rows up, now dark. New probe `(-16, 0)`,
    4 cells out at the tower's edge and clear of the plan-17 base's 6-cell
    vision (`(-20,-4)` would have been base-lit: dx 5, dy −2 → 29 ≤ 36).
    The layer-lock test probes `(-45,-4)` instead of `SURFACE_TOP`.
  - `tests/test_3d_fog.gd::test_built_tower_clears_surface_fog_but_not_the_cell_below`:
    surface probe moved to `(-45,-4)` (4 rows up, at the new edge); the
    underground-hidden half of the test is unchanged.
- `plans/README.md`: stale "bases at `±40`" contract line corrected to
  `(±25,-2)` (plan 17 value) while editing.

## Gameplay consequences (accepted)

- Towers see 4 cells but still shoot 8: at max range they need a spotter
  (lantern, pigeon, or unit vision) — shared team vision, standard RTS rule.
  Towers alone now reveal less on approach, so storms + rushes pressure
  tower-only defenses harder.
- The AI builds towers/lanterns through the same constants, so both teams
  are equally affected; AI defensive lanterns (ai_awareness) become
  relatively more valuable.
- Legacy 2D profile: tower vision along the single row shrinks 10 → 4 cells
  too (one shared constant, same as the shared lantern radii) — accepted as
  a legacy balance shift rather than adding a profile override.

## Out of scope / non-changes

- Attack range (`TOWER_RANGE_CELLS` 8), damage, HP, build time: untouched.
- Lantern radii (T1 4 / T2 7 / T3 10): untouched — a T2+ lantern already
  covers the band vertically by design.
- The HUD build-menu tooltip interpolates `TOWER_VISION` and updates itself
  ("doubles as a 4-cell vision source").

## Verification

- Focused: `test_map_definition`, `test_fog_of_war`, `test_3d_fog`,
  `test_structures`, `test_weather`, `test_tech_branches` — green.
- Full: `tools/run_checks.sh` → PASS (budget gate + headless GUT suite).
