## Boss Debug 模式 — T4 参考机 + 主题化 build roller
##
## 正式升级节奏是每 3 级一次；Boss Debug 以最高档 T5 的前一档 T4 为参考，
## 先从正式三星战区奖池抽取等级匹配的特殊武器，再按目标节点门槛规划三轴、
## 在对应轴内抽取真实可用技能。这样等级、机型、武器、技能、三轴与里程碑
## 来自当前正式数据，而不是旧版“Lv15 + 14 张随机技能”。
class_name BossDebugBuilds
extends RefCounted

const REFERENCE_TIER := 4
const REFERENCE_WEAPON_DIFFICULTY := 3

# 主题定义：keywords 命中 → 高权重；categories 命中 → 中权重；其它 → 低权重
const THEMES: Dictionary = {
	"missile":  {"keywords": ["missile", "chain", "swarm"],            "categories": ["missile"]},
	"gun":      {"keywords": ["gun", "kill"],                          "categories": ["secondary"]},
	"status":   {"keywords": ["fear", "slow", "stealth", "jam"],       "categories": ["electronic_warfare"]},
	"low_alt":  {"keywords": ["low_alt", "head_on", "dodge", "armor"], "categories": ["mobility", "secondary"]},
	"high_alt": {"keywords": ["altitude", "high_alt", "radar"],        "categories": ["electronic_warfare"]},
}

const WEIGHT_KEYWORD := 6
const WEIGHT_CATEGORY := 3
const WEIGHT_DEFAULT := 1

const CATEGORY_THEMES: Dictionary = {
	"attack": ["gun", "low_alt"],
	"air": ["missile", "gun", "high_alt"],
	"bridge": ["missile", "gun"],
	"carrier": ["missile", "high_alt"],
	"range": ["missile", "high_alt"],
	"stealth": ["status", "high_alt"],
	"ew": ["status", "high_alt"],
	"omni": ["missile", "gun", "status"],
	"legend": ["missile", "gun", "status"],
}

const CATEGORY_PRIMARY_AXIS: Dictionary = {
	"attack": SurvivorData.AXIS_GLADIATOR,
	"air": SurvivorData.AXIS_GLADIATOR,
	"bridge": SurvivorData.AXIS_KNIGHT,
	"carrier": SurvivorData.AXIS_KNIGHT,
	"range": SurvivorData.AXIS_KNIGHT,
	"stealth": SurvivorData.AXIS_SCHEMER,
	"ew": SurvivorData.AXIS_SCHEMER,
	"omni": SurvivorData.AXIS_KNIGHT,
	"legend": SurvivorData.AXIS_KNIGHT,
}

const THEME_PRIMARY_AXIS: Dictionary = {
	"missile": SurvivorData.AXIS_KNIGHT,
	"gun": SurvivorData.AXIS_GLADIATOR,
	"status": SurvivorData.AXIS_SCHEMER,
	"low_alt": SurvivorData.AXIS_GLADIATOR,
	"high_alt": SurvivorData.AXIS_KNIGHT,
}


## 当前进化树的全部次顶档参考机；排序稳定，供 Debug 选机 UI 与回归共用。
static func reference_nodes() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for raw_node in EvolutionSystem.all_nodes():
		var node: Dictionary = raw_node
		if int(node.get("tier", 0)) == REFERENCE_TIER:
			out.append(node)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var level_a := EvolutionSystem.min_level_of(a)
		var level_b := EvolutionSystem.min_level_of(b)
		if level_a != level_b:
			return level_a < level_b
		return String(a.get("id", "")) < String(b.get("id", "")))
	return out


## 目标节点在其解锁等级应有的三轴分配。先满足 gates，剩余点继续投入机种主轴，
## 使 Lv18~20 的专精机自然兑现 6 点里程碑，而非把剩余点随机撒成无反馈的 1/1。
static func target_axis_points(node_id: StringName, level: int = -1) -> Dictionary:
	var node: Dictionary = EvolutionSystem.node_of(node_id)
	var out: Dictionary = {
		SurvivorData.AXIS_GLADIATOR: 0,
		SurvivorData.AXIS_KNIGHT: 0,
		SurvivorData.AXIS_SCHEMER: 0,
	}
	if node.is_empty():
		return out
	var category := String(node.get("category", ""))
	var primary: StringName = CATEGORY_PRIMARY_AXIS.get(
		category, SurvivorData.AXIS_GLADIATOR)
	var gates: Dictionary = EvolutionSystem.gates_of(node)
	for raw_key in gates:
		var key := String(raw_key)
		if key == "any":
			var alternatives: Dictionary = gates[raw_key]
			var chosen := primary if alternatives.has(String(primary)) else StringName()
			if chosen == &"":
				for raw_alternative in alternatives:
					chosen = StringName(String(raw_alternative))
					break
			if chosen != &"":
				out[chosen] = maxi(int(out.get(chosen, 0)),
					int(alternatives.get(String(chosen), 0)))
			continue
		var axis := StringName(key)
		if out.has(axis):
			out[axis] = maxi(int(out[axis]), int(gates[raw_key]))
	var reference_level := EvolutionSystem.min_level_of(node) if level < 0 else level
	var budget := SurvivorData.axis_points_earnable(reference_level)
	var used := 0
	for axis in SurvivorData.AXES:
		used += int(out.get(axis, 0))
	while used < budget:
		out[primary] = int(out.get(primary, 0)) + 1
		used += 1
	return out


## Boss Debug 特殊武器构筑：武器身份从正式三星战区奖池加权、无放回抽取。
## 五次升级里程碑（Lv16~17）配 2 件，六次（Lv18~20）配 3 件；机尾位继续互斥。
static func roll_weapon_loadout(level: int) -> Array[String]:
	var source: Dictionary = ZoneData.REWARD_WEAPON_WEIGHTS.get(
		REFERENCE_WEAPON_DIFFICULTY, {})
	var weights: Dictionary = source.duplicate()
	var target_count := 2 if SurvivorData.axis_points_earnable(level) <= 5 else 3
	var out: Array[String] = []
	while out.size() < target_count:
		var weapon_id := _weighted_weapon_pick(weights)
		if weapon_id.is_empty():
			break
		out.append(weapon_id)
		weights[weapon_id] = 0.0
		if weapon_id == "tail_mine":
			weights["loyal_wingman"] = 0.0
		elif weapon_id == "loyal_wingman":
			weights["tail_mine"] = 0.0
	return out


## Visual/回归共用：确认正式奖励入口已把所选武器实际挂到 ACE params。
static func is_weapon_mounted(params: AircraftParams, weapon_id: String) -> bool:
	if params == null:
		return false
	match weapon_id:
		"tail_mine":
			return params.torpedo != null
		"loyal_wingman":
			return params.loyal_wingman != null
		"qmaam":
			return params.secondary_missile != null
		"rocket":
			return params.rocket != null
		"railgun", "laser", "esm_pod":
			return params.get_equipment_of_kind(weapon_id) != null
	return false


## T4 节点专用入口：返回 level/theme/picks/axis_points，供运行时一次性配置。
static func roll_reference_build(node_id: StringName, params: AircraftParams,
		reference_level: int = -1) -> Dictionary:
	var node: Dictionary = EvolutionSystem.node_of(node_id)
	if node.is_empty():
		return {}
	var min_level := EvolutionSystem.min_level_of(node)
	var level := min_level if reference_level < 0 else maxi(reference_level, min_level)
	var theme_name := _theme_for_category(String(node.get("category", "")))
	var axis_points := target_axis_points(node_id, level)
	var axis_plan := _axis_plan(axis_points)
	var aircraft_id := StringName(String(node.get("profile", "")))
	var picks := _roll_for_axis_plan(THEMES[theme_name], axis_plan, aircraft_id, params)
	return {
		"node_id": node_id,
		"level": level,
		"theme": theme_name,
		"picks": picks,
		"axis_points": axis_points,
	}

## 兼容入口：没有进化节点时仍按正式每 3 级节奏生成单轴主题 build。
static func roll_build(level: int, aircraft_id: StringName, params: AircraftParams) -> Dictionary:
	var theme_keys: Array = THEMES.keys()
	var theme_name: String = theme_keys[randi() % theme_keys.size()]
	var axis := StringName(THEME_PRIMARY_AXIS[theme_name])
	var plan: Array[StringName] = []
	for _pick in SurvivorData.axis_points_earnable(level):
		plan.append(axis)
	var picks := _roll_for_axis_plan(THEMES[theme_name], plan, aircraft_id, params)
	return {"theme": theme_name, "picks": picks}

## 指定主题 roll（debug 热键切主题用）
static func roll_for_theme_name(theme_name: String, level: int, aircraft_id: StringName, params: AircraftParams) -> Dictionary:
	if not THEMES.has(theme_name):
		theme_name = "missile"
	var axis := StringName(THEME_PRIMARY_AXIS[theme_name])
	var plan: Array[StringName] = []
	for _pick in SurvivorData.axis_points_earnable(level):
		plan.append(axis)
	var picks := _roll_for_axis_plan(THEMES[theme_name], plan, aircraft_id, params)
	return {"theme": theme_name, "picks": picks}

static func _theme_for_category(category: String) -> String:
	var options: Array = CATEGORY_THEMES.get(category, ["missile", "gun", "status"])
	return String(options[randi() % options.size()])

static func _axis_plan(axis_points: Dictionary) -> Array[StringName]:
	var plan: Array[StringName] = []
	for axis in SurvivorData.AXES:
		for _pick in int(axis_points.get(axis, 0)):
			plan.append(axis)
	plan.shuffle()
	return plan

static func _roll_for_axis_plan(theme_def: Dictionary, axis_plan: Array[StringName],
		aircraft_id: StringName, params: AircraftParams) -> Array[Dictionary]:
	var picks: Array[Dictionary] = []
	var stack_count: Dictionary = {}
	var present_classes := EvolutionSystem.class_identity_of_profile(aircraft_id)

	# 每次 pick 后基础池可能因 requires_skill / excludes 变化，所以每轮都重新筛。
	for target_axis in axis_plan:
		var pool: Array = SurvivorData.UPGRADES.filter(func(u):
			if u.get("evolved", false) or not SurvivorData.is_normal_random_candidate(u):
				return false
			if SurvivorData.axis_of_upgrade(u) != target_axis:
				return false
			var max_st: int = int(u.get("max_stacks", 1))
			if int(stack_count.get(u["id"], 0)) >= max_st:
				return false
			return SurvivorData.is_upgrade_available_for(
				u, aircraft_id, params, stack_count, present_classes)
		)
		if pool.is_empty():
			continue

		var weighted: Array = []
		var total_w := 0
		for u in pool:
			var w := WEIGHT_DEFAULT
			var kws: Array = u.get("keywords", [])
			for k in theme_def["keywords"]:
				if k in kws:
					w = WEIGHT_KEYWORD
					break
			if w == WEIGHT_DEFAULT and (u.get("category", "") in theme_def["categories"]):
				w = WEIGHT_CATEGORY
			weighted.append({"u": u, "w": w})
			total_w += w

		var pick: Dictionary = _weighted_pick(weighted, total_w)
		if pick.is_empty():
			continue
		picks.append(pick)
		stack_count[pick["id"]] = int(stack_count.get(pick["id"], 0)) + 1

	return picks

static func _weighted_pick(weighted: Array, total_w: int) -> Dictionary:
	if total_w <= 0:
		return {}
	var r := randi() % total_w
	var acc := 0
	for entry in weighted:
		acc += int(entry["w"])
		if r < acc:
			return entry["u"]
	return weighted[weighted.size() - 1]["u"]


static func _weighted_weapon_pick(weights: Dictionary) -> String:
	var total_weight := 0.0
	var fallback := ""
	for raw_weapon_id in weights:
		var weight := maxf(0.0, float(weights[raw_weapon_id]))
		if weight > 0.0:
			fallback = String(raw_weapon_id)
		total_weight += weight
	if total_weight <= 0.0:
		return ""
	var roll := randf() * total_weight
	for raw_weapon_id in weights:
		roll -= maxf(0.0, float(weights[raw_weapon_id]))
		if roll < 0.0:
			return String(raw_weapon_id)
	return fallback
