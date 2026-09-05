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
	FAILED,       ## 任务失败；战术地图完全隐藏，不算攻克
}

## 战区难度（1~3 星，影响驻守敌机强度/数量）
const DIFFICULTY_MIN := 1
const DIFFICULTY_MAX := 3
## 三级战区是全图单槽战略威胁。所有正式开放路径（普通、机场、可选任务、Debug）
## 都必须经 `_tier3_allowed_for`，不能各自维护一份上限。
const MAX_CONCURRENT_TIER3_ZONES := 1

## 轰炸机护送不是普通战区军械奖励：成功只给固定星级经验。
## 该值不走击杀 XP 乘区/小队分摊，保证 Tab 预告值与实际到账完全一致。
const BOMBER_ESCORT_XP_PER_STAR := 150

## 战区定义（世界坐标 + 半径 + 翻译 key）
## 布局沿用用户手绘的相对方位（A/C 西侧、B/D 东侧），2026-07-05 扩图 60km 后中心 ×2 外推
## （spec map-expansion §2.4：任两区缘距 ≥2000px、离边 ≥1500px；回归见 tests/test_map_expansion.gd）
## mission_type 可选值：
##   "ground"  → 战区刷 SAM + AA（需要陆地）
##   "air"     → 战区刷敌方中队（可设在海上）
## 战区中心与半径保证 center ± radius 不越界（地图 ±15000）
##
## 可选字段：
##   "ground_spawn_polygons": Array  —— 元素为 Array[Vector2]（顶点列表，使用时转 PackedVector2Array）。
##     仅 mission_type=="ground" 起效。
##     SAM/AA 只在这些多边形内随机刷（按面积加权挑一块 → bbox reject-sample）。
##     仍走严格陆地判定 + 间距 + 距路，多边形外的部分被自动滤掉。
##     若设置，应让多边形整体中心 ≈ zone center，使战术地图圆圈对齐刷怪区。
##     缺省时 SAM/AA 走原 zone center + radius×0.85 散布逻辑。
##     注：用嵌套 Vector2 数组而非 PackedVector2Array，因为后者构造调用在 const 字面量里不能展开。
##     ⚠ 扩图后 A/D 的旧手画多边形（±7500 时代绝对坐标）已作废删除，暂走散布 fallback；
##       如需精修刷怪区，按 docs/reference/manual-map-editing.md 对新底图重描。
const ZONES: Array[Dictionary] = [
	{
		"id": &"A",
		"name_key": "ZONE_A_NAME",
		"label": "A",
		"center": Vector2(-6400.0, -5000.0),    ## 川崎/横滨北内陆城区（陆）
		"radius": 3500.0,                        ## 2026-07-06 密度调优 2500→3500（60km 空间充裕）
		"mission_type": "ground",
	},
	{
		"id": &"B",
		"name_key": "ZONE_B_NAME",
		"label": "B",
		## ×2 初值 (7600,-7600) 落在湾里（land_mask 占比 0.00，test_map_expansion 抓出），
		## 网格扫描修正到市川/船桥湾岸城带；密度调优半径 2500→3000（陆带贴北边界，
		## y 同步内收 -11000→-10500 保住离边 ≥1500）
		"center": Vector2(6000.0, -10500.0),    ## 市川/船桥湾岸（陆）
		"radius": 3000.0,
		"mission_type": "ground",
	},
	{
		"id": &"C",
		"name_key": "ZONE_C_NAME",
		"label": "C",
		"center": Vector2(-8200.0, 7600.0),     ## 横须贺/三浦东岸海域（海/陆过渡）
		"radius": 3500.0,                        ## 2026-07-06 密度调优 2500→3500
		"mission_type": "air",                   ## 海上，改为空战中队
	},
	{
		"id": &"D",
		"name_key": "ZONE_D_NAME",
		"label": "D",
		"center": Vector2(9600.0, 9000.0),      ## 房总西岸（君津/富津，陆）
		"radius": 3500.0,                        ## 2026-07-06 密度调优 2500→3500
		"mission_type": "ground",
	},
	{
		"id": &"E",
		"name_key": "ZONE_E_NAME",
		"label": "E",
		## 中央海域偏南（浦贺水道北口）—— 与 C/D 的缘距 ≈3km（扩图前仅 ~210px 贴脸，
		## 是"战区目标互飞对方区域"的根因；敌机雷达 3~4.5km 略够不到）
		"center": Vector2(800.0, 7000.0),
		"radius": 2500.0,                        ## 2026-07-06 密度调优 1800→2500
		## E 专属：mission_type 只 roll "naval" 或 "squadron"（见 _roll_mission_type；
		## elite 任务已移除——spec early-game-uav-rework §2.3，squadron 可在水上刷）
		"mission_type": "naval",
		"restricted_mission_types": ["naval", "squadron"],
	},
	{
		"id": &"F",
		"name_key": "ZONE_F_NAME",
		"label": "F",
		## 都心北内陆（荒川北岸，A/B 之间的北中空档）—— spec battlefield-tempo-pass §2.2
		## 几何：离边 1800；F↔A 缘距 ≈2047（压 2000 下限，动 F 前先跑 test_map_expansion）
		"center": Vector2(-1500.0, -11000.0),
		"radius": 2200.0,
		"mission_type": "ground",
	},
	{
		"id": &"G",
		"name_key": "ZONE_G_NAME",
		"label": "G",
		## 千叶中部（东侧中带空档）—— spec battlefield-tempo-pass §2.2
		## air 型不查陆地占比；离边 1700，与 B/D/E 缘距 4400+
		"center": Vector2(10800.0, -1800.0),
		"radius": 2500.0,
		"mission_type": "air",
	},
	## ── 机场解放战区（spec airfield-liberation-zones §2.1）──
	## 三座固定机场：敌占战区，打光地面防空＝解放 → 圆心开一次性友军补给点。
	## 开局全部 AVAILABLE；不 roll 奖励/难度/任务类型（难度靠热度首刷定档）。
	## 圆心与旧 _spawn_airfield_docks 三处机场坐标一致（羽田＝HANEDA_AIRPORT 质心烘焙字面量）。
	{
		"id": &"AF_HANEDA",
		"name_key": "DOCK_HANEDA_NAME",
		"label": "✈",
		"center": Vector2(1030.0, -6080.0),      ## HANEDA_AIRPORT 十顶点均值（烘焙）
		"radius": 2000.0,
		"mission_type": "airfield",
		"airfield": true,
		"dock_name_key": "DOCK_HANEDA_NAME",
	},
	{
		"id": &"AF_KISARAZU",
		"name_key": "DOCK_KISARAZU_NAME",
		"label": "✈",
		"center": Vector2(6844.0, 2381.0),
		"radius": 2000.0,
		"mission_type": "airfield",
		"airfield": true,
		"dock_name_key": "DOCK_KISARAZU_NAME",
	},
	{
		"id": &"AF_CHOFU",
		"name_key": "DOCK_CHOFU_NAME",
		"label": "✈",
		"center": Vector2(-10434.0, -12864.0),
		"radius": 2000.0,
		"mission_type": "airfield",
		"airfield": true,
		"dock_name_key": "DOCK_CHOFU_NAME",
	},
]

## 机场战区 id（固定三座；开局全部 AVAILABLE）
const AIRFIELD_IDS: Array[StringName] = [&"AF_HANEDA", &"AF_KISARAZU", &"AF_CHOFU"]

## BOSS 战区：不再固定中央位置，根据玩家最后攻克的战区动态选南北
##   - 最后攻克 ∈ {A, B}（北部） → BOSS 出现在 **南** (E 位置)，朝北飞来迎战
##   - 最后攻克 ∈ {C, D, E}（南部） → BOSS 出现在 **北** (B 位置)，朝西南飞来迎战
## 目的：BOSS 出现在玩家上一个战区的对角侧，避免刷脸 + 给玩家赶赴时间
const BOSS_RADIUS: float = 2200.0
## 北 BOSS：湾内北部水域、桥主体以南（视觉上像"舰队从桥下驶出"）。
## 地理坐标未随扩图移动：桥线性逼近仍是 y = 0.827x - 5616（x=2500 处桥在 y≈-3548），
## center_y = -3000 留 ~550 px 离桥；湾北再往上是东京陆地，CSG 上不了陆，
## 故北锚点不做 ×2 外推（水域形状是硬约束），靠 _snap_to_water 兜底
const BOSS_NORTH_CENTER: Vector2 = Vector2(2500.0, -3000.0)
const BOSS_SOUTH_CENTER: Vector2 = Vector2(0.0, 7000.0)      ## E 战区位置（南，浦贺水道）
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
## 最近一次完成或失败的战区 id —— 当次刷新排除，避免失败地点立即原地重开。
var _last_resolved: StringName = &""
## 移动战区的运行时圆心；静态战区不写入本表，读取时回退 ZONES.center。
var _dynamic_centers: Dictionary = {}
var _dynamic_radii: Dictionary = {}
## 护送等任务的固定目标点、明确航线、状态与移动编队朝向；TacticalMap 只读缓存，不扫描演员。
var _objective_centers: Dictionary = {}
var _dynamic_headings: Dictionary = {}
var _mission_routes: Dictionary = {}
var _mission_status: Dictionary = {}

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

## ── 可选战区任务整局配额 ──
## “可失败”是行为属性；玩家可见类别统一叫 Optional Zone Mission / 可选战区任务。
const OPTIONAL_MISSION_TYPE := "bomber_escort"
const OPTIONAL_MISSION_SECOND_CHANCE := 0.20
const OPTIONAL_MISSION_MAX_PER_RUN := 2
const OPTIONAL_MISSION_CARRIER_IDS: Array[StringName] = [&"C", &"D", &"F", &"G"]
var _optional_mission_run_quota := 1
var _optional_mission_assigned_count := 0
var _optional_mission_resolved_count := 0
var _scheduled_optional_mission_ids: Dictionary = {}

## 各难度下各 mission_type 的基础权重（数值是相对值，会按历史衰减后再归一）
## 与旧 _roll_mission_type 的概率近似一致，便于回归
## elite（Sentinel TGT）任务已移除（spec early-game-uav-rework §2.3）：作为战区目标
## 分量不足；Sentinel 改为普通地图刷新 + 战区驻守障碍（zone_mission._spawn_sentinel_garrison）
const MISSION_TYPE_BASE_WEIGHTS := {
	1: {"ground": 45.0, "squadron": 30.0},   ## ★
	2: {"ground": 35.0, "squadron": 35.0},   ## ★★ 两类均衡
	3: {"ground": 40.0, "squadron": 60.0},   ## ★★★
}
var boss_unlocked: bool = false
## 战区阶段是否已结束（survivor_mode 在 10 分钟到点时置 true）
## 置 true 后 _refresh_availability_after_resolution 不再开新战区，E 解锁路径也屏蔽
var phase_ended: bool = false
## E 战区是否已经尝试过解锁（避免 A+B 清完反复 roll）
var _e_unlock_rolled: bool = false
var _rewards: Dictionary = {}                ## id → reward dict（四类奖励，spec zone-reward-arsenal §2.1）
## 整局奖励去重（用户 2026-07-24 重定：武器/技能/航母**每种整局只出现一次**，出现过即永久移出池）。
## 僚机(reward_wingman)**刻意不入此表** = 可重复出现的保底奖励（与"每次停靠必送僚机"呼应）。
## 记录的是"已出现过的 reward id"（roll 时写入，不因清区/换区而清除）。
var _used_reward_ids: Dictionary = {}
## 航母奖励整局保证（用户 2026-07-24）：确保每局一定出现一次航母奖励。
## pity——第 CARRIER_PITY_ROLLS 次奖励 roll 时航母仍未自然出现 → 当次强制发航母。
var _carrier_reward_assigned: bool = false
var _reward_roll_count: int = 0
const CARRIER_PITY_ROLLS: int = 4
## 每局类别保底：首批 A/B 随机各占一槽，开放后可看到一件武器 + 一项次世代技能。
## 这里只保证“至少一件”，后续战区仍按 REWARD_KIND_WEIGHTS 正常抽取。
const RUN_GUARANTEED_REWARD_KINDS: Array[String] = ["weapon", "nextgen"]
var _guaranteed_reward_kinds: Array[String] = []
var _difficulties: Dictionary = {}            ## id → int (DIFFICULTY_MIN..DIFFICULTY_MAX)
var _mission_types: Dictionary = {}            ## id → String（运行时 mission_type，覆盖 ZONES 默认）
## 当前地图的战区定义副本。默认与海岸线 ZONES 完全一致；其它正式地图只覆盖地理字段，
## 保留稳定 id 与通用机场解放生命周期，避免把海岸线地名/坐标泄漏到别的地图。
var _zone_definitions: Array[Dictionary] = []
## 标记哪些战区是"新开放"的（最近一轮 refresh 打开的），便于 UI 再次提示玩家
var _newly_opened: Array[StringName] = []
const INITIAL_REWARD_UNLOCK_TIME_S := 60.0
const INITIAL_REWARD_UNLOCK_LEVEL := 3
const OPTIONAL_MISSION_UNLOCK_TIME_S := 150.0
const OPTIONAL_MISSION_UNLOCK_LEVEL := 5
var _initial_reward_zones_released := false

func _init(reward_context: Callable = Callable(), schedule_optional_missions: bool = true,
		defer_initial_zones: bool = false) -> void:
	for zone in ZONES:
		_zone_definitions.append(zone.duplicate(true))
	nextgen_context = reward_context
	_guaranteed_reward_kinds.assign(RUN_GUARANTEED_REWARD_KINDS)
	_guaranteed_reward_kinds.shuffle()  # A/B 每局换位，避免固定“一区必武器、二区必技能”
	_optional_mission_run_quota = optional_mission_quota_for_roll(randf()) \
		if schedule_optional_missions else 0
	# 正式局延迟开放 A/B；测试/Debug 默认仍可使用即时构造契约。
	_states[&"A"] = State.LOCKED
	_states[&"B"] = State.LOCKED
	_states[&"C"] = State.LOCKED
	_states[&"D"] = State.LOCKED
	_states[&"E"] = State.LOCKED
	_states[&"F"] = State.LOCKED
	_states[&"G"] = State.LOCKED
	_states[&"BOSS"] = State.LOCKED
	if not defer_initial_zones:
		release_initial_reward_zones()
		if schedule_optional_missions:
			release_first_optional_mission()
	# 机场解放战区（spec airfield-liberation-zones）：开局全部 AVAILABLE，
	# 不 roll 奖励/难度/任务类型（难度由 ZoneMission 首刷时按当前热度定档）
	for af in AIRFIELD_IDS:
		_states[af] = State.AVAILABLE

static func initial_reward_unlock_ready(elapsed_s: float, level: int) -> bool:
	return elapsed_s >= INITIAL_REWARD_UNLOCK_TIME_S and level >= INITIAL_REWARD_UNLOCK_LEVEL

static func optional_mission_unlock_ready(elapsed_s: float, level: int) -> bool:
	return elapsed_s >= OPTIONAL_MISSION_UNLOCK_TIME_S and level >= OPTIONAL_MISSION_UNLOCK_LEVEL

func initial_reward_zones_released() -> bool:
	return _initial_reward_zones_released

## 首批 A/B 的唯一开放入口；把奖励 roll 延迟到真正出现时，避免开局提前消耗 pity。
func release_initial_reward_zones() -> bool:
	if _initial_reward_zones_released or phase_ended:
		return false
	_initial_reward_zones_released = true
	for zid in [&"A", &"B"]:
		_states[zid] = State.AVAILABLE
		_roll_difficulty(zid, 2)
		_assign_reward(zid)
		_roll_mission_type(zid)
		if not _newly_opened.has(zid):
			_newly_opened.append(zid)
	return true

## 正式局首个 optional 的唯一开放入口；第二个仍由首次结算后的刷新逻辑管理。
func release_first_optional_mission() -> StringName:
	if phase_ended or not _initial_reward_zones_released \
			or _optional_mission_run_quota <= 0 or _optional_mission_assigned_count > 0:
		return &""
	var candidates: Array[StringName] = []
	for zid in OPTIONAL_MISSION_CARRIER_IDS:
		if get_state(zid) == State.LOCKED:
			candidates.append(zid)
	if candidates.is_empty():
		return &""
	var picked: StringName = candidates[randi() % candidates.size()]
	_open_optional_mission(picked, 2)
	if not _newly_opened.has(picked):
		_newly_opened.append(picked)
	EventLogger.log_event("ZONE", "OptionalOpened",
		"id=%s assigned=%d quota=%d initial=true" % [picked,
		_optional_mission_assigned_count, _optional_mission_run_quota])
	return picked

## BOSS 阶段：玩家已选中 BOSS（在战术地图点了 BOSS 圈）。
## 进入此阶段后：常规战区 A/B/C/D 的地图显示 + 任务推进全部停止，专心打 BOSS。
func is_boss_phase() -> bool:
	return selected_id == &"BOSS"

func get_state(id: StringName) -> State:
	return _states.get(id, State.LOCKED)

func set_state(id: StringName, state: State) -> void:
	_states[id] = state

## 是否机场解放战区（spec airfield-liberation-zones）
func is_airfield(id: StringName) -> bool:
	return AIRFIELD_IDS.has(id)

## 机场战区难度定档（ZoneMission 首刷时按当前热度写入；不走 _roll_difficulty 随机）
func set_airfield_difficulty(id: StringName, star: int) -> void:
	var desired := clampi(star, DIFFICULTY_MIN, DIFFICULTY_MAX)
	if desired == DIFFICULTY_MAX and not _tier3_allowed_for(id):
		desired = DIFFICULTY_MAX - 1
	_difficulties[id] = desired

## 解放机场（spec airfield-liberation-zones §3.1）：独立于普通战区 mark_cleared 的
## churn（不改 _last_cleared / 不进重开池 / 不 erase 奖励 / 不触发 _refresh_availability）。
## 机场一次性、彼此独立，只把状态置 CLEARED + 记 _ever_cleared。
func liberate_airfield(id: StringName) -> void:
	if not is_airfield(id):
		return
	_states[id] = State.CLEARED
	_ever_cleared[id] = true
	if selected_id == id:
		selected_id = &""
	EventLogger.log_event("ZONE", "AirfieldLiberated", "id=%s" % id)

## 查找战区数据（不含 Boss）
func get_zone_by_id(id: StringName) -> Dictionary:
	for z in _zone_definitions:
		if z["id"] == id:
			return z
	if boss_zone["id"] == id:
		return boss_zone
	return {}

## 将 MapDocument.zones 中与稳定 id 匹配的条目覆盖到当前局副本。
## 只改变本局实例，不污染海岸线常量，也不改变存档/统计使用的 AF_* id。
func apply_map_zone_overrides(overrides: Array) -> void:
	for raw_override in overrides:
		if not raw_override is Dictionary:
			continue
		var override: Dictionary = raw_override
		var id := StringName(String(override.get("id", "")))
		if id == &"":
			continue
		for index in range(_zone_definitions.size()):
			if _zone_definitions[index].get("id", &"") != id:
				continue
			var resolved: Dictionary = _zone_definitions[index].duplicate(true)
			for key in override:
				resolved[key] = override[key]
			var center_data = resolved.get("center", Vector2.INF)
			if center_data is Array and center_data.size() >= 2:
				resolved["center"] = Vector2(float(center_data[0]), float(center_data[1]))
			if resolved.get("center", Vector2.INF) is Vector2 \
					and (resolved["center"] as Vector2).is_finite():
				_zone_definitions[index] = resolved
			break

func get_zone_definitions() -> Array[Dictionary]:
	return _zone_definitions

## 战区运行时圆心。护送等移动任务由任务控制器持续写入；无覆盖时返回静态圆心。
func get_zone_center(id: StringName) -> Vector2:
	if _dynamic_centers.has(id):
		return _dynamic_centers[id]
	var zone := get_zone_by_id(id)
	return zone.get("center", Vector2.INF) if not zone.is_empty() else Vector2.INF

func get_zone_radius(id: StringName) -> float:
	if _dynamic_radii.has(id):
		return float(_dynamic_radii[id])
	var zone := get_zone_by_id(id)
	return float(zone.get("radius", 0.0)) if not zone.is_empty() else 0.0

## 固定任务目标点。未设置时回退静态战区中心。
func get_objective_center(id: StringName) -> Vector2:
	if _objective_centers.has(id):
		return _objective_centers[id]
	var zone := get_zone_by_id(id)
	return zone.get("center", Vector2.INF) if not zone.is_empty() else Vector2.INF

func set_objective_center(id: StringName, center: Vector2) -> void:
	if center.is_finite() and not get_zone_by_id(id).is_empty():
		_objective_centers[id] = center

func set_mission_route(id: StringName, route: PackedVector2Array) -> void:
	if route.size() >= 2 and not get_zone_by_id(id).is_empty():
		_mission_routes[id] = route.duplicate()

func get_mission_route(id: StringName) -> PackedVector2Array:
	var route: PackedVector2Array = _mission_routes.get(id, PackedVector2Array())
	return route.duplicate()

func set_mission_status(id: StringName, status: Dictionary) -> void:
	if not get_zone_by_id(id).is_empty():
		_mission_status[id] = status.duplicate(true)

func get_mission_status(id: StringName) -> Dictionary:
	var status: Dictionary = _mission_status.get(id, {})
	return status.duplicate(true)

func has_dynamic_center(id: StringName) -> bool:
	return _dynamic_centers.has(id)

func get_dynamic_heading(id: StringName) -> float:
	return float(_dynamic_headings.get(id, 0.0))

func set_dynamic_center(id: StringName, center: Vector2, radius: float = -1.0,
		heading: float = INF) -> void:
	if center.is_finite() and not get_zone_by_id(id).is_empty():
		_dynamic_centers[id] = center
		if radius > 0.0:
			_dynamic_radii[id] = radius
		if is_finite(heading):
			_dynamic_headings[id] = heading

## 清除本轮任务的全部运行时几何；失败后不能留下目标或编队标记。
func clear_dynamic_center(id: StringName) -> void:
	_dynamic_centers.erase(id)
	_dynamic_radii.erase(id)
	_dynamic_headings.erase(id)
	_objective_centers.erase(id)
	_mission_routes.erase(id)
	_mission_status.erase(id)

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
	_resolve_scheduled_optional_mission(id)
	set_state(id, State.CLEARED)
	cleared_count += 1
	_ever_cleared[id] = true
	_last_cleared = id
	_last_resolved = id
	_last_cleared_mission_type = get_mission_type(id)
	if selected_id == id:
		selected_id = &""
	# 清除该战区的奖励/难度缓存，下次再开启时会 roll 新的
	_rewards.erase(id)
	_difficulties.erase(id)
	_mission_types.erase(id)
	clear_dynamic_center(id)
	_refresh_availability_after_resolution()

## 任务失败：不计攻克、不发奖励、不改热度；当前战区从战术地图消失并补开新战区。
func mark_failed(id: StringName, reason: String = "") -> void:
	if get_state(id) == State.FAILED:
		return
	_resolve_scheduled_optional_mission(id)
	set_state(id, State.FAILED)
	_last_resolved = id
	if selected_id == id:
		selected_id = &""
	_rewards.erase(id)
	_difficulties.erase(id)
	_mission_types.erase(id)
	_newly_opened.erase(id)
	clear_dynamic_center(id)
	EventLogger.log_event("ZONE", "Failed", "id=%s reason=%s" % [id, reason])
	_refresh_availability_after_resolution()

## 依据 `_last_cleared` 决定 BOSS 出现在南还是北
## 并把同位置的常规战区（E 或 B）压回 LOCKED，避免 UI 重叠
## 选定位置后若在陆地上则向海面吸附 —— 舰队 BOSS（CSG）才能刷进池子
## public：survivor_mode 在 10 分钟到点（或 SELECTED 战区结算后）调用
func finalize_boss_placement() -> void:
	_finalize_boss_placement()

## 把所有 AVAILABLE 状态的战区压回 LOCKED，except_id 保留不动（玩家正在打的）
## 用途：10 分钟战区阶段结束时调用，让 BOSS 阶段视野干净
func lock_all_open_zones_except(except_id: StringName) -> void:
	for z in _zone_definitions:
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

func _refresh_availability_after_resolution() -> void:
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
				_roll_difficulty(&"E")
				_assign_reward(&"E")
				_roll_mission_type(&"E")
				_newly_opened.append(&"E")
				_try_open_followup_optional_mission()
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
	for z in _zone_definitions:
		var zid: StringName = z["id"]
		if zid == _last_resolved:
			continue
		# 机场解放战区一次性、独立，不进随机战区重开池（spec airfield-liberation-zones §3.1）
		if is_airfield(zid):
			continue
		var st := get_state(zid)
		if st == State.AVAILABLE or st == State.SELECTED:
			continue
		pool.append(zid)
		# CLEARED 1.5× 权重（再激活），LOCKED 1.0× 权重（新开）
		weights.append(1.5 if st == State.CLEARED else 1.0)
	if pool.is_empty():
		_try_open_followup_optional_mission()
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
		_roll_difficulty(open_id)
		_assign_reward(open_id)
		_roll_mission_type(open_id)
		_newly_opened.append(open_id)
		EventLogger.log_event("ZONE", "Reactivated" if was_cleared else "Opened",
			"id=%s mt=%s diff=%d" % [open_id, get_mission_type(open_id), get_difficulty(open_id)])
	_try_open_followup_optional_mission()

## 可选任务配额是整局一次性骰：80% 一次、20% 两次，永远不按刷新次数累积概率。
static func optional_mission_quota_for_roll(roll: float) -> int:
	return OPTIONAL_MISSION_MAX_PER_RUN if roll < OPTIONAL_MISSION_SECOND_CHANCE else 1

static func is_optional_mission_type(mission_type: String) -> bool:
	return mission_type == OPTIONAL_MISSION_TYPE

func get_optional_mission_run_quota() -> int:
	return _optional_mission_run_quota

func get_optional_mission_assigned_count() -> int:
	return _optional_mission_assigned_count

## 用普通 zone id 只承载生命周期，实际地理仍由 bomber_escort 独立航线目录决定。
func _open_optional_mission(id: StringName, max_difficulty: int = DIFFICULTY_MAX) -> void:
	_states[id] = State.AVAILABLE
	_rewards.erase(id)
	_difficulties.erase(id)
	_mission_types.erase(id)
	_roll_difficulty(id, max_difficulty)
	_set_mission_type_and_record(id, OPTIONAL_MISSION_TYPE)
	_scheduled_optional_mission_ids[id] = true
	_optional_mission_assigned_count += 1

func _resolve_scheduled_optional_mission(id: StringName) -> void:
	if not _scheduled_optional_mission_ids.has(id):
		return
	_scheduled_optional_mission_ids.erase(id)
	_optional_mission_resolved_count += 1

## 第二次任务必须等第一次正式结算后才追加；Debug 强制类型不进入这本账。
func _try_open_followup_optional_mission() -> void:
	if _optional_mission_assigned_count >= _optional_mission_run_quota \
			or _optional_mission_resolved_count < _optional_mission_assigned_count:
		return
	var candidates: Array[StringName] = []
	for zid in OPTIONAL_MISSION_CARRIER_IDS:
		if zid == _last_resolved:
			continue
		var state := get_state(zid)
		if state != State.AVAILABLE and state != State.SELECTED:
			candidates.append(zid)
	if candidates.is_empty():
		return
	var picked: StringName = candidates[randi() % candidates.size()]
	_open_optional_mission(picked)
	if not _newly_opened.has(picked):
		_newly_opened.append(picked)
	EventLogger.log_event("ZONE", "OptionalOpened",
		"id=%s assigned=%d quota=%d" % [picked, _optional_mission_assigned_count,
		_optional_mission_run_quota])

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
	return get_zone_center(selected_id)

# ══════════════════════════════════════════════
#  奖励系统
# ══════════════════════════════════════════════

## 战区奖励池（spec zone-reward-arsenal §2.1）：四类奖励按难度加权 roll。
## 奖励 dict：{ kind: "carrier"|"wingman"|"weapon"|"nextgen", id, name(tr key), quality(=难度星), weapon?(仅 weapon 类) }
## nextgen = 次世代技术（spec zone-reward-arsenal §2.1）：NEXT_GEN 稀有度技能只经战区奖励发放
const REWARD_KIND_WEIGHTS := {
	1: {"weapon": 60.0, "wingman": 25.0, "carrier": 0.0, "nextgen": 30.0},
	2: {"weapon": 35.0, "wingman": 30.0, "carrier": 20.0, "nextgen": 30.0},
	3: {"weapon": 15.0, "wingman": 25.0, "carrier": 45.0, "nextgen": 40.0},
}
## 追加武器子池：低星偏尾雷、高星偏忠诚僚机/QMAAM（"难度越高奖励越好"）。
## 2026-07-22 军械库扩容（spec zone-reward-arsenal §2.2）：+火箭弹/电磁炮/激光
## （equipment 泛化，全机型可挂；电磁炮/激光属高价值件，★ 区不出）
const REWARD_WEAPON_WEIGHTS := {
	1: {"tail_mine": 20.0, "loyal_wingman": 20.0, "qmaam": 25.0, "rocket": 20.0, "railgun": 10.0, "laser": 10.0, "esm_pod": 10.0},
	2: {"tail_mine": 20.0, "loyal_wingman": 30.0, "qmaam": 25.0, "rocket": 20.0, "railgun": 15.0, "laser": 15.0, "esm_pod": 15.0},
	3: {"tail_mine": 10.0, "loyal_wingman": 25.0, "qmaam": 20.0, "rocket": 15.0, "railgun": 20.0, "laser": 20.0, "esm_pod": 30.0},
}
const REWARD_WEAPON_NAME_KEYS := {
	"tail_mine": "REWARD_WEAPON_TAILMINE_NAME",
	"loyal_wingman": "REWARD_WEAPON_LOYAL_NAME",
	"qmaam": "REWARD_WEAPON_QMAAM_NAME",
	"rocket": "REWARD_WEAPON_ROCKET_NAME",
	"railgun": "REWARD_WEAPON_RAILGUN_NAME",
	"laser": "REWARD_WEAPON_LASER_NAME",
	"esm_pod": "REWARD_WEAPON_ESM_NAME",
}
## 奖励说明文案 key（Tab 战术地图信息面板在奖励名下方多显示一行"它到底是什么"）。
## 实体奖励（航母/僚机/武器件）各配一条 REWARD_*_DESC；技能类直接沿用升级表自己的 desc。
const REWARD_WEAPON_DESC_KEYS := {
	"tail_mine": "REWARD_WEAPON_TAILMINE_DESC",
	"loyal_wingman": "REWARD_WEAPON_LOYAL_DESC",
	"qmaam": "REWARD_WEAPON_QMAAM_DESC",
	"rocket": "REWARD_WEAPON_ROCKET_DESC",
	"railgun": "REWARD_WEAPON_RAILGUN_DESC",
	"laser": "REWARD_WEAPON_LASER_DESC",
	"esm_pod": "REWARD_WEAPON_ESM_DESC",
}
## 航母登舰全局余量（spec §2.4：全程限 2 次；survivor_mode 登舰时扣减；归零后 carrier 不再进池）
var carrier_uses_left: int = 2

## 战区奖励 roll 的玩家上下文提供器（spec zone-reward-arsenal §3.1，survivor_mode 注入）。
## 返回 {aircraft_id, params, stacks, squad_classes} 快照，用于 nextgen 候选过滤与
## "已持有武器件"过滤。未注入时跳过机型/stacks 过滤，但成就型奖励一律 fail-closed。
var nextgen_context: Callable = Callable()

## 次世代技术候选（spec zone-reward-arsenal §2.3/§3.1）：NEXT_GEN 稀有度 + 跨活跃区去重
## + stacks 未满 + 机型/品类可用（后两项需上下文）。
func _nextgen_candidates(used: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	for u in SurvivorData.UPGRADES:
		if int(u.get("rarity", -1)) != SurvivorData.Rarity.NEXT_GEN:
			continue
		if not SurvivorData.is_normal_random_candidate(u, true):
			continue  # 专属技只走机场留机选择，禁止其它奖励池旁路
		if MetaShop.is_upgrade_gated(u):
			continue  # Doctrine 门控（spec doctrine-unlocks §3.3：战区奖励池同样不发无证牌）
		var uid := String(u["id"])
		if used.has(uid):
			continue
		if not ctx.is_empty():
			var stacks: Dictionary = ctx.get("stacks", {})
			if int(stacks.get(uid, 0)) >= int(u.get("max_stacks", 1)):
				continue
			if not SurvivorData.is_upgrade_available_for(u, StringName(str(ctx.get("aircraft_id", ""))),
					ctx.get("params", null) as AircraftParams, stacks, ctx.get("squad_classes", [])):
				continue
		out.append(u)
	return out

## 玩家是否已持有某武器件（roll 侧过滤；rocket 走 legacy 字段、railgun/laser 走 equipment）
static func _ctx_owns_weapon(p: AircraftParams, w: String) -> bool:
	if p == null:
		return false
	match w:
		"rocket": return p.rocket != null
		"railgun", "laser", "esm_pod": return p.get_equipment_of_kind(w) != null
		_: return false

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

## 收集当前活跃战区（AVAILABLE/SELECTED，排除 exclude_id）已占用的奖励 id 集合。
## 用于同时开放的战区之间奖励去重（spec zone-reward-docking：不给两个战区同样的奖励，
## 尤其航母）。CLEARED 战区的 reward 已在 mark_cleared 时 erase → 不算占用。
func _active_reward_ids(exclude_id: StringName) -> Dictionary:
	var used: Dictionary = {}
	for z in _zone_definitions:
		var zid: StringName = z["id"]
		if zid == exclude_id:
			continue
		var st := get_state(zid)
		if (st == State.AVAILABLE or st == State.SELECTED) and _rewards.has(zid):
			var rid := String((_rewards[zid] as Dictionary).get("id", ""))
			if rid != "":
				used[rid] = true
	return used

## 给战区 roll 四类奖励（spec zone-reward-arsenal §3.1；如已分配则保留）
## 前置：应先 _roll_difficulty（权重按星级）。去重两层（用户 2026-07-24 重定）：
## ① 整局去重 `_used_reward_ids`——武器/技能/航母每种整局只出现一次（僚机豁免=可重复保底）；
## ② 同时活跃战区去重 `_active_reward_ids`——避免两个在开战区同时挂同一奖励。
## 开局 A/B 类别保证：随机各出 1 个 weapon / nextgen；后续恢复权重随机。
## 航母整局保证：pity（_reward_roll_count ≥ CARRIER_PITY_ROLLS 仍未出航母 → 强制发）。
func _assign_reward(id: StringName) -> void:
	if _rewards.has(id):
		return
	if is_optional_mission_type(get_mission_type(id)):
		# 特殊护送任务只发经验，不能占用普通奖励池、保底槽或航母 pity 次数。
		return
	_roll_difficulty(id)
	var diff: int = get_difficulty(id)
	_reward_roll_count += 1
	# 去重集合 = 同时活跃战区已占 ∪ 整局已出现过（后者只含武器/技能/航母，僚机不入表）
	var used := _active_reward_ids(id)
	for rid in _used_reward_ids:
		used[rid] = true
	var ctx: Dictionary = nextgen_context.call() if nextgen_context.is_valid() else {}
	var own_p: AircraftParams = ctx.get("params", null)

	# 航母整局保证（用户 2026-07-24）：前 N 次 roll 内仍未自然出航母 → 本次强制发
	var force_carrier := (not _carrier_reward_assigned) and carrier_uses_left > 0 \
			and _reward_roll_count >= CARRIER_PITY_ROLLS

	# kind 权重 + 去重门控（航母还受全局登舰余量门 + 整局唯一）
	var kind_w: Dictionary = (REWARD_KIND_WEIGHTS.get(diff, REWARD_KIND_WEIGHTS[1]) as Dictionary).duplicate()
	if carrier_uses_left <= 0 or used.has("reward_carrier"):
		kind_w["carrier"] = 0.0
	if used.has("reward_wingman"):  # 僚机仅活跃战区去重（不入 _used_reward_ids → 整局可重复）
		kind_w["wingman"] = 0.0
	# 武器子类可用性：逐个避开已出现过的子类（整局唯一）+ 已持有同类件（签名机自带，
	# spec zone-reward-arsenal §2.2）；全部被占则整个 weapon 类不可选
	var weap_w: Dictionary = (REWARD_WEAPON_WEIGHTS.get(diff, REWARD_WEAPON_WEIGHTS[1]) as Dictionary).duplicate()
	var weap_any := false
	for w0 in weap_w.keys():
		if used.has("reward_weapon_%s" % String(w0)):
			weap_w[w0] = 0.0
		elif _ctx_owns_weapon(own_p, String(w0)):
			weap_w[w0] = 0.0
		elif String(w0) == "loyal_wingman" and not bool(ctx.get("loyal_wingman_unlocked", false)):
			# 成就门控（spec career-archive §3.3）：无人机猎手未解锁 → 忠诚僚机不进 roll。
			# 缺键 fail-closed：解锁型奖励宁可少发，不能因调用方漏注入而提前泄漏。
			weap_w[w0] = 0.0
		elif float(weap_w[w0]) > 0.0:
			weap_any = true
	# 起始机型只影响武器子池，相关武器权重 ×2；换机/进化不改本局倾向。
	var start_id := String(ctx.get("start_aircraft_id", ""))
	var favored_weapon := String({"f15": "qmaam", "a6e": "rocket", "f14": "railgun", "mirage3": "laser"}.get(start_id, ""))
	if favored_weapon != "" and float(weap_w.get(favored_weapon, 0.0)) > 0.0:
		weap_w[favored_weapon] = float(weap_w[favored_weapon]) * 2.0
	if not weap_any:
		kind_w["weapon"] = 0.0
	# 次世代技术候选（spec zone-reward-arsenal §3.2 降级链）：候选空 → 类权重清零
	var ng_pool := _nextgen_candidates(used, ctx)
	if ng_pool.is_empty():
		kind_w["nextgen"] = 0.0
	# 每局类别保底只在候选有效时消费；正常新局会由 A/B 两次首 roll 恰好清空队列。
	# 若 debug/特殊上下文暂时没有可用候选，则保留到后续战区重试，绝不发空奖励。
	var guaranteed_kind := ""
	if not _guaranteed_reward_kinds.is_empty():
		var scheduled_kind: String = _guaranteed_reward_kinds[0]
		if float(kind_w.get(scheduled_kind, 0.0)) > 0.0:
			guaranteed_kind = scheduled_kind

	var kind: String
	if force_carrier:
		kind = "carrier"
	elif guaranteed_kind != "":
		kind = guaranteed_kind
		_guaranteed_reward_kinds.pop_front()
	else:
		kind = _weighted_pick_str(kind_w)
		# 兜底：武器/技能/航母都用尽或被占 → 回退僚机（可重复保底，不再回退重复武器）
		if kind == "":
			kind = "wingman"

	var reward: Dictionary = {"kind": kind, "quality": diff}
	match kind:
		"carrier":
			reward["id"] = "reward_carrier"
			reward["name"] = "REWARD_CARRIER_NAME"
		"wingman":
			reward["id"] = "reward_wingman"
			reward["name"] = "REWARD_WINGMAN_NAME"
		"nextgen":
			# 次世代技术：奖励 id = 技能 id（整局去重自动生效），领取走升级分发链
			var pick: Dictionary = ng_pool[randi() % ng_pool.size()]
			reward["id"] = String(pick["id"])
			reward["name"] = String(pick["name"])
		_:
			var w := _weighted_pick_str(weap_w)
			if w == "":
				w = "tail_mine"
			reward["id"] = "reward_weapon_%s" % w
			reward["weapon"] = w
			reward["name"] = String(REWARD_WEAPON_NAME_KEYS.get(w, "REWARD_WEAPON_TAILMINE_NAME"))
	_rewards[id] = reward
	# 整局去重登记（僚机豁免=可重复保底）；航母整局保证标记
	if kind != "wingman":
		_used_reward_ids[String(reward["id"])] = true
	if kind == "carrier":
		_carrier_reward_assigned = true

## 通用字符串键权重抽取（返回 "" = 全零权重）
func _weighted_pick_str(weights: Dictionary) -> String:
	var total := 0.0
	for k in weights:
		total += maxf(0.0, float(weights[k]))
	if total <= 0.0:
		return ""
	var rr := randf() * total
	var acc := 0.0
	for k in weights:
		acc += maxf(0.0, float(weights[k]))
		if rr <= acc:
			return String(k)
	return ""

## 获取某战区的奖励 upgrade dict（可能为空）
func get_reward(id: StringName) -> Dictionary:
	return _rewards.get(id, {})

## 轰炸机护送成功的唯一奖励。固定按任务星级结算，失败路径不会调用。
static func bomber_escort_xp_reward(difficulty: int) -> int:
	return BOMBER_ESCORT_XP_PER_STAR * clampi(difficulty, DIFFICULTY_MIN, DIFFICULTY_MAX)

## 奖励说明文案的 tr key（空串 = 无说明）。四类来源：
## ① reward 自带 desc（ZoneRewardRegistry 注册的 upgrade dict）→ 直接用；
## ② 实体奖励（carrier/wingman/weapon）→ 查 REWARD_*_DESC 常量；
## ③ nextgen 技能 → 按 id 回查升级表的 desc（技能介绍与选卡完全一致）；
## ④ 兜底：id 能在升级表里查到就用它的 desc。
static func reward_desc_key(reward: Dictionary) -> String:
	if reward.is_empty():
		return ""
	var own := String(reward.get("desc", ""))
	if own != "":
		return own
	match String(reward.get("kind", "")):
		"carrier":
			return "REWARD_CARRIER_DESC"
		"wingman":
			return "REWARD_WINGMAN_DESC"
		"weapon":
			return String(REWARD_WEAPON_DESC_KEYS.get(String(reward.get("weapon", "")), ""))
	var uid := String(reward.get("id", ""))
	if uid == "":
		return ""
	var up: Dictionary = SurvivorData.upgrade_by_id(uid)
	return String(up.get("desc", "")) if not up.is_empty() else ""

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
	if hi == DIFFICULTY_MAX and not _tier3_allowed_for(id):
		hi = DIFFICULTY_MAX - 1
	_difficulties[id] = DIFFICULTY_MIN + randi() % (hi - DIFFICULTY_MIN + 1)

func get_difficulty(id: StringName) -> int:
	return int(_difficulties.get(id, DIFFICULTY_MIN))

## 当前仍占三级单槽的正式战区。只统计玩家可见/可选/执行中的 AVAILABLE/SELECTED；
## 已清除、失败、锁定或尚未写难度的战区都不占名额。
func active_tier3_zone_ids(except_id: StringName = &"") -> Array[StringName]:
	var out: Array[StringName] = []
	for zid_value in _states.keys():
		var zid := StringName(zid_value)
		if zid == except_id:
			continue
		var state: int = int(_states[zid])
		if state != State.AVAILABLE and state != State.SELECTED:
			continue
		if int(_difficulties.get(zid, DIFFICULTY_MIN)) == DIFFICULTY_MAX:
			out.append(zid)
	return out

func has_active_tier3(except_id: StringName = &"") -> bool:
	return not active_tier3_zone_ids(except_id).is_empty()

func _tier3_allowed_for(id: StringName) -> bool:
	return active_tier3_zone_ids(id).size() < MAX_CONCURRENT_TIER3_ZONES

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
	if is_optional_mission_type(mission_type):
		_rewards.erase(id)
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
	if is_optional_mission_type(mission_type):
		_rewards.erase(id)

# ══════════════════════════════════════════════
#  Debug 辅助（F6 面板用）
# ══════════════════════════════════════════════

## Debug：强制把任意状态的战区改为 AVAILABLE，并 roll 好奖励/难度/任务类型
## 若已经是 AVAILABLE/SELECTED 且已有 reward+difficulty，不会覆盖
func debug_set_available(id: StringName) -> void:
	_states[id] = State.AVAILABLE
	if not _difficulties.has(id):
		_roll_difficulty(id)
	if not _rewards.has(id):
		_assign_reward(id)
	if not _mission_types.has(id):
		_roll_mission_type(id)

## Debug：指定战区使用指定 mission_type（不 roll 随机，直接覆写）
## 与 set_mission_type 相同但命名更明确
func debug_set_mission_type(id: StringName, new_type: String) -> void:
	set_mission_type(id, new_type)
	if not is_optional_mission_type(new_type) and not _rewards.has(id) \
			and get_state(id) in [State.AVAILABLE, State.SELECTED]:
		# 从护送任务切回普通任务时恢复 F6 的“可直接验收完整战区”语义。
		_assign_reward(id)

## Debug 仍服从正式单槽；测试若要覆盖保护性多源场，必须显式传 allow_multiple_tier3。
func debug_set_difficulty(id: StringName, star: int,
		allow_multiple_tier3: bool = false) -> void:
	var desired := clampi(star, DIFFICULTY_MIN, DIFFICULTY_MAX)
	if desired == DIFFICULTY_MAX and not allow_multiple_tier3 and not _tier3_allowed_for(id):
		desired = DIFFICULTY_MAX - 1
	_difficulties[id] = desired

## F6 强制验收 3★内容：保持正式唯一槽，但把槽位转移给用户指定战区。
## 返回被降为 2★的旧占用者，调用方须在生成新来源前先重刷这些战区。
func debug_claim_tier3_slot(id: StringName) -> Array[StringName]:
	var displaced := active_tier3_zone_ids(id)
	for old_id in displaced:
		_difficulties[old_id] = DIFFICULTY_MAX - 1
	_difficulties[id] = DIFFICULTY_MAX
	return displaced

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
	## 与 zone_mission 实际刷怪一致：全图 OSM 陆地减视觉水面，并要求 50px 连续陆地。
	## 手画 LAND 轮廓包含港池且只覆盖旧 30km 范围，不能再作为正式部署依据。
	if MapGeography.is_ground_spawn_safe(center):
		land_hits += 1
	for i in range(LAND_SAMPLE_COUNT):
		var a := TAU * float(i) / float(LAND_SAMPLE_COUNT)
		## 用黄金比例差步进半径，避免所有采样都落在同一圆环
		var t := fposmod(float(i) * 0.618033, 1.0)
		var r := sqrt(t) * radius
		var p := center + Vector2(cos(a), sin(a)) * r
		if MapGeography.is_ground_spawn_safe(p):
			land_hits += 1
	var frac := float(land_hits) / float(LAND_SAMPLE_COUNT + 1)
	return frac >= LAND_FRACTION_THRESHOLD
