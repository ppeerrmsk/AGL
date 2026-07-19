class_name ChatterLines
extends RefCounted

## 无线电台词表的【加载器】（spec radio-chatter §2.9）
##
## ★ 本文件不含任何台词、权重、冷却数值 —— 全部住在 resources/chatter/radio_chatter.json。
##   加台词 / 调频率 / 调权重都改那个 JSON，不用碰代码。
##   台词文本本身住在 i18n/translations.csv（本地化同事只需要看那一个文件）。
##
## 加载策略：静态缓存，全进程解析一次。JSON 缺失 / 损坏时不崩游戏 —— 报 error 后
## 整个无线电系统降级为静默（台词是氛围，绝不值得为它中断一局）。

const DATA_PATH := "res://resources/chatter/radio_chatter.json"

## 无线电分类（spec §2.10）
enum Kind {
	SCRIPTED,   ## 剧情关键节点（BOSS 登场等）：不受任何冷却/概率限制，必定播出
	AMBIENT,    ## 普通战场无线电：受全局冷却 + 自身冷却 + 概率三重限制
}

# ══════════════════════════════════════════════
#  静态缓存
# ══════════════════════════════════════════════

static var _data: Dictionary = {}
static var _loaded: bool = false

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true   # 先置位：解析失败也不重复尝试，避免每帧刷 error
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f == null:
		push_error("ChatterLines: 打不开 %s —— 无线电系统降级为静默" % DATA_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ChatterLines: %s 解析失败（不是 JSON 对象）—— 无线电系统降级为静默" % DATA_PATH)
		return
	_data = parsed

## 供测试/热重载用：丢弃缓存，下次访问重新读盘
static func reload() -> void:
	_loaded = false
	_data = {}
	_ensure_loaded()

static func _global() -> Dictionary:
	_ensure_loaded()
	return _data.get("global", {})

static func _triggers() -> Dictionary:
	_ensure_loaded()
	return _data.get("triggers", {})

static func _trigger(id: String) -> Dictionary:
	var t: Dictionary = _triggers().get(id, {})
	return t if typeof(t) == TYPE_DICTIONARY else {}

# ══════════════════════════════════════════════
#  全局节流参数（spec §2.2 / §2.11）
# ══════════════════════════════════════════════

static func global_ambient_cooldown() -> float:
	return float(_global().get("ambient_cooldown_sec", 12.0))

static func line_gap() -> float:
	return float(_global().get("line_gap_sec", 0.30))

static func queue_max() -> int:
	return int(_global().get("queue_max", 3))

static func queue_stale_sec() -> float:
	return float(_global().get("queue_stale_sec", 6.0))

static func duration_base() -> float:
	return float(_global().get("line_duration_base_sec", 2.6))

static func duration_per_char() -> float:
	return float(_global().get("line_duration_per_char_sec", 0.035))

static func duration_max() -> float:
	return float(_global().get("line_duration_max_sec", 5.0))

# ══════════════════════════════════════════════
#  单个 trigger 的属性
# ══════════════════════════════════════════════

static func has_trigger(id: String) -> bool:
	return _triggers().has(id)

## 分类。未登记的 trigger 一律按 AMBIENT 处理（保守：受冷却限制，不会意外强插）
static func kind_of(id: String) -> int:
	return Kind.SCRIPTED if String(_trigger(id).get("class", "ambient")) == "scripted" else Kind.AMBIENT

static func is_scripted(id: String) -> bool:
	return kind_of(id) == Kind.SCRIPTED

## 权重：多条同时排队时谁先播。只影响排队顺序，永不打断正在播的那条。
static func weight_of(id: String) -> int:
	return int(_trigger(id).get("weight", 40))

## 共享冷却的桶名（例：所有 ack_* 共享 "ack"）。省略则用 trigger 自己的 id。
static func cooldown_group_of(id: String) -> String:
	return String(_trigger(id).get("cooldown_group", id))

static func cooldown_of(id: String) -> float:
	return float(_trigger(id).get("cooldown_sec", 0.0))

## 概率骰（0~1）。"偶尔出现一下"的主要旋钮。
static func chance_of(id: String) -> float:
	return clampf(float(_trigger(id).get("chance", 1.0)), 0.0, 1.0)

## trigger 的台词 key 列表。支持 lines_ref 复用别的 trigger 的列表（避免重复粘贴）。
static func lines_of(id: String) -> Array:
	var t := _trigger(id)
	var ref := String(t.get("lines_ref", ""))
	if ref != "" and ref != id:
		return lines_of(ref)
	var arr = t.get("lines", [])
	return arr if typeof(arr) == TYPE_ARRAY else []

# ══════════════════════════════════════════════
#  BOSS 序列 / 说话资格
# ══════════════════════════════════════════════

## 取 BOSS 对话序列。phase ∈ {"spawn", "engage"}。未登记的 boss_id 退 _default。
static func boss_sequence(boss_id: String, phase: String) -> Array:
	_ensure_loaded()
	var all: Dictionary = _data.get("boss_sequences", {})
	var seq = all.get(boss_id, all.get("_default", {}))
	if typeof(seq) != TYPE_DICTIONARY:
		return []
	var arr = seq.get(phase, [])
	return arr if typeof(arr) == TYPE_ARRAY else []

## 机型是否配有无线电（spec §2.8 等级门）。未登记 = 沉默。
static func type_has_voice(type_tag: String) -> bool:
	_ensure_loaded()
	var block: Dictionary = _data.get("voiced_enemy_types", {})
	var types = block.get("types", [])
	if typeof(types) != TYPE_ARRAY:
		return false
	return type_tag in types

## 敌方减员档位 → trigger id（spec §2.6）
static func attrition_trigger(total_losses: int) -> String:
	if total_losses >= 72:
		return "attrition_t3"
	if total_losses >= 36:
		return "attrition_t2"
	return "attrition_t1"

# ══════════════════════════════════════════════
#  选词
# ══════════════════════════════════════════════

## trigger → 上次选中的下标，用于防连续重复（spec §3.5）
var _last_pick: Dictionary = {}

## 从 trigger 的台词列表里取一个 i18n key。列表为空 → 返回 ""（调用方跳过）。
func pick(trigger: String) -> String:
	var arr := lines_of(trigger)
	if arr.is_empty():
		return ""
	if arr.size() == 1:
		return String(arr[0])
	var idx: int = randi() % arr.size()
	if _last_pick.has(trigger) and _last_pick[trigger] == idx:
		idx = (idx + 1) % arr.size()
	_last_pick[trigger] = idx
	return String(arr[idx])

# ══════════════════════════════════════════════
#  校验（无头测试用）
# ══════════════════════════════════════════════

## 表里出现的全部 i18n key（含 BOSS 序列），用于校验译文齐全。
static func all_line_keys() -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for id in _triggers():
		for k in lines_of(String(id)):
			if String(k) not in out:
				out.append(String(k))
	var bosses: Dictionary = _data.get("boss_sequences", {})
	for bid in bosses:
		var seq = bosses[bid]
		if typeof(seq) != TYPE_DICTIONARY:
			continue
		for phase in seq:
			var arr = seq[phase]
			if typeof(arr) != TYPE_ARRAY:
				continue
			for item in arr:
				if typeof(item) == TYPE_DICTIONARY and item.has("key"):
					var k := String(item["key"])
					if k not in out:
						out.append(k)
	return out

## 全部已登记的 trigger id
static func all_trigger_ids() -> Array[String]:
	var out: Array[String] = []
	for id in _triggers():
		out.append(String(id))
	return out
