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
##
## 可选字段：
##   "ground_spawn_polygons": Array  —— 元素为 Array[Vector2]（顶点列表，使用时转 PackedVector2Array）。
##     仅 mission_type=="ground" 起效。
##     SAM/AA 只在这些多边形内随机刷（按面积加权挑一块 → bbox reject-sample）。
##     仍走严格陆地判定 + 间距 + 距路，多边形外的部分被自动滤掉。
##     若设置，应让多边形整体中心 ≈ zone center，使战术地图圆圈对齐刷怪区。
##     缺省时 SAM/AA 走原 zone center + radius×0.85 散布逻辑。
##     注：用嵌套 Vector2 数组而非 PackedVector2Array，因为后者构造调用在 const 字面量里不能展开。
const ZONES: Array[Dictionary] = [
	{
		"id": &"A",
		"name_key": "ZONE_A_NAME",
		"label": "A",
		"center": Vector2(-3200.0, -2500.0),    ## 横滨核心（陆）
		"radius": 2500.0,
		"mission_type": "ground",
		"ground_spawn_polygons": [
			[
				Vector2(-2512, -2207),
				Vector2(-2117, -1485),
				Vector2(-1055, -2099),
				Vector2(-1468, -2754),
			],
			[
				Vector2(-5424, -4063),
				Vector2(-5339, -2634),
				Vector2(-3957, -3096),
				Vector2(-1441, -4490),
			],
			[
				Vector2(-3212, -4605),
				Vector2(-1937, -5148),
				Vector2(-1724, -4199),
				Vector2(-3078, -3559),
			],
		],
	},
	{
		"id": &"B",
		"name_key": "ZONE_B_NAME",
		"label": "B",
		"center": Vector2(3800.0, -3800.0),     ## 木更津北（陆），从 (4500,-4500) 内移避免贴边
		"radius": 2500.0,
		"mission_type": "ground",
	},
	{
		"id": &"C",
		"name_key": "ZONE_C_NAME",
		"label": "C",
		"center": Vector2(-4100.0, 3800.0),     ## 三浦东岸 / 湾内南部（海/陆过渡），从 (-4800,4500) 内移避免贴边
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
		"ground_spawn_polygons": [
			[
				Vector2(3697, 4090),
				Vector2(3930, 3701),
				Vector2(5591, 4494),
				Vector2(5270, 5098),
			],
			[
				Vector2(5057, 5032),
				Vector2(5100, 5961),
				Vector2(6670, 6080),
				Vector2(6506, 5047),
			],
		],
	},
	{
		"id": &"E",
		"name_key": "ZONE_E_NAME",
		"label": "E",
		## 中央海域 —— BOSS 位置正南方，全海面战区
		## BOSS 在 (0, 1000) r=2200；E 在 (0, 3500) r=1800，两者南北相距 2500，
		## 边缘留 500 余量保证视觉不重叠（且被 BOSS 取消时也不会产生 UI 冲突）
		"center": Vector2(0.0, 3500.0),
		"radius": 1800.0,
		## E 专属：mission_type 只 roll "naval" 或 "elite"（见 _roll_mission_type）
		"mission_type": "naval",
		"restricted_mission_types": ["naval", "elite"],
	},
]

## BOSS 战区：放在地图中央偏南，与 4 个角的常规战区都留出余量
##  - vs A (-3200,-2500) r=2500：距 ≈ 4744 ≥ 2500+2200=4700 ✓
##  - vs B (3800,-3800) r=2500：距 ≈ 6123 ✓
##  - vs C (-4100, 3800) r=2500：距 ≈ 4965 ✓
##  - vs D (4800, 4500) r=2500：距 ≈ 5941 ✓
const BOSS_ZONE: Dictionary = {
	"id": &"BOSS",
	"name_key": "ZONE_BOSS_NAME",
	"label": "BOSS",
	"center": Vector2(0.0, 1000.0),
	"radius": 2200.0,
}

## 战区攻克时给玩家恢复的基础 HP（除了技能奖励外的额外回血）
const ZONE_CLEAR_HP_RESTORE := 30.0

## E 战区在 A+B 都清掉后出现的概率（< 1.0 表示不是 100% 必出）
const E_ZONE_UNLOCK_CHANCE := 0.60

## 运行时状态
var _states: Dictionary = {}                 ## id → State
var selected_id: StringName = &""
## 累计攻克次数（同一个战区重复攻克也会累计，用于判断 3 次攻克→解锁 BOSS）
var cleared_count: int = 0
## 历史上是否攻克过该 id（用于 E 战区"A+B 都清过"判定）
var _ever_cleared: Dictionary = {}           ## id → true
## 最近一次攻克的战区 id —— 下一轮 refresh 时排除它（不能刚打完又被选中）
var _last_cleared: StringName = &""
## 最近一次攻克的 mission_type —— 下一轮新战区 roll 时尽量避开相同类型
## （防止"刚打完中队又蹦出中队"的重复感）
var _last_cleared_mission_type: String = ""
var boss_unlocked: bool = false
## E 战区是否已经尝试过解锁（避免 A+B 清完反复 roll）
var _e_unlock_rolled: bool = false
var _rewards: Dictionary = {}                ## id → upgrade dict（该战区攻克后发放的技能）
## 本局已分配过的奖励技能 id（含已攻克 + 当前 AVAILABLE 的所有战区）。
## 用途：保证一局游戏中每个奖励技能最多出现在一个战区，不重复
var _used_reward_ids: Dictionary = {}        ## skill_id → true
var _difficulties: Dictionary = {}            ## id → int (DIFFICULTY_MIN..DIFFICULTY_MAX)
var _mission_types: Dictionary = {}            ## id → String（运行时 mission_type，覆盖 ZONES 默认）
## 标记哪些战区是"新开放"的（最近一轮 refresh 打开的），便于 UI 再次提示玩家
var _newly_opened: Array[StringName] = []

func _init() -> void:
	# 初始：A、B 可选；C、D、E 锁定；Boss 锁定
	_states[&"A"] = State.AVAILABLE
	_states[&"B"] = State.AVAILABLE
	_states[&"C"] = State.LOCKED
	_states[&"D"] = State.LOCKED
	_states[&"E"] = State.LOCKED
	_states[&"BOSS"] = State.LOCKED
	# 给初始可选的两个战区分配奖励 + 难度
	_assign_reward(&"A")
	_assign_reward(&"B")
	## 开局保底：首发两个战区不会直接出 ★★★，避免玩家一上来就被 MiG-29/Su-27 中队压制
	_roll_difficulty(&"A", 2)
	_roll_difficulty(&"B", 2)
	_roll_mission_type(&"A")
	_roll_mission_type(&"B")
	_newly_opened = [&"A", &"B"]

## BOSS 阶段：玩家已选中 BOSS（在战术地图点了 BOSS 圈）。
## 进入此阶段后：常规战区 A/B/C/D 的地图显示 + 任务推进全部停止，专心打 BOSS。
func is_boss_phase() -> bool:
	return selected_id == &"BOSS"

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
	_ever_cleared[id] = true
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
		# BOSS 解锁 → E 战区被取消掉（中央海域被 BOSS 占用）
		# 不改 _ever_cleared（E 可能都没出过），只把当前 state 压回 LOCKED
		var e_state := get_state(&"E")
		if e_state == State.AVAILABLE or e_state == State.SELECTED:
			_states[&"E"] = State.LOCKED
			if selected_id == &"E":
				selected_id = &""
			_rewards.erase(&"E")
			_difficulties.erase(&"E")
			_mission_types.erase(&"E")
		return

	# E 战区解锁判定：A + B 都曾攻克过 → 按概率出现
	# 只尝试一次，避免反复 roll；如果不出就不再出（由 C/D 等补上）
	if not _e_unlock_rolled and _ever_cleared.has(&"A") and _ever_cleared.has(&"B"):
		_e_unlock_rolled = true
		if get_state(&"E") == State.LOCKED and &"E" != _last_cleared:
			if randf() < E_ZONE_UNLOCK_CHANCE:
				_states[&"E"] = State.AVAILABLE
				_assign_reward(&"E")
				_roll_difficulty(&"E")
				_roll_mission_type(&"E")
				_newly_opened.append(&"E")
				EventLogger.log_event("ZONE", "E_Unlock",
					"after A+B cleared (chance=%.0f%% rolled success)" % (E_ZONE_UNLOCK_CHANCE * 100.0))
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
## 一局游戏中每个奖励技能只会出现在一个战区 —— 本函数过滤掉已分配过的 id
## 若候选池被全部用尽，则该战区无奖励（_rewards 不写入），UI 应处理空奖励的情况
func _assign_reward(id: StringName) -> void:
	if _rewards.has(id):
		return
	var pool := _build_reward_pool()
	# 过滤已用过的奖励
	var avail: Array = []
	for u in pool:
		var uid := String(u.get("id", ""))
		if uid != "" and not _used_reward_ids.has(uid):
			avail.append(u)
	if avail.is_empty():
		return
	var pick: Dictionary = avail[randi() % avail.size()]
	_rewards[id] = pick
	_used_reward_ids[String(pick["id"])] = true

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

func _roll_difficulty(id: StringName, max_diff: int = DIFFICULTY_MAX) -> void:
	if _difficulties.has(id):
		return
	var hi: int = clampi(max_diff, DIFFICULTY_MIN, DIFFICULTY_MAX)
	_difficulties[id] = DIFFICULTY_MIN + randi() % (hi - DIFFICULTY_MIN + 1)

func get_difficulty(id: StringName) -> int:
	return int(_difficulties.get(id, DIFFICULTY_MIN))

# ══════════════════════════════════════════════
#  任务类型（runtime roll，覆盖 ZONES 的默认 mission_type）
# ══════════════════════════════════════════════

## 基础 mission_type = "air" 的战区（C）地形在水上，只能空战中队任务
## 其他战区按难度权重滚动：
##   - ★     → ground(60) / squadron(25) / elite(15)
##   - ★★    → ground(40) / squadron(35) / elite(25)
##   - ★★★   → ground(40) / squadron(60)   — 无 elite
## elite (Sentinel 首领怪) 从 ★★★ 移除 —— 打掉 Sentinel 即完成任务，体量不够 ★★★ 分量。
## ★★★ 改为纯 ground/squadron，配合 TGT 虚拟等级 +5 floor 8 抽 MiG-29/Su-27/MiG-31 级中队。
func _roll_mission_type(id: StringName) -> void:
	if _mission_types.has(id):
		return
	var base := get_zone_by_id(id)
	var base_type: String = base.get("mission_type", "ground")

	# 带 restricted_mission_types 的战区（如 E）只从限定列表中 roll
	var restricted: Array = base.get("restricted_mission_types", [])
	if not restricted.is_empty():
		var pick: String = String(restricted[randi() % restricted.size()])
		# 尝试避开刚完成的类型，换一次；如果唯一就接受
		if pick == _last_cleared_mission_type and restricted.size() > 1:
			pick = String(restricted[randi() % restricted.size()])
		_mission_types[id] = pick
		return

	# 水上战区只能空战
	if base_type == "air":
		_mission_types[id] = "air"
		return
	# 陆地可用性检查：即便战区基础类型是 ground，若圆内几乎没有陆地
	# （战区中心偏海/城市多边形稀疏），也强制为空战中队，避免 SAM/AA 落到海面
	var has_land := zone_has_land(id)
	var diff := int(_difficulties.get(id, DIFFICULTY_MIN))
	# 最多重 roll 1 次以避开与刚完成的任务同类型，防止连续重复体验
	# （水上 air 战区上面已直接返回，不走这里）
	for attempt in range(2):
		var r := randf()
		var picked: String = ""
		match diff:
			3:
				## ★★★ 去掉 elite —— 分量不够，改走 squadron/ground
				picked = "squadron" if r < 0.60 else "ground"
			2:
				## ★★ 下放 elite（25%），其余 squadron/ground
				if r < 0.25:
					picked = "elite"
				elif r < 0.60:
					picked = "squadron"
				else:
					picked = "ground"
			_:
				## ★ 开始提供 elite（15%），作为玩家早期首次见到 Sentinel 的场合
				if r < 0.15:
					picked = "elite"
				elif r < 0.40:
					picked = "squadron"
				else:
					picked = "ground"
		# 水上/近海战区不允许地面任务 —— 改为空战中队
		if picked == "ground" and not has_land:
			picked = "squadron"
		if picked != _last_cleared_mission_type or attempt >= 1:
			_mission_types[id] = picked
			return

func get_mission_type(id: StringName) -> String:
	if _mission_types.has(id):
		return String(_mission_types[id])
	var z := get_zone_by_id(id)
	return z.get("mission_type", "ground")

## 运行时覆写 mission_type（zone_mission 在刷怪前做陆地可用性检查时调用，
## 防止"地面任务刷到海上"的情况下一次 refresh 仍然显示错误的任务类型）
func set_mission_type(id: StringName, mission_type: String) -> void:
	_mission_types[id] = mission_type

# ══════════════════════════════════════════════
#  Debug 辅助（F6 面板用）
# ══════════════════════════════════════════════

## Debug：强制把任意状态的战区改为 AVAILABLE，并 roll 好奖励/难度/任务类型
## 若已经是 AVAILABLE/SELECTED 且已有 reward+difficulty，不会覆盖
func debug_set_available(id: StringName) -> void:
	_states[id] = State.AVAILABLE
	if not _rewards.has(id):
		_assign_reward(id)
	if not _difficulties.has(id):
		_roll_difficulty(id)
	if not _mission_types.has(id):
		_roll_mission_type(id)

## Debug：指定战区使用指定 mission_type（不 roll 随机，直接覆写）
## 与 set_mission_type 相同但命名更明确
func debug_set_mission_type(id: StringName, new_type: String) -> void:
	_mission_types[id] = new_type

## Debug：强制把战区置为 CLEARED（不走 mark_cleared 的 refresh 逻辑）
func debug_mark_cleared(id: StringName) -> void:
	_states[id] = State.CLEARED
	if selected_id == id:
		selected_id = &""
	_rewards.erase(id)
	_difficulties.erase(id)
	_mission_types.erase(id)

## Debug：强制 LOCK 战区（隐藏到战术地图外）
func debug_mark_locked(id: StringName) -> void:
	_states[id] = State.LOCKED
	if selected_id == id:
		selected_id = &""
	_rewards.erase(id)
	_difficulties.erase(id)
	_mission_types.erase(id)

## 获取所有非 BOSS 的战区 id（A/B/C/D/E）
static func get_all_zone_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for z in ZONES:
		ids.append(z["id"])
	return ids

# ══════════════════════════════════════════════
#  陆地可用性（水上战区不允许地面任务）
# ══════════════════════════════════════════════

## 战区圆内可视为"有地面可刷"的最低陆地点比例
const LAND_FRACTION_THRESHOLD := 0.12
## 采样点数（随机散布 + 固定中心点）
const LAND_SAMPLE_COUNT := 48

## 在战区圆内（或 ground_spawn_polygons 内）随机采样若干点，判断陆地比例是否足以支撑"地面任务"
## 采样半径与 zone_mission 的 SCATTER_RADIUS_SCALE(0.85) 对齐，避免圆边采到外海
##
## 若战区设了 ground_spawn_polygons，直接返回 true —— 用户既然指定了多边形，
## 就默认那些点在陆地上（手画范围内不会故意标到水里）；实际 spawn 仍走严格陆地判定兜底
static func zone_has_land(id: StringName) -> bool:
	var z: Dictionary = {}
	for zz in ZONES:
		if zz["id"] == id:
			z = zz
			break
	if z.is_empty():
		return false
	var polys: Array = z.get("ground_spawn_polygons", [])
	if not polys.is_empty():
		return true
	var center: Vector2 = z["center"]
	var radius: float = float(z["radius"]) * 0.85
	var land_hits := 0
	## 采用严格判定（只认 OSM 陆地 mask），与 zone_mission 实际刷怪的落点判定保持一致
	## —— 手画 LAND 轮廓包含港池/海湾，会高估陆地占比
	if MapGeography.is_on_land_strict(center):
		land_hits += 1
	for i in range(LAND_SAMPLE_COUNT):
		var a := TAU * float(i) / float(LAND_SAMPLE_COUNT)
		## 用黄金比例差步进半径，避免所有采样都落在同一圆环
		var t := fposmod(float(i) * 0.618033, 1.0)
		var r := sqrt(t) * radius
		var p := center + Vector2(cos(a), sin(a)) * r
		if MapGeography.is_on_land_strict(p):
			land_hits += 1
	var frac := float(land_hits) / float(LAND_SAMPLE_COUNT + 1)
	return frac >= LAND_FRACTION_THRESHOLD
