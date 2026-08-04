class_name EsmPodEquipment
extends EquipmentParams

## 战区奖励 ESM 吊舱：每 0.5s 给 3000m 内友军刷新短时数据链增益。
## 消费点只读 Aircraft 上的过期时间/meta，不新增逐友军节点或每帧全场扫描。

const STATE_KEY := "esm_pod"

@export var aura_radius_m: float = 3000.0
@export var scan_interval: float = 0.5
@export var lock_rate_mult: float = 1.5
@export var reload_time_mult: float = 0.7

func _init() -> void:
	equipment_kind = "esm_pod"
	display_name = "ESM Pod"

func update(ac, delta: float) -> void:
	if ac == null or not is_instance_valid(ac) or ac.is_destroyed:
		return
	var state: Dictionary = ac.equipment_state.get(STATE_KEY, {"scan": 0.0})
	var remaining := float(state.get("scan", 0.0)) - delta
	if remaining > 0.0:
		state["scan"] = remaining
		ac.equipment_state[STATE_KEY] = state
		return
	state["scan"] = scan_interval
	ac.equipment_state[STATE_KEY] = state
	var radius_px := aura_radius_m * CombatUnit.PIXELS_PER_METER
	var radius_sq := radius_px * radius_px
	var expires_ms := Time.get_ticks_msec() + int((scan_interval + 0.25) * 1000.0)
	for unit in CombatUnit.all_units:
		if not is_instance_valid(unit) or not unit is Aircraft or unit.is_destroyed:
			continue
		if CombatUnit.teams_hostile(ac.team, unit.team):
			continue
		if ac.global_position.distance_squared_to(unit.global_position) > radius_sq:
			continue
		unit.set_meta(&"esm_aura_until_ms", expires_ms)
		unit.set_meta(&"esm_lock_rate_mult", lock_rate_mult)
		unit.set_meta(&"esm_reload_time_mult", reload_time_mult)
