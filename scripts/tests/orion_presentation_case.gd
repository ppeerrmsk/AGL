extends RefCounted
## 真实物理步与渲染帧之间检查持续武器附着；不以静止坐标恒等式替代运动回归。
const Pacing = preload("res://scripts/util/display_pacing.gd")
const Laser = preload("res://scripts/survivor/orion_fang_laser.gd")

class Motion extends Node:
	var units: Array[Aircraft] = []
	func _physics_process(delta: float) -> void:
		for ac in units:
			ac.interp_prev_xform = ac.transform
			ac.interp_prev_tick = Engine.get_physics_frames()
			ac.position += Vector2(240.0, 40.0) * delta
			ac.heading += delta * 0.7
			ac.rotation = ac.heading


static func run(root: Node, controller: RefCounted, player: Aircraft) -> int:
	var mover := Motion.new()
	var saved: Array = []
	for ac: Aircraft in controller.get_members() + [player]:
		mover.units.append(ac)
		saved.append([ac.transform, ac.heading])
	root.add_child(mover)
	var old_fps := Engine.max_fps
	Engine.max_fps = 120
	var body: Aircraft = controller.body()
	var fang: Aircraft = controller.get_members()[1]
	var laser: RefCounted = controller.lasers[0]
	laser.phase = Laser.Phase.ACTIVE
	laser.beam_start = Vector2(11, 22)
	laser.beam_end = Vector2(33, 44)
	controller.lock_ids.assign([player.get_instance_id()])
	controller._rail_elapsed = 0.1
	controller._rail_target_id = player.get_instance_id()
	controller._rail_aims[0] = Vector2.RIGHT
	var frozen := {"start": Vector2(50, 70), "end": Vector2(500, 70), "life": 0.2}
	controller.rail_lines.assign([frozen])
	var max_error := 0.0
	var interpolated := 0
	var failures := 0
	for frame in range(32):
		await root.get_tree().process_frame
		controller._present_weapons()
		var overlay: Node2D = instance_from_id(controller._overlay_id)
		if overlay._locks.size() != 1 or overlay._beams.size() != 3:
			failures += 1
			continue
		var body_heading := body.heading + Pacing.display_rotation_offset(body)
		var fang_heading := fang.heading + Pacing.display_rotation_offset(fang)
		max_error = maxf(max_error, Vector2(overlay._locks[0].position).distance_to(Pacing.display_origin(player)))
		max_error = maxf(max_error, Vector2(overlay._beams[0].start).distance_to(Pacing.display_origin(fang)))
		max_error = maxf(max_error, Vector2(overlay._beams[0].end).distance_to(
			Pacing.display_origin(fang) + Vector2(sin(fang_heading), -cos(fang_heading)) * controller.Rules.BEAM_LENGTH))
		for index in range(2):
			var beam: Dictionary = overlay._beams[index + 1]
			var muzzle := Pacing.display_origin(body) + Vector2(-10.0 if index == 0 else 10.0, 0).rotated(body_heading)
			max_error = maxf(max_error, Vector2(beam.start).distance_to(muzzle))
			var direction := Vector2.RIGHT if index == 0 else (Pacing.display_origin(player) - Pacing.display_origin(body)).normalized()
			max_error = maxf(max_error, Vector2(beam.end).distance_to(muzzle + direction * 3000.0))
		if Pacing.display_origin(body).distance_to(body.global_position) > 0.01:
			interpolated += 1
		if laser.beam_start != Vector2(11, 22) or laser.beam_end != Vector2(33, 44) or overlay._rail != [frozen]:
			failures += 1
	mover.set_physics_process(false)
	for index in range(mover.units.size()):
		var ac := mover.units[index]
		ac.transform = saved[index][0]
		ac.heading = saved[index][1]
		ac.clear_trail()
	mover.queue_free()
	Engine.max_fps = old_fps
	laser.phase = Laser.Phase.COOLDOWN
	controller.lock_ids.clear()
	controller._rail_elapsed = -1.0
	controller._rail_target_id = 0
	controller._rail_aims.clear()
	controller.rail_lines.clear()
	controller._present_weapons()
	if max_error > 0.01 or interpolated == 0:
		failures += 1
	print("[ORION presentation] frames=32 interpolated=%d max_error_px=%.5f failures=%d" % [interpolated, max_error, failures])
	return failures
