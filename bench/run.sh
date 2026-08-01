#!/usr/bin/env bash
# AGL crash-safe Godot bench launcher for Git Bash on Windows.
# Usage: bench/run.sh [scenario] [duration_seconds] [timeout_seconds]

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-/d/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe}"
SCENARIO="${1:-stress_40}"
DURATION="${2:-30}"
TIMEOUT="${3:-0}"

PROJECT_WIN="$(cygpath -w "$PROJECT_DIR")"
GODOT_WIN="$(cygpath -w "$GODOT")"
RUNNER_WIN="$(cygpath -w "$PROJECT_DIR/bench/invoke_godot.ps1")"

set +e
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$RUNNER_WIN" \
  -GodotExe "$GODOT_WIN" \
  -ProjectDir "$PROJECT_WIN" \
  -Scenario "$SCENARIO" \
  -DurationSeconds "$DURATION" \
  -TimeoutSeconds "$TIMEOUT" \
  -ProcDumpExe "${AGL_PROCDUMP:-}"
EXIT_CODE=$?
set -e

echo ""
echo "[bench] godot exited with code $EXIT_CODE"
exit "$EXIT_CODE"
