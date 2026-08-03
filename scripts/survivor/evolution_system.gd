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

# ── 飞机品类身份（spec skills-720-rework §1.2 / squad-upgrade-ownership §2.8）──
## 机种类（树节点 category）→ 品类身份轴集合。与进化 gates / 卡片三轴同一套词汇：
## 攻击=斗士 / 远程=骑士 / 电战=策士 / 制空·桥接·母舰=斗骑 / 隐身=骑策 / omni·传说=三系全通。
## 品类限定技能（UPGRADES.classes）按此过滤生效对象。
const CLASS_IDENTITY_BY_CATEGORY: Dictionary = {
	"attack": [&"gladiator"],
	"air": [&"gladiator", &"knight"],
	"bridge": [&"gladiator", &"knight"],
	"carrier": [&"gladiator", &"knight"],
	"range": [&"knight"],
	"stealth": [&"knight", &"schemer"],
	"ew": [&"schemer"],
	"omni": [&"gladiator", &"knight", &"schemer"],
	"legend": [&"gladiator", &"knight", &"schemer"],
}

## 机型档案 id → 品类身份（轴 StringName 数组）。
## 未知档案 / 不在进化树上的机返回空数组（不吃任何品类限定技，通用技不受影响）。
static func class_identity_of_profile(profile_id: StringName) -> Array:
	_ensure_loaded()
	var nid: StringName = node_id_for_profile(profile_id)
	if nid == &"":
		return []
	var cat := str(node_of(nid).get("category", ""))
	return CLASS_IDENTITY_BY_CATEGORY.get(cat, [])

# ── 属性门槛（spec evolution-attribute-gates §2.3/§2.4）──
## 节点 gates 字段形如 {"gladiator": 2} / air 类 {"gladiator":1,"knight":1,"sum_gk":3}
## / omni 三轴各写；"sum_gk" = 斗士+骑士合计（制空混合门）。无字段 = 无门槛（T1 起手）。
## 当前 12 机树为临时缩放值（tier2≈设计T3 / tier3≈设计T5），41 机重排时重生成。

static func gates_of(nd: Dictionary) -> Dictionary:
	return nd.get("gates", {})

## 进化 = LV 且 属性双门；本函数只查属性侧。axis_points = SurvivorPlayer.axis_points。
static func gates_passed(nd: Dictionary, axis_points: Dictionary) -> bool:
	return gates_missing(nd, axis_points).is_empty()

## 缺口列表 [{key, have, need}]，空 = 全过。UI 缺口徽记数据源。
## key 语义：轴名（≥）/ "sum_gk"（斗+骑合计）/ "sum_all"（三轴合计）/ "any"（值为 {轴:门槛}，任一满足即过）。
static func gates_missing(nd: Dictionary, axis_points: Dictionary) -> Array:
	var out: Array = []
	var g := gates_of(nd)
	for k in g:
		var ks := String(k)
		if ks == "any":
			var alt: Dictionary = g[k]
			var any_ok := false
			var best_key := ""
			var best_have := 0
			var best_need := 0
			for ak in alt:
				var need_a: int = int(alt[ak])
				var have_a: int = int(axis_points.get(StringName(String(ak)), 0))
				if have_a >= need_a:
					any_ok = true
					break
				if best_key == "" or need_a - have_a < best_need - best_have:
					best_key = String(ak)
					best_have = have_a
					best_need = need_a
			if not any_ok:
				out.append({"key": best_key, "have": best_have, "need": best_need})
			continue
		var need: int = int(g[k])
		var have: int
		if ks == "sum_gk":
			have = int(axis_points.get(&"gladiator", 0)) + int(axis_points.get(&"knight", 0))
		elif ks == "sum_all":
			have = int(axis_points.get(&"gladiator", 0)) + int(axis_points.get(&"knight", 0)) \
				+ int(axis_points.get(&"schemer", 0))
		else:
			have = int(axis_points.get(StringName(ks), 0))
		if have < need:
			out.append({"key": ks, "have": have, "need": need})
	return out

static func category_key_of(nd: Dictionary) -> String:
	_ensure_loaded()
	return _category_keys.get(nd.get("category", ""), "")

## 整机进化执行（aircraft-evolution §3.1：实例不销毁，只换档案）。
## 保：位置/heading/速度/高度（不动即保）、HP 比例；换：params 整套 + 武器载弹（武器绑机型 §2.5）。
## 升级绑机型（squad-upgrade-ownership）：旧机型局内升级随 params 换掉而失效 = 设计使然。
static func evolve(ac: Aircraft, node_id: StringName, is_wingman: bool,
		record_discovery: bool) -> bool:
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
	# ⚠ duplicate(true) **不会**深拷 gun/combat 等子资源（本引擎版本实测：换机后 params.gun
	# 仍指向磁盘上的共享 default_gun.tres）。玩家机炮/战斗风格升级是直改 params 字段的，
	# 不补这一行 → 升级会写进共享 .tres → 同引用该资源的 12 个敌机型当场一起变强，
	# 且 load 缓存不重置 → 污染跨局残留。与出生路径（survivor_mode 三处）保持同一深拷契约。
	# 回归守卫：bench `player_params` 的"共享武器库隔离"组。
	SurvivorPlayableSetup.deep_dup_weapons(ac.params)
	SurvivorPlayableSetup.apply(ac, profile, is_wingman)
	# HP 按比例折算（避免换机瞬间白血/暴毙）
	ac.hp = clampf(hp_ratio * ac.params.max_hp, 1.0, ac.params.max_hp)
	# 武器 = 新机型自带，载弹/热诱弹重置为新机满额
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
	if record_discovery:
		AircraftCodex.mark_discovered(node_id)  # 正式局跨局图鉴：拥有过=永久揭示
	EventLogger.log_event("EVOLVE", ac._log_name(),
		"%s → %s (tier=%d, wingman=%s)" % [old_name, ac.params.display_name, int(nd.get("tier", 0)), str(is_wingman)])
	return true
