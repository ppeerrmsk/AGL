class_name ArmoredTrainBoss
extends BossEncounter

const TRAIN_SCRIPT := preload("res://scripts/survivor/armored_train_unit.gd")
const DESERT_MAP_PATH := "res://resources/maps/desert_railway_preview.aglmap"
const RAILWAY_ID := "iron_serpent_main"

var _train: Variant = null
var _failed: bool = false


func spawn(scene_root: Node, _player: Aircraft, bullet_manager: Node2D,
		missile_manager: Node2D, _anchor: Vector2 = Vector2.INF) -> void:
	_train = TRAIN_SCRIPT.new()
	var route := train_route()
	_train.configure_route(route)
	_train.route_finished.connect(_on_route_finished)
	scene_root.add_child(_train)
	_train.arm_segments(scene_root, bullet_manager, missile_manager)
	_train.begin_arrival_ingress()
	_failed = false
	active = true
	hud_visible = false
	EventLogger.log_event("BOSS", "ArmoredTrainSpawn",
		"segments=7 hp=%.0f route_px=%.0f" % [
			TRAIN_SCRIPT.TOTAL_MAX_HP, route_length_px(route)])


func engage() -> void:
	if _train != null and is_instance_valid(_train):
		_train.finish_arrival_ingress()
	EventLogger.log_event("BOSS", "ArmoredTrainEngaged", "left-to-right escape run")


func update(_delta: float) -> void:
	var raw: Variant = _train
	if typeof(raw) != TYPE_OBJECT or raw == null or not is_instance_valid(raw):
		if not _failed:
			active = false
		return
	if _train.is_destroyed:
		active = false


func has_failed() -> bool:
	return _failed


func failure_reason() -> String:
	return "armored_train_escaped" if _failed else ""


func get_display_members() -> Array:
	var raw: Variant = _train
	if typeof(raw) == TYPE_OBJECT and raw != null and is_instance_valid(raw):
		return _train.get_display_segments()
	return []


func get_hud_entries() -> Array[Dictionary]:
	var raw: Variant = _train
	if typeof(raw) != TYPE_OBJECT or raw == null or not is_instance_valid(raw):
		return []
	return [{
		"name": "IRON SERPENT",
		"generation": 0,
		"hp": _train.aggregate_hp(),
		"max_hp": TRAIN_SCRIPT.TOTAL_MAX_HP,
		"state": "%s · %d/14 · %03d%%" % [
			_train.active_segment_name(), _train.active_tail_index() + 1,
			int(round(_train.route_progress * 100.0))],
		"altitude": 0.0,
		"seconds": 0.0,
	}]


func set_player_ref(_p: Aircraft) -> void:
	# 列车不追逐玩家，也不缓存玩家引用。
	pass


func _on_route_finished() -> void:
	if _train == null or not is_instance_valid(_train) or _train.is_destroyed:
		return
	_failed = true
	active = false
	EventLogger.log_event("BOSS", "ArmoredTrainEscaped", "route_progress=1.0")


static func route_length_px(points: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(maxi(points.size() - 1, 0)):
		total += points[i].distance_to(points[i + 1])
	return total


static func train_route() -> PackedVector2Array:
	var doc := MapDocument.load_from(DESERT_MAP_PATH)
	if doc != null:
		for raw in doc.railways:
			if not (raw is Dictionary) or str(raw.get("id", "")) != RAILWAY_ID:
				continue
			var points := PackedVector2Array()
			for p in raw.get("points", []):
				if p is Array and p.size() >= 2:
					points.append(Vector2(float(p[0]), float(p[1])))
			if points.size() >= 2:
				return points
	push_error("ArmoredTrainBoss: desert railway route missing: %s" % RAILWAY_ID)
	return PackedVector2Array()
