#!/usr/bin/env bash
# AGL headless 性能压测启动器
#
# 用法:
#   bench/run.sh                       # 默认 stress_40 / 30s
#   bench/run.sh stress_40 60          # 跑 60 秒
#   bench/run.sh stress_40 30 windowed # 带窗口（保留 _draw 桶数据）
#
# 输出文件: bench/results/<scenario>_<UTC>.txt
# 看输出: ls -t bench/results/*.txt | head -1 | xargs cat

set -e

GODOT="${GODOT:-/d/Program Files (x86)/Steam/steamapps/common/Godot Engine/godot.windows.opt.tools.64.exe}"
if [ ! -x "$GODOT" ]; then
  echo "[bench] ERROR: GODOT is not executable: $GODOT" >&2
  exit 2
fi
GODOT_VERSION=$("$GODOT" --version)
case "$GODOT_VERSION" in
  4.7*) ;;
  *) echo "[bench] ERROR: project.godot requires Godot 4.7; found $GODOT_VERSION" >&2; exit 2 ;;
esac
SCENARIO="${1:-stress_40}"
DURATION="${2:-30}"
MODE="${3:-headless}"

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# headless / windowed 切换
DISPLAY_ARGS=()
if [ "$MODE" = "headless" ]; then
  DISPLAY_ARGS+=(--headless)
fi

echo "[bench] godot=$GODOT"
echo "[bench] scenario=$SCENARIO duration=${DURATION}s mode=$MODE"
echo "[bench] project=$PROJECT_DIR"

cd "$PROJECT_DIR"
"$GODOT" "${DISPLAY_ARGS[@]}" --path . -- --bench="$SCENARIO" --duration="$DURATION"
EXIT_CODE=$?

# 显示最新一份结果
LATEST=$(ls -t bench/results/${SCENARIO}_*.txt 2>/dev/null | head -1 || true)
if [ -n "$LATEST" ]; then
  echo ""
  echo "[bench] === LATEST RESULT: $LATEST ==="
  cat "$LATEST"
fi

exit $EXIT_CODE
