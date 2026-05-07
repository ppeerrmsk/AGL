## Carrier Strike Group BOSS —— 航母战斗群
##
## 设计流程：
##   Phase 1: CV 航母（旗舰）+ 2 CG + 1 DDG + 2 FFG 刚体舰队航行
##   Phase 2 触发：CV 沉没 → 航母爆炸前最后一击弹射 4 架 F-14 Poltergeist
##          弹射从 CV 死亡位置沿 CV 最后朝向依次滑出（每架 1.2 秒间隔）
##   胜利条件：CV 沉没 AND Poltergeist 中队全灭
##
## 与 AceSquad 架构关系：
##   - CSG 本身继承 BossEncounter（管理舰队 + 相位切换）
##   - Phase 2 的 PoltergeistSquad 是 AceSquad 子类（复用飞机小队战术）
##   - CSG.update 每帧同步 Poltergeist.anchor_position = CV.global_position，
##     让 F-14 永远跟随 CV 盘旋
##
## BGM：
##   bgm_track      → Phase 1 BGM id
##   bgm_phase2     → Phase 2 BGM id（F-14 弹射时切歌）
class_name CarrierStrikeGroup
extends BossEncounter

const FrigateShipScript   := preload("res://scripts/naval/frigate_ship.gd")
const DestroyerShipScript := preload("res://scripts/naval/destroyer_ship.gd")
const CruiserShipScript   := preload("res://scripts/naval/cruiser_ship.gd")
const CarrierShipScript   := preload("res://scripts/naval/carrier_ship.gd")

# ── Phase 2 触发 ──
## CV 沉没瞬间触发 F-14 弹射（"最后一搏"的戏剧化时刻）
## 捕获 CV 死亡时的位置和朝向，Poltergeist 沿该方向依次起飞

# ── 舰队几何（BOSS 战区像素尺度；BOSS_ZONE radius ≈ 2200 px，舰队要能装进去）──
const CV_PATROL_HALF_SPAN: float = 1500.0     ## CV 往返直线半程（紧贴 zone 中心，舰队不脱环）
const ESCORT_OFFSETS: Array[Vector2] = [
	# (前后, 左右) 相对旗舰本地坐标；+X 船头，+Y 右舷
	# 舰队 bbox 约 1500×1100 px（≈3.0 km × 2.2 km）—— 紧密护卫队形
	# 拉近后 CIWS 拦截网交叉覆盖更密，玩家从单侧突防更难钻空当
	Vector2(650, -500),     # 前左 CG
	Vector2(650, 500),      # 前右 CG
	Vector2(-380, 0),       # 贴身后卫 DDG（CV 半长 210 + DDG 半长 90 + ~80 间隙）
	Vector2(-850, -550),    # 后左 FFG
	Vector2(-850, 550),     # 后右 FFG
]

# ── 身份默认值（可被 BossRegistry 覆盖）──
func _init() -> void:
	display_name = "CARRIER STRIKE GROUP"
	callsign_prefix = "CSG"
	bgm_track = ""                            ## 层叠模式下 bgm_track 不使用，置空避免误调
	bgm_layers = ["boss_csg", "boss_csg_phase2"]  ## Phase 1 + Phase 2 同步层叠

# ── BGM（Phase 2）──
var bgm_phase2: String = "boss_csg_phase2"    ## Phase 2 BGM id（保留字段供日志/引用，切换走 layer index）

# ── 运行时状态 ──
var _cv: NavalUnit = null                     ## 旗舰航母
var _escorts: Array[NavalUnit] = []           ## 护航舰
var _phase: int = 1                           ## 1 = 舰队战；2 = CV 沉没后 F-14 弹射
var _poltergeist: PoltergeistSquad = null    ## Phase 2 小队（Phase 1 为 null）
## CV 沉没瞬间捕获的位置/朝向，供 Poltergeist 弹射使用（CV 残骸过几秒会消失）
var _cv_death_position: Vector2 = Vector2.INF
var _cv_death_heading: float = 0.0

# ── F/A-18 持续弹射（Phase 1 战斗期间）──
const FA18_INITIAL_COUNT: int = 2             ## engage() 瞬间弹射数（一对编队）
const FA18_PERIODIC_INTERVAL: float = 120.0   ## 每 2 分钟弹射一架补充
const FA18_TAKEOFF_GRACE: float = 4.0         ## 起飞保护期（与 Poltergeist 同步）
const FA18_INITIAL_LATERAL_OFFSET: float = 220.0 ## 初始两架左右分开像素距离
var _fa18_engaged: bool = false               ## engage() 是否已经触发（防止重复）
var _fa18_periodic_timer: float = 0.0         ## 距离下一次定期弹射的剩余秒数
var _fa18_alive: Array[Aircraft] = []         ## 跟踪存活的 F/A-18，用于胜利判定 / 清理

# ── spawn 时注入的外部依赖（Phase 2 要用）──
var _mode: Node2D = null
var _aircraft_scene: PackedScene = null
var _create_enemy_func: Callable
var _player: Aircraft = null
var _bullet_mgr: BulletManager = null
var _missile_mgr: MissileManager = null
var _squads_ref: Array[Squad] = []

# ══════════════════════════════════════════════
#  生成（Phase 1：刷舰队）
# ══════════════════════════════════════════════

func spawn(mode: Node2D, aircraft_scene: PackedScene, create_enemy_func: Callable,
		player: Aircraft, bullet_mgr: BulletManager, missile_mgr: MissileManager,
		squads: Array[Squad], anchor: Vector2) -> void:
	if active:
		return
	if anchor == Vector2.INF:
		push_error("CarrierStrikeGroup.spawn: anchor is INF")
		return

	_mode = mode
	_aircraft_scene = aircraft_scene
	_create_enemy_func = create_enemy_func
	_player = player
	_bullet_mgr = bullet_mgr
	_missile_mgr = missile_mgr
	_squads_ref = squads

	active = true
	_phase = 1

	# 加载舰队参数
	var cv_params: Resource = load("res://resources/naval/carrier_cv.tres")
	var cg_params: Resource = load("res://resources/naval/cruiser_cg.tres")
	var ddg_params: Resource = load("res://resources/naval/destroyer_ddg.tres")
	var ffg_params: Resource = load("res://resources/naval/frigate_ffg.tres")
	if cv_params == null or cg_params == null or ddg_params == null or ffg_params == null:
		push_error("CarrierStrikeGroup.spawn: missing naval params")
		active = false
		return

	# 旗舰 CV 走直线往返：沿 initial_heading_deg 方向前进，到端点 180° U-turn
	# heading 约定：0°=北=-Y 世界方向
	var heading_rad: float = deg_to_rad(initial_heading_deg)
	var fwd: Vector2 = Vector2(sin(heading_rad), -cos(heading_rad))
	var cv_wps := PackedVector2Array([
		anchor + fwd * CV_PATROL_HALF_SPAN,
		anchor - fwd * CV_PATROL_HALF_SPAN,
	])
	_cv = _make_ship(CarrierShipScript, cv_params, anchor, initial_heading_deg, cv_wps)
	_cv.is_mission_target = true

	# CV 甲板停 2 架舰载机（可选：不和 Phase 2 的 4 架 F-14 冲突，留空）
	# 如果想让 CV 自带 2 架标准僚机 + Phase 2 弹射 4 架 F-14，下一行取消注释
	# if _cv is CarrierShip: (_cv as CarrierShip).spawn_escort_aircraft(_mode)

	# 护航舰队
	var escort_plan: Array = [
		{"cls": CruiserShipScript,   "params": cg_params,  "off": ESCORT_OFFSETS[0]},
		{"cls": CruiserShipScript,   "params": cg_params,  "off": ESCORT_OFFSETS[1]},
		{"cls": DestroyerShipScript, "params": ddg_params, "off": ESCORT_OFFSETS[2]},
		{"cls": FrigateShipScript,   "params": ffg_params, "off": ESCORT_OFFSETS[3]},
		{"cls": FrigateShipScript,   "params": ffg_params, "off": ESCORT_OFFSETS[4]},
	]
	for plan in escort_plan:
		_spawn_escort(plan["cls"], plan["params"], plan["off"])

	EventLogger.log_event("BOSS", display_name, "%s Phase 1 engaged (CV + %d escorts)" % [display_name, _escorts.size()])

## 收集所有舰船单位（CV + 护卫）—— 事件层用来批量下 directive
func get_all_ships() -> Array:
	var arr: Array = []
	if _cv != null and is_instance_valid(_cv):
		arr.append(_cv)
	for escort in _escorts:
		if is_instance_valid(escort):
			arr.append(escort)
	return arr

# ══════════════════════════════════════════════
#  每帧更新
# ══════════════════════════════════════════════

func update(delta: float) -> void:
	if not active:
		return

	# Phase 1: F/A-18 持续弹射（CV 还活着的时候）
	if _phase == 1 and _fa18_engaged:
		_update_fa18_periodic_launch(delta)

	# Phase 1: 监测 CV 沉没瞬间 → 捕获死亡位置/朝向 → 进 Phase 2
	if _phase == 1 and _should_trigger_phase2():
		_enter_phase2()

	# Phase 2：F-14 中队盘旋 anchor 在 CV 死亡位置（CV 残骸可能已消失）
	if _phase == 2 and _poltergeist and _poltergeist.active:
		_poltergeist.anchor_position = _cv_death_position
		_poltergeist.update(delta)
		# 小地图 BOSS 圈跟随 F-14 群质心（已 FLYING 的成员），让玩家在远距能看见 BOSS 在哪
		_sync_boss_zone_to_poltergeist()

	# 胜利判定
	_check_victory()

# ══════════════════════════════════════════════
#  接战入口（boss_encounter_event PRE_STAGE → ENGAGED 时调用）
# ══════════════════════════════════════════════

## 玩家进入 BOSS 圈瞬间触发 — 先弹射两架 F/A-18 见面礼，并启动 2 分钟定期补充
func engage() -> void:
	if _fa18_engaged:
		return
	_fa18_engaged = true
	_fa18_periodic_timer = FA18_PERIODIC_INTERVAL
	# 立即弹射 2 架（一对编队，左右分开）
	for i in range(FA18_INITIAL_COUNT):
		var lateral_idx: float = float(i) - float(FA18_INITIAL_COUNT - 1) * 0.5  # -0.5, +0.5 两架
		_launch_fa18(lateral_idx * FA18_INITIAL_LATERAL_OFFSET)
	EventLogger.log_event("BOSS", display_name,
			"engaged: %d F/A-18 launched, periodic catapult every %.0fs" % [FA18_INITIAL_COUNT, FA18_PERIODIC_INTERVAL])

## 每帧 tick — 计时到了刷一架（CV 还活着才刷；CV 沉没即停止）
func _update_fa18_periodic_launch(delta: float) -> void:
	# 清理已死的 F/A-18 引用（避免数组膨胀，胜利判定看 _phase/_poltergeist 不需要这个数组）
	var alive: Array[Aircraft] = []
	for ac in _fa18_alive:
		if is_instance_valid(ac) and not ac.is_destroyed:
			alive.append(ac)
	_fa18_alive = alive
	# CV 已死或正在死 → 不再刷
	if _cv == null or not is_instance_valid(_cv) or _cv.is_destroyed:
		return
	_fa18_periodic_timer -= delta
	if _fa18_periodic_timer <= 0.0:
		_fa18_periodic_timer = FA18_PERIODIC_INTERVAL
		_launch_fa18(0.0)
		EventLogger.log_event("BOSS", display_name,
				"periodic F/A-18 catapult (1 launched, %d alive)" % _fa18_alive.size())

## 单架 F/A-18 弹射：CV 位置 + CV 当前朝向 + lateral 偏移（米/像素同尺度）
## 起飞后立即开火（不像 Poltergeist 走 4 秒滑跑动画 — 设计上"补充梯队"节奏快）
## 给一段 takeoff grace，玩家短暂内无法锁定 + 飞机自爬到作战高度
func _launch_fa18(lateral_offset: float) -> void:
	if _cv == null or not is_instance_valid(_cv):
		return
	var heading: float = _cv.heading
	var fwd := Vector2(sin(heading), -cos(heading))
	var stb := Vector2(cos(heading), sin(heading))
	var spawn_pos: Vector2 = _cv.global_position + fwd * 60.0 + stb * lateral_offset
	var heading_deg: float = rad_to_deg(heading)
	var hornet := director_create_enemy(SurvivorSpawner.EnemyType.FA18, spawn_pos, heading_deg)
	if hornet == null:
		return
	# 起飞参数：拉到低空作战高度，开 AB
	hornet.altitude = 800.0
	hornet.vertical_speed = 80.0
	hornet.set_target_tier(CombatUnit.AltitudeTier.MID)
	hornet.is_afterburner = true
	hornet._lock_immunity_timer = FA18_TAKEOFF_GRACE
	# 标识为 CSG 派生（survivor_spawner 远距清理跳过 + HUD 不显示血条）
	hornet.set_meta("category", "boss_csg_aircraft")
	hornet.set_meta("skip_far_cleanup", true)
	# 让玩家成为目标 — combat_target 由 AI 雷达扫描自动获取，这里不强设
	_fa18_alive.append(hornet)

## 调 spawner._create_enemy（保留为内部辅助，防止 spawner 接口变化时一处定位）
func director_create_enemy(etype: int, spawn_pos: Vector2, heading_deg: float) -> Aircraft:
	if not _create_enemy_func.is_valid():
		return null
	return _create_enemy_func.call(etype, spawn_pos, heading_deg)

## Phase 2 触发：CV 沉没（is_destroyed=true 的第一帧，趁 CV 节点还没 queue_free）
func _should_trigger_phase2() -> bool:
	return _cv != null and is_instance_valid(_cv) and _cv.is_destroyed

func _enter_phase2() -> void:
	_phase = 2
	# 捕获 CV 死亡时的位置和朝向（之后 CV 残骸会 queue_free，引用失效）
	_cv_death_position = _cv.global_position
	_cv_death_heading = _cv.heading
	# 弹射甲板上的停机舰载机（若 CV 预先有）
	if _cv is CarrierShip:
		(_cv as CarrierShip).launch_escort_aircraft()
	# 刷 Poltergeist 中队：anchor 在 CV 位置，沿 CV heading 起飞方向排队滑出
	_poltergeist = PoltergeistSquad.new()
	_poltergeist.anchor_position = _cv_death_position
	# entry_angle 让生成朝向恰好等于 CV heading（参考 AceSquad.spawn：heading_deg = entry_angle+PI）
	_poltergeist.entry_angle_override = _cv_death_heading - PI
	_poltergeist.spawn(_mode, _aircraft_scene, _create_enemy_func, _player,
			_bullet_mgr, _missile_mgr, _squads_ref)
	# 立即触发 PURSUIT — 否则 AceSquad combat_phase_active=false 会让状态机停摆，
	# 也就让 poltergeist_squad.gd 弹射结束的 ENGAGE 同步守卫拒绝触发
	_poltergeist.engage()
	# 切 Phase 2 BGM：层叠模式下只压音量，两轨继续同步播放 —— 无缝衔接
	AudioManager.set_music_layer(1, 2.5)
	EventLogger.log_event("BOSS", display_name,
			"Phase 2: CV sunk, F-14 catapult launch begins at %s heading=%.0f°" % [_cv_death_position, rad_to_deg(_cv_death_heading)])

## 把战术小地图的 boss_zone 中心移到 F-14 群质心（已揭幕的成员位置平均）。
## 没有揭幕成员时退回 _cv_death_position（FROZEN 期 / 弹射中）。
## 不修改 boss_zone radius —— 让玩家依旧看到完整 BOSS 圈范围。
## 调用频次：每帧 update() 一次（CSG.update 每帧调一次本函数）；写入 Dictionary 是廉价操作，
## minimap 在 _on_map_draw 里读取，自然反映最新值。
func _sync_boss_zone_to_poltergeist() -> void:
	if _mode == null or not is_instance_valid(_mode):
		return
	var zd: ZoneData = null
	if "_zone_data" in _mode:
		zd = _mode._zone_data
	if zd == null:
		return
	# 取已揭幕 F-14 质心；没有则用 CV 死亡位置
	var center: Vector2 = _cv_death_position
	if _poltergeist:
		var sum := Vector2.ZERO
		var n := 0
		for m in _poltergeist.get_display_members():
			if not is_instance_valid(m) or (m as CombatUnit).is_destroyed:
				continue
			sum += (m as Node2D).global_position
			n += 1
		if n > 0:
			center = sum / float(n)
	zd.boss_zone["center"] = center


## 胜利：CV 死 AND（Phase 2 未触发 OR Poltergeist 全灭）
func _check_victory() -> void:
	var cv_dead: bool = _cv == null or not is_instance_valid(_cv) or _cv.is_destroyed
	if not cv_dead:
		return
	# Phase 2 未触发 → CV 死即胜
	if _phase == 1:
		active = false
		EventLogger.log_event("BOSS", display_name, "%s defeated (CV sunk before Phase 2)" % display_name)
		return
	# Phase 2 已触发 → 需等 Poltergeist 全灭
	if _poltergeist == null or not _poltergeist.active:
		active = false
		EventLogger.log_event("BOSS", display_name, "%s defeated (CV + Poltergeist eliminated)" % display_name)

# ══════════════════════════════════════════════
#  HUD
# ══════════════════════════════════════════════

## HUD BOSS 面板：永远第一张卡片是 CV（显示血条），之后接 Phase 2 的 4 架 F-14
## Phase 1 只显示 CV；Phase 2 显示 CV + 4 架 Poltergeist
func get_display_members() -> Array:
	var out: Array = []
	if _cv != null and is_instance_valid(_cv):
		out.append(_cv)
	if _poltergeist:
		out.append_array(_poltergeist.get_display_members())
	return out

## 呼号分配：Phase 2 时 _create_enemy 要知道当前 AceSquad 是 Poltergeist
func get_active_ace_squad() -> AceSquad:
	return _poltergeist

# ══════════════════════════════════════════════
#  舰船 spawn 工具
# ══════════════════════════════════════════════

func _make_ship(ship_class: GDScript, params_res: Resource,
		spawn_pos: Vector2, heading_deg: float, waypoints: PackedVector2Array) -> NavalUnit:
	var ship: NavalUnit = ship_class.new()
	ship.params = params_res
	ship.position = spawn_pos
	ship.initial_heading_deg = heading_deg
	ship.waypoints = waypoints
	ship.set_meta("category", "boss_csg")
	ship.set_meta("skip_far_cleanup", true)
	_mode.add_child(ship)
	if "bullet_manager" in _mode:
		ship.bullet_manager = _mode.bullet_manager
	if "missile_manager" in _mode:
		ship.missile_manager = _mode.missile_manager
	return ship

## 护航舰：刚体跟随 CV，偏移走 ESCORT_OFFSETS
func _spawn_escort(ship_class: GDScript, params_res: Resource, offset: Vector2) -> void:
	var leader_heading: float = _cv.heading
	var fwd := Vector2(sin(leader_heading), -cos(leader_heading))
	var stb := Vector2(cos(leader_heading), sin(leader_heading))
	var spawn_pos: Vector2 = _cv.global_position + fwd * offset.x + stb * offset.y
	var heading_deg: float = rad_to_deg(leader_heading)
	var ship := _make_ship(ship_class, params_res, spawn_pos, heading_deg, PackedVector2Array())
	ship.formation_leader = _cv
	ship.formation_offset = offset
	_escorts.append(ship)
