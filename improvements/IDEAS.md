# Improvement Ideas

Proposed improvements for MineAttack, grouped by area. Status legend: `[ ]` not started, `[~]` in progress, `[x]` done.

## High impact

- [x] **Post-match stats & match logging** — match-end screen with graphs/numbers (coin mined over time, army size, damage dealt) plus a per-match JSON log from the autoloads to feed balance analysis. (Implemented: `MatchStats` autoload, game-over summary table + `MatchGraph` coin/population charts, JSON logs in `user://match_logs/`.)
- [ ] **AI difficulty smoothing** — adaptive difficulty that nudges `game_manager.gd` modifiers mid-match instead of only fixed tiers (Easy → Godly); builds on `AIBeliefSystem` and smarts tiers.
- [ ] **Save/resume mid-match** — `user://savegame` snapshot of grid state + unit/structure state; state already lives mostly in serializable autoloads and `GridWorld._cells`.

## Gameplay depth

- [ ] **Map seed / map archetypes** — expose the RNG seed or 2–3 archetypes (narrow shaft, wide field, rich-center) via `grid_map_generation.gd`.
- [ ] **More unit counters** — cheap early anti-air option, or a support unit (healer/engineer that repairs walls/towers) rather than more raw units.
- [ ] **Underground combat** — tunnel skirmishes, or research that lets you collapse a tunnel on enemy miners; makes the two layers interact.

## UX polish

- [ ] **Control groups (Ctrl+1–9)** — saved selection groups; natural home is `player_selection.gd`.
- [ ] **Attack-move (A+click)** — per-order attack-move instead of only the global Attack stance.
- [ ] **Minimap** — canvas-drawn minimap fed by `GridWorld` fog maps; ties fog, layers, and lava events together visually.

## Technical

- [ ] **Web performance audit** — profile `gl_compatibility` + per-frame `_draw` in units/grid with a large army before adding visual features.
- [ ] **CI for the GUT suite** — GitHub Actions job running the headless GUT command on PRs (the pre-push hook only fires on pushes to `main`).
