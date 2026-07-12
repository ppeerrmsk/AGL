class_name AwacsSupportEvent
extends GameEvent

## 预警机支援事件（spec global-awareness-roe §2.6c）
##
## ALLY 大型机（复用 Tu-160 轰炸机轮廓/simple_ai 管线，翻阵营 + 换名换色）从南界外
## 物理飞入，在南带两固定点之间直线往返盘旋；不可操控、不响应任何命令。
## Buff 区：半径 8000m（4000px），仅玩家小队受益——
##   锁定速率 ×3（锁定循环单点注入）+ 区内发射的导弹追踪 G ×1.25（发射瞬间快照）。
## 被击落 → buff 圈消失，事件结束；调度层（survivor_mode）≥180s 后可再触发。

const BUFF_RADIUS_PX := 4000.0     ## 8000m
const LOCK_RATE_MULT := 3.0        ## 区内玩家小队锁定速率倍率（等效 lock_time ÷3）
const MISSILE_G_MULT := 1.25       ## 区内发射的导弹追踪 G 倍率（发射瞬间快照）
const CRUISE_KMH := 700.0

## buff 源静态注册表：注入点（锁定循环 / 导弹发射）经静态函数查询，全程 validity 守卫，
## 场景重开残留引用自然失效 —— 无需显式清理。
static var _awacs_ref: Aircraft = null

var _awacs: Aircraft = null


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
	# 南带（友方侧）两固定点：y = 世界半宽 × 0.62（60km 图 ≈ +9300px），点距边 ≥6km、
	# 避开全部战区圆（战区最南 E 中心 y=7000 半径 2500 → 缘 9500，横向错开即可）
	var half: float = MapBoundary.world_half_px()
	var p_a := Vector2(-6000.0, half * 0.62)
	var p_b := Vector2(6000.0, half * 0.62)
	# 边缘物理飞入：南界外生成，先飞 A 点再进入往返
	var spawn_pos := Vector2(p_a.x - 2000.0, half + 400.0)
	var awacs: Aircraft = sp._create_enemy(sp.EnemyType.TU160, spawn_pos, 0.0)
	if awacs == null:
		end()
		return
	AllyForce.convert_aircraft(awacs)
	awacs.params.display_name = "AWACS"
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
		"onstation route=%s↔%s buff_r=%.0fm" % [p_a.round(), p_b.round(),
			BUFF_RADIUS_PX / CombatUnit.PIXELS_PER_METER])


func _update(_delta: float) -> void:
	# 直线往返由 PATROL 航点循环自持；这里只监护存活（被击落 → buff 圈消失 → 事件结束）
	if _awacs == null or not is_instance_valid(_awacs) or _awacs.is_destroyed:
		end()


func _finish() -> void:
	if _awacs_ref == _awacs:
		_awacs_ref = null
	_awacs = null
