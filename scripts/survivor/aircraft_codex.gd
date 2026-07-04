class_name AircraftCodex
extends RefCounted

## 机体图鉴（跨局持久，user://aircraft_codex.cfg，与 merit.cfg 等同属游戏存档）。
## 用途：进化树视图的"战争迷雾"（从没拥有过的飞机只显示剪影 ？？？），鼓励多开几局解锁。
##
## ⚠ 入鉴铁律（用户 2026-07-03）：**只有"从玩家自己这头获得"才算**——
##   ✅ 算：开局起手机（拿到那一刻）/ 进化到该机型（含僚机跟随进化）
##   ❌ 不算：战场上看到敌机用同款 / 一场对局里在树上"见过"相邻出口的名字（那只是本局临时揭示）
## 除本文件的 mark_discovered 三个既有调用点（开局 + 结算兜底 + evolve）外，
## **不得**从敌机 spawn / 树视图渲染等路径调用。
##
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
