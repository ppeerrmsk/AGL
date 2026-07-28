extends Node

## 全局事件日志系统
## 环形缓冲区记录最近 60 秒的游戏事件，按 F9 导出到文件

const BUFFER_DURATION := 300.0  ## 保留最近多少秒的事件（5 分钟，配合 F47 BOSS 诊断）

## 击杀战况信号 → survivor_hud 的 kill feed 订阅。在 Aircraft._record_kill_attribution 致死瞬间 emit。
## killer/victim = 可读呼号；weapon_kind ∈ gun/missile/rocket/aoe/ground_crash；team: 0=友方。
## victim_voiced = 阵亡者是否配有无线电（spec radio-chatter §2.8）——无人机为 false，
## 用于抑制"无人机喊弹射"。kill feed 不消费此字段，只有无线电用。
signal kill_recorded(killer: String, victim: String, weapon_kind: String, killer_team: int, victim_team: int, victim_voiced: bool)

## 进入规避（导弹咬住）信号 → 无线电 "break" 呼叫订阅。
## 在 Aircraft.set_evasion_mode 的 false→true 上升沿 emit，只带呼号与阵营（不带单位引用）。
## 注意：加力模式（玩家主动）走 afterburner_engaged，不复用此信号——语义已从"躲导弹"分离。
signal evasion_started(callsign: String, team: int)

## 加力模式激活信号（玩家主动，非躲导弹）→ 无线电 "加力冲刺" 呼叫订阅。
## 在 AfterburnerCharge.toggle 成功启动时 emit；同一时刻 set_evasion_mode 的 break emit 被抑制。
signal afterburner_engaged(callsign: String, team: int)

## 新僚机编入编队信号 → 无线电 "归队" 呼叫订阅。
## 在 SquadFactory.register_wingman 真正新增成员时 emit（开局建队也会触发，订阅方自行过滤）。
signal wingman_joined(callsign: String, team: int)

var _events: Array[Dictionary] = []
var _game_time: float = 0.0

## ── 本局战报累计统计（不进环形缓冲，整局持续累加，F9 导出时汇总）──
## key = 射手的 _log_name() 字符串；value = {kills, gun_hits, msl_fired, msl_hit, msl_miss}
## 只在低频事件点（命中/击杀/发射/脱靶）做一次 dict++，对性能无感。
var _stats: Dictionary = {}

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

## 战报累计：给某射手的某项计数 +n（key 不存在则初始化）。
## 在命中/击杀/发射/脱靶等低频点调用，cost ≈ 1 次 dict 查 + 1 次 int 加。
func tally(subject: String, key: String, n: int = 1) -> void:
	if subject == "":
		return
	if not _stats.has(subject):
		_stats[subject] = {"kills": 0, "gun_hits": 0, "msl_fired": 0, "msl_hit": 0, "msl_miss": 0}
	_stats[subject][key] = int(_stats[subject].get(key, 0)) + n

## 清空战报统计（新一局开始时调用，避免跨局累加）
func reset_stats() -> void:
	_stats.clear()

## 把战报汇总成多行文本（F9 导出时追加到末尾）。按击杀数降序。
func format_stats_summary() -> String:
	if _stats.is_empty():
		return ""
	var keys: Array = _stats.keys()
	keys.sort_custom(func(a, b): return int(_stats[a]["kills"]) > int(_stats[b]["kills"]))
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== 战报汇总 (本局累计) ===")
	for k in keys:
		var st: Dictionary = _stats[k]
		var resolved: int = int(st["msl_hit"]) + int(st["msl_miss"])
		var rate_str: String = "--"
		if resolved > 0:
			rate_str = "%d%%" % roundi(100.0 * float(st["msl_hit"]) / float(resolved))
		lines.append("%-26s 击坠=%-3d 机炮命中=%-4d 导弹[发射=%-2d 命中=%-2d 脱靶=%-2d 命中率=%s]" % [
			k, int(st["kills"]), int(st["gun_hits"]),
			int(st["msl_fired"]), int(st["msl_hit"]), int(st["msl_miss"]), rate_str])
	return "\n".join(lines)

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

	# 战报汇总（每机击坠 / 机炮命中 / 导弹发射·命中·脱靶·命中率）
	var stats_summary: String = format_stats_summary()
	if stats_summary != "":
		file.store_line("")
		file.store_line(stats_summary)

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
