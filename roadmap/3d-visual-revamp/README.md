# 3D Visual Revamp — Overview

**Status:** R1–R2 accepted (baseline captures under `baseline/`, R2 captures
under `r2/`); R3 implemented (height-field dunes; harness captures pending
owner/CI run); R4 implemented (structure GLB pipeline + Minas Morgul
fortress; harness captures pending owner/CI run); R5 implemented (two-mode
camera + capture posing API; captures under `r5/`); R6 implemented (opaque
fog void + lantern pools + first-wall-breach moment; captures under `r6/`);
R7 implemented (sculpted textured unit GLBs + shared-rig faction variants;
surface/underground captures for all three factions under `r7/`); R8
implemented (cold-glass/brass UI, Cinzel display type, production/research
progress dials, and six showcase captures at 1080p/4K under `r8/`). Owner
visual sign-off and real-hardware 200-unit performance validation remain
pending. Final art-style polish review remains with the owner.
**Parent:** `roadmap/3d-rework/README.md` (phases 1–5 implemented there; read it
for the hard rules that still apply).
**Branch:** `feat/3d-conversion`.

This revamp supersedes the *conditional* phase 6 of the 3D rework. The trigger
condition fired: with camera/scale, lighting/post, and palette landed, the game
still reads as flat-shaded primitive low-poly rather than the intended
Frostpunk-cold industrial-fantasy RTS. The owner decision (2026-10-28): move
away from the procedural flat-shaded style entirely and rebuild the visual
layer around **textured, imported models** and a **height-field surface**.

## Decision log (owner answers, 2026-10-28)

| # | Decision |
|---|---|
| 1 | Stay in **Godot** — no engine change. |
| 2 | Export targets: **macOS + Windows** primary; **browser (web export) in scope** (cheap to add in Godot). Mobile descoped. |
| 4 | Reference feel: **They Are Billions / StarCraft** surface RTS (build a region, fog of war lifted by structures, build-time loaders, send units where you want) + **SteamWorld Dig** underground (darkness lifted by lanterns). Current visuals undershoot this: too low-poly, interaction not smooth, surface doesn't read as an RTS. |
| 5 | Everything visual is high priority: camera, lighting, materials, UI/UX. |
| 6 | Art bar: games made with K3.1, e.g. *The Lantern Compact* (https://7dhjuvcwxja7k.ok.kimi.link) — stylized, cohesive palette, dense detail, quality UI. See `01-art-direction.md` §Reference analysis. |
| 7 | Visual verification via the headless capture harness (`tools/capture/`) — already merged. |
| 8 | **Textured models + real asset imports** replace the procedural flat-shaded primitives. |
| 9 | Mood: **Frostpunk cold**. Not cinematic, not gritty, not cozy, not toylike. Between **industrial and fantasy** (magic exists via the units). |
| 10 | **Height-field surface** — experiment with **rolling snow dunes**. |
| 11 | **Enemy fortress redesigned to mimic Minas Morgul** (LOTR): dark spired gothic citadel. |
| 12 | Unit/building models are **workshopped completely** — nothing is sacred. |
| 13 | **View toggle**: underground = flat top-down X-Y plane view; above ground = perspective FOV dolly. |
| 14 | Units may stay **blobs/simple for now**; map is small; zoom range = close-up of units ↔ whole local area (no strategic mega-zoom-out). |
| 15 | **Keep Tab switching** between surface/underground. |
| 16 | Open to **reskinning the palette**. |
| 17 | (n/a — deferred to art direction doc where the choice is explained) |
| 18 | No per-platform art variants. |
| 19 | **First wall breach** may become a notable visual moment. |
| 20 | Keep existing sound; revisit later. |
| 21 | **Minimal camera shake**. |
| 22 | Success = **screenshots that make someone want to play it**. |
| 23 | Mobile descoped. |
| 24 | 60 fps target (higher if free). |
| 25 | This plan ships as a PR off `feat/3d-conversion` with plans + starter models. |
| 26 | Harness used for all visual checks. |
| 27 | Accept-and-iterate workflow with the owner on screenshots. |

## What changes vs. the current 3D layer

| Layer | Today (3D rework phases 1–5) | After this revamp |
|---|---|---|
| Units | Procedural primitive rigs (`unit_model_3d.gd`, ≤60 primitives, flat-shaded) | Blob/sculpted meshes now (`14`), full model workshop later (`12`); team/faction identity via tinted accents + materials |
| Structures | Procedural boxes/cylinders (`structure_proxy_3d.gd`) | **Imported textured GLBs** (`frost_mines_assets/models/`); Minas Morgul enemy fortress (R4 landed: manifest + loader + per-proxy material rebind, Potato keeps the procedural recipes) |
| Terrain | Flat per-cell quads (`terrain_3d.gd`) | **Height-field mesh** with rolling snow dunes; underground keeps readable flat-ish X-Y view |
| Materials | Flat albedo, roughness 1.0, no textures | Hand-painted-style textured materials; warm emissive accents vs cold ambient |
| Camera | Single 55° pitch dolly rig, FOV 45 | **Two view modes**: perspective surface dolly + flat/near-top-down underground plane |
| Palette | Phase-4 luminance ladder | Reskin per `01-art-direction.md` (cold indigo/slate + amber warmth; enemy pale witch-green) |
| UI | Frosted-steel 2D HUD (kept) | Restyled to match (see art direction §UI) |

## Hard rules (inherited + new)

- **Presentation-only** — the sim is never written by the 3D layer (inherited).
- **All quality presets keep working** — Potato / Standard / Fancy
  (`ArtStyle3D.apply_quality()`). Textured GLBs are the Standard look;
  Primitive-fallback recipes stay for Potato where a model is too heavy
  (inherited, adapted for imports).
- **Tests stay green** — full GUT suite + `tests/test_3d_*.gd` extended where
  behavior is testable (inherited).
- **Performance budget** — 60 fps desktop with 200+ units; web degrades
  gracefully (inherited). New: textured models need LOD discipline —
  Standard = full models, Potato = primitive fallback, Fancy = full models +
  post.
- **Every visual phase ends with harness screenshots** attached to the PR
  (new; the harness exists on this branch since the `feat/capture-harness`
  merge).
- **Exports must keep working** — Web/macOS/Windows presets green after every
  phase (new; web forces `gl_compatibility`, so no Forward+-only features).

## Phases

| # | File | Model | Scope | Depends |
|---|---|---|---|---|
| R1 | `04-phase-plan.md` §R1 | K2.8 | Harness 3D adaptation + baseline captures (lands in this PR) | — |
| R2 | `04-phase-plan.md` §R2 | K3 | Art direction tokens in code: palette reskin, material library, lighting moods retune | R1 |
| R3 | `04-phase-plan.md` §R3 | K2.8 | Height-field surface terrain with rolling snow dunes | R2 |
| R4 | `04-phase-plan.md` §R4 | K2.8 | Structure GLB import pipeline + Minas Morgul enemy fortress + player keep | R2 ✅ |
| R5 | `04-phase-plan.md` §R5 | K3 | Two-mode camera: perspective surface / flat underground plane | R2 |
| R6 | `04-phase-plan.md` §R6 | K3 | Fog-of-war & lantern darkness treatment for 3D + first-wall-breach moment | R3, R4 |
| R7 | `04-phase-plan.md` §R7 | K3 | Unit model workshop (blobs → sculpted) + faction variants | R4 |
| R8 | `04-phase-plan.md` §R8 | K2.8 | UI restyle + screenshot/marketing pass | R2–R7 |

Model guidance (inherited): K3 for judgment-heavy visual work, K2.8 for
mechanical execution. Taste calls escalate to the owner with harness
screenshots, not guesses.
