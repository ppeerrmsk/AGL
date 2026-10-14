extends RefCounted
const AO := preload("res://scripts/experiments/tokyo_baked_ao.gd")
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")


static func run(battle: Node, map: Node, output: String) -> int:
	var directory := OS.get_environment("AGL_TOKYO_AO")
	var tree := battle.get_tree()
	var paused := tree.paused
	var ignore: bool = battle.camera.ignore_rotation
	var collision := var_to_bytes(BuildingRenderer._cache_entries)
	var geometry := preload("res://scripts/tests/tokyo_static_shadow_review.gd").new()
	var rows: Array = []
	var fail := 0
	tree.paused = true
	battle.camera.ignore_rotation = false
	var poses := [Vector2(0.65, 0), Vector2(0.98, 0), Vector2(1.3, 0), Vector2(1.95, 0), Vector2(2.4, 0), Vector2(2.4, -14), Vector2(2.4, 14), Vector2(5.0, 0)]
	for index in poses.size():
		var pose: Vector2 = poses[index]
		battle.camera.position = Vector2(-5900, -1100)
		battle.camera.zoom = Vector2.ONE * pose.x
		battle.camera.rotation = deg_to_rad(pose.y)
		battle.camera.force_update_scroll()
		await tree.create_timer(0.3).timeout
		var deadline := Time.get_ticks_msec() + 15000
		while not Session.state_ready(map.debug_state()) and Time.get_ticks_msec() < deadline:
			await tree.process_frame
		var state: Dictionary = map.debug_state()
		if not Session.state_ready(state):
			fail += 1
			continue
		map.set_process(false)
		var native := geometry._geometry_state(map)
		var original_materials: Array = map._materials.duplicate()
		var stem := output.path_join("r64_ao_%02d" % index)
		var original := await _capture(battle, map, stem + "_none")
		var layer := AO.new()
		if not layer.bind_ao(map, directory, state.output_scale):
			fail += 1
			rows.append({"zoom": pose.x, "rotation": pose.y, "rejected": true, "state": state})
			map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			map.set_process(true)
			continue
		layer.strength(0.0)
		var zero := await _capture(battle, map, stem + "_zero")
		var zero_error := Pixels._pixel_error(original, zero)
		var differences := []
		for strength: float in [0.45, 0.75]:
			layer.strength(strength)
			var candidate := await _capture(battle, map, stem + "_ao%02d" % roundi(strength*100))
			differences.append(Pixels._pixel_error(original, candidate))
		var unchanged: bool = geometry._geometry_state(map) == native and var_to_bytes(BuildingRenderer._cache_entries) == collision
		var masks := Pixels._screen_bounds(map, [{"original": [[-6100,-1300],[-5700,-1300],[-5700,-900],[-6100,-900]], "candidate": [], "height_px": map._source_max_height}])
		var stats := layer.stats.duplicate(true)
		var components := OS.get_environment("AGL_TOKYO_AO_COMPONENTS") == "1" and int(stats["size"]) < 2048
		var coarse_ao: ImageTexture = layer._texture if components else null
		var coarse_height: ImageTexture = layer._height_texture if components else null
		layer.close()
		layer.close()
		# 同一相机/几何比较下一精细纹理，独立暴露接收高度边缘的切档差。
		var finer_error := -1
		var component_errors := {}
		if int(stats["size"]) < 2048:
			var finer := AO.new()
			if finer.bind_ao(map, directory, float(stats.max_scale) + 0.001):
				finer.strength(0.45)
				var fine := await _capture(battle, map, stem + "_finer45")
				var coarse := Image.load_from_file(stem + "_ao45_native.png")
				finer_error = Pixels._pixel_error(coarse, fine)
				if components:
					var peak := int(state.stream.bytes) + int(state.stream.reserved_bytes) + int(stats.conservative_bytes) + int(finer.stats.conservative_bytes)
					fail += int(peak > 96 * 1024 * 1024)
					if peak <= 96 * 1024 * 1024:
						for material: ShaderMaterial in finer._replacement:
							material.set_shader_parameter("baked_height", coarse_height)
						var only_ao := await _capture(battle, map, stem + "_only_ao_finer")
						for material: ShaderMaterial in finer._replacement:
							material.set_shader_parameter("baked_height", finer._height_texture)
							material.set_shader_parameter("baked_ao", coarse_ao)
						var only_height := await _capture(battle, map, stem + "_only_height_finer")
						component_errors = {"only_ao_max": Pixels._pixel_error(coarse, only_ao),
							"only_height_max": Pixels._pixel_error(coarse, only_height),
							"height_to_full_max": Pixels._pixel_error(only_height, fine), "conservative_peak_bytes": peak}
				finer.close()
			else:
				fail += 1
		coarse_ao = null
		coarse_height = null
		var restored := await _capture(battle, map, stem + "_restored")
		var restore_error := Pixels._pixel_error(original, restored)
		fail += int(zero_error > 1 or restore_error > 1 or not unchanged or map._materials != original_materials)
		fail += int(differences[0] == 0 or differences[1] < differences[0])
		rows.append({"zoom": pose.x, "rotation": pose.y, "state": state, "ao": stats, "stem": stem,
			"allowed_screen_bounds": masks, "zero_error": zero_error, "restore_error": restore_error,
			"geometry_collision_unchanged": unchanged, "ao_max_differences": differences, "same_view_finer_max_error": finer_error,
			"components": component_errors})
		map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		map.set_process(true)
		print("[R64 AO Visual] zoom=", pose.x, " rotation=", pose.y, " texture=", stats["size"], " differences=", differences, " restored=", restore_error)
	tree.paused = paused
	battle.camera.ignore_rotation = ignore
	var file := FileAccess.open(output.path_join("r64_ao_review.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "fail": fail, "fps_evidence": false, "horizontal_only": true}, "\t"))
	file.close()
	return fail


static func _capture(battle: Node, map: Node, stem: String) -> Image:
	map._viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for frame in 4:
		await RenderingServer.frame_post_draw
	var native: Image = map._viewport.get_texture().get_image()
	assert(native.save_png(stem + "_native.png") == OK)
	assert(battle.get_viewport().get_texture().get_image().save_png(stem + ".png") == OK)
	return native
