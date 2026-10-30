# Headless screenshot capture

Deterministic in-match screenshots without a display — built for CI and for
AI coding agents (Kimi Code and friends) whose sandboxes can run Godot
headlessly but never had a way to *see* the game. With this harness an agent
can close the render → look → fix loop on its own: edit, capture, look at
the PNGs, iterate.

```bash
tools/capture/run_capture.sh /tmp/shots
# → /tmp/shots/001_start.png, 002_zoomout.png, 003_underground.png, ...
```

Requirements: Linux, `xvfb-run`, `curl`, `unzip`. A Godot 4.7-stable Linux
binary is downloaded automatically on first run (`GODOT_BIN` env var to
override with a local install).

## How it works

1. `run_capture.sh` fetches Godot, builds the `.godot/` import cache
   (`--import`), then runs the project under Xvfb.
2. Instead of the main menu, it launches `tools/capture/capture_driver.tscn`.
   The driver configures the autoloads exactly like the menu's Play flow
   (difficulty, faction, seed, speed — adaptive off) and swaps in
   `scenes/main_3d.tscn` on the 3D branch.
3. A `CapturePilot` node (parented to the root window so it survives the
   scene swap) advances the match and, at each requested sim timestamp,
   poses the camera, waits two frames, and saves the viewport as a PNG.
4. Random weather scheduling is disabled for determinism. Weather poses force
   a snowstorm / volcano a few seconds early via `WeatherManager`'s own
   routines, then end it after the shot so events cannot overlap. The breach
   pose forces central-wall damage through `GridWorld.damage_cell()` and
   temporarily reveals the board so the effect is visible.

The harness changes only its throwaway match and is inert during normal play
and invisible to the GUT suite (parsing is covered by
`tests/test_capture_driver.gd`).

## Flags and shot specs

```
SHOTS="10:start;45:zoomout;80:underground;100:breach;120:storm;150:volcano;180:custom:0:-150:6" \
FACTION=brute DIFFICULTY=2 SEED=777 SPEED=2.0 \
tools/capture/run_capture.sh /tmp/shots
```

Pose names: `start` (spawn camera), `surface` (surface bookmark,
recentered), `zoomout` (centered, 0.5× zoom), `underground` (built mine
lantern framed at local-area dolly), `breach` (forced central-wall breach
framed underground), `units` / `units_underground` (R7 eight-unit silhouette
lineups on the surface/near-top-down plane), `base` (R8 player keep and an
active production dial), `dunes` (R8 snow-field composition), `fortress`
(R8 revealed enemy citadel), `storm` / `volcano` (surface + forced weather),
and `custom:X:Y:Z` (explicit camera position and dolly). Times are sim-seconds;
keep the list ordered.

`RESOLUTION=3840x2160` changes the capture size (default `1920x1080`). The R8
showcase runner captures all six marketing poses at 1080p and 4K:

```bash
tools/capture/run_showcase.sh roadmap/3d-visual-revamp/r8
# Override the shot list or limit a quick iteration to one resolution:
SHOTS="8:base;16:dunes" RESOLUTIONS="1920x1080" \
  tools/capture/run_showcase.sh /tmp/r8-preview
```

## Verified environment notes (don't relearn these the hard way)

- **Use `--rendering-driver opengl3`.** Under Mesa's software Vulkan
  (lavapipe) the Forward+ desktop renderer presents **blank frames**. The
  OpenGL path renders correctly — and matches the web build's
  `gl_compatibility` "Standard" preset, so captures represent what web
  players see.
- **Fresh checkouts need `--import` first,** or resource loads fail on the
  missing `.godot/imported` cache.
- **Frame times under llvmpipe are meaningless** (~5 fps at 1080p); only the
  pixels are trustworthy. Never benchmark from this harness.
- Run at 1920×1080 so the resolution-adaptive base zoom is 1.0 and shots
  match the UI's logical design size.

## Using it from an agent session

```bash
git clone --depth 1 --branch <branch> https://github.com/SZaidi00/mine-attack.git
cd mine-attack && tools/capture/run_capture.sh /tmp/shots
```

Then open the PNGs and judge.

## On the 3D branch (`feat/3d-conversion`)

The driver swaps to `res://scenes/main_3d.tscn` (the 3D shell that mounts
the sim), and the pilot poses the 3D camera rig instead of the 2D camera:

- `start` / `storm` / `volcano` — unchanged semantics.
- `underground` — places and finishes a real mine lantern through the player
  placement API, then frames its light pool at dolly 6.
- `breach` — reveals the board, forces the central wall's lethal damage,
  places a lantern at the opened cell, frames it at dolly 4.5, then restores
  the reveal override.
- `surface` — surface view, rig focused on midfield at default dolly.
- `zoomout` — rig focused on map center at max dolly (whole board).
- `custom:X:Y:Z` — rig focus at world (X, Y) (2D px × 0.01) with dolly Z
  (3.0–16.0 on the surface, 3.0–10.0 underground). Example:
  `60:custom:-800:-100:6`.

The rig is reached at `/root/Main3D`; the pilot uses its public
`pose_camera(focus, dolly, pitch)` API. Posing cancels any active view tween
and updates the camera immediately. Underground/breach shots also wait for
the 0.5-second fog refresh before saving.
