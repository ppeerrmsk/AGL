class_name EvolutionSystem
extends RefCounted

## 进化系统（垂直切片，spec ace-system §2.3/§2.4 + aircraft-evolution §3.1）
## 护栏 1：树 = 数据文件（resources/evolution/evolution_tree.json），本代码只读表。
## 触发在战区结算（survivor_mode），本类只负责：树查询 + 单机进化执行。

const TREE_PATH := "res://resources/evolution/evolution_tree.json"

static var _loaded: bool = false
static var _nodes: Dictionary = {}            ## id(StringName) → node Dictionary
static var _profile_to_node: Dictionary = {}  ## profile id → node id
static var _tier_min_level: Dictionary = {}   ## tier(int) → min level(int)
static var _category_keys: Dictionary = {}    ## category → i18n key

static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open(TREE_PATH, FileAccess.READ)
	if f == null:
		push_error("EvolutionSystem: 树文件缺失 " + TREE_PATH)
		return
	var data = JSON.parse_string(f.get_as_text())
	if not (data is Dictionary):
		push_error("EvolutionSystem: 树 JSON 解析失败")
		return
	for k in data.get("tier_min_level", {}):
		_tier_min_level[int(k)] = int(data["tier_min_level"][k])
	_category_keys = data.get("categories", {})
	for nd in data.get("nodes", []):
		var nid := StringName(nd.get("id", ""))
		if nid == &"":
			continue
		_nodes[nid] = nd
		_profile_to_node[StringName(nd.get("profile", ""))] = nid

static func node_of(id: StringName) -> Dictionary:
	_ensure_loaded()
	return _nodes.get(id, {})

static func node_id_for_profile(profile_id: StringName) -> StringName:
	_ensure_loaded()
	return _profile_to_node.get(profile_id, &"")

## 当前节点的全部出口（node Dictionary 数组，含不满足等级的——UI 负责灰显）
static func exits_of(id: StringName) -> Array:
	_ensure_loaded()
	var out: Array = []
	for eid in node_of(id).get("exits", []):
		var nd := node_of(StringName(eid))
		if not nd.is_empty():
			out.append(nd)
	return out

## 逐机解锁等级（spec player-aircraft-power-curve §1.8）：节点带 min_level 字段则优先；
## 否则回退档位默认（tier_min_level）。
static func min_level_of(nd: Dictionary) -> int:
	_ensure_loaded()
	if nd.has("min_level"):
		return int(nd["min_level"])
	return _tier_min_level.get(int(nd.get("tier", 1)), 1)

## 全部节点（进化树视图用）
static func all_nodes() -> Array:
	_ensure_loaded()
	return _nodes.values()

static func category_key_of(nd: Dictionary) -> String:
	_ensure_loaded()
	return _category_keys.get(nd.get("category", ""), "")

## 整机进化执行（aircraft-evolution §3.1：实例不销毁，只换档案）。
## 保：位置/heading/速度/高度（不动即保）、HP 比例；换：params 整套 + 武器载弹（武器绑机型 §2.5）。
## 升级绑机型（squad-upgrade-ownership）：旧机型局内升级随 params 换掉而失效 = 设计使然。
static func evolve(ac: Aircraft, node_id: StringName, is_wingman: bool) -> bool:
	var nd := node_of(node_id)
	if nd.is_empty() or ac == null or not is_instance_valid(ac) or ac.is_destroyed:
		return false
	var profile := AircraftDB.get_profile(StringName(nd.get("profile", "")))
	if profile == null or profile.base_params == null:
		return false
	var hp_ratio: float = clampf(ac.hp / maxf(ac.params.max_hp, 1.0), 0.05, 1.0) if ac.params else 1.0
	var old_name: String = ac.params.display_name if ac.params else "?"
	# ── 换档案：与出生注入完全同路（survivor_playable_setup 头注释约定）──
	ac.params = profile.base_params.duplicate(true)
	SurvivorPlayableSetup.apply(ac, profile, is_wingman)
	# HP 按比例折算（避免换机瞬间白血/暴毙）
	ac.hp = clampf(hp_ratio * ac.params.max_hp, 1.0, ac.params.max_hp)
	# 武器 = 新机型自带，载弹/热诱弹重置为新机满额（充能/CD 由 apply 内 LoadoutLedger 处理）
	if ac.params.missile:
		ac.missiles_remaining = ac.params.missile.max_count
	if ac.params.secondary_missile:
		ac.secondary_missiles_remaining = ac.params.secondary_missile.max_count
	if ac.params.flare:
		ac.flares_remaining = ac.params.flare.max_flares
	# 爬线历史（树视图"从哪来"高亮）：首次进化先补记起点，再记本次终点
	var hist: Array = ac.get_meta("evo_history", [])
	var prev: StringName = ac.get_meta("evo_node", &"")
	if hist.is_empty() and prev != &"":
		hist.append(prev)
	hist.append(node_id)
	ac.set_meta("evo_history", hist)
	ac.set_meta("evo_node", node_id)
	AircraftCodex.mark_discovered(node_id)  # 跨局图鉴：拥有过=永久揭示（树视图迷雾）
	EventLogger.log_event("EVOLVE", ac._log_name(),
		"%s → %s (tier=%d, wingman=%s)" % [old_name, ac.params.display_name, int(nd.get("tier", 0)), str(is_wingman)])
	return true
