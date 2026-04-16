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
const MAX_MISSILES_TARGETING_PLAYER := 3  ## 同时飞向玩家的导弹上限

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
var _commander_params_base: AircraftParams
var _f86_params_base: AircraftParams
var _mig31_params_base: AircraftParams
var _mig23_params_base: AircraftParams
var _f100_params_base: AircraftParams
var _su27_params_base: AircraftParams
var _a7_params_base: AircraftParams
var _q5_params_base: AircraftParams
var _tu160_params_base: AircraftParams
var _ah64_params_base: AircraftParams
var _ch47_params_base: AircraftParams
var _f47_params_base: AircraftParams

# ── 王牌中队 BOSS ──
var _ace_squad: AceSquad = null              ## 当前活跃的王牌中队（F-47 等）

# ── 地面单位场景/参数（Debug 面板用）──
var _sam_scene: PackedScene
var _sam_params: Resource
var _aa_scene: PackedScene
var _aa_params: Resource

# ── 操控状态（与 main.gd 一致）──
var selected_aircraft: Array[Aircraft] = []
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO
var target_zoom: float = 1.0
var _hovered_unit: CombatUnit = null

# ── 噪声 ──
var _noise: FastNoiseLite
var _cloud_noise: FastNoiseLite

# ── 生存模式状态 ──
var player_aircraft: Aircraft
var _player_profile_id: StringName = &""  ## 当前主角的 PlayableAircraft.id（用于专属技能筛选）
var _wingman_formation_debug: bool = false  ## F11 切换：友方僚机编队调试覆盖层
var survivor_player: SurvivorPlayer
var game_time: float = 0.0
var kill_count: int = 0
var is_game_over: bool = false
var is_paused_for_upgrade: bool = false
var _spawn_timer: float = 3.0  ## 初始延迟
var upgrade_stacks: Dictionary = {}
var _hunter_timer: float = 0.0  ## 猎手指派计时器
const HUNTER_INTERVAL := 5.0   ## 每5秒检查一次，指派猎手追踪玩家
const WAYPOINT_UPDATE_INTERVAL := 8.0  ## 每8秒更新敌机巡逻航点跟踪玩家
var _waypoint_update_timer: float = 0.0
var _squads: Array[Squad] = []  ## 活跃分队列表
var _uav_serial: int = 0        ## UAV 类编号计数器
var _squad_cleanup_timer: float = 0.0
const SQUAD_CLEANUP_INTERVAL := 3.0  ## 每3秒清理一次无效分队

# ── Adds 族群（Flock）──
## Adds 类敌人（Tu-160 / AH-64 / CH-47）不走随机刷新系统，由未来的事件系统按需 spawn。
## 这里仅保留单位编号计数器（分配 callsign 用）和共通的 despawn_after 生命期清理。
var _tu160_serial: int = 0       ## Tu-160 编号计数器
var _ah64_serial: int = 0
var _ch47_serial: int = 0

# ── Token 烈度控制 ──
var _token_used: int = 0
var _token_count_by_type: Dictionary = {}  ## EnemyType(int) -> 当前数量
var _far_cleanup_timer: float = 0.0

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
	# 确保 SurvivorMode 在所有子节点（含 AI 控制器）之前执行
	# 这样 _f47_assign_roles 设置的 boss_attacker 等标志在 AI 运行时已经生效
	process_priority = -10
	process_physics_priority = -10
	_init_noise()
	target_zoom = camera.zoom.x

	_aircraft_scene = preload("res://scenes/aircraft.tscn")
	_enemy_params_base = preload("res://resources/enemy_fighter.tres")
	_uav_params_base = preload("res://resources/enemy_uav.tres")
	_ucav_params_base = preload("res://resources/enemy_uav_missile.tres")
	_interceptor_params_base = preload("res://resources/enemy_interceptor.tres")
	_commander_params_base = preload("res://resources/enemy_uav_commander.tres")
	_f86_params_base = preload("res://resources/enemy_f86.tres")
	_mig31_params_base = preload("res://resources/enemy_mig31.tres")
	_mig23_params_base = preload("res://resources/enemy_mig23.tres")
	_f100_params_base = preload("res://resources/enemy_f100.tres")
	_su27_params_base = preload("res://resources/enemy_su27.tres")
	_a7_params_base = preload("res://resources/enemy_a7.tres")
	_q5_params_base = preload("res://resources/enemy_q5.tres")
	_tu160_params_base = preload("res://resources/enemy_tu160.tres")
	_ah64_params_base = preload("res://resources/enemy_ah64.tres")
	_ch47_params_base = preload("res://resources/enemy_ch47.tres")
	_f47_params_base = preload("res://resources/enemy_f47.tres")
	_sam_scene = preload("res://scenes/sam_unit.tscn")
	_sam_params = preload("res://resources/sam_params.tres")
	_aa_scene = preload("res://scenes/aa_gun_unit.tscn")
	_aa_params = preload("res://resources/aa_gun_params.tres")

	# 读取选择的机型档案（PlayableAircraft），缺省用 F-16
	var profile_path: String = "res://resources/playable_f16.tres"
	if get_tree().has_meta("survivor_aircraft_resource"):
		profile_path = get_tree().get_meta("survivor_aircraft_resource")
		get_tree().remove_meta("survivor_aircraft_resource")
	var profile: PlayableAircraft = load(profile_path)
	if profile == null or profile.base_params == null:
		push_error("survivor_mode: 无效的 PlayableAircraft：%s" % profile_path)
		return
	_player_params_base = profile.base_params
	_player_profile_id = profile.id  # 用于专属技能筛选

	# 读取选择的地图（占位：当前仅 default 一张实装，其它为预留位）
	# 后续在此根据 map_id 切换噪声 seed/frequency/地形配色
	if get_tree().has_meta("survivor_map_id"):
		get_tree().remove_meta("survivor_map_id")

	# 友方子弹命中判定增强（生存模式全局，不依赖具体机型）
	bullet_manager.friendly_hit_radius = 20.0   # 命中半径 12→20px
	bullet_manager.friendly_dmg_full_ratio = 0.5  # 满伤害区间 30%→50%
	bullet_manager.friendly_dmg_min_mult = 0.4    # 最远衰减 20%→40%
	bullet_manager.flat_altitude_mode = true       # 扁平高度：无高度容差限制
	bullet_manager.missile_manager = missile_manager  # CIWS 子弹需要碰撞导弹

	# 生成玩家飞机
	player_aircraft = _aircraft_scene.instantiate()
	player_aircraft.callsign = "Ultra"  # 生存模式固定代号
	CallsignDB.reserve("Ultra")
	player_aircraft.params = _player_params_base.duplicate(true)  # 深拷贝，升级修改不影响原资源
	# 手动 duplicate 外部子资源，避免多实例共享同一 Resource
	SurvivorPlayableSetup.deep_dup_weapons(player_aircraft.params)
	# 应用机型档案的全部生存模式强化（数据驱动，逻辑见 survivor_playable_setup.gd）
	SurvivorPlayableSetup.apply(player_aircraft, profile)

	# 通用主角实例配置（与机型无关）
	player_aircraft.hide_data_label = true          # HUD 替代显示
	player_aircraft.flat_altitude = true            # 三档高度模式
	player_aircraft.use_tactical_preference = true  # 启用战术偏好面板
	player_aircraft.set_target_tier(Aircraft.AltitudeTier.MID)
	player_aircraft.team = 0
	player_aircraft.position = Vector2.ZERO
	player_aircraft.bullet_manager = bullet_manager
	player_aircraft.missile_manager = missile_manager
	player_aircraft.selected = true
	add_child(player_aircraft)
	selected_aircraft.append(player_aircraft)

	# 起始僚机（小队主控）：仅当档案声明 wingman_count > 0 时生成
	if profile.wingman_count > 0:
		_spawn_starting_wingmen(profile)

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

	# Debug 刷怪面板 (F5) — 不暂停游戏，可即时测试
	var debug_spawn := SurvivorDebugSpawn.new()
	debug_spawn.game_scene = self
	add_child(debug_spawn)

# ══════════════════════════════════════════════
#  起始僚机（"小队主控"型主角专用）
# ══════════════════════════════════════════════

## 根据 PlayableAircraft 档案在玩家旁边生成 N 架友方僚机，
## 并把它们和玩家组成一个 Squad（玩家为长机）。
## 仅当 profile.wingman_count > 0 时由 _ready 调用。
func _spawn_starting_wingmen(profile: PlayableAircraft) -> void:
	if not profile or profile.wingman_count <= 0 or not player_aircraft:
		return
	var wing_base: AircraftParams = profile.wingman_params
	if wing_base == null:
		wing_base = profile.base_params  # 缺省：与主角同型
	if wing_base == null:
		return

	var sq := Squad.new()
	sq.leader = player_aircraft
	sq.add_member(player_aircraft)

	for i in range(1, profile.wingman_count + 1):
		var ac: Aircraft = _aircraft_scene.instantiate()
		ac.params = wing_base.duplicate(true)
		SurvivorPlayableSetup.deep_dup_weapons(ac.params)
		# 僚机走与长机完全相同的档案应用，确保起始属性（雷达/速度/G/武器/装填/伤害上限/
		# 闪避/无限燃油 等）完全一致；is_wingman=true 仅跳过 codename 后缀。
		# 升级仍然只作用于长机，所以僚机不会随玩家成长。
		SurvivorPlayableSetup.apply(ac, profile, true)
		ac.team = 0

		# 阵型槽位
		var offset := sq.get_formation_offset(i)
		var rotated := offset.rotated(player_aircraft.heading)
		ac.position = player_aircraft.global_position + rotated
		ac.initial_heading_deg = rad_to_deg(player_aircraft.heading)
		ac.altitude = player_aircraft.altitude
		ac.target_altitude = player_aircraft.altitude
		ac.bullet_manager = bullet_manager
		ac.missile_manager = missile_manager
		# 生存模式全局规则 + 与长机一致的显示/战术设置
		ac.flat_altitude = true
		ac.hide_data_label = true  # 用与长机一致的精简 HUD 标签（无 MSL/AMM/FLR 细节，详情走小队面板）
		ac.set_target_tier(Aircraft.AltitudeTier.MID)
		add_child(ac)

		var ai := AIController.new()
		ai.name = "AI_Wing%d" % i
		ai.aircraft = ac
		ai.squad = sq
		ai.squad_index = i
		ai.enable_combat = true
		ai.evade_missiles = true
		# ── 完美飞行员：所有僚机都完美执行战术，不受压力/技能退化影响 ──
		# skill_level=1 + composure=1 → effective_skill 永远是 1（见 _effective_skill 公式）
		# focus=1 → 永不分心，目标重评不会频繁切换
		# situational_awareness=1 → 态势感知满值
		# self_preservation 保留 0.5 以保证导弹来袭会做规避
		ai.aggression = 1.0
		ai.skill_level = 1.0
		ai.composure = 1.0
		ai.focus = 1.0
		ai.situational_awareness = 1.0
		ai.self_preservation = 0.5
		ai.patrol_altitude = player_aircraft.altitude
		ai._state = AIController.AIState.SQUAD_FOLLOW
		ac.add_child(ai)

		# 预置编队托管态：避免 frame 1 上 lod_level=0 + formation_mode=false 的默认值
		# 让飞机走 LOD 0 全模拟分支（target_position=INF 直行漂移）。
		# 直接把 aircraft 设置成"已经在编队里"的状态，让 frame 1 就走 LOD 1 编队分支。
		ac.lod_level = 1
		ac.formation_mode = true
		ac._formation_leader = player_aircraft
		ac._formation_blend = 1.0
		ac._formation_jitter_phase = ai._formation_jitter_phase
		ac.keep_target_on_arrival = true
		var initial_slot := sq.get_wingman_target(i)
		if initial_slot != Vector2.INF:
			ac.target_position = initial_slot
		# 若 F11 编队调试已开启，新生成的僚机也跟着开
		if _wingman_formation_debug:
			ac.formation_debug = true

		sq.add_member(ac)

	_squads.append(sq)

# ══════════════════════════════════════════════
#  编队调试（F11 切换覆盖层 / F12 状态快照）
# ══════════════════════════════════════════════

## F11：在所有友方僚机（team==0 且不是 player_aircraft）上切换 formation_debug 标志。
## 打开后每架僚机会绘制：
##   - 橙色 X 与连线 → 阵型槽位
##   - 蓝色射线 → 当前 heading
##   - 黄色射线 → 编队代码计算的目标 heading
##   - 文本 [BRANCH] slot_d hdg→Δ° bank→ blend spd
##   - 50px CLOSE_DIST 阈值圆
## 同时每架僚机每秒一次写入 EventLogger（F9 导出查看历史）。
func _toggle_wingman_formation_debug() -> void:
	_wingman_formation_debug = not _wingman_formation_debug
	var count := 0
	for child in get_children():
		if not child is Aircraft:
			continue
		var ac: Aircraft = child
		if ac == player_aircraft or ac.team != 0 or ac.is_destroyed:
			continue
		ac.formation_debug = _wingman_formation_debug
		ac._dbg_log_timer = 0.0  # 让下一帧立刻打一行
		count += 1
	var status := "ON" if _wingman_formation_debug else "OFF"
	print("[WingmanDebug] formation_debug=%s applied to %d wingmen" % [status, count])
	EventLogger.log_event("FORM_DBG", "Survivor", "F11 toggled formation_debug=%s on %d wingmen" % [status, count])

## F12：立即抓一帧友方僚机的编队状态快照，打印到控制台 + EventLogger。
## 不需要先按 F11；这是单次状态读取。
func _dump_wingman_formation_state() -> void:
	var lines := PackedStringArray()
	lines.append("=== Wingman Formation Snapshot @ %.1fs ===" % game_time)
	if player_aircraft and not player_aircraft.is_destroyed:
		lines.append("LEADER %s: pos=(%d,%d) hdg=%d bank=%+.0f° G=%.1f spd=%d alt=%d" % [
			player_aircraft.callsign,
			int(player_aircraft.global_position.x), int(player_aircraft.global_position.y),
			int(rad_to_deg(player_aircraft.heading)),
			rad_to_deg(player_aircraft.bank_angle),
			player_aircraft.g_load,
			int(player_aircraft.speed * 3.6),
			int(player_aircraft.altitude),
		])
	for child in get_children():
		if not child is Aircraft:
			continue
		var ac: Aircraft = child
		if ac == player_aircraft or ac.team != 0 or ac.is_destroyed:
			continue
		var slot_dist_str := "?"
		if ac._dbg_slot_pos != Vector2.INF:
			slot_dist_str = str(int(ac._dbg_slot_dist))
		lines.append("  %s: lod=%d fmode=%s branch=%s slot_d=%s hdg=%d→%d Δ%+.1f° bank=%+.0f°→%+.0f° spd=%d/%d G=%.1f" % [
			ac.callsign,
			ac.lod_level,
			"Y" if ac.formation_mode else "n",
			ac._dbg_branch if ac._dbg_branch != "" else "?",
			slot_dist_str,
			int(rad_to_deg(ac.heading)),
			int(rad_to_deg(ac._dbg_target_heading)),
			rad_to_deg(ac._dbg_hdiff),
			rad_to_deg(ac.bank_angle),
			rad_to_deg(ac._dbg_desired_bank),
			int(ac.speed * 3.6),
			int(ac._dbg_chase_target_kmh),
			ac.g_load,
		])
	for line in lines:
		print(line)
		EventLogger.log_event("FORM_DBG", "Snapshot", line)

# ══════════════════════════════════════════════
#  输入处理（与 main.gd 一致）
# ══════════════════════════════════════════════

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().paused = false
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_F9:
		# 消费事件，避免编辑器调试器捕获 F9 进入断点/暂停状态
		get_viewport().set_input_as_handled()
		# 保险：若被其他机制设为暂停，立即解除
		if get_tree().paused and not is_paused_for_upgrade:
			get_tree().paused = false
		var path := EventLogger.dump_to_file()
		if path != "":
			print("Combat log saved: %s" % path)
		return
	# F11：切换友方僚机的编队调试覆盖层
	if event is InputEventKey and event.pressed and event.keycode == KEY_F11:
		get_viewport().set_input_as_handled()
		_toggle_wingman_formation_debug()
		return
	# F12：把当前所有友方僚机的编队状态打印到控制台 + EventLogger
	if event is InputEventKey and event.pressed and event.keycode == KEY_F12:
		get_viewport().set_input_as_handled()
		_dump_wingman_formation_state()
		return
	if is_game_over or is_paused_for_upgrade:
		return
	# 战术面板快捷键
	if event is InputEventKey and event.pressed and player_aircraft and not player_aircraft.is_destroyed:
		match event.keycode:
			KEY_1:
				player_aircraft.weapon_preference = Aircraft.WeaponPreference.PREFER_MISSILE
				return
			KEY_2:
				player_aircraft.weapon_preference = Aircraft.WeaponPreference.PREFER_GUN
				return
			KEY_3:
				player_aircraft.altitude_preference = Aircraft.AltitudePreference.PREFER_CLIMB
				return
			KEY_4:
				player_aircraft.altitude_preference = Aircraft.AltitudePreference.PREFER_LOW
				return
			KEY_E:
				# 进入规避会清空当前指令（内部实现等同右键"解除任务"）
				player_aircraft.set_evasion_mode(not player_aircraft.evasion_mode)
				return
			KEY_F:
				player_aircraft.missile_auto_fire = not player_aircraft.missile_auto_fire
				return
			KEY_5:
				# 小队阵型切换（等同点击小队面板的"阵型"按钮）
				if hud:
					hud._on_squad_formation_pressed()
				return
			KEY_6:
				# 小队交战模式（护航 ↔ 自由）
				if hud:
					hud._on_squad_engage_pressed()
				return
			KEY_7:
				# 小队武器偏好（导弹 ↔ 机炮）
				if hud:
					hud._on_squad_weapon_pressed()
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
				ac.evasion_mode = false  # 选择攻击目标自动关闭规避
				ac.set_combat_target(enemy)
		return

	# 无敌机：普通移动指令（自动关闭规避）
	for ac in selected_aircraft:
		if is_instance_valid(ac) and not ac.is_destroyed:
			ac.evasion_mode = false
			ac.clear_combat_target()
			ac.target_position = world_pos

func _on_right_click() -> void:
	for ac in selected_aircraft:
		if is_instance_valid(ac):
			ac.clear_combat_target()
			ac.target_position = Vector2.INF

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

func _update_hover(screen_pos: Vector2) -> void:
	var world_pos := _screen_to_world(screen_pos)
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
	_update_friendly_squad_lod()

	# 检查玩家是否死亡
	if player_aircraft and player_aircraft.is_destroyed and not is_game_over:
		_on_player_died()
		return

	# 检测击杀（比较当前敌人数与上一帧）
	_detect_kills()

	# 刷怪
	_update_spawner(delta)

	# Adds 类敌人（Tu-160 / AH-64 / CH-47）不随机刷新——由未来的事件系统按需触发 spawn。
	# 这里仅处理已刷出来单位的生命期超限清理（despawn_after meta）
	_cleanup_expired_adds()

	# 王牌中队 BOSS 更新
	if _ace_squad:
		_ace_squad.update(delta)

	# 猎手追踪 & 巡逻航点更新
	_update_hunters(delta)
	_update_enemy_waypoints(delta)

	# 清理已坠毁的敌机（节省性能）
	_cleanup_destroyed_enemies()
	# 远距清理：释放 Token 预算
	_update_far_cleanup(delta)

	# 定期清理无效分队
	_squad_cleanup_timer -= delta
	if _squad_cleanup_timer <= 0.0:
		_squad_cleanup_timer = SQUAD_CLEANUP_INTERVAL
		_cleanup_squads()

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

func _update_radar_locks(delta: float) -> void:
	# 收集所有战斗单位（飞机 + 地面单位）
	var all_units: Array[CombatUnit] = []
	for child in get_children():
		if child is CombatUnit:
			all_units.append(child)

	for unit in all_units:
		unit.is_locked = false
		unit.locked_by.clear()

	for unit in all_units:
		var keys_to_remove: Array = []
		for key in unit.radar_targets:
			if not is_instance_valid(key):
				keys_to_remove.append(key)
		for key in keys_to_remove:
			unit.radar_targets.erase(key)

		for other in all_units:
			if other == unit or other.team == unit.team:
				continue
			# 锁定免疫期间：无法对该目标累积雷达照射
			if other.is_lock_immune():
				unit.radar_targets.erase(other)
				continue
			if unit.is_in_radar_cone(other.global_position):
				# 低空/地面目标更难锁定
				var lock_rate := _lock_rate_for_tier(other.get_altitude_tier())
				var prev: float = unit.radar_targets.get(other, 0.0)
				unit.radar_targets[other] = prev + delta * lock_rate
			else:
				var prev: float = unit.radar_targets.get(other, 0.0)
				if prev > 0.0:
					unit.radar_targets[other] = prev - delta / 1.5
					if unit.radar_targets[other] <= 0.0:
						unit.radar_targets.erase(other)
				else:
					unit.radar_targets.erase(other)

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

	# 限制同时飞向玩家的导弹数量（最多 MAX_MISSILES_TARGETING_PLAYER）
	if player_aircraft and missile_manager:
		var missiles_at_player := _count_missiles_targeting_player()
		if missiles_at_player >= MAX_MISSILES_TARGETING_PLAYER:
			# 阻止更多敌机对玩家发射导弹：清除尚未发射的敌机对玩家的锁定
			# 只清除那些还没有在飞导弹指向玩家的敌机的锁定
			for ac in _get_enemies_without_active_missile_at_player():
				var lock_val: float = ac.radar_targets.get(player_aircraft, 0.0)
				var lock_time_val: float = ac.params.lock_time if ac.params else 3.0
				if lock_val >= lock_time_val:
					# 将锁定进度压回刚好低于锁定阈值，阻止发射但保持追踪
					ac.radar_targets[player_aircraft] = lock_time_val - 0.5

## 低空/地面目标锁定速率衰减
static func _lock_rate_for_tier(tier: int) -> float:
	match tier:
		CombatUnit.AltitudeTier.GROUND:
			return 0.5
		CombatUnit.AltitudeTier.LOW:
			return 0.7
		_:
			return 1.0

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
		# 友方僚机不走 set_physics_process 节流（数量极少且必须每帧维持编队同步），
		# 它们的 LOD 由 _update_friendly_squad_lod 单独管理。
		if ac.team == 0:
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

## 友方编队 LOD：明确把僚机置入正确的 lod_level（防止 AI 与物理跑步序错位时
## 落到 LOD 0 全模拟分支，引起编队抖动）。
##   - player_aircraft → 永远 LOD 0
##   - 友方僚机交战中 → LOD 0
##   - 友方僚机巡航中 → LOD 1（编队托管）
##   - 友方僚机离屏 → LOD 2（自我节流）
func _update_friendly_squad_lod() -> void:
	if not player_aircraft or player_aircraft.is_destroyed:
		return
	# 玩家长机始终 LOD 0
	player_aircraft.lod_level = 0
	player_aircraft.visible = true

	var cam_pos := camera.global_position
	var vp_size := get_viewport_rect().size / camera.zoom
	var half := vp_size / 2.0 + Vector2(OFFSCREEN_MARGIN, OFFSCREEN_MARGIN)

	for child in get_children():
		if not child is Aircraft:
			continue
		var ac: Aircraft = child
		if ac == player_aircraft or ac.team != 0 or ac.is_destroyed:
			continue

		var rel := ac.global_position - cam_pos
		var offscreen := absf(rel.x) > half.x or absf(rel.y) > half.y

		if offscreen:
			ac.lod_level = 2
			ac.visible = false
		elif ac.combat_target != null:
			ac.lod_level = 0
			ac.visible = true
		else:
			ac.lod_level = 1
			ac.visible = true

func _cleanup_destroyed_enemies() -> void:
	for child in get_children():
		if child is Aircraft and child.team != 0 and child.is_destroyed:
			if child._destroy_timer > 5.0:
				child.queue_free()

## 远距清理：飞出战区的敌机静默移除，释放占用的 Token
## 不触发击杀逻辑（不播坠毁动画、不给经验）
func _update_far_cleanup(delta: float) -> void:
	_far_cleanup_timer -= delta
	if _far_cleanup_timer > 0.0:
		return
	_far_cleanup_timer = SurvivorData.FAR_CLEANUP_INTERVAL
	if not player_aircraft or player_aircraft.is_destroyed:
		return

	var pp := player_aircraft.global_position
	var cleanup_d2 := SurvivorData.FAR_CLEANUP_DISTANCE * SurvivorData.FAR_CLEANUP_DISTANCE
	var removed := 0
	for child in get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			var ac: Aircraft = child
			# Adds 杂兵（Tu-160 等族群）不受远距清理影响，它们沿固定航线飞过战场
			if ac.has_meta("skip_far_cleanup") and ac.get_meta("skip_far_cleanup"):
				continue
			if ac.global_position.distance_squared_to(pp) > cleanup_d2:
				# 防止 _detect_kills 在同帧误判为击杀
				ac.set_meta("xp_granted", true)
				ac.queue_free()
				removed += 1

	if removed > 0:
		EventLogger.log_event("TOKEN", "FarCleanup", "despawned %d distant enemies" % removed)

## 猎手系统：定期指派空闲敌机主动追击玩家
func _update_hunters(delta: float) -> void:
	_hunter_timer -= delta
	if _hunter_timer > 0.0:
		return
	_hunter_timer = HUNTER_INTERVAL
	if not player_aircraft or player_aircraft.is_destroyed:
		return

	# 统计当前正在交战玩家的敌机数量
	var engaging_count := 0
	var idle_enemies: Array[Aircraft] = []
	for child in get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			# Adds 杂兵和 Boss 不参与猎手系统（Adds 沿航线飞，Boss 有独立战术循环）
			var cat: String = child.get_meta("category", "")
			if cat == "adds" or cat == "boss":
				continue
			var ai := _get_ai(child)
			if ai:
				if ai._current_target == player_aircraft:
					engaging_count += 1
				elif ai._state == AIController.AIState.PATROL and ai._cooldown_timer <= 0.0:
					idle_enemies.append(child)

	# 确保至少有一定比例的敌机在追击玩家
	# 最少2架，随等级增加
	var desired_hunters := maxi(2, 1 + survivor_player.level / 3)
	var need := desired_hunters - engaging_count

	if need > 0 and not idle_enemies.is_empty():
		# 按距离排序，优先指派近的
		idle_enemies.sort_custom(func(a: Aircraft, b: Aircraft) -> bool:
			return a.global_position.distance_squared_to(player_aircraft.global_position) < \
				   b.global_position.distance_squared_to(player_aircraft.global_position)
		)
		for i in range(mini(need, idle_enemies.size())):
			var enemy := idle_enemies[i]
			var ai := _get_ai(enemy)
			if ai:
				# 强制进入交战状态
				ai._current_target = player_aircraft
				enemy.set_combat_target(player_aircraft)
				ai._state = AIController.AIState.ENGAGE if not ai.simple_ai else AIController.AIState.PATROL
				ai._engage_timer = 0.0
				ai._cooldown_timer = 0.0
				if ai.simple_ai:
					ai._current_target = player_aircraft
				else:
					ai._tactic = AIController.EngageTactic.LEAD_PURSUIT
					ai._tactic_timer = 0.0
					ai._tactic_min_duration = 0.5
					ai._target_eval_timer = 0.0
					enemy.ai_override_pursuit = true

## 定期更新敌机巡逻航点，使其围绕玩家当前位置巡逻
func _update_enemy_waypoints(delta: float) -> void:
	_waypoint_update_timer -= delta
	if _waypoint_update_timer > 0.0:
		return
	_waypoint_update_timer = WAYPOINT_UPDATE_INTERVAL
	if not player_aircraft or player_aircraft.is_destroyed:
		return

	var pp := player_aircraft.global_position
	for child in get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			# Adds 杂兵和 Boss 有独立航点管理，不被绕玩家航点覆盖
			var cat2: String = child.get_meta("category", "")
			if cat2 == "adds" or cat2 == "boss":
				continue
			var ai := _get_ai(child)
			if ai and (ai._state == AIController.AIState.PATROL or (ai.simple_ai and ai._current_target == null)):
				# 更新航点围绕玩家当前位置，半径略随机化
				var radius := randf_range(800.0, 1500.0)
				var offset_angle := randf() * TAU
				ai.waypoints = PackedVector2Array([
					pp + Vector2(cos(offset_angle), sin(offset_angle)) * radius,
					pp + Vector2(cos(offset_angle + TAU * 0.25), sin(offset_angle + TAU * 0.25)) * radius,
					pp + Vector2(cos(offset_angle + TAU * 0.5), sin(offset_angle + TAU * 0.5)) * radius,
					pp + Vector2(cos(offset_angle + TAU * 0.75), sin(offset_angle + TAU * 0.75)) * radius,
				])

## 获取飞机的 AI 控制器
func _get_ai(ac: Aircraft) -> AIController:
	for child in ac.get_children():
		if child is AIController:
			return child
	return null

func _count_missiles_targeting_player() -> int:
	var count := 0
	for child in missile_manager.get_children():
		if child is Missile:
			var m: Missile = child as Missile
			if m.is_active and m.target == player_aircraft:
				count += 1
	return count

func _get_enemies_without_active_missile_at_player() -> Array[Aircraft]:
	# 找出有锁定玩家但没有在飞导弹指向玩家的敌机
	var has_missile: Dictionary = {}  # Aircraft -> bool
	for child in missile_manager.get_children():
		if child is Missile:
			var m: Missile = child as Missile
			if m.is_active and m.target == player_aircraft and is_instance_valid(m.source):
				has_missile[m.source] = true
	var result: Array[Aircraft] = []
	for child in get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			if not has_missile.has(child):
				result.append(child)
	return result

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

	# 从场景真实状态重算 Token 占用（捕获死亡/远距清理/debug spawn）
	_recalc_token_usage()

	var current_enemies := _count_enemies()
	if current_enemies >= _dynamic_enemy_cap:
		return

	# FPS 低于目标时完全停止刷怪
	var avg_fps := _get_avg_fps()
	if avg_fps > 0.0 and avg_fps < SurvivorData.TARGET_FPS:
		return

	var budget := _get_token_budget()
	if _token_used >= budget:
		return  # Token 已满，本轮跳过

	var count := SurvivorData.ENEMIES_PER_WAVE_BASE + int(survivor_player.level * SurvivorData.ENEMIES_PER_WAVE_GROWTH)
	count = mini(count, _dynamic_enemy_cap - current_enemies)

	EventLogger.log_event("WAVE", "Spawner",
		"wave lvl=%d token=%d/%d cap=%d/%d" % [
			survivor_player.level, _token_used, budget,
			current_enemies, _dynamic_enemy_cap])

	var spawned := 0
	while spawned < count:
		var remaining := budget - _token_used
		if remaining <= 0:
			break

		var etype := _pick_enemy_type()
		if not _can_spawn_type(int(etype), remaining):
			break  # fallback 是 UAV=1，若连它都不够就整轮结束

		var cost: int = int(SurvivorData.TOKEN_COST.get(int(etype), 1))
		var is_late_game := survivor_player.level >= SurvivorData.LATE_GAME_LEVEL

		# MiG-31 永远单机精英；J-7 在后期改走编队（视作低级 Lancer）
		var spawn_as_single := etype == EnemyType.MIG31 \
				or etype == EnemyType.SU27 \
				or (etype == EnemyType.INTERCEPTOR and not is_late_game)

		if spawn_as_single:
			# 单机精英 Lancer：一架一架地刷
			_spawn_single(etype)
			_token_used += cost
			_token_count_by_type[int(etype)] = int(_token_count_by_type.get(int(etype), 0)) + 1
			spawned += 1

		elif etype == EnemyType.UAV_COMMANDER:
			# Sentinel + UAV 僚机组成小队；僚机按 UAV 计费
			var uav_cost: int = int(SurvivorData.TOKEN_COST.get(int(EnemyType.UAV), 1))
			var max_wingmen := int((remaining - cost) / maxi(uav_cost, 1))
			max_wingmen = mini(max_wingmen, SurvivorData.COMMANDER_SQUAD_MAX)
			max_wingmen = mini(max_wingmen, count - spawned - 1)
			if max_wingmen >= SurvivorData.COMMANDER_SQUAD_MIN:
				var wingman_count := randi_range(SurvivorData.COMMANDER_SQUAD_MIN, max_wingmen)
				_spawn_commander_squad(wingman_count)
				_token_used += cost + uav_cost * wingman_count
				_token_count_by_type[int(EnemyType.UAV_COMMANDER)] = int(_token_count_by_type.get(int(EnemyType.UAV_COMMANDER), 0)) + 1
				_token_count_by_type[int(EnemyType.UAV)] = int(_token_count_by_type.get(int(EnemyType.UAV), 0)) + wingman_count
				spawned += 1 + wingman_count
			else:
				# 预算不足 → 回退到单架 UAV
				if _can_spawn_type(int(EnemyType.UAV), remaining):
					_spawn_single(EnemyType.UAV)
					_token_used += uav_cost
					_token_count_by_type[int(EnemyType.UAV)] = int(_token_count_by_type.get(int(EnemyType.UAV), 0)) + 1
					spawned += 1
				else:
					break

		else:
			# MiG / F86 / MiG-23 / F-100 / UCAV / UAV / J-7(后期) ：分队生成
			var squad_size: int
			if etype == EnemyType.MIG or etype == EnemyType.F86 \
					or etype == EnemyType.MIG23 or etype == EnemyType.F100 \
					or etype == EnemyType.INTERCEPTOR \
					or etype == EnemyType.A7 or etype == EnemyType.Q5:
				squad_size = randi_range(2, 3)
			else:
				squad_size = randi_range(2, 4)
			squad_size = mini(squad_size, count - spawned)
			# Token 约束
			squad_size = mini(squad_size, int(remaining / maxi(cost, 1)))
			# 实例上限约束
			var type_cap: int = int(SurvivorData.TOKEN_INSTANCE_CAP.get(int(etype), -1))
			if type_cap > 0:
				var type_cur: int = int(_token_count_by_type.get(int(etype), 0))
				squad_size = mini(squad_size, type_cap - type_cur)

			# 后期分水岭：低级飞机/杂鱼不允许单架，至少凑成 2 架编队
			# - 早期 min=1（允许尾巴落单），后期 min=2（强制成对）
			# - 凑不齐 min 就 break，等下一个 spawner tick 重新选型
			var min_squad_size := 2 if is_late_game else 1
			if squad_size < min_squad_size:
				break

			if squad_size == 1:
				_spawn_single(etype)
			else:
				_spawn_squad(etype, squad_size)
			_token_used += cost * squad_size
			_token_count_by_type[int(etype)] = int(_token_count_by_type.get(int(etype), 0)) + squad_size
			spawned += squad_size

## 敌人类型
## ⚠ 新增时必须同步 TOKEN_COST / TOKEN_INSTANCE_CAP / _create_enemy match /
##   _preload / _pick_enemy_type / survivor_debug_spawn.ENEMY_TYPE_LABELS
##
## 分类说明：
## - Adds（杂兵，category="adds"）：无反击能力，只沿直线飞行，不走 _update_spawner
##     / Token 预算系统，通过独立 flock 波次刷新，不受远距清理影响。
##     目前成员：TU160, AH64, CH47。敌人参数的 meta("category")="adds" 标识。
enum EnemyType { UAV, UCAV, MIG, INTERCEPTOR, UAV_COMMANDER, F86, MIG31, MIG23, F100, SU27, A7, Q5, TU160, AH64, CH47, F47 }

## 当前 Token 预算（随等级增长，夹在常量范围内）
func _get_token_budget() -> int:
	var budget := SurvivorData.TOKEN_BUDGET_BASE + int(survivor_player.level * SurvivorData.TOKEN_BUDGET_PER_LEVEL)
	return mini(budget, SurvivorData.TOKEN_BUDGET_MAX)

## 从场景真实状态重算 Token 占用 & 每种敌人的数量
func _recalc_token_usage() -> void:
	_token_used = 0
	_token_count_by_type.clear()
	for child in get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			var cost: int = int(child.get_meta("token_cost", 1))
			_token_used += cost
			var t_idx: int = int(child.get_meta("enemy_type_idx", -1))
			if t_idx >= 0:
				_token_count_by_type[t_idx] = int(_token_count_by_type.get(t_idx, 0)) + 1

## 指定敌人类型是否可生成（预算 + 实例上限）
func _can_spawn_type(etype_idx: int, remaining_budget: int) -> bool:
	var cost: int = int(SurvivorData.TOKEN_COST.get(etype_idx, 1))
	if cost > remaining_budget:
		return false
	var cap: int = int(SurvivorData.TOKEN_INSTANCE_CAP.get(etype_idx, -1))
	if cap > 0:
		var cur: int = int(_token_count_by_type.get(etype_idx, 0))
		if cur >= cap:
			return false
	return true

func _pick_enemy_type() -> EnemyType:
	var lvl := survivor_player.level
	var remaining := _get_token_budget() - _token_used

	# MiG-31（顶级 Lancer，单机）：等级 9+ 优先判定，压过普通 MiG
	if lvl >= SurvivorData.MIG31_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.MIG31), remaining):
		var mig31_chance := clampf(
			(lvl - SurvivorData.MIG31_UNLOCK_LEVEL + 1) * SurvivorData.MIG31_CHANCE_PER_LEVEL,
			0.0, SurvivorData.MIG31_CHANCE_MAX)
		if randf() < mig31_chance:
			return EnemyType.MIG31
	# Su-27（主力威胁 + 眼镜蛇机动，单机）：等级 8+ 出现
	if lvl >= SurvivorData.SU27_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.SU27), remaining):
		var su27_chance := clampf(
			(lvl - SurvivorData.SU27_UNLOCK_LEVEL + 1) * SurvivorData.SU27_CHANCE_PER_LEVEL,
			0.0, SurvivorData.SU27_CHANCE_MAX)
		if randf() < su27_chance:
			return EnemyType.SU27
	# MiG：等级 7+ 逐步出现
	if lvl >= SurvivorData.MIG_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.MIG), remaining):
		var mig_chance := clampf(
			(lvl - SurvivorData.MIG_UNLOCK_LEVEL) * SurvivorData.MIG_CHANCE_PER_LEVEL,
			0.0, SurvivorData.MIG_CHANCE_MAX)
		if randf() < mig_chance:
			return EnemyType.MIG
	# F-100（Lancer 编队，雷达弹）：等级 6+ 逐步出现
	if lvl >= SurvivorData.F100_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.F100), remaining):
		var f100_chance := clampf(
			(lvl - SurvivorData.F100_UNLOCK_LEVEL + 1) * SurvivorData.F100_CHANCE_PER_LEVEL,
			0.0, SurvivorData.F100_CHANCE_MAX)
		if randf() < f100_chance:
			return EnemyType.F100
	# 指挥 UAV（Sentinel）：等级 4+ 出现，优先于 J-7 判定
	if lvl >= SurvivorData.COMMANDER_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.UAV_COMMANDER), remaining):
		var cmd_chance := clampf(
			SurvivorData.COMMANDER_CHANCE_BASE + (lvl - SurvivorData.COMMANDER_UNLOCK_LEVEL) * SurvivorData.COMMANDER_CHANCE_PER_LEVEL,
			0.0, SurvivorData.COMMANDER_CHANCE_MAX)
		if randf() < cmd_chance:
			return EnemyType.UAV_COMMANDER
	# MiG-23（Gladiator 综合型，编队）：等级 4+ 逐步出现
	if lvl >= SurvivorData.MIG23_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.MIG23), remaining):
		var mig23_chance := clampf(
			(lvl - SurvivorData.MIG23_UNLOCK_LEVEL + 1) * SurvivorData.MIG23_CHANCE_PER_LEVEL,
			0.0, SurvivorData.MIG23_CHANCE_MAX)
		if randf() < mig23_chance:
			return EnemyType.MIG23
	# Q-5（Lancer 超音速攻击机，机炮+火箭弹编队）：等级 5+ 逐步出现
	if lvl >= SurvivorData.Q5_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.Q5), remaining):
		var q5_chance := clampf(
			(lvl - SurvivorData.Q5_UNLOCK_LEVEL + 1) * SurvivorData.Q5_CHANCE_PER_LEVEL,
			0.0, SurvivorData.Q5_CHANCE_MAX)
		if randf() < q5_chance:
			return EnemyType.Q5
	# 截击机（J-7）：等级 5+ 逐步出现
	if lvl >= SurvivorData.INTERCEPTOR_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.INTERCEPTOR), remaining):
		var int_chance := clampf(
			(lvl - SurvivorData.INTERCEPTOR_UNLOCK_LEVEL) * SurvivorData.INTERCEPTOR_CHANCE_PER_LEVEL,
			0.0, SurvivorData.INTERCEPTOR_CHANCE_MAX)
		if randf() < int_chance:
			return EnemyType.INTERCEPTOR
	# A-7（Lancer 亚音速攻击机，机炮+火箭弹编队）：等级 3+ 逐步出现
	if lvl >= SurvivorData.A7_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.A7), remaining):
		var a7_chance := clampf(
			(lvl - SurvivorData.A7_UNLOCK_LEVEL + 1) * SurvivorData.A7_CHANCE_PER_LEVEL,
			0.0, SurvivorData.A7_CHANCE_MAX)
		if randf() < a7_chance:
			return EnemyType.A7
	# F-86（Gladiator 斗士型）：等级 2+ 逐步出现
	if lvl >= SurvivorData.F86_UNLOCK_LEVEL and _can_spawn_type(int(EnemyType.F86), remaining):
		var f86_chance := clampf(
			(lvl - SurvivorData.F86_UNLOCK_LEVEL + 1) * SurvivorData.F86_CHANCE_PER_LEVEL,
			0.0, SurvivorData.F86_CHANCE_MAX)
		if randf() < f86_chance:
			return EnemyType.F86
	# 后期：所有概率 roll 未命中时，不再回退到低 Token 杂鱼，
	# 而是从已解锁且满足最低 Token 的类型中随机选一个
	if lvl >= SurvivorData.LATE_GAME_LEVEL:
		var candidates: Array[EnemyType] = []
		for etype_int in SurvivorData.TOKEN_COST:
			if SurvivorData.TOKEN_COST[etype_int] >= SurvivorData.LATE_GAME_MIN_TOKEN \
					and _can_spawn_type(etype_int, remaining):
				candidates.append(etype_int as EnemyType)
		if candidates.size() > 0:
			return candidates[randi() % candidates.size()]
	# UAV/UCAV 是等权重的杂鱼 adds，从 1 级一起出现（后期已被上面拦截）
	if _can_spawn_type(int(EnemyType.UCAV), remaining):
		if randf() < 0.5:
			return EnemyType.UCAV
	return EnemyType.UAV

## 生成单架敌机（不含分队），用于 J-7 截击机
func _spawn_single(etype: EnemyType) -> void:
	var spawn_angle := randf() * TAU
	var spawn_pos := player_aircraft.global_position + Vector2(cos(spawn_angle), sin(spawn_angle)) * SurvivorData.SPAWN_DISTANCE
	var to_player := (player_aircraft.global_position - spawn_pos).normalized()
	var heading := rad_to_deg(atan2(to_player.x, -to_player.y))
	_create_enemy(etype, spawn_pos, heading)

## 以分队形式生成一组敌机
func _spawn_squad(etype: EnemyType, squad_size: int) -> void:
	var sq := Squad.new()

	# 长机生成位置
	var spawn_angle := randf() * TAU
	var leader_pos := player_aircraft.global_position + Vector2(cos(spawn_angle), sin(spawn_angle)) * SurvivorData.SPAWN_DISTANCE
	var to_player := (player_aircraft.global_position - leader_pos).normalized()
	var heading := rad_to_deg(atan2(to_player.x, -to_player.y))
	var heading_rad := deg_to_rad(heading)

	for i in range(squad_size):
		var spawn_pos: Vector2
		if i == 0:
			spawn_pos = leader_pos
		else:
			# 僚机按编队偏移生成
			var offset := sq.get_formation_offset(i)
			# heading 转换为弧度并旋转偏移（heading: 0=北）
			spawn_pos = leader_pos + offset.rotated(heading_rad)

		var enemy := _create_enemy(etype, spawn_pos, heading)

		sq.add_member(enemy)
		if i == 0:
			sq.leader = enemy

		# 设置 AI 的编队引用
		var ai := enemy.get_node_or_null("AI_%s" % enemy.name) as AIController
		if not ai:
			for child in enemy.get_children():
				if child is AIController:
					ai = child
					break
		if ai:
			ai.squad = sq
			ai.squad_index = i

	_squads.append(sq)

## 生成指挥 UAV 及其自带小队
func _spawn_commander_squad(wingman_count: int) -> void:
	var sq := Squad.new()

	# 指挥机生成位置
	var spawn_angle := randf() * TAU
	var leader_pos := player_aircraft.global_position + Vector2(cos(spawn_angle), sin(spawn_angle)) * SurvivorData.SPAWN_DISTANCE
	var to_player := (player_aircraft.global_position - leader_pos).normalized()
	var heading := rad_to_deg(atan2(to_player.x, -to_player.y))

	# 生成指挥 UAV（leader）
	var commander := _create_enemy(EnemyType.UAV_COMMANDER, leader_pos, heading)
	sq.add_member(commander)
	sq.leader = commander

	# 挂载光环 + 视觉覆盖
	var aura := CommanderAura.new()
	aura.name = "CommanderAura"
	commander.add_child(aura)

	var overlay := CommanderOverlay.new()
	overlay.name = "CommanderOverlay"
	commander.add_child(overlay)

	# 设置指挥机 AI 的分队引用
	for child in commander.get_children():
		if child is AIController:
			child.squad = sq
			child.squad_index = 0
			break

	# 生成 UAV 僚机（保持 simple_ai + 绕长机飞行 + 自主扫描交战）
	for i in range(wingman_count):
		# 在指挥机附近随机散开生成（不用阵型偏移，简单即可）
		var rand_angle := randf() * TAU
		var rand_dist := randf_range(200.0, 400.0)
		var spawn_pos := leader_pos + Vector2(cos(rand_angle), sin(rand_angle)) * rand_dist
		var wingman := _create_enemy(EnemyType.UAV, spawn_pos, heading)
		sq.add_member(wingman)

		for child in wingman.get_children():
			if child is AIController:
				var wai := child as AIController
				wai.squad = sq
				wai.squad_index = i + 1
				# 关键：保持 simple_ai，启用绕长机飞行
				wai.orbit_squad_leader = true
				wai.shield_leader = true
				wai.enable_combat = true
				wai.evade_missiles = false
				wai.aggression = randf_range(0.7, 0.95)  # 高攻击欲望
				# 清空默认绕玩家航点（与绕长机冲突）
				wai.waypoints = PackedVector2Array()
				break

	_squads.append(sq)

# ══════════════════════════════════════════════
#  Adds 族群系统（独立于 Token / 编队系统）
#  Tu-160 / 其他杂兵通过此系统刷新：
#   - 不占 Token 预算
#   - 不被 _update_far_cleanup 清理（skip_far_cleanup meta）
#   - 不走 Squad 系统（没有阵型偏移 / 长机跟随）
#   - 沿固定直线从 A 飞到 B
# ══════════════════════════════════════════════

## 超过 despawn_after 时间戳的 Adds 静默移除（不触发击杀/经验）
func _cleanup_expired_adds() -> void:
	for child in get_children():
		if child is Aircraft and child.team != 0 and not child.is_destroyed:
			var ac: Aircraft = child
			if ac.has_meta("despawn_after"):
				var t: float = float(ac.get_meta("despawn_after"))
				if game_time >= t:
					ac.set_meta("xp_granted", true)  # 防止 _detect_kills 当成击杀
					ac.queue_free()

## 刷一群 Tu-160 杂兵波次（族群而非编队）
##   - 随机方位选起点 A（距玩家 SPAWN_DISTANCE）
##   - 终点 B = A 的对面方向延伸 TU160_FLIGHT_DISTANCE
##   - 4 架沿 AB 垂直方向排开（有轻微前后错位）
##   - 全程**只沿直线飞**（不转弯，不规避，被击中也没反应）
##   - 超过 120 秒静默消失（防止 skip_far_cleanup 下无限堆积）
func _spawn_tu160_flock() -> void:
	var flock_size: int = SurvivorData.TU160_FLOCK_SIZE
	var pp := player_aircraft.global_position

	# 随机方位角（玩家为圆心）
	var spawn_angle := randf() * TAU
	var spawn_dir := Vector2(cos(spawn_angle), sin(spawn_angle))
	# 起点 A：玩家外圈
	var point_a := pp + spawn_dir * SurvivorData.SPAWN_DISTANCE
	# 终点 B：起点穿过玩家、继续往对面延伸（确保航线经过玩家附近）
	var flight_dir := (pp - point_a).normalized()
	var point_b := point_a + flight_dir * SurvivorData.TU160_FLIGHT_DISTANCE

	# 横向偏置轴（垂直于 AB）
	var lateral_axis := Vector2(-flight_dir.y, flight_dir.x)

	# 航向（沿 AB 方向）
	var heading_deg := rad_to_deg(atan2(flight_dir.x, -flight_dir.y))

	# 族群统一高度层：战略轰炸机永远在 HIGH 作战
	var flock_tier: int = Aircraft.AltitudeTier.HIGH

	# 排布 4 架：横向槽位左右交错，前后小幅错位
	for i in range(flock_size):
		var lateral_slot := float(i) - (float(flock_size) - 1.0) * 0.5
		var base_lateral: Vector2 = lateral_axis * lateral_slot * SurvivorData.TU160_LATERAL_SPACING
		var stagger: float = (float(i % 2) - 0.5) * 2.0 * SurvivorData.TU160_STAGGER_SPACING
		var stagger_offset: Vector2 = flight_dir * stagger

		var spawn_pos := point_a + base_lateral + stagger_offset
		var target_pos := point_b + base_lateral

		var bomber := _create_enemy(EnemyType.TU160, spawn_pos, heading_deg)
		bomber.set_meta("skip_far_cleanup", true)
		bomber.set_meta("category", "adds")
		bomber.set_meta("crash_style", "bomber")
		bomber.set_meta("silhouette", "bomber")

		# 单点直线目标 — 出生时就朝向终点，完全不转弯
		var ai := _get_ai(bomber)
		if ai:
			ai.waypoints = PackedVector2Array([target_pos])
			ai.current_waypoint_index = 0
			ai.arrival_distance = 250.0
			ai.patrol_altitude = randf_range(7000.0, 9000.0)

		bomber.speed = 650.0 / 3.6  # km/h → m/s
		bomber.target_position = target_pos
		bomber.set_target_tier(flock_tier)
		# 生命期上限：Tu-160 有 skip_far_cleanup 不会被远距清理
		# 给 120 秒的自爆期限（120s × 180 m/s × 0.5 px/m ≈ 10800px，够飞完 8000 px 航线）
		bomber.set_meta("despawn_after", game_time + 120.0)

	EventLogger.log_event("WAVE", "Tu160Flock",
		"spawned %d Tu-160 from %s to %s" % [flock_size, point_a, point_b])

## 通用：配置一架 Adds 单位走固定直线航线（Tu-160 / AH-64 / CH-47 共用）
##   - 设置 adds 分类元数据（跳过 hunter / waypoint-rewrite / far-cleanup 系统）
##   - 单点 waypoint 确保直线飞行
##   - 设置速度、高度层、生命期
##   - **关键**：直接把 altitude 设到 tier 对应高度，避免从默认 5000m 慢慢爬升/
##     下降（直升机 15 m/s 爬升率要 200 秒才能下到低空，整个生命期都耗在换高度）
func _configure_adds_unit(unit: Aircraft, target_pos: Vector2, tier: int,
		cruise_kmh: float, silhouette: String, crash_style: String, lifetime_sec: float) -> void:
	unit.set_meta("skip_far_cleanup", true)
	unit.set_meta("category", "adds")
	unit.set_meta("silhouette", silhouette)
	unit.set_meta("crash_style", crash_style)

	var ai := _get_ai(unit)
	if ai:
		ai.waypoints = PackedVector2Array([target_pos])
		ai.current_waypoint_index = 0
		ai.arrival_distance = 250.0

	unit.speed = cruise_kmh / 3.6
	unit.target_position = target_pos
	unit.set_target_tier(tier)
	# 直接赋值初始高度到目标层，保证一出生就在对应高度作战
	unit.altitude = CombatUnit.TIER_ALTITUDE[tier]
	unit.set_meta("despawn_after", game_time + lifetime_sec)

## 刷一队 AH-64 Apache（4 架菱形/楔形编队）
##   - A→B 直线航线，采用 3 层菱形编队：
##       [0] 队长（前）
##     [1]   [2]  （左右两翼，后方一层）
##       [3] （殿后中线，再后一层）
##   - 每架挂 scatter_on_damage meta + flock_members 引用：任何一架被击中 → 整队散开
func _spawn_ah64_flock() -> void:
	var flock_size: int = SurvivorData.AH64_FLOCK_SIZE
	var pp := player_aircraft.global_position

	var spawn_angle := randf() * TAU
	var spawn_dir := Vector2(cos(spawn_angle), sin(spawn_angle))
	var point_a := pp + spawn_dir * SurvivorData.SPAWN_DISTANCE
	var flight_dir := (pp - point_a).normalized()
	var point_b := point_a + flight_dir * SurvivorData.AH64_FLIGHT_DISTANCE
	var lateral_axis := Vector2(-flight_dir.y, flight_dir.x)
	var heading_deg := rad_to_deg(atan2(flight_dir.x, -flight_dir.y))

	# 直升机永远低空飞行
	var flock_tier: int = Aircraft.AltitudeTier.LOW

	# 菱形编队偏移（x = 沿航向前后，y = 侧向；负号代表远离队首）
	var fwd := SurvivorData.AH64_FORWARD_SPACING
	var lat := SurvivorData.AH64_LATERAL_SPACING
	var formation_offsets := [
		Vector2(0.0, 0.0),         # [0] 队长：最前中线
		Vector2(-fwd, -lat),       # [1] 左翼：后一层 + 左偏
		Vector2(-fwd,  lat),       # [2] 右翼：后一层 + 右偏
		Vector2(-fwd * 2.0, 0.0),  # [3] 殿后：再后一层，回到中线
	]

	var heli_list: Array[Aircraft] = []
	for i in range(flock_size):
		var local_off: Vector2 = formation_offsets[i]
		# 把菱形局部坐标旋到世界坐标：x 轴沿 flight_dir，y 轴沿 lateral_axis
		var world_off: Vector2 = flight_dir * local_off.x + lateral_axis * local_off.y
		var spawn_pos := point_a + world_off
		var target_pos := point_b + world_off  # 队形平移飞到终点

		var heli := _create_enemy(EnemyType.AH64, spawn_pos, heading_deg)
		_configure_adds_unit(heli, target_pos, flock_tier, 230.0, "apache", "heli", 140.0)
		heli.set_meta("scatter_on_damage", true)
		heli_list.append(heli)

	# 每架共享同一个 flock_members 列表（受击时 _apply_damage 遍历传播 scatter）
	for heli in heli_list:
		heli.flock_members = heli_list

	EventLogger.log_event("WAVE", "AH64Flock",
		"spawned %d AH-64 (diamond) from %s to %s" % [flock_size, point_a, point_b])

## 刷一队 CH-47 Chinook（纵阵 3 架，间距更大）
func _spawn_ch47_flock() -> void:
	var flock_size: int = SurvivorData.CH47_FLOCK_SIZE
	var pp := player_aircraft.global_position

	var spawn_angle := randf() * TAU
	var spawn_dir := Vector2(cos(spawn_angle), sin(spawn_angle))
	var point_a := pp + spawn_dir * SurvivorData.SPAWN_DISTANCE
	var flight_dir := (pp - point_a).normalized()
	var point_b := point_a + flight_dir * SurvivorData.CH47_FLIGHT_DISTANCE
	var heading_deg := rad_to_deg(atan2(flight_dir.x, -flight_dir.y))

	# 运输直升机永远低空飞行
	var flock_tier: int = Aircraft.AltitudeTier.LOW

	for i in range(flock_size):
		var back_offset: Vector2 = -flight_dir * float(i) * SurvivorData.CH47_COLUMN_SPACING
		var spawn_pos := point_a + back_offset
		var target_pos := point_b + back_offset

		var heli := _create_enemy(EnemyType.CH47, spawn_pos, heading_deg)
		_configure_adds_unit(heli, target_pos, flock_tier, 215.0, "chinook", "heli", 150.0)

	EventLogger.log_event("WAVE", "CH47Flock",
		"spawned %d CH-47 (column) from %s to %s" % [flock_size, point_a, point_b])

## 在玩家附近生成一辆敌方 SAM（防空导弹车）
func _spawn_enemy_sam() -> void:
	_spawn_ground_unit(_sam_scene, _sam_params, 1, 1500.0)

## 在玩家附近生成一辆敌方 AA 炮（高射炮）
func _spawn_enemy_aa() -> void:
	_spawn_ground_unit(_aa_scene, _aa_params, 1, 800.0)

## 地面单位通用生成（与沙盒 debug_panel._spawn_ground_unit 同构）
## 地面单位归类为 Adds：不占 Token、不随机刷新、只由事件/Debug 面板触发
# ══════════════════════════════════════════════
#  王牌中队 BOSS（委托给 AceSquad 模块）
# ══════════════════════════════════════════════

## 生成 F-47 王牌小队（事件/Debug 面板触发）
func _spawn_f47_squad() -> void:
	if _ace_squad and _ace_squad.active:
		return
	_ace_squad = F47AceSquad.new()
	_ace_squad.spawn(self, _aircraft_scene, _create_enemy, player_aircraft,
		bullet_manager, missile_manager, _squads)

func _spawn_ground_unit(scene: PackedScene, params_res: Resource, team_id: int, distance: float) -> void:
	if not player_aircraft or player_aircraft.is_destroyed:
		return
	var pp := player_aircraft.global_position
	var angle := randf() * TAU
	var spawn_pos := pp + Vector2(cos(angle), sin(angle)) * distance
	var unit: GroundUnit = scene.instantiate()
	unit.params = params_res
	unit.team = team_id
	unit.position = spawn_pos
	var to_player := (pp - spawn_pos).normalized()
	unit.initial_heading_deg = rad_to_deg(atan2(to_player.x, -to_player.y))
	# Adds 分类标记：不被 _update_hunters / _update_enemy_waypoints 影响（它们只查 Aircraft）
	# Token 消耗 = 0（地面单位不参与 _recalc_token_usage，后者只查 Aircraft）
	unit.set_meta("category", "adds")
	add_child(unit)
	# 注入管理器
	unit.bullet_manager = bullet_manager
	unit.missile_manager = missile_manager

## 创建单架敌机并添加到场景（公共逻辑）
func _create_enemy(etype: EnemyType, spawn_pos: Vector2, heading_deg: float) -> Aircraft:
	# 选择基础参数
	var base_params: AircraftParams
	match etype:
		EnemyType.MIG:
			base_params = _enemy_params_base
		EnemyType.INTERCEPTOR:
			base_params = _interceptor_params_base
		EnemyType.UCAV:
			base_params = _ucav_params_base
		EnemyType.UAV_COMMANDER:
			base_params = _commander_params_base
		EnemyType.F86:
			base_params = _f86_params_base
		EnemyType.MIG31:
			base_params = _mig31_params_base
		EnemyType.MIG23:
			base_params = _mig23_params_base
		EnemyType.F100:
			base_params = _f100_params_base
		EnemyType.SU27:
			base_params = _su27_params_base
		EnemyType.A7:
			base_params = _a7_params_base
		EnemyType.Q5:
			base_params = _q5_params_base
		EnemyType.TU160:
			base_params = _tu160_params_base
		EnemyType.AH64:
			base_params = _ah64_params_base
		EnemyType.CH47:
			base_params = _ch47_params_base
		EnemyType.F47:
			base_params = _f47_params_base
		_:
			base_params = _uav_params_base

	var enemy: Aircraft = _aircraft_scene.instantiate()
	var enemy_params: AircraftParams = base_params.duplicate(true)
	# 手动 duplicate 所有外部子资源，避免累积修改污染基础资源
	# ⚠ duplicate(true) 只深拷贝 AircraftParams 本身，嵌套的 Resource 字段仍是共享引用
	if enemy_params.missile:
		enemy_params.missile = enemy_params.missile.duplicate()
	if enemy_params.secondary_missile:
		enemy_params.secondary_missile = enemy_params.secondary_missile.duplicate()
	if enemy_params.gun:
		enemy_params.gun = enemy_params.gun.duplicate()
	if enemy_params.flare:
		enemy_params.flare = enemy_params.flare.duplicate()
	if enemy_params.rocket:
		enemy_params.rocket = enemy_params.rocket.duplicate()
	if enemy_params.combat:
		enemy_params.combat = enemy_params.combat.duplicate()

	# 根据等级缩放（载人战机走 enemy_scale_for_level，含 MiG-31/23/F-100）
	var scale: Dictionary
	if etype == EnemyType.MIG or etype == EnemyType.INTERCEPTOR or etype == EnemyType.F86 \
			or etype == EnemyType.MIG31 or etype == EnemyType.MIG23 or etype == EnemyType.F100 \
			or etype == EnemyType.SU27 or etype == EnemyType.A7 or etype == EnemyType.Q5:
		scale = SurvivorData.enemy_scale_for_level(survivor_player.level)
	elif etype == EnemyType.UAV_COMMANDER:
		scale = SurvivorData.commander_scale_for_level(survivor_player.level)
	elif etype == EnemyType.TU160 or etype == EnemyType.AH64 or etype == EnemyType.CH47:
		# Adds 杂兵：无缩放（一击必杀才有设计意义）
		scale = {"hp_mult": 1.0, "missile_add": 0, "gun_damage_mult": 1.0}
	elif etype == EnemyType.F47:
		# F-47 BOSS：无缩放（按满级玩家平衡，固定参数）
		scale = {"hp_mult": 1.0, "missile_add": 0, "gun_damage_mult": 1.0}
	else:
		scale = SurvivorData.uav_scale_for_level(survivor_player.level)

	enemy_params.max_hp *= float(scale["hp_mult"])
	# 导弹一击必杀：除 Sentinel 外，HP 不得超过导弹伤害（确保任何等级被导弹命中即死）
	if etype != EnemyType.UAV_COMMANDER:
		enemy_params.max_hp = minf(enemy_params.max_hp, SurvivorData.ENEMY_HP_MISSILE_CAP)
	if enemy_params.missile:
		enemy_params.missile.max_count += int(scale["missile_add"])
	if enemy_params.gun:
		enemy_params.gun.bullet_damage *= float(scale["gun_damage_mult"])
	# 火箭弹伤害随等级轻度增长（命中率低，整体威���还是有限）
	if (etype == EnemyType.F86 or etype == EnemyType.A7 or etype == EnemyType.Q5) and enemy_params.rocket:
		enemy_params.rocket.rocket_damage *= 1.0 + (survivor_player.level - 1) * 0.04

	# 敌机热诱弹限制：整个生命周期只允许释放一次，且只释放 1 枚
	# （只够干扰玩家第一枚导弹，之后就没弹了，玩家第二发会命中）
	# F-47 BOSS 豁免此限制：6 代电子战允许多次释放
	if enemy_params.flare:
		if etype != EnemyType.F47:
			enemy_params.flare.burst_count = 1
			enemy_params.flare.max_flares = 1
		# 热诱弹失误概率：编队低级机高失误率，精英单机低失误率
		match etype:
			EnemyType.UAV:
				enemy_params.flare.fail_chance = 0.85
			EnemyType.UCAV:
				enemy_params.flare.fail_chance = 0.80
			EnemyType.F86:
				enemy_params.flare.fail_chance = 0.65
			EnemyType.MIG23:
				enemy_params.flare.fail_chance = 0.55
			EnemyType.INTERCEPTOR:
				enemy_params.flare.fail_chance = 0.50
				enemy_params.flare.head_on_fail_reduction = 0.25
			EnemyType.MIG:
				enemy_params.flare.fail_chance = 0.45
			EnemyType.F100:
				enemy_params.flare.fail_chance = 0.45
				enemy_params.flare.head_on_fail_reduction = 0.20
			EnemyType.MIG31:
				enemy_params.flare.fail_chance = 0.15
				enemy_params.flare.head_on_fail_reduction = 0.10
			EnemyType.SU27:
				enemy_params.flare.fail_chance = 0.15
			EnemyType.UAV_COMMANDER:
				enemy_params.flare.fail_chance = 0.0
			EnemyType.AH64:
				# 攻击直升机：战斗机组，反应快但只有 1 枚热诱弹，35% 概率未能释放
				enemy_params.flare.fail_chance = 0.35
			EnemyType.CH47:
				# 运输直升机：机组偏向飞行而非战斗，50% 概率未能释放
				enemy_params.flare.fail_chance = 0.50
			EnemyType.F47:
				# F-47 王牌：6 代电子战套件，不限制为 1 枚（BOSS 豁免热诱弹削弱）
				enemy_params.flare.fail_chance = 0.05
				enemy_params.flare.head_on_fail_reduction = 0.05

	enemy.params = enemy_params
	enemy.team = 1
	enemy.infinite_fuel = true
	enemy.infinite_ammo = true  # 生存模式：所有敌机无限弹药（机炮+导弹永不耗尽）

	# UAV/UCAV/Tu-160 无耐力（载人战机有耐力；Tu-160 虽然有人驾驶但在游戏内走直线，不需要耐力系统）
	if etype != EnemyType.MIG and etype != EnemyType.INTERCEPTOR and etype != EnemyType.F86 \
			and etype != EnemyType.MIG31 and etype != EnemyType.MIG23 and etype != EnemyType.F100 \
			and etype != EnemyType.SU27 and etype != EnemyType.A7 and etype != EnemyType.Q5 \
			and etype != EnemyType.F47:
		enemy.no_stamina = true

	var type_tag: String
	match etype:
		EnemyType.MIG: type_tag = "mig"
		EnemyType.INTERCEPTOR: type_tag = "interceptor"
		EnemyType.F86: type_tag = "f86"
		EnemyType.MIG31: type_tag = "mig31"
		EnemyType.MIG23: type_tag = "mig23"
		EnemyType.F100: type_tag = "f100"
		EnemyType.SU27: type_tag = "su27"
		EnemyType.A7: type_tag = "a7"
		EnemyType.Q5: type_tag = "q5"
		EnemyType.UCAV: type_tag = "ucav"
		EnemyType.UAV_COMMANDER: type_tag = "uav_commander"
		EnemyType.TU160: type_tag = "tu160"
		EnemyType.AH64: type_tag = "ah64"
		EnemyType.CH47: type_tag = "ch47"
		EnemyType.F47: type_tag = "f47"
		_: type_tag = "uav"
	enemy.set_meta("enemy_type", type_tag)
	# Token 系统元数据：便于重算占用与实例计数
	enemy.set_meta("enemy_type_idx", int(etype))
	enemy.set_meta("token_cost", int(SurvivorData.TOKEN_COST.get(int(etype), 1)))

	# UAV 类不使用代号库，直接用类型+编号
	if etype == EnemyType.UAV or etype == EnemyType.UCAV or etype == EnemyType.UAV_COMMANDER:
		_uav_serial += 1
		enemy.callsign = "%s-%02d" % [type_tag.to_upper(), _uav_serial]
	elif etype == EnemyType.TU160:
		# Tu-160 北约代号 Blackjack
		_tu160_serial += 1
		enemy.callsign = "BLKJK-%02d" % _tu160_serial
	elif etype == EnemyType.AH64:
		_ah64_serial += 1
		enemy.callsign = "APA-%02d" % _ah64_serial
	elif etype == EnemyType.CH47:
		_ch47_serial += 1
		enemy.callsign = "CHK-%02d" % _ch47_serial
	elif etype == EnemyType.F47:
		# 呼号由 AceSquad 模块的 _serial 管理，这里用 _ace_squad 的计数器
		if _ace_squad:
			_ace_squad._serial += 1
			enemy.callsign = "%s-%02d" % [_ace_squad.callsign_prefix, _ace_squad._serial]
		else:
			enemy.callsign = "ACE-%02d" % (randi() % 99 + 1)

	enemy.position = spawn_pos
	enemy.initial_heading_deg = heading_deg

	add_child(enemy)

	# 注入管理器
	enemy.bullet_manager = bullet_manager
	enemy.missile_manager = missile_manager
	# 三档高度模式
	enemy.flat_altitude = true
	var enemy_tiers := [Aircraft.AltitudeTier.LOW, Aircraft.AltitudeTier.MID, Aircraft.AltitudeTier.HIGH]
	enemy.set_target_tier(enemy_tiers[randi() % enemy_tiers.size()])

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
	ai.engage_cooldown = 3.0
	ai.engage_duration = 30.0

	match etype:
		EnemyType.MIG:
			ai.evade_missiles = true
			ai.aggression = randf_range(0.6, 0.95)
			ai.engage_cooldown = 2.0
			var level_bonus := clampf(float(survivor_player.level) / 20.0, 0.0, 0.3)
			ai.skill_level = clampf(randf_range(0.3, 0.65) + level_bonus, 0.3, 0.95)
			ai.composure = clampf(randf_range(0.2, 0.55) + level_bonus, 0.2, 0.9)
			ai.focus = clampf(randf_range(0.5, 0.85) + level_bonus * 0.5, 0.5, 0.95)
			ai.self_preservation = randf_range(0.1, 0.5)
		EnemyType.INTERCEPTOR:
			# J-7 = Lancer 骑士型打带跑：开加力单次突击后脱离
			ai.evade_missiles = false
			ai.aggression = randf_range(0.6, 0.8)
			ai.engage_cooldown = 8.0
			ai.engage_duration = 5.0
			var level_bonus_int := clampf(float(survivor_player.level) / 20.0, 0.0, 0.2)
			ai.skill_level = clampf(randf_range(0.3, 0.5) + level_bonus_int, 0.3, 0.7)
			ai.composure = clampf(randf_range(0.2, 0.4) + level_bonus_int, 0.2, 0.6)
			ai.focus = clampf(randf_range(0.3, 0.5) + level_bonus_int * 0.5, 0.3, 0.7)
			ai.self_preservation = randf_range(0.3, 0.6)
			if enemy_params.gun:
				enemy_params.gun = enemy_params.gun.duplicate()
				enemy_params.gun.fire_rate = 2000.0
				enemy_params.gun.bullet_damage *= 0.6
				enemy_params.gun.fire_cone_half_angle = 3.0
		EnemyType.F86:
			# F-86 = Gladiator 斗士型：积极近身狗斗 + 火箭弹骚扰
			ai.evade_missiles = false
			ai.aggression = randf_range(0.85, 1.0)   # 极高攻击欲
			ai.engage_cooldown = 1.5                  # 很快就再次冲锋
			ai.engage_duration = 45.0                 # 持续缠斗
			var lbonus_f86 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.25)
			ai.skill_level = clampf(randf_range(0.4, 0.65) + lbonus_f86, 0.4, 0.9)
			ai.composure = clampf(randf_range(0.35, 0.65) + lbonus_f86, 0.35, 0.9)
			ai.focus = clampf(randf_range(0.65, 0.9) + lbonus_f86 * 0.5, 0.65, 0.95)  # 死盯玩家
			ai.self_preservation = randf_range(0.15, 0.4)  # 不怕死 → 不拉开
			ai.situational_awareness = randf_range(0.4, 0.7)
		EnemyType.MIG31:
			# MiG-31 = Lancer 顶级（最强骑士型）：超高速远距 BVR 截击 + 一击脱离
			# 单机出现，威胁极高；用雷达弹打远距，机炮只是补刀
			ai.evade_missiles = true
			ai.aggression = randf_range(0.7, 0.9)
			ai.engage_cooldown = 6.0                  # 比 J-7 短，但仍长于狗斗机
			ai.engage_duration = 9.0                  # 一次突击 9 秒后脱离
			var lbonus_m31 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.35)
			ai.skill_level = clampf(randf_range(0.6, 0.85) + lbonus_m31, 0.6, 0.98)
			ai.composure = clampf(randf_range(0.55, 0.8) + lbonus_m31, 0.55, 0.95)
			ai.focus = clampf(randf_range(0.7, 0.9) + lbonus_m31 * 0.5, 0.7, 0.98)
			ai.self_preservation = randf_range(0.4, 0.7)
			ai.situational_awareness = randf_range(0.6, 0.85)
		EnemyType.MIG23:
			# MiG-23 = Gladiator 综合型：编队斗士，导弹+机炮通吃，缠斗能力强
			ai.evade_missiles = true
			ai.aggression = randf_range(0.7, 0.95)
			ai.engage_cooldown = 2.0
			ai.engage_duration = 35.0
			var lbonus_m23 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.3)
			ai.skill_level = clampf(randf_range(0.45, 0.7) + lbonus_m23, 0.45, 0.92)
			ai.composure = clampf(randf_range(0.4, 0.65) + lbonus_m23, 0.4, 0.9)
			ai.focus = clampf(randf_range(0.55, 0.85) + lbonus_m23 * 0.5, 0.55, 0.95)
			ai.self_preservation = randf_range(0.2, 0.5)
			ai.situational_awareness = randf_range(0.45, 0.75)
		EnemyType.F100:
			# F-100 = Lancer 编队型：高速突击编队，雷达弹照射后脱离
			# 比 J-7 强（更高 skill / 雷达弹），但比 MiG-31 弱
			ai.evade_missiles = true
			ai.aggression = randf_range(0.65, 0.85)
			ai.engage_cooldown = 5.0
			ai.engage_duration = 7.0
			var lbonus_f100 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.25)
			ai.skill_level = clampf(randf_range(0.45, 0.7) + lbonus_f100, 0.45, 0.85)
			ai.composure = clampf(randf_range(0.4, 0.6) + lbonus_f100, 0.4, 0.8)
			ai.focus = clampf(randf_range(0.5, 0.75) + lbonus_f100 * 0.5, 0.5, 0.85)
			ai.self_preservation = randf_range(0.3, 0.55)
			ai.situational_awareness = randf_range(0.5, 0.75)
		EnemyType.SU27:
			# Su-27 = 斗士型 + 眼镜蛇机动：积极近身狗斗 + 一次性眼镜蛇防御
			ai.evade_missiles = true
			ai.aggression = randf_range(0.8, 1.0)         # 极高攻击欲（斗士型）
			ai.engage_cooldown = 1.5                       # 快速再次冲锋
			ai.engage_duration = 40.0                      # 长时间缠斗
			var lbonus_su27 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.3)
			ai.skill_level = clampf(randf_range(0.55, 0.8) + lbonus_su27, 0.55, 0.95)
			ai.composure = clampf(randf_range(0.5, 0.75) + lbonus_su27, 0.5, 0.9)
			ai.focus = clampf(randf_range(0.7, 0.9) + lbonus_su27 * 0.5, 0.7, 0.95)  # 死盯玩家
			ai.self_preservation = randf_range(0.1, 0.35)  # 不怕死
			ai.situational_awareness = randf_range(0.5, 0.75)
			# 斗士型削弱雷达（偏好狗斗而非 BVR）
			enemy_params.radar_range = 2500.0
			enemy_params.radar_half_angle = 20.0
			# 挂载眼镜蛇机动模块
			var cobra := CobraManeuver.new()
			cobra.name = "CobraManeuver"
			enemy.add_child(cobra)
		EnemyType.A7:
			# A-7 = Lancer 亚音速攻击机：火神炮+祖尼火箭弹，高HP低机动，编队突击
			# 亚音速无后燃器，靠大弹药量和火箭弹齐射制造威胁
			ai.evade_missiles = false
			ai.aggression = randf_range(0.6, 0.8)
			ai.engage_cooldown = 6.0
			ai.engage_duration = 8.0
			var lbonus_a7 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.2)
			ai.skill_level = clampf(randf_range(0.3, 0.55) + lbonus_a7, 0.3, 0.7)
			ai.composure = clampf(randf_range(0.3, 0.5) + lbonus_a7, 0.3, 0.65)
			ai.focus = clampf(randf_range(0.4, 0.65) + lbonus_a7 * 0.5, 0.4, 0.75)
			ai.self_preservation = randf_range(0.3, 0.55)
			ai.situational_awareness = randf_range(0.35, 0.6)
		EnemyType.Q5:
			# Q-5 = Lancer 超音速攻击机（MiG-19 底子）：23mm双炮+57mm火箭弹，编队突击
			# 比 A-7 更快更灵活，但 HP ���低
			ai.evade_missiles = false
			ai.aggression = randf_range(0.65, 0.85)
			ai.engage_cooldown = 5.5
			ai.engage_duration = 7.0
			var lbonus_q5 := clampf(float(survivor_player.level) / 20.0, 0.0, 0.25)
			ai.skill_level = clampf(randf_range(0.35, 0.6) + lbonus_q5, 0.35, 0.75)
			ai.composure = clampf(randf_range(0.3, 0.55) + lbonus_q5, 0.3, 0.7)
			ai.focus = clampf(randf_range(0.45, 0.7) + lbonus_q5 * 0.5, 0.45, 0.8)
			ai.self_preservation = randf_range(0.25, 0.5)
			ai.situational_awareness = randf_range(0.4, 0.65)
		EnemyType.UAV_COMMANDER:
			# Sentinel = Schemer 策士型：��指挥/预警 + 光环 buff 招募僚机
			# 自身无武装，靠特殊机制（CommanderAura）��响战场，玩家靠近即脱离
			ai.simple_ai = true
			ai.enable_combat = false
			ai.evade_missiles = false
			ai.self_preservation = randf_range(0.8, 1.0)
		EnemyType.TU160:
			# Tu-160 = Adds 杂兵：沿固定直线航线飞行，无反击/无规避/无雷达
			# 唯一行为：按 waypoints 直线飞到终点；实际 waypoints 由 _spawn_tu160_flock 设置
			ai.simple_ai = true
			ai.enable_combat = false
			ai.evade_missiles = false
			ai.aggression = 0.0
			ai.self_preservation = 0.0
			ai.orbit_squad_leader = false
		EnemyType.CH47:
			# CH-47 = Adds 运输直升机：纯直线飞行，无武装，无反击
			# 有 1 枚热诱弹（fail_chance 决定是否真的释放，_update_flares 被动触发）
			ai.simple_ai = true
			ai.enable_combat = false
			ai.evade_missiles = false
			ai.aggression = 0.0
			ai.self_preservation = 0.0
			ai.orbit_squad_leader = false
		EnemyType.F47:
			# F-47 = BOSS 王牌狙击小队：第一要务是消灭玩家
			# bvr_only 由 _update_f47_squad 动态控制（被盯上的逃，其他攻击）
			ai.evade_missiles = true
			ai.bvr_only = false                           # 默认不逃——主动攻击
			ai.boss_attacker = true                       # 默认就是攻击手（EVADER 角色才设 false）
			ai.aggression = randf_range(0.90, 1.0)        # 极高攻击欲
			ai.engage_cooldown = 0.5                      # 几乎无冷却
			ai.engage_duration = 999.0                    # 永不自动脱离交战
			ai.skill_level = 0.95                         # 王牌
			ai.composure = 0.95
			ai.focus = 0.95
			ai.self_preservation = randf_range(0.10, 0.25) # 低自保——杀玩家优先
			ai.situational_awareness = 0.95
		EnemyType.AH64:
			# AH-64 = Adds 攻击直升机：带机炮+火箭弹，但 ground_combat_only 限定只攻地面
			# 空中永远不交战，主航线仍是直线飞行；途中遇到地面单位会做 strafing 打击
			# 受击后 _apply_damage 会触发 flock_scatter → AIController 做 jink 机动
			ai.simple_ai = true
			ai.enable_combat = true
			ai.ground_combat_only = true     ## AI 选目标时过滤非 GroundUnit
			ai.evade_missiles = false
			ai.aggression = 0.7
			ai.self_preservation = 0.2
			ai.orbit_squad_leader = false
			ai.engage_duration = 12.0        ## 打完 10 多秒就脱离回航线
			ai.engage_cooldown = 4.0
			enemy.attack_air_targets = false  ## _auto_gun_scan 跳过空中目标（防止扫到玩家）
		_:
			ai.simple_ai = true
			ai.evade_missiles = false
			ai.aggression = randf_range(0.4, 0.7)

	# 斗士型基础机炮闪避：combat_bank_aggression > 1.0 的机型
	# 按 skill_level 梯度：低技能 5%，高技能 15%
	if enemy_params.combat and enemy_params.combat.combat_bank_aggression > 1.0:
		enemy.bullet_dodge_chance = lerpf(0.05, 0.15, ai.skill_level)

	# ── F-47 BOSS 抗性设定 ──
	if etype == EnemyType.F47:
		enemy.bullet_dodge_chance = 0.60   # 60% 闪避 = 40% 命中率（闪避时触发滚转动画）
		enemy.boss_flare_immunity = true   # 热诱弹释放后享有导弹穿透无敌时间

	enemy.add_child(ai)
	return enemy

## 清理无效分队（成员被击毁后自动移除）
func _cleanup_squads() -> void:
	var valid_squads: Array[Squad] = []
	for sq in _squads:
		sq.cleanup()
		if sq.members.size() > 0:
			valid_squads.append(sq)
	_squads = valid_squads

# ══════════════════════════════════════════════
#  击杀检测 & 经验球
# ══════════════════════════════════════════════

func _detect_kills() -> void:
	for child in get_children():
		# ── 飞机击杀检测 ──
		if child is Aircraft and child.team != 0 and child.is_destroyed:
			if not child.has_meta("xp_granted"):
				child.set_meta("xp_granted", true)
				# UAV/UCAV 给较少经验，MiG 给完整经验，Tu-160 给高奖励
				var base_xp := XP_PER_KILL
				var etype: String = child.get_meta("enemy_type", "mig")
				if etype == "uav" or etype == "ucav":
					base_xp = XP_PER_KILL_UAV
				elif etype == "uav_commander":
					base_xp = SurvivorData.XP_PER_KILL_COMMANDER
				elif etype == "tu160":
					base_xp = SurvivorData.XP_PER_KILL_TU160
				elif etype == "ah64":
					base_xp = SurvivorData.XP_PER_KILL_AH64
				elif etype == "ch47":
					base_xp = SurvivorData.XP_PER_KILL_CH47
				elif etype == "f47":
					base_xp = SurvivorData.XP_PER_KILL_F47
				var xp_value := base_xp + survivor_player.level * 8
				survivor_player.add_xp(xp_value)
				kill_count += 1
				_kill_heal()
		# ── 地面单位击杀检测（SAM / AA 炮等）──
		elif child is GroundUnit and child.team != 0 and child.is_destroyed:
			if not child.has_meta("xp_granted"):
				child.set_meta("xp_granted", true)
				var xp_value := SurvivorData.XP_PER_KILL_GROUND + survivor_player.level * 4
				survivor_player.add_xp(xp_value)
				kill_count += 1
				_kill_heal()

## 击杀回血（_detect_kills 共用）
func _kill_heal() -> void:
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
	var p: AircraftParams = player_aircraft.params if player_aircraft else null
	for u in SurvivorData.UPGRADES:
		# 进化技能不进入随机池
		if u.get("evolved", false):
			continue
		# 硬件 / 专属机型筛选
		if not SurvivorData.is_upgrade_available_for(u, _player_profile_id, p):
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
	var stk: int = upgrade_stacks.get(upgrade["id"], 0) + 1
	EventLogger.log_event("UPGRADE", "Player",
		"selected '%s' (stack %d/%d)" % [
			tr(upgrade["name"]), stk, int(upgrade["max_stacks"])])
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
					evolved_name = tr(u["name"])
					break

	is_paused_for_upgrade = false
	get_tree().paused = false

	# 进化提示
	if evolved_name != "":
		if survivor_player.aircraft:
			survivor_player.aircraft.show_tactic_popup(tr("POPUP_EVOLUTION_FMT") % evolved_name)

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
