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

	# §7.6 末尾追加技能快照（玩家飞机当前 upgrade_stacks + 状态效果 + max_hp 修正）
	# 用 try/except 风格的 nil-safe 拼装：找不到玩家就跳过整段
	_dump_skill_snapshot(file)

	# Perf 快照：CSG/F-47 等高压场景的根因定位
	# 内容：all_units 分类 / AI 拥挤度 / 雷达对/热区 µs，详见 perf_buckets.gd
	file.store_line("")
	file.store_line(PerfBuckets.format_full_dump())

	file.close()
	print("EventLogger: saved %d events to %s" % [_events.size(), path])
	return path


## §7.6 技能快照：玩家技能 / 状态效果 / 关键属性 / 最近钩子触发
## 不持久化新数据，只是把已有信息汇总到 log 末尾，方便用户对照玩家死亡前 30s 看哪些技能链触发了什么
func _dump_skill_snapshot(file: FileAccess) -> void:
	var pref: Aircraft = AircraftRenderer.player_ref
	if pref == null or not is_instance_valid(pref):
		return
	file.store_line("")
	file.store_line("=== SKILLS SNAPSHOT @ t=%.1fs ===" % _game_time)
	file.store_line("Player: %s (callsign=%s, hp=%.0f/%.0f)" % [
		(pref.params.display_name if pref.params else "?"),
		pref.callsign,
		pref.hp,
		(pref.params.max_hp if pref.params else 0.0),
	])
	# Active upgrades
	var stacks: Dictionary = {}
	if pref.has_meta("upgrade_stacks"):
		stacks = pref.get_meta("upgrade_stacks")
	file.store_line("Active upgrades (%d):" % stacks.size())
	for u in SurvivorData.UPGRADES:
		var uid: String = u.get("id", "")
		var stk: int = int(stacks.get(uid, 0))
		if stk <= 0:
			continue
		var rarity_idx: int = SurvivorData.get_rarity(u)
		var rarity_name: String = ""
		match rarity_idx:
			0: rarity_name = "STABLE"
			1: rarity_name = "ADV"
			2: rarity_name = "EXP"
			3: rarity_name = "CLA"
			4: rarity_name = "NEXT"
			_: rarity_name = "?"
		var kw: Variant = u.get("keywords", [])
		var kw_str: String = ""
		if kw is Array and (kw as Array).size() > 0:
			kw_str = " keywords=%s" % str(kw)
		file.store_line("  [%-4s] %s ×%d%s" % [rarity_name, uid, stk, kw_str])
	# Active status effects
	file.store_line("Active status effects (%d):" % pref.status_effects.size())
	for sid in pref.status_effects.keys():
		var rem: float = float(pref.status_effects[sid])
		var initial: float = float(pref.status_initial_durations.get(sid, rem))
		file.store_line("  %s remaining=%.2fs / initial=%.2fs" % [sid, rem, initial])
	# evasion_modifiers active values
	if "evasion_modifiers" in pref:
		file.store_line("Evasion modifiers (active=%s):" % pref.evasion_mode)
		for k in pref.evasion_modifiers.keys():
			file.store_line("  %s = %s" % [k, str(pref.evasion_modifiers[k])])
	# Pity / steering snapshot — survivor_mode 持有，需穿透找
	var sm := get_tree().current_scene
	if sm and "_pity_counter" in sm:
		file.store_line("Pity counter: %s" % str(sm._pity_counter))
	if sm and "upgrade_stacks" in sm:
		var steering: Dictionary = SurvivorData.compute_keyword_steering_weights(sm.upgrade_stacks, sm.survivor_player.level if sm.survivor_player else 1)
		file.store_line("Keyword steering: %s" % str(steering))
	file.store_line("=== END SKILLS SNAPSHOT ===")


## 获取当前游戏时间（供外部使用）
func get_game_time() -> float:
	return _game_time
