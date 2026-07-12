class_name EscortConvoyEvent
extends GameEvent

## 护送任务事件（spec global-awareness-roe §2.6a）
##
## ALLY 运输直升机 ×3 纵队从玩家前方侧边缘飞入（机头沿途原则，复用 adds 安全航线选取），
## 沿 ~18km 直线航段飞向对侧；途中脚本派 2 波拦截中队（当级选型、不占 token、普通 XP）。
## 每架存活抵达 +40 功勋（MeritLedger 直接入账）；全灭 = 失败，无惩罚；玩家可完全无视。

const HELI_COUNT := 3
const ROUTE_LEN_PX := 9000.0        ## ~18km（60km 图真·端到端超局节奏，取可玩折衷）
const CRUISE_KMH := 300.0
const MERIT_PER_HELI := 40
const ARRIVE_DIST_PX := 400.0
const WAVE_FRACS: Array = [0.30, 0.60]   ## 按航程时间进度触发拦截波
const COLUMN_SPACING_PX := 260.0

var _helis: Array = []
var _point_b := Vector2.ZERO
var _dir := Vector2.ZERO
var _waves_fired := 0
var _arrived := 0
var _route_time := 1.0
var _elapsed := 0.0


func _start() -> void:
	super._start()
	name = "escort_convoy"
	var sp = director.spawner
	var player: Aircraft = director.player
	if sp == null or player == null or not is_instance_valid(player):
		end()
		return
	var route = sp._pick_safe_flock_route(player.global_position,
			SurvivorData.SPAWN_DISTANCE, ROUTE_LEN_PX)
	_dir = route.dir
	_point_b = route.b
	var heading_deg := rad_to_deg(atan2(_dir.x, -_dir.y))
	for i in range(HELI_COUNT):
		var back: Vector2 = -_dir * float(i) * COLUMN_SPACING_PX
		var heli: Aircraft = sp._create_enemy(sp.EnemyType.CH47, route.a + back, heading_deg)
		if heli == null:
			continue
		sp._configure_adds_unit(heli, _point_b + back, CombatUnit.AltitudeTier.LOW,
				CRUISE_KMH, "chinook", "heli", 400.0)
		AllyForce.convert_aircraft(heli)
		_helis.append(heli)
		managed_units.append(heli)
	if _helis.is_empty():
		end()
		return
	_route_time = ROUTE_LEN_PX / (CRUISE_KMH / 3.6 * CombatUnit.PIXELS_PER_METER)
	_banner(tr("EVENT_ESCORT_TITLE"), 4.5)
	EventLogger.log_event("EVENT", "Escort",
		"convoy=%d route %s→%s eta=%.0fs" % [_helis.size(), route.a.round(), _point_b.round(), _route_time])


func _update(delta: float) -> void:
	_elapsed += delta
	# 拦截波（按航程时间进度）
	if _waves_fired < WAVE_FRACS.size() and _elapsed >= _route_time * float(WAVE_FRACS[_waves_fired]):
		_spawn_intercept_wave()
		_waves_fired += 1
	# 到达 / 团灭判定
	var alive := 0
	for h in _helis:
		if h == null or not is_instance_valid(h) or h.is_destroyed:
			continue
		alive += 1
		if h.global_position.distance_to(_point_b) < ARRIVE_DIST_PX + COLUMN_SPACING_PX * 2.0:
			_arrived += 1
			h.set_meta("xp_granted", true)   # 防任何击杀误判
			h.queue_free()                   # 抵达即安全离场（终点在图边，紧接出界）
	if alive == 0:
		_settle()


func _settle() -> void:
	if _arrived > 0:
		var merit: int = _arrived * MERIT_PER_HELI
		MeritLedger.award(merit, "escort_convoy x%d" % _arrived)
		_banner("%s  +%d" % [tr("EVENT_ESCORT_SUCCESS"), merit], 4.5)
	else:
		_banner(tr("EVENT_ESCORT_FAIL"), 4.0)
	end()


## 拦截波：2~3 机当级杂鱼从航线侧向 4.5km 外入场，直扑领头直升机。
## 不占 token（meta 置 0）、普通 XP（HOSTILE 击杀检测照常）、despawn_after 兜底。
func _spawn_intercept_wave() -> void:
	var lead: Aircraft = null
	for h in _helis:
		if h != null and is_instance_valid(h) and not h.is_destroyed:
			lead = h
			break
	if lead == null:
		return
	var sp = director.spawner
	var n := randi_range(2, 3)
	var etype = sp.EnemyType.UAV if sp.survivor_player.level <= SurvivorData.UAV_RETIRE_LEVEL \
			else sp.EnemyType.F86
	var side := 1.0 if randf() < 0.5 else -1.0
	var perp := Vector2(-_dir.y, _dir.x) * side
	var base: Vector2 = lead.global_position + perp * 4500.0
	var atk_dir := -perp
	var hdg := rad_to_deg(atan2(atk_dir.x, -atk_dir.y))
	for i in range(n):
		var pos := base + _dir * (float(i) - 1.0) * 250.0
		var e: Aircraft = sp._create_enemy(etype, pos, hdg)
		if e == null:
			continue
		e.set_meta("token_cost", 0)
		e.set_meta("despawn_after", director.mode.game_time + 240.0)
		var ai: AIController = sp._get_ai(e)
		if ai and ai.acquire_target(lead, AIController.TargetSource.TS_BOSS, "escort intercept"):
			ai._state = AIController.AIState.ENGAGE if not ai.simple_ai else AIController.AIState.PATROL
			ai._engage_timer = 0.0
			ai._cooldown_timer = 0.0
			e.ai_override_pursuit = true
	EventLogger.log_event("EVENT", "Escort", "intercept wave %d: %d× spawned" % [_waves_fired + 1, n])


func _banner(msg: String, dur: float) -> void:
	if director and director.mode and director.mode._zone_hint:
		director.mode._zone_hint.show_temp(msg, dur)
