extends Node2D

## 生存模式主控制器
## 操控/镜头/武器/雷达 全部与沙盒模式一致
## 在此基础上叠加：敌机波次刷新、经验球、等级升级

# ── 共享模块 ──
var _map_features: MapFeatureRenderer
var _camera_ctrl: CameraController
var _weather: WeatherSystem

# ── 场景/资源引用 ──
@onready var camera: Camera2D = $Camera2D
@onready var bullet_manager: BulletManager = $BulletManager
@onready var missile_manager: MissileManager = $MissileManager

var _aircraft_scene: PackedScene
var _player_params_base: AircraftParams

# ── 刷怪系统（委托给 SurvivorSpawner）──
var _spawner: SurvivorSpawner

# ── 地面单位场景/参数（Debug 面板用）──
var _sam_scene: PackedScene
var _sam_params: Resource
var _aa_scene: PackedScene
var _aa_params: Resource

# ── 海上单位参数（Debug 面板用，船没有 .tscn，直接 FrigateShip.new()）──
var _ffg_params: Resource
var _ddg_params: Resource
var _cg_params: Resource
var _cv_params: Resource
var _ss_params: Resource

# ── 通用战区系统（所有 ZoneType 共用）──
var zone_manager: ZoneManager

# ── 操控状态 ──
var selected_aircraft: Array[Aircraft] = []
var is_dragging: bool = false
var drag_start: Vector2 = Vector2.ZERO

# ── 生存模式状态 ──
var player_aircraft: Aircraft
var _player_profile_id: StringName = &""  ## 当前主角的 PlayableAircraft.id（用于专属技能筛选）
var _wingman_formation_debug: bool = false  ## F11 切换：友方僚机编队调试覆盖层
var survivor_player: SurvivorPlayer
var game_time: float = 0.0
var is_game_over: bool = false
var is_paused_for_upgrade: bool = false
var upgrade_stacks: Dictionary = {}

const OFFSCREEN_MARGIN := 500.0    ## 屏幕外判定余量（像素）

# ── 雷达锁定节流（每 RADAR_LOCK_INTERVAL 秒跑一次 O(N²) 循环）──
const RADAR_LOCK_INTERVAL := 0.2
var _radar_lock_accum: float = 0.0
var _all_combat_units_cache: Array[CombatUnit] = []   ## _update_aircraft_list 填充，_update_radar_locks 复用

# ── HUD / UI ──
var hud: SurvivorHUD
var upgrade_ui: SurvivorUpgradeUI
var _tutorial: SurvivorTutorial  ## 首次进入生存模式的浮现式教程

# ── 大地图边界 / 战术地图（P1）──
var _map_boundary: MapBoundary
var _boundary_ui: BoundaryUI
var _tactical_map: TacticalMap
var _zone_data: ZoneData
var _zone_arrow: ZoneArrow
var _zone_hint: ZoneHint
var _zone_mission: ZoneMission
var _adbs: AdbsManager
## BOSS 阶段状态（P4）
var _boss_unlock_announced: bool = false  ## 已提示过"BOSS 出现"
var _boss_spawned: bool = false            ## F-47 小队已生成
var _boss_was_active: bool = false         ## 上一帧 ace_squad.active 状态（用于检测击败沿）
var _is_victory: bool = false              ## 已胜利，阻止重复触发

func _ready() -> void:
	# 确保 SurvivorMode 在所有子节点（含 AI 控制器）之前执行
	# 这样 _f47_assign_roles 设置的 boss_attacker 等标志在 AI 运行时已经生效
	process_priority = -10
	process_physics_priority = -10

	# 海岸线地图：两首战斗泛用 BGM 轮播（播完自动切下一首，周而复始）
	# BOSS 登场时 crossfade 到 boss 曲，会自动退出 playlist 模式
	AudioManager.play_music_playlist(["battle_coast", "battle_coast_2"], 2.0, 2.0)

	# 海岸线大地图：用固定几何数据替代原 TerrainRenderer 的噪声
	_map_features = MapFeatureRenderer.new()
	_map_features.show_behind_parent = true
	add_child(_map_features)
	move_child(_map_features, 0)
	# _map_features.setup() 会在 _map_boundary 创建后调用（见下方）

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
	_sam_scene = preload("res://scenes/sam_unit.tscn")
	_sam_params = preload("res://resources/sam_params.tres")
	_aa_scene = preload("res://scenes/aa_gun_unit.tscn")
	_aa_params = preload("res://resources/aa_gun_params.tres")
	_ffg_params = preload("res://resources/naval/frigate_ffg.tres")
	_ddg_params = preload("res://resources/naval/destroyer_ddg.tres")
	_cg_params = preload("res://resources/naval/cruiser_cg.tres")
	_cv_params = preload("res://resources/naval/carrier_cv.tres")
	_ss_params = preload("res://resources/naval/submarine_ss.tres")

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
	player_aircraft.position = MapBoundary.get_player_start()
	# 相机初始对准玩家起始点 + 启用跟随
	camera.global_position = player_aircraft.position
	_camera_ctrl.set_follow_target(player_aircraft)
	_camera_ctrl.follow_enabled = true
	player_aircraft.bullet_manager = bullet_manager
	player_aircraft.missile_manager = missile_manager
	player_aircraft.selected = true
	add_child(player_aircraft)
	AircraftRenderer.player_ref = player_aircraft
	# 引擎环境音：只给玩家一个循环源，按缩放+视野动态调音量
	AudioManager.start_player_engine(player_aircraft)
	selected_aircraft.append(player_aircraft)

	# 生存模式状态
	survivor_player = SurvivorPlayer.new()
	survivor_player.aircraft = player_aircraft
	survivor_player.leveled_up.connect(_on_player_leveled_up)
	add_child(survivor_player)

	# 刷怪系统（委托给 SurvivorSpawner）
	_spawner = SurvivorSpawner.new()
	add_child(_spawner)
	_spawner.setup(self, player_aircraft, survivor_player, bullet_manager, missile_manager)

	# 起始僚机（小队主控）：仅当档案声明 wingman_count > 0 时生成
	# 必须在 _spawner 初始化之后，因为 _spawn_starting_wingmen 会往 _spawner.get_squads() 追加队伍
	if profile.wingman_count > 0:
		_spawn_starting_wingmen(profile)

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

	# 通用战区系统 + F6 Debug 面板
	zone_manager = ZoneManager.new()
	zone_manager.name = "ZoneManager"
	add_child(zone_manager)
	zone_manager.setup(self, player_aircraft)

	var debug_zone := SurvivorDebugZone.new()
	debug_zone.game_scene = self
	# 新 F6 面板直接从 game_scene 里读 _zone_data / _zone_mission，不再需要 zone_manager
	add_child(debug_zone)

	# ── 大地图边界系统 + 撤退菜单（P1）──
	_map_boundary = MapBoundary.new()
	_map_boundary.player = player_aircraft
	add_child(_map_boundary)
	# 相机钳制：比游戏边界稍大（CAMERA_MARGIN_PX），允许玩家看到边界外少许空域
	_camera_ctrl.set_world_bounds(_map_boundary.get_camera_bounds())
	# 地图特征绘制现在有了世界矩形
	_map_features.setup(camera, _map_boundary.get_world_rect())

	_boundary_ui = BoundaryUI.new()
	add_child(_boundary_ui)
	_map_boundary.approach_warning.connect(_boundary_ui.on_approach)
	_map_boundary.boundary_crossed.connect(_boundary_ui.on_crossed)
	_boundary_ui.retreat_confirmed.connect(_on_retreat_confirmed)
	_boundary_ui.supply_confirmed.connect(_on_supply_confirmed)
	_boundary_ui.cancelled.connect(_on_retreat_cancelled)

	# ── 战术地图 + 战区系统（P2）──
	_zone_data = ZoneData.new()
	# BoundaryUI 需要 _zone_data 来检测 BOSS 阶段（切换警告文案 + 补给阻断由 _on_supply_confirmed 做）
	if _boundary_ui:
		_boundary_ui.zones = _zone_data

	_tactical_map = TacticalMap.new()
	add_child(_tactical_map)
	_tactical_map.setup(_map_boundary.get_world_rect(), player_aircraft, _zone_data, self)
	_tactical_map.zone_selected.connect(_on_zone_selected)

	_zone_arrow = ZoneArrow.new()
	add_child(_zone_arrow)
	_zone_arrow.setup(player_aircraft, camera, _zone_data)

	_zone_hint = ZoneHint.new()
	add_child(_zone_hint)
	_zone_hint.show_persistent(tr("ZONE_HINT_NEW_OPENED"))

	_zone_mission = ZoneMission.new()
	add_child(_zone_mission)
	_zone_mission.setup(self, _zone_data, player_aircraft,
		_sam_scene, _sam_params, _aa_scene, _aa_params,
		bullet_manager, missile_manager, _spawner)
	_zone_mission.mission_triggered.connect(_on_zone_mission_triggered)
	_zone_mission.mission_completed.connect(_on_zone_mission_completed)
	# 回注给 spawner：旅途刷怪需查询"玩家当前是否在战区任务里"
	_spawner.set_zone_mission(_zone_mission)

	# ── ADBS 随机事件系统（P4）──
	_adbs = AdbsManager.new()
	add_child(_adbs)
	_adbs.setup(self, _spawner, player_aircraft, _zone_hint)
	_tactical_map.set_adbs(_adbs)

	# ── 首次进入生存模式：浮现式教程 ──
	if SurvivorTutorial.should_show():
		_start_first_run_tutorial()

## 首次进入生存模式：浮现操作提示 + 在最上方那架 Tu-160 左侧显示"点击攻击"标签
## （不自己刷 Tu-160，已有 Tu-160 场上时由教程内部轮询挂靶）
func _start_first_run_tutorial() -> void:
	_tutorial = SurvivorTutorial.new()
	_tutorial.find_target_fn = _find_topmost_tu160
	add_child(_tutorial)

func _find_topmost_tu160() -> Node2D:
	var best: Aircraft = null
	var best_y := INF
	for child in get_children():
		if not (child is Aircraft) or child.is_destroyed or child.team == 0:
			continue
		if not child.has_meta("silhouette") or child.get_meta("silhouette") != "bomber":
			continue
		if child.global_position.y < best_y:
			best_y = child.global_position.y
			best = child
	return best

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

	_spawner.get_squads().append(sq)

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
	# SPACE：重新启用跟随（镜头平滑回到玩家并锁定，后续持续跟随）
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE and player_aircraft and not player_aircraft.is_destroyed:
		get_viewport().set_input_as_handled()
		_camera_ctrl.set_follow_target(player_aircraft)
		_camera_ctrl.snap_to_follow()
		return
	# Tab：切换战术地图（暂停）
	if event is InputEventKey and event.pressed and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()
		if _tactical_map:
			_tactical_map.toggle()
		return
	# 战术地图打开时，ESC 也用于关闭而不是退主菜单
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and _tactical_map and _tactical_map.is_open():
		get_viewport().set_input_as_handled()
		_tactical_map.close()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().paused = false
		AudioManager.stop_music(1.0)
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
			KEY_1, KEY_2:
				# 武器优先 toggle（对齐 HUD 按钮）
				if player_aircraft.weapon_preference == Aircraft.WeaponPreference.PREFER_MISSILE:
					player_aircraft.weapon_preference = Aircraft.WeaponPreference.PREFER_GUN
				else:
					player_aircraft.weapon_preference = Aircraft.WeaponPreference.PREFER_MISSILE
				return
			KEY_3, KEY_4:
				# 高度偏好 toggle（对齐 HUD 按钮）
				if player_aircraft.altitude_preference == Aircraft.AltitudePreference.PREFER_CLIMB:
					player_aircraft.altitude_preference = Aircraft.AltitudePreference.PREFER_LOW
				else:
					player_aircraft.altitude_preference = Aircraft.AltitudePreference.PREFER_CLIMB
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
				_camera_ctrl.handle_zoom_input(1.0 + CameraController.ZOOM_STEP)
				if is_instance_valid(_tutorial): _tutorial.notify_zoom()
		MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				_camera_ctrl.handle_zoom_input(1.0 - CameraController.ZOOM_STEP)
				if is_instance_valid(_tutorial): _tutorial.notify_zoom()
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
		if is_instance_valid(_tutorial) and event.relative.length_squared() > 1.0:
			_tutorial.notify_pan()
	_camera_ctrl.update_hover(event.global_position, get_children())

func _on_left_click(screen_pos: Vector2) -> void:
	var world_pos := _camera_ctrl.screen_to_world(screen_pos)

	# 优先检测点击附近的敌方飞机
	var enemy := _find_enemy_near(world_pos)
	if enemy:
		for ac in selected_aircraft:
			if is_instance_valid(ac) and not ac.is_destroyed:
				ac.evasion_mode = false  # 选择攻击目标自动关闭规避
				ac.set_combat_target(enemy)
		if is_instance_valid(_tutorial): _tutorial.notify_click_attack()
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
	var best_dist := CameraController.HOVER_RADIUS
	var best: CombatUnit = null
	for child in get_children():
		if child is CombatUnit and child.team != 0 and not child.is_destroyed:
			# 跳过锁定免疫的目标 —— 如 NavalUnit 船体（不可直接锁定 / 攻击只能走 MountTarget 挂点代理）
			# 否则玩家点到船身时 combat_target 会被设为 NavalUnit，但雷达循环从不累积它的
			# radar_targets，导致导弹发射逻辑看不到锁定进度，拒绝开火。
			if child.is_lock_immune():
				continue
			var d := world_pos.distance_to(child.global_position)
			if d < best_dist:
				best_dist = d
				best = child
	return best


# ══════════════════════════════════════════════
#  主循环
# ══════════════════════════════════════════════

func _process(delta: float) -> void:
	_camera_ctrl.update(delta)
	# WASD 自由镜头也算完成"平移"教程项
	if is_instance_valid(_tutorial) and (
			Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A)
			or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_D)):
		_tutorial.notify_pan()
	_cleanup_references()
	_update_aircraft_list()
	_update_radar_locks(delta)
	# MapFeatureRenderer 自己每帧 queue_redraw，不需要在这里触发

func _physics_process(delta: float) -> void:
	if is_game_over or is_paused_for_upgrade:
		return

	game_time += delta

	# 动态性能控制
	_spawner.update_fps_sampling(delta)
	_update_offscreen_lod()
	_update_friendly_squad_lod()

	# 检查玩家是否死亡
	if player_aircraft and player_aircraft.is_destroyed and not is_game_over:
		_on_player_died()
		return

	# 刷怪系统（击杀检测/刷怪/猎手/航点/远距清理/分队清理 全部委托给 spawner）
	_spawner.update(delta)

	# BOSS 阶段：3 个战区攻克后在 BOSS_ZONE 刷 F-47 小队 + 胜利判定
	_update_boss_phase()

	# 清理已坠毁的敌机（节省性能）
	_cleanup_destroyed_enemies()

	# 更新HUD
	hud.game_time = game_time
	hud.kill_count = _spawner.kill_count

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
		elif child is NavalUnit:
			all_units.append(child)
		elif child is CombatUnit:
			# 兜底：MountTarget 等不是 Aircraft/GroundUnit/NavalUnit 的 CombatUnit 子类
			# 它们是船上挂点的锁定代理，必须进 all_units 才能被雷达锁定循环看见
			all_units.append(child)
	bullet_manager.combat_unit_list = all_units
	missile_manager.target_list = all_units
	_all_combat_units_cache = all_units
	CombatUnit.all_units = all_units  # AI / 武器扫描共享引用，消灭多处 get_children() 扫描

func _update_radar_locks(delta: float) -> void:
	# 节流：每 RADAR_LOCK_INTERVAL 秒跑一次 O(N²) 循环
	# 锁定时间 2-4s，0.2s 粒度对玩家不可感知，却把这段最重的循环从 60Hz 降到 5Hz
	_radar_lock_accum += delta
	if _radar_lock_accum < RADAR_LOCK_INTERVAL:
		return
	var step_delta := _radar_lock_accum
	_radar_lock_accum = 0.0

	# 复用 _update_aircraft_list 已经构建的列表
	var all_units := _all_combat_units_cache

	for unit in all_units:
		unit.is_locked = false
		unit.locked_by.clear()
		unit.incoming_lock_progress = 0.0

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
			var in_cone := unit.is_in_radar_cone(other.global_position)
			# ECM 吊舱（战区奖励）：目标自身缩短敌方雷达有效距离
			if in_cone and other is Aircraft and other.ecm_range_mult < 1.0 \
					and unit.params and "radar_range" in unit.params:
				var ecm_range: float = unit.params.radar_range * other.ecm_range_mult
				if unit.global_position.distance_to(other.global_position) > ecm_range:
					in_cone = false
			if in_cone:
				# 低空飞机更难锁定（地面单位不受此影响）
				var lock_rate := _lock_rate_for_target(other)
				# 云层锁定衰减：
				#   - 默认：HIGH 档在云里 ×0.5
				#   - 云雾机动（战区奖励）：任意档位云里 ×0.1（近乎无法锁定）
				if _weather and _cached_is_in_cloud(other):
					if other is Aircraft and other.cloud_lock_stealth:
						lock_rate *= 0.1
					elif other.get_altitude_tier() == CombatUnit.AltitudeTier.HIGH:
						lock_rate *= 0.5
				# 目标自身的锁定抗性（强化吊舱升级）
				if other is Aircraft and other.lock_resistance_mult > 1.0:
					lock_rate /= other.lock_resistance_mult
				# 硬下限：保证 effective_lock_time = threshold / rate ≤ MAX_EFFECTIVE_LOCK_TIME_S
				var shooter_threshold: float = unit.params.lock_time if unit.params else 3.0
				var min_rate: float = shooter_threshold / CombatUnit.MAX_EFFECTIVE_LOCK_TIME_S
				if lock_rate < min_rate:
					lock_rate = min_rate
				var prev: float = unit.radar_targets.get(other, 0.0)
				unit.radar_targets[other] = prev + step_delta * lock_rate
			else:
				var prev: float = unit.radar_targets.get(other, 0.0)
				if prev > 0.0:
					unit.radar_targets[other] = prev - step_delta / 1.5
					if unit.radar_targets[other] <= 0.0:
						unit.radar_targets.erase(other)
				else:
					unit.radar_targets.erase(other)

	for unit in all_units:
		var lock_time_val: float
		if unit is Aircraft and unit.params:
			lock_time_val = unit.params.lock_time
			# 侩子手：玩家锁定时间 ×0.90/层
			lock_time_val *= unit._executioner_lock_mult()
		elif unit is GroundUnit and unit.params:
			lock_time_val = unit.params.lock_time
		else:
			lock_time_val = 3.0
		for target in unit.radar_targets:
			var t: CombatUnit = target
			var progress: float = clampf(unit.radar_targets[target] / lock_time_val, 0.0, 1.0)
			if progress > t.incoming_lock_progress:
				t.incoming_lock_progress = progress
			if unit.radar_targets[target] >= lock_time_val:
				t.is_locked = true
				t.locked_by.append(unit)

	# 限制同时飞向玩家的导弹数量（最多 SurvivorSpawner.MAX_MISSILES_TARGETING_PLAYER）
	if player_aircraft and missile_manager:
		var missiles_at_player := _count_missiles_targeting_player()
		if missiles_at_player >= SurvivorSpawner.MAX_MISSILES_TARGETING_PLAYER:
			# 阻止更多敌机对玩家发射导弹：清除尚未发射的敌机对玩家的锁定
			# 只清除那些还没有在飞导弹指向玩家的敌机的锁定
			for ac in _get_enemies_without_active_missile_at_player():
				var lock_val: float = ac.radar_targets.get(player_aircraft, 0.0)
				var lock_time_val: float = ac.params.lock_time if ac.params else 3.0
				if lock_val >= lock_time_val:
					# 将锁定进度压回刚好低于锁定阈值，阻止发射但保持追踪
					ac.radar_targets[player_aircraft] = lock_time_val - 0.5

## 云层采样缓存（0.3s 有效期 + 位置 >200px 自动失效）
## 雷达锁定循环对每个 HIGH 目标都会查云，节流后仍是 10+ 次/tick，缓存消除噪声采样开销
func _cached_is_in_cloud(unit: CombatUnit) -> bool:
	if not _weather:
		return false
	var now := game_time
	var pos := unit.global_position
	if now - unit._cloud_cache_time < 0.3 and pos.distance_squared_to(unit._cloud_cache_pos) < 40000.0:
		return unit._cloud_cache_result
	unit._cloud_cache_time = now
	unit._cloud_cache_pos = pos
	unit._cloud_cache_result = _weather.is_in_cloud(pos)
	return unit._cloud_cache_result

## 低空飞行目标锁定速率衰减（仅对 Aircraft 生效；地面单位恒定 1.0）
static func _lock_rate_for_target(target: CombatUnit) -> float:
	if not (target is Aircraft):
		return 1.0
	if target.get_altitude_tier() == CombatUnit.AltitudeTier.LOW:
		return 0.7
	return 1.0

## simple_ai 敌机的"全速物理"预算：最近 N 架每帧跑，超出名额的隔帧跑
## 人海战术（大量 UAV）场景下这是最关键的 CPU 节流开关，可按性能需求调
const SIMPLE_AI_FULL_TICK_BUDGET := 6

func _update_offscreen_lod() -> void:
	var cam_pos := camera.global_position
	var vp_size := get_viewport_rect().size / camera.zoom
	var half := vp_size / 2.0 + Vector2(OFFSCREEN_MARGIN, OFFSCREEN_MARGIN)
	var player_pos := player_aircraft.global_position if player_aircraft and not player_aircraft.is_destroyed else cam_pos

	# 先收集所有 onscreen simple_ai 敌机，按距离玩家排序，超出预算的隔帧节流
	var simple_enemies: Array = []   # [ {ac, ai, dist} ]

	for child in get_children():
		if not child is Aircraft or child == player_aircraft:
			continue
		var ac: Aircraft = child
		if ac.is_destroyed:
			continue
		# 友方僚机由 _update_friendly_squad_lod 管
		if ac.team == 0:
			continue

		var rel := ac.global_position - cam_pos
		var offscreen := absf(rel.x) > half.x or absf(rel.y) > half.y

		var ai_node: AIController = null
		for c in ac.get_children():
			if c is AIController:
				ai_node = c
				break

		if offscreen:
			# 离屏：走 Aircraft 自己的 LOD 2 机制（内部处理节流）+ 不画
			# 旧代码 `set_physics_process(frames % 3 == 0)` 是错的：
			# Aircraft._physics_process 每 3 帧才被调用一次，但 delta 还是 1/60s，
			# 结果是"飞机按 1/3 实时速度运行"—— 用户看到的"不拖镜头飞机就冻住"。
			# 正确做法是保持 _physics_process 每帧运行，让 Aircraft LOD 2 内部每帧都
			# _apply_movement（位置推进），每 3 帧做一次完整 AI/物理更新。
			# AIController 通过 ai_tick_divisor（已配合 delta 乘法）承担 AI 节流，simple_ai
			# 在 _ready 里已设为 3，全功能 AI（boss/战斗机）离屏时保持每帧跑，数量有限不造成性能问题。
			# 详见 docs/changelogs/player-ai-log.md 2026-04-20 (8)
			ac.lod_level = 2
			ac.set_physics_process(true)
			if ai_node:
				ai_node.set_physics_process(true)
			ac.visible = false
			continue

		# 屏幕内
		# ⚠ 必须把 lod_level 重置回 0，否则敌机从离屏回屏幕内时 lod_level 卡在 2，导致：
		# 1) _draw/queue_redraw 节流 → label 数据停留在离屏瞬间的 HDG/spd/RNG/FLR 不更新
		# 2) label 跟飞机一起转（inv_rot 用的是过时 rotation 计算的角度补偿）
		# 3) LOD 2 内部 delta*3 物理在屏幕内还继续跑 → 转向过激
		# 敌机（含 simple_ai）屏幕内都应该走完整 LOD 0 路径，用户能看到细节渲染
		# 详见 docs/changelogs/player-ai-log.md 2026-04-20 (11)
		ac.visible = true
		ac.lod_level = 0
		# BOSS 之类关键目标强制全速，不参与预算排队
		var is_critical: bool = ac.has_meta("category") and ac.get_meta("category") == "boss"
		if is_critical or not (ai_node and ai_node.simple_ai):
			ac.set_physics_process(true)
			if ai_node:
				ai_node.set_physics_process(true)
			continue

		# simple_ai 敌机入预算池
		simple_enemies.append({
			"ac": ac,
			"ai": ai_node,
			"dist": ac.global_position.distance_squared_to(player_pos),
		})

	# 按距离玩家升序：前 N 架全速 AI 决策（divisor=3，simple_ai 默认），剩下的放大到 divisor=6
	# Aircraft 本体物理一直每帧跑 → 移动平滑无卡顿；只是 AI 重新选目标/设航向的频率降下来
	simple_enemies.sort_custom(func(a, b): return a["dist"] < b["dist"])
	for i in range(simple_enemies.size()):
		var item: Dictionary = simple_enemies[i]
		item["ac"].set_physics_process(true)
		if not item["ai"]:
			continue
		item["ai"].set_physics_process(true)
		item["ai"].ai_tick_divisor = 3 if i < SIMPLE_AI_FULL_TICK_BUDGET else 6

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

# ══════════════════════════════════════════════
#  地面单位生成（Debug 面板用，不走 Spawner）
# ══════════════════════════════════════════════

## 在玩家附近生成一辆敌方 SAM（防空导弹车）
func _spawn_enemy_sam() -> void:
	_spawn_ground_unit(_sam_scene, _sam_params, 1, 1500.0)

## 在玩家附近生成一辆敌方 AA 炮（高射炮）
func _spawn_enemy_aa() -> void:
	_spawn_ground_unit(_aa_scene, _aa_params, 1, 800.0)

## 在玩家附近生成一艘敌方 FFG 护卫舰（Debug 面板用）
## 直线往返 waypoint：玩家前方 1500 px 附近起刷，两条 5000 px 对角 waypoint 组成往返
func _spawn_enemy_ffg() -> void:
	_spawn_naval_ship(_ffg_params, FrigateShip)

## 在玩家附近生成一艘敌方 DDG 驱逐舰
func _spawn_enemy_ddg() -> void:
	_spawn_naval_ship(_ddg_params, DestroyerShip)

## 在玩家附近生成一艘敌方 CG 巡洋舰
func _spawn_enemy_cg() -> void:
	_spawn_naval_ship(_cg_params, CruiserShip)

## 在玩家附近生成一艘敌方 CV 航母（BOSS 级，非常肉）
## 用 preload 而非 class_name 引用 —— 防止 Godot 全局 class 缓存未更新时 "CarrierShip not declared"
func _spawn_enemy_cv() -> void:
	var cv_script: GDScript = preload("res://scripts/naval/carrier_ship.gd")
	_spawn_naval_ship(_cv_params, cv_script)

## 在玩家附近生成一艘敌方 SS 核潜艇（预留事件 BOSS，目前默认浮出可直接打）
func _spawn_enemy_ss() -> void:
	var ss_script: GDScript = preload("res://scripts/naval/submarine_ship.gd")
	_spawn_naval_ship(_ss_params, ss_script)

## 通用海上单位 spawn：在玩家附近刷一艘，配上直线往返 waypoint + 注入武器管理器
func _spawn_naval_ship(params_res: Resource, ship_class: GDScript) -> void:
	if not player_aircraft or player_aircraft.is_destroyed:
		return
	var pp := player_aircraft.global_position
	var angle := randf() * TAU
	var spawn_pos := pp + Vector2(cos(angle), sin(angle)) * 3000.0

	var ship: NavalUnit = ship_class.new()
	ship.params = params_res
	ship.position = spawn_pos

	# 朝向：沿切线方向（垂直于玩家-船连线）
	var tangent := Vector2(-sin(angle), cos(angle))
	ship.initial_heading_deg = rad_to_deg(atan2(tangent.x, -tangent.y))

	# 直线往返 waypoint（船开起来比较容易观察火力）
	var wp_dir := tangent * 4000.0
	ship.waypoints = PackedVector2Array([spawn_pos + wp_dir, spawn_pos - wp_dir])

	ship.set_meta("category", "adds")
	ship.set_meta("skip_far_cleanup", true)

	add_child(ship)
	ship.bullet_manager = bullet_manager
	ship.missile_manager = missile_manager

## 地面单位通用生成（与沙盒 debug_panel._spawn_ground_unit 同构）
## 地面单位归类为 Adds：不占 Token、不随机刷新、只由事件/Debug 面板触发
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

# ══════════════════════════════════════════════
#  升级流程
# ══════════════════════════════════════════════

func _on_player_leveled_up(_new_level: int) -> void:
	is_paused_for_upgrade = true
	get_tree().paused = true
	AudioManager.set_music_muffled(true)

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
		survivor_player.consume_level_up_display()
		is_paused_for_upgrade = false
		get_tree().paused = false
		AudioManager.set_music_muffled(false)
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

	survivor_player.consume_level_up_display()
	is_paused_for_upgrade = false
	get_tree().paused = false
	AudioManager.set_music_muffled(false)

	# 进化提示
	if evolved_name != "":
		if survivor_player.aircraft:
			survivor_player.aircraft.show_tactic_popup(tr("POPUP_EVOLUTION_FMT") % evolved_name)

func _on_player_died() -> void:
	is_game_over = true
	hud.show_game_over(survivor_player.level, game_time, _spawner.kill_count)

# ══════════════════════════════════════════════
#  边界 / 撤退菜单回调（P1）
# ══════════════════════════════════════════════

func _on_retreat_confirmed() -> void:
	# 撤退 = 结束本局，走死亡结算入口（沿用 HUD 的 game_over 面板）
	EventLogger.log_event("BOUNDARY", "Retreat",
		"lvl=%d time=%.0fs kills=%d" % [survivor_player.level, game_time, _spawner.kill_count])
	is_game_over = true
	hud.show_game_over(survivor_player.level, game_time, _spawner.kill_count)

func _on_supply_confirmed() -> void:
	# BOSS 阶段禁用补给 —— 防止玩家反复贴边回血刷 BOSS
	# 显示 toast 告诉玩家「无法补给，返回战场」，并把机头转回内部
	if _zone_data and _zone_data.is_boss_phase():
		if _zone_hint:
			_zone_hint.show_temp(tr("BOUNDARY_SUPPLY_BLOCKED_BOSS"), 4.0)
		_turn_player_inward()
		EventLogger.log_event("BOUNDARY", "SupplyBlockedBoss", "boss_phase")
		return
	# 回血 + Token 加成（代价是敌人变强）
	if player_aircraft and not player_aircraft.is_destroyed and player_aircraft.params:
		player_aircraft.hp = player_aircraft.params.max_hp
	if _spawner:
		_spawner.add_supply_token_bonus()
	# 机头转向地图中心，玩家自然飞回内部
	_turn_player_inward()
	EventLogger.log_event("BOUNDARY", "Supply", "hp_restored, token +%d" % SurvivorSpawner.SUPPLY_TOKEN_GAIN)

func _on_retreat_cancelled() -> void:
	# 取消：机头转向地图中心，不传送，玩家自己飞回
	_turn_player_inward()

## 战术地图选中战区（P2）
func _on_zone_selected(zone_id: StringName) -> void:
	EventLogger.log_event("ZONE", "Selected", "id=%s" % zone_id)
	# 选定后清理"新战区已开放"提示条（持久）
	if _zone_hint:
		_zone_hint.hide_persistent()
	# 消费掉 newly_opened 标记
	if _zone_data:
		_zone_data.take_newly_opened()

func _on_zone_mission_triggered(zone_id: StringName) -> void:
	# 自动进入战区 = 自动开始任务；同时清掉顶部"新战区已开放"提示
	if _zone_hint:
		_zone_hint.hide_persistent()
		var mt: String = _zone_data.get_mission_type(zone_id) if _zone_data else "ground"
		var fmt_key: String
		match mt:
			"air":       fmt_key = "ZONE_MISSION_STARTED_AIR_FMT"
			"squadron":  fmt_key = "ZONE_MISSION_STARTED_SQUADRON_FMT"
			"elite":     fmt_key = "ZONE_MISSION_STARTED_ELITE_FMT"
			"naval":     fmt_key = "ZONE_MISSION_STARTED_NAVAL_FMT"
			_:           fmt_key = "ZONE_MISSION_STARTED_FMT"
		_zone_hint.show_temp(tr(fmt_key) % _zone_label(zone_id), 3.0)
	if _zone_data:
		_zone_data.take_newly_opened()

func _on_zone_mission_completed(zone_id: StringName) -> void:
	if not _zone_data:
		return
	var reward: Dictionary = _zone_data.get_reward(zone_id)
	# 发放奖励
	var reward_name := ""
	if not reward.is_empty() and survivor_player:
		survivor_player.apply_upgrade(reward)
		reward_name = tr(reward.get("name", ""))
		# 写入 upgrade_stacks，否则右下角 HUD 已激活技能列表不会显示战区奖励
		var rid: String = reward.get("id", "")
		if rid != "":
			upgrade_stacks[rid] = upgrade_stacks.get(rid, 0) + 1
	# 基础回血：每攻克一个战区 +ZONE_CLEAR_HP_RESTORE，夹到 max_hp
	var hp_gained := 0.0
	if player_aircraft and not player_aircraft.is_destroyed and player_aircraft.params:
		var max_hp: float = player_aircraft.params.max_hp
		var before: float = player_aircraft.hp
		player_aircraft.hp = minf(player_aircraft.hp + ZoneData.ZONE_CLEAR_HP_RESTORE, max_hp)
		hp_gained = player_aircraft.hp - before
	_zone_data.mark_cleared(zone_id)
	# 清掉 zone_mission 内部对该战区的记录；下次该战区再进入 AVAILABLE 时会重新刷
	if _zone_mission:
		_zone_mission.reset_zone(zone_id)
		## 2026-04-21：攻克后对其他仍空闲的战区做一次"按当前等级"的敌情升级
		## 已进入交战的战区不会被刷新（避免打到一半敌人换型）
		var refreshed: Array[StringName] = _zone_mission.refresh_active_zones_for_level(zone_id)
		if refreshed.size() > 0 and _zone_hint:
			_zone_hint.show_temp(tr("ZONE_REFRESHED_AFTER_CLEAR"), 3.0)
	EventLogger.log_event("ZONE", "Cleared",
		"id=%s reward=%s hp+%d" % [zone_id, reward.get("id", "-"), int(hp_gained)])

	# 攻克 toast
	var label := _zone_label(zone_id)
	if _zone_hint:
		var msg: String
		if reward_name != "":
			msg = tr("ZONE_CLEARED_WITH_REWARD_FMT") % [label, reward_name]
		else:
			msg = tr("ZONE_CLEARED_FMT") % label
		_zone_hint.show_temp(msg, 4.5)

	# 新战区开放 → 再挂 persistent 提示
	var opened := _zone_data.peek_newly_opened()
	if opened.size() > 0:
		# 用 call_deferred 让 toast 先显示完再闪 persistent（不冲突，zone_hint 支持两者共存）
		_zone_hint.show_persistent(tr("ZONE_HINT_NEW_OPENED"))

## 系统铁则：世界坐标是否在玩家屏幕可见范围内
## 供 spawner / zone_mission / adbs_manager 刷新前做可见性检查
const VIEW_SPAWN_MARGIN_PX := 200.0  ## 屏外 200px 缓冲，避免贴边刷新被玩家瞥见
## extra_radius：把以 world_pos 为圆心、半径 extra_radius 的圆视作一个整体来测
## 可见（用于"战区整个生成区域是否会露脸"这种判定，而不只是测中心点）
func is_world_pos_visible(world_pos: Vector2, extra_radius: float = 0.0) -> bool:
	if not _camera_ctrl:
		return false
	return _camera_ctrl.is_world_pos_visible(world_pos, VIEW_SPAWN_MARGIN_PX + extra_radius)

## BOSS 阶段（P4）——3 个战区攻克后在 BOSS_ZONE 刷 F-47 小队
func _update_boss_phase() -> void:
	if _is_victory or is_game_over:
		return
	if not _zone_data or not _zone_data.boss_unlocked:
		return

	# 第一次解锁 → 挂 persistent 提示
	if not _boss_unlock_announced:
		_boss_unlock_announced = true
		if _zone_hint:
			_zone_hint.show_persistent(tr("ZONE_HINT_BOSS_UNLOCKED"))
		EventLogger.log_event("BOSS", "Unlock", "F-47 squad awaits at BOSS_ZONE")

	# 玩家进入 BOSS_ZONE 圆 → 触发 F-47 小队
	if not _boss_spawned and player_aircraft and not player_aircraft.is_destroyed:
		var boss_zone := ZoneData.BOSS_ZONE
		var d: float = player_aircraft.global_position.distance_to(boss_zone["center"])
		if d <= float(boss_zone["radius"]) + BOSS_ZONE_ENTRY_BUFFER_PX:
			_boss_spawned = true
			# 【硬规则】玩家直接飞入 BOSS_ZONE（没走战术地图点击）时也要把 selected_id 切到 BOSS，
			# 否则 is_boss_phase() 永远 false，所有"BOSS 阶段早退"守卫（刷怪 / 猎手 /
			# 战区地图隐藏 / _update_boss_phase_purge / 敌机绕玩家航点）全部失效。
			if _zone_data.selected_id != &"BOSS":
				_zone_data.select_zone(&"BOSS")
			if _zone_hint:
				_zone_hint.hide_persistent()
				_zone_hint.show_warning_banner("WARNING  WARNING")
				_zone_hint.show_temp(tr("ZONE_HINT_BOSS_ARRIVAL"), 5.0)
			_spawner._spawn_f47_squad(boss_zone["center"])
			EventLogger.log_event("BOSS", "Spawn",
				"F-47 engaging at BOSS_ZONE anchor=%s" % boss_zone["center"])

	# 胜利判定：曾生成且 ace_squad 从 active 变 inactive = 全灭
	if _boss_spawned and _spawner:
		var ace := _spawner.get_ace_squad()
		if ace:
			if _boss_was_active and not ace.active:
				_on_victory()
			_boss_was_active = ace.active

func _on_victory() -> void:
	if _is_victory:
		return
	_is_victory = true
	is_game_over = true  # 复用 game_over 流程，阻止后续物理
	EventLogger.log_event("VICTORY", "Clear", "BOSS defeated — game cleared")
	if hud:
		hud.show_victory(survivor_player.level, game_time, _spawner.kill_count)

func _zone_label(zone_id: StringName) -> String:
	if not _zone_data:
		return str(zone_id)
	var z := _zone_data.get_zone_by_id(zone_id)
	if z.is_empty():
		return str(zone_id)
	return z.get("label", str(zone_id))

## 把玩家传送回边界内侧 + 机头朝向地图中心
## 回归时只钳到边界线上（0 margin），玩家从边缘线继续飞回战区，没有"瞬移闪烁"感
const RESPAWN_MARGIN_PX := 0.0
const RESPAWN_INWARD_TARGET_PX := 2500.0 ## 传送后 target_position 指向原点方向的距离
const BOSS_ZONE_ENTRY_BUFFER_PX := 500.0 ## 进入 BOSS_ZONE 圆的宽松余量

func _turn_player_inward() -> void:
	if not player_aircraft or not _map_boundary:
		return
	var r := _map_boundary.get_world_rect()
	var p := player_aircraft.global_position
	var was_outside := not r.has_point(p)
	# 只在真越界时钳回边界线上（0 margin，不再把玩家拉离边缘几公里）
	p.x = clampf(p.x, r.position.x, r.end.x)
	p.y = clampf(p.y, r.position.y, r.end.y)
	player_aircraft.global_position = p
	# heading 指向原点（0=北，顺时针）：atan2(-p.x, p.y)
	if not p.is_equal_approx(Vector2.ZERO):
		player_aircraft.heading = atan2(-p.x, p.y)
	player_aircraft.bank_angle = 0.0
	# 只有越界被钳回时才清丝带 + 同步相机，避免边界内点取消菜单出现视觉瞬跳
	if was_outside:
		player_aircraft.clear_trail()
		camera.global_position = p
	var inward := (Vector2.ZERO - p).normalized() if not p.is_equal_approx(Vector2.ZERO) else Vector2(0, -1)
	player_aircraft.target_position = p + inward * RESPAWN_INWARD_TARGET_PX
