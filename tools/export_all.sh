#!/bin/bash
# Export all release presets (Web, macOS, Windows) into build/, then package
# the desktop builds as zips in the project root for easy upload.
# Usage: tools/export_all.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# Prefer a godot on PATH; fall back to the local Godot.app.
GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT="godot"
	elif [ -x "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" ]; then
		GODOT="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
	elif [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
		GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
	else
		echo "error: Godot binary not found — set GODOT=/path/to/Godot" >&2
		exit 1
	fi
fi

# Remove previous artifacts so every run produces a completely fresh set
# (stale bundle contents or archive entries can survive a plain overwrite).
rm -rf build/MineAttack.app build/MineAttack.exe build/MineAttack.pck \
	MineAttack-macOS.zip MineAttack-Windows.zip

"$GODOT" --headless --path . --export-release "Web" build/MineAttack.html
"$GODOT" --headless --path . --export-release "macOS" build/MineAttack.app
"$GODOT" --headless --path . --export-release "Windows" build/MineAttack.exe

echo "Packaging desktop builds for upload..."
# ditto keeps the .app bundle's metadata intact so it still runs when unzipped.
ditto -c -k --sequesterRsrc --keepParent build/MineAttack.app MineAttack-macOS.zip
( cd build && zip -q ../MineAttack-Windows.zip MineAttack.exe )

echo "All exports complete:"
ls -lh build/MineAttack.html build/MineAttack.app/Contents/MacOS/MineAttack build/MineAttack.exe \
	MineAttack-macOS.zip MineAttack-Windows.zip | awk '{print "  " $5 "  " $9}'
