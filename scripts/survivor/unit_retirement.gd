extends RefCounted

## 资源回收的共同空间门；不拥有任务结果，也不创建常驻节点。
const OFFSCREEN_GRACE_S := 8.0
const FREE_OUTSET_PX := 800.0
const PLAYER_CLEARANCE_PX := 5000.0
const VIEW_MARGIN_PX := 1200.0
const EXIT_OUTSET_PX := PLAYER_CLEARANCE_PX + VIEW_MARGIN_PX + 400.0
const CHECK_INTERVAL_S := 0.2
const FREE_BUDGET := 4
const DIRECTIVE_PRIORITY := 100

static func begin_aircraft_exit(ac: Aircraft, exit_point: Vector2) -> void:
	if bool(ac.get_meta(&"world_retiring", false)):
		return
	ac.set_meta(&"world_retiring", true)
	ac.set_meta(&"retire_offscreen_s", 0.0)
	ac.remove_meta(&"zone_ingress")
	ac.remove_meta(&"zone_ingress_center")
	ac.remove_meta(&"zone_ingress_arrive_radius")
	ac.is_mission_target = false
	ac.is_firing = false
	ac.clear_formation()
	ac.clear_combat_target()
	ac.is_afterburner = true
	ac.set_physics_process(true)
	ac.target_position = exit_point
	# 正常撤离机复用既有错帧模拟：每帧真实位移，完整设备/状态/导航分三相执行。
	# 保留王牌、BOSS 与 Sentinel 的既有豁免，不新增第二套简化飞行物理。
	var stagger_retirement: bool = ac.params != null and ac.params.flight_model != AircraftParams.FlightModel.ROTORCRAFT \
			and not AceTier.is_ace(ac) and not String(ac.get_meta(&"category", "")).begins_with("boss") \
			and String(ac.get_meta(&"enemy_type", "")) != "uav_commander" \
			and not bool(ac.get_meta(&"sentinel_native_escort", false))
	if stagger_retirement:
		var divisor := maxi(3, int(ac.get_meta(&"dense_battle_sim_divisor", 1)))
		ac.set_meta(&"dense_battle_sim_divisor", divisor)
		ac.set_meta(&"dense_battle_sim_phase", ac.get_instance_id() % divisor)
	if ac.params:
		ac.target_speed_kmh = AircraftPhysics.effective_max_speed_kmh(ac)
	var ai_value: Variant = ac._ai_ref
	var ai: AIController = null
	if typeof(ai_value) == TYPE_OBJECT and is_instance_valid(ai_value) and ai_value is AIController:
		ai = ai_value as AIController
	if ai == null:
		for child in ac.get_children():
			if child is AIController:
				ai = child
				break
	if ai == null:
		return
	if stagger_retirement:
		ai.ai_tick_divisor = maxi(6, ai.ai_tick_divisor)
		ai._tick_phase = ac.get_instance_id() % ai.ai_tick_divisor
	ai.set_physics_process(true)
	ai.release_target(AIController.TargetSource.TS_COMMANDED, "physical retirement")
	ai.combat_zone_anchor = null
	ai.combat_zone_radius = 0.0
	ai.enable_combat = false
	ai.enter_patrol_state(false)
	ai.waypoints = PackedVector2Array([exit_point])
	ai.current_waypoint_index = 0
	var directive := AIDirective.fly_to(exit_point, AIDirective.OnArrival.HOLD, 300.0)
	directive.priority = DIRECTIVE_PRIORITY
	ai.set_event_directive(directive)

static func release_ready(ac: Aircraft, mode: Node, player: Variant, delta: float) -> bool:
	# 缺观察者时保守保留；不能把缺引用解释成“玩家看不见”。
	if not is_instance_valid(mode) or not mode.has_method("is_world_pos_visible") \
			or typeof(player) != TYPE_OBJECT or not is_instance_valid(player) \
			or not (player is Aircraft) or player.is_destroyed:
		ac.set_meta(&"retire_offscreen_s", 0.0)
		return false
	if MapBoundary.distance_to_edge(ac.global_position) > -FREE_OUTSET_PX \
			or ac.global_position.distance_squared_to(player.global_position) < PLAYER_CLEARANCE_PX * PLAYER_CLEARANCE_PX \
			or mode.is_world_pos_visible(ac.global_position, VIEW_MARGIN_PX):
		ac.set_meta(&"retire_offscreen_s", 0.0)
		return false
	var elapsed := float(ac.get_meta(&"retire_offscreen_s", 0.0)) + delta
	ac.set_meta(&"retire_offscreen_s", elapsed)
	return elapsed + 0.0001 >= maxf(OFFSCREEN_GRACE_S,
		float(ac.get_meta(&"retire_offscreen_grace_s", OFFSCREEN_GRACE_S)))

static func free_aircraft(ac: Aircraft) -> void:
	ac.set_meta(&"xp_granted", true)
	CombatUnit.release_target_refs(ac)
	ac.set_process(false)
	ac.set_physics_process(false)
	ac.queue_free()
