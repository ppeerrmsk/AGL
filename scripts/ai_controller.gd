class_name AIController
extends Node

@export var aircraft: Aircraft
@export var waypoints: PackedVector2Array = PackedVector2Array()
@export var patrol_altitude: float = 5000.0
@export var arrival_distance: float = 100.0  ## 像素，到达航路点的判定距离

var current_waypoint_index: int = 0

func _ready() -> void:
	if waypoints.is_empty():
		_generate_default_waypoints()
	if aircraft:
		aircraft.target_altitude = patrol_altitude
		_set_next_waypoint()

func _physics_process(_delta: float) -> void:
	if not aircraft or waypoints.is_empty() or aircraft.is_destroyed:
		return

	var target := waypoints[current_waypoint_index]
	var dist := aircraft.global_position.distance_to(target)

	if dist < arrival_distance:
		current_waypoint_index = (current_waypoint_index + 1) % waypoints.size()
		_set_next_waypoint()

func _set_next_waypoint() -> void:
	aircraft.target_position = waypoints[current_waypoint_index]

func _generate_default_waypoints() -> void:
	# 生成一个简单的矩形巡逻路线
	var center := aircraft.global_position if aircraft else Vector2.ZERO
	var radius := 500.0  # 像素
	waypoints = PackedVector2Array([
		center + Vector2(radius, -radius),
		center + Vector2(radius, radius),
		center + Vector2(-radius, radius),
		center + Vector2(-radius, -radius),
	])
