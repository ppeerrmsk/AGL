class_name AwacsSupportEvent
extends GameEvent

## 预警机支援事件（spec global-awareness-roe §2.6c）
##
## ALLY 大型机（复用 Tu-160 轰炸机轮廓/simple_ai 管线，翻阵营 + 换名换色）从南界外
## 物理飞入，在**当前战区南侧**跑道形轨道往返盘旋；不可操控、不响应任何命令。
## Buff 区：半径 8000m（4000px），仅玩家小队受益——
##   锁定速率 ×3（锁定循环单点注入）+ 区内发射的导弹追踪 G ×1.25（发射瞬间快照）。
## 在站 ON_STATION_S 后转向撤离，飞出地图即结束；被击落同样结束。
## 进场 / 离场各播一条无线电（scripted 必播）—— 光环来了没来是战术信息，
## 不能只靠玩家自己开 Tab 图发现。调度层（survivor_mode）≥180s 后可再触发。

const BUFF_RADIUS_PX := 4000.0     ## 8000m
const LOCK_RATE_MULT := 3.0        ## 区内玩家小队锁定速率倍率（等效 lock_time ÷3）
const MISSILE_G_MULT := 1.25       ## 区内发射的导弹追踪 G 倍率（发射瞬间快照）
const CRUISE_KMH := 700.0

## 在站时长（秒）。此前没有这个闸，AWACS 会一直待到被击落为止 ——
## 支援变成永久挂件，"抓住支援窗口打一波"的节奏完全不存在。
const ON_STATION_S := 180.0
## 撤离兜底超时：越界判定万一没触发也别让事件永远挂着
const EGRESS_TIMEOUT_S := 90.0
## 轨道相对战区中心的南向退避距离。
## 必须 < BUFF_RADIUS_PX，否则光环根本盖不到战区，"预警机支援"就只是个装饰。
const ORBIT_STANDOFF_PX := 2200.0
## 跑道形轨道的东西向半程
const ORBIT_HALF_SPAN_PX := 2500.0
## 轨道点距地图边界的最小余量
const ORBIT_MARGIN_PX := 1200.0
## 判定"已进入轨道"的半径：进圈才开始烧在站时间。
## AWACS 从南界外物理飞入，战区在北端时航程可达 20000px，700km/h 下要 200s ——
## 若从 spawn 就开始计时，它会没到岗就撤离，整个支援窗口白给。
const ARRIVAL_RADIUS_PX := ORBIT_HALF_SPAN_PX + 800.0
## 进场兜底超时：飞不到也强制转入在站计时，保证事件总能往前走
const INGRESS_TIMEOUT_S := 240.0

## buff 源静态注册表：注入点（锁定循环 / 导弹发射）经静态函数查询，全程 validity 守卫，
## 场景重开残留引用自然失效 —— 无需显式清理。
static var _awacs_ref: Aircraft = null

var _awacs: Aircraft = null
var _orbit_center: Vector2 = Vector2.ZERO
var _arrived: bool = false        ## 已进入轨道（进圈才开始烧在站时间）
var _ingress_t: float = 0.0       ## 进场累计秒数（兜底超时用）
var _on_station_t: float = 0.0    ## 在站累计秒数
var _egressing: bool = false      ## 已转入撤离段
var _egress_t: float = 0.0        ## 撤离累计秒数（兜底超时用）


## 区内玩家小队 shooter 的锁定速率倍率（survivor_mode._update_radar_locks 调）
static func lock_rate_mult_for(shooter: CombatUnit) -> float:
	if _awacs_ref == null or not is_instance_valid(_awacs_ref) or _awacs_ref.is_destroyed:
		return 1.0
	if shooter == null or not shooter.is_player_squad():
		return 1.0
	if shooter.global_position.distance_squared_to(_awacs_ref.global_position) \
			> BUFF_RADIUS_PX * BUFF_RADIUS_PX:
		return 1.0
	return LOCK_RATE_MULT


## 发射瞬间快照（missile_manager.spawn_missile 调）：shooter 在圈内 → 弹全程 ×1.25
static func missile_g_mult_for(source: CombatUnit) -> float:
	if source == null or not is_instance_valid(source):
		return 1.0
	return MISSILE_G_MULT if lock_rate_mult_for(source) > 1.0 else 1.0


## Tab 战术图画 buff 圈用：存活的预警机（无则 null）
static func active_awacs() -> Aircraft:
	if _awacs_ref != null and is_instance_valid(_awacs_ref) and not _awacs_ref.is_destroyed:
		return _awacs_ref
	return null


func _start() -> void:
	super._start()
	name = "awacs_support"
	var sp = director.spawner
	if sp == null:
		end()
		return
	# 轨道：当前战区南侧的跑道形往返（此前是南带两个写死的点，离战场十万八千里，
	# 光环基本盖不到玩家在打的地方）
	var half: float = MapBoundary.world_half_px()
	var center := _pick_orbit_center()
	_orbit_center = center
	var p_a := MapBoundary.clamp_inside(center + Vector2(-ORBIT_HALF_SPAN_PX, 0.0), ORBIT_MARGIN_PX)
	var p_b := MapBoundary.clamp_inside(center + Vector2(ORBIT_HALF_SPAN_PX, 0.0), ORBIT_MARGIN_PX)
	# 边缘物理飞入：南界外生成，先飞 A 点再进入往返
	var spawn_pos := Vector2(p_a.x, half + 400.0)
	var awacs: Aircraft = sp._create_enemy(sp.EnemyType.TU160, spawn_pos, 0.0)
	if awacs == null:
		end()
		return
	AllyForce.convert_aircraft(awacs)
	awacs.params.display_name = "AWACS"
	awacs.has_radio_voice = true   # 预警机是有人机组，进离场要能喊话
	awacs.params.cruise_speed = CRUISE_KMH
	awacs.params.max_speed = CRUISE_KMH
	awacs.speed = CRUISE_KMH / 3.6
	awacs.set_target_tier(CombatUnit.AltitudeTier.HIGH)
	awacs.altitude = CombatUnit.TIER_ALTITUDE[CombatUnit.AltitudeTier.HIGH]
	var ai: AIController = awacs._get_ai_controller()
	if ai:
		ai.waypoints = PackedVector2Array([p_a, p_b])   # 两点循环 = 直线往返盘旋
		ai.current_waypoint_index = 0
	_awacs = awacs
	_awacs_ref = awacs
	managed_units.append(awacs)
	EventLogger.log_event("EVENT", "AWACS",
		"inbound route=%s↔%s buff_r=%.0fm dwell=%.0fs" % [p_a.round(), p_b.round(),
			BUFF_RADIUS_PX / CombatUnit.PIXELS_PER_METER, ON_STATION_S])


func _update(delta: float) -> void:
	# 往返盘旋由 PATROL 航点循环自持；这里管存活 + 进场/在站计时 + 撤离段
	if _awacs == null or not is_instance_valid(_awacs) or _awacs.is_destroyed:
		end()
		return
	# BOSS 解锁 → 提前撤离（同王牌支援中队 / 宿敌 Orion 契约：BOSS 独享舞台，场上不留闲机）
	if not _egressing and director.mode and director.mode.has_method("is_boss_phase") \
			and director.mode.is_boss_phase():
		_begin_egress()
		return
	if not _egressing:
		if not _arrived:
			_ingress_t += delta
			var d2: float = _awacs.global_position.distance_squared_to(_orbit_center)
			if d2 <= ARRIVAL_RADIUS_PX * ARRIVAL_RADIUS_PX or _ingress_t >= INGRESS_TIMEOUT_S:
				_arrived = true
				_say("awacs_onstation")   # 就位才喊，不在界外就报到
				EventLogger.log_event("EVENT", "AWACS",
					"on station (ingress %.0fs)" % _ingress_t)
			return
		_on_station_t += delta
		if _on_station_t >= ON_STATION_S:
			_begin_egress()
		return
	# 撤离段：飞出地图（或兜底超时）即结束，buff 随事件一起下线
	_egress_t += delta
	var half: float = MapBoundary.world_half_px()
	var p: Vector2 = _awacs.global_position
	if _egress_t >= EGRESS_TIMEOUT_S or absf(p.x) > half or absf(p.y) > half:
		end()


## 转入撤离：航点改到南界外，喊一句离场，光环保留到真正飞出去为止
func _begin_egress() -> void:
	_egressing = true
	var half: float = MapBoundary.world_half_px()
	var exit_wp := Vector2(_awacs.global_position.x, half + 3000.0)
	var ai: AIController = _awacs._get_ai_controller()
	if ai:
		ai.waypoints = PackedVector2Array([exit_wp])
		ai.current_waypoint_index = 0
	_say("awacs_egress")
	EventLogger.log_event("EVENT", "AWACS", "egress → %s" % exit_wp.round())


## 轨道中心：优先玩家当前选中的战区，其次离玩家最近的可用战区，
## 都没有就退回老的南带位置。战区中心南侧 ORBIT_STANDOFF_PX 处开跑道。
func _pick_orbit_center() -> Vector2:
	var half: float = MapBoundary.world_half_px()
	var fallback := Vector2(0.0, half * 0.62)
	var m = director.mode if director else null
	if m == null or not ("_zone_data" in m) or m._zone_data == null:
		return fallback
	var zd = m._zone_data
	var best := Vector2.INF
	if zd.selected_id != &"":
		for z_any in ZoneData.ZONES:
			var z: Dictionary = z_any
			if z["id"] == zd.selected_id:
				best = z["center"]
				break
	if best == Vector2.INF:
		var pl = director.player if director else null
		var pp: Vector2 = pl.global_position if (pl != null and is_instance_valid(pl)) else Vector2.ZERO
		var best_d := INF
		for z_any in ZoneData.ZONES:
			var z: Dictionary = z_any
			if zd.get_state(z["id"]) != ZoneData.State.AVAILABLE:
				continue
			var d: float = pp.distance_squared_to(z["center"])
			if d < best_d:
				best_d = d
				best = z["center"]
	if best == Vector2.INF:
		return fallback
	return best + Vector2(0.0, ORBIT_STANDOFF_PX)


## 无线电（scripted 必播）；无线电系统缺席时静默跳过
func _say(trigger: String) -> void:
	var m = director.mode if director else null
	if m == null or _awacs == null or not is_instance_valid(_awacs):
		return
	var radio = m.get("_radio") if ("_radio" in m) else null
	if radio:
		radio.say_unit(trigger, _awacs)


func _finish() -> void:
	if _awacs_ref == _awacs:
		_awacs_ref = null
	_awacs = null
