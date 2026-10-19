extends RefCounted
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")
const Capture := preload("res://scripts/tests/tokyo_ao_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")


static func cancelled_loading(parent: Node) -> int:
	var tree := parent.get_tree()
	var fail := 0
	for explicit_cancel: bool in [false, true]:
		var loading := Node2D.new()
		parent.add_child(loading)
		var reference: WeakRef = Session.start(loading, Vector2(-5900,-1100), 0.65)
		var stream_ref: WeakRef
		var texture_ref: WeakRef
		var shore_refs: Array[WeakRef] = []
		var warm_ref: WeakRef
		var atlas_refs: Array[WeakRef] = []
		var pending := false
		var deadline := Time.get_ticks_msec() + 10000
		while reference != null and Time.get_ticks_msec() < deadline:
			var session: Variant = reference.get_ref()
			if typeof(session) != TYPE_OBJECT or not is_instance_valid(session):
				break
			if is_instance_valid(session.overlay) and session.overlay._stream.summary().pending > 0:
				pending = true
				stream_ref = weakref(session.overlay._stream)
				texture_ref = weakref(session.overlay._preloaded_ao._texture)
				var actual_ao: Dictionary = session.overlay._preloaded_ao.stats
				var expected := 20973096 if actual_ao.get("ao_encoding")=="bc4_unorm_mips" else 29361664
				if actual_ao.get("height_encoding")=="global_palette_r5_lsb":
					expected -= 4718592
					fail += int(actual_ao.get("height_size")!=2048 or actual_ao.get("height_storage_width")!=1280)
				if OS.get_environment("AGL_TOKYO_SHORELINE") != "":
					var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("AGL_TOKYO_SHORELINE").path_join("manifest.json")))
					var shore_bytes := 0
					for entry: Dictionary in manifest.meshes:
						shore_bytes += int(entry.faces)*3*64*3
					fail += int(session.overlay._shoreline.stats.reserved_bytes != shore_bytes)
					expected += shore_bytes
					# 暖绘视口退出树前仍持有512KiB；不能漏算，也不能照抄总预约放行。
					warm_ref = session.overlay._shoreline._material_warmup
					var warm_live: bool = warm_ref != null and warm_ref.get_ref() != null
					var warm_bytes := warmup_bytes(session.overlay._shoreline.stats.get("material_warmup", {}), warm_live)
					fail += int(warm_bytes < 0)
					expected += maxi(0, warm_bytes)
					for index in session.overlay._shoreline._meshes.size():
						shore_refs.append(weakref(session.overlay._shoreline._meshes[index]))
				if OS.get_environment("AGL_TOKYO_FIXED_ATLAS") != "":
					var atlas: RefCounted = session.overlay._fixed_atlas
					for member: RefCounted in atlas.members():
						var atlas_warm: WeakRef = member._warm
						var atlas_warm_live: bool = atlas_warm != null and atlas_warm.get_ref() != null
						var atlas_bytes := fixed_region_bytes(member._state,atlas_warm_live)
						fail += int(atlas_bytes < 0)
						expected += maxi(0, atlas_bytes)
						atlas_refs.append(weakref(member._texture))
						atlas_refs.append(weakref(member._node))
						if atlas_warm != null:
							atlas_refs.append(atlas_warm)
				fail += int(session.overlay._stream.summary().auxiliary_bytes != expected)
				print("[R140 AO cancel budget] actual=", session.overlay._stream.summary().auxiliary_bytes, " expected=", expected)
				if explicit_cancel:
					session.cancel()
					session.cancel()
				break
			await tree.process_frame
		loading.queue_free()
		deadline = Time.get_ticks_msec() + 10000
		while Time.get_ticks_msec() < deadline:
			await tree.process_frame
			if (reference == null or reference.get_ref() == null) and (stream_ref == null or stream_ref.get_ref() == null):
				break
		await tree.process_frame
		var released: bool = reference != null and reference.get_ref() == null and stream_ref != null \
			and stream_ref.get_ref() == null and texture_ref != null and texture_ref.get_ref() == null
		for index in shore_refs.size():
			released = released and shore_refs[index].get_ref() == null
		for atlas_reference: WeakRef in atlas_refs:
			released = released and atlas_reference.get_ref() == null
		released = released and (warm_ref == null or warm_ref.get_ref() == null)
		fail += int(not pending or not released)
		print("[R66 cancel] explicit=", explicit_cancel, " real_pending=", pending, " released=", released)
	var directory := OS.get_environment("AGL_TOKYO_AO_PRELOAD")
	OS.set_environment("AGL_TOKYO_AO_PRELOAD", directory.path_join("intentional_missing"))
	var missing_owner := Node2D.new()
	parent.add_child(missing_owner)
	var missing_ref: WeakRef = Session.start(missing_owner, Vector2(-5900,-1100), 0.65)
	for frame in 8:
		await tree.process_frame
	var rejected: bool = missing_ref != null and missing_ref.get_ref() == null
	fail += int(not rejected)
	missing_owner.queue_free()
	await tree.process_frame
	OS.set_environment("AGL_TOKYO_AO_PRELOAD", directory)
	print("[R66 missing AO] rejected_and_released=", rejected, " fail=", fail)
	return fail


static func run(battle: Node, map: Node, output: String) -> int:
	var tree := battle.get_tree()
	var paused := tree.paused
	var ignore: bool = battle.camera.ignore_rotation
	tree.paused = true
	battle.camera.ignore_rotation = false
	var layer: RefCounted = map._preloaded_ao
	var fixed_layer: RefCounted = map.get("_fixed_atlas")
	var bounds: Array = layer.stats.bounds
	var region := Rect2(float(bounds[0]),float(bounds[1]),float(bounds[2])-float(bounds[0]),float(bounds[3])-float(bounds[1]))
	var ids := [layer._texture.get_instance_id(), layer._height_texture.get_instance_id(), map._stream.get_instance_id()]
	var geometry := preload("res://scripts/tests/tokyo_static_shadow_review.gd").new()
	var collision := var_to_bytes(BuildingRenderer._cache_entries)
	var rows := []
	var fail := 0
	var shore_reservation := 0
	if OS.get_environment("AGL_TOKYO_SHORELINE")!="":
		var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(OS.get_environment("AGL_TOKYO_SHORELINE").path_join("manifest.json")))
		shore_reservation=shoreline_bytes(manifest) if manifest is Dictionary else -1
		if shore_reservation<0 or map._shoreline==null or map._shoreline.stats.reserved_bytes!=shore_reservation:
			tree.paused=paused
			battle.camera.ignore_rotation=ignore
			return 1
	var cold_poses := OS.get_environment("AGL_TOKYO_AO_COLD_POSES")=="1"
	var source: Node = battle._map_features._raster_basemap
	var source_mode: int = source.process_mode
	# 观察场暂停战斗但让瓦片完成真实淡入，不能用上一镜头ready做AO对拍。
	source.process_mode=Node.PROCESS_MODE_ALWAYS
	var readiness := preload("res://scripts/tests/tokyo_canonical_review.gd")
	var poses: Array[Vector2] = [Vector2(0.65,0), Vector2(0.98,0), Vector2(1.3,0), Vector2(1.95,0), Vector2(2.4,0), Vector2(2.4,-14), Vector2(2.4,14), Vector2(5,0), Vector2(0.65,0)]
	if fixed_layer != null:
		poses.push_front(Vector2(0.4,0))
		poses.append(Vector2(0.4,0))
	for pose: Vector2 in poses:
		# 独立静态对拍诊断：明确清空上个切面，不可冒充连续LOD验收。
		if cold_poses:
			map.set_enabled(false)
			var drain_deadline := Time.get_ticks_msec()+15000
			while (map._stream.summary().bytes>0 or map._stream.summary().pending>0 or map._stream.summary().reserved_bytes>0) and Time.get_ticks_msec()<drain_deadline:
				await tree.process_frame
			if map._stream.summary().bytes>0 or map._stream.summary().pending>0 or map._stream.summary().reserved_bytes>0:
				fail+=1
				rows.append({"pose":str(pose),"rejected":true,"reason":"cold geometry drain failed","state":map.debug_state()})
				break
		battle.camera.position = region.get_center()
		battle.camera.zoom = Vector2.ONE * pose.x
		battle.camera.rotation = deg_to_rad(pose.y)
		battle.camera.force_update_scroll()
		if cold_poses:
			map.set_enabled(true)
		var deadline := Time.get_ticks_msec() + 15000
		var stable_since := 0
		var settled := false
		while Time.get_ticks_msec() < deadline:
			await RenderingServer.frame_post_draw
			if readiness.ready_at_canvas(map._last_canvas,battle.get_viewport().get_canvas_transform(),map.debug_state()) and readiness.source_ready(source):
				if stable_since==0:
					stable_since=Time.get_ticks_msec()
				if Time.get_ticks_msec()-stable_since>=200:
					settled=true
					break
			else:
				stable_since=0
		var state: Dictionary = map.debug_state()
		if not settled:
			if OS.get_environment("AGL_TOKYO_CUT_CAPACITY_PROBE")=="1":
				preload("res://scripts/tests/tokyo_cut_capacity_probe.gd").run(map,output)
			fail += 1
			rows.append({"pose": str(pose), "rejected": true, "state": state})
			break
		map.set_process(false)
		var before := geometry._geometry_state(map)
		var stem := output.path_join("r66_ao_%02d" % rows.size())
		layer.strength(0.0)
		var atlas_material: ShaderMaterial = fixed_layer._node.material_override if fixed_layer != null else null
		if atlas_material != null:
			fail += int(not is_zero_approx(float(atlas_material.get_shader_parameter("ao_strength"))))
		var zero := await Capture._capture(battle, map, stem+"_zero")
		layer.strength(0.25)
		await Capture._capture(battle, map, stem+"_ao25")
		layer.strength(0.45)
		var first := await Capture._capture(battle, map, stem+"_ao45")
		var repeated := await Capture._capture(battle, map, stem+"_repeat")
		layer.strength(0.65)
		if atlas_material != null:
			fail += int(not is_equal_approx(float(atlas_material.get_shader_parameter("ao_strength")), 0.65))
		await Capture._capture(battle, map, stem+"_ao65")
		layer.strength(0.0)
		var restored := await Capture._capture(battle, map, stem+"_restored")
		var restore_error := Pixels._pixel_error(zero,restored)
		layer.strength(0.45)
		# 同一已冻结切面隔离图块接收AO差异；不能拿首尾不同LOD作画质对照。
		var native_atlas_pair := fixed_layer != null and bool(fixed_layer.stats.get("applied",false))
		if native_atlas_pair:
			fixed_layer.suspend()
			layer.strength(0.0)
			await Capture._capture(battle,map,stem+"_native_ground_zero")
			layer.strength(0.45)
			await Capture._capture(battle,map,stem+"_native_ground_ao45")
			fixed_layer.update(map,float(state.output_scale),bool(state.active))
			fail += int(not fixed_layer.stats.get("applied",false))
		var unchanged: bool = before == geometry._geometry_state(map) and collision == var_to_bytes(BuildingRenderer._cache_entries)
		var same_ids: bool = ids == [layer._texture.get_instance_id(), layer._height_texture.get_instance_id(), map._stream.get_instance_id()]
		fail += int(not unchanged or not same_ids or state.stream.peak_total_bytes > 96*1024*1024)
		var expected_auxiliary := int(layer.stats.conservative_bytes)+(128*1024 if state.get("projected_source_reserved",false) else 0)+shore_reservation
		if fixed_layer != null:
			var atlas_bytes := fixed_atlas_bytes(state.get("fixed_atlas",{}), false)
			fail += int(atlas_bytes < 0)
			expected_auxiliary += maxi(0, atlas_bytes)
		fail += int(int(state.stream.auxiliary_bytes) != expected_auxiliary or float(state.output_scale) > float(layer.stats.max_scale) or restore_error>1)
		rows.append({"pose": str(pose), "state": state, "settled":settled,"source_state":source.debug_state(),"same_resources": same_ids, "geometry_collision_unchanged": unchanged,
			"allowed_screen_bounds": Pixels._screen_bounds(map, [{"original": [[region.position.x,region.position.y],[region.end.x,region.position.y],[region.end.x,region.end.y],[region.position.x,region.end.y]], "candidate": [], "height_px": map._source_max_height}]),
			"variants":["ao25","ao45","ao65"],"restore_max":restore_error,"region":bounds,"native_atlas_pair":native_atlas_pair,
			"repeat_max": Pixels._pixel_error(first, repeated), "stem": stem})
		map._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		map.set_process(true)
		print("[R66 AO preload] pose=", pose, " total_peak=", state.stream.peak_total_bytes, " same_resources=", same_ids)
	tree.paused = paused
	source.process_mode=source_mode
	battle.camera.ignore_rotation = ignore
	var file := FileAccess.open(output.path_join("r66_ao_preload_review.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows": rows, "fail": fail, "fps_evidence": false,"cold_poses":cold_poses,"continuous_lod_evidence":not cold_poses}, "\t"))
	file.close()
	return fail


static func fixed_atlas_bytes(state: Dictionary, warm_live: bool) -> int:
	if state.get("regions") is Dictionary and state.regions.size()>1:
		if state.regions.keys().size()!=6 or warm_live:
			return -1
		var total := 0
		for parent: String in ["11","0","1","3","12","13"]:
			if not state.regions.get(parent) is Dictionary:
				return -1
			var amount := fixed_region_bytes(state.regions[parent],false)
			if amount<0:
				return -1
			total+=amount
		return total if state.get("reserved_bytes")==total else -1
	var single_step: Variant = state.get("texture_step",2)
	if typeof(single_step) not in [TYPE_INT,TYPE_FLOAT] or single_step not in [1,2]:
		return -1
	if single_step==1:
		return fixed_region_bytes(state,warm_live)
	# 独立按已审824×504 BC3全mip三份与单quad计费，不复用被测层常量。
	if state.get("ready") != true or state.get("reserved_bytes") != 1668112:
		return -1
	var warm_bytes := warmup_bytes(state.get("warm", {}), warm_live)
	return 1668112 + warm_bytes if warm_bytes >= 0 else -1


static func fixed_region_bytes(state: Dictionary, warm_live: bool) -> int:
	var charges := {11:1668112,0:190912,1:276784,3:304000,12:983632,13:594928}
	var parent: Variant = state.get("parent")
	if not typeof(parent) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(parent)) or parent!=int(parent) or not charges.has(int(parent)):
		return -1
	var amount: int = charges[int(parent)]
	var step: Variant = state.get("texture_step",2)
	if typeof(step) not in [TYPE_INT,TYPE_FLOAT] or step not in [1,2]:
		return -1
	if step==1:
		if int(parent)!=11 or state.get("catalog_sha256")!="c0311651371c29025b8db0a8618adb57a2faeb39ab59c4751ee743b3d9c346ca":
			return -1
		amount=6619840
	if state.get("ready")!=true or state.get("reserved_bytes")!=amount:
		return -1
	var warm_bytes := warmup_bytes(state.get("warm",{}),warm_live)
	return amount+warm_bytes if warm_bytes>=0 else -1


static func warmup_bytes(state: Dictionary, live: bool) -> int:
	# 独立生命周期预算反例：活视口定额、退出归零，未知状态和少计均拒绝。
	var expected := 512 * 1024 if live else 0
	for field: String in ["peak_reserved_bytes", "reserved_bytes"]:
		var amount: Variant = state.get(field)
		if typeof(amount) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(amount)):
			return -1
	if state.get("state", "") not in ["pending", "ready", "headless_skipped"] or state.peak_reserved_bytes != 512 * 1024 or state.reserved_bytes != expected:
		return -1
	if state.state == "pending" and not live:
		return -1
	return expected


static func shoreline_bytes(manifest: Dictionary) -> int:
	# 独立按原生清单三/四网格上界计算；不能直接采用被测Stream额度。
	var meshes: Variant = manifest.get("meshes")
	var schema: Variant = manifest.get("schema",1)
	if not typeof(schema) in [TYPE_INT,TYPE_FLOAT] or not (schema==1 or schema==2) or not meshes is Array or meshes.size()!=(4 if schema==2 else 3):
		return -1
	var total := 0
	for row: Variant in meshes:
		if not row is Dictionary:
			return -1
		var faces: Variant = row.get("faces")
		if not typeof(faces) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(faces)) or faces<=0 or faces!=int(faces):
			return -1
		total+=int(faces)*3*64*3
	if schema==2 and manifest.get("reserved_bytes",-1)!=total:
		return -1
	return total if total<=6*1024*1024 else -1
