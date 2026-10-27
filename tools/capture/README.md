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
   `scenes/main.tscn`.
3. A `CapturePilot` node (parented to the root window so it survives the
   scene swap) advances the match and, at each requested sim timestamp,
   poses the camera, waits two frames, and saves the viewport as a PNG.
4. Weather poses force a snowstorm / volcano a few seconds early via
   `WeatherManager`'s own routines, then end it after the shot.

Everything is presentation-only: the driver uses the same setters the menu
uses and never writes sim state. The harness is inert during normal play
and invisible to the GUT suite (parsing is covered by
`tests/test_capture_driver.gd`).

## Flags and shot specs

```
SHOTS="10:start;45:zoomout;80:underground;120:storm;150:volcano:custom:0:-150:0.5" \
FACTION=brute DIFFICULTY=2 SEED=777 SPEED=2.0 \
tools/capture/run_capture.sh /tmp/shots
```

Pose names: `start` (spawn camera), `surface` (surface bookmark,
recentered), `zoomout` (centered, 0.5× zoom), `underground` (own-mine
bookmark), `storm` / `volcano` (surface + forced weather), and
`custom:X:Y:Z` (explicit camera position and zoom factor). Times are
sim-seconds; keep the list ordered.

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

Then open the PNGs and judge. On `feat/3d-conversion` the same driver runs
(the 3D branch mounts the same sim); pose semantics for the 3D camera rig
land with the 3D branch's own capture update.
