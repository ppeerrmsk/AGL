class_name ZoneData
extends RefCounted

## 战术地图战区数据 + 状态机
##
## P2：数据结构完整，但奖励/任务逻辑为占位
## P3 会接入：进入圈 + 击杀 N 地面单位 + 奖励抽取

enum State {
	LOCKED,       ## 灰色，不可选
	AVAILABLE,    ## 可选
	SELECTED,     ## 玩家已选，正在前往/执行中
	CLEARED,      ## 已攻克
}

## 战区难度（1~3 星，影响驻守敌机强度/数量）
const DIFFICULTY_MIN := 1
const DIFFICULTY_MAX := 3

## 战区定义（世界坐标 + 半径 + 翻译 key）
## 位置参考用户手绘：A/C 在西侧（横滨/海滨公园），B/D 在东侧，Boss 位于地图中央偏北
## mission_type 可选值：
##   "ground"  → 战区刷 SAM + AA（需要陆地）
##   "air"     → 战区刷敌方中队（可设在海上）
## 战区中心与半径保证 center ± radius 不越界（地图 ±7500）
const ZONES: Array[Dictionary] = [
	{
		"id": &"A",
		"name_key": "ZONE_A_NAME",
		"label": "A",
		"center": Vector2(-3200.0, -2500.0),    ## 横滨核心（陆）
		"radius": 2500.0,
		"mission_type": "ground",
	},
	{
		"id": &"B",
		"name_key": "ZONE_B_NAME",
		"label": "B",
		"center": Vector2(4500.0, -4500.0),     ## 木更津北（陆）
		"radius": 2500.0,
		"mission_type": "ground",
	},
	{
		"id": &"C",
		"name_key": "ZONE_C_NAME",
		"label": "C",
		"center": Vector2(-4800.0, 4500.0),     ## 三浦东岸 / 湾内南部（海/陆过渡）
		"radius": 2500.0,
		"mission_type": "air",                   ## 海上，改为空战中队
	},
	{
		"id": &"D",
		"name_key": "ZONE_D_NAME",
		"label": "D",
		"center": Vector2(4800.0, 4500.0),      ## 富津基部（陆）
		"radius": 2500.0,
		"mission_type": "ground",
	},
]

const BOSS_ZONE: Dictionary = {
	"id": &"BOSS",
	"name_key": "ZONE_BOSS_NAME",
	"label": "BOSS",
	"center": Vector2(0.0, -500.0),
	"radius": 1800.0,
}

## 战区攻克时给玩家恢复的基础 HP（除了技能奖励外的额外回血）
const ZONE_CLEAR_HP_RESTORE := 30.0

## 运行时状态
var _states: Dictionary = {}                 ## id → State
var selected_id: StringName = &""
## 累计攻克次数（同一个战区重复攻克也会累计，用于判断 3 次攻克→解锁 BOSS）
var cleared_count: int = 0
## 最近一次攻克的战区 id —— 下一轮 refresh 时排除它（不能刚打完又被选中）
var _last_cleared: StringName = &""
## 最近一次攻克的 mission_type —— 下一轮新战区 roll 时尽量避开相同类型
## （防止"刚打完中队又蹦出中队"的重复感）
var _last_cleared_mission_type: String = ""
var boss_unlocked: bool = false
var _rewards: Dictionary = {}                ## id → upgrade dict（该战区攻克后发放的技能）
var _difficulties: Dictionary = {}            ## id → int (DIFFICULTY_MIN..DIFFICULTY_MAX)
var _mission_types: Dictionary = {}            ## id → String（运行时 mission_type，覆盖 ZONES 默认）
## 标记哪些战区是"新开放"的（最近一轮 refresh 打开的），便于 UI 再次提示玩家
var _newly_opened: Array[StringName] = []

func _init() -> void:
	# 初始：A、B 可选；C、D 锁定；Boss 锁定
	_states[&"A"] = State.AVAILABLE
	_states[&"B"] = State.AVAILABLE
	_states[&"C"] = State.LOCKED
	_states[&"D"] = State.LOCKED
	_states[&"BOSS"] = State.LOCKED
	# 给初始可选的两个战区分配奖励 + 难度
	_assign_reward(&"A")
	_assign_reward(&"B")
	_roll_difficulty(&"A")
	_roll_difficulty(&"B")
	_roll_mission_type(&"A")
	_roll_mission_type(&"B")
	_newly_opened = [&"A", &"B"]

func get_state(id: StringName) -> State:
	return _states.get(id, State.LOCKED)

func set_state(id: StringName, state: State) -> void:
	_states[id] = state

## 查找战区数据（不含 Boss）
func get_zone_by_id(id: StringName) -> Dictionary:
	for z in ZONES:
		if z["id"] == id:
			return z
	if BOSS_ZONE["id"] == id:
		return BOSS_ZONE
	return {}

## 玩家选中某战区（从 AVAILABLE → SELECTED）
func select_zone(id: StringName) -> bool:
	if get_state(id) != State.AVAILABLE:
		return false
	# 清除之前的 SELECTED
	if selected_id != &"":
		if get_state(selected_id) == State.SELECTED:
			set_state(selected_id, State.AVAILABLE)
	selected_id = id
	set_state(id, State.SELECTED)
	return true

## 攻克某战区
## 同一个战区可以被反复攻克（走回头路），每次计入 cleared_count
## 刚攻克的战区在下一轮 refresh 时会被排除（不能立刻又被选中）
func mark_cleared(id: StringName) -> void:
	set_state(id, State.CLEARED)
	cleared_count += 1
	_last_cleared = id
	_last_cleared_mission_type = get_mission_type(id)
	if selected_id == id:
		selected_id = &""
	# 清除该战区的奖励/难度缓存，下次再开启时会 roll 新的
	_rewards.erase(id)
	_difficulties.erase(id)
	_mission_types.erase(id)
	_refresh_availability_after_clear()

func _refresh_availability_after_clear() -> void:
	_newly_opened.clear()
	# 累计攻克 3 次 → 解锁 Boss（无论是否走回头路）
	if cleared_count >= 3:
		boss_unlocked = true
		_states[&"BOSS"] = State.AVAILABLE
		_newly_opened.append(&"BOSS")
		return
	# 候选池 = 所有非 AVAILABLE / 非 SELECTED 的战区，排除刚攻克的那个
	# 这样同一个战区之后可以被再次选中（走回头路），但不会"刚打完又立刻刷"
	var pool: Array[StringName] = []
	for z in ZONES:
		var zid: StringName = z["id"]
		if zid == _last_cleared:
			continue
		var st := get_state(zid)
		if st == State.AVAILABLE or st == State.SELECTED:
			continue
		pool.append(zid)
	if pool.is_empty():
		return
	pool.shuffle()
	var open_id: StringName = pool[0]
	_states[open_id] = State.AVAILABLE
	_assign_reward(open_id)
	_roll_difficulty(open_id)
	_roll_mission_type(open_id)
	_newly_opened.append(open_id)

## 返回最近 refresh 新开放的战区 id 列表（UI 显示"新战区开放"提示用），读一次后通常重置
func take_newly_opened() -> Array[StringName]:
	var out := _newly_opened.duplicate()
	_newly_opened.clear()
	return out

func peek_newly_opened() -> Array[StringName]:
	return _newly_opened.duplicate()

## 获取当前选中战区的世界坐标（P2 arrow 指示用）；未选中返回 INF
func get_selected_world_pos() -> Vector2:
	if selected_id == &"":
		return Vector2.INF
	var z := get_zone_by_id(selected_id)
	if z.is_empty():
		return Vector2.INF
	return z["center"]

# ══════════════════════════════════════════════
#  奖励系统
# ══════════════════════════════════════════════

## 战区奖励池：目前使用所有"进化技能"（UPGRADES 中 evolved=true）
## 这些技能已从常规升级随机池移除（由 survivor_data.is_upgrade_available_for 控制可用性）
## 未来可扩展：加入一些非进化技能（稀有生存强化等）
static func _build_reward_pool() -> Array:
	var pool: Array = []
	for u in SurvivorData.UPGRADES:
		if u.get("evolved", false):
			pool.append(u)
	return pool

static func _infer_category(skill_id: String) -> StringName:
	if skill_id.contains("flare"):
		return &"FLARE"
	if skill_id.contains("gun") or skill_id.contains("ciws"):
		return &"GUN"
	if skill_id.contains("missile") or skill_id.contains("proximity") or skill_id.contains("bounce"):
		return &"MISSILE"
	return &"SURVIVAL"

static func category_hint_key(category: StringName) -> String:
	match category:
		&"FLARE": return "ZONE_REWARD_HINT_FLARE"
		&"GUN": return "ZONE_REWARD_HINT_GUN"
		&"MISSILE": return "ZONE_REWARD_HINT_MISSILE"
		_: return "ZONE_REWARD_HINT_SURVIVAL"

## 随机给某个战区分配一个奖励技能（如已分配则保留）
func _assign_reward(id: StringName) -> void:
	if _rewards.has(id):
		return
	var pool := _build_reward_pool()
	if pool.is_empty():
		return
	var pick: Dictionary = pool[randi() % pool.size()]
	_rewards[id] = pick

## 获取某战区的奖励 upgrade dict（可能为空）
func get_reward(id: StringName) -> Dictionary:
	return _rewards.get(id, {})

## 获取某战区的奖励"类别提示 key"（用于 UI 翻译）
func get_reward_category_key(id: StringName) -> String:
	var r := get_reward(id)
	if r.is_empty():
		return "ZONE_REWARD_HINT_UNKNOWN"
	return category_hint_key(_infer_category(r["id"]))

# ══════════════════════════════════════════════
#  难度
# ══════════════════════════════════════════════

func _roll_difficulty(id: StringName) -> void:
	if _difficulties.has(id):
		return
	_difficulties[id] = DIFFICULTY_MIN + randi() % (DIFFICULTY_MAX - DIFFICULTY_MIN + 1)

func get_difficulty(id: StringName) -> int:
	return int(_difficulties.get(id, DIFFICULTY_MIN))

# ══════════════════════════════════════════════
#  任务类型（runtime roll，覆盖 ZONES 的默认 mission_type）
# ══════════════════════════════════════════════

## 基础 mission_type = "air" 的战区（C）地形在水上，只能空战中队任务
## 其他战区按难度权重滚动：
##   - ★     → ground(70) / squadron(30)
##   - ★★    → ground(50) / squadron(50)
##   - ★★★   → ground(30) / squadron(30) / elite(40)  (elite = Sentinel 首领怪)
func _roll_mission_type(id: StringName) -> void:
	if _mission_types.has(id):
		return
	var base := get_zone_by_id(id)
	var base_type: String = base.get("mission_type", "ground")
	# 水上战区只能空战
	if base_type == "air":
		_mission_types[id] = "air"
		return
	var diff := int(_difficulties.get(id, DIFFICULTY_MIN))
	# 最多重 roll 1 次以避开与刚完成的任务同类型，防止连续重复体验
	# （水上 air 战区上面已直接返回，不走这里）
	for attempt in range(2):
		var r := randf()
		var picked: String = ""
		match diff:
			3:
				if r < 0.40:
					picked = "elite"
				elif r < 0.70:
					picked = "squadron"
				else:
					picked = "ground"
			2:
				picked = "squadron" if r < 0.50 else "ground"
			_:
				picked = "squadron" if r < 0.30 else "ground"
		if picked != _last_cleared_mission_type or attempt >= 1:
			_mission_types[id] = picked
			return

func get_mission_type(id: StringName) -> String:
	if _mission_types.has(id):
		return String(_mission_types[id])
	var z := get_zone_by_id(id)
	return z.get("mission_type", "ground")
