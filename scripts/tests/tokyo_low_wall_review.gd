extends RefCounted
## 实际地图单份低墙LOD；固定对拍与连续运动单列，不以截图耗时冒充性能。
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")
const Binding := preload("res://scripts/rendering/tokyo_low_wall_binding.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")


static func run(battle: Node, map: Node, output: String) -> int:
	var tree := battle.get_tree()
	var paused := tree.paused
	var ignore: bool = battle.camera.ignore_rotation
	var source: RasterBasemapRenderer = battle._map_features._raster_basemap
	var source_mode := source.process_mode
	var source_processing := source.is_processing()
	tree.paused = true
	source.process_mode = Node.PROCESS_MODE_ALWAYS
	battle.camera.ignore_rotation = false
	var collision := var_to_bytes(BuildingRenderer._cache_entries)
	var fail := 0
	var rows: Array[Dictionary] = []
	var endpoints := {"hidden":0,"fade":0,"full":0}
	for zoom_value: float in [0.26,0.48,0.65,0.98,2.2]:
		battle.camera.position = Vector2(-6196,-2548) if OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_REVIEW")=="1" else Vector2(-6675,-2325)
		if OS.get_environment("AGL_TOKYO_NORTHWEST_REVIEW")=="1":
			battle.camera.position=Vector2(-6755,-3200)
			if OS.get_environment("AGL_TOKYO_NORTHWEST_WEST_REVIEW")=="1":
				battle.camera.position=Vector2(-7140,-3200)
		battle.camera.zoom = Vector2.ONE * zoom_value
		battle.camera.rotation = 0.0
		battle.camera.force_update_scroll()
		await tree.create_timer(0.4).timeout
		var source_ready := await preload("res://scripts/tests/tokyo_tile_ground_review.gd")._wait_source(source,tree)
		var deadline := Time.get_ticks_msec()+15000
		while not Session.state_ready(map.debug_state()) and Time.get_ticks_msec()<deadline:
			await tree.process_frame
		if not source_ready or not Session.state_ready(map.debug_state()):
			fail += 1
			break
		map.set_process(false)
		source.set_process(false)
		var automatic: Dictionary = map.debug_state()
		var stem := output.path_join("r188_wall_%02d" % rows.size())
		var candidate := await Capture._capture(battle,map,stem+"_auto")
		if zoom_value==2.2 and OS.get_environment("AGL_TOKYO_COVERAGE_GAP_PROBE")=="1":
			fail += preload("res://scripts/tests/tokyo_coverage_gap_probe.gd").run(map,candidate,output.path_join("r194_coverage_gap.json"))
		map.set_low_wall_full_override(true)
		var full_state: Dictionary = map.debug_state()
		var reference := await Capture._capture(battle,map,stem+"_full")
		map.set_low_wall_full_override(false)
		var restored := await Capture._capture(battle,map,stem+"_restored")
		var mix_value := float(automatic.low_wall_mix)
		var mode := "hidden" if mix_value == 1.0 else ("full" if mix_value == 0.0 else "fade")
		endpoints[mode] += 1
		var saved_faces := int(full_state.triangles)-int(automatic.triangles)
		var expected_saved := int(full_state.low_wall_faces) if mode == "hidden" else 0
		var error := Pixels._pixel_error(candidate,reference)
		var restore_error := Pixels._pixel_error(candidate,restored)
		fail += int(saved_faces != expected_saved or int(full_state.resident_triangles) != int(automatic.resident_triangles))
		fail += int(restore_error > 1 or (mode == "full" and error > 1))
		rows.append({"zoom":zoom_value,"mode":mode,"state":automatic,"full":full_state,"saved_faces":saved_faces,"source":source.debug_state(),
			"pixel_error":error,"restore_error":restore_error,"stem":stem})
		map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		map.set_process(true)
		source.set_process(source_processing)
	var probe := preload("res://scripts/tests/tokyo_draw_geometry_probe.gd").new()
	# 底图detail退出阈值为zoom0.20；旧0.26下限根本不触发底图切档。
	battle.camera.zoom = Vector2.ONE*0.13
	battle.camera.force_update_scroll()
	await tree.create_timer(0.5).timeout
	fail += int(not await preload("res://scripts/tests/tokyo_tile_ground_review.gd")._wait_source(source,tree))
	fail += int(not probe.setup(map))
	var samples := 0
	var mismatches := 0
	var motion_modes := {"hidden":0,"fade":0,"full":0}
	var source_modes: Dictionary = {}
	var source_transitions := 0
	var invalid_borrow := 0
	var source_capacity := {"samples":0,"peak_committed":0,"violations":0}
	var observe_capacity := func() -> void:
		var committed: int = source.resident_tile_count()+source._pending.size()
		source_capacity.samples += 1
		source_capacity.peak_committed = maxi(source_capacity.peak_committed,committed)
		source_capacity.violations += int(committed>RasterBasemapRenderer.HARD_RESIDENT_TILES)
	RenderingServer.frame_post_draw.connect(observe_capacity)
	# 两次近远往返，逐真实draw验墙节点/原生索引；不插入参考图或暂停地图更新。
	for frame in 192:
		var phase := float(frame % 96)/95.0
		var amount := sin(phase*PI)
		battle.camera.zoom = Vector2.ONE*lerpf(0.13,1.4,amount)
		battle.camera.rotation = deg_to_rad(45.0*sin(phase*TAU))
		var center := Vector2(-6196,-2548) if OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_REVIEW")=="1" else Vector2(-6675,-2325)
		if OS.get_environment("AGL_TOKYO_NORTHWEST_REVIEW")=="1":
			center=Vector2(-6755,-3200)
			if OS.get_environment("AGL_TOKYO_NORTHWEST_WEST_REVIEW")=="1":
				center=Vector2(-7140,-3200)
		battle.camera.position = center+Vector2(50.0*sin(phase*TAU),30.0*amount)
		battle.camera.force_update_scroll()
		await tree.create_timer(0.02).timeout
		await RenderingServer.frame_post_draw
		source_modes[String(source._current_lod)] = true
		source_transitions += int(source._transitioning)
		if map._tile_ground != null:
			invalid_borrow += int(source._transitioning or not preload("res://scripts/experiments/tokyo_tile_ground_candidate.gd").texture_resolved(map._tile_ground.source_step,map._low_wall_scale))
		var mix_value: float = map._low_wall_mix
		mismatches += int(not is_equal_approx(mix_value,Binding.fade_for_scale(map._low_wall_scale)))
		motion_modes["hidden" if mix_value == 1.0 else ("full" if mix_value == 0.0 else "fade")] += 1
		for batch: Dictionary in map._batches.values():
			if not batch.has("low_wall_node"):
				continue
			var actual := Indexed.triangles(batch.nodes[0].mesh)
			if batch.low_wall_node.visible:
				actual += Indexed.triangles(batch.low_wall_node.mesh)
			mismatches += int(actual != batch.layer_triangles[0] or batch.low_wall_node.visible != (mix_value < 1.0))
			samples += 1
	probe.close()
	RenderingServer.frame_post_draw.disconnect(observe_capacity)
	var geometry: Dictionary = probe.summary()
	fail += int(samples == 0 or mismatches > 0 or geometry.get("runtime_underreported",-1) != 0)
	fail += int(not source_processing or source_modes.size()<2 or source_transitions == 0 or invalid_borrow > 0)
	fail += int(source_capacity.samples == 0 or source_capacity.violations > 0 or source._peak_committed_tiles>16)
	for mode: String in motion_modes:
		fail += int(motion_modes[mode] == 0 or endpoints[mode] == 0)
	fail += int(collision != var_to_bytes(BuildingRenderer._cache_entries))
	tree.paused = paused
	source.set_process(source_processing)
	source.process_mode = source_mode
	battle.camera.ignore_rotation = ignore
	var file := FileAccess.open(output.path_join("r188_wall_review.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":rows,"motion_frames":192,"motion_modes":motion_modes,"samples":samples,
		"mismatches":mismatches,"geometry":geometry,"source_processing":source_processing,"source_modes":source_modes,
		"source_transition_frames":source_transitions,"invalid_borrow":invalid_borrow,"source_capacity":source_capacity,
		"source_peak_committed":source._peak_committed_tiles,"source_capacity_deferrals":source._capacity_deferrals,"fail":fail,"fps_evidence":false},"\t"))
	file.close()
	print("[R188 wall review] samples=",samples," modes=",motion_modes," fail=",fail)
	return fail
