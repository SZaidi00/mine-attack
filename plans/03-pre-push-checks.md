# Plan 03 — Pre-push checks (budget gate + GUT)

Status: Done
Size: S
Depends on: —

## Mission
Make the two repo health checks that currently run only by hand — the GLB
budget gate and the GUT suite — run automatically in the pre-push hook, with
an escape hatch, so "green" claims are reproducible for everyone.

## Context
- There is **no CI** in this repo (no `.github/workflows`).
- `.githooks/pre-push` currently: on pushes to `main` only, runs
  `tools/export_all.sh` and publishes macOS/Windows/Linux release zips via
  `gh release create`. It runs NO checks.
- `tools/check_model_budgets.sh` gates every manifest entry's triangle count
  vs its `tri_gate`, per-image ≤2048², and the 64 MB total embedded-texture
  web budget. Exit codes: 0 pass / 1 budget fail / 2 tooling error. Pure-python
  GLB parser by default; needs only `python3`.
- The canonical headless test command (from `AGENTS.md`):
  `godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit`
- The hook already has a `SKIP_RELEASE=1` convention and a Homebrew-PATH
  workaround for `gh`; mirror both patterns.

## Task
1. Add `tools/run_checks.sh`: a small wrapper that runs, in order,
   (a) `tools/check_model_budgets.sh`, then (b) the headless GUT suite if a
   Godot binary is found (`godot` on PATH, else the same fallback paths
   `tools/export_all.sh` uses, else `GODOT` env var). Any failure exits
   non-zero with a clear message. If no Godot binary is found, run only the
   budget gate and print a prominent warning that tests were skipped (exit 0).
2. Wire it into `.githooks/pre-push` for `refs/heads/main` pushes, **before**
   `tools/export_all.sh`: if `SKIP_CHECKS` is not `1`, run
   `tools/run_checks.sh`; on failure, abort the push with an actionable
   message (`SKIP_CHECKS=1 git push origin main` to bypass). Keep
   `SKIP_RELEASE=1` behavior unchanged.
3. Update `AGENTS.md`: the "Automated releases" section (checks now run
   first, `SKIP_CHECKS` documented) and the "Check imported-model budgets"
   section (the wrapper exists).
4. Prove the failure path safely: copy the budget gate to a temp dir with a
   crafted manifest whose `tri_gate` is below the actual triangle count, run
   the embedded checker against it, and confirm exit 1 — paste the transcript
   into the PR. Do NOT temporarily weaken the real manifest or the gate.

## Constraints
- The budget gate and GUT commands stay the single source of truth; the
  wrapper only sequences them. Do not fork check logic into bash.
- Never weaken `tools/check_model_budgets.sh` or `model_manifest.json` to make
  anything pass.
- macOS GUI-git PATH workaround: reuse the existing `gh` fallback loop style.

## Verification
```bash
bash -n tools/run_checks.sh && bash -n .githooks/pre-push
tools/run_checks.sh            # expect PASS on a clean checkout
git config core.hooksPath .githooks   # if not already enabled locally
```
Paste both transcripts + the injected-failure transcript into the PR.

## Acceptance criteria
- [ ] `tools/run_checks.sh` runs budget gate + GUT (or warns + skips tests
      when no Godot binary exists)
- [ ] Pre-push aborts a `main` push on red checks; `SKIP_CHECKS=1` bypasses;
      `SKIP_RELEASE=1` still skips only the release
- [ ] Injected-failure demonstration shows exit 1 (transcript in PR)
- [ ] `AGENTS.md` documents the new behavior
- [ ] No changes to the gate logic itself or to any GLB/manifest data

## Out of scope
- GitHub Actions / any hosted CI
- Running BENCH or capture harness in the hook (too slow for a push)
- Web-export verification
