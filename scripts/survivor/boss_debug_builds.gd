## Boss Debug 模式 — 主题化随机 build roller
##
## 在 5 个主题中随机抽一个，按主题给 SurvivorData.UPGRADES 加权后抽 N 张。
## 抽卡按 max_stacks / requires / exclusive_to / excludes / requires_skill
## 全部尊重，模拟玩家正常升级 N 次的结果。
##
## 使用：BossDebugBuilds.roll_build(15, &"f16", aircraft.params)
class_name BossDebugBuilds
extends RefCounted

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

## 返回 [theme_name, picks_array]；level 决定 picks 数量（level 1→N 共 N-1 次升级机会）
static func roll_build(level: int, aircraft_id: StringName, params: AircraftParams) -> Dictionary:
	var theme_keys: Array = THEMES.keys()
	var theme_name: String = theme_keys[randi() % theme_keys.size()]
	var theme_def: Dictionary = THEMES[theme_name]
	var picks: Array[Dictionary] = _roll_for_theme(theme_def, level, aircraft_id, params)
	return {"theme": theme_name, "picks": picks}

## 指定主题 roll（debug 热键切主题用）
static func roll_for_theme_name(theme_name: String, level: int, aircraft_id: StringName, params: AircraftParams) -> Dictionary:
	if not THEMES.has(theme_name):
		theme_name = "missile"
	var picks: Array[Dictionary] = _roll_for_theme(THEMES[theme_name], level, aircraft_id, params)
	return {"theme": theme_name, "picks": picks}

static func _roll_for_theme(theme_def: Dictionary, level: int, aircraft_id: StringName, params: AircraftParams) -> Array[Dictionary]:
	var picks_target: int = maxi(level - 1, 1)
	var picks: Array[Dictionary] = []
	var stack_count: Dictionary = {}

	# 每次 pick 后基础池可能因 requires_skill / excludes 变化（picks 也算 stacks），所以每轮都重新筛
	var attempts := 0
	while picks.size() < picks_target and attempts < 400:
		attempts += 1
		# 1. 用 picks + 已堆数构造 owned_stacks 给 is_upgrade_available_for
		var pool: Array = SurvivorData.UPGRADES.filter(func(u):
			# 已经满 stacks 的直接排除
			var max_st: int = int(u.get("max_stacks", 1))
			if int(stack_count.get(u["id"], 0)) >= max_st:
				return false
			return SurvivorData.is_upgrade_available_for(u, aircraft_id, params, stack_count)
		)
		if pool.is_empty():
			break  # 抽不到了

		# 2. 给 pool 加权
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

		# 3. 加权随机抽一张
		var pick: Dictionary = _weighted_pick(weighted, total_w)
		if pick.is_empty():
			break
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
