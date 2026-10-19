extends "res://scripts/experiments/volume_3d_lab.gd"
## S3 真实地形/瓦片跨区与 LOD 成本；不冒充有参战者的 C1。


func _capture_sequence() -> void:
	var tree := get_tree()
	var viewport := get_viewport()
	var viewport_rid := viewport.get_viewport_rid()
	var measure_gpu := OS.get_environment("AGL_VOLUME_RENDER_TIMING") == "1"
	var diagnose_stalls := OS.get_environment("AGL_VOLUME_STALL_DIAGNOSTICS") == "1"
	var stalls: Array[Dictionary] = []
	RenderingServer.viewport_set_measure_render_time(viewport_rid, measure_gpu)
	var points: Array[Vector2] = [Vector2(11227, 43), Vector2(2450, 1150),
		Vector2(-11000, -10500), Vector2(-5900, -6250), Vector2(4800, 400), Vector2(-6359.84, -15465.87)]
	var water_coverage_mode := OS.get_environment("AGL_VOLUME_WATER_COVERAGE_PERF")
	if OS.get_environment("AGL_VOLUME_CROSSING_PERF") == "1":
		points = [Vector2(615.01011,-3069.83700),Vector2(-1508.94404,-5111.29061),
			Vector2(3410.22448,-1800.78650),Vector2(8672,4318),Vector2(4800,400),Vector2(-10100,10100)]
	if water_coverage_mode in ["legacy", "coverage"]:
		points = [Vector2(-10100, 10100), Vector2(-14914.4116, 9001.04241), Vector2(-3602.54109, 9600.04538),
			Vector2(-3761.94, -7540.73), Vector2(-1916.3, -8621.03), Vector2(-757.31, 9538.58)]
		var water_material := _satellite_ground._details.get_node("Source_Water_Contours").material_override as ShaderMaterial
		water_material.set_shader_parameter("watercourse_coverage_enabled", water_coverage_mode == "coverage")
		assert(water_material.get_shader_parameter("watercourse_coverage_enabled") == (water_coverage_mode == "coverage"))
	_set_play_map_view(points[0], 0.26)
	if OS.get_environment("AGL_VOLUME_NORTHEAST_RIVER_PERF") == "1":
		points = [Vector2(5260,-13800),Vector2(3500,-12300),Vector2(2000,-15500),
			Vector2(4800,400),Vector2(8672,4318),Vector2(-10100,10100)]
		_set_play_map_view(points[0], 0.26)
	await tree.create_timer(3.0, true, false, true).timeout
	var start := Time.get_ticks_usec()
	var start_wall := Time.get_unix_time_from_system()
	var previous := start
	var duration := maxf(36.0, float(tree.get_meta("bench_duration", 36.0)))
	var samples := PackedFloat64Array()
	var visited := {}
	var below := 0
	var previous_phase := -1
	var submitted_frames := 0
	var min_primitives := 2147483647
	var max_primitives := 0
	var min_draw_calls := 2147483647
	var gpu_nonzero := 0
	var gpu_total_ms := 0.0
	while float(Time.get_ticks_usec() - start) / 1000000.0 < duration:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		var frame_seconds := float(now - previous) / 1000000.0
		previous = now
		samples.append(frame_seconds)
		if frame_seconds > 1.0 / 60.0:
			below += 1
			# 仅显式诊断时保留最多8个坏帧；不让均值掩盖跨区卡顿。
			if diagnose_stalls and stalls.size() < 8:
				stalls.append({"elapsed_s": (now - start) / 1000000.0,
					"wall_unix_s": Time.get_unix_time_from_system(),
					"frame_ms": frame_seconds * 1000.0, "site": previous_phase,
					"render_timing": _render_diagnostic(viewport_rid, measure_gpu),
					"streaming": _streaming_snapshot(), "ground": _satellite_ground.debug_state()})
		# 全局计数在 draw_viewports 每轮重新累计；只读 viewport 的旧计数可能遗漏跳过绘制。
		var primitives := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		var draw_calls := viewport.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE, Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		var global_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		submitted_frames += int(render_sample_valid(primitives, draw_calls, global_calls))
		min_primitives = mini(min_primitives, primitives)
		max_primitives = maxi(max_primitives, primitives)
		min_draw_calls = mini(min_draw_calls, draw_calls)
		if measure_gpu:
			var gpu_ms := RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
			if is_finite(gpu_ms) and gpu_ms > 0.0:
				gpu_nonzero += 1
				gpu_total_ms += gpu_ms
		var elapsed := float(now - start) / 1000000.0
		var phase := mini(int(elapsed / 6.0), points.size() - 1)
		if phase != previous_phase:
			previous_phase = phase
			visited[phase] = true
		var zoom_value := lerpf(0.18, 0.65, (sin(elapsed * PI / 3) + 1) * 0.5)
		_set_play_map_view(points[phase] + Vector2(sin(elapsed) * 240, cos(elapsed) * 140), zoom_value)
	samples.sort()
	var sum := 0.0
	for seconds in samples:
		sum += seconds
	var report := "S3 terrain-only transition: sites=%d/6 frames=%d avg_fps=%.2f p1_fps=%.2f worst_frame_fps=%.2f frames_below_60=%d\n%s" % [
		visited.size(), samples.size(), samples.size() / sum,
		1.0 / samples[int(samples.size() * 0.99)], 1.0 / samples[-1], below,
		str(_satellite_ground.debug_state())]
	report += "\nrender_submission frames=%d/%d primitives_min=%d primitives_max=%d draw_calls_min=%d proof=submission_not_screen_presentation" % [
		submitted_frames, samples.size(), min_primitives, max_primitives, min_draw_calls]
	report += "\nwater_coverage_mode=%s source_watercourses=%d source_segments=%d" % [water_coverage_mode,
		int(_satellite_ground._details.get_meta("watercourse_count", 0)), int(_satellite_ground._details.get_meta("watercourse_segments", 0))]
	report += "\nnortheast_river_route=%s" % OS.get_environment("AGL_VOLUME_NORTHEAST_RIVER_PERF")
	report += "\nrender_timing=%s gpu_nonzero=%d gpu_avg_ms=%.4f diagnostic_only=%s" % [
		"on" if measure_gpu else "off", gpu_nonzero, gpu_total_ms / maxf(1.0, samples.size()), measure_gpu]
	if diagnose_stalls:
		report += "\nstall_diagnostics=true diagnostic_only=true stalls=%s" % JSON.stringify(stalls)
		report += "\nruntime_context=%s" % JSON.stringify({"sampling_start_unix_s": start_wall,
			"max_fps": Engine.max_fps, "vsync_mode": DisplayServer.window_get_vsync_mode(),
			"user_data_dir": OS.get_user_data_dir(), "viewport_size": viewport.get_visible_rect().size,
			"renderer": RenderingServer.get_current_rendering_method()})
	var motion_end := _streaming_snapshot()
	# 正式计时结束后才等待；由原 renderer 正常 tick 收敛，不强灌或增预算。
	await tree.create_timer(1.5, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var settled := _streaming_snapshot()
	var converged: bool = not settled.is_empty() and settled.current_lod == settled.target_lod \
		and not settled.transitioning and settled.missing_keys.is_empty() \
		and settled.unbound_visible_3d.is_empty() and settled.strategic_bridge_ready
	report += "\nstreaming_motion_end=%s\nstreaming_settled_1_5s=%s\nstreaming_converged=%s coverage=source_ground_viewport_not_pixel_occlusion" % [
		JSON.stringify(motion_end), JSON.stringify(settled), converged]
	print(report)
	var image_error := viewport.get_texture().get_image().save_png("res://bench/results/volume_relief_stress.png")
	var stamp := Time.get_datetime_string_from_system(true).replace(":", "").replace("-", "").replace("T", "_")
	var file := FileAccess.open("res://bench/results/volume_relief_stress_%s.txt" % stamp, FileAccess.WRITE)
	if file != null:
		file.store_string("Godot %s GL Compatibility Visual\n%s" % [Engine.get_version_info().string, report])
		file.close()
	RenderingServer.viewport_set_measure_render_time(viewport_rid, false)
	tree.quit(0 if below == 0 and visited.size() == 6 and file != null and image_error == OK
		and submitted_frames == samples.size() and not samples.is_empty() and converged else 1)


static func _render_diagnostic(viewport_rid: RID, enabled: bool) -> Dictionary:
	# 仅已有坏帧诊断分支调用；GPU/CPU是后端最近测量值，不能当作该停顿的同步归因。
	var result := {"enabled": enabled, "scope": "latest_backend_measurement_not_stall_attribution"}
	if enabled:
		result["cpu_ms"] = RenderingServer.viewport_get_measured_render_time_cpu(viewport_rid)
		result["gpu_ms"] = RenderingServer.viewport_get_measured_render_time_gpu(viewport_rid)
	return result


func _streaming_snapshot() -> Dictionary:
	if not is_instance_valid(_satellite_ground):
		return {}
	var value: Variant = _satellite_ground._source.get_ref() if _satellite_ground._source != null else null
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value) or not value is RasterBasemapRenderer:
		return {}
	var source: RasterBasemapRenderer = value
	var state := source.debug_state()
	var lod := StringName(state.target_lod)
	var visible: Array[String] = source._visible_keys(lod) if lod != source.LOD_STRATEGIC else []
	var missing_visible: Array[String] = []
	var missing_prefetch: Array[String] = []
	for key: String in state.missing_keys:
		if key in visible:
			missing_visible.append(key)
		else:
			missing_prefetch.append(key)
	var unbound: Array[String] = []
	var native := _satellite_ground._tactical_style
	var bridge: Dictionary = {}
	if is_instance_valid(source._strategic_sprite):
		bridge = _satellite_ground._planes.get(source._strategic_sprite.get_instance_id(), {})
	var bridge_ready: bool = not bridge.is_empty() and is_instance_valid(bridge.node) and bridge.node.visible
	var native_rect := Rect2()
	if native and bridge_ready:
		# 仅认可经过逐面等价回归的原归档实例；AABB 不能独自证明内部无孔洞。
		var relief: RefCounted = _satellite_ground.relief
		bridge_ready = relief.archive != null and bridge.node.mesh == relief.archive.entries.StrategicBasemap.mesh \
			and _satellite_ground._planes.size() == 1 \
			and bridge.node.position == Vector3(0, _satellite_ground.TACTICAL_SURFACE_LIFT, 0) \
			and bridge.material.shader == _satellite_ground.TACTICAL_OPAQUE_SHADER
		var bounds: AABB = bridge.node.mesh.get_aabb()
		native_rect = Rect2(bounds.position.x, bounds.position.z, bounds.size.x, bounds.size.z)
	var sprites: Dictionary = source._sprites.get(lod, {})
	for key: String in visible:
		var sprite_value: Variant = sprites.get(key)
		if typeof(sprite_value) != TYPE_OBJECT or not is_instance_valid(sprite_value) or not sprite_value is Sprite2D:
			unbound.append(key)
			continue
		var sprite: Sprite2D = sprite_value
		if native:
			var region := sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, Vector2(sprite.texture.get_size()))
			var tile_rect := Rect2(sprite.position, region.size * sprite.scale)
			# 原源矩形与1/256规范顶点有不足0.004的裁边舍入差，不扩大相机覆盖范围。
			if not bridge_ready or not native_rect.grow(0.004).encloses(tile_rect):
				unbound.append(key)
			continue
		var entry: Dictionary = _satellite_ground._planes.get(sprite.get_instance_id(), {})
		if entry.is_empty() or not is_instance_valid(entry.node) or not entry.node.visible:
			unbound.append(key)
	return {"current_lod": state.current_lod, "target_lod": state.target_lod, "transitioning": state.transitioning,
		"native_surface": native, "native_bounds": str(native_rect),
		"pending_count": state.pending_count, "resident_tiles": state.resident_tiles,
		"visible_keys": visible, "missing_keys": state.missing_keys, "missing_visible": missing_visible,
		"missing_prefetch": missing_prefetch, "unbound_visible_3d": unbound, "strategic_bridge_ready": bridge_ready}


static func render_sample_valid(primitives: int, draw_calls: int, global_calls: int) -> bool:
	return primitives > 0 and draw_calls > 0 and global_calls >= draw_calls
