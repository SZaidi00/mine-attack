# Plan 04 — Roadmap docs refresh

Status: Done
Size: S
Depends on: —

## Mission
Bring the 3D-conversion roadmap documents back in line with the code on
`feat/3d-conversion`, so the branch's own record stops contradicting itself
before it merges.

## Context (what is stale, verified against the code)
- `roadmap/3d-conversion/phase-0-findings.md`:
  - Claims "Script changes needed: none" — false now. Sim-side files changed on
    this branch include `grid_world.gd` (SURFACE_ROWS/SURFACE_TOP,
    `is_surface_row`, `player_fog_revision`, fog-change accumulator),
    `grid_map_generation.gd` (band generation, border walls, A* region),
    `grid_pathfinding.gd` (band snap + underground band sealing),
    `wall_segment.gd` (full-band column sealing, `_wall_sealed_cells`),
    `building.gd` (footprint seals band rows), `grid_fog_of_war.gd`
    (revision diffing), `lantern.gd`/`tower.gd` (bounds at own row),
    `unit_navigation.gd` (stand/walkable bounds), `unit_combat.gd` (3D popup
    branch), `main_menu.gd` (Play loads `main_3d.tscn`).
  - Go/no-go checklist: 3 of 4 items still "pending playtest", 1 checked.
- `roadmap/3d-conversion/phase-1-progress.md`:
  - M3 (control scheme) shows **Not started**, but the branch ships
    `_screen_to_world` mouse-ray picking, selection rings (`selection_rings_3d.gd`),
    order markers, attack telegraphs, build ghosts (`build_ghost_3d.gd`),
    range discs.
  - M4 (fog/weather/effects) shows **Not started**, but ships `fog_3d.gd`,
    `effects_3d.gd`, `event_proxies_3d.gd`, damage popups.
  - M5 (tests/exports/release) shows **Not started**, but the branch adds ~17
    new GUT files and `export_presets.cfg` targets Web/macOS/Windows/Linux.
- `AGENTS.md` does not yet mention `plans/` (this directory).

## Task
1. Read `phase-0-findings.md`, `phase-1-progress.md`, and skim
   `phase-1-25d-port.md` / `style-guide.md` for tone. Read the actual code for
   anything you assert — the lists above are pointers, not ground truth.
2. `phase-0-findings.md`: replace the "Script changes needed: none" section
   with an accurate "sim changes on this branch" list (files + one line each,
   like the pointer list above but verified). Reword the go/no-go items:
   mark what is now verifiable headlessly (camera/terrain reads via the
   capture harness, 60fps via the BENCH probe numbers — cite where numbers
   live, e.g. `tools/capture/README.md`), keep the genuine feel judgments
   (camera feel, tile readability) marked *pending playtest* — do not claim
   they passed.
3. `phase-1-progress.md`: update the milestone table — M3/M4 **Done** with a
   one-line pointer to the implementing files; M5 **Partially done** (tests
   green per suite, exports configured, human playtest + actual release
   pending). Mark carried-forward "known gaps" that have since shipped as
   done or strike them with a note; keep genuinely open items open (e.g.
   box-select — unless plan 02 has landed, in which case close it).
4. `AGENTS.md`: add `plans/` (with one line: "Kimi Code implementation
   plans — see plans/README.md") to the project-structure tree.
5. If a plan from `plans/` has landed by the time you run, reference its PR
   number; otherwise reference the plan file.

## Constraints
- Docs only: no code changes beyond `AGENTS.md`'s tree listing. `git diff
  --stat` must show only markdown.
- Do not mark playtest-dependent items as passed — honest status only.
- Match the existing doc voice (concise, technical, no marketing).

## Verification
```bash
git diff --stat   # only *.md files
grep -rn "Not started" roadmap/3d-conversion/   # no stale milestone rows left
```
Render check: open both files in any markdown viewer and confirm tables/lists
are well-formed.

## Acceptance criteria
- [ ] "Script changes needed: none" replaced with an accurate verified list
- [ ] Milestone table reflects shipped M3/M4, honest M5
- [ ] Go/no-go distinguishes headlessly-verified from playtest-pending
- [ ] `AGENTS.md` mentions `plans/`
- [ ] Only markdown files touched

## Out of scope
- Rewriting the roadmap planning docs (`phase-1-25d-port.md` etc.)
- The `improvements/` docs
- Performing the playtest (human task)
