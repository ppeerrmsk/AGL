## Mother Goose BOSS Encounter
##
## 灵感：Arsenal Bird "Liberty"。巨型空中航母，三大机制：
##   1. UAV 蜂群（起始 12 / 上限 30 / 每 12s 补给 2）
##   2. 周期性干扰场（60s 周期：4s WARNING → 8s EXPANDING → 8s SUSTAIN）
##   3. 缓速大圈巡逻（200km/h, MID 高度，绕地图中心）
##
## v2 已实装：
##   - 8 螺旋桨槽位 + 2 VLS 作为 MountTarget（雷达独立可锁）
##   - 弱点暴露：所有挂点死光后主体可锁，HP 由 weak_point.hp 计
##   - 角度免伤：从机头 ±90° 前向扇区命中挂点 → 0 伤害；侧 60° 渐变 → 30%；尾扇区 → 100%
##
## v2 待补：
##   - VLS 主动齐射（boss 自己开火）
##
## 与 BossEncounter 接口对接：
##   spawn() 由 SurvivorSpawner._spawn_boss / BossEncounterEvent._start 调
##   update(delta) 每帧推 — 主要监测 boss 死亡触发胜利
##   engage() 玩家进入交战范围时事件层调（v1 不需要切状态，UAV/jam 已经在跑）
##   get_display_members() HUD 血条 — 返回 [boss_unit]

class_name MotherGooseBoss
extends BossEncounter

const PARAMS_PATH := "res://resources/enemy_mother_goose.tres"
## UAV 三型号资源路径定义在 [mother_goose_uav_swarm.gd] VARIANT_PARAMS

const PATROL_RADIUS_PX: float = 4000.0    ## 绕地图中心巡逻半径（像素）
const PATROL_WAYPOINTS: int = 8            ## 8 点环形路径
const BOSS_ALTITUDE: float = 5500.0        ## MID 档位中部

# ── 挂点配置 ──
## WeaponMount.world_position(ship_pos, h)：world = ship_pos + fwd*x + stb*y
##   forward = (sin h, -cos h), starboard = (cos h, sin h)
## 渲染层 [draw_mother_goose_icon](scripts/aircraft_renderer.gd) 用 s = size*9 = 144 像素，
## 应用 xform = scale(base_scale ≈ 1.05@MID) → 实际渲染 ≈ 151。
## 渲染本地坐标 (rx, ry) 关系：rx 对应 starboard (mount.y)，ry 对应 -forward (mount.x)
## 因此 mount.x = -ry_render*scale，mount.y = rx_render*scale
const MOUNT_PROP_HP: float = 200.0         ## 单个螺旋桨挂点 HP
const MOUNT_VLS_HP: float = 350.0          ## VLS 挂点 HP（更耐打）
const WEAK_POINT_HP: float = 800.0         ## 弱点暴露后的最终 HP（≈ 1 发玩家高伤导弹无法秒）
const WEAK_POINT_RADIUS: float = 220.0     ## 弱点点击命中半径

## 8 个螺旋桨 —— 与 [aircraft_renderer.gd:draw_mother_goose_icon] prop_xs 对齐
## 渲染 prop 在 ry=0.42 → mount.x = -0.42 * 151 ≈ -63
## 渲染 prop_xs ∈ [-0.95, -0.68, -0.41, -0.14, 0.14, 0.41, 0.68, 0.95] → mount.y = rx * 151
const PROP_OFFSETS_PX: Array[Vector2] = [
	Vector2(-63.0, -143.0),
	Vector2(-63.0, -103.0),
	Vector2(-63.0,  -62.0),
	Vector2(-63.0,  -21.0),
	Vector2(-63.0,   21.0),
	Vector2(-63.0,   62.0),
	Vector2(-63.0,  103.0),
	Vector2(-63.0,  143.0),
]
## 2 个 VLS —— 渲染在 (±0.18, 0.10) → mount.x = -0.10*151 ≈ -15, mount.y = ±0.18*151 ≈ ±27
const VLS_OFFSETS_PX: Array[Vector2] = [
	Vector2(-15.0, -27.0),
	Vector2(-15.0,  27.0),
]

# 运行时状态
var boss_unit: Aircraft = null
var controller: MotherGooseController = null
var boss_squad: Squad = null            ## boss + UAV 共享的小队，CommanderAura 通过 ai.squad 招募/buff
var commander_aura: CommanderAura = null

# 挂点系统
var mounts: Array[WeaponMount] = []          ## 8 propeller + 2 VLS = 10 个 WeaponMount
var weak_point: WeakPoint = null              ## 挂点全死后 reveal
var mount_targets: Array[MountTarget] = []   ## 雷达锁定代理（_scene_root 子节点）
var weak_point_target: MountTarget = null    ## 弱点暴露时 spawn

var _scene_root: Node = null
var _aircraft_scene: PackedScene = null
var _player: Aircraft = null
var _bullet_mgr: BulletManager = null
var _missile_mgr: MissileManager = null

func _init() -> void:
	display_name = "MOTHER GOOSE"
	callsign_prefix = "GOOSE"
	bgm_track = "boss"   ## 复用 F-47 BGM；v2 单独配


# ──────────────────────── 生成 ────────────────────────

## 与 AceSquad / CSG 同签名（squads 参数为 trailing optional，本 BOSS 不用 squad）
func spawn(scene_root: Node, aircraft_scene: PackedScene, _create_enemy_func: Callable,
		player: Aircraft, bullet_mgr: BulletManager, missile_mgr: MissileManager,
		_squads: Array[Squad], anchor: Vector2 = Vector2.INF) -> void:
	if active:
		return
	if scene_root == null or aircraft_scene == null:
		push_error("MotherGooseBoss.spawn: missing scene_root / aircraft_scene")
		return

	_scene_root = scene_root
	_aircraft_scene = aircraft_scene
	_player = player
	_bullet_mgr = bullet_mgr
	_missile_mgr = missile_mgr
	active = true

	# spawn_pos：anchor 优先，否则地图中心
	var spawn_pos: Vector2 = anchor if anchor != Vector2.INF else Vector2.ZERO

	# 加载主体 params
	var base_params: Resource = load(PARAMS_PATH)
	if base_params == null:
		push_error("MotherGooseBoss.spawn: failed to load %s" % PARAMS_PATH)
		active = false
		return
	var ac_params: AircraftParams = (base_params as AircraftParams).duplicate(true)
	if ac_params.combat:
		ac_params.combat = ac_params.combat.duplicate()
	# 主体 HP = 所有子系统 HP 总和 → HUD 血条按总和分母显示，
	# update() 每帧把 boss_unit.hp 同步到当前剩余子系统 HP，玩家拆挂点能看到血条下降
	var total_subsystem_hp: float = (
		float(PROP_OFFSETS_PX.size()) * MOUNT_PROP_HP +
		float(VLS_OFFSETS_PX.size()) * MOUNT_VLS_HP +
		WEAK_POINT_HP
	)
	ac_params.max_hp = total_subsystem_hp

	# 实例化主体 Aircraft
	boss_unit = _aircraft_scene.instantiate()
	boss_unit.params = ac_params
	boss_unit.team = 1
	boss_unit.position = spawn_pos
	boss_unit.initial_heading_deg = initial_heading_deg
	boss_unit.altitude = BOSS_ALTITUDE
	boss_unit.flat_altitude = true
	boss_unit.set_target_tier(CombatUnit.AltitudeTier.MID)
	boss_unit.infinite_fuel = true
	boss_unit.infinite_ammo = true
	boss_unit.is_mission_target = true
	boss_unit.set_meta("enemy_type", "mother_goose")
	boss_unit.set_meta("category", "boss")
	boss_unit.set_meta("skip_far_cleanup", true)
	boss_unit.set_meta("silhouette", "mother_goose")
	# 主体免锁：玩家必须先打挂点，挂点全死后弱点暴露才能锁主体
	boss_unit.set_meta(&"lock_immune_override", true)
	# 无人机 boss 同样 fear 免疫（"母机"是硬件平台，无飞行员）
	boss_unit.set_meta(&"fear_immune", true)
	boss_unit.callsign = "%s-01" % callsign_prefix
	# 注入子弹/导弹管理器（与 survivor_spawner._create_enemy 一致），否则 boss 自己开火
	# / UAV 激光扫导弹 / 子弹命中检测 全部失效
	boss_unit.bullet_manager = _bullet_mgr
	boss_unit.missile_manager = _missile_mgr
	_scene_root.add_child(boss_unit)

	# 构建 10 个挂点（8 螺旋桨 + 2 VLS）+ 1 弱点
	_build_mounts()
	# 弱点：占位创建（revealed=false），mount 全死后才 reveal
	weak_point = WeakPoint.new()
	weak_point.hp = WEAK_POINT_HP
	weak_point.radius = WEAK_POINT_RADIUS
	weak_point.local_offset = Vector2.ZERO   ## 机身中央
	weak_point.revealed = false

	# 共享小队：boss = leader（index 0），UAV 加入后通过 ai.squad 被 CommanderAura 扫到
	boss_squad = Squad.new()
	boss_squad.leader = boss_unit
	boss_squad.add_member(boss_unit)
	if _squads != null:
		_squads.append(boss_squad)

	# AI 控制器：禁用战斗（只巡逻），航点 = 绕地图中心环形
	var ai := AIController.new()
	ai.name = "AI_MotherGoose"
	ai.aircraft = boss_unit
	ai.patrol_altitude = BOSS_ALTITUDE
	ai.enable_combat = false
	ai.squad = boss_squad
	ai.squad_index = 0
	_assign_patrol_ring(ai, spawn_pos)
	boss_unit.add_child(ai)

	# 光环：复用 Sentinel 的 CommanderAura（招募 + 机动/速度/攻击欲望 buff）
	## CommanderAura 内部 MAX_WINGMEN=5 是"额外招募"上限；我们直接 spawn 30 架塞进 squad，
	## _try_recruit 看到 size>5 即跳过，不影响我们；_scan_and_buff 对 squad 全员都 buff
	## 节点名必须为 "CommanderAura"，CommanderOverlay 通过 get_node_or_null 找它
	commander_aura = CommanderAura.new()
	commander_aura.name = "CommanderAura"
	boss_unit.add_child(commander_aura)
	# 视觉光环圈 + 数据链虚线（看见哪些 UAV 被 buff）
	var overlay := CommanderOverlay.new()
	overlay.name = "CommanderOverlay"
	boss_unit.add_child(overlay)

	# 挂 controller（管理 jam shield + uav swarm + VLS 齐射 + 绘制场圈 + 挂点伤害路由）
	controller = MotherGooseController.new()
	controller.boss_unit = boss_unit
	controller.boss_encounter = self
	controller.player_ref = _player
	controller.missile_manager_ref = _missile_mgr
	## damage_router meta 让 Aircraft.take_damage_at 委托给 controller.route_damage
	boss_unit.set_meta(&"damage_router", controller)
	# UAV swarm（四型号 MQ-109/110/111/112 加权随机由 swarm 内部抽签）
	var swarm := MotherGooseUAVSwarm.new()
	swarm.setup(_scene_root, _aircraft_scene, boss_unit, boss_squad, _bullet_mgr, _missile_mgr)
	controller.uav_swarm = swarm
	# Jam shield 在 controller._ready 内自动 new()
	boss_unit.add_child(controller)

	# Shield 视觉圈：独立 Node2D 挂在 _scene_root 上（不在 boss 子节点）
	# 原因：boss 屏外时其子节点 _draw 可能不被绘制，但 AOE 是 gameplay 元素必须始终可见
	var shield_overlay := MotherGooseShieldOverlay.new()
	shield_overlay.name = "MotherGooseShieldOverlay"
	shield_overlay.boss_unit = boss_unit
	shield_overlay.jam_shield = controller.jam_shield
	_scene_root.call_deferred("add_child", shield_overlay)

	# 起始 UAV 12 架（延后一帧让 boss_unit._ready 跑完）
	if controller.uav_swarm:
		controller.uav_swarm.call_deferred("spawn_initial")

	# spawn 挂点锁定代理（延后一帧让 boss_unit._ready 跑完）
	call_deferred("_spawn_mount_targets")

	EventLogger.log_event("BOSS", display_name,
		"Mother Goose engaged at %s, hp=%.0f, jam_shield + uav_swarm online" %
		[spawn_pos, ac_params.max_hp])


## 构建 10 个 WeaponMount（含内联 WeaponMountParams，无需 .tres）
func _build_mounts() -> void:
	mounts.clear()
	for off in PROP_OFFSETS_PX:
		mounts.append(_make_mount(off, MOUNT_PROP_HP, "P"))
	for off in VLS_OFFSETS_PX:
		mounts.append(_make_mount(off, MOUNT_VLS_HP, "V"))

func _make_mount(local_offset: Vector2, max_hp: float, symbol: String) -> WeaponMount:
	var p := WeaponMountParams.new()
	p.local_offset = local_offset
	p.max_hp = max_hp
	p.display_symbol = symbol
	p.weapon_type = WeaponMountParams.WeaponType.CIWS  ## 占位（v2 不开火）
	var m := WeaponMount.new()
	m.initialize(p)
	return m

## 给每个存活挂点 spawn 一个 MountTarget（_scene_root 子节点，避免继承 boss rotation）
func _spawn_mount_targets() -> void:
	if _scene_root == null or boss_unit == null or not is_instance_valid(boss_unit):
		return
	for m in mounts:
		if m.destroyed:
			continue
		var mt := MountTarget.new()
		mt.parent_ship = boss_unit
		mt.mount_ref = m
		_scene_root.add_child(mt)
		mount_targets.append(mt)

## 弱点暴露：所有挂点死光时由 controller 调
func reveal_weak_point() -> void:
	if weak_point == null or weak_point.revealed:
		return
	weak_point.revealed = true
	# spawn 弱点的锁定代理；同时撤掉主体免锁，让玩家最后一击可以直接锁主体
	if _scene_root and boss_unit and is_instance_valid(boss_unit):
		var mt := MountTarget.new()
		mt.parent_ship = boss_unit
		mt.weak_point_ref = weak_point
		_scene_root.add_child(mt)
		weak_point_target = mt
		boss_unit.set_meta(&"lock_immune_override", false)
	EventLogger.log_event("BOSS", display_name, "Mother Goose weak point exposed")

## controller 调：所有挂点全死了？
func all_mounts_destroyed() -> bool:
	for m in mounts:
		if not m.destroyed:
			return false
	return true

## controller 调：VLS 挂点都属于 PROP_OFFSETS_PX 之后的索引（最后 2 个 mounts）
## 返回未损毁的 VLS WeaponMount 列表
func alive_vls_mounts() -> Array[WeaponMount]:
	var out: Array[WeaponMount] = []
	var prop_count: int = PROP_OFFSETS_PX.size()
	for i in range(prop_count, mounts.size()):
		var m: WeaponMount = mounts[i]
		if m and not m.destroyed:
			out.append(m)
	return out


## 巡逻环形：以地图中心为环心（限制不出界），8 点正多边形
func _assign_patrol_ring(ai: AIController, spawn_pos: Vector2) -> void:
	var center: Vector2 = Vector2.ZERO
	# 半径限制：不超过 (MAP_HALF - 1500) 以保证 UAV 也不贴边
	var max_r: float = MapBoundary.world_half_px() - 1500.0
	var r: float = minf(PATROL_RADIUS_PX, max_r)
	var wps: PackedVector2Array = PackedVector2Array()
	# 起始相位让首个 waypoint 接近 spawn_pos，避免 boss 拐大弯
	var start_angle: float = atan2(spawn_pos.x - center.x, -(spawn_pos.y - center.y))
	for i in range(PATROL_WAYPOINTS):
		var a: float = start_angle + TAU * float(i) / float(PATROL_WAYPOINTS)
		var wp := center + Vector2(sin(a), -cos(a)) * r
		wps.append(wp)
	ai.waypoints = wps
	ai.current_waypoint_index = 0


# ──────────────────────── 接战 ────────────────────────

## 玩家进入 BOSS 圈触发；本 BOSS 不需要切换状态（UAV / jam 已在跑）
## 但开启 enable_combat 让 boss 雷达开始照射玩家（用于 HUD 上 boss"看到"玩家的视觉）
func engage() -> void:
	if boss_unit == null or not is_instance_valid(boss_unit):
		return
	# v1：boss 自己不开火，但允许 AI 维持航向 + 雷达扫描（不变）
	# 留空：jam_shield 周期触发已经在 controller 里跑


# ──────────────────────── 帧循环 ────────────────────────

func update(_delta: float) -> void:
	if not active:
		return
	# 胜利判定：弱点暴露后被打死 OR 主体直接被击毁（兜底，理论上 lock_immune 阻止）
	if boss_unit == null or not is_instance_valid(boss_unit) or boss_unit.is_destroyed:
		active = false
		EventLogger.log_event("BOSS", display_name, "Mother Goose defeated")
		return

	# 每帧把主体 HP 同步到所有子系统剩余 HP 总和（HUD 血条由此驱动）
	var hp_sum: float = 0.0
	for m in mounts:
		if m and not m.destroyed:
			hp_sum += m.hp
	if weak_point != null:
		# 未暴露的弱点也计入"潜在 HP"，让玩家看到从满血逐渐下降而不是突然多出 800 血
		hp_sum += weak_point.hp
	boss_unit.hp = hp_sum

	if weak_point != null and weak_point.revealed and weak_point.hp <= 0.0:
		# 弱点死亡 → 触发主体销毁动画
		boss_unit.is_destroyed = true
		active = false
		EventLogger.log_event("BOSS", display_name, "Mother Goose defeated (weak point destroyed)")


# ──────────────────────── HUD ────────────────────────

func get_display_members() -> Array:
	if boss_unit and is_instance_valid(boss_unit):
		return [boss_unit]
	return []

## 飞机 BOSS 但不是 AceSquad —— 返回 null，呼号分配走默认路径
func get_active_ace_squad() -> AceSquad:
	return null
