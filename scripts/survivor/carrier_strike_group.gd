## Carrier Strike Group BOSS —— Ladon 战斗群（内部 id / 类名保留 CARRIER_STRIKE_GROUP）
##
## 设计流程：
##   Phase 1: CV 航母（旗舰）+ 通关次数驱动的护航编成（初见 0CG+2DDG+6FFG；首败后 2CG+2DDG+8FFG）
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
## 旗舰盘旋半径：舰队绕锚点恒定转圈，角速度 = CV 航速 / 半径 = 3.5/750 ≈ 0.0047 rad/s（0.27°/s）
## 不能再用"直线往返 + 端点 180° U-turn"：僚舰是刚体跟随，一次掉头 = 整支舰队原地旋转 60 s
## 半径下限受 NavalUnit.FORMATION_TANGENTIAL_CAP_PXS 约束（太小 → 转速被截断，船画不出这个圆）
const CV_PATROL_RING_RADIUS: float = 750.0    ## 舰队外缘 750 + 1556 ≈ 2306 px，约等于 BOSS_ZONE 半径
const ESCORT_OFFSETS: Array[Vector2] = [
	# (前后, 左右) 相对旗舰本地坐标；+X 船头，+Y 右舷
	# 舰队 bbox 约 1950×2200 px（≈3.9 km × 4.4 km）—— 11 舰双层护卫队形
	# 最外点到中心 sqrt(1100²+1100²) ≈ 1556 px，仍在 BOSS_ZONE radius 2200 px 内
	# CIWS / 防空网双层交叉覆盖，玩家从单侧突防更难钻空当
	Vector2(650, -500),     # [0] 前左 CG
	Vector2(650, 500),      # [1] 前右 CG
	Vector2(-380, 0),       # [2] 贴身后卫 DDG（CV 半长 210 + DDG 半长 90 + ~80 间隙）
	Vector2(-850, -550),    # [3] 后左 FFG
	Vector2(-850, 550),     # [4] 后右 FFG
	Vector2(500, 0),        # [5] 贴身前卫 DDG（与 [2] 对称，封堵 CV 正前死角）
	Vector2(0, -1100),      # [6] 左舷腰部 FFG（封堵左舷侧突）
	Vector2(0, 1100),       # [7] 右舷腰部 FFG（封堵右舷侧突）
	Vector2(1100, -900),    # [8] 左舷前哨 FFG（CG 外翼，前向预警）
	Vector2(1100, 900),     # [9] 右舷前哨 FFG（CG 外翼，前向预警）
	Vector2(-1200, -900),   # [10] 强化层后左外翼 FFG
	Vector2(-1200, 900),    # [11] 强化层后右外翼 FFG
]

# ── 身份默认值（可被 BossRegistry 覆盖）──
func _init() -> void:
	display_name = "LADON STRIKE GROUP"
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
## 【全场累计上限】整场 BOSS 战最多弹射 8 架（含开局 2 架）——弹完就不再补。
## 旧版无上限：拖时间 = 无限舰载机 = 无限经验/连击农场，BOSS 战变成"运营局"。
## 舰载机是压制手段，不是产出来源；连同 no_kill_reward 一起封死这条运营路子。
const FA18_TOTAL_CAP: int = 8
const FA18_TAKEOFF_GRACE: float = 4.0         ## 起飞保护期（与 Poltergeist 同步）
const FA18_INITIAL_LATERAL_OFFSET: float = 220.0 ## 初始两架左右分开像素距离
var _fa18_engaged: bool = false               ## engage() 是否已经触发（防止重复）
var _fa18_periodic_timer: float = 0.0         ## 距离下一次定期弹射的剩余秒数
var _fa18_alive: Array[Aircraft] = []         ## 跟踪存活的 F/A-18，用于胜利判定 / 清理
var _fa18_launched_total: int = 0             ## 本场累计弹射数（对 FA18_TOTAL_CAP 计数，死了也不退还）

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
	var escort_plan: Array = _build_escort_plan(cg_params, ddg_params, ffg_params)
	var placement_offsets: Array[Vector2] = []
	for plan in escort_plan:
		var planned_offset: Vector2 = plan["off"]
		placement_offsets.append(planned_offset)

	# 摆位地形校验：BOSS 锚点只保证圆心在水面，整支舰队还要摆得下（见 _pick_water_placement）
	var placement: Dictionary = _pick_water_placement(anchor, initial_heading_deg, placement_offsets)
	var place_anchor: Vector2 = placement["anchor"]
	var place_heading: float = placement["heading"]
	var place_ring: float = float(placement["ring"])
	var land_hits: int = int(placement["land"])
	EventLogger.log_event("BOSS", display_name,
		"placement anchor=(%d,%d) hdg=%.0f ring=%d land=%d" % [
			place_anchor.x, place_anchor.y, place_heading, roundi(place_ring), land_hits])
	if land_hits > 0:
		push_warning("CarrierStrikeGroup: 舰队仍有 %d 个落点在陆地（锚点 %s）" % [land_hits, str(place_anchor)])

	# 旗舰 CV 绕锚点恒定盘旋（顺时针，圆心在右舷）：全程不掉头，整支舰队只有 0.27°/s 的缓慢转位
	# 出生点放在圆周上（锚点左舷 R 处），初始 heading 恰好是该点的切线 → 无入圈瞬态
	# heading 约定：0°=北=-Y 世界方向
	var heading_rad: float = deg_to_rad(place_heading)
	var cv_spawn: Vector2 = NavalPlacement.leader_pos(place_anchor, place_ring, heading_rad)
	_cv = _make_ship(CarrierShipScript, cv_params, cv_spawn, place_heading, PackedVector2Array())
	# place_ring = 0（窄水域降级）→ patrol 模式关闭，舰队原地驻泊
	_cv.patrol_center = place_anchor if place_ring > 1.0 else Vector2.INF
	_cv.patrol_radius = place_ring
	_cv.is_mission_target = true

	# CV 甲板停 2 架舰载机（可选：不和 Phase 2 的 4 架 F-14 冲突，留空）
	# 如果想让 CV 自带 2 架标准僚机 + Phase 2 弹射 4 架 F-14，下一行取消注释
	# if _cv is CarrierShip: (_cv as CarrierShip).spawn_escort_aircraft(_mode)

	# 护航舰队：escort_plan 已在摆位前按通关层构建，水域校验与真实编成严格一致。
	for plan in escort_plan:
		_spawn_escort(plan["cls"], plan["params"], plan["off"])

	EventLogger.log_event("BOSS", display_name, "%s Phase 1 engaged (CV + %d escorts)" % [display_name, _escorts.size()])

## 纯数据查询：给 UI/bench 复核编成，不依赖舰船实例。
static func escort_counts_for_progression(defeat_count: int) -> Dictionary:
	return {
		"cg": 2 if defeat_count >= 1 else 0,
		"ddg": 2,
		"ffg": 8 if defeat_count >= 1 else 6,
	}

## 本局护航计划。初见拿掉旧默认 2 CG；首败后加回，并追加后翼 2 FFG。
func _build_escort_plan(cg_params: Resource, ddg_params: Resource, ffg_params: Resource) -> Array:
	var plan: Array = [
		{"cls": DestroyerShipScript, "params": ddg_params, "off": ESCORT_OFFSETS[2]},
		{"cls": FrigateShipScript,   "params": ffg_params, "off": ESCORT_OFFSETS[3]},
		{"cls": FrigateShipScript,   "params": ffg_params, "off": ESCORT_OFFSETS[4]},
		{"cls": DestroyerShipScript, "params": ddg_params, "off": ESCORT_OFFSETS[5]},
		{"cls": FrigateShipScript,   "params": ffg_params, "off": ESCORT_OFFSETS[6]},
		{"cls": FrigateShipScript,   "params": ffg_params, "off": ESCORT_OFFSETS[7]},
		{"cls": FrigateShipScript,   "params": ffg_params, "off": ESCORT_OFFSETS[8]},
		{"cls": FrigateShipScript,   "params": ffg_params, "off": ESCORT_OFFSETS[9]},
	]
	if prior_defeats >= 1:
		plan.push_front({"cls": CruiserShipScript, "params": cg_params, "off": ESCORT_OFFSETS[1]})
		plan.push_front({"cls": CruiserShipScript, "params": cg_params, "off": ESCORT_OFFSETS[0]})
		plan.append({"cls": FrigateShipScript, "params": ffg_params, "off": ESCORT_OFFSETS[10]})
		plan.append({"cls": FrigateShipScript, "params": ffg_params, "off": ESCORT_OFFSETS[11]})
	return plan

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
		# BOSS 圈跟随质心的逻辑已上提为通用规则，由 BossEncounterEvent 单一所有
		# （spec boss-hunter-doctrine §2.6）—— 猎手模型下每个 BOSS 都需要它，不止 CSG 二阶段

	# 胜利判定
	_check_victory()

# ══════════════════════════════════════════════
#  接战入口（boss_encounter_event PRE_STAGE → ENGAGED 时调用）
# ══════════════════════════════════════════════

## 玩家机换人时重定向（基类契约，见 BossEncounter.set_player_ref）。
## CSG 自持一份 _player（弹射的舰载机据此挂目标），二阶段还有一支 Poltergeist 小队
func set_player_ref(p: Aircraft) -> void:
	if p == null or not is_instance_valid(p):
		return
	_player = p
	if _poltergeist != null:
		_poltergeist.set_player_ref(p)

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
	# 累计上限用尽 → 机库空了，永不再刷（不看存活数：击落即消耗，不许"打一架补一架"）
	if _fa18_launched_total >= FA18_TOTAL_CAP:
		return
	_fa18_periodic_timer -= delta
	if _fa18_periodic_timer <= 0.0:
		_fa18_periodic_timer = FA18_PERIODIC_INTERVAL
		_launch_fa18(0.0)
		EventLogger.log_event("BOSS", display_name,
				"periodic F/A-18 catapult (%d/%d launched, %d alive)" % [
					_fa18_launched_total, FA18_TOTAL_CAP, _fa18_alive.size()])

## 单架 F/A-18 弹射：CV 位置 + CV 当前朝向 + lateral 偏移（米/像素同尺度）
## 起飞后立即开火（不像 Poltergeist 走 4 秒滑跑动画 — 设计上"补充梯队"节奏快）
## 给一段 takeoff grace，玩家短暂内无法锁定 + 飞机自爬到作战高度
func _launch_fa18(lateral_offset: float) -> void:
	if _cv == null or not is_instance_valid(_cv):
		return
	# 机库上限（唯一守卫处；engage() 的开局 2 架也走这里计数）
	if _fa18_launched_total >= FA18_TOTAL_CAP:
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
	## BOSS 自带单位不计价（同 Goose 蜂群 / MQ-X）：无 XP / 不入生涯档案 / 不给对头永久 +max_hp。
	## 奖励挂在 BOSS 本体上，舰载机是压制手段不是产出来源（消费点 survivor_spawner._detect_kills）
	hornet.set_meta("no_kill_reward", true)
	# 猎手化（spec boss-hunter-doctrine §3.5）：舰载机起飞即挂玩家为目标。
	# 旧版靠"AI 雷达扫描自然获取"—— F/A-18 雷达锥有限，玩家在 5km 外绕开就永远不被发现，
	# 整个舰队于是变成一个不会反击的固定靶。舰船追不动玩家，CSG 的猎手性全靠这些飞机
	_assign_player_target(hornet, "CSG F/A-18 launch")
	_fa18_alive.append(hornet)
	_fa18_launched_total += 1

## 给一架 CSG 舰载机挂玩家目标。走 acquire_target(TS_BOSS) —— 与既有猎手系统同一条通路，
## 优先级仲裁防抢写，且 TS_BOSS 天然绕过 ROE 感知门（= 地面指挥所全知引导）
func _assign_player_target(ac: Aircraft, why: String) -> void:
	if ac == null or not is_instance_valid(ac):
		return
	if _player == null or not is_instance_valid(_player) or _player.is_destroyed:
		return
	var ai: AIController = ac._get_ai_controller()
	if ai == null:
		return
	ai.enable_combat = true
	ai.boss_attacker = true
	if ai.acquire_target(_player, AIController.TargetSource.TS_BOSS, why):
		ai.enter_engage_state()

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
	# 转阶段无线电：航母沉没瞬间的最后命令（boss_sequences 的 phase2，走 scripted 豁免节流）
	_say_phase2_radio()
	EventLogger.log_event("BOSS", display_name,
			"Phase 2: CV sunk, F-14 catapult launch begins at %s heading=%.0f°" % [_cv_death_position, rad_to_deg(_cv_death_heading)])

## Phase 2 转阶段台词：航母沉没瞬间下达的最后命令。
## 说话人仍是 CSG-01（舰队指挥）——此刻 Poltergeist 尚未升空，还轮不到 PLTGST 呼号。
## trigger 落到 boss_engage（scripted），豁免全部节流且不被队列淘汰，保证必定播出。
func _say_phase2_radio() -> void:
	if _mode == null or not is_instance_valid(_mode):
		return
	var radio = _mode.get("_radio")
	if radio == null or not is_instance_valid(radio):
		return
	radio.say_boss_sequence("CARRIER_STRIKE_GROUP", "phase2", callsign_prefix)

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
#  摆位地形校验
# ══════════════════════════════════════════════
#
# zone_data._snap_to_water 只保证 BOSS 圈的圆心在水面，但整支舰队 bbox ≈1950×2200 px、
# 还要绕锚点盘旋（一圈约 20 分钟内扫过半径 ≈2300 px 的圆盘）—— 锚点靠岸时护卫舰会直接
# 刷在陆地上、或转着转着开上岸。下水前先扫候选锚点，取落地点最少的一组；全水面解立即采用。

## 锚点候选偏移（由近及远，八方向；原锚点由 pick_center 自己先试）
const PLACEMENT_NUDGE_RADII: Array = [1800.0, 3200.0]
## 盘旋半径降级序列：湾北桥下的全水圆只有 ~1750 px，装不下"编队 1421 + 盘旋 750"，
## 与其让护卫舰开上岸，不如缩巡航圈乃至就地抛锚（0 = 静止）
const PLACEMENT_RING_CANDIDATES: Array = [CV_PATROL_RING_RADIUS, 400.0, 0.0]

## 选出落地点最少的摆位 → { anchor, heading, ring, land }
## 落地计分委托 NavalPlacement（沿每艘船的轨道同心圆细采）——舰队整体绕锚点转，
## 只查出生那一刻的朝向正是"转过去以后搁浅"的来源
## 评分对朝向不变（舰队绕锚点盘旋），因此只挪锚点、不扫朝向；heading 原样透传给 F-14 弹射方向
func _pick_water_placement(anchor: Vector2, heading_deg: float,
		escort_offsets: Array[Vector2] = ESCORT_OFFSETS) -> Dictionary:
	var picked: Dictionary = NavalPlacement.pick_placement(
			anchor, NavalPlacement.ring_nudges(PLACEMENT_NUDGE_RADII),
			PLACEMENT_RING_CANDIDATES, escort_offsets, deg_to_rad(heading_deg))
	return {
		"anchor": picked["center"], "heading": heading_deg,
		"ring": picked["ring"], "land": picked["land"],
	}


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
