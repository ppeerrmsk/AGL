#!/usr/bin/env bash
# AGL 战斗日志自动打开器
# 由 UserPromptSubmit hook 驱动：每次用户在 Claude Code 里发消息时，检查项目根
# 的 logs/ 目录有没有新的 combat_log_*.txt，若有则用系统默认程序打开。
#
# 相关位置：
#   - 日志生成：scripts/event_logger.gd:dump_to_file（F9 触发，editor 模式写 res://logs/）
#   - gitignore：/logs/ 整个目录都不进 git
#   - sentinel：logs/.last_seen_log 记录上次处理过的文件，防止重复打开
#   - 安装配置：.claude/settings.local.json 的 hooks.UserPromptSubmit 段
#
# 失败始终静默退出 0，不阻塞用户 prompt。

LOG_DIR="logs"
SENTINEL="$LOG_DIR/.last_seen_log"

# 目录不存在（还没玩过游戏或还没按 F9） → 静默退出
[ -d "$LOG_DIR" ] || exit 0

# 找最新的 combat log（按 mtime 倒序取第一个）
LATEST=$(ls -t "$LOG_DIR"/combat_log_*.txt 2>/dev/null | head -1)
[ -z "$LATEST" ] && exit 0

# 读取上次处理过的路径
LAST_SEEN=""
[ -f "$SENTINEL" ] && LAST_SEEN=$(cat "$SENTINEL" 2>/dev/null)

# 跟上次一样 → 静默退出（避免重复打开同一个文件）
if [ "$LATEST" = "$LAST_SEEN" ]; then
  exit 0
fi

# 更新 sentinel 并调用系统默认程序打开
echo "$LATEST" > "$SENTINEL"

# Windows 下需要绝对路径 + Windows 格式给 cmd.exe
# 非 Windows 系统退化为直接路径（实际项目只在 Windows 用，不支）
if command -v cygpath >/dev/null 2>&1; then
  WIN_PATH=$(cygpath -wa "$LATEST" 2>/dev/null || echo "$LATEST")
  cmd //c start "" "$WIN_PATH" >/dev/null 2>&1
fi

# 在 Claude Code UI 里通知
BASENAME=$(basename "$LATEST")
printf '{"systemMessage": "已打开新战斗日志: %s"}\n' "$BASENAME"
exit 0
