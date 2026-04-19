extends Node

## 全局事件日志系统
## 环形缓冲区记录最近 60 秒的游戏事件，按 F9 导出到文件

const BUFFER_DURATION := 300.0  ## 保留最近多少秒的事件（5 分钟，配合 F47 BOSS 诊断）

var _events: Array[Dictionary] = []
var _game_time: float = 0.0

func _process(delta: float) -> void:
	_game_time += delta
	# 清理超过 60 秒的旧事件
	var cutoff := _game_time - BUFFER_DURATION
	while _events.size() > 0 and _events[0]["time"] < cutoff:
		_events.pop_front()

## 记录一条事件
## category: 分类字符串，如 "AI_STATE", "MISSILE", "DAMAGE" 等
## subject: 事件主体名称，如 "Enemy#3", "Player"
## message: 事件描述
func log_event(category: String, subject: String, message: String) -> void:
	_events.append({
		"time": _game_time,
		"category": category,
		"subject": subject,
		"message": message,
	})

## 导出日志到文件，返回文件路径
##
## 路径策略：
## - 编辑器运行（F5 调试）：写到项目根 `logs/combat_log_*.txt`
##   好处是 log 与代码在一起，Claude Code / hook 能直接看到，`logs/` 由 .gitignore 排除
## - 导出版本（正式发布包）：写到 `user://`（Godot 的 OS 用户数据目录）
##   因为 res:// 在导出包里是 .pck 只读的，不能写
func dump_to_file() -> String:
	var now := Time.get_datetime_dict_from_system()
	var filename := "combat_log_%04d%02d%02d_%02d%02d%02d.txt" % [
		now["year"], now["month"], now["day"],
		now["hour"], now["minute"], now["second"],
	]
	var path: String
	if OS.has_feature("editor"):
		var log_dir := ProjectSettings.globalize_path("res://logs/")
		DirAccess.make_dir_recursive_absolute(log_dir)
		path = log_dir + filename
	else:
		path = "user://" + filename

	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("EventLogger: cannot open %s" % path)
		return ""

	file.store_line("=== AGL Combat Log ===")
	file.store_line("Dumped at: %02d:%02d:%02d (game time: %.1fs)" % [
		now["hour"], now["minute"], now["second"], _game_time])
	file.store_line("Period: last %d seconds (%d events)" % [
		int(BUFFER_DURATION), _events.size()])
	file.store_line("=" .repeat(40))
	file.store_line("")

	for ev in _events:
		file.store_line("[%.1f] [%s] %s: %s" % [
			ev["time"], ev["category"], ev["subject"], ev["message"]])

	file.close()
	print("EventLogger: saved %d events to %s" % [_events.size(), path])
	return path

## 获取当前游戏时间（供外部使用）
func get_game_time() -> float:
	return _game_time
