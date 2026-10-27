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
#   1920x1080                   base zoom == 1.0 at the UI's logical size
exec xvfb-run -a -s "-screen 0 1920x1080x24" "$GODOT_BIN" --path . \
	--rendering-driver opengl3 --audio-driver Dummy --fixed-fps 60 \
	res://tools/capture/capture_driver.tscn -- \
	--out "$OUT_DIR" --shots "$SHOTS" \
	--difficulty "$DIFFICULTY" --faction "$FACTION" \
	--seed "$SEED" --speed "$SPEED" "${EXTRA_ARGS[@]}"
