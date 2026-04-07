extends Node2D

## 生存模式主控制器
## 操控/镜头/武器/雷达 全部与沙盒模式一致
## 在此基础上叠加：敌机波次刷新、经验球、等级升级

# ── 操控常量（与 main.gd 一致）──
const ZOOM_MIN := 0.1
const ZOOM_MAX := 5.0
const ZOOM_STEP := 0.1
const HOVER_RADIUS := 30.0

# ── 地形常量（与 main.gd 一致）──
const GRID_SIZE := 200.0
const GRID_COLOR := Color(0.55, 0.55, 0.52, 0.25)
const TERRAIN_CELL := 400.0

enum TerrainType { DEEP_OCEAN, OCEAN, COAST, LOWLAND, PLAINS, HILLS, HIGHLANDS, MOUNTAINS }

const TERRAIN_COLORS := {
	TerrainType.DEEP_OCEAN: Color(0.76, 0.80, 0.78, 1.0),
	TerrainType.OCEAN: Color(0.78, 0.82, 0.80, 1.0),
	TerrainType.COAST: Color(0.80, 0.83, 0.78, 1.0),
	TerrainType.LOWLAND: Color(0.82, 0.84, 0.77, 1.0),
	TerrainType.PLAINS: Color(0.84, 0.85, 0.78, 1.0),
	TerrainType.HILLS: Color(0.83, 0.82, 0.75, 1.0),
	TerrainType.HIGHLANDS: Color(0.80, 0.78, 0.72, 1.0),
	TerrainType.MOUNTAINS: Color(0.77, 0.75, 0.70, 1.0),
}

# ── 经验球常量 ──
const ORB_MAX := 50
const ORB_PICKUP_DIST := 12.0
const ORB_MAGNET_RADIUS := 100.0
const ORB_MAGNET_SPEED := 400.0
const ORB_LIFETIME := 15.0
const XP_PER_KILL := 20  ## 基础经验值

# ── 场景/资源引用 ──
@onready var camera: Camera2D = $Camera2D
@onready var bullet_manager: BulletManager = $BulletManager
@onready var missile_manager: MissileManager = $MissileManager

var _aircraft_scene: PackedScene
var _player_params_base: AircraftParams
var _enemy_params_base: AircraftParams

# ── 操控状态（与 main.gd 一致）──
var selected_aircraft: Array[Aircraft] = []
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var target_zoom: float = 1.0
var _hovered_aircraft: Aircraft = null

# ── 噪声 ──
var _noise: FastNoiseLite
var _cloud_noise: FastNoiseLite

# ── 生存模式状态 ──
var player_aircraft: Aircraft
var survivor_player: SurvivorPlayer
var xp_orbs: Array[Dictionary] = []  ## { pos: Vector2, value: int, life: float }
var game_time: float = 0.0
var kill_count: int = 0
var is_game_over: bool = false
var is_paused_for_upgrade: bool = false
var _spawn_timer: float = 3.0  ## 初始延迟
var upgrade_stacks: Dictionary = {}
var _prev_enemy_count: int = 0  ## 上一帧敌人数量，用于检测击杀

# ── HUD / UI ──
var hud: SurvivorHUD
var upgrade_ui: SurvivorUpgradeUI

func _ready() -> void:
	_init_noise()
	target_zoom = camera.zoom.x

	_aircraft_scene = preload("res://scenes/aircraft.tscn")
	_player_params_base = preload("res://resources/default_fighter.tres")
	_enemy_params_base = preload("res://resources/enemy_fighter.tres")

	# 生成玩家飞机
	player_aircraft = _aircraft_scene.instantiate()
	player_aircraft.params = _player_params_base.duplicate(true)  # 深拷贝，升级修改不影响原资源
	player_aircraft.team = 0
	player_aircraft.position = Vector2.ZERO
	player_aircraft.bullet_manager = bullet_manager
	player_aircraft.missile_manager = missile_manager
	player_aircraft.selected = true
	add_child(player_aircraft)
	selected_aircraft.append(player_aircraft)

	# 生存模式状态
	survivor_player = SurvivorPlayer.new()
	survivor_player.aircraft = player_aircraft
	survivor_player.leveled_up.connect(_on_player_leveled_up)
	add_child(survivor_player)

	# HUD
	hud = SurvivorHUD.new()
	hud.survivor_player = survivor_player
	add_child(hud)

	# 升级UI
	upgrade_ui = SurvivorUpgradeUI.new()
	upgrade_ui.upgrade_selected.connect(_on_upgrade_selected)
	add_child(upgrade_ui)

# ══════════════════════════════════════════════
#  输入处理（与 main.gd 一致）
# ══════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	if is_game_over or is_paused_for_upgrade:
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

	# 优先检测点击附近的敌方飞机
	var enemy := _find_enemy_near(world_pos)
	if enemy:
		for ac in selected_aircraft:
			if is_instance_valid(ac) and not ac.is_destroyed:
				ac.set_combat_target(enemy)
		return

	# 无敌机：普通移动指令
	for ac in selected_aircraft:
		if is_instance_valid(ac) and not ac.is_destroyed:
			ac.clear_combat_target()
			ac.target_position = world_pos

func _on_right_click() -> void:
	for ac in selected_aircraft:
		if is_instance_valid(ac):
			ac.clear_combat_target()
			ac.target_position = Vector2.INF

func _find_enemy_near(world_pos: Vector2) -> Aircraft:
	var best_dist := HOVER_RADIUS
	var best: Aircraft = null
	for child in get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			var d := world_pos.distance_to(child.global_position)
			if d < best_dist:
				best_dist = d
				best = child
	return best

func _screen_to_world(screen_pos: Vector2) -> Vector2:
	var viewport := get_viewport()
	var canvas_transform := viewport.get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos

func _update_hover(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)
	if _hovered_aircraft and is_instance_valid(_hovered_aircraft):
		_hovered_aircraft.is_hovered = false
	_hovered_aircraft = null

	var best_dist := HOVER_RADIUS
	for child in get_children():
		if child is Aircraft:
			var d := world_pos.distance_to(child.global_position)
			if d < best_dist:
				best_dist = d
				_hovered_aircraft = child

	if _hovered_aircraft:
		_hovered_aircraft.is_hovered = true

# ══════════════════════════════════════════════
#  主循环
# ══════════════════════════════════════════════

func _process(delta: float) -> void:
	# 相机缩放平滑
	var current_zoom := camera.zoom.x
	var new_zoom := lerpf(current_zoom, target_zoom, delta * 10.0)
	camera.zoom = Vector2(new_zoom, new_zoom)

	_cleanup_references()
	_update_aircraft_list()
	_update_radar_locks(delta)
	queue_redraw()

func _physics_process(delta: float) -> void:
	if is_game_over or is_paused_for_upgrade:
		return

	game_time += delta

	# 检查玩家是否死亡
	if player_aircraft and player_aircraft.is_destroyed and not is_game_over:
		_on_player_died()
		return

	# 检测击杀（比较当前敌人数与上一帧）
	_detect_kills()

	# 刷怪
	_update_spawner(delta)

	# 经验球
	_update_xp_orbs(delta)

	# 更新HUD
	hud.game_time = game_time
	hud.kill_count = kill_count

func _cleanup_references() -> void:
	var valid: Array[Aircraft] = []
	for ac in selected_aircraft:
		if is_instance_valid(ac):
			valid.append(ac)
	selected_aircraft = valid

func _update_aircraft_list() -> void:
	var all: Array[Aircraft] = []
	for child in get_children():
		if child is Aircraft:
			all.append(child)
	bullet_manager.aircraft_list = all
	missile_manager.aircraft_list = all

func _update_radar_locks(delta: float) -> void:
	var all_aircraft: Array[Aircraft] = []
	for child in get_children():
		if child is Aircraft:
			all_aircraft.append(child)

	for ac in all_aircraft:
		ac.is_locked = false
		ac.locked_by.clear()

	for ac in all_aircraft:
		var keys_to_remove: Array = []
		for key in ac.radar_targets:
			if not is_instance_valid(key):
				keys_to_remove.append(key)
		for key in keys_to_remove:
			ac.radar_targets.erase(key)

		for other in all_aircraft:
			if other == ac or other.team == ac.team:
				continue
			if ac.is_in_radar_cone(other.global_position):
				var prev: float = ac.radar_targets.get(other, 0.0)
				ac.radar_targets[other] = prev + delta
			else:
				var prev: float = ac.radar_targets.get(other, 0.0)
				if prev > 0.0:
					ac.radar_targets[other] = prev - delta / 1.5
					if ac.radar_targets[other] <= 0.0:
						ac.radar_targets.erase(other)
				else:
					ac.radar_targets.erase(other)

	for ac in all_aircraft:
		var lock_time_val: float = ac.params.lock_time if ac.params else 3.0
		for target in ac.radar_targets:
			if ac.radar_targets[target] >= lock_time_val:
				var t: Aircraft = target
				t.is_locked = true
				t.locked_by.append(ac)

# ══════════════════════════════════════════════
#  刷怪系统
# ══════════════════════════════════════════════

func _update_spawner(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return
	if not player_aircraft or player_aircraft.is_destroyed:
		return

	var interval := lerpf(
		SurvivorData.BASE_SPAWN_INTERVAL,
		SurvivorData.MIN_SPAWN_INTERVAL,
		clampf(survivor_player.level / 20.0, 0.0, 1.0)
	)
	_spawn_timer = interval

	var count := SurvivorData.ENEMIES_PER_WAVE_BASE + int(survivor_player.level * SurvivorData.ENEMIES_PER_WAVE_GROWTH)

	for _i in range(count):
		_spawn_enemy()

func _spawn_enemy() -> void:
	var enemy: Aircraft = _aircraft_scene.instantiate()
	var params: AircraftParams = _enemy_params_base.duplicate(true)

	# 根据等级缩放敌人属性
	var scale := SurvivorData.enemy_scale_for_level(survivor_player.level)
	params.max_hp *= float(scale["hp_mult"])
	if params.missile:
		params.missile.max_count += int(scale["missile_add"])
	if params.gun:
		params.gun.bullet_damage *= float(scale["gun_damage_mult"])

	enemy.params = params
	enemy.team = 1

	# 在玩家周围随机方向生成
	var angle := randf() * TAU
	var spawn_pos := player_aircraft.global_position + Vector2(cos(angle), sin(angle)) * SurvivorData.SPAWN_DISTANCE
	enemy.position = spawn_pos

	# 朝向玩家
	var to_player := (player_aircraft.global_position - spawn_pos).normalized()
	enemy.initial_heading_deg = rad_to_deg(atan2(to_player.x, -to_player.y))

	add_child(enemy)

	# 注入管理器
	enemy.bullet_manager = bullet_manager
	enemy.missile_manager = missile_manager

	# AI 控制器：围绕玩家巡逻
	var ai := AIController.new()
	ai.name = "AI_%s" % enemy.name
	ai.aircraft = enemy
	ai.patrol_altitude = randf_range(4000.0, 8000.0)
	# 航点围绕玩家当前位置
	var pp := player_aircraft.global_position
	ai.waypoints = PackedVector2Array([
		pp + Vector2(1200, -1200),
		pp + Vector2(1200, 1200),
		pp + Vector2(-1200, 1200),
		pp + Vector2(-1200, -1200),
	])
	ai.enable_combat = true
	ai.evade_missiles = true
	ai.aggression = randf_range(0.4, 0.8)
	# 飞行员能力随等级提升
	var level_bonus := clampf(float(survivor_player.level) / 20.0, 0.0, 0.3)
	ai.skill_level = clampf(randf_range(0.3, 0.65) + level_bonus, 0.3, 0.95)
	ai.composure = clampf(randf_range(0.2, 0.55) + level_bonus, 0.2, 0.9)
	ai.focus = clampf(randf_range(0.3, 0.7) + level_bonus * 0.5, 0.3, 0.9)
	ai.self_preservation = randf_range(0.2, 0.7)
	enemy.add_child(ai)

# ══════════════════════════════════════════════
#  击杀检测 & 经验球
# ══════════════════════════════════════════════

func _detect_kills() -> void:
	# 统计当前存活敌人，检测被摧毁的敌人并生成经验球
	for child in get_children():
		if child is Aircraft and child.team != 0 and child.is_destroyed:
			# 检查是否已经处理过（用 meta 标记）
			if not child.has_meta("xp_dropped"):
				child.set_meta("xp_dropped", true)
				var xp_value := XP_PER_KILL + survivor_player.level * 5
				xp_orbs.append({
					"pos": child.global_position,
					"value": xp_value,
					"life": ORB_LIFETIME,
				})
				kill_count += 1

func _update_xp_orbs(delta: float) -> void:
	if not player_aircraft or player_aircraft.is_destroyed:
		return
	var player_pos := player_aircraft.global_position
	var kept: Array[Dictionary] = []

	for orb in xp_orbs:
		orb["life"] = float(orb["life"]) - delta
		if float(orb["life"]) <= 0.0:
			continue

		var orb_pos: Vector2 = orb["pos"]
		var dist := orb_pos.distance_to(player_pos)

		# 磁铁吸引
		if dist < ORB_MAGNET_RADIUS:
			var dir := (player_pos - orb_pos).normalized()
			orb["pos"] = orb_pos + dir * ORB_MAGNET_SPEED * delta

		# 拾取
		orb_pos = orb["pos"]
		dist = orb_pos.distance_to(player_pos)
		if dist < ORB_PICKUP_DIST:
			survivor_player.add_xp(int(orb["value"]))
			continue

		kept.append(orb)

	xp_orbs = kept

	while xp_orbs.size() > ORB_MAX:
		survivor_player.add_xp(int(xp_orbs[0]["value"]))
		xp_orbs.remove_at(0)

# ══════════════════════════════════════════════
#  升级流程
# ══════════════════════════════════════════════

func _on_player_leveled_up(_new_level: int) -> void:
	is_paused_for_upgrade = true
	get_tree().paused = true

	var available: Array[Dictionary] = []
	for u in SurvivorData.UPGRADES:
		var stacks: int = upgrade_stacks.get(u["id"], 0)
		if stacks < int(u["max_stacks"]):
			available.append(u)

	if available.is_empty():
		is_paused_for_upgrade = false
		get_tree().paused = false
		return

	available.shuffle()
	var choices: Array[Dictionary] = []
	for i in range(mini(3, available.size())):
		choices.append(available[i])

	upgrade_ui.show_choices(choices)

func _on_upgrade_selected(upgrade: Dictionary) -> void:
	survivor_player.apply_upgrade(upgrade)
	var uid: String = upgrade["id"]
	upgrade_stacks[uid] = upgrade_stacks.get(uid, 0) + 1

	is_paused_for_upgrade = false
	get_tree().paused = false

func _on_player_died() -> void:
	is_game_over = true
	hud.show_game_over(survivor_player.level, game_time, kill_count)

# ══════════════════════════════════════════════
#  噪声 & 绘制（与 main.gd 一致）
# ══════════════════════════════════════════════

func _init_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = 42
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0006
	_noise.fractal_octaves = 2
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.3

	_cloud_noise = FastNoiseLite.new()
	_cloud_noise.seed = 142
	_cloud_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_cloud_noise.frequency = 0.0008
	_cloud_noise.fractal_octaves = 2

func _draw() -> void:
	_draw_terrain()
	_draw_grid()
	_draw_xp_orbs()

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

	var start_x := snappedf(left, TERRAIN_CELL) - TERRAIN_CELL
	var start_y := snappedf(top, TERRAIN_CELL) - TERRAIN_CELL

	var cx := start_x
	while cx <= right + TERRAIN_CELL:
		var cy := start_y
		while cy <= bottom + TERRAIN_CELL:
			var center_x := cx + TERRAIN_CELL * 0.5
			var center_y := cy + TERRAIN_CELL * 0.5
			var noise_val := _noise.get_noise_2d(center_x, center_y)

			var terrain := _get_terrain_type(noise_val)
			var base_color: Color = TERRAIN_COLORS[terrain]

			var variation := _noise.get_noise_2d(center_x * 2.3, center_y * 2.3) * 0.04
			var cell_color := Color(
				clampf(base_color.r + variation, 0.0, 1.0),
				clampf(base_color.g + variation, 0.0, 1.0),
				clampf(base_color.b + variation, 0.0, 1.0),
				base_color.a
			)

			draw_rect(Rect2(cx, cy, TERRAIN_CELL, TERRAIN_CELL), cell_color)

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

func _draw_xp_orbs() -> void:
	var orb_color := Color(1.0, 0.8, 0.3, 0.8)
	for orb in xp_orbs:
		var pos: Vector2 = orb["pos"]
		var s := 4.0
		var verts := PackedVector2Array([
			pos + Vector2(0, -s),
			pos + Vector2(s * 0.6, 0),
			pos + Vector2(0, s),
			pos + Vector2(-s * 0.6, 0),
		])
		var life: float = orb["life"]
		var alpha := clampf(life / 2.0, 0.0, 1.0)
		var c := Color(orb_color.r, orb_color.g, orb_color.b, orb_color.a * alpha)
		draw_colored_polygon(verts, c)
