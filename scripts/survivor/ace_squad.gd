## 王牌中队（Ace Squad）BOSS 基类
##
## ── 架构 ──
## 纯**小队级状态机**，不每帧覆盖 AI 内部字段。每个状态：
##   - enter() 一次性配置（设 ENGAGE 状态 / 写 directive / 切视觉）
##   - update() 软维护（每 ~0.5s 检查一次，不重置 timer）
##   - exit() 撤销该状态特有效果
##
## 状态：
##   INTRO        经典通场进场（4s）→ PURSUIT
##   PURSUIT      默认战斗：每架走自己 BFM；不干预战术决策树
##   CLOAK        隐形 5.5s（仅切视觉 + suppress flares，不改 AI）→ PURSUIT
##
## ⚠ 曾有第四个状态 ANCHOR_HOLD（玩家飞远 → 回锚点绕圈等）。2026-07-22 按
##    spec boss-hunter-doctrine 删除：王牌中队是猎手，没有归巢、没有 leash，
##    玩家跑到天涯海角它也追。PURSUIT 现在是唯一的战斗常态。
##
## ── 角色（AceRole）──
## 在 spawn 时**静态分配**，运行时不变（spec bosses/wraith-squadron §2.1）：
##   - 前 2 架（队长 + 第一僚机）= KNIGHT（机炮 + 高度激进近距参数）
##   - 后 2 架 = SNIPER（导弹 + BVR 站位，被压进 4km 就拉开）
##
## ── 与事件系统的关系 ──
## - PRE_STAGE(INBOUND) 阶段：BossEncounterEvent 通过 AIDirective.PURSUE_UNIT 驱动追击玩家
## - ENGAGED 触发：事件 clear_all_directives() + AceSquad.engage() → 进 PURSUIT 状态

class_name AceSquad
extends BossEncounter

const SENSOR_STEALTH_CONTROLLER := preload(
	"res://scripts/survivor/sensor_stealth_controller.gd")

# ══════════════════════════════════════════════
#  状态机
# ══════════════════════════════════════════════

enum SquadState { INTRO, PURSUIT, CLOAK }
## 王牌中队角色（spec bosses/wraith-squadron §2.1）。spawn 时静态分配，运行时不变。
##   KNIGHT（骑士）—— 机炮近战，逼玩家进入转弯
##   SNIPER（狙击手）—— 导弹远距，惩罚玩家的每一次承诺
## 取代此前的两个死 meta：combat_specialty（只写不读）与 f47_role（只读不写）
enum AceRole { NONE, KNIGHT, SNIPER }

## 角色 meta 键。值 = AceRole 枚举。这是**唯一**的角色真源，HUD 与 AI 都读它
const ROLE_META := &"ace_role"

# ══════════════════════════════════════════════
#  配置（子类在 _init 中覆盖）
# ══════════════════════════════════════════════

var squad_size: int = 4
var intro_duration: float = 4.0
var intro_pass_dist: float = 800.0
var enemy_type: int = 15

## 隐形
var cloak_enabled: bool = false
var cloak_cycle: float = 60.0       ## 基础 CD（秒）
var cloak_duration: float = 5.5
var cloak_fade: float = 0.5
var cloak_cycle_jitter: float = 20.0
var cloak_emergency_enabled: bool = true
const CLOAK_EMERGENCY_MIN_ELAPSED: float = 10.0  ## 非 Wraith 子类的既有紧急隐形最早触发间隔

## 距离
var standoff_radius_min: float = 1800.0
var standoff_radius_max: float = 2500.0
var ranged_max_distance: float = 3500.0
var force_pursuit_distance: float = 2500.0  ## 距玩家 > 此值时开加力（PURSUIT 软维护检查）

## PURSUIT 软维护节流：每 N 秒一次"成员是否还在 ENGAGE"检查
const PURSUIT_MAINTAIN_INTERVAL := 0.5

## 世界边缘收容（boss-hunter-doctrine §2.4.1）。这是世界外框硬约束，不是已删除的锚点 leash。
const BOUNDARY_TRIGGER_PX := MapBoundary.AI_EDGE_TURN_MARGIN_PX
const BOUNDARY_RECOVER_MARGIN_PX := 800.0
const BOUNDARY_TARGET_MARGIN_PX := MapBoundary.EXTENSION_WIDTH_PX + 200.0
const BOUNDARY_ARRIVAL_RADIUS_PX := 300.0  ## 目标比解除线深 400px，保证抵达 HOLD 前已释放
const BOUNDARY_HARD_CLAMP_MARGIN_PX := 40.0
const BOUNDARY_DIRECTIVE_PRIORITY := 100

## 奖励
var xp_per_kill: int = 100

# ══════════════════════════════════════════════
#  运行时状态
# ══════════════════════════════════════════════

## active 继承自 BossEncounter
var members: Array[Aircraft] = []          ## 存活成员（每帧过滤）
var all_members: Array[Aircraft] = []      ## 全部成员（含已击毁，HUD 用）

## 状态机
var squad_state: int = SquadState.INTRO
var state_timer: float = 0.0
## true 时 update() 跑状态机；false 时只清理死亡成员（PRE_STAGE 阶段事件层占用 AI）
var combat_phase_active: bool = false

## 子类或外部可覆盖进场方向（CSG 弹射 F-14：强制沿 CV heading 起飞）
var entry_angle_override: float = NAN
## 子类或外部可覆盖进场起点（BossEncounterEvent 设为"离玩家最远的地图边缘"）
var entry_origin_override: Vector2 = Vector2.INF

## 锚点（事件层注入）。猎手化后不再是"巡逻中心 / 归巢点"，只剩两个用途：
## ①与 entry_origin_override 一起判定是否走远端进场 ②经典进场时的出生基准
var anchor_position: Vector2 = Vector2.INF

## 隐形（CD 节奏管理 —— 状态机决定何时进 CLOAK 状态）
var _cloak_cd_timer: float = 0.0   ## 距下次允许进 CLOAK 的剩余秒数
var _cloak_in_state: bool = false  ## 当前是否在 CLOAK 状态（替代旧 cloak_active；仅供 _update_cloak_visual 读）
var _cloak_remaining: float = 0.0  ## CLOAK 状态剩余时间

## PURSUIT 软维护节流
var _maintain_timer: float = 0.0

## instance_id → 本层下发的返场 directive。只在进入/退出边缘带时变更，不每帧重建。
var _boundary_recoveries: Dictionary = {}
var _boundary_recovery_active: bool = false

## 呼号序号（由 survivor_spawner._create_enemy F-47/F-14 分支递增使用）
## 不能省 —— spawner 用它生成 WRAITH-01 / PLTGST-01 等
var _serial: int = 0

## 外部引用（spawn 时注入）
var _scene_root: Node = null
var _player: Aircraft = null
var _bullet_mgr: BulletManager = null
var _missile_mgr: MissileManager = null
var _squads_ref: Array[Squad] = []         ## 引用 survivor_mode._squads

# ══════════════════════════════════════════════
#  生成
# ══════════════════════════════════════════════

func spawn(scene_root: Node, aircraft_scene: PackedScene, create_enemy_func: Callable,
		player: Aircraft, bullet_mgr: BulletManager, missile_mgr: MissileManager,
		squads: Array[Squad]) -> void:
	if active:
		return
	if not player or player.is_destroyed:
		return

	_scene_root = scene_root
	_player = player
	_bullet_mgr = bullet_mgr
	_missile_mgr = missile_mgr
	_squads_ref = squads

	active = true
	members.clear()
	all_members.clear()
	# 远端进场（BossEncounterEvent 设了 entry_origin_override + anchor）：
	#   spawn 时不进 INTRO，事件层用 PURSUE_UNIT directive 驱动追击玩家；engage() 才切 PURSUIT
	# 经典进场：进 INTRO 状态走通场逻辑
	var use_remote_entry: bool = entry_origin_override != Vector2.INF and anchor_position != Vector2.INF
	if use_remote_entry:
		squad_state = SquadState.PURSUIT  ## 占位，combat_phase_active=false 时不会跑
		combat_phase_active = false
	else:
		squad_state = SquadState.INTRO
		combat_phase_active = true
	state_timer = 0.0

	if cloak_enabled:
		# 首轮 CD 固定一个周期 + 随机抖动
		_cloak_cd_timer = cloak_cycle + randf_range(0.0, cloak_cycle_jitter)
	_cloak_in_state = false
	_cloak_remaining = 0.0

	# ── 计算进场方向 / 起点 ──
	var pp := player.global_position
	var player_hdg := player.heading
	var side := 1.0 if randf() > 0.5 else -1.0
	var entry_angle: float
	var spawn_origin: Vector2
	if use_remote_entry:
		spawn_origin = entry_origin_override
		# 猎手：机头朝【玩家】，不是朝锚点 —— 出生即已经在往玩家方向压
		var to_player := (pp - spawn_origin)
		if to_player.length_squared() < 1.0:
			to_player = Vector2(0, -1)
		var dir := to_player.normalized()
		entry_angle = atan2(dir.x, -dir.y)
	elif is_nan(entry_angle_override):
		entry_angle = player_hdg + side * PI / 2.0
	else:
		entry_angle = entry_angle_override
	var entry_dir := Vector2(sin(entry_angle), -cos(entry_angle))
	var lateral_axis := Vector2(sin(entry_angle + PI / 2.0), -cos(entry_angle + PI / 2.0))
	if not use_remote_entry:
		if anchor_position != Vector2.INF:
			spawn_origin = anchor_position + entry_dir * 800.0
		else:
			spawn_origin = pp + entry_dir * SurvivorData.SPAWN_DISTANCE
			# 防越界
			if not MapBoundary.is_safe_inside(spawn_origin, 1500.0):
				var inward := (Vector2.ZERO - pp)
				if inward.length_squared() > 1.0:
					entry_dir = inward.normalized()
					entry_angle = atan2(entry_dir.x, -entry_dir.y)
					lateral_axis = Vector2(sin(entry_angle + PI / 2.0), -cos(entry_angle + PI / 2.0))
					spawn_origin = pp + entry_dir * SurvivorData.SPAWN_DISTANCE
	# 远端进场机头朝玩家，其他模式延用旧逻辑（entry_angle 反向）
	var heading_deg: float = rad_to_deg(entry_angle) if use_remote_entry else rad_to_deg(entry_angle + PI)

	# ── 菱形编队偏移 ──
	var offsets := _get_formation_offsets(entry_dir, lateral_axis)

	# ── 生成成员 + 静态分配战斗专长 ──
	var sq := Squad.new()
	sq.escort_doctrine_enabled = true  # 精英 BOSS 队吃护卫学说（spec squad-ai-escort §1）：护旗舰/反杀威胁者
	for i in range(squad_size):
		var pos := spawn_origin + (offsets[i] if i < offsets.size() else Vector2.ZERO)
		var ac: Aircraft = create_enemy_func.call(_member_type(i), pos, heading_deg)

		# 通用 BOSS meta
		ac.set_meta("boss_intro", true)
		ac.set_meta("category", "boss")
		ac.set_meta("skip_far_cleanup", true)
		ac.set_target_tier(Aircraft.AltitudeTier.HIGH)

		# 静态分配角色（默认：前 2 架 KNIGHT 近战，后排 SNIPER 远距；混编子类按 element 覆写）
		var role: int = _member_role(i)
		ac.set_meta(ROLE_META, role)

		var ai_node: AIController = ac._get_ai_controller()
		if ai_node:
			ai_node.enable_combat = false   ## 由 INTRO 完成 / engage() 打开
			# 经典 INTRO 才设通场航点；远端进场航点由 directive 接管
			if not use_remote_entry:
				var pass_point := pp - entry_dir * intro_pass_dist
				var exit_point := pp - entry_dir * standoff_radius_min
				ai_node.waypoints = PackedVector2Array([pass_point, exit_point])
				ai_node.current_waypoint_index = 0
			ai_node.arrival_distance = 300.0
			ai_node.squad = sq
			ai_node.squad_index = i
			if i == 0:
				sq.leader = ac
			# 静态写一次战斗参数（spec → AI 配置）
			_apply_role(ac, ai_node, role)

		# 子类钩子（挂 Herbst / 设 salvo_leader 等）
		_configure_spawn(ac, i, sq, ai_node)

		sq.members.append(ac)
		members.append(ac)
		all_members.append(ac)

	squads.append(sq)
	EventLogger.log_event("BOSS", display_name, "%s spawned (%d aircraft)" % [display_name, squad_size])

# ══════════════════════════════════════════════
#  主循环
# ══════════════════════════════════════════════

func update(delta: float) -> void:
	if not active:
		return

	# 清理已击毁
	var alive: Array[Aircraft] = []
	for member in members:
		if is_instance_valid(member) and not member.is_destroyed:
			alive.append(member)
		elif is_instance_valid(member) and member.is_destroyed:
			_on_member_destroyed(member)
	members = alive

	# 全灭
	if members.is_empty():
		active = false
		_cloak_in_state = false
		EventLogger.log_event("BOSS", display_name, "%s eliminated" % display_name)
		return

	# PRE_STAGE 阶段：事件层用 directive 接管 AI，状态机不跑
	if not combat_phase_active:
		return

	if not _player or _player.is_destroyed:
		return

	# 全局敌机边界纪律会跳过 category=boss，飞机类 BOSS 在基类自行守世界外框。
	# 收容期间暂停专属战术，避免 Relay Break / Wraith 相位 directive 与返场指令抢写；
	# 其它成员的常规 BFM 仍继续，返场成员也保持火控开启。
	_update_boundary_recovery()

	# 推进状态机
	state_timer += delta
	if cloak_enabled and not _cloak_in_state:
		_cloak_cd_timer = maxf(_cloak_cd_timer - delta, 0.0)

	var next_state := _decide_next_state(delta)
	if next_state != squad_state:
		_exit_state(squad_state)
		var prev := squad_state
		squad_state = next_state
		state_timer = 0.0
		_enter_state(next_state, prev)

	_update_state(squad_state, delta)


## 成员从存活数组移除前的单次钩子。基类无行为；具体 BOSS 可绑定减员演出。
func _on_member_destroyed(_member: Aircraft) -> void:
	pass


## 飞机类 BOSS 的世界边缘收容。返回 true 表示至少一架仍在返场；同名状态位暂停专属战术层。
func _update_boundary_recovery() -> bool:
	var should_start := false
	var has_boss_member := false
	for m in members:
		if not is_instance_valid(m) or m.is_destroyed \
				or String(m.get_meta("category", "")) != "boss":
			continue
		has_boss_member = true
		if MapBoundary.distance_to_edge(m.global_position) <= BOUNDARY_TRIGGER_PX:
			should_start = true
			break
	# AceSupportSquad 也继承本类，但 category=ace_support 的物理出入场/撤离由事件层管理。
	if not has_boss_member and not _boundary_recovery_active:
		return false
	# 常态热路径只做至多 4 次标量距离判断；Dictionary/keys 分配仅在罕见返场期间发生。
	if not should_start and not _boundary_recovery_active:
		return false

	if should_start and not _boundary_recovery_active:
		# 先撤专属战术下过的 directive，再给越界成员下高优先级返场；恢复后从干净相位重启。
		if squad_state == SquadState.PURSUIT:
			_tactics_exit()
		_boundary_recovery_active = true

	var alive_ids: Dictionary = {}
	for m in members:
		if not is_instance_valid(m) or m.is_destroyed \
				or String(m.get_meta("category", "")) != "boss":
			continue
		var id := m.get_instance_id()
		alive_ids[id] = true
		var edge_dist := MapBoundary.distance_to_edge(m.global_position)
		var recovery: AIDirective = _boundary_recoveries.get(id, null)

		if recovery != null and edge_dist >= BOUNDARY_RECOVER_MARGIN_PX:
			var recovered_ai := m._get_ai_controller()
			if recovered_ai != null and recovered_ai._directive == recovery:
				recovered_ai.set_event_directive(null)
			_boundary_recoveries.erase(id)
			EventLogger.log_event("BOSS", display_name,
					"%s boundary recovery complete" % m.callsign)
			continue

		if recovery == null and edge_dist > BOUNDARY_TRIGGER_PX:
			continue

		# 40px 硬护栏在尚未越线时即生效；正常路径仍靠 fly_to 真实转弯。
		# SurvivorSpawner 另有不依赖 encounter tick 的同语义兜底（SEAM-027）。
		var touching_hard_rail := edge_dist <= BOUNDARY_HARD_CLAMP_MARGIN_PX
		if touching_hard_rail:
			m.global_position = MapBoundary.clamp_inside(
					m.global_position, BOUNDARY_HARD_CLAMP_MARGIN_PX)
			m.clear_trail()

		var target := boundary_recovery_point(m.global_position)
		if recovery == null:
			recovery = AIDirective.fly_to(
					target, AIDirective.OnArrival.HOLD, BOUNDARY_ARRIVAL_RADIUS_PX)
			recovery.combat_disabled = false
			recovery.priority = BOUNDARY_DIRECTIVE_PRIORITY
			_boundary_recoveries[id] = recovery
			EventLogger.log_event("BOSS", display_name,
					"%s boundary recovery start edge=%.0fpx" % [m.callsign, edge_dist])

		var ai := m._get_ai_controller()
		if ai != null and ai._directive != recovery:
			ai.set_event_directive(recovery)
		if touching_hard_rail:
			var inward := target - m.global_position
			if inward.length_squared() > 1.0:
				m.heading = atan2(inward.x, -inward.y)

	# 死亡成员的 RefCounted directive 不应驻留到 encounter 结束。
	for id in _boundary_recoveries.keys():
		if not alive_ids.has(id):
			_boundary_recoveries.erase(id)

	if _boundary_recoveries.is_empty():
		if _boundary_recovery_active:
			_boundary_recovery_active = false
			if squad_state == SquadState.PURSUIT:
				_tactics_enter()
		return false
	return true


## 纯几何：保留与边缘平行的坐标，只把越界轴推回安全带。
static func boundary_recovery_point(pos: Vector2) -> Vector2:
	return MapBoundary.clamp_inside(pos, BOUNDARY_TARGET_MARGIN_PX)

# ══════════════════════════════════════════════
#  状态机：决策
# ══════════════════════════════════════════════

func _decide_next_state(delta: float) -> int:
	match squad_state:
		SquadState.INTRO:
			if state_timer >= intro_duration:
				return SquadState.PURSUIT
		SquadState.PURSUIT:
			# 猎手：不因玩家跑远而脱战。PURSUIT 只会被隐形打断，之后必回 PURSUIT
			if cloak_enabled and _should_enter_cloak():
				return SquadState.CLOAK
		SquadState.CLOAK:
			if _has_close_player_contact():
				return SquadState.PURSUIT
			_cloak_remaining -= delta
			if _cloak_remaining <= 0.0:
				return SquadState.PURSUIT
	return squad_state

## CLOAK 触发条件：CD 完成且玩家不在近距揭露圈；可选紧急触发仅供非 Wraith 子类。
func _should_enter_cloak() -> bool:
	if _has_close_player_contact():
		return false
	if _cloak_cd_timer <= 0.0:
		return true
	var elapsed_in_cd := cloak_cycle - _cloak_cd_timer
	if cloak_emergency_enabled and elapsed_in_cd >= CLOAK_EMERGENCY_MIN_ELAPSED \
			and _has_incoming_missile():
		EventLogger.log_event("BOSS", display_name, "emergency cloak (incoming missile)")
		return true
	return false

# ══════════════════════════════════════════════
#  状态机：进入 / 退出 / 维护
# ══════════════════════════════════════════════

func _enter_state(s: int, _prev: int) -> void:
	match s:
		SquadState.INTRO:
			# 由 spawn 直接进入；INTRO 期间 enable_combat=false
			pass
		SquadState.PURSUIT:
			_pursuit_enter()
		SquadState.CLOAK:
			_cloak_enter()

func _exit_state(s: int) -> void:
	match s:
		SquadState.CLOAK:
			_cloak_exit()
		SquadState.PURSUIT:
			# 离开 PURSUIT（进隐形）→ 撤掉战术层的 directive 与包围偏置，
			# 否则隐形期间四机还在执行上一相的站位，回来时相位与实际脱节
			_tactics_exit()
		_:
			pass

func _update_state(s: int, delta: float) -> void:
	match s:
		SquadState.INTRO:
			_intro_update(delta)
		SquadState.PURSUIT:
			_pursuit_update(delta)
			if not _boundary_recovery_active:
				_tactics_update(delta)
		SquadState.CLOAK:
			_cloak_update(delta)

# ══════════════════════════════════════════════
#  队级战术层钩子（子类可选实现）
# ══════════════════════════════════════════════
#
# tier 层（本类）管"是否交战 / 是否隐形"；**队级战术编排**是子类的事。
# Wraith 在 PURSUIT 之内跑一套 PERCH→BRACKET→PRESS→RESET 状态机（见 wraith_tactics.gd）；
# 其它王牌中队不实现这三个钩子就退化为"各自跑 BFM"的现状行为，零影响。

## 进入 PURSUIT：战术层起手
func _tactics_enter() -> void:
	pass

## PURSUIT 每帧：推进战术状态机
func _tactics_update(_delta: float) -> void:
	pass

## 离开 PURSUIT（进隐形 / 全灭 / 事件结束）：撤掉战术层下过的一切
func _tactics_exit() -> void:
	pass

# ── INTRO ──

func _intro_update(_delta: float) -> void:
	if state_timer >= intro_duration:
		# 由 _decide_next_state 切到 PURSUIT，在 _enter_state 启用 combat
		pass

# ── PURSUIT（默认战斗）──

## 进入 PURSUIT：一次性把每个成员设到 ENGAGE 状态 + 锁玩家。**之后绝不每帧覆盖 AI 字段**。
## 让 AIController 的 BFM 决策树自然跑（LEAD_PURSUIT / LAG_PURSUIT / HIGH_YOYO 等）
func _pursuit_enter() -> void:
	for m in members:
		if not is_instance_valid(m):
			continue
		m.remove_meta("boss_intro")
		var ai: AIController = m._get_ai_controller()
		if not ai:
			continue
		ai.set_event_directive(null)   ## 清掉 PRE_STAGE 残留的 directive
		ai.enable_combat = true
		# ace_evader（零 flare 机动规避型个体，tier §3.4 例外条款）：不打 boss_attacker，
		# 让既有规避入口（被 not is_boss_attacker() 挡）对其放行
		ai.boss_attacker = not m.has_meta(&"ace_evader")
		# ace_tactics_owned：该成员的交战状态整体归队级战术模块管（骑士掠袭等），
		# 基类不下 ENGAGE 锁玩家（下了会把 PATROL 相位打回缠斗）
		if m.has_meta(&"ace_tactics_owned"):
			continue
		# ⚠ 不在这里写 bvr_only —— 它是**角色属性**（SNIPER=true / KNIGHT=false），
		#   在 spawn 期由 _apply_role 静态写死。此处若无脑置 false 会把 SNIPER 的
		#   站位带（4~6km）当场抹掉，角色分化名存实亡
		# 经 acquire_target(TS_BOSS) 指派，优先级仲裁防抢写；过渡走 API 不碰私有 _state
		if ai.acquire_target(_player, AIController.TargetSource.TS_BOSS, "ace PURSUIT enter"):
			ai.enter_engage_state()
			m.tactical_aggression = 1.0
	_maintain_timer = 0.0
	EventLogger.log_event("BOSS", display_name, "→ PURSUIT")
	_tactics_enter()

## 软维护：每 PURSUIT_MAINTAIN_INTERVAL 秒检查一次，**只补不破坏**。
##   - 成员被打掉 ENGAGE → 重新设 ENGAGE + combat_target（不重置任何 timer）
##   - 远距开加力（让 BFM 该用的速度不被巡航速度卡住）
func _pursuit_update(delta: float) -> void:
	_maintain_timer -= delta
	if _maintain_timer > 0.0:
		return
	_maintain_timer = PURSUIT_MAINTAIN_INTERVAL
	var pp := _player.global_position
	for m in members:
		if not is_instance_valid(m):
			continue
		if m.has_meta(&"ace_tactics_owned"):
			continue   # 战术模块全权成员：软维护不得抢写（见 _pursuit_enter 注释）
		var ai: AIController = m._get_ai_controller()
		if not ai:
			continue
		# Herbst 活动中不打扰；记录"刚才在 Herbst"，退出帧立刻硬补 combat_target
		var hm := m.get_herbst()
		if hm and hm.is_active:
			m.set_meta("ace_herbst_was_active", true)
			continue
		var herbst_just_exited := m.has_meta("ace_herbst_was_active")
		if herbst_just_exited:
			m.remove_meta("ace_herbst_was_active")
		# 软重连：只在掉出 ENGAGE 时补回，不动 _tactic_timer
		var need_target := ai._current_target == null \
				or not is_instance_valid(ai._current_target) \
				or (ai._current_target is Aircraft and (ai._current_target as Aircraft).is_destroyed)
		if ai._state != AIController.AIState.ENGAGE or need_target or herbst_just_exited:
			# 经 acquire_target(TS_BOSS) 指派，优先级仲裁防抢写；软重连不打断战术选择
			if ai.acquire_target(_player, AIController.TargetSource.TS_BOSS, "ace PURSUIT maintain"):
				ai.enter_engage_state(false)  # reset_tactic=false：只补状态+engage_timer
				ai.boss_attacker = not m.has_meta(&"ace_evader")
				if herbst_just_exited:
					ai._tactic_timer = 0.0   ## Herbst 退出后让 BFM 重新挑战术（避免一路 EXTEND）
		# 远距加力（燃油守卫 2026-07-03：裸写发生在该机 update_fuel 之后，无检查会
		# 零燃油白嫖 AB 推力——当前被 spawner 的 infinite_fuel 掩盖，防未来关无限油翻车）
		var dist := m.global_position.distance_to(pp)
		if dist > force_pursuit_distance and m.fuel > 0.0:
			m.is_afterburner = true
		else:
			# ⚠ 必须有 else：原先只置 true 从不置 false，一旦拉开就永久点着加力，
			# 速度上去后盘旋半径爆炸 → 再也回不到能咬住的距离 → 自锁死绕圈
			# （playtest log 20260720_172222：g 全程钉死 max_g）
			m.is_afterburner = false

# ── CLOAK ──

## CLOAK 进入：仅切视觉 + suppress flares。**不改 AI 状态** —— 飞机继续 PURSUIT 行为
## 当前 PURSUIT 设置的 ENGAGE / target 仍在
func _cloak_enter() -> void:
	_cloak_in_state = true
	_cloak_remaining = cloak_duration
	# 黄色战术框
	var popup_text := tr("POPUP_CLOAK")
	for m in members:
		if is_instance_valid(m):
			m.show_tactic_popup(popup_text)
	EventLogger.log_event("BOSS", display_name, "cloak activated (%.1fs)" % cloak_duration)

func _cloak_update(_delta: float) -> void:
	# 衰减视觉
	var newly_cloaked: Array[Aircraft] = []
	for m in members:
		if not is_instance_valid(m):
			continue
		var was_cloaked := m.is_cloaked
		if _cloak_remaining > cloak_duration - cloak_fade:
			# 起 fade-in 阶段：alpha 1→0
			var fade_progress := (cloak_duration - _cloak_remaining) / cloak_fade
			m._cloak_alpha = 1.0 - clampf(fade_progress, 0.0, 1.0)
			m.is_cloaked = fade_progress >= 1.0
		elif _cloak_remaining < cloak_fade:
			# 末尾 fade-out 阶段：alpha 0→1
			var fade_progress := _cloak_remaining / cloak_fade
			m._cloak_alpha = 1.0 - clampf(fade_progress, 0.0, 1.0)
			m.is_cloaked = fade_progress >= 0.5
		else:
			m._cloak_alpha = 0.0
			m.is_cloaked = true
		if m.counter_stealth_revealed:
			m._cloak_alpha = 1.0
			m.is_cloaked = false
		if m.is_cloaked and not was_cloaked:
			newly_cloaked.append(m)
			m.sync_stealth_trail_emission()
		elif was_cloaked and not m.is_cloaked:
			m.sync_stealth_trail_emission()
		m.suppress_flares = true
	# 四机通常在同帧跨过隐形沿；合批后全场玩家观察者只扫描一次。
	if not newly_cloaked.is_empty():
		SENSOR_STEALTH_CONTROLLER.release_player_sensor_refs_batch(
			newly_cloaked, CombatUnit.all_units, false, "optical cloak")

func _cloak_exit() -> void:
	_cloak_in_state = false
	_cloak_cd_timer = cloak_cycle + randf_range(0.0, cloak_cycle_jitter)
	for m in members:
		if not is_instance_valid(m):
			continue
		m.is_cloaked = false
		m._cloak_alpha = 1.0
		m.suppress_flares = false
		m.sync_stealth_trail_emission()
	EventLogger.log_event("BOSS", display_name, "cloak deactivated")


func _has_close_player_contact() -> bool:
	if _player == null or not is_instance_valid(_player) or _player.is_destroyed:
		return false
	var reveal_dist_sq := SensorStealthController.PROXIMITY_REVEAL_PX \
		* SensorStealthController.PROXIMITY_REVEAL_PX
	for member in members:
		if is_instance_valid(member) and not member.is_destroyed \
				and member.global_position.distance_squared_to(_player.global_position) <= reveal_dist_sq:
			return true
	return false

# ══════════════════════════════════════════════
#  外部触发（BossEncounterEvent 调用）
# ══════════════════════════════════════════════

## 玩家机换人时重定向（基类契约，见 BossEncounter.set_player_ref）
func set_player_ref(p: Aircraft) -> void:
	if p == null or not is_instance_valid(p):
		return
	_player = p

## 玩家进入 BOSS 圈或贴近成员 → 进入 PURSUIT 状态
## 远端进场模式（PRE_STAGE）下，combat_phase_active=false；这里翻 true 启动状态机
func engage() -> void:
	combat_phase_active = true
	# 状态机推进到 PURSUIT（_enter_state 会跑配置）
	if squad_state != SquadState.PURSUIT:
		_exit_state(squad_state)
		squad_state = SquadState.PURSUIT
		state_timer = 0.0
		_enter_state(SquadState.PURSUIT, SquadState.INTRO)

# ══════════════════════════════════════════════
#  角色（spawn 时静态写一次）
# ══════════════════════════════════════════════

## SNIPER 的距离带（spec bosses/wraith-squadron §2.2）：4000~6000 m。
## PIXELS_PER_METER = 0.5 → 1 px = 2 m，故 4000 m = 2000 px、6000 m = 3000 px。
## 这两个数恰好等于 AIController 的 BVR 全局默认值，此处显式写出以免默认值将来变动时
## 悄悄改掉 Wraith 的站位设计
const SNIPER_STANDOFF_MIN_PX := 2000.0   ## 4000 m —— 被压进这个距离即视为站位失败，拉开
const SNIPER_FLEE_DIST_PX := 3000.0      ## 6000 m —— 拉开后重新站位的距离

## 角色 → AI 配置（spec bosses/wraith-squadron §3.5 的三个消费点）
##   ①期望交战距离  ②武器竞选偏好  ③被咬时的反应
##
## ⚠ aggression / self_preservation 守 ace-squadron-tier §2.1 的 tier 级铁律
##   （≥0.90 / ≤0.25）。SNIPER 的"不贪战"**不靠调低交战欲实现** —— 那会让它在该开火时
##   也消极，正是 tier 想禁止的。真正要的是空间行为"被压近了就拉开"，由 bvr_only 表达，
##   与交战欲正交（裁决记录见 wraith spec §2.2）
func _apply_role(member: Aircraft, ai: AIController, role: int) -> void:
	ai.boss_attacker = true
	match role:
		AceRole.KNIGHT:
			# ②机炮优先 ③被咬转身对抗（不脱离）
			member.prefer_gun_mode = true
			ai.bvr_only = false
			ai.aggression = 0.95
			ai.self_preservation = 0.15
			_configure_close_fighter_combat(member)
		AceRole.SNIPER:
			# ②导弹优先 ①③低于 4km 强制脱离、拉到 6km 重新站位
			member.prefer_gun_mode = false
			ai.bvr_only = true
			ai.bvr_standoff_min_px_override = SNIPER_STANDOFF_MIN_PX
			ai.bvr_flee_distance_px_override = SNIPER_FLEE_DIST_PX
			ai.aggression = 0.95
			ai.self_preservation = 0.25
			_configure_ranged_striker_combat(member)

## 读一架飞机的王牌角色（无 meta = NONE）
static func role_of(ac: Aircraft) -> int:
	if ac == null or not is_instance_valid(ac):
		return AceRole.NONE
	return int(ac.get_meta(ROLE_META, AceRole.NONE))

# ══════════════════════════════════════════════
#  HUD / 工具方法
# ══════════════════════════════════════════════

## HUD 用：获取全部成员（含已击毁）
func get_display_members() -> Array:
	return all_members

## 收集所有成员（事件层批量下 directive 用）
func get_all_members() -> Array:
	return members

## 当前激活的飞机小队（用于呼号分配 / HUD 兼容）
func get_active_ace_squad() -> AceSquad:
	return self

func _has_incoming_missile() -> bool:
	if not _missile_mgr:
		return false
	for child in _missile_mgr.get_children():
		if child is Missile:
			var m: Missile = child as Missile
			if m.is_active and m.has_guidance and m.target is Aircraft:
				for member in members:
					if m.target == member:
						return true
	return false

## 编队偏移（子类可覆盖）
func _get_formation_offsets(entry_dir: Vector2, lateral_axis: Vector2) -> Array[Vector2]:
	return [
		Vector2.ZERO,
		-entry_dir * 200.0 + lateral_axis * 180.0,
		-entry_dir * 200.0 - lateral_axis * 180.0,
		-entry_dir * 400.0,
	]

# ══════════════════════════════════════════════
#  子类钩子（覆盖以定制行为）
# ══════════════════════════════════════════════

## 每架飞机生成后的额外配置（挂载机动模块、设 salvo_leader 等）
func _configure_spawn(_member: Aircraft, _index: int, _squad: Squad, _ai: AIController) -> void:
	pass

## 第 i 架成员的机型（混编子类按 element 覆写；默认全队同型）
func _member_type(_i: int) -> int:
	return enemy_type

## 第 i 架成员的角色（默认基类规则：前 2 架 KNIGHT，其余 SNIPER）
func _member_role(i: int) -> int:
	return AceRole.KNIGHT if i < 2 else AceRole.SNIPER

## 近距纠缠组战斗参数
func _configure_close_fighter_combat(_member: Aircraft) -> void:
	pass

## 远距攻击组战斗参数
func _configure_ranged_striker_combat(_member: Aircraft) -> void:
	pass
