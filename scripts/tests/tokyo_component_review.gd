extends RefCounted
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")
const Meshes := preload("res://scripts/tests/build_tokyo_shared_pages.gd")


static func run(battle: Node, map: Node, output: String) -> int:
	var tree := battle.get_tree()
	var paused := tree.paused
	var ignore: bool = battle.camera.ignore_rotation
	tree.paused = true
	battle.camera.ignore_rotation = false
	var token := RefCounted.new()
	var collision := var_to_bytes(BuildingRenderer._cache_entries)
	var rows: Array = []
	var fail := 0
	var compared := 0
	var wall_review := OS.get_environment("AGL_TOKYO_LOW_WALL_REVIEW") == "1"
	# 完整网格守恒对照与自动渐隐对照分开；不能拿隐藏墙图要求逐像素等于完整原图。
	if wall_review:
		map.set_low_wall_full_override(true)
	for pose: Vector2 in [Vector2(0.20, 0), Vector2(0.26, 0), Vector2(0.35, 0), Vector2(0.26, -14), Vector2(0.26, 14), Vector2(5, 0), Vector2(0.26, 0)]:
		battle.camera.position = Vector2(-5600, -2900)
		if wall_review:
			battle.camera.position = Vector2(-6675,-2325)
		if OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_REVIEW")=="1":
			battle.camera.position = Vector2(-6196,-2548)
		battle.camera.zoom = Vector2.ONE * pose.x
		battle.camera.rotation = deg_to_rad(pose.y)
		battle.camera.force_update_scroll()
		await tree.create_timer(0.3).timeout
		var deadline := Time.get_ticks_msec() + 15000
		while not Session.state_ready(map.debug_state()) and Time.get_ticks_msec() < deadline:
			await tree.process_frame
		var state: Dictionary = map.debug_state()
		if not Session.state_ready(state):
			rows.append({"pose": str(pose), "rejected": "incomplete cut", "state": state})
			fail += 1
			break
		map.set_process(false)
		var checks := 0
		for key: Variant in map._batches:
			var batch: Dictionary = map._batches[key]
			if wall_review and not batch.has("low_wall_node"):
				continue
			if not map._descriptors[batch.path].has("components") or checks >= 3:
				continue
			var bytes := int(map._descriptors[batch.path].bytes)
			# 对照确实加载一份原三层页；领取前预留额，恢复节点并释放后归还。
			if not map._stream.reserve_auxiliary(token.get_instance_id(), bytes):
				rows.append({"pose": str(pose), "rejected": "comparison memory", "state": state})
				fail += 1
				break
			var original: Resource = ResourceLoader.load(batch.path, "", ResourceLoader.CACHE_MODE_IGNORE)
			if original == null or not original.valid() or original.stream_identity() != batch.building.stream_identity():
				original = null
				map._stream.release_auxiliary(token.get_instance_id())
				fail += 1
				break
			var saved: Array[ArrayMesh] = []
			var exact := true
			for kind in 3:
				saved.append(batch.nodes[kind].mesh)
				if kind == 0 and batch.has("low_wall_node"):
					exact = exact and preload("res://scripts/experiments/tokyo_packed_mesh_join.gd").conserved(original.meshes[0],[saved[0],batch.low_wall_node.mesh])
				else:
					exact = exact and Meshes.same_mesh(saved[kind], original.meshes[kind])
			var stem := output.path_join("r69_component_%02d" % compared)
			var current := await Capture._capture(battle, map, stem + "_component")
			for kind in 3:
				batch.nodes[kind].mesh = original.meshes[kind]
			if batch.has("low_wall_node"):
				batch.low_wall_node.hide()
			var reference := await Capture._capture(battle, map, stem + "_original")
			for kind in 3:
				batch.nodes[kind].mesh = saved[kind]
			if batch.has("low_wall_node"):
				batch.low_wall_node.show()
			var restored := await Capture._capture(battle, map, stem + "_restored")
			original = null
			map._stream.release_auxiliary(token.get_instance_id())
			var delta := Pixels._pixel_error(current, reference)
			var restore_delta := Pixels._pixel_error(current, restored)
			fail += int(not exact or delta > 1 or restore_delta > 1 or collision != var_to_bytes(BuildingRenderer._cache_entries))
			rows.append({"pose": str(pose), "path": batch.path, "stem": stem, "arrays_exact": exact,"low_wall_pair":batch.has("low_wall_node"),
				"pixel_error": delta, "restore_error": restore_delta, "state": state, "peak_total_bytes": map._stream.summary().peak_total_bytes})
			compared += 1
			checks += 1
		if checks == 0:
			fail += int(wall_review)
			await Capture._capture(battle, map, output.path_join("r69_component_transition_%02d" % rows.size()))
			rows.append({"pose": str(pose), "non_component_level": true, "state": state})
		map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		map.set_process(true)
		print("[R69 component Visual] pose=", pose, " comparisons=", checks, " fail=", fail)
	tree.paused = paused
	if wall_review:
		map.set_low_wall_full_override(false)
	battle.camera.ignore_rotation = ignore
	fail += int(compared < (7 if wall_review else 9))
	var file := FileAccess.open(output.path_join("r69_component_review.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "fail": fail, "compared": compared, "fps_evidence": false}, "\t"))
	file.close()
	return fail
