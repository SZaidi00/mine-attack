#!/bin/bash
# Repo health checks: GLB budget gate + headless GUT suite, in that order.
# This wrapper only sequences the checks; the gate and the test command stay
# the single source of truth. Usage: tools/run_checks.sh
set -uo pipefail
cd "$(dirname "$0")/.."

echo "==> [1/2] tools/check_model_budgets.sh"
if ! ./tools/check_model_budgets.sh; then
	echo "error: model budget gate FAILED — fix the violations above before pushing." >&2
	exit 1
fi

# Same Godot lookup as tools/export_all.sh: PATH first, then the usual local
# install locations, then the GODOT env var.
GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT="godot"
	elif [ -x "$HOME/Downloads/Godot.app/Contents/MacOS/Godot" ]; then
		GODOT="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
	elif [ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]; then
		GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
	fi
fi

if [ -z "$GODOT" ]; then
	echo "WARNING: no Godot binary found (PATH, ~/Downloads/Godot.app, /Applications/Godot.app)" >&2
	echo "         SKIPPING the GUT test suite — only the budget gate ran." >&2
	echo "         Install Godot or set GODOT=/path/to/Godot to enable tests." >&2
	exit 0
fi

echo "==> [2/2] GUT test suite ($GODOT)"
if ! "$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -gexit; then
	echo "error: GUT test suite FAILED — fix the failing tests before pushing." >&2
	exit 1
fi

echo "All checks passed."
