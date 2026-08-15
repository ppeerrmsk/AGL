extends Node2D

@onready var camera: Camera2D = $Camera2D
@onready var bullet_manager: BulletManager = $BulletManager
@onready var missile_manager: MissileManager = $MissileManager

var selected_aircraft: Array[Aircraft] = []
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO

## ── 共享模块 ──
var _terrain: TerrainRenderer
var _camera_ctrl: CameraController
var _weather: WeatherSystem

## ── 编队系统 ──
var squads: Array[Squad] = []
var active_squad: Squad = null
var _aircraft_scene: PackedScene
var _player_params: Resource
var _enemy_params: Resource
const LOD_OFFSCREEN_MARGIN := 200.0  ## 屏幕外判定余量（像素）

# ── 雷达锁定节流 + 战斗单位列表缓存 ──
const RADAR_LOCK_INTERVAL := 0.2
var _radar_lock_accum: float = 0.0
var _all_combat_units_cache: Array[CombatUnit] = []
var _sandbox_time: float = 0.0

func _ready() -> void:
	# 地形渲染器（最先添加，绘制在最底层）
	_terrain = TerrainRenderer.new()
	_terrain.show_behind_parent = true
	add_child(_terrain)
	_terrain.setup(camera)
	move_child(_terrain, 0)

	# 天气系统（高空云层，绘制在地形之上、单位之下）
	_weather = WeatherSystem.new()
	_weather.show_behind_parent = true
	add_child(_weather)
	_weather.setup(camera)
	_weather.add_to_group("weather")
	move_child(_weather, 1)

	# 相机控制器
	_camera_ctrl = CameraController.new()
	add_child(_camera_ctrl)
	_camera_ctrl.setup(camera)

	_aircraft_scene = preload("res://scenes/aircraft.tscn")
	_player_params = preload("res://resources/default_fighter.tres")
	_enemy_params = preload("res://resources/enemy_fighter.tres")
	_auto_select_player_aircraft()

func _auto_select_player_aircraft() -> void:
	for child in get_children():
		if child is Aircraft:
			child.bullet_manager = bullet_manager
			child.missile_manager = missile_manager
			if child.team == 0 and selected_aircraft.is_empty():
				child.selected = true
				selected_aircraft.append(child)
				AircraftRenderer.player_ref = child

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
				return
			KEY_F1:
				_spawn_friendly_squad(4)
				return
			KEY_F2:
				_spawn_friendly_squad(2)
				return
			KEY_F3:
				_spawn_enemies(2)
				return
			KEY_F4:
				_spawn_enemies(4)
				return
			KEY_F5:
				_cycle_formation()
				return
			KEY_F9:
				_dump_combat_log()
				return
	if event is InputEventMouseButton:
		_handle_mouse_button(event)
	elif event is InputEventMouseMotion:
		_handle_mouse_motion(event)

func _handle_mouse_button(event: InputEventMouseButton) -> void:
	match event.button_index:
		MOUSE_BUTTON_WHEEL_UP:
			if event.pressed:
				_camera_ctrl.handle_zoom_input(1.0 + CameraController.ZOOM_STEP)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_camera_ctrl.handle_zoom_input(1.0 - CameraController.ZOOM_STEP)
		MOUSE_BUTTON_LEFT:
			if event.pressed:
				_on_left_click(event.global_position)
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				_on_right_click()
		MOUSE_BUTTON_MIDDLE:
			is_dragging = event.pressed
			if event.pressed:
				drag_start = event.global_position

func _handle_mouse_motion(event: InputEventMouseMotion) -> void:
	if is_dragging:
		_camera_ctrl.handle_drag(event.relative)
	_camera_ctrl.update_hover(event.global_position, get_children())

func _on_left_click(screen_pos: Vector2) -> void:
	var world_pos := _camera_ctrl.screen_to_world(screen_pos)

	# 优先检测点击附近是否有敌方飞机
	var enemy := _find_enemy_near(world_pos)
	if enemy:
		for ac in selected_aircraft:
			if is_instance_valid(ac) and not ac.is_destroyed:
				ac.set_combat_target(enemy)
		return

	# 无敌机：普通移动指令，清除战斗目标
	for ac in selected_aircraft:
		if is_instance_valid(ac) and not ac.is_destroyed:
			ac.clear_combat_target()
			ac.target_position = world_pos

func _on_right_click() -> void:
	for ac in selected_aircraft:
		if is_instance_valid(ac):
			ac.clear_combat_target()
			ac.target_position = Vector2.INF

## 查找世界坐标附近的敌方飞机
func _find_enemy_near(world_pos: Vector2) -> CombatUnit:
	var best_dist := CameraController.HOVER_RADIUS
	var best: CombatUnit = null
	for child in get_children():
		if child is CombatUnit and child.team != 0 and not child.is_destroyed:
			var d := world_pos.distance_to(child.global_position)
			if d < best_dist:
				best_dist = d
				best = child
	return best

func _process(delta: float) -> void:
	_sandbox_time += delta
	_camera_ctrl.update_zoom(delta)
	_cleanup_references()
	_cleanup_squads()
	_update_aircraft_list()
	_update_radar_locks(delta)
	_update_lod()
	# TerrainRenderer 需要跟随相机重绘
	_terrain.queue_redraw()

func _cleanup_references() -> void:
	var valid: Array[Aircraft] = []
	for ac in selected_aircraft:
		if is_instance_valid(ac):
			valid.append(ac)
	selected_aircraft = valid

func _update_aircraft_list() -> void:
	var all_aircraft: Array[Aircraft] = []
	var all_units: Array[CombatUnit] = []
	for child in get_children():
		if child is Aircraft:
			all_aircraft.append(child)
			all_units.append(child)
		elif child is GroundUnit:
			all_units.append(child)
	bullet_manager.combat_unit_list = all_units
	missile_manager.target_list = all_units
	_all_combat_units_cache = all_units
	CombatUnit.all_units = all_units

func _cached_is_in_cloud(unit: CombatUnit) -> bool:
	if not _weather:
		return false
	var now := _sandbox_time
	var pos := unit.global_position
	if now - unit._cloud_cache_time < 0.3 and pos.distance_squared_to(unit._cloud_cache_pos) < 40000.0:
		return unit._cloud_cache_result
	unit._cloud_cache_time = now
	unit._cloud_cache_pos = pos
	unit._cloud_cache_result = _weather.is_in_cloud(pos)
	return unit._cloud_cache_result

func _update_radar_locks(delta: float) -> void:
	# 节流：每 RADAR_LOCK_INTERVAL 秒跑一次 O(N²) 循环
	_radar_lock_accum += delta
	if _radar_lock_accum < RADAR_LOCK_INTERVAL:
		return
	var step_delta := _radar_lock_accum
	_radar_lock_accum = 0.0

	var all_units := _all_combat_units_cache

	# 重置锁定状态
	for unit in all_units:
		unit.is_locked = false
		unit.locked_by.clear()
		unit.incoming_lock_progress = 0.0

	# 对每个单位，检查其雷达锥内的敌方单位
	for unit in all_units:
		# 无主雷达锁定武器的飞机不当 shooter；仍保留为 victim。
		if unit is Aircraft:
			var shooter := unit as Aircraft
			if shooter.params == null or not shooter.params.has_lock_capable_weapon():
				shooter.radar_targets.clear()
				continue
		# 清理无效目标
		var keys_to_remove: Array = []
		for key in unit.radar_targets:
			if not is_instance_valid(key):
				keys_to_remove.append(key)
		for key in keys_to_remove:
			unit.radar_targets.erase(key)

		# JAM 状态：被干扰者完全无法累积锁定（与 survivor_mode.gd:1417-1420 对称）
		# 详见 docs/changelogs/2026-05-10-secondary-slot-revival.md（一致性补丁段）
		if unit.status_jam_active:
			unit.radar_targets.clear()
			continue

		for other in all_units:
			if other == unit or other.team == unit.team:
				continue
			if other.is_lock_immune():
				unit.radar_targets.erase(other)
				continue

			var in_cone := unit.is_in_radar_cone(other.global_position)
			# ECM 吊舱（战区奖励）：目标自身缩短敌方雷达有效距离
			if in_cone and other is Aircraft and other.ecm_range_mult < 1.0 \
					and unit.params and "radar_range" in unit.params:
				var ecm_range: float = unit.params.radar_range * other.ecm_range_mult
				if unit.global_position.distance_to(other.global_position) > ecm_range:
					in_cone = false
			if in_cone:
				# 在锥内：累加照射时间（低空目标更难锁定）
				var lock_rate := _lock_rate_for_target(other)
				# 云层锁定衰减（与 survivor_mode 保持一致）
				if _weather and _cached_is_in_cloud(other):
					if other is Aircraft and other.cloud_lock_stealth:
						lock_rate *= 0.1
					elif other.get_altitude_tier() == CombatUnit.AltitudeTier.HIGH:
						lock_rate *= 0.5
				# 目标自身的锁定抗性（强化吊舱升级）
				if other is Aircraft and other.lock_resistance_mult > 1.0:
					lock_rate /= other.lock_resistance_mult
				# 硬下限：effective_lock_time = threshold / rate ≤ MAX_EFFECTIVE_LOCK_TIME_S
				var shooter_threshold: float = unit.params.lock_time if unit.params else 3.0
				var min_rate: float = shooter_threshold / CombatUnit.MAX_EFFECTIVE_LOCK_TIME_S
				if lock_rate < min_rate:
					lock_rate = min_rate
				var prev: float = unit.radar_targets.get(other, 0.0)
				unit.radar_targets[other] = prev + step_delta * lock_rate
			else:
				# 不在锥内：极短衰减（0.3 秒）—— 仅用于挡住雷达锥边缘 1-2 帧的几何抖动，
				# 不再做"长记忆"。物理直觉：不照射就该丢锁；半主动 SARH 也确实如此。
				# 之前的 1.5s 记忆窗会让 _fire_multi_lock_salvo 对早就脱离锥的"幽灵锁定"
				# 继续发弹（玩家观感"乱射"），改 0.3s 后这些条目快速归零并 erase。
				var prev: float = unit.radar_targets.get(other, 0.0)
				if prev > 0.0:
					unit.radar_targets[other] = prev - step_delta / 0.3
					if unit.radar_targets[other] <= 0.0:
						unit.radar_targets.erase(other)
				else:
					unit.radar_targets.erase(other)

	# 根据累计时间判定锁定
	for unit in all_units:
		var lock_time_val: float
		if unit is Aircraft and unit.params:
			lock_time_val = unit.params.lock_time
			lock_time_val *= unit._executioner_lock_mult()  # 侩子手：×0.90/层
		elif unit is GroundUnit and unit.params:
			lock_time_val = unit.params.lock_time
		else:
			lock_time_val = 3.0
		for target in unit.radar_targets:
			var t: CombatUnit = target
			var progress: float = clampf(unit.radar_targets[target] / lock_time_val, 0.0, 1.0)
			# 沙盒与正式局保持同一口径：第三方 AI 互锁不产生玩家锁框/被锁反应。
			t.accumulate_player_lock_state(unit, progress,
				unit.radar_targets[target] >= lock_time_val)

## 低空飞行目标锁定速率衰减（仅对 Aircraft 生效；地面单位恒定 1.0）
static func _lock_rate_for_target(target: CombatUnit) -> float:
	if not (target is Aircraft):
		return 1.0
	if target.get_altitude_tier() == CombatUnit.AltitudeTier.LOW:
		return 0.7  # 低空杂波，锁定时间延长 ~43%
	return 1.0

# ══════════════════════════════════════════════
#  编队管理
# ══════════════════════════════════════════════

func _cleanup_squads() -> void:
	for sq in squads:
		sq.cleanup()
	# 移除空编队
	var valid_squads: Array[Squad] = []
	for sq in squads:
		if sq.members.size() > 0 and sq.leader:
			valid_squads.append(sq)
	squads = valid_squads
	if active_squad and active_squad not in squads:
		active_squad = squads[0] if squads.size() > 0 else null

## 生成友方小队
func _spawn_friendly_squad(count: int) -> void:
	if selected_aircraft.is_empty():
		return
	var leader: Aircraft = selected_aircraft[0]
	if not is_instance_valid(leader) or leader.is_destroyed:
		return

	var sq := SquadFactory.create()
	SquadFactory.register_leader(sq, leader)

	for i in range(1, count):
		var ac: Aircraft = _aircraft_scene.instantiate()
		ac.params = _player_params.duplicate(true)
		ac.team = 0

		# 在阵型位置生成
		var offset := sq.get_formation_offset(i)
		var rotated := offset.rotated(leader.heading)
		ac.position = leader.global_position + rotated
		ac.initial_heading_deg = rad_to_deg(leader.heading)
		ac.altitude = leader.altitude
		ac.target_altitude = leader.altitude
		ac.bullet_manager = bullet_manager
		ac.missile_manager = missile_manager
		add_child(ac)

		# AI 控制器：编队跟随
		var ai := AIController.new()
		ai.name = "AI_Wing%d" % i
		ai.aircraft = ac
		ai.enable_combat = true
		ai.evade_missiles = true
		ai.aggression = randf_range(0.5, 0.8)
		ai.skill_level = randf_range(0.6, 0.85)
		ai.composure = randf_range(0.5, 0.8)
		ai.focus = randf_range(0.5, 0.8)
		ai.self_preservation = randf_range(0.3, 0.6)
		ai.patrol_altitude = leader.altitude
		ac.add_child(ai)

		SquadFactory.register_wingman(sq, ac)  # 设 squad/squad_index/_state=SQUAD_FOLLOW
		selected_aircraft.append(ac)

	squads.append(sq)
	active_squad = sq

## 生成敌机编队
func _spawn_enemies(count: int) -> void:
	var ref_pos := Vector2.ZERO
	var ref_heading := 0.0
	if selected_aircraft.size() > 0 and is_instance_valid(selected_aircraft[0]):
		ref_pos = selected_aircraft[0].global_position
		ref_heading = selected_aircraft[0].heading

	# 编队中心位置：玩家前方 3000-5000px
	var angle := ref_heading + randf_range(-PI / 4, PI / 4)
	var dist := randf_range(3000.0, 5000.0)
	var spawn_center := ref_pos + Vector2(sin(angle), -cos(angle)) * dist

	# 长机朝向玩家
	var to_player := (ref_pos - spawn_center).normalized()
	var leader_heading := atan2(to_player.x, -to_player.y)
	var patrol_alt := randf_range(4000.0, 7000.0)

	var sq := SquadFactory.create()

	for i in range(count):
		var enemy: Aircraft = _aircraft_scene.instantiate()
		enemy.params = _enemy_params.duplicate(true)
		enemy.team = 1

		if i == 0:
			# 长机
			enemy.position = spawn_center
		else:
			# 僚机：按阵型偏移生成
			var offset := sq.get_formation_offset(i)
			var rotated := offset.rotated(leader_heading)
			enemy.position = spawn_center + rotated

		enemy.initial_heading_deg = rad_to_deg(leader_heading)
		enemy.altitude = patrol_alt
		enemy.target_altitude = patrol_alt
		enemy.bullet_manager = bullet_manager
		enemy.missile_manager = missile_manager
		add_child(enemy)

		# AI
		var ai := AIController.new()
		ai.name = "AI_%s" % enemy.name
		ai.aircraft = enemy
		ai.patrol_altitude = patrol_alt
		ai.waypoints = PackedVector2Array([
			ref_pos + Vector2(800, -800),
			ref_pos + Vector2(800, 800),
			ref_pos + Vector2(-800, 800),
			ref_pos + Vector2(-800, -800),
		])
		ai.enable_combat = true
		ai.evade_missiles = true
		ai.aggression = randf_range(0.4, 0.8)
		ai.engage_cooldown = 12.0
		ai.engage_duration = 25.0
		ai.skill_level = randf_range(0.4, 0.8)
		ai.composure = randf_range(0.3, 0.7)
		ai.focus = randf_range(0.3, 0.8)
		ai.self_preservation = randf_range(0.2, 0.7)
		enemy.add_child(ai)

		if i == 0:
			SquadFactory.register_leader(sq, enemy)
		else:
			SquadFactory.register_wingman(sq, enemy)

	squads.append(sq)

## 切换编队阵型
func _cycle_formation() -> void:
	if active_squad:
		active_squad.cycle_formation()

func _dump_combat_log() -> void:
	var path := EventLogger.dump_to_file()
	if path != "":
		print("Combat log saved: %s" % path)

# ══════════════════════════════════════════════
#  LOD 管理
# ══════════════════════════════════════════════

func _update_lod() -> void:
	var cam_pos := camera.global_position
	var vp_size := get_viewport_rect().size / camera.zoom
	var half := vp_size / 2.0 + Vector2(LOD_OFFSCREEN_MARGIN, LOD_OFFSCREEN_MARGIN)

	# 确定玩家长机
	var player_leader: Aircraft = null
	if selected_aircraft.size() > 0 and is_instance_valid(selected_aircraft[0]):
		player_leader = selected_aircraft[0]

	for child in get_children():
		if not child is Aircraft:
			continue
		var ac: Aircraft = child
		if ac.is_destroyed:
			continue

		var rel := ac.global_position - cam_pos
		var offscreen := absf(rel.x) > half.x or absf(rel.y) > half.y

		if offscreen:
			ac.lod_level = 2
			ac.visible = false
		elif ac == player_leader:
			ac.lod_level = 0
			ac.visible = true
		elif ac.combat_target != null:
			ac.lod_level = 0
			ac.visible = true
		else:
			ac.lod_level = 1
			ac.visible = true
