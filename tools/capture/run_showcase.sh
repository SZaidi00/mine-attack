#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${1:-${PROJECT_ROOT}/roadmap/3d-visual-revamp/r8}"
SHOTS="${SHOTS:-8:base;16:dunes;28:underground;40:storm;52:volcano;64:fortress}"
RESOLUTIONS="${RESOLUTIONS:-1920x1080 3840x2160}"

for resolution in $RESOLUTIONS; do
	case "$resolution" in
		1920x1080) label="1080p" ;;
		3840x2160) label="4k" ;;
		*) label="$resolution" ;;
	esac
	SHOTS="$SHOTS" RESOLUTION="$resolution" \
		"${PROJECT_ROOT}/tools/capture/run_capture.sh" "${OUT_DIR}/${label}"
done
