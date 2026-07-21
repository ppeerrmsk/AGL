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
##   ANCHOR_HOLD  玩家飞远了 → 给每架下 PATROL_RING directive 绕锚点 → 玩家回来切 PURSUIT
##
## ── 战斗专长（CombatSpecialty）──
## 在 spawn 时**静态分配**，运行时不变：
##   - 前 2 架（队长 + 第一僚机）= CLOSE_FIGHTER（机炮 + 高度激进近距参数）
##   - 后 2 架 = RANGED_STRIKER（导弹 + 远距冲刺参数）
##
## ── 与事件系统的关系 ──
## - PRE_STAGE 阶段：BossEncounterEvent 通过 AIDirective.FLY_TO_POINT 驱动飞入 + PATROL_RING 巡逻
## - ENGAGED 触发：事件 clear_all_directives() + AceSquad.engage() → 进 PURSUIT 状态
## - ANCHOR_HOLD 状态：AceSquad 自己下 PATROL_RING directive（owner_event=null，永久直到清除）

class_name AceSquad
extends BossEncounter

# ══════════════════════════════════════════════
#  状态机
# ══════════════════════════════════════════════

enum SquadState { INTRO, PURSUIT, CLOAK, ANCHOR_HOLD }
enum CombatSpecialty { NONE, CLOSE_FIGHTER, RANGED_STRIKER }

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
const CLOAK_EMERGENCY_MIN_ELAPSED: float = 10.0  ## 紧急隐形最早触发的间隔

## 距离
var standoff_radius_min: float = 1800.0
var standoff_radius_max: float = 2500.0
var ranged_max_distance: float = 3500.0
var force_pursuit_distance: float = 2500.0  ## 距玩家 > 此值时开加力（PURSUIT 软维护检查）

## 锚点
const ANCHOR_ENGAGEMENT_RADIUS := 4500.0  ## 玩家在此半径内 → PURSUIT；外 → ANCHOR_HOLD
const ANCHOR_ORBIT_RADIUS := 1600.0       ## ANCHOR_HOLD 状态下盘旋半径

## PURSUIT 软维护节流：每 N 秒一次"成员是否还在 ENGAGE"检查
const PURSUIT_MAINTAIN_INTERVAL := 0.5

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

## 锚点（事件层注入）；INF = 不启用 ANCHOR_HOLD 状态
var anchor_position: Vector2 = Vector2.INF
var _anchor_orbit_phase: float = 0.0  ## ANCHOR_HOLD 进入时记录的相位（不再每帧动）

## 隐形（CD 节奏管理 —— 状态机决定何时进 CLOAK 状态）
var _cloak_cd_timer: float = 0.0   ## 距下次允许进 CLOAK 的剩余秒数
var _cloak_in_state: bool = false  ## 当前是否在 CLOAK 状态（替代旧 cloak_active；仅供 _update_cloak_visual 读）
var _cloak_remaining: float = 0.0  ## CLOAK 状态剩余时间

## PURSUIT 软维护节流
var _maintain_timer: float = 0.0

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
	#   spawn 时不进 INTRO，事件层会用 directive 驱动飞入 + 巡逻；engage() 才切 PURSUIT
	# 经典进场：进 INTRO 状态走通场逻辑
	var use_far_edge_entry: bool = entry_origin_override != Vector2.INF and anchor_position != Vector2.INF
	if use_far_edge_entry:
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
	if use_far_edge_entry:
		spawn_origin = entry_origin_override
		var to_anchor := (anchor_position - spawn_origin)
		if to_anchor.length_squared() < 1.0:
			to_anchor = Vector2(0, -1)
		var dir := to_anchor.normalized()
		entry_angle = atan2(dir.x, -dir.y)
	elif is_nan(entry_angle_override):
		entry_angle = player_hdg + side * PI / 2.0
	else:
		entry_angle = entry_angle_override
	var entry_dir := Vector2(sin(entry_angle), -cos(entry_angle))
	var lateral_axis := Vector2(sin(entry_angle + PI / 2.0), -cos(entry_angle + PI / 2.0))
	if not use_far_edge_entry:
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
	# 远端进场机头朝 anchor，其他模式延用旧逻辑（entry_angle 反向）
	var heading_deg: float = rad_to_deg(entry_angle) if use_far_edge_entry else rad_to_deg(entry_angle + PI)

	# ── 菱形编队偏移 ──
	var offsets := _get_formation_offsets(entry_dir, lateral_axis)

	# ── 生成成员 + 静态分配战斗专长 ──
	var sq := Squad.new()
	sq.escort_doctrine_enabled = true  # 精英 BOSS 队吃护卫学说（spec squad-ai-escort §1）：护旗舰/反杀威胁者
	for i in range(squad_size):
		var pos := spawn_origin + (offsets[i] if i < offsets.size() else Vector2.ZERO)
		var ac: Aircraft = create_enemy_func.call(enemy_type, pos, heading_deg)

		# 通用 BOSS meta
		ac.set_meta("boss_intro", true)
		ac.set_meta("category", "boss")
		ac.set_meta("skip_far_cleanup", true)
		ac.set_target_tier(Aircraft.AltitudeTier.HIGH)

		# 静态分配战斗专长：前 2 架近战 + 机炮，后 2 架远距 + 导弹
		var spec: int = CombatSpecialty.CLOSE_FIGHTER if i < 2 else CombatSpecialty.RANGED_STRIKER
		ac.set_meta("combat_specialty", spec)

		var ai_node: AIController = ac._get_ai_controller()
		if ai_node:
			ai_node.enable_combat = false   ## 由 INTRO 完成 / engage() 打开
			# 经典 INTRO 才设通场航点；远端进场航点由 directive 接管
			if not use_far_edge_entry:
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
			_apply_specialty(ac, ai_node, spec)

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

# ══════════════════════════════════════════════
#  状态机：决策
# ══════════════════════════════════════════════

func _decide_next_state(delta: float) -> int:
	match squad_state:
		SquadState.INTRO:
			if state_timer >= intro_duration:
				return SquadState.PURSUIT
		SquadState.PURSUIT:
			if _is_player_far_from_anchor():
				return SquadState.ANCHOR_HOLD
			if cloak_enabled and _should_enter_cloak():
				return SquadState.CLOAK
		SquadState.CLOAK:
			_cloak_remaining -= delta
			if _cloak_remaining <= 0.0:
				return SquadState.PURSUIT
		SquadState.ANCHOR_HOLD:
			if not _is_player_far_from_anchor():
				return SquadState.PURSUIT
	return squad_state

func _is_player_far_from_anchor() -> bool:
	if anchor_position == Vector2.INF:
		return false
	return _player.global_position.distance_to(anchor_position) > ANCHOR_ENGAGEMENT_RADIUS

## CLOAK 触发条件：CD 到了 OR 紧急（CD 已过最短间隔且有导弹来袭）
func _should_enter_cloak() -> bool:
	if _cloak_cd_timer <= 0.0:
		return true
	# 紧急隐形：CD 已过最短间隔 + 有导弹锁住任一成员
	var elapsed_in_cd := cloak_cycle - _cloak_cd_timer
	if elapsed_in_cd >= CLOAK_EMERGENCY_MIN_ELAPSED and _has_incoming_missile():
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
		SquadState.ANCHOR_HOLD:
			_anchor_hold_enter()

func _exit_state(s: int) -> void:
	match s:
		SquadState.CLOAK:
			_cloak_exit()
		SquadState.ANCHOR_HOLD:
			_anchor_hold_exit()
		_:
			pass

func _update_state(s: int, delta: float) -> void:
	match s:
		SquadState.INTRO:
			_intro_update(delta)
		SquadState.PURSUIT:
			_pursuit_update(delta)
		SquadState.CLOAK:
			_cloak_update(delta)
		SquadState.ANCHOR_HOLD:
			pass   # directive 已下，每帧无需操作

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
		ai.boss_attacker = true
		ai.bvr_only = false
		# 经 acquire_target(TS_BOSS) 指派，优先级仲裁防抢写；过渡走 API 不碰私有 _state
		if ai.acquire_target(_player, AIController.TargetSource.TS_BOSS, "ace PURSUIT enter"):
			ai.enter_engage_state()
			m.tactical_aggression = 1.0
	_maintain_timer = 0.0
	EventLogger.log_event("BOSS", display_name, "→ PURSUIT")

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
				ai.boss_attacker = true
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
	# 玩家若锁着我们，清掉锁（给视觉效果一个清爽起点）
	if _player.combat_target and is_instance_valid(_player.combat_target):
		for m in members:
			if _player.combat_target == m:
				_player.clear_combat_target()
				break
	# 黄色战术框
	var popup_text := tr("POPUP_CLOAK")
	for m in members:
		if is_instance_valid(m):
			m.show_tactic_popup(popup_text)
	EventLogger.log_event("BOSS", display_name, "cloak activated (%.1fs)" % cloak_duration)

func _cloak_update(_delta: float) -> void:
	# 衰减视觉
	for m in members:
		if not is_instance_valid(m):
			continue
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
		m.suppress_flares = true

func _cloak_exit() -> void:
	_cloak_in_state = false
	_cloak_cd_timer = cloak_cycle + randf_range(0.0, cloak_cycle_jitter)
	for m in members:
		if not is_instance_valid(m):
			continue
		m.is_cloaked = false
		m._cloak_alpha = 1.0
		m.suppress_flares = false
	EventLogger.log_event("BOSS", display_name, "cloak deactivated")

# ── ANCHOR_HOLD ──

## 玩家飞远了 → 给每架下 PATROL_RING directive 绕锚点慢飞
## directive owner_event=null（永久），_anchor_hold_exit 时清除
func _anchor_hold_enter() -> void:
	for m in members:
		if not is_instance_valid(m):
			continue
		var ai: AIController = m._get_ai_controller()
		if not ai:
			continue
		var d := AIDirective.patrol_ring(anchor_position, ANCHOR_ORBIT_RADIUS)
		ai.set_event_directive(d)
	EventLogger.log_event("BOSS", display_name, "→ ANCHOR_HOLD (player far from anchor)")

func _anchor_hold_exit() -> void:
	for m in members:
		if not is_instance_valid(m):
			continue
		var ai: AIController = m._get_ai_controller()
		if ai:
			ai.set_event_directive(null)

# ══════════════════════════════════════════════
#  外部触发（BossEncounterEvent 调用）
# ══════════════════════════════════════════════

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
#  战斗专长（spawn 时静态写一次）
# ══════════════════════════════════════════════

func _apply_specialty(member: Aircraft, ai: AIController, spec: int) -> void:
	ai.boss_attacker = true
	ai.bvr_only = false
	match spec:
		CombatSpecialty.CLOSE_FIGHTER:
			member.prefer_gun_mode = true
			ai.aggression = 0.95
			ai.self_preservation = 0.15
			_configure_close_fighter_combat(member)
		CombatSpecialty.RANGED_STRIKER:
			member.prefer_gun_mode = false
			ai.aggression = 0.95
			ai.self_preservation = 0.10
			_configure_ranged_striker_combat(member)

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

## 近距纠缠组战斗参数
func _configure_close_fighter_combat(_member: Aircraft) -> void:
	pass

## 远距攻击组战斗参数
func _configure_ranged_striker_combat(_member: Aircraft) -> void:
	pass
