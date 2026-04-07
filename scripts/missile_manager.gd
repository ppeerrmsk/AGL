class_name MissileManager
extends Node2D

const PIXELS_PER_METER: float = 0.5

var _missile_scene: PackedScene = preload("res://scenes/missile.tscn")

## 场景中所有飞机的缓存引用，由 main.gd 每帧更新
var aircraft_list: Array[Aircraft] = []

func spawn_missile(source: Aircraft, target: Aircraft, missile_params: MissileParams) -> void:
	var missile: Missile = _missile_scene.instantiate()
	missile.params = missile_params
	missile.source = source
	missile.target = target
	missile.team = source.team
	missile.heading = source.heading
	missile.speed = source.speed + 50.0  # 初速 = 载机速度 + 50 m/s
	missile.altitude = source.altitude

	# 初始位置：载机前方 15px
	var fwd := Vector2(sin(source.heading), -cos(source.heading))
	missile.global_position = source.global_position + fwd * 15.0

	# 初始化 LOS 角，避免第一帧 PN 尖峰
	var los := target.global_position - missile.global_position
	missile._prev_los_angle = atan2(los.x, -los.y)

	add_child(missile)

## 检查某目标是否已有在飞的导弹（由指定发射机发射）
func has_active_missile_at(source: Aircraft, target: Aircraft) -> bool:
	for child in get_children():
		if child is Missile:
			var m: Missile = child as Missile
			if m.is_active and m.source == source and m.target == target:
				return true
	return false

func _physics_process(_delta: float) -> void:
	for child in get_children():
		if not child is Missile:
			continue
		var missile: Missile = child as Missile

		if not missile.is_active:
			missile.queue_free()
			continue

		# 引信武装时间检查
		if missile.age < missile.params.guidance_delay:
			continue

		# 命中检测：遍历所有敌方飞机
		var fuse_radius_px := missile.params.proximity_fuse_radius * PIXELS_PER_METER
		for ac in aircraft_list:
			if not is_instance_valid(ac) or ac.is_destroyed:
				continue
			if ac.team == missile.team:
				continue
			# 2D 距离 + 高度容差
			var dist_2d := missile.global_position.distance_to(ac.global_position)
			var alt_diff := absf(missile.altitude - ac.altitude)
			if dist_2d < fuse_radius_px and alt_diff < missile.params.proximity_fuse_alt:
				ac.take_damage(missile.params.damage)
				missile.is_active = false
				missile.queue_free()
				break
