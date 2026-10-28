    # Attach order for Kimi Code

Always attach: `README.md` (the roadmap overview with the 27-item decision log) — untagged, goes in every session.

Then attach, in this order, stopping at the phase you're working on:

1. `01-phase-plan.md` — what to build, in what order, with acceptance criteria per phase. Start every session here to find your phase (R2 is next).
2. `02-art-direction.md` — the palette, materials, lighting rules, Minas Morgul fortress spec. Needed for R2 (art tokens) and every later look decision.
3. `03-technical-plan.md` — height-field terrain, two-mode camera, fog/breach, GLB pipeline details. Needed from R3 onward.
4. `04-asset-pipeline.md` — import conventions, face budgets, model manifest format, next-generation prompts. Needed when you touch models (R4).

`optional-baselines/` — the five "before" captures (current primitive state). Attach them only when you want the agent to see what the game looks like today; the docs describe it, so they're optional.

Name mapping (the docs cross-reference each other by their repo filenames):
`01-phase-plan.md` = repo `04-phase-plan.md` · `02-art-direction.md` = repo `01-art-direction.md` · `03-technical-plan.md` = repo `03-technical-plan.md` · `04-asset-pipeline.md` = repo `02-asset-pipeline.md`.

Not included, on purpose:

- The five `.glb` files — they go into the repo (`unzip -o` at repo root, commit, push to the PR branch), not into agent chats. The agent reads them from `frost_mines_assets/models/structures/`.
- Preview PNGs — human reference only.
