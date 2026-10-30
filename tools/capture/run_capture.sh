#!/usr/bin/env bash
# Headless screenshot capture for Mine Attack (CI / agent sandboxes).
#
# Usage:
#   tools/capture/run_capture.sh [OUT_DIR] [-- extra godot/driver args...]
#
# Environment:
#   GODOT_BIN   path to a Godot 4.7+ Linux binary (default: download
#               4.7-stable into /tmp/godot-ci — sandboxes are ephemeral,
#               so the download repeats per fresh environment; it is
#               cached for the lifetime of the machine)
#   SHOTS       shot spec override (default: the five baseline poses)
#   FACTION / DIFFICULTY / SEED / SPEED   match config overrides
#   RESOLUTION  WxH output size (default 1920x1080; use 3840x2160 for 4K)
#   STRESS_UNITS  spawn N extra units per team (BENCH stress load)
#   BENCH       run BENCH seconds of sim, then print the Probe3D
#               script-time report (shots optional; GPU frame times under
#               software GL are meaningless, script ms are comparable)
#
# Requirements: xvfb-run, curl, unzip. Output: PNGs named NNN_<pose>.png.
set -euo pipefail

GODOT_VERSION="4.7-stable"
GODOT_BIN="${GODOT_BIN:-/tmp/godot-ci/Godot_v${GODOT_VERSION}_linux.x86_64}"
OUT_DIR="${1:-/tmp/mine-attack-capture}"
SHOTS="${SHOTS:-10:start;30:zoomout;50:underground;70:storm;90:volcano}"
FACTION="${FACTION:-arcane}"
DIFFICULTY="${DIFFICULTY:-1}"
SEED="${SEED:-12345}"
SPEED="${SPEED:-1.0}"
RESOLUTION="${RESOLUTION:-1920x1080}"
STRESS_UNITS="${STRESS_UNITS:-0}"
BENCH="${BENCH:-0}"
if [[ ! "$RESOLUTION" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]]; then
	echo "run_capture: RESOLUTION must be WxH (got '$RESOLUTION')" >&2
	exit 2
fi
CAPTURE_WIDTH="${RESOLUTION%x*}"
CAPTURE_HEIGHT="${RESOLUTION#*x}"

if [ "${1:-}" != "" ] && [ "${1:0:2}" != "--" ]; then
	shift
fi
EXTRA_ARGS=("$@")

if [ ! -x "$GODOT_BIN" ]; then
	echo "run_capture: fetching Godot ${GODOT_VERSION}..."
	mkdir -p "$(dirname "$GODOT_BIN")"
	curl -fsSL --retry 3 \
		"https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip" \
		-o "$(dirname "$GODOT_BIN")/godot.zip"
	unzip -o -q "$(dirname "$GODOT_BIN")/godot.zip" -d "$(dirname "$GODOT_BIN")"
	chmod +x "$GODOT_BIN"
fi

# Project root = two levels up from this script.
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$PROJECT_ROOT"

# Sandboxes may not have a writable $HOME; Godot needs one for user data.
export HOME="${HOME:-/tmp}"
if [ ! -w "$HOME" ]; then
	export HOME=/tmp
fi

# Fresh checkouts have no .godot/imported cache; build it first. headless is
# enough for importing.
xvfb-run -a "$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true

mkdir -p "$OUT_DIR"

# Why these flags (verified on a software-GL sandbox, see README.md):
#   --rendering-driver opengl3  software Vulkan (lavapipe) renders BLANK
#                               frames; the gl_compatibility path matches
#                               the web build's "Standard" preset anyway
#   --fixed-fps 60              deterministic: sim-seconds == frames/60
#   --audio-driver Dummy        no audio device in headless environments
#   RESOLUTION                  capture dimensions; 1920x1080 is the UI baseline
exec xvfb-run -a -s "-screen 0 ${CAPTURE_WIDTH}x${CAPTURE_HEIGHT}x24" "$GODOT_BIN" --path . \
	--rendering-driver opengl3 --audio-driver Dummy --fixed-fps 60 \
	--resolution "$RESOLUTION" \
	res://tools/capture/capture_driver.tscn -- \
	--out "$OUT_DIR" --shots "$SHOTS" \
	--difficulty "$DIFFICULTY" --faction "$FACTION" \
	--seed "$SEED" --speed "$SPEED" \
	--stress-units "$STRESS_UNITS" --bench "$BENCH" "${EXTRA_ARGS[@]}"
