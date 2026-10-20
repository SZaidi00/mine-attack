# Phase 6 — Model & Structure Redesign (conditional)

**Parent plan:** `roadmap/3d-rework/README.md` (read it first for rules).
**Depends on phases 2, 3, 4.** This phase is CONDITIONAL: only start it if,
after camera/scale (2), lighting/post (3), and palette (4) have landed, the
game still looks "old school" in screenshots. Phases 2–4 change how the
models are *presented*; this phase changes the *models themselves* — the most
expensive and most subjective work in the rework.

## Current state (verified)

- All unit models are procedural primitive rigs built in
  `scripts/three_d/unit_model_3d.gd` (humanoids 0.34–0.38 world units tall,
  ≤60 primitives each per the style guide budget). Silhouette rules per unit
  are defined in `roadmap/3d-conversion/style-guide.md` (miner pickaxe +
  helmet lamp, swordsman blade, archer bow, wizard hat + staff, dragon
  wingspan, etc.).
- Structures are procedural in `scripts/three_d/structure_proxy_3d.gd`:
  keep = box + pyramid roof + banner + faction trim (6×5 cells), tower =
  squat cylinder + cap, wall = chunky block with capstone, lantern = post +
  glowing head, mine entry = A-frame. Towers/walls have 3 damage states
  (tilt + darken + rubble, `structure_proxy_3d.gd:434-452`).
- Animation is procedural and state-driven (idle bob, walk swing, attack
  lunge, death topple) — see the style guide's Animation section.
- Faction identity today = accent trims only (violet/red/brass on
  belts/shields/hat cones/wing tips). Bodies are team-colored.

## Why this is last

SC2 and They Are Billions units are geometrically simple — their readability
comes from scale exaggeration, value separation, and post-processing, all of
which phases 2–4 deliver. Redesigning models before those land risks burning
effort on geometry that was never the problem. It also churns every visual
test screenshot and is the hardest change to A/B objectively.

## Goals (in priority order)

1. **The keep as centerpiece.** The enemy base is the win condition and the
   faction-reveal moment — it should be the best-looking thing on the board.
   Replace the box + pyramid roof with a multi-part silhouette: battlemented
   main hall, asymmetric tower, faction-specific crown (Arcane: crystal
   spire; Brute: horned skull gate; Industrial: smokestack + gears), animated
   banner, chimney smoke (routed through `effects_3d.gd` particle budget).
   Enemy faction crown must swap visibly on identification (the re-tint hook
   already exists at `structure_proxy_3d.gd:171-179` — extend it to geometry).
2. **Proportion exaggeration on units.** Following SC2's rule (oversized
   weapons, heads, shoulders): swordsman's blade +50% length, archer's bow
   readable at max zoom-out, wizard hat wider than shoulders, dragon wingspan
   from ~1.2 to ~1.6 world units. Stay within the phase-2 proxy scale so
   footprints don't change.
3. **Faction-distinct silhouettes beyond color.** Per-faction helmet/shoulder
   variants on swordsman/archer (Arcane: pointed, Brute: horned/heavy,
   Industrial: riveted/boxy). Same skeleton and animation code — only the
   primitive recipe varies by faction.
4. **Structure variety.** Towers get faction caps (crystal / spike / vent);
   walls get crenellation + a faction capstone; lanterns get three visibly
   different head geometries per tier (today only light range/energy
   changes). Mine entry: deeper shaft illusion (dark gradient + support
   beams receding).
5. **Raised primitive budget.** Style guide cap of ≤60 primitives/unit can go
   to ~100 on Fancy if the 200-unit stress test holds; Potato/Standard keep
   the current recipes via `ArtStyle3D.detail_enabled()`. Poly budget is a
   hard gate, not a suggestion.

## Non-goals

- No imported/textured models, no skeletal animation — the procedural
  flat-shaded style stays (style guide: "flat-shaded stylized low-poly").
- No sim changes: footprints, vision, hit feedback timing untouched.
- No animation system rewrite; proportion changes must reuse the existing
  state-driven animation.

## Steps

1. Screenshot board + every unit at default/max zoom in all four lighting
   moods as the pre-redesign baseline; file them next to this plan.
2. Redesign the keep (goal 1) first and get sign-off on screenshots before
   touching anything else — it sets the bar.
3. Unit proportion pass (goal 2), one unit type at a time, style-guide
   silhouette table updated per unit.
4. Faction variants (goal 3), then structure variety (goal 4).
5. Budget check: profile 200+ units on Fancy and Standard; if frame time
   regresses, move detail behind `detail_enabled()` until it passes.
6. Update `roadmap/3d-conversion/style-guide.md` (silhouette table, poly
   budget, faction rules) and `AGENTS.md`'s `scripts/three_d/` description.

## Acceptance criteria

- Before/after screenshots at identical camera settings show a clear quality
  jump for the keep and at least the swordsman/archer/wizard.
- Every unit still passes the style-guide rule: identifiable by silhouette
  at max zoom-out — with phases 2+4 landed, this must hold in the underground
  mood too.
- Enemy faction reveal changes the enemy keep's silhouette, not just colors.
- 200+ units at 60 fps on Fancy; Standard/Potato recipes unchanged.
- Full test suite green
  (`godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests
  -gexit`); update `tests/test_3d_structure_models.gd` and any test asserting
  model part counts.
