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

- [x] **Web performance audit** — 3D presentation perf pass (2026-10):
      per-frame unit sync is change-detected (fog-hidden/off-layer proxies
      early-out, dune re-sample on movement/field revision), fog/terrain
      rebuilds are event-driven off `GridWorld.player_fog_revision` instead
      of unconditional 0.5s timers, quality presets carry a render scale
      (Potato 0.75, web Standard 0.85, FSR where supported) plus MSAA 2x on
      desktop Fancy, shadows are 2-split 2048² (was 4-split 4096²), and the
      structure GLB textures dropped 2048² → 1024² (17.8 → 6.0 MB embedded).
      Remaining owner check: 60 fps @ 200+ units on real hardware (F3 debug
      overlay now shows frame ms, draws/tris, and per-section script ms).
- [ ] **Perf regression check in CI** — BENCH mode exists locally
      (`STRESS_UNITS=100 BENCH=30` in tools/capture prints per-section
      script-time averages via Probe3D; script ms stay meaningful under
      software GL where GPU frame times do not). The automated CI gate on
      top of it is not wired yet.

## Architecture notes (reference, not tasks)

- Simulation/render split is the load-bearing convention: autoloads and
  AI never touch rendering, and the 3D roadmap depends on it. Keep it
  that way — new features enter through the sim layer first.
- `.tres` data-driven units/research/factions is why content additions
  (engineer, crawler, necromancy) shipped fast; extend the pattern.
- The `improvements/IDEAS.md` status legend applies here. When an item
  here is also tracked there, update both (or migrate it here).
