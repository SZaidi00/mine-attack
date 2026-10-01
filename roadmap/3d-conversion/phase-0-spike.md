# Phase 0 — The Spike (prove the feel)

**Goal:** in a throwaway branch, answer one question — does a 3D camera
looking at our existing 2D world feel good enough to build on?

**Timebox:** a weekend or two. **Outcome:** go / no-go for Phase 1.

## Steps

1. **Branch:** `spike/3d-camera` off `main`. Tag `main` as `2d-legacy`
   first (see hard rules in the README).
2. **Duplicate the main scene:** create `scenes/main_3d.tscn` as a
   `Node3D` root. Do **not** modify `scenes/main.tscn` yet.
3. **Mount the 2D world as a texture plane:**
   - Add a `SubViewportContainer` + `SubViewport` rendering the existing
     2D scene graph, displayed on a plane mesh angled in the 3D world.
   - Alternative (cleaner): port the tile rendering to a `MeshInstance3D`
     grid where each cell is a colored quad fed by `GridWorld._cells`.
     Either is fine for the spike — the point is the camera.
4. **Rewrite `player_camera.gd` as a 3D rig:**
   - `CharacterBody3D`-less rig: a `Camera3D` under a pivot at fixed
     pitch (~55°), WASD/arrows pan on the ground plane, mouse wheel
     dolly-zoom, `Tab` still toggles surface/underground (teleport the
     rig between two saved transforms).
   - Keep edge-of-screen pan and zoom limits sensible for an RTS.
5. **Hook one unit:** make a single miner render as a `Sprite3D`
   billboard following the unit's logical position, driven by the
   existing `unit.gd` — proving sim→render decoupling.
6. **Judge it:** pan, zoom, Tab. Does it feel like an RTS? Does the
   fog/ore/lava readability survive the pitch?

## Go / no-go checklist

- [ ] Camera pan/zoom/Tab feels tight (no seasickness, no dead zones).
- [ ] The 2D tile data reads clearly from an angled view.
- [ ] Sim still runs at 60fps+ with the 3D viewport open.
- [ ] No changes were needed in any autoload or AI script to make the
      camera work. (If there were, note them — they are Phase 1 tasks.)

## Deliverable

A short note in this folder (`phase-0-findings.md`) recording: chosen
rendering approach (SubViewport plane vs. per-cell meshes), camera
parameters that felt right, and the go/no-go call.

## Explicitly out of scope

Real terrain, real models, lighting, shadows, fog visuals, effects,
UI changes, performance work, web export. All of that is Phase 1+.
