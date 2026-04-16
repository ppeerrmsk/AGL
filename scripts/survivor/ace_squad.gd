## 王牌中队（Ace Squad）BOSS 基类
## 飞机类 BOSS 通用框架：小队生命周期 / 角色分配 / 隐形系统 / HUD 接口
## 子类只需覆盖配置方法即可创建新的 BOSS 类型。
class_name AceSquad
extends RefCounted

# ── 角色 & 阶段 ──
enum Role { NONE, EVADER, CLOSE_FIGHTER, RANGED_STRIKER }
enum Tactic { INTRO, COMBAT }

# ══════════════════════════════════════════════
#  配置（子类在 _init 中覆盖）
# ══════════════════════════════════════════════

var squad_size: int = 4
var intro_duration: float = 4.0
var intro_pass_dist: float = 800.0
var callsign_prefix: String = "ACE"
var boss_name: String = "ACE SQUAD"       ## HUD 标题
var enemy_type: int = 15                  ## EnemyType 枚举值（F47=15）

## 隐形
var cloak_enabled: bool = false
var cloak_cycle: float = 60.0
var cloak_duration: float = 5.5
var cloak_fade: float = 0.5

## 距离
var standoff_radius_min: float = 1800.0
var standoff_radius_max: float = 2500.0
var ranged_max_distance: float = 3500.0
var force_pursuit_distance: float = 2500.0  ## 超过此距离强制 LEAD_PURSUIT + 加力

## 奖励
var xp_per_kill: int = 100

# ══════════════════════════════════════════════
#  运行时状态
# ══════════════════════════════════════════════

var active: bool = false
var members: Array[Aircraft] = []          ## 存活成员（每帧过滤）
var all_members: Array[Aircraft] = []      ## 全部成员（含已击毁，HUD 用）
var tactic: int = Tactic.INTRO
var tactic_timer: float = 0.0
var _serial: int = 0

## 隐形状态
var cloak_timer: float = 0.0
var cloak_active: bool = false
var cloak_remaining: float = 0.0

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
	tactic = Tactic.INTRO
	tactic_timer = intro_duration
	if cloak_enabled:
		cloak_timer = cloak_cycle
	cloak_active = false
	cloak_remaining = 0.0

	var pp := player.global_position
	var player_hdg := player.heading
	var side := 1.0 if randf() > 0.5 else -1.0
	var entry_angle := player_hdg + side * PI / 2.0
	var entry_dir := Vector2(sin(entry_angle), -cos(entry_angle))
	var lateral_axis := Vector2(sin(entry_angle + PI / 2.0), -cos(entry_angle + PI / 2.0))
	var spawn_origin := pp + entry_dir * SurvivorData.SPAWN_DISTANCE
	var heading_deg := rad_to_deg(entry_angle + PI)

	# 菱形编队偏移
	var offsets := _get_formation_offsets(entry_dir, lateral_axis)

	var sq := Squad.new()
	for i in range(squad_size):
		var pos := spawn_origin + (offsets[i] if i < offsets.size() else Vector2.ZERO)
		var ac: Aircraft = create_enemy_func.call(enemy_type, pos, heading_deg)

		# 通用 BOSS meta
		ac.set_meta("boss_intro", true)
		ac.set_meta("category", "boss")
		ac.set_meta("skip_far_cleanup", true)
		ac.set_target_tier(Aircraft.AltitudeTier.HIGH)

		# 通场航路点
		var pass_point := pp - entry_dir * intro_pass_dist
		var exit_point := pp - entry_dir * standoff_radius_min
		var ai_node: AIController = ac._get_ai_controller()
		if ai_node:
			ai_node.enable_combat = false
			ai_node.waypoints = PackedVector2Array([pass_point, exit_point])
			ai_node.current_waypoint_index = 0
			ai_node.arrival_distance = 300.0
			ai_node.squad = sq
			ai_node.squad_index = i
			if i == 0:
				sq.leader = ac

		# 子类钩子：额外配置（挂载机动模块、设 salvo_leader 等）
		_configure_spawn(ac, i, sq, ai_node)

		sq.members.append(ac)
		members.append(ac)
		all_members.append(ac)

	squads.append(sq)
	EventLogger.log_event("BOSS", boss_name, "%s spawned (%d aircraft)" % [boss_name, squad_size])

# ══════════════════════════════════════════════
#  每帧更新
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
		cloak_active = false
		EventLogger.log_event("BOSS", boss_name, "%s eliminated" % boss_name)
		return

	# 隐形系统
	if cloak_enabled:
		_update_cloak(delta)

	# INTRO 阶段
	if tactic == Tactic.INTRO:
		tactic_timer -= delta
		_process_intro()
		return

	# 战斗阶段：角色分配
	if not _player or _player.is_destroyed:
		return
	_assign_roles()

# ══════════════════════════════════════════════
#  角色分配系统
# ══════════════════════════════════════════════

func _assign_roles() -> void:
	var pp := _player.global_position

	# 判断被追成员
	var chased: Aircraft = null
	if _player.combat_target and is_instance_valid(_player.combat_target):
		for member in members:
			if _player.combat_target == member:
				chased = member
				break
	if not chased:
		var player_fwd := Vector2(sin(_player.heading), -cos(_player.heading))
		var best_dot := -1.0
		for member in members:
			var to_m := (member.global_position - pp).normalized()
			var dot := player_fwd.dot(to_m)
			var dist := member.global_position.distance_to(pp)
			if dot > 0.7 and dist < 2500.0 and dot > best_dot:
				best_dot = dot
				chased = member

	# 按距离排序
	var attackers: Array[Aircraft] = []
	for member in members:
		if member != chased:
			attackers.append(member)
	attackers.sort_custom(func(a: Aircraft, b: Aircraft) -> bool:
		return a.global_position.distance_squared_to(pp) < b.global_position.distance_squared_to(pp))

	# 分配角色（只在变化时配置）
	for member in members:
		var new_role: int
		if member == chased:
			new_role = Role.EVADER
		elif attackers.find(member) < 2:
			new_role = Role.CLOSE_FIGHTER
		else:
			new_role = Role.RANGED_STRIKER

		var old_role: int = member.get_meta("f47_role", Role.NONE)
		var ai: AIController = member._get_ai_controller()
		if not ai:
			continue

		if new_role != old_role:
			member.set_meta("f47_role", new_role)
			_apply_role(member, ai, new_role, chased != null)

		_maintain_role(member, ai, new_role, pp, chased != null)

# ══════════════════════════════════════════════
#  角色配置（子类可覆盖）
# ══════════════════════════════════════════════

## 角色切换时一次性配置
func _apply_role(member: Aircraft, ai: AIController, role: int, has_chased: bool) -> void:
	match role:
		Role.EVADER:
			ai.bvr_only = true
			ai.boss_attacker = false
			member.prefer_gun_mode = false
		Role.CLOSE_FIGHTER:
			ai.bvr_only = false
			ai.boss_attacker = true
			member.prefer_gun_mode = true
			_configure_close_fighter_combat(member)
			ai.aggression = 1.0 if has_chased else 0.95
			ai.self_preservation = 0.05 if has_chased else 0.15
		Role.RANGED_STRIKER:
			ai.bvr_only = false
			ai.boss_attacker = true
			member.prefer_gun_mode = false
			_configure_ranged_striker_combat(member)
			ai.aggression = 1.0 if has_chased else 0.95
			ai.self_preservation = 0.05 if has_chased else 0.10

## 每帧维护
func _maintain_role(member: Aircraft, ai: AIController, role: int, pp: Vector2, _has_chased: bool) -> void:
	match role:
		Role.EVADER:
			# Herbst 活动中不干预
			var hm: HerbstManeuver = member.get_herbst()
			if hm and (hm.is_active or hm.counterattack_timer > 0.0):
				return
			var dist := member.global_position.distance_to(pp)
			if dist > ranged_max_distance:
				var side_dir := Vector2(sin(_player.heading + PI / 2.0), -cos(_player.heading + PI / 2.0))
				ai.waypoints = PackedVector2Array([pp + side_dir * 1800.0])
				member.is_afterburner = true
			else:
				var flee_dir := (member.global_position - pp).normalized()
				if flee_dir.length_squared() < 0.1:
					flee_dir = Vector2(randf_range(-1, 1), randf_range(-1, 1)).normalized()
				ai.waypoints = PackedVector2Array([pp + flee_dir * standoff_radius_max])
			ai.current_waypoint_index = 0

		Role.CLOSE_FIGHTER, Role.RANGED_STRIKER:
			_force_engage(member, ai)
			ai.waypoints = PackedVector2Array([pp])
			ai.current_waypoint_index = 0
			var dist := member.global_position.distance_to(pp)
			if dist > force_pursuit_distance:
				member.is_afterburner = true
				if ai._tactic != AIController.EngageTactic.LEAD_PURSUIT:
					ai._apply_new_tactic(AIController.EngageTactic.LEAD_PURSUIT)

## 确保 BOSS 在 ENGAGE 状态
func _force_engage(member: Aircraft, ai: AIController) -> void:
	ai.boss_attacker = true
	member.tactical_aggression = 1.0
	if ai._state != AIController.AIState.ENGAGE:
		ai._state = AIController.AIState.ENGAGE
		ai._current_target = _player
		member.combat_target = _player
		ai._engage_timer = 0.0
		ai._cooldown_timer = 0.0
		ai._tactic_timer = 0.0
		ai._tactic_min_duration = 0.0
	elif not ai._current_target or not is_instance_valid(ai._current_target) or ai._current_target.is_destroyed:
		ai._current_target = _player
		member.combat_target = _player

# ══════════════════════════════════════════════
#  隐形系统
# ══════════════════════════════════════════════

func _update_cloak(delta: float) -> void:
	if cloak_active:
		cloak_remaining -= delta
		for member in members:
			if cloak_remaining > cloak_duration - cloak_fade:
				var fade_progress := (cloak_duration - cloak_remaining) / cloak_fade
				member._cloak_alpha = 1.0 - clampf(fade_progress, 0.0, 1.0)
				member.is_cloaked = fade_progress >= 1.0
			elif cloak_remaining < cloak_fade:
				var fade_progress := cloak_remaining / cloak_fade
				member._cloak_alpha = 1.0 - clampf(fade_progress, 0.0, 1.0)
				member.is_cloaked = fade_progress >= 0.5
			else:
				member._cloak_alpha = 0.0
				member.is_cloaked = true
		if cloak_remaining <= 0.0:
			cloak_active = false
			cloak_timer = cloak_cycle
			for member in members:
				member.is_cloaked = false
				member._cloak_alpha = 1.0
			EventLogger.log_event("BOSS", boss_name, "cloak deactivated")
	else:
		cloak_timer -= delta
		var should_cloak := cloak_timer <= 0.0
		if not should_cloak and cloak_timer < cloak_cycle - 10.0:
			if _missile_mgr and _has_incoming_missile():
				should_cloak = true
				EventLogger.log_event("BOSS", boss_name, "emergency cloak (incoming missile)")
		if should_cloak and tactic != Tactic.INTRO:
			cloak_active = true
			cloak_remaining = cloak_duration
			if _player and is_instance_valid(_player):
				if _player.combat_target and is_instance_valid(_player.combat_target):
					for member in members:
						if _player.combat_target == member:
							_player.clear_combat_target()
							break
			EventLogger.log_event("BOSS", boss_name, "cloak activated (%.1fs)" % cloak_duration)

	var cloak_ready := cloak_active or cloak_timer <= 0.0
	for member in members:
		member.suppress_flares = cloak_ready

# ══════════════════════════════════════════════
#  INTRO 阶段
# ══════════════════════════════════════════════

func _process_intro() -> void:
	if tactic_timer <= 0.0:
		for member in members:
			member.remove_meta("boss_intro")
			var ai: AIController = member._get_ai_controller()
			if ai:
				ai.enable_combat = true
		tactic = Tactic.COMBAT
		EventLogger.log_event("BOSS", boss_name, "intro → COMBAT")

# ══════════════════════════════════════════════
#  工具方法
# ══════════════════════════════════════════════

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

## HUD 用：获取全部成员（含已击毁）
func get_display_members() -> Array:
	return all_members

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
