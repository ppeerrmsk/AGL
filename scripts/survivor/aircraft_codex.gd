class_name AircraftCodex
extends RefCounted

## 机体图鉴（跨局持久，user://aircraft_codex.cfg）——记录玩家**拥有过**哪些机型。
## 用途：进化树视图的"战争迷雾"（从没接触过的飞机只显示剪影 ？？？），
## 鼓励多开几局解锁更多机型（用户 2026-07-03）。
## 归属：局外 meta 数据（与局内 roguelike 清零不冲突，见 meta-progression spec）。
## 低频写盘：只在发现新机型时 save 一次。

const PATH := "user://aircraft_codex.cfg"

static var _loaded: bool = false
static var _discovered: Dictionary = {}   ## id(String) → true

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in cf.get_section_keys("discovered") if cf.has_section("discovered") else []:
			_discovered[k] = true

## 玩家是否拥有过该机型（进化到过 / 用它开过局）
static func is_discovered(id: StringName) -> bool:
	_ensure_loaded()
	return _discovered.has(String(id))

## 记录发现（幂等；仅新发现时写盘）
static func mark_discovered(id: StringName) -> void:
	_ensure_loaded()
	var key := String(id)
	if key == "" or _discovered.has(key):
		return
	_discovered[key] = true
	var cf := ConfigFile.new()
	cf.load(PATH)  # 失败=新文件，忽略
	for k in _discovered:
		cf.set_value("discovered", k, true)
	cf.save(PATH)
	EventLogger.log_event("CODEX", "Player", "发现新机型: %s" % key)
