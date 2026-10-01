# Feature Ideas & Known Issues

This subfolder collects proposed features and improvements beyond the
3D conversion, grouped by area. Status legend (same as
`improvements/IDEAS.md`): `[ ]` not started, `[~]` in progress,
`[x]` done.

Overlap with `improvements/IDEAS.md` is intentional — items listed there
are cross-referenced rather than duplicated in detail.

## Files

- [gameplay.md](gameplay.md) — new mechanics, modes, and content
- [ux-polish.md](ux-polish.md) — controls, UI, feedback, accessibility
- [technical.md](technical.md) — CI, performance, engineering hygiene

## Quick wins (do these first)

1. **Attack/threat alerts** — ping + edge indicator when miners or the
   base are under attack. (ux-polish.md)
2. **Post-game coaching hints** — use `MatchStats` logs to show 2–3
   concrete "what went wrong" tips. (ux-polish.md)
3. **Floating damage numbers / hit feedback.** (ux-polish.md)
4. **CI for the GUT suite** — protect branches before any of the above
   lands. (technical.md)
5. **Control groups + attack-move** — already tracked in
   `improvements/IDEAS.md`; highest gameplay value per effort.
