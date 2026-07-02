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
		## 中央海域偏东 —— 与 C(-4100, 3800)r2500 / D(4800, 4500)r2500 同时拉开间距
		## 距 C ≈ 4510 → 边缘 gap ≈ 210；距 D ≈ 4512 → 边缘 gap ≈ 212；
		## y 不动（避免与 BOSS_SOUTH(0,3500) 区域更近），仅 x 东移 400
		"center": Vector2(400.0, 3500.0),
		"radius": 1800.0,
		## E 专属：mission_type 只 roll "naval" 或 "elite"（见 _roll_mission_type）
		"mission_type": "naval",
		"restricted_mission_types": ["naval", "elite"],
	},
]

## BOSS 战区：不再固定中央位置，根据玩家最后攻克的战区动态选南北
##   - 最后攻克 ∈ {A, B}（北部） → BOSS 出现在 **南** (E 位置)，朝北飞来迎战
##   - 最后攻克 ∈ {C, D, E}（南部） → BOSS 出现在 **北** (B 位置)，朝西南飞来迎战
## 目的：BOSS 出现在玩家上一个战区的对角侧，避免刷脸 + 给玩家赶赴时间
const BOSS_RADIUS: float = 2200.0
## 北 BOSS：桥主体以南、靠近桥的位置（视觉上像"舰队从桥下驶出"）
## 桥线性逼近 y = 0.827x - 5616；center_y = -500 在 x=2500 处留 ~1300 px 离桥
## 舰队北角（center + (1414, -2546)）= (3914, -3046)，会越过桥线 ~667 px —
## 这部分船在视觉上贴近桥北侧，由玩家自己判断接受程度；主体（CV + 贴身护航）仍在桥南
const BOSS_NORTH_CENTER: Vector2 = Vector2(2500.0, -500.0)
const BOSS_SOUTH_CENTER: Vector2 = Vector2(0.0, 3500.0)      ## E 战区位置（南）
const BOSS_NORTH_HEADING_DEG: float = 225.0                  ## 北 BOSS 朝西南（向玩家所在南部扑来）
const BOSS_SOUTH_HEADING_DEG: float = 0.0                    ## 南 BOSS 朝正北

## 运行时 BOSS 战区数据（boss_unlocked 时由 _finalize_boss_placement 填充）
var boss_zone: Dictionary = {
	"id": &"BOSS",
	"name_key": "ZONE_BOSS_NAME",
	"label": "BOSS",
	"center": BOSS_NORTH_CENTER,          ## 占位，boss_unlocked 前不使用
	"radius": BOSS_RADIUS,
}
var boss_heading_deg: float = 0.0         ## BOSS 出场朝向，供 CSG 等 encounter 决定航线

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
## 最近一次攻克的 mission_type（保留供日志/UI 用，不再参与抽取决策）
var _last_cleared_mission_type: String = ""

## ── 任务类型反重复抽取系统 ──
##
## 维护最近 N 次 `_roll_mission_type` 产出的类型滑窗。每次抽取时，把该类型
## 的基础权重按"窗口内出现次数"指数衰减（每出现一次 ×REPEAT_PENALTY），
## 自然把抽取倾向推向"窗口里没出现过的类型"。
##
## 比硬性"禁止上一次类型"更鲁棒：
##   - 解决"刚开局 A/B 都 ground，C 又 ground，D 还 ground"的灾难
##   - 不是硬禁 → 偶发重复仍可能，避免可预测性
##   - E 战区 restricted_mission_types 走同一套衰减
##
## 历史在 _init / 首次 _assign 后就开始记录，A/B 开局抽两次也会互相影响。
const MISSION_HISTORY_WINDOW := 5
const MISSION_REPEAT_PENALTY := 0.30
var _mission_type_history: Array[String] = []

## 各难度下各 mission_type 的基础权重（数值是相对值，会按历史衰减后再归一）
## 与旧 _roll_mission_type 的概率近似一致，便于回归
const MISSION_TYPE_BASE_WEIGHTS := {
	1: {"ground": 45.0, "squadron": 30.0, "elite": 25.0},   ## ★ 提一些 elite，玩家早期能见 Sentinel
	2: {"ground": 35.0, "squadron": 35.0, "elite": 30.0},   ## ★★ 三类均衡
	3: {"ground": 40.0, "squadron": 60.0},                    ## ★★★ 无 elite（分量不够）
}
var boss_unlocked: bool = false
## 战区阶段是否已结束（survivor_mode 在 10 分钟到点时置 true）
## 置 true 后 _refresh_availability_after_clear 不再开新战区，E 解锁路径也屏蔽
var phase_ended: bool = false
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
	if boss_zone["id"] == id:
		return boss_zone
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

## 依据 `_last_cleared` 决定 BOSS 出现在南还是北
## 并把同位置的常规战区（E 或 B）压回 LOCKED，避免 UI 重叠
## 选定位置后若在陆地上则向海面吸附 —— 舰队 BOSS（CSG）才能刷进池子
## public：survivor_mode 在 10 分钟到点（或 SELECTED 战区结算后）调用
func finalize_boss_placement() -> void:
	_finalize_boss_placement()

## 把所有 AVAILABLE 状态的战区压回 LOCKED，except_id 保留不动（玩家正在打的）
## 用途：10 分钟战区阶段结束时调用，让 BOSS 阶段视野干净
func lock_all_open_zones_except(except_id: StringName) -> void:
	for z in ZONES:
		var zid: StringName = z["id"]
		if zid == except_id:
			continue
		var st := get_state(zid)
		if st == State.AVAILABLE:
			_states[zid] = State.LOCKED
			_rewards.erase(zid)
			_difficulties.erase(zid)
			_mission_types.erase(zid)
	_newly_opened.clear()

func _finalize_boss_placement() -> void:
	# 最后攻克 A/B（北部）→ BOSS 出现在南；其他情况（C/D/E 或未知）→ 出现在北
	var spawn_at_south: bool = _last_cleared == &"A" or _last_cleared == &"B"
	var center: Vector2
	if spawn_at_south:
		center = BOSS_SOUTH_CENTER
		boss_heading_deg = BOSS_SOUTH_HEADING_DEG
		_cancel_zone_if_open(&"E")
	else:
		center = BOSS_NORTH_CENTER
		boss_heading_deg = BOSS_NORTH_HEADING_DEG
		_cancel_zone_if_open(&"B")
	# 陆地吸附：BOSS_NORTH 原位 (B) 是陆地，CSG 上不了陆，
	# 这里把中心点平移到最近的海面，让舰队 BOSS 也能正常刷
	boss_zone["center"] = _snap_to_water(center, BOSS_RADIUS)
	EventLogger.log_event("BOSS", "Placement",
		"center=%s heading=%.0f° (last_cleared=%s)" % [boss_zone["center"], boss_heading_deg, _last_cleared])

## 若 pos 已是海面直接返回；否则螺旋扫描半径 search_radius 内的方向，
## 找到的第一个海面点返回。全在陆地就回退原点（保底，CSG 会被 requires_water 过滤掉）
func _snap_to_water(pos: Vector2, search_radius: float) -> Vector2:
	if not MapGeography.is_on_land(pos):
		return pos
	# 16 方向 × 3 步长 = 48 候选点，由近到远选第一个海面点
	for step in [search_radius * 0.5, search_radius * 1.0, search_radius * 1.5]:
		for i in range(16):
			var ang: float = float(i) * TAU / 16.0
			var candidate: Vector2 = pos + Vector2(cos(ang), sin(ang)) * step
			if not MapGeography.is_on_land(candidate):
				return candidate
	return pos

func _cancel_zone_if_open(zid: StringName) -> void:
	var st := get_state(zid)
	if st == State.AVAILABLE or st == State.SELECTED:
		_states[zid] = State.LOCKED
		if selected_id == zid:
			selected_id = &""
		_rewards.erase(zid)
		_difficulties.erase(zid)
		_mission_types.erase(zid)

func _refresh_availability_after_clear() -> void:
	_newly_opened.clear()
	# 阶段已结束（10 分钟到点）→ 不再开新战区，BOSS 由 survivor_mode 接管
	if phase_ended:
		return

	# E 战区解锁判定：A + B 都曾攻克过 → 按概率出现
	# 只尝试一次，避免反复 roll；如果不出就不再出（由 C/D 等补上）
	# 注意：E 单独占一次 refresh（不和下方 2 个新战区叠加），保留原行为
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
	# 同一个战区之后可以被再次选中（走回头路），但不会"刚打完又立刻刷"
	#
	# 加权抽取（2026-05-09）：CLEARED 比 LOCKED 多一点权重 →
	# 让"已攻克战区被重新激活刷新敌人"成为玩家能感知的机制，
	# 而不只是无差别随机（早期 LOCKED 数量远多于 CLEARED 时几乎抽不到）
	var pool: Array[StringName] = []
	var weights: Array[float] = []
	for z in ZONES:
		var zid: StringName = z["id"]
		if zid == _last_cleared:
			continue
		var st := get_state(zid)
		if st == State.AVAILABLE or st == State.SELECTED:
			continue
		pool.append(zid)
		# CLEARED 1.5× 权重（再激活），LOCKED 1.0× 权重（新开）
		weights.append(1.5 if st == State.CLEARED else 1.0)
	if pool.is_empty():
		return
	# 加权无放回抽 2 个
	var open_count: int = mini(2, pool.size())
	for i in range(open_count):
		var idx: int = _weighted_pick(weights)
		if idx < 0:
			break
		var open_id: StringName = pool[idx]
		var was_cleared: bool = get_state(open_id) == State.CLEARED
		pool.remove_at(idx)
		weights.remove_at(idx)
		_states[open_id] = State.AVAILABLE
		_assign_reward(open_id)
		_roll_difficulty(open_id)
		_roll_mission_type(open_id)
		_newly_opened.append(open_id)
		EventLogger.log_event("ZONE", "Reactivated" if was_cleared else "Opened",
			"id=%s mt=%s diff=%d" % [open_id, get_mission_type(open_id), get_difficulty(open_id)])

## 加权随机：返回 weights 数组中按权重抽取的索引；空数组返回 -1
func _weighted_pick(weights: Array[float]) -> int:
	if weights.is_empty():
		return -1
	var total: float = 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return 0
	var r: float = randf() * total
	var acc: float = 0.0
	for i in range(weights.size()):
		acc += weights[i]
		if r <= acc:
			return i
	return weights.size() - 1

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

## 抽取战区的 mission_type，写入 `_mission_types[id]` 并推入历史滑窗。
##   - C 战区基础 type=="air"（水上）→ 直接 air，不参与抽取
##   - 带 restricted_mission_types 的战区（E）→ 限定池里加权抽
##   - 普通战区 → MISSION_TYPE_BASE_WEIGHTS[difficulty] 加权抽
##   - 陆地不足时 ground 候选权重清零（不会被选中），避免 SAM/AA 落水
##   - 抽取前对每个候选权重按"历史出现次数"做 pow(REPEAT_PENALTY, count) 衰减
func _roll_mission_type(id: StringName) -> void:
	if _mission_types.has(id):
		return
	var base := get_zone_by_id(id)
	var base_type: String = base.get("mission_type", "ground")

	# 水上战区只能空战
	if base_type == "air":
		_set_mission_type_and_record(id, "air")
		return

	# E 战区：从 restricted_mission_types 等权抽，再走衰减
	var restricted: Array = base.get("restricted_mission_types", [])
	if not restricted.is_empty():
		var weights: Dictionary = {}
		for t_any in restricted:
			weights[String(t_any)] = 1.0
		var picked := _weighted_pick_with_history(weights)
		if picked == "":
			picked = String(restricted[randi() % restricted.size()])  ## 兜底
		_set_mission_type_and_record(id, picked)
		return

	# 普通战区：按难度查基础权重表
	var diff: int = int(_difficulties.get(id, DIFFICULTY_MIN))
	var base_weights: Dictionary = MISSION_TYPE_BASE_WEIGHTS.get(diff, MISSION_TYPE_BASE_WEIGHTS[DIFFICULTY_MIN])
	var weights := base_weights.duplicate()

	# 陆地可用性：圆内陆地不足 → ground 不能抽（让其他类型瓜分权重）
	if not zone_has_land(id):
		weights["ground"] = 0.0

	var picked2 := _weighted_pick_with_history(weights)
	if picked2 == "":
		picked2 = "squadron"  ## 兜底：所有候选权重都为 0（理论不会发生）
	_set_mission_type_and_record(id, picked2)

## 写入 _mission_types + 推入历史滑窗（同一个 zone 重 roll 时不会重复推 —— `if _mission_types.has` 已挡）
func _set_mission_type_and_record(id: StringName, mission_type: String) -> void:
	_mission_types[id] = mission_type
	_mission_type_history.append(mission_type)
	if _mission_type_history.size() > MISSION_HISTORY_WINDOW:
		_mission_type_history.pop_front()

## 加权抽取：对每个候选 type 按"历史窗口内出现次数"做指数衰减，再归一抽取
## 返回 "" 表示所有权重都为 0（调用方应给兜底）
func _weighted_pick_with_history(base_weights: Dictionary) -> String:
	var adjusted: Array = []  ## [[type, weight], ...]
	var total := 0.0
	for k in base_weights.keys():
		var t: String = String(k)
		var w0: float = float(base_weights[k])
		if w0 <= 0.0:
			continue
		var count: int = _count_in_history(t)
		var w: float = w0 * pow(MISSION_REPEAT_PENALTY, count)
		if w <= 0.0001:
			continue
		adjusted.append([t, w])
		total += w
	if total <= 0.0 or adjusted.is_empty():
		return ""
	var r := randf() * total
	var acc := 0.0
	for entry in adjusted:
		acc += float(entry[1])
		if r <= acc:
			return String(entry[0])
	return String(adjusted[adjusted.size() - 1][0])

func _count_in_history(mission_type: String) -> int:
	var c := 0
	for t in _mission_type_history:
		if t == mission_type:
			c += 1
	return c

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
