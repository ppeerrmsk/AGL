class_name SnowblindController
extends RefCounted

## Snowblind 的唯一运行时控制器。由 Spawner 持有并 tick；常态 5Hz，禁止逐机节点扫描。

const RADIUS_PX: float = 2000.0       ## 4000m
const EXIT_RADIUS_PX: float = 2250.0  ## 4500m
const EXIT_DELAY_S: float = 2.0
const MIN_REVEAL_S: float = 3.0
const TICK_INTERVAL_S: float = 0.2

var _spawner
var _tick_accum: float = 0.0
var _revealed: bool = false
var _reveal_elapsed: float = 0.0
var _outside_elapsed: float = 0.0
var _concealed: Array[Aircraft] = []
var _saved_modulate: Dictionary = {} ## 非本体幕内机 → 原 modulate；只在显隐边沿写一次
var _host: Aircraft = null


func _init(spawner) -> void:
	_spawner = spawner


## 创建当帧登记并立即隐藏本体，不能等待 Token 重算或下一次 5Hz tick。
func register(host: Aircraft) -> void:
	if host == null or not is_instance_valid(host):
		return
	if _host != null and is_instance_valid(_host) and _host != host:
		push_warning("[Snowblind] 同场只支持一个雪幕，忽略重复本体 %s" % host.callsign)
		return
	_host = host
	_revealed = false
	_reveal_elapsed = 0.0
	_outside_elapsed = 0.0
	_set_visual_concealed(host, true)
	_conceal_one(host, host.get_instance_id(), host)
	# 下一次 spawner.update 不等 0.2s，立即把刚创建的护卫一并纳入。
	_tick_accum = TICK_INTERVAL_S


func refresh_now() -> void:
	_tick_accum = TICK_INTERVAL_S
	tick(0.0)


func has_active_state() -> bool:
	return (_host != null and is_instance_valid(_host)) \
		or _revealed or not _concealed.is_empty()


func shutdown() -> void:
	if _host != null and is_instance_valid(_host):
		_set_visual_concealed(_host, false)
	_clear_concealment()
	_host = null
	_spawner = null


## 3★ DEADAIR 占用唯一场型支援槽时退役旧雪幕；实体仍可自然交战/离场，但不会被扫描复活。
func retire_for_priority_field() -> void:
	if _host != null and is_instance_valid(_host):
		_set_visual_concealed(_host, false)
		_host.set_meta(&"support_field_retired", true)
	_clear_concealment()
	_revealed = false
	_reveal_elapsed = 0.0
	_outside_elapsed = 0.0
	_host = null
	_tick_accum = 0.0


func tick(delta: float) -> void:
	_tick_accum += delta
	if _tick_accum < TICK_INTERVAL_S:
		return
	var step := _tick_accum
	_tick_accum = 0.0
	var host := _find_host()
	if host == null:
		_clear_concealment()
		_revealed = false
		_host = null
		return

	var members := _direct_player_members()
	var player_inside := false
	var all_outside_exit := not members.is_empty()
	for member in members:
		var distance_sq := member.global_position.distance_squared_to(host.global_position)
		if distance_sq <= RADIUS_PX * RADIUS_PX:
			player_inside = true
		if distance_sq <= EXIT_RADIUS_PX * EXIT_RADIUS_PX:
			all_outside_exit = false

	if player_inside:
		if not _revealed:
			EventLogger.log_event("SNOWBLIND", host.callsign, "shroud breached; contacts revealed")
			_reveal_elapsed = 0.0
			_order_escape(host, members)
		else:
			_reveal_elapsed += step
		_revealed = true
		_outside_elapsed = 0.0
	elif _revealed:
		_reveal_elapsed += step
		_outside_elapsed = _outside_elapsed + step if all_outside_exit else 0.0
		if _reveal_elapsed >= MIN_REVEAL_S and _outside_elapsed >= EXIT_DELAY_S:
			_revealed = false
			_reveal_elapsed = 0.0
			_outside_elapsed = 0.0
			EventLogger.log_event("SNOWBLIND", host.callsign, "shroud concealed again")

	if _revealed:
		_set_visual_concealed(host, false)
		_clear_concealment()
	else:
		_set_visual_concealed(host, true)
		_apply_concealment(host)


## 纯函数，供无头测试滞回边界。
static func next_reveal_state(revealed: bool, player_inside: bool, all_outside_exit: bool,
		reveal_elapsed: float, outside_elapsed: float, delta: float) -> Dictionary:
	if player_inside:
		return {"revealed": true,
			"reveal_elapsed": reveal_elapsed + delta if revealed else 0.0,
			"outside_elapsed": 0.0}
	if not revealed:
		return {"revealed": false, "reveal_elapsed": 0.0, "outside_elapsed": 0.0}
	var next_reveal := reveal_elapsed + delta
	var next_outside := outside_elapsed + delta if all_outside_exit else 0.0
	var stays_revealed := next_reveal < MIN_REVEAL_S or next_outside < EXIT_DELAY_S
	return {
		"revealed": stays_revealed,
		"reveal_elapsed": next_reveal if stays_revealed else 0.0,
		"outside_elapsed": next_outside if stays_revealed else 0.0,
	}


func _find_host() -> Aircraft:
	if _host != null and is_instance_valid(_host) and not _host.is_destroyed:
		return _host
	for unit in CombatUnit.all_units:
		if unit is Aircraft and is_instance_valid(unit) and not unit.is_destroyed \
				and not bool(unit.get_meta(&"support_field_retired", false)) \
				and str(unit.get_meta("enemy_type", "")) == "snowblind":
			_host = unit as Aircraft
			return _host
	return null


func _direct_player_members() -> Array[Aircraft]:
	var out: Array[Aircraft] = []
	if _spawner == null or _spawner.mode == null:
		return out
	for unit in _spawner.mode._squad_members_alive():
		if unit is Aircraft:
			out.append(unit as Aircraft)
	return out


func _apply_concealment(host: Aircraft) -> void:
	var shroud_id := host.get_instance_id()
	var radius_sq := RADIUS_PX * RADIUS_PX
	var desired: Dictionary = {}
	for unit in CombatUnit.all_units:
		if not unit is Aircraft or not is_instance_valid(unit) or unit.is_destroyed:
			continue
		var ac := unit as Aircraft
		if ac.team != CombatUnit.TEAM_HOSTILE \
				or ac.global_position.distance_squared_to(host.global_position) > radius_sq:
			continue
		desired[ac] = true
	for i in range(_concealed.size() - 1, -1, -1):
		var previous := _concealed[i]
		if is_instance_valid(previous) and desired.has(previous):
			continue
		if is_instance_valid(previous):
			_clear_one(previous)
		_concealed.remove_at(i)
	for candidate in desired:
		var ac := candidate as Aircraft
		if ac in _concealed:
			continue
		_conceal_one(ac, shroud_id, host)
	_release_cross_boundary_targets()


func _conceal_one(ac: Aircraft, shroud_id: int, host: Aircraft) -> void:
	if ac in _concealed:
		return
	ac.sensor_hidden = true
	ac.sensor_shroud_id = shroud_id
	if ac == host:
		# 实体仍不可选/锁定/自动攻击；圆心轮廓由雪幕 shader 独立提示。
		if ac._trail_ribbon:
			ac._trail_ribbon.visible = false
	else:
		_saved_modulate[ac] = ac.modulate
		ac.modulate = Color(ac.modulate, 0.0)
	ac.queue_redraw()
	_concealed.append(ac)


func _set_visual_concealed(host: Aircraft, concealed: bool) -> void:
	SnowblindShroudVisual.set_concealed(host, concealed)


func _clear_concealment() -> void:
	for ac in _concealed:
		if not is_instance_valid(ac):
			continue
		_clear_one(ac)
	_concealed.clear()
	_saved_modulate.clear()


func _clear_one(ac: Aircraft) -> void:
	ac.sensor_hidden = false
	ac.sensor_shroud_id = 0
	if _saved_modulate.has(ac):
		ac.modulate = _saved_modulate[ac]
		_saved_modulate.erase(ac)
	elif ac._trail_ribbon:
		ac._trail_ribbon.visible = true
	ac.queue_redraw()


func _release_cross_boundary_targets() -> void:
	for unit in CombatUnit.all_units:
		if not unit is Aircraft or not is_instance_valid(unit) or unit.is_destroyed:
			continue
		var ac := unit as Aircraft
		var target := ac.combat_target
		if target == null or not is_instance_valid(target) \
				or not ac.is_sensor_engagement_obscured(target):
			continue
		var ai = _spawner._get_ai(ac) if _spawner else null
		if ai:
			ai.release_target(AIController.TargetSource.TS_COMMANDED, "snowblind boundary")
		else:
			ac.clear_combat_target()
		ac.is_firing = false
		if ac.commanded_target == target:
			ac.commanded_target = null


func _order_escape(host: Aircraft, members: Array[Aircraft]) -> void:
	if members.is_empty():
		return
	var nearest := members[0]
	var best_sq := host.global_position.distance_squared_to(nearest.global_position)
	for member in members:
		var distance_sq := host.global_position.distance_squared_to(member.global_position)
		if distance_sq < best_sq:
			nearest = member
			best_sq = distance_sq
	var away := (host.global_position - nearest.global_position).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	var ai = _spawner._get_ai(host) if _spawner else null
	if ai:
		ai.enable_combat = false
		ai.evade_missiles = false
		ai.waypoints = PackedVector2Array([host.global_position + away * 4500.0])
	host.is_afterburner = false
	host.target_speed_kmh = host.params.cruise_speed if host.params else 400.0
