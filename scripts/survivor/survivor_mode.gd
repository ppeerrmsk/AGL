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

# ── 经验常量 ──
const XP_PER_KILL := 40  ## 基础经验值（MiG）
const XP_PER_KILL_UAV := 25  ## UAV 击杀经验
const MAX_ENEMIES_LOCKING_PLAYER := 3  ## 同时锁定玩家的敌机上限

# ── 场景/资源引用 ──
@onready var camera: Camera2D = $Camera2D
@onready var bullet_manager: BulletManager = $BulletManager
@onready var missile_manager: MissileManager = $MissileManager

var _aircraft_scene: PackedScene
var _player_params_base: AircraftParams
var _enemy_params_base: AircraftParams
var _uav_params_base: AircraftParams
var _ucav_params_base: AircraftParams
var _interceptor_params_base: AircraftParams

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
var game_time: float = 0.0
var kill_count: int = 0
var is_game_over: bool = false
var is_paused_for_upgrade: bool = false
var _spawn_timer: float = 3.0  ## 初始延迟
var upgrade_stacks: Dictionary = {}

# ── 动态性能控制 ──
var _dynamic_enemy_cap: int = SurvivorData.MAX_ENEMIES_DEFAULT
var _fps_samples: Array[float] = []
var _fps_sample_timer: float = 0.0
const FPS_SAMPLE_INTERVAL := 0.5   ## 每 0.5 秒采样一次 FPS
const FPS_SAMPLE_COUNT := 6        ## 保留最近 6 次采样（3 秒窗口）
const OFFSCREEN_MARGIN := 500.0    ## 屏幕外判定余量（像素）

# ── HUD / UI ──
var hud: SurvivorHUD
var upgrade_ui: SurvivorUpgradeUI

func _ready() -> void:
	_init_noise()
	target_zoom = camera.zoom.x

	_aircraft_scene = preload("res://scenes/aircraft.tscn")
	_enemy_params_base = preload("res://resources/enemy_fighter.tres")
	_uav_params_base = preload("res://resources/enemy_uav.tres")
	_ucav_params_base = preload("res://resources/enemy_uav_missile.tres")
	_interceptor_params_base = preload("res://resources/enemy_interceptor.tres")

	# 读取选择的机型（从选择界面传入），缺省用 F-16
	var selected_res: String = "res://resources/default_fighter.tres"
	if get_tree().has_meta("survivor_aircraft_resource"):
		selected_res = get_tree().get_meta("survivor_aircraft_resource")
		get_tree().remove_meta("survivor_aircraft_resource")
	_player_params_base = load(selected_res)

	# 生成玩家飞机
	player_aircraft = _aircraft_scene.instantiate()
	player_aircraft.params = _player_params_base.duplicate(true)  # 深拷贝，升级修改不影响原资源
	# 生存模式专属强化
	var p := player_aircraft.params
	p.radar_range /= 3.0         # 雷达范围缩减至 1/3
	p.max_speed *= 1.15          # +15% 最大速度
	p.cruise_speed *= 1.15
	p.acceleration *= 1.3        # +30% 加速
	p.roll_rate *= 1.2           # +20% 滚转
	p.max_g += 1.0               # +1G 持续过载
	if p.missile:
		p.missile.max_count = 4  # 初始 4 发导弹
	if p.gun:
		p.gun.bullet_damage *= 1.25  # +25% 机炮伤害
		p.gun.max_range = 1200.0     # 射程 1000→1200m
		p.gun.fire_cone_half_angle = 8.0  # 开火偏斜容差 5°→8°
	# 战斗行为：精通所有战术，完美执行
	if p.combat:
		p.combat = p.combat.duplicate()
	else:
		p.combat = CombatParams.new()
	var cb := p.combat
	cb.combat_bank_aggression = 1.5    # 极限转弯激进度
	cb.combat_full_bank_diff = 0.06    # 更小偏差就压满坡度
	cb.combat_half_bank_diff = 0.01    # 几乎无死区
	cb.intercept_lead_max = 10.0       # 更大预判窗口
	cb.opportunity_cone_mult = 3.0     # 更宽机会射击角
	cb.opportunity_range_mult = 0.6    # 更远机会射击距离
	cb.approach_speed_mult = 1.6       # 接近阶段更快
	cb.overshoot_speed_margin = 1.02   # 更精确速度匹配防冲过
	# 热诱弹释放：冷静老练
	if p.flare:
		p.flare = p.flare.duplicate()
		p.flare.nervousness = 0.0      # 完全冷静，关键时刻才释放
	# 友方子弹命中判定增强
	bullet_manager.friendly_hit_radius = 20.0   # 命中半径 12→20px
	bullet_manager.friendly_dmg_full_ratio = 0.5  # 满伤害区间 30%→50%
	bullet_manager.friendly_dmg_min_mult = 0.4    # 最远衰减 20%→40%
	player_aircraft.enable_missile_reload = true   # 导弹耗尽后自动装填
	player_aircraft.flares_guaranteed = true        # 热诱弹 100% 干扰
	player_aircraft.infinite_fuel = true            # 无限燃油
	player_aircraft.survivor_missile_damage_cap = 30.0  # 导弹伤害上限
	player_aircraft.survivor_bullet_damage_cap = 5.0    # 机炮伤害上限
	player_aircraft.hide_data_label = true          # HUD 替代显示
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
	hud.game_scene = self
	add_child(hud)

	# 升级UI
	upgrade_ui = SurvivorUpgradeUI.new()
	upgrade_ui.upgrade_selected.connect(_on_upgrade_selected)
	add_child(upgrade_ui)

	# Debug 技能面板 (F4)
	var debug_skills := SurvivorDebugSkills.new()
	debug_skills.game_scene = self
	debug_skills.survivor_player = survivor_player
	add_child(debug_skills)

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

	# 动态性能控制
	_update_fps_sampling(delta)
	_update_offscreen_lod()

	# 检查玩家是否死亡
	if player_aircraft and player_aircraft.is_destroyed and not is_game_over:
		_on_player_died()
		return

	# 检测击杀（比较当前敌人数与上一帧）
	_detect_kills()

	# 刷怪
	_update_spawner(delta)

	# 清理已坠毁的敌机（节省性能）
	_cleanup_destroyed_enemies()

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
			# 锁定免疫期间：敌机无法对该目标累积雷达照射
			if other.is_lock_immune():
				ac.radar_targets.erase(other)
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

	# 限制同时锁定玩家的敌机数量（最多 MAX_ENEMIES_LOCKING_PLAYER）
	if player_aircraft and player_aircraft.locked_by.size() > MAX_ENEMIES_LOCKING_PLAYER:
		# 按距离排序，保留最近的几架，其余清除锁定
		var sorted_lockers: Array[Aircraft] = []
		sorted_lockers.assign(player_aircraft.locked_by)
		sorted_lockers.sort_custom(func(a: Aircraft, b: Aircraft) -> bool:
			return a.global_position.distance_squared_to(player_aircraft.global_position) < \
				   b.global_position.distance_squared_to(player_aircraft.global_position)
		)
		var to_remove := sorted_lockers.slice(MAX_ENEMIES_LOCKING_PLAYER)
		for ac in to_remove:
			ac.radar_targets.erase(player_aircraft)
		player_aircraft.locked_by = sorted_lockers.slice(0, MAX_ENEMIES_LOCKING_PLAYER)
		player_aircraft.is_locked = player_aircraft.locked_by.size() > 0

# ══════════════════════════════════════════════
#  刷怪系统
# ══════════════════════════════════════════════

# ══════════════════════════════════════════════
#  动态性能控制
# ══════════════════════════════════════════════

func _update_fps_sampling(delta: float) -> void:
	_fps_sample_timer += delta
	if _fps_sample_timer < FPS_SAMPLE_INTERVAL:
		return
	_fps_sample_timer -= FPS_SAMPLE_INTERVAL

	_fps_samples.append(Engine.get_frames_per_second())
	if _fps_samples.size() > FPS_SAMPLE_COUNT:
		_fps_samples.remove_at(0)

	var avg := _get_avg_fps()
	if avg <= 0.0:
		return

	if avg < SurvivorData.TARGET_FPS:
		# 帧率低于目标：缩减上限
		_dynamic_enemy_cap = maxi(_dynamic_enemy_cap - 2, SurvivorData.MIN_ENEMIES_CAP)
	elif avg > SurvivorData.TARGET_FPS + 10 and _dynamic_enemy_cap < SurvivorData.MAX_ENEMIES_HARD:
		# 帧率充裕：缓慢回升
		_dynamic_enemy_cap = mini(_dynamic_enemy_cap + 1, SurvivorData.MAX_ENEMIES_HARD)

func _get_avg_fps() -> float:
	if _fps_samples.is_empty():
		return 0.0
	var total := 0.0
	for s in _fps_samples:
		total += s
	return total / _fps_samples.size()

func _update_offscreen_lod() -> void:
	var cam_pos := camera.global_position
	var vp_size := get_viewport_rect().size / camera.zoom
	var half := vp_size / 2.0 + Vector2(OFFSCREEN_MARGIN, OFFSCREEN_MARGIN)

	for child in get_children():
		if not child is Aircraft or child == player_aircraft:
			continue
		var ac: Aircraft = child
		if ac.is_destroyed:
			continue

		var rel := ac.global_position - cam_pos
		var offscreen := absf(rel.x) > half.x or absf(rel.y) > half.y

		# 屏幕外的敌人：降低 AI tick 频率 + 禁用视觉更新
		var ai_node: AIController = null
		for c in ac.get_children():
			if c is AIController:
				ai_node = c
				break

		if offscreen:
			# 降低物理处理频率：每 3 帧处理一次
			ac.set_physics_process(Engine.get_physics_frames() % 3 == 0)
			if ai_node:
				ai_node.set_physics_process(Engine.get_physics_frames() % 3 == 0)
			# 禁用绘制
			ac.visible = false
		else:
			ac.set_physics_process(true)
			if ai_node:
				ai_node.set_physics_process(true)
			ac.visible = true

func _cleanup_destroyed_enemies() -> void:
	for child in get_children():
		if child is Aircraft and child.team != 0 and child.is_destroyed:
			if child._destroy_timer > 5.0:
				child.queue_free()

func _count_enemies() -> int:
	var count := 0
	for child in get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			count += 1
	return count

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

	var current_enemies := _count_enemies()
	if current_enemies >= _dynamic_enemy_cap:
		return

	# FPS 低于目标时完全停止刷怪
	var avg_fps := _get_avg_fps()
	if avg_fps > 0.0 and avg_fps < SurvivorData.TARGET_FPS:
		return

	var count := SurvivorData.ENEMIES_PER_WAVE_BASE + int(survivor_player.level * SurvivorData.ENEMIES_PER_WAVE_GROWTH)
	count = mini(count, _dynamic_enemy_cap - current_enemies)

	for _i in range(count):
		_spawn_enemy()

## 敌人类型
enum EnemyType { UAV, UCAV, MIG, INTERCEPTOR }

func _pick_enemy_type() -> EnemyType:
	var lvl := survivor_player.level
	# MiG：等级 7+ 逐步出现
	if lvl >= SurvivorData.MIG_UNLOCK_LEVEL:
		var mig_chance := clampf(
			(lvl - SurvivorData.MIG_UNLOCK_LEVEL) * SurvivorData.MIG_CHANCE_PER_LEVEL,
			0.0, SurvivorData.MIG_CHANCE_MAX)
		if randf() < mig_chance:
			return EnemyType.MIG
	# 截击机（J-7）：等级 5+ 逐步出现
	if lvl >= SurvivorData.INTERCEPTOR_UNLOCK_LEVEL:
		var int_chance := clampf(
			(lvl - SurvivorData.INTERCEPTOR_UNLOCK_LEVEL) * SurvivorData.INTERCEPTOR_CHANCE_PER_LEVEL,
			0.0, SurvivorData.INTERCEPTOR_CHANCE_MAX)
		if randf() < int_chance:
			return EnemyType.INTERCEPTOR
	# UCAV（导弹无人机）：等级 3+ 逐步出现
	if lvl >= SurvivorData.UCAV_UNLOCK_LEVEL:
		var ucav_chance := clampf(
			(lvl - SurvivorData.UCAV_UNLOCK_LEVEL) * SurvivorData.UCAV_CHANCE_PER_LEVEL,
			0.0, SurvivorData.UCAV_CHANCE_MAX)
		if randf() < ucav_chance:
			return EnemyType.UCAV
	return EnemyType.UAV

func _spawn_enemy() -> void:
	var etype := _pick_enemy_type()

	# 选择基础参数
	var base_params: AircraftParams
	match etype:
		EnemyType.MIG:
			base_params = _enemy_params_base
		EnemyType.INTERCEPTOR:
			base_params = _interceptor_params_base
		EnemyType.UCAV:
			base_params = _ucav_params_base
		_:
			base_params = _uav_params_base

	var enemy: Aircraft = _aircraft_scene.instantiate()
	var enemy_params: AircraftParams = base_params.duplicate(true)

	# 根据等级缩放
	var scale: Dictionary
	if etype == EnemyType.MIG or etype == EnemyType.INTERCEPTOR:
		scale = SurvivorData.enemy_scale_for_level(survivor_player.level)
	else:
		scale = SurvivorData.uav_scale_for_level(survivor_player.level)

	enemy_params.max_hp *= float(scale["hp_mult"])
	if enemy_params.missile:
		enemy_params.missile.max_count += int(scale["missile_add"])
	if enemy_params.gun:
		enemy_params.gun.bullet_damage *= float(scale["gun_damage_mult"])

	# MiG 热诱弹限制：仅允许一次释放（burst_count 枚）
	if etype == EnemyType.MIG and enemy_params.flare:
		enemy_params.flare.max_flares = enemy_params.flare.burst_count

	enemy.params = enemy_params
	enemy.team = 1
	enemy.infinite_fuel = true

	# UAV/UCAV 无耐力
	if etype != EnemyType.MIG and etype != EnemyType.INTERCEPTOR:
		enemy.no_stamina = true

	var type_tag: String
	match etype:
		EnemyType.MIG: type_tag = "mig"
		EnemyType.INTERCEPTOR: type_tag = "interceptor"
		EnemyType.UCAV: type_tag = "ucav"
		_: type_tag = "uav"
	enemy.set_meta("enemy_type", type_tag)

	# 在玩家周围随机方向生成
	var spawn_angle := randf() * TAU
	var spawn_pos := player_aircraft.global_position + Vector2(cos(spawn_angle), sin(spawn_angle)) * SurvivorData.SPAWN_DISTANCE
	enemy.position = spawn_pos

	# 朝向玩家
	var to_player := (player_aircraft.global_position - spawn_pos).normalized()
	enemy.initial_heading_deg = rad_to_deg(atan2(to_player.x, -to_player.y))

	add_child(enemy)

	# 注入管理器
	enemy.bullet_manager = bullet_manager
	enemy.missile_manager = missile_manager

	# AI 控制器
	var ai := AIController.new()
	ai.name = "AI_%s" % enemy.name
	ai.aircraft = enemy
	ai.patrol_altitude = randf_range(4000.0, 8000.0)
	var pp := player_aircraft.global_position
	ai.waypoints = PackedVector2Array([
		pp + Vector2(1200, -1200),
		pp + Vector2(1200, 1200),
		pp + Vector2(-1200, 1200),
		pp + Vector2(-1200, -1200),
	])
	ai.enable_combat = true

	match etype:
		EnemyType.MIG:
			# MiG：完整 AI 逻辑
			ai.evade_missiles = true
			ai.aggression = randf_range(0.4, 0.8)
			var level_bonus := clampf(float(survivor_player.level) / 20.0, 0.0, 0.3)
			ai.skill_level = clampf(randf_range(0.3, 0.65) + level_bonus, 0.3, 0.95)
			ai.composure = clampf(randf_range(0.2, 0.55) + level_bonus, 0.2, 0.9)
			ai.focus = clampf(randf_range(0.3, 0.7) + level_bonus * 0.5, 0.3, 0.9)
			ai.self_preservation = randf_range(0.2, 0.7)
		EnemyType.INTERCEPTOR:
			# 截击机：高攻击性纯机炮 AI，低自保
			ai.evade_missiles = false
			ai.aggression = randf_range(0.7, 1.0)
			var level_bonus_int := clampf(float(survivor_player.level) / 20.0, 0.0, 0.3)
			ai.skill_level = clampf(randf_range(0.4, 0.7) + level_bonus_int, 0.4, 0.95)
			ai.composure = clampf(randf_range(0.3, 0.6) + level_bonus_int, 0.3, 0.9)
			ai.focus = clampf(randf_range(0.5, 0.8) + level_bonus_int * 0.5, 0.5, 0.95)
			ai.self_preservation = randf_range(0.05, 0.3)
		_:
			# UAV / UCAV：简化 AI
			ai.simple_ai = true
			ai.evade_missiles = false
			ai.aggression = randf_range(0.2, 0.5)

	enemy.add_child(ai)

# ══════════════════════════════════════════════
#  击杀检测 & 经验球
# ══════════════════════════════════════════════

func _detect_kills() -> void:
	for child in get_children():
		if child is Aircraft and child.team != 0 and child.is_destroyed:
			if not child.has_meta("xp_granted"):
				child.set_meta("xp_granted", true)
				# UAV/UCAV 给较少经验，MiG 给完整经验
				var base_xp := XP_PER_KILL
				var etype: String = child.get_meta("enemy_type", "mig")
				if etype == "uav" or etype == "ucav":
					base_xp = XP_PER_KILL_UAV
				var xp_value := base_xp + survivor_player.level * 8
				survivor_player.add_xp(xp_value)
				kill_count += 1
				# 战场急救：击杀回血
				if survivor_player.aircraft and survivor_player.aircraft.kill_heal_amount > 0.0:
					var ac := survivor_player.aircraft
					var max_hp_val: float = ac.params.max_hp if ac.params else 100.0
					ac.hp = minf(ac.hp + ac.kill_heal_amount, max_hp_val)

# ══════════════════════════════════════════════
#  升级流程
# ══════════════════════════════════════════════

func _on_player_leveled_up(_new_level: int) -> void:
	is_paused_for_upgrade = true
	get_tree().paused = true

	var available: Array[Dictionary] = []
	for u in SurvivorData.UPGRADES:
		# 进化技能不进入随机池
		if u.get("evolved", false):
			continue
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

	# ── 进化检测 ──
	var evolved_name := ""
	if upgrade.has("evolves_to"):
		var stacks: int = upgrade_stacks.get(uid, 0)
		if stacks >= int(upgrade["max_stacks"]):
			var evo_id: String = upgrade["evolves_to"]
			# 查找进化技能定义
			for u in SurvivorData.UPGRADES:
				if u["id"] == evo_id:
					survivor_player.apply_upgrade(u)
					upgrade_stacks[evo_id] = 1
					evolved_name = u["name"]
					break

	is_paused_for_upgrade = false
	get_tree().paused = false

	# 进化提示
	if evolved_name != "":
		if survivor_player.aircraft:
			survivor_player.aircraft.show_tactic_popup("技能进化！%s" % evolved_name)

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
