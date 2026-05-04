class_name NavalUnit
extends CombatUnit

## 海上单位基类 —— 所有船（FFG / DDG / CG / CV / SS）的公共骨架
##
## 本次实装（步骤 1）只包含：
##   - 生命期：从 NavalParams 实例化挂点 + 弱点，分配舰名
##   - 伤害路由：take_damage_at(amount, hit_pos) → 挂点 / 弱点
##   - 弱点暴露：挂点死亡到阈值后自动 revealed
##   - 锁定候选：get_lockable_targets() 返回挂点 + 弱点（船本身永远不在候选里）
##   - 基础移动：沿 waypoints 缓慢前进 + 缓慢转向
##   - 占位绘制：单色船体轮廓 + 小挂点方块 + 弱点脉动圈 + 状态栏标签
##
## 下一步（步骤 2 FFG）会接入：
##   - 挂点武器开火（SAM_SHORT / CIWS）
##   - CIWS 导弹拦截 + 对空扫射双模式
##   - 击毁动画（naval_destruction.gd）
##
## 后续（步骤 3+）：VLS 齐射、航母舰载机起飞、战区集成

@export var params: NavalParams
@export var initial_heading_deg: float = 0.0

# ── 武器管理器引用（由主场景初始化时注入）──
var bullet_manager: BulletManager = null
var missile_manager: MissileManager = null

# ── 身份 ──
var full_name: String = ""              ## 完整舰名，如 "DDG-187 Valkyrie"
var ship_class_label: String = ""       ## 舰种文本（"FFG" / "DDG" 等）

# ── 子系统实例 ──
var mounts: Array[WeaponMount] = []     ## 挂点运行时列表
var weak_point: WeakPoint = null        ## 弱点（仅当 params.weak_point_enabled 时存在）

# ── 锁定代理节点（挂点 + 弱点）──
## 每个挂点一个 MountTarget 子节点（survivor_mode 的 child），代表该挂点在雷达锁定系统里的"目标"
## 弱点暴露后再 spawn 一个；挂点摧毁 / 弱点消失时对应代理 queue_free
var _mount_targets: Array[MountTarget] = []
var _weak_point_target: MountTarget = null

# ── 船体总血量（所有路径的伤害都会累积到这里）──
## 从 params.hull_hp_max 初始化；归零 → 无论挂点/弱点状态直接摧毁船只
## 0 (params 未设) → 关闭此机制，只靠挂点/弱点死法致死
var hull_hp: float = 0.0
var hull_hp_max: float = 0.0

# ── 移动 ──
var target_position: Vector2 = Vector2.INF
var waypoints: PackedVector2Array = PackedVector2Array()
var current_waypoint_index: int = 0
var arrival_distance: float = 80.0      ## 到达判定距离（像素，船更宽容）

# ── 事件 directive（事件系统下发的覆盖指令）──
## 由 GameEvent.set_directive 写入；存在且 owner_event 仍 active 时：
##   - directive.combat_disabled = true → 跳过 NavalWeapons.update（不开火不锁玩家）
##   - directive.type = HOLD_POSITION → 还跳过 waypoints 推进（船保持当前点）
var _directive: AIDirective = null

func set_event_directive(directive: AIDirective) -> void:
	_directive = directive

func _directive_active() -> bool:
	return _directive != null and _directive.is_owner_alive()

# ── 编队跟随（zone_mission 的多艘船编队用）──
## 设置后每帧 target_position 由 leader 的位置 + 朝向动态计算（忽略 waypoints）
## leader 死亡后自动清空并 fallback 到 waypoints
var formation_leader: NavalUnit = null
## 相对 leader 的编队偏移（leader 本地坐标系：+X = 船头方向, +Y = 右舷）
var formation_offset: Vector2 = Vector2.ZERO

# ── 视觉 ──
var _font: Font
var _weak_pulse_time: float = 0.0       ## 弱点脉动计时

# ── 销毁 ──
var _destroy_timer: float = 0.0
# NavalDestruction 用的状态字段（声明在这里，让 RefCounted 静态方法能直接读写）
var _destroy_explosion_index: int = 0
var _destroy_explosion_cooldown: float = 0.0
var _destroy_debris: Array = []      ## [{pos, vel, size, life}]
var _destroy_ripples: Array = []     ## [{life}]
var _destroy_ripple_accum: float = 0.0

func _ready() -> void:
	if params == null:
		push_error("NavalUnit _ready: params is null, ship cannot be initialized")
		return

	# 图层：船画在飞机下面（飞机 z_index=0 默认），统一压到 -10
	# 配合 GroundUnit 同层，保证空中单位永远覆盖地面/海面单位
	z_index = -10

	altitude = 0.0
	flat_altitude = true
	heading = deg_to_rad(initial_heading_deg)
	rotation = heading
	team = params.default_team

	# 挂点实例化
	mounts.clear()
	for cfg in params.mount_configs:
		if cfg == null:
			continue
		var m := WeaponMount.new()
		m.initialize(cfg)
		mounts.append(m)

	# 弱点实例化（可选）
	weak_point = null
	if params.weak_point_enabled:
		weak_point = WeakPoint.new()
		weak_point.hp = params.weak_point_hp
		weak_point.radius = params.weak_point_radius
		weak_point.local_offset = Vector2.ZERO  # 船体中央

	# HP：船本身没有独立血量；挂点和弱点血量加总仅用于 HUD 粗略显示
	hp = _total_subsystem_hp()

	# 船体总血量初始化
	hull_hp_max = params.hull_hp_max
	hull_hp = hull_hp_max

	# 舰名分配
	ship_class_label = _ship_class_to_string(params.ship_class)
	full_name = NavalShipNames.roll(ship_class_label)
	callsign = full_name  # 同步到 CombatUnit 基类字段，供 AI / logger / UI 使用

	# 挂点锁定代理 —— 每个挂点 spawn 一个 MountTarget
	# 延迟到父节点存在之后（我们挂在父节点下，不是 NavalUnit 下，避免 rotation 干扰）
	call_deferred("_spawn_mount_targets")

## ============ 帧循环 ============
## LOD 策略（距玩家大于阈值 = "远距/屏幕外"）：
##   - 移动依然每帧跑（保持刚体编队位置）
##   - 武器子系统（VLS / CIWS / SAM）每 6 帧才 tick 一次（节流 83%）
##   - 绘制每 6 帧 queue_redraw 一次（避免脏矩形频繁重刷）
## 触发距离用玩家 Aircraft；找不到玩家就按远距处理
const LOD_FAR_DISTANCE_PX: float = 6000.0    ## 12 km：超过此距离启用 LOD
const LOD_FAR_TICK_DIVISOR: int = 6          ## 远距每 N 帧才跑一次完整更新
var _lod_frame: int = 0

# ── 脏驱动 redraw 跟踪状态 ──
## 不再每帧 queue_redraw —— 只在视觉真正变化时重画。
## CSG 6 船 × 60Hz redraw（每艘 ~30 draw 调用）= 10800 draw/sec，
## 砍到事件驱动后大多数帧只重画 0~2 艘船（hover / 被锁 / 销毁）
var _last_hover: bool = false
var _last_locked: bool = false
var _last_destroyed: bool = false
var _last_heading_int: int = -1
var _last_speed_int: int = -1
var _last_lock_progress_quant: int = -1
var _last_mounts_destroyed_count: int = -1
var _last_weak_revealed: bool = false
var _last_lock_warning_active: bool = false

func _physics_process(delta: float) -> void:
	if is_destroyed:
		_update_destroy(delta)
		queue_redraw()
		return

	_update_movement(delta)

	# LOD 判定：玩家远 → 节流武器 + 绘制
	_lod_frame += 1
	var is_far: bool = _is_far_from_player()
	if is_far and (_lod_frame % LOD_FAR_TICK_DIVISOR) != 0:
		return

	# 远距跑 subsystems 时补偿 delta，让 VLS / SAM 冷却按真实时间推进（不因节流慢 N 倍）
	var sub_delta: float = delta * LOD_FAR_TICK_DIVISOR if is_far else delta
	_update_subsystems(sub_delta)
	update_lock_line_state(sub_delta)
	# weak_pulse_time 只在弱点暴露时才推进（脉动动画用），
	# 否则任何旁观船都会以这个累加值为由触发 redraw
	if weak_point != null and weak_point.revealed:
		_weak_pulse_time += sub_delta

	if _should_redraw():
		queue_redraw()

## 判断本帧是否需要 _draw 重新提交：连续动画状态 + 状态变化事件 + 标签整数级变化
## 注意：连续动画分支返回 true 之前必须把"会触发状态机的"缓存字段同步好，
## 否则关闭动画那一帧（hover→!hover）的下降沿会被错过 → 残留旧画面
func _should_redraw() -> bool:
	# 连续动画类（每帧都需要重画）
	if is_hovered:
		_last_hover = true
		return true
	var lws = lock_warning_state if "lock_warning_state" in self else null
	var lw_active: bool = lws != null and lws.show_timer > 0.0
	if lw_active:
		_last_lock_warning_active = true
		return true
	if lw_active != _last_lock_warning_active:
		_last_lock_warning_active = lw_active
		return true
	if weak_point != null and weak_point.revealed:
		_last_weak_revealed = true
		return true  # 1Hz 脉动需要每帧重画
	if incoming_lock_progress > 0.001 or is_locked:
		_last_locked = is_locked
		return true

	# 状态变化事件（一次性触发）
	if is_hovered != _last_hover:
		_last_hover = is_hovered
		return true
	if is_locked != _last_locked:
		_last_locked = is_locked
		return true
	if is_destroyed != _last_destroyed:
		_last_destroyed = is_destroyed
		return true
	var weak_revealed: bool = weak_point != null and weak_point.revealed
	if weak_revealed != _last_weak_revealed:
		_last_weak_revealed = weak_revealed
		return true
	# 挂点击毁事件
	var destroyed_count := 0
	for m in mounts:
		if m.destroyed:
			destroyed_count += 1
	if destroyed_count != _last_mounts_destroyed_count:
		_last_mounts_destroyed_count = destroyed_count
		return true

	# 标签整数级变化（HDG / KTS 显示，避免每帧重画）
	var hdg_deg := int(rad_to_deg(heading)) % 360
	if hdg_deg < 0:
		hdg_deg += 360
	var kts := int(speed / 0.5144)
	if hdg_deg != _last_heading_int or kts != _last_speed_int:
		_last_heading_int = hdg_deg
		_last_speed_int = kts
		return true

	# lock_progress 量化 0~10 级，跨级才重画
	var lp_q := int(clampf(incoming_lock_progress, 0.0, 1.0) * 10.0)
	if lp_q != _last_lock_progress_quant:
		_last_lock_progress_quant = lp_q
		return true

	return false

func _is_far_from_player() -> bool:
	var pref: Aircraft = AircraftRenderer.player_ref
	if pref == null or not is_instance_valid(pref) or pref.is_destroyed:
		return true
	var d2: float = global_position.distance_squared_to(pref.global_position)
	return d2 > LOD_FAR_DISTANCE_PX * LOD_FAR_DISTANCE_PX

## ============ 移动 ============

func _update_movement(delta: float) -> void:
	if params == null:
		return

	# ──── 编队模式（刚体跟随 leader）────
	# 僚舰直接复制 leader 的 heading/speed，位置用弹簧力修正到理想偏移位置
	# 这样整支舰队作为"一个刚体"移动，不会出现僚舰各自物理打转、撞船、拉开队形
	if formation_leader != null:
		if not is_instance_valid(formation_leader) or formation_leader.is_destroyed:
			formation_leader = null   # leader 死 → 解除编队
		else:
			_update_formation_follow(delta)
			return

	# ──── waypoints 模式（独立巡航：旗舰 / 无主船）────
	if not waypoints.is_empty():
		var wp := waypoints[current_waypoint_index]
		if global_position.distance_to(wp) < arrival_distance:
			current_waypoint_index = (current_waypoint_index + 1) % waypoints.size()
		target_position = waypoints[current_waypoint_index]

	if target_position == Vector2.INF:
		speed = 0.0
		return

	var to_target := target_position - global_position
	var dist := to_target.length()
	if dist < 5.0:
		speed = 0.0
		return

	var target_heading := atan2(to_target.x, -to_target.y)
	var diff := angle_difference(heading, target_heading)
	var turn_rate := params.turn_rate
	heading += clampf(diff, -turn_rate * delta, turn_rate * delta)

	speed = params.max_sea_speed
	var vel := Vector2(sin(heading), -cos(heading)) * speed * PIXELS_PER_METER
	global_position += vel * delta
	rotation = heading

## 编队刚体跟随 —— 位置/朝向/速度全部刚性绑定 leader
## 僚舰不再独立计算速度方向：直接放在 leader 本地坐标系里的固定偏移位
## 这样整支舰队作为一个整体移动，船头始终朝航行方向，转弯时一起转
func _update_formation_follow(_delta: float) -> void:
	var leader: NavalUnit = formation_leader
	var lead_fwd := Vector2(sin(leader.heading), -cos(leader.heading))
	var lead_stb := Vector2(cos(leader.heading), sin(leader.heading))

	# 位置：跟 leader heading 同步旋转的刚体偏移
	global_position = leader.global_position \
			+ lead_fwd * formation_offset.x \
			+ lead_stb * formation_offset.y
	# 朝向：完全复制 leader（整队一起拐弯，船头永远朝航向）
	heading = leader.heading
	rotation = heading
	# 速度：跟 leader（HUD KTS 一致）
	speed = leader.speed
	target_position = global_position

## ============ 子系统 ============
## 每帧先推进所有挂点冷却，再调用 NavalWeapons.update 做开火判定
## 事件 directive 的 combat_disabled 跳过开火（CSG 预驻阶段用）
func _update_subsystems(delta: float) -> void:
	for m in mounts:
		if m.destroyed:
			continue
		if m.fire_cooldown > 0.0:
			m.fire_cooldown = maxf(m.fire_cooldown - delta, 0.0)
		if m.engage_cooldown > 0.0:
			m.engage_cooldown = maxf(m.engage_cooldown - delta, 0.0)
		if m.acquire_cooldown > 0.0:
			m.acquire_cooldown = maxf(m.acquire_cooldown - delta, 0.0)

	if _directive_active() and _directive.combat_disabled:
		return
	NavalWeapons.update(self, delta)

## ============ 高度 ============

func get_altitude_tier() -> int:
	return AltitudeTier.GROUND

## ============ 雷达（360° 圆形，无锥角）============

## 船的雷达覆盖是圆形而非扇形 —— 四周 CIWS + 桅杆雷达看得到所有方位
## 半径由 params.radar_range 决定
func is_in_radar_cone(target_global_pos: Vector2) -> bool:
	if params == null or params.radar_range <= 0.0:
		return false
	var dist: float = global_position.distance_to(target_global_pos)
	return dist <= params.radar_range and dist > 1.0

## 船体本身锁定免疫 —— 玩家只能锁挂点（MountTarget 代理）或暴露后的弱点
## 这样锁定框出现在挂点位置而不是船中心
func is_lock_immune() -> bool:
	return true

## ============ 锁定代理节点管理 ============

## 为每个存活挂点 spawn 一个 MountTarget；弱点暂不 spawn（等 reveal 时再 spawn）
## 需在 NavalUnit 被 add_child 到场景后调用（call_deferred）
func _spawn_mount_targets() -> void:
	var parent_scene := get_parent()
	if parent_scene == null:
		return
	for m in mounts:
		if m.destroyed:
			continue
		var mt := MountTarget.new()
		mt.parent_ship = self
		mt.mount_ref = m
		parent_scene.add_child(mt)
		_mount_targets.append(mt)

## 弱点暴露后 spawn 对应的 MountTarget（独立锁定目标，玩家可点击射击）
func _spawn_weak_point_target() -> void:
	if _weak_point_target != null and is_instance_valid(_weak_point_target):
		return
	if weak_point == null or not weak_point.revealed:
		return
	var parent_scene := get_parent()
	if parent_scene == null:
		return
	var mt := MountTarget.new()
	mt.parent_ship = self
	mt.weak_point_ref = weak_point
	parent_scene.add_child(mt)
	_weak_point_target = mt

## 船销毁时把所有代理一起清掉（避免代理飞到虚无位置）
## 先标 is_destroyed=true 再 queue_free：
##   其他系统（bullet_manager / missile_manager / radar 循环）依赖 `is_destroyed` 跳过，
##   直接 queue_free 会有一帧窗口期 is_instance_valid=true 但节点要释放，可能被误访问
func _despawn_all_lock_targets() -> void:
	for mt in _mount_targets:
		if mt and is_instance_valid(mt):
			mt.is_destroyed = true
			mt.queue_free()
	_mount_targets.clear()
	if _weak_point_target and is_instance_valid(_weak_point_target):
		_weak_point_target.is_destroyed = true
		_weak_point_target.queue_free()
		_weak_point_target = null

## ============ 伤害路由 ============

## 位置感知伤害入口 —— 导弹 / 子弹命中时应调用这个，传入命中世界坐标
## 伤害同时扣两个池：
##   A. 部件路由（最近挂点 / 弱点）—— 视觉上的逐块剥离 + 弱点/全清致死
##   B. 船体总血量（hull_hp）—— 无论打中哪个部位都累加到这；归零直接沉船
## 两条路径谁先满足谁触发摧毁
##
## hull_dmg_mult: 对"总血量"的折扣系数。防止机炮用总血秒杀船：
##   - 导弹 / AOE：1.0（全额）/ 火箭弹：0.5 / 机炮子弹：0.15
## can_hit_weak_point: 能否一发斩杀弱点。机炮子弹传 false —— 弱点是给导弹的斩杀点，
##   否则玩家一梭子扫过弱点就 60HP 秒死，违背设计
func take_damage_at(amount: float, hit_pos: Vector2, hull_dmg_mult: float = 1.0, can_hit_weak_point: bool = true) -> void:
	if is_destroyed:
		return

	# 路由到部件（为了视觉上打掉哪个位置、触发弱点暴露）
	var routed_to_part := false

	# 1. 弱点（已暴露，且发射源是可破甲武器）
	if can_hit_weak_point and weak_point and weak_point.revealed:
		var wp_world := _local_to_world(weak_point.local_offset)
		if weak_point.contains_point(wp_world, hit_pos):
			routed_to_part = true
			if weak_point.apply_damage(amount):
				_start_destruction()
				return

	# 2. 最近存活挂点（400 px 内）
	if not routed_to_part:
		var target_mount: WeaponMount = null
		var best_d := 400.0
		for m in mounts:
			if m.destroyed:
				continue
			var mp := m.world_position(global_position, heading)
			var d := hit_pos.distance_to(mp)
			if d < best_d:
				best_d = d
				target_mount = m
		if target_mount:
			routed_to_part = true
			if target_mount.apply_damage(amount):
				_on_mount_destroyed(target_mount)

	# 3. 总血量：只要命中到船体范围（即使部件路由失败，也累加到总血）
	#    机炮伤害用 hull_dmg_mult=0.15 大幅削减，避免一梭子扫死大船
	if hull_hp_max > 0.0:
		hull_hp = maxf(hull_hp - amount * hull_dmg_mult, 0.0)
		if hull_hp <= 0.0 and not is_destroyed:
			_start_destruction()

## CombatUnit 基类伤害入口（无位置信息）—— 兜底路由到船中心
## 例如 AOE 爆炸波可能调这个
func take_damage(amount: float, attacker: Node = null, kind: String = "") -> void:
	if attacker != null:
		set_meta("_pending_attacker", attacker)
	if kind != "":
		set_meta("_last_damage_kind", kind)
	take_damage_at(amount, global_position)

## 挂点被摧毁的回调
func _on_mount_destroyed(_mount: WeaponMount) -> void:
	_check_weak_point_reveal()

## 检查挂点死亡数是否达到弱点暴露阈值 / 无弱点船只全死判定
func _check_weak_point_reveal() -> void:
	if params == null:
		return

	var alive_count := 0
	var dead_count := 0
	for m in mounts:
		if m.destroyed:
			dead_count += 1
		else:
			alive_count += 1

	# FFG / 无弱点特例：所有挂点打掉即摧毁船只
	if not params.weak_point_enabled:
		if alive_count == 0 and dead_count > 0:
			_start_destruction()
		return

	# 正常弱点机制：挂点死亡数达到阈值 → 弱点暴露（玩家可用 1 发导弹斩杀）
	if weak_point and not weak_point.revealed and dead_count >= params.weak_point_threshold:
		weak_point.revealed = true
		_spawn_weak_point_target()

## 船本身被击毁（由弱点死亡或 FFG 挂点清零 / hull_hp 归零触发）
## 委托给 NavalDestruction 四阶段动画（连环爆炸 / 白方块碎片 / 沉没淡出）
func _start_destruction() -> void:
	if is_destroyed:
		return  # 防重入
	is_destroyed = true
	# 立即清理所有锁定代理（船还在绘制沉没动画，但代理没意义了）
	_despawn_all_lock_targets()
	NavalDestruction.start(self)

func _update_destroy(delta: float) -> void:
	if NavalDestruction.update(self, delta):
		# 动画完成
		if full_name != "":
			NavalShipNames.release(full_name)
		queue_free()

func _on_destroyed() -> void:
	_start_destruction()

## ============ 锁定候选接口 ============

## 返回所有可被玩家锁定 / 点击的目标（展平挂点 + 弱点）
## main.gd / survivor_mode.gd 的 _update_radar_locks 循环应该调这个而不是把船当单体
## 返回结构：{ "kind": "mount"/"weak_point", "ref": ..., "world_pos": Vector2 }
func get_lockable_targets() -> Array:
	var out: Array = []
	if is_destroyed:
		return out

	for m in mounts:
		if m.destroyed:
			continue
		out.append({
			"kind": "mount",
			"ref": m,
			"world_pos": m.world_position(global_position, heading),
		})

	if weak_point and weak_point.revealed:
		out.append({
			"kind": "weak_point",
			"ref": weak_point,
			"world_pos": _local_to_world(weak_point.local_offset),
		})

	return out

## ============ 几何辅助 ============

## 本地船体坐标 → 世界坐标（考虑船体 heading 旋转）
## 船本地 +X = 船头方向；+Y = 右舷
func _local_to_world(local_offset: Vector2) -> Vector2:
	var forward := Vector2(sin(heading), -cos(heading))
	var starboard := Vector2(cos(heading), sin(heading))
	return global_position + forward * local_offset.x + starboard * local_offset.y

## 所有存活挂点 + 弱点血量求和（仅供 HUD 粗略显示，不是精确击杀判定）
func _total_subsystem_hp() -> float:
	var total := 0.0
	for m in mounts:
		if not m.destroyed:
			total += m.hp
	if weak_point and weak_point.revealed:
		total += weak_point.hp
	return total

static func _ship_class_to_string(sc: int) -> String:
	match sc:
		NavalParams.ShipClass.FFG: return "FFG"
		NavalParams.ShipClass.DDG: return "DDG"
		NavalParams.ShipClass.CG:  return "CG"
		NavalParams.ShipClass.CV:  return "CV"
		NavalParams.ShipClass.SS:  return "SS"
	return "SHIP"

## ============ 占位绘制（步骤 2 完整重写）============
## 说明：目前用最简单的矩形 + 挂点方块让船可见。步骤 2 会接入 naval_renderer.gd
## 画 Tacview 风格的单色剪影（见计划 §3.11）

func _draw() -> void:
	if params == null:
		return

	if is_destroyed:
		# 击毁状态：继续画船体（靠 modulate 整体淡出）+ 叠加碎片 / 水波
		_draw_hull_placeholder()
		_draw_mounts_placeholder()
		NavalDestruction.draw(self)
		return

	if is_hovered:
		_draw_radar_circle()
		_draw_sam_envelope()
		_draw_ciws_envelopes()
		_draw_naval_aa_envelopes()
	_draw_hull_placeholder()
	_draw_mounts_placeholder()
	_draw_weak_point_placeholder()
	_draw_target_bracket()
	_draw_lock_indicator()
	LockWarning.draw(self, AircraftRenderer.player_ref)
	_draw_status_label()


## 任意挂点是否装载导弹（SAM_SHORT / VLS_SALVO，未损毁）
func has_missile_capability() -> bool:
	for m in mounts:
		if m == null or m.destroyed or m.params == null:
			continue
		var wt: int = m.params.weapon_type
		if wt == WeaponMountParams.WeaponType.SAM_SHORT or wt == WeaponMountParams.WeaponType.VLS_SALVO:
			return true
	return false

## 覆写 CombatUnit：海军单位能否对玩家发射导弹
## 条件：玩家在某个导弹挂点的雷达/有效射程内 + 该挂点 fire_cooldown ≤ 0
func _lock_line_can_engage_player() -> bool:
	var pref: Aircraft = AircraftRenderer.player_ref
	if pref == null or not is_instance_valid(pref) or pref.is_destroyed:
		return false
	for m in mounts:
		if m == null or m.destroyed or m.params == null:
			continue
		var wt: int = m.params.weapon_type
		if wt != WeaponMountParams.WeaponType.SAM_SHORT and wt != WeaponMountParams.WeaponType.VLS_SALVO:
			continue
		if m.fire_cooldown > 0.05:
			continue
		var msl := m.params.weapon_params as MissileParams
		if msl == null:
			continue
		var max_range_px: float = msl.max_range_rear * msl.front_rear_ratio * PIXELS_PER_METER
		if global_position.distance_to(pref.global_position) <= max_range_px:
			return true
	return false

## 圆形雷达覆盖（hover 时显示）—— 与 SAM 同构但更薄，避免遮挡
## 边缘线用 draw_multiline 一次提交，省掉 48 次独立 draw_line 调用
func _draw_radar_circle() -> void:
	if params == null or params.radar_range <= 0.0:
		return
	var radar_r: float = params.radar_range
	var color := GameConstants.team_radar_color(team, 0.08)

	var segments := 48
	var pts := PackedVector2Array()
	pts.resize(segments)
	for i in range(segments):
		var angle: float = float(i) / segments * TAU
		# 抵消本节点旋转（船 rotation = heading）
		pts[i] = Vector2(cos(angle), sin(angle)).rotated(-rotation) * radar_r
	draw_colored_polygon(pts, color)

	var edge_color := Color(color.r, color.g, color.b, 0.25)
	var edge_pairs := PackedVector2Array()
	edge_pairs.resize(segments * 2)
	for i in range(segments):
		edge_pairs[i * 2] = pts[i]
		edge_pairs[i * 2 + 1] = pts[(i + 1) % segments]
	draw_multiline(edge_pairs, edge_color, 1.0)

## SAM 武器包线（hover 时显示）—— 橙色虚线圆，居船中心
## 显示所有 SAM_SHORT / VLS_SALVO 挂点中射程最远的一个的最大射程
func _draw_sam_envelope() -> void:
	var max_range := _compute_max_sam_range()
	if max_range <= 0.0:
		return
	var color := Color(1.0, 0.55, 0.2, 0.55)  # 橙色
	_draw_dashed_ring(Vector2.ZERO, max_range, color, 1.5, 64, 0.35)

## CIWS 包线（hover 时显示）—— 每个存活 CIWS 挂点一个黄色虚线圆，
## 圆心在挂点本地位置（而非船中心），直观表达"这个挂点能覆盖到的范围"
func _draw_ciws_envelopes() -> void:
	var ciws_range := NavalWeapons.CIWS_INTERCEPT_RANGE_PX
	var color := Color(1.0, 0.9, 0.2, 0.5)  # 黄色
	for m in mounts:
		if m.destroyed or m.params == null:
			continue
		if m.params.weapon_type != WeaponMountParams.WeaponType.CIWS:
			continue
		# 转换到绘制本地坐标系（与 _draw_mounts_placeholder 一致：+X 船头 → 本地 -Y；+Y 右舷 → 本地 +X）
		var lo := m.params.local_offset
		var draw_pos := Vector2(lo.y, -lo.x)
		_draw_dashed_ring(draw_pos, ciws_range, color, 1.3, 48, 0.35)

## NAVAL_AA 包线（hover 时显示）—— 每个 AA 挂点一个青色虚线圆
func _draw_naval_aa_envelopes() -> void:
	var color := Color(0.4, 0.9, 1.0, 0.5)  # 青色
	for m in mounts:
		if m.destroyed or m.params == null or m.params.weapon_params == null:
			continue
		if m.params.weapon_type != WeaponMountParams.WeaponType.NAVAL_AA:
			continue
		var gun := m.params.weapon_params as GunParams
		if gun == null:
			continue
		var aa_range: float = gun.max_range * PIXELS_PER_METER
		var lo := m.params.local_offset
		var draw_pos := Vector2(lo.y, -lo.x)
		_draw_dashed_ring(draw_pos, aa_range, color, 1.3, 48, 0.35)

## 计算船上所有 SAM/VLS 挂点中最大射程（像素）
func _compute_max_sam_range() -> float:
	var max_r := 0.0
	for m in mounts:
		if m.destroyed or m.params == null or m.params.weapon_params == null:
			continue
		var wt := m.params.weapon_type
		if wt != WeaponMountParams.WeaponType.SAM_SHORT and wt != WeaponMountParams.WeaponType.VLS_SALVO:
			continue
		var mp := m.params.weapon_params as MissileParams
		if mp == null:
			continue
		var range_px: float = mp.max_range_rear * mp.front_rear_ratio * PIXELS_PER_METER
		if range_px > max_r:
			max_r = range_px
	return max_r

## 画虚线圆（center 是本地坐标，gap_ratio=0..1 表示每段之间留多少空白）
## 用 draw_multiline 一次提交所有段，48 段一调用替代 48 次 draw_line
func _draw_dashed_ring(center: Vector2, radius: float, color: Color, width: float, segments: int, gap_ratio: float) -> void:
	var seg_angle: float = TAU / segments
	var pairs := PackedVector2Array()
	pairs.resize(segments * 2)
	for i in range(segments):
		var a0: float = seg_angle * i
		var a1: float = seg_angle * (i + 1) - seg_angle * gap_ratio
		# 抵消船体 rotation，保证虚线段在屏幕上稳定（不随船头转）
		pairs[i * 2] = center + Vector2(cos(a0), sin(a0)).rotated(-rotation) * radius
		pairs[i * 2 + 1] = center + Vector2(cos(a1), sin(a1)).rotated(-rotation) * radius
	draw_multiline(pairs, color, width)

## 船体轮廓（占位：矩形 + 船头三角）
## 绘制坐标系原点在船中心，+Y 方向 = 船头方向（因为 node.rotation = heading，heading 0=北=-Y世界，但本地坐标系需要把船头朝 -Y 画，这样经 rotation 旋转后与 heading 对齐）
##
## 坐标系说明：
##   ship_heading 约定：0 = 北 = 世界 -Y
##   node.rotation = heading 应用后，本地 -Y 方向会指向 heading 方向
##   所以船头在本地 -Y，船尾在本地 +Y，左舷在本地 -X，右舷在本地 +X
##   本地 hull_length 在 Y 方向上展开，hull_width 在 X 方向上展开
func _draw_hull_placeholder() -> void:
	var L := params.hull_length
	var W := params.hull_width
	var color: Color = GameConstants.team_color(team)
	# 简单路径：hull_length 对应 Y（船头 -Y 方向），hull_width 对应 X
	var half_w := W * 0.5
	var half_l := L * 0.5
	# 船体主矩形（稍微收窄成船型）
	var body := PackedVector2Array([
		Vector2(-half_w, half_l),              # 船尾左
		Vector2(-half_w, -half_l * 0.6),       # 左舷前
		Vector2(0, -half_l),                   # 船头
		Vector2(half_w, -half_l * 0.6),        # 右舷前
		Vector2(half_w, half_l),               # 船尾右
	])
	draw_colored_polygon(body, color)
	# 轮廓线
	var outline_color := color.darkened(0.3)
	for i in body.size():
		var a := body[i]
		var b := body[(i + 1) % body.size()]
		draw_line(a, b, outline_color, 1.5)

func _draw_mounts_placeholder() -> void:
	# 本地坐标系：+Y 船头方向 = 本地 -Y（见 _draw_hull_placeholder 注释）
	# WeaponMountParams.local_offset：+X 船头, +Y 右舷（世界定义）
	# 转到绘制本地坐标系：local_offset.x → 本地 -Y（翻转），local_offset.y → 本地 +X
	for m in mounts:
		if m.params == null:
			continue
		var lo := m.params.local_offset
		var draw_pos := Vector2(lo.y, -lo.x)  # 翻转轴向以匹配绘制坐标系
		if m.destroyed:
			_draw_dead_mount(draw_pos)
		else:
			_draw_alive_mount(draw_pos, m.params.weapon_type)

func _draw_alive_mount(pos: Vector2, wtype: int) -> void:
	var size := 6.0
	var c := Color(0.95, 0.9, 0.7)
	match wtype:
		WeaponMountParams.WeaponType.CIWS:
			draw_circle(pos, size * 0.5, c)
		WeaponMountParams.WeaponType.VLS_SALVO:
			draw_rect(Rect2(pos - Vector2(size * 0.5, size * 0.5), Vector2(size, size)), c)
		WeaponMountParams.WeaponType.SAM_SHORT:
			# 小三角
			var tri := PackedVector2Array([
				pos + Vector2(0, -size * 0.6),
				pos + Vector2(size * 0.5, size * 0.4),
				pos + Vector2(-size * 0.5, size * 0.4),
			])
			draw_colored_polygon(tri, c)
		WeaponMountParams.WeaponType.NAVAL_AA:
			# 十字（区分于 CIWS 圆点），代表旋转机炮
			draw_line(pos + Vector2(-size * 0.5, 0), pos + Vector2(size * 0.5, 0), c, 1.5)
			draw_line(pos + Vector2(0, -size * 0.5), pos + Vector2(0, size * 0.5), c, 1.5)

func _draw_dead_mount(pos: Vector2) -> void:
	var size := 5.0
	var c := Color(0.35, 0.35, 0.35, 0.8)
	draw_line(pos + Vector2(-size, -size), pos + Vector2(size, size), c, 1.5)
	draw_line(pos + Vector2(-size, size), pos + Vector2(size, -size), c, 1.5)

func _draw_weak_point_placeholder() -> void:
	if weak_point == null or not weak_point.revealed:
		return
	# 弱点在船中央（0,0 本地）
	var pulse := 0.5 + 0.5 * sin(_weak_pulse_time * TAU)  # 1Hz 脉动
	var base_r := 10.0
	for i in range(3):
		var r := base_r + i * 5.0
		var alpha := (1.0 - i / 3.0) * (0.4 + 0.4 * pulse)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(1.0, 0.2, 0.2, alpha), 1.5)

## TGT 任务目标框 —— 旗舰专属，屏幕对齐（抵消船 rotation），黄色 L 角 + "TGT" 文字
func _draw_target_bracket() -> void:
	if not is_mission_target or params == null or is_destroyed:
		return
	var color := Color(1.0, 0.85, 0.2, 0.95)
	# 包围盒用船长一半 + padding；短边也取船长，保证任何朝向都能罩住船
	var half_size: float = params.hull_length * 0.55
	var corner: float = half_size * 0.15
	var w: float = 2.5

	# 屏幕对齐：抵消船 rotation，让 L 角永远与屏幕水平 / 垂直对齐
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	var s: float = half_size
	var c: float = corner
	# 左上
	draw_line(Vector2(-s, -s), Vector2(-s + c, -s), color, w)
	draw_line(Vector2(-s, -s), Vector2(-s, -s + c), color, w)
	# 右上
	draw_line(Vector2(s, -s), Vector2(s - c, -s), color, w)
	draw_line(Vector2(s, -s), Vector2(s, -s + c), color, w)
	# 左下
	draw_line(Vector2(-s, s), Vector2(-s + c, s), color, w)
	draw_line(Vector2(-s, s), Vector2(-s, s - c), color, w)
	# 右下
	draw_line(Vector2(s, s), Vector2(s - c, s), color, w)
	draw_line(Vector2(s, s), Vector2(s, s - c), color, w)
	# TGT 文字（在框上方）
	if _font == null:
		_font = ThemeDB.fallback_font
	draw_string(_font, Vector2(-s * 0.2, -s - 6),
			"TGT", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_lock_indicator() -> void:
	var p: float = clampf(incoming_lock_progress, 0.0, 1.0)
	if p <= 0.0 and not is_locked:
		return
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	AircraftRenderer.draw_lock_box(self, p, is_locked)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 状态栏标签：舰种 / 代号 / 朝向 / 速度（仿 GroundUnit._draw_data_label 风格）
func _draw_status_label() -> void:
	if not _font:
		_font = ThemeDB.fallback_font

	var lines: PackedStringArray = PackedStringArray()
	lines.append(ship_class_label)
	lines.append(full_name)
	var heading_deg := rad_to_deg(heading)
	while heading_deg < 0.0:
		heading_deg += 360.0
	while heading_deg >= 360.0:
		heading_deg -= 360.0
	lines.append("HDG %03d" % roundi(heading_deg))
	# 速度：内部是 m/s，显示为 节（1 节 ≈ 0.5144 m/s）
	var knots := speed / 0.5144
	lines.append("%d KTS" % roundi(knots))

	var font_size := 10
	var line_height := 12.0
	var label_offset := Vector2(params.hull_width * 0.6 + 10.0, 0.0)

	var inv_rot := -rotation
	var zoom_scale := get_viewport_transform().get_scale()
	var inv_zoom := 1.0 / maxf(zoom_scale.x, 0.01)

	var max_w := 0.0
	for line in lines:
		var w := _font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		max_w = maxf(max_w, w)
	var box_w := max_w + 6.0
	var box_h := lines.size() * line_height + 4.0

	var glc := GameConstants.ground_label_colors(team)
	var text_color: Color = glc[0]
	var bg_color: Color = glc[1]

	var rotated_offset := (label_offset * inv_zoom).rotated(inv_rot)
	var scale_v := Vector2(inv_zoom, inv_zoom)
	draw_set_transform(rotated_offset, inv_rot, scale_v)
	draw_rect(Rect2(-1, -1, box_w, box_h), bg_color)
	for i in lines.size():
		draw_string(_font, Vector2(2, 10 + i * line_height), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## _draw_destroyed 已被 NavalDestruction.draw 取代，保留作兼容接口但不再使用
