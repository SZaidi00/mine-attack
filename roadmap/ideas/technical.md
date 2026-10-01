# Technical Ideas

Engineering hygiene, CI, and performance. Do the first two items before
heavy feature work — they make everything else safer.

## CI & automation

- [ ] **GitHub Actions for the GUT suite** — headless GUT run on every
      PR (`godot --headless --path . -s addons/gut/gut_cmdln.gd
      -gdir=res://tests -gexit`). The pre-push hook only guards
      `main`; branches currently have no net. Tracked in IDEAS.md.
- [ ] **CI: format & lint** — `gdformat`/`gdlint` in the same workflow
      so style debates never happen in PR reviews.
- [ ] **CI: headless export smoke test** — run `tools/export_all.sh` (or
      just the web preset) on PRs so export breakage is caught before
      the pre-push release hook fires.

## Performance

- [ ] **Web performance audit** — flagged in IDEAS.md; profile
      `gl_compatibility` + per-frame `_draw` costs with a large army
      *before* adding visual features, and again as the Phase 1 gate
      for the 3D port.
- [ ] **Perf regression check in CI** — capture frame-time stats from a
      scripted headless scenario; fail on large regressions. Only worth
      building after the audit gives us a baseline.

## Architecture notes (reference, not tasks)

- Simulation/render split is the load-bearing convention: autoloads and
  AI never touch rendering, and the 3D roadmap depends on it. Keep it
  that way — new features enter through the sim layer first.
- `.tres` data-driven units/research/factions is why content additions
  (engineer, crawler, necromancy) shipped fast; extend the pattern.
- The `improvements/IDEAS.md` status legend applies here. When an item
  here is also tracked there, update both (or migrate it here).
