# 3D Readability Rework — Overview

**Status:** Phase 1 implemented (2026-10-19); Phase 2 implemented (2026-10-20); Phase 3 implemented (2026-10-20); phases 4–6 not started.
**Branch:** `feat/3d-conversion` (Phase 1 + 2
of the original 3D conversion are complete; see `roadmap/3d-conversion/`).

## Problem statement

The 2.5D presentation layer works mechanically, but the game **looks
old-school and is hard to read at a glance**. Concrete symptoms found in the
current code:

1. **No 3D selection feedback at all** — the selection ring is 2D
   (`scripts/units/unit_rendering.gd:97`) on a hidden canvas layer
   (`scripts/three_d/main_3d.gd:78`). A selected full-HP unit has zero
   on-screen feedback. HP bars only appear once damaged
   (`scripts/three_d/unit_proxy_3d.gd:124`).
2. **No 3D projectiles** — arrows/fireballs/meteors live on the hidden 2D
   `Projectiles` layer; combat in 3D mode is invisible
   (`scripts/three_d/entity_proxies_3d.gd:13` only mirrors units/structures).
3. **Order markers and damage popups render misaligned** — they are 2D canvas
   items added to a Node3D scene at 2D world coordinates
   (`scripts/controllers/player_commands.gd:244`,
   `scripts/units/unit_combat.gd:241`).
4. **Units are tiny at gameplay zoom** — a 0.34-unit-tall humanoid is ~11 px
   at the default dolly and ~5 px at max zoom-out (1080p), because the camera
   uses Godot's default 75° FOV (`scenes/main_3d.tscn` never sets it).
5. **Terrain ignores all lighting** — the terrain albedo pass is unshaded
   (`scripts/three_d/terrain_3d.gd:62`), so sun, ambient mood, shadows, and
   fog never touch the ground; units sit on a flat matte backdrop.
6. **Bare environment** — no glow/bloom, no tonemapping, no SSAO, fog only on
   Fancy and too subtle to matter (`scenes/world_3d.tscn:6-23`,
   `scripts/three_d/lighting_3d.gd:79`).
7. **Weak team separation** — enemy `#B91C1C` on dark underground rock has low
   luminance contrast; Brute's faction accent red is nearly the same hue as
   the enemy team red; the colorblind palette never reaches 3D
   (`scripts/three_d/art_style_3d.gd:146`,
   `scripts/ui/ui_theme_tokens.gd:91`).

## Visual benchmarks

Target references: **StarCraft 2** and **They Are Billions**. The relevant
principles, translated to this project:

| Principle (SC2 / TAB) | What it means here |
|---|---|
| Units pop off a quieter terrain | Terrain stays desaturated and darker; units get saturated team color, rim light, and bloom-friendly emissive accents. Requires lit terrain + material pass (phases 3–4). |
| Selection is unmissable | Team-colored 3D selection discs, hover highlight, HP bars on selection and on damage (phase 1). |
| Big, honest silhouettes | Fewer degrees of FOV, closer default dolly, scaled-up unit roots so models read at RTS distance (phase 2). |
| Bloom sells the glow | Lava, lanterns, wizard orbs, miner lamps already emissive (energy 1.4–2.2) but nothing blooms; enable glow + ACES tonemap (phase 3). |
| Depth cueing | Aerial-perspective fog at all quality tiers, shadows that land on the ground, SSAO on Fancy (phase 3). |
| Telegraph every threat | 3D projectiles, order markers projected onto the terrain, meteor/burning-ground VFX mirrored in 3D (phases 1 & 5). |
| Readability over realism at max zoom-out | TAB-style: at full zoom the board must read as *zones and blobs of team color*, not individual models (phase 4). |

## Phases

Each phase file is self-contained: it restates the relevant current state
with `file:line` references, lists concrete steps, and has its own acceptance
criteria. **A fresh chat session should be able to implement a phase by
reading only its file** (plus the code it points at).

| # | File | Model | Scope | Depends on |
|---|---|---|---|---|
| 1 | `phase-1-selection-and-combat-feedback--k3.md` | **K3** | 3D selection rings, hover, HP-bar rework, 3D projectiles, projected order markers | — |
| 2 | `phase-2-camera-and-scale--k2.8.md` | **K2.8** | FOV/dolly retune, unit scale-up, readability at zoom levels | — |
| 3 | `phase-3-lighting-and-post--k2.8.md` | **K2.8** | Lit terrain, bloom, tonemap, fog, shadows, SSAO | — |
| 4 | `phase-4-palette-and-team-identity--k3.md` | **K3** | Value/saturation separation, rim light, colorblind 3D, accent conflict | 3 |
| 5 | `phase-5-effects-and-telegraphs--k3.md` | **K3** | 3D meteors/burning ground, telegraphed attacks, ember/bloom polish | 3 |
| 6 | `phase-6-model-redesign--k3.md` | **K3** | **Conditional** — keep/units/structure geometry redesign; only if 2–4 don't fix the look | 2, 3, 4 |

**Model guidance:** K3 for judgment-heavy phases (visual taste, new systems,
many integration points); K2.8 for well-specified mechanical execution
(constants, environment toggles). If a K2.8 phase drifts into taste calls
(e.g. "which fog density looks right"), escalate that decision to a K3
session rather than letting K2.8 guess.

Phases 1–3 are independent and can be done in any order; do 1 first if
gameplay readability is the priority, 3 first if screenshot appeal is.
Phases 4–5 build on the post-processing from phase 3. Phase 6 is gated on
a judgment call after 2–4 land — it changes the models themselves and is
the most expensive, most subjective work in the rework.

## Hard rules for every phase

- **Presentation-only.** The sim (`scripts/units/`, `scripts/world/`,
  `scripts/controllers/ai_*`, all autoloads' game state) is never touched
  beyond reading state. 3D stays sim → render, one direction.
- **All quality presets keep working:** `ArtStyle3D.apply_quality()` Potato /
  Standard / Fancy (see `roadmap/3d-conversion/style-guide.md`). Every new
  visual feature needs a preset-appropriate fallback.
- **Tests stay green:** `godot --headless --path . -s addons/gut/gut_cmdln.gd
  -gdir=res://tests -gexit` (see `AGENTS.md`). Extend `tests/test_3d_*.gd`
  where behavior is testable.
- **Performance budget:** 60 fps desktop with 200+ units; web degrades
  gracefully (Phase 2.7 of the original conversion).
- Update `AGENTS.md` if any phase changes what it documents about
  `scripts/three_d/`.
