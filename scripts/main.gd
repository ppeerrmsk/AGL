extends Node2D

const ZOOM_MIN := 0.1
const ZOOM_MAX := 5.0
const ZOOM_STEP := 0.1
const GRID_SIZE := 200.0  ## 网格间距（像素）
const GRID_COLOR := Color(0.55, 0.55, 0.52, 0.25)

## 地形类型枚举
enum TerrainType { DEEP_OCEAN, OCEAN, COAST, LOWLAND, PLAINS, HILLS, HIGHLANDS, MOUNTAINS }

## 地形颜色 - 纸质航图风格，低对比度，米白/淡绿基调
const TERRAIN_COLORS := {
	TerrainType.DEEP_OCEAN: Color(0.76, 0.80, 0.78, 1.0),    # 深水
	TerrainType.OCEAN: Color(0.78, 0.82, 0.80, 1.0),          # 浅水
	TerrainType.COAST: Color(0.80, 0.83, 0.78, 1.0),          # 海岸
	TerrainType.LOWLAND: Color(0.82, 0.84, 0.77, 1.0),        # 低地
	TerrainType.PLAINS: Color(0.84, 0.85, 0.78, 1.0),         # 平原
	TerrainType.HILLS: Color(0.83, 0.82, 0.75, 1.0),          # 丘陵
	TerrainType.HIGHLANDS: Color(0.80, 0.78, 0.72, 1.0),      # 高地
	TerrainType.MOUNTAINS: Color(0.77, 0.75, 0.70, 1.0),      # 山脉
}

## 地形单元格大小（像素）
const TERRAIN_CELL := 400.0

## 噪声种子，用于生成可复现的地形
var terrain_seed: int = 42
var _noise: FastNoiseLite
var _cloud_noise: FastNoiseLite

@onready var camera: Camera2D = $Camera2D
@onready var bullet_manager: BulletManager = $BulletManager
@onready var missile_manager: MissileManager = $MissileManager

var selected_aircraft: Array[Aircraft] = []
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var target_zoom: float = 1.0

var _hovered_unit: CombatUnit = null
const HOVER_RADIUS := 30.0  ## 鼠标悬停判定半径（像素）

## ── 编队系统 ──
var squads: Array[Squad] = []
var active_squad: Squad = null
var _aircraft_scene: PackedScene
var _player_params: Resource
var _enemy_params: Resource
const LOD_OFFSCREEN_MARGIN := 200.0  ## 屏幕外判定余量（像素）

func _ready() -> void:
	target_zoom = camera.zoom.x
	_init_noise()
	_aircraft_scene = preload("res://scenes/aircraft.tscn")
	_player_params = preload("res://resources/default_fighter.tres")
	_enemy_params = preload("res://resources/enemy_fighter.tres")
	_auto_select_player_aircraft()

func _init_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = terrain_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0006  # 低频率 → 大片连续的生态区域
	_noise.fractal_octaves = 2  # 少分形层 → 更平滑的过渡
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.3

	_cloud_noise = FastNoiseLite.new()
	_cloud_noise.seed = terrain_seed + 100
	_cloud_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cloud_noise.frequency = 0.0008
	_cloud_noise.fractal_octaves = 2

func _auto_select_player_aircraft() -> void:
	for child in get_children():
		if child is Aircraft:
			child.bullet_manager = bullet_manager
			child.missile_manager = missile_manager
			if child.team == 0 and selected_aircraft.is_empty():
				child.selected = true
				selected_aircraft.append(child)

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
				target_zoom = clampf(target_zoom * (1.0 + ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				target_zoom = clampf(target_zoom * (1.0 - ZOOM_STEP), ZOOM_MIN, ZOOM_MAX)
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
		var delta := event.relative / camera.zoom
		camera.global_position -= delta
	_update_hover(event.global_position)

func _on_left_click(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)

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
	var best_dist := HOVER_RADIUS
	var best: CombatUnit = null
	for child in get_children():
		if child is CombatUnit and child.team != 0 and not child.is_destroyed:
			var d := world_pos.distance_to(child.global_position)
			if d < best_dist:
				best_dist = d
				best = child
	return best

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var viewport := get_viewport()
	var canvas_transform := viewport.get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos

func _process(delta: float) -> void:
	var current_zoom := camera.zoom.x
	var new_zoom := lerpf(current_zoom, target_zoom, delta * 10.0)
	camera.zoom = Vector2(new_zoom, new_zoom)
	_cleanup_references()
	_cleanup_squads()
	_update_aircraft_list()
	_update_radar_locks(delta)
	_update_lod()
	queue_redraw()

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

func _update_hover(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)
	# 清除旧悬停
	if _hovered_unit and is_instance_valid(_hovered_unit):
		_hovered_unit.is_hovered = false
	_hovered_unit = null

	var best_dist := HOVER_RADIUS
	for child in get_children():
		if child is CombatUnit:
			var d := world_pos.distance_to(child.global_position)
			if d < best_dist:
				best_dist = d
				_hovered_unit = child

	if _hovered_unit:
		_hovered_unit.is_hovered = true

func _update_radar_locks(delta: float) -> void:
	# 收集所有战斗单位（飞机 + 地面单位）
	var all_units: Array[CombatUnit] = []
	for child in get_children():
		if child is CombatUnit:
			all_units.append(child)

	# 重置锁定状态
	for unit in all_units:
		unit.is_locked = false
		unit.locked_by.clear()

	# 对每个单位，检查其雷达锥内的敌方单位
	for unit in all_units:
		# 清理无效目标
		var keys_to_remove: Array = []
		for key in unit.radar_targets:
			if not is_instance_valid(key):
				keys_to_remove.append(key)
		for key in keys_to_remove:
			unit.radar_targets.erase(key)

		for other in all_units:
			if other == unit or other.team == unit.team:
				continue
			if other.is_lock_immune():
				unit.radar_targets.erase(other)
				continue

			if unit.is_in_radar_cone(other.global_position):
				# 在锥内：累加照射时间（低空目标更难锁定）
				var lock_rate := _lock_rate_for_tier(other.get_altitude_tier())
				var prev: float = unit.radar_targets.get(other, 0.0)
				unit.radar_targets[other] = prev + delta * lock_rate
			else:
				# 不在锥内：逐渐衰减（1.5秒记忆窗口），而非瞬间清零
				# 防止目标在雷达锥边缘反复进出导致锁定震荡
				var prev: float = unit.radar_targets.get(other, 0.0)
				if prev > 0.0:
					unit.radar_targets[other] = prev - delta / 1.5  # 衰减速率 = 累积速率的 2/3
					if unit.radar_targets[other] <= 0.0:
						unit.radar_targets.erase(other)
				else:
					unit.radar_targets.erase(other)

	# 根据累计时间判定锁定
	for unit in all_units:
		var lock_time_val: float
		if unit is Aircraft and unit.params:
			lock_time_val = unit.params.lock_time
		elif unit is GroundUnit and unit.params:
			lock_time_val = unit.params.lock_time
		else:
			lock_time_val = 3.0
		for target in unit.radar_targets:
			if unit.radar_targets[target] >= lock_time_val:
				var t: CombatUnit = target
				t.is_locked = true
				t.locked_by.append(unit)

## 低空/地面目标锁定速率衰减
static func _lock_rate_for_tier(tier: int) -> float:
	match tier:
		CombatUnit.AltitudeTier.GROUND:
			return 0.5  # 地面杂波严重干扰
		CombatUnit.AltitudeTier.LOW:
			return 0.7  # 低空杂波，锁定时间延长 ~43%
		_:
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

	var sq := Squad.new()
	sq.leader = leader
	sq.add_member(leader)

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

		# AI 控制器：编队���随
		var ai := AIController.new()
		ai.name = "AI_Wing%d" % i
		ai.aircraft = ac
		ai.squad = sq
		ai.squad_index = i
		ai.enable_combat = true
		ai.evade_missiles = true
		ai.aggression = randf_range(0.5, 0.8)
		ai.skill_level = randf_range(0.6, 0.85)
		ai.composure = randf_range(0.5, 0.8)
		ai.focus = randf_range(0.5, 0.8)
		ai.self_preservation = randf_range(0.3, 0.6)
		ai.patrol_altitude = leader.altitude
		ai._state = AIController.AIState.SQUAD_FOLLOW
		ac.add_child(ai)

		sq.add_member(ac)
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

	var sq := Squad.new()
	var leader_ac: Aircraft = null

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

		if i == 0:
			# 长机：正常巡逻AI
			leader_ac = enemy
			sq.leader = enemy
		else:
			# 僚机：编队跟随
			ai.squad = sq
			ai.squad_index = i
			ai._state = AIController.AIState.SQUAD_FOLLOW

		enemy.add_child(ai)
		sq.add_member(enemy)

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

# ══════════════════════════════════════════════
#  绘制
# ══════════════════════════════════════════════

func _draw() -> void:
	_draw_terrain()
	_draw_grid()

## 根据噪声值映射地形类型
func _get_terrain_type(noise_val: float) -> TerrainType:
	if noise_val < -0.30:
		return TerrainType.DEEP_OCEAN
	elif noise_val < -0.12:
		return TerrainType.OCEAN
	elif noise_val < -0.02:
		return TerrainType.COAST
	elif noise_val < 0.10:
		return TerrainType.LOWLAND
	elif noise_val < 0.22:
		return TerrainType.PLAINS
	elif noise_val < 0.34:
		return TerrainType.HILLS
	elif noise_val < 0.46:
		return TerrainType.HIGHLANDS
	else:
		return TerrainType.MOUNTAINS

func _draw_terrain() -> void:
	var viewport_size := get_viewport_rect().size / camera.zoom
	var cam_pos := camera.global_position
	var half := viewport_size / 2.0

	var left := cam_pos.x - half.x
	var right := cam_pos.x + half.x
	var top := cam_pos.y - half.y
	var bottom := cam_pos.y + half.y

	# 按地形单元格绘制
	var start_x := snappedf(left, TERRAIN_CELL) - TERRAIN_CELL
	var start_y := snappedf(top, TERRAIN_CELL) - TERRAIN_CELL

	var cx := start_x
	while cx <= right + TERRAIN_CELL:
		var cy := start_y
		while cy <= bottom + TERRAIN_CELL:
			# 取单元格中心点的噪声值
			var center_x := cx + TERRAIN_CELL * 0.5
			var center_y := cy + TERRAIN_CELL * 0.5
			var noise_val := _noise.get_noise_2d(center_x, center_y)

			var terrain := _get_terrain_type(noise_val)
			var base_color: Color = TERRAIN_COLORS[terrain]

			# 用噪声微调颜色，增加自然感
			var variation := _noise.get_noise_2d(center_x * 2.3, center_y * 2.3) * 0.04
			var cell_color := Color(
				clampf(base_color.r + variation, 0.0, 1.0),
				clampf(base_color.g + variation, 0.0, 1.0),
				clampf(base_color.b + variation, 0.0, 1.0),
				base_color.a
			)

			draw_rect(Rect2(cx, cy, TERRAIN_CELL, TERRAIN_CELL), cell_color)

			# 薄雾叠加 - 极淡
			var cloud_val := _cloud_noise.get_noise_2d(center_x, center_y)
			if cloud_val > 0.25:
				var cloud_alpha := remap(cloud_val, 0.25, 0.7, 0.0, 0.08)
				cloud_alpha = clampf(cloud_alpha, 0.0, 0.08)
				draw_rect(Rect2(cx, cy, TERRAIN_CELL, TERRAIN_CELL), Color(1.0, 1.0, 0.98, cloud_alpha))

			cy += TERRAIN_CELL
		cx += TERRAIN_CELL

func _draw_grid() -> void:
	var viewport_size := get_viewport_rect().size / camera.zoom
	var cam_pos := camera.global_position
	var half := viewport_size / 2.0

	var left := cam_pos.x - half.x
	var right := cam_pos.x + half.x
	var top := cam_pos.y - half.y
	var bottom := cam_pos.y + half.y

	var start_x := snappedf(left, GRID_SIZE) - GRID_SIZE
	var start_y := snappedf(top, GRID_SIZE) - GRID_SIZE

	var x := start_x
	while x <= right + GRID_SIZE:
		draw_line(Vector2(x, top - GRID_SIZE), Vector2(x, bottom + GRID_SIZE), GRID_COLOR, 1.0)
		x += GRID_SIZE

	var y := start_y
	while y <= bottom + GRID_SIZE:
		draw_line(Vector2(left - GRID_SIZE, y), Vector2(right + GRID_SIZE, y), GRID_COLOR, 1.0)
		y += GRID_SIZE
