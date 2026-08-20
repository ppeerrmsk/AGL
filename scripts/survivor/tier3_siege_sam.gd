class_name Tier3SiegeSAM
extends SAMUnit

var owner_tank: GroundUnit
var local_mount_offset: Vector2 = Vector2.ZERO

func configure(owner: GroundUnit, offset: Vector2) -> void:
	owner_tank = owner
	local_mount_offset = offset
	team = owner.team
	set_meta(&"tier3_child_mount", true)
	set_meta(&"no_kill_reward", true)
	set_meta(&"token_cost", 0)

func _physics_process(delta: float) -> void:
	if owner_tank == null or not is_instance_valid(owner_tank) or owner_tank.is_destroyed:
		queue_free()
		return
	global_position = owner_tank.global_position + local_mount_offset.rotated(owner_tank.heading)
	heading = owner_tank.heading
	rotation = heading
	super._physics_process(delta)

func is_lock_immune() -> bool:
	return true

func take_damage(_amount: float, _attacker: Node = null, _kind: String = "") -> void:
	pass

func take_missile_damage(_amount: float) -> void:
	pass

func _draw() -> void:
	var color := Color(1.0, 0.30, 0.14)
	draw_rect(Rect2(-7.0, -9.0, 14.0, 18.0), color.darkened(0.45), true)
	draw_line(Vector2(-5.0, -8.0), Vector2(-5.0, -17.0), color, 2.5)
	draw_line(Vector2(5.0, -8.0), Vector2(5.0, -17.0), color, 2.5)
