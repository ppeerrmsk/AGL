extends RefCounted
## 实际Survivor相机分区复查；不替换网格或伪造旧楼屏蔽清单。
const Session := preload("res://scripts/rendering/tokyo_volume_preload.gd")


static func run(battle: Node, map: Node, output: String) -> int:
	var nine_seams := OS.get_environment("AGL_TOKYO_NINE_SEAMS_REVIEW")=="1"
	var south_review := OS.get_environment("AGL_TOKYO_SOUTH_SEAMS_REVIEW")=="1"
	var southwest_review := OS.get_environment("AGL_TOKYO_SOUTHWEST_SEAMS_REVIEW")=="1"
	if southwest_review and (not south_review or not nine_seams):
		return 1
	if south_review and not nine_seams:
		return 1
	var review_sha := "167ef74c4d1a9b5c3dfdf3fe929473e6f67d6917c4d0bcf71accd0836ab71026" if south_review else "90d2378a4f480b9c97609038ac7913fd6f3f6b5f816d9ebe36bd935f88000fab"
	var review_coverage := "r299-near-coverage-a/coverage-" if south_review else "r276-near-coverage-a/coverage-"
	if southwest_review:
		review_sha="22a0c03939f61d6f15fc800a7c676d411cbee72c30806dd4f6fe98c92ef5fd30"
		review_coverage="r313-near-coverage-a/coverage-"
	if OS.get_environment("AGL_TOKYO_SOUTHWEST_RAIL_REVIEW") == "1":
		if not southwest_review:
			return 1
		review_sha="6417741a437cf3cca86fc2493491dd881f1f92f46b0c8c22054fe9861e31193b"
		review_coverage="r324-southwest-rail-catalog-a/coverage-"
	if OS.get_environment("AGL_TOKYO_ROAD_MESHOPT_REVIEW") == "1":
		if not southwest_review or OS.get_environment("AGL_TOKYO_SOUTHWEST_RAIL_REVIEW") != "1":
			return 1
		review_sha="437cd67e10cc7d44a1551f17dd27c9970c7c6f5f30d8ee7d70fb4f3e9ecb4fa2"
		review_coverage="r337-road-catalog-b/coverage-"
	if nine_seams and (OS.get_environment("AGL_TOKYO_RESIDENTIAL_REVIEW")!="1" or FileAccess.get_sha256(OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG"))!=review_sha or not OS.get_environment("AGL_TOKYO_COVERAGE_PREFIX").ends_with(review_coverage)):
		return 1
	var left_seams := OS.get_environment("AGL_TOKYO_LEFT_SEAMS_REVIEW")=="1"
	if left_seams and (OS.get_environment("AGL_TOKYO_RESIDENTIAL_REVIEW")!="1" or FileAccess.get_sha256(OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG"))!="c59753a8ac3779a30ed117cb817ef0861ef262b71db8114227a06bea01039b06"):
		return 1
	var tree := battle.get_tree()
	var paused := tree.paused
	var ignore: bool = battle.camera.ignore_rotation
	var signature := var_to_bytes(BuildingRenderer._cache_entries)
	var bounded_review := OS.get_environment("AGL_TOKYO_BOUNDED_LEGACY_REVIEW")=="1"
	var prior_bounded := false
	var prior_shadow_cache := false
	var prior_legacy_mode := Node.PROCESS_MODE_INHERIT
	if bounded_review:
		var legacy: Variant = battle.get("_building_renderer")
		if typeof(legacy)!=TYPE_OBJECT or not is_instance_valid(legacy) or not legacy is BuildingRenderer:
			return 1
		prior_bounded=legacy.bounded_roof_projection
		prior_legacy_mode=legacy.process_mode
		legacy.process_mode=Node.PROCESS_MODE_ALWAYS
		prior_shadow_cache=legacy.cache_shadow_geometry
		legacy.cache_shadow_geometry=OS.get_environment("AGL_TOKYO_SHADOW_CACHE_REVIEW")=="1"
		battle._building_renderer.bounded_roof_projection=true
		battle._building_renderer.queue_redraw()
	var rows: Array[Dictionary] = []
	var fail := 0
	tree.paused = true
	battle.camera.ignore_rotation = false
	var poses := [Vector3(0.65, 0, 0), Vector3(0.98, 0, 0), Vector3(1.3, 0, 0), Vector3(1.95, 0, 0),
		Vector3(0.98, -14, 0), Vector3(0.98, 14, 0)]
	var regional := OS.get_environment("AGL_TOKYO_REGIONAL_REVIEW")=="1"
	var corridor := OS.get_environment("AGL_TOKYO_EXTENSION_REVIEW")=="1"
	var street := corridor and OS.get_environment("AGL_TOKYO_STREET_REVIEW")=="1"
	var guarded := OS.get_environment("AGL_TOKYO_GUARDED_REVIEW")=="1" or corridor
	var source: Node = battle._map_features._raster_basemap
	var source_mode: int = source.process_mode
	if guarded:
		source.process_mode=Node.PROCESS_MODE_ALWAYS
	if regional:
		poses=[Vector3(0.13,0,0),Vector3(0.52,0,0),Vector3(0.98,0,0),Vector3(2.2,0,0),Vector3(5,0,0),
			Vector3(0.52,0,1),Vector3(0.98,14,1),Vector3(2.2,0,1),Vector3(0.98,0,2)]
	if guarded:
		poses=[Vector3(.13,0,0),Vector3(.26,0,0),Vector3(.52,0,0),Vector3(.98,0,0),Vector3(2.2,0,0),Vector3(5,0,0),
			Vector3(.13,0,1),Vector3(.26,0,1),Vector3(5,14,1)]
	if corridor:
		poses=[Vector3(.13,0,0),Vector3(.26,0,0),Vector3(.52,0,0),Vector3(.98,0,0),Vector3(2.2,0,0),Vector3(5,0,0),
			Vector3(.98,14,1),Vector3(2.2,0,1),Vector3(5,0,1),Vector3(.98,0,2),Vector3(.98,0,3)]
	if street:
		# 保留原西区路线，追加实际北岸远/近及旋转接缝，再回总览；不替换旧失败机位。
		poses.append_array([Vector3(.26,0,4),Vector3(.4,0,4),Vector3(.98,0,4),Vector3(5,0,4),Vector3(.26,14,5),Vector3(.13,0,0)])
	var reversal := street and OS.get_environment("AGL_TOKYO_REUSE_REVERSAL_REVIEW")=="1"
	if reversal:
		# 两组均追加同序机位，覆盖复用后的突然放大、缩回、跨区及再次放大。
		poses.append_array([Vector3(5,0,0),Vector3(.13,0,0),Vector3(.13,14,5),Vector3(5,14,5)])
	if street and OS.get_environment("AGL_TOKYO_NEAR_DOMINANCE_REVIEW")=="1":
		# 原21位只命中mid/近档，另加真实full4范围，不能用未触发分支的截图验收。
		poses.append_array([Vector3(1.2,0,4),Vector3(1.5,0,4),Vector3(1.85,0,4),Vector3(1.2,14,4),Vector3(1.2,14,5),Vector3(.13,0,0)])
	var fixed_set := corridor and OS.get_environment("AGL_TOKYO_FIXED_SET_REVIEW")=="1"
	var rail_review := OS.get_environment("AGL_TOKYO_RAIL_REVIEW")=="1"
	var residential := OS.get_environment("AGL_TOKYO_RESIDENTIAL_REVIEW")=="1"
	if fixed_set:
		# 保留历史27位，追加五区远景/旋转/近景，再检父11/12接缝和返回。
		for region in range(6,11):
			poses.append_array([Vector3(.26,0,region),Vector3(.4,14,region),Vector3(.98,0,region)])
		poses.append_array([Vector3(.4,-14,11),Vector3(.4,14,11),Vector3(.13,0,0)])
	if rail_review:
		# 独立单片同位审图，不代替历史连续路线或性能证据。
		poses = [Vector3(.26,0,0),Vector3(.4,0,0),Vector3(.52,0,0),Vector3(.98,0,0),Vector3(2.2,0,0),Vector3(.98,14,0),Vector3(.26,0,0)]
	if residential:
		# 已认可住宅核心：独立分档审图，不替代连续镜头与性能巡检。
		poses=[Vector3(.13,0,0),Vector3(.26,0,0),Vector3(.52,0,0),Vector3(.98,0,0),Vector3(2.2,0,0),Vector3(5,0,0),Vector3(.98,14,0),Vector3(.26,0,0)]
	if left_seams:
		# 保留原八机位，再追加南/东共边与突放大、缩回；静态逐站检查不冒称连续视频。
		for seam in 2:
			poses.append_array([Vector3(.52,0,seam),Vector3(.98,0,seam),Vector3(1.5,14,seam),Vector3(5,-14,seam),Vector3(.26,14,seam),Vector3(2.2,0,seam),Vector3(5,14,seam),Vector3(.52,0,seam)])
	if nine_seams:
		# 保留原八位，补右翼核心、西/南共边与左翼两处共边；只证明静态逐站画面。
		for seam in 5:
			poses.append_array([Vector3(.52,0,seam),Vector3(.98,0,seam),Vector3(2.2,14,seam),Vector3(5,-14,seam)])
	if south_review:
		# 保留九区原28机位，追加南侧新合并区六档；不冒称连续运动验收。
		poses.append_array([Vector3(.26,0,0),Vector3(.52,0,0),Vector3(.98,0,0),Vector3(2.2,14,0),Vector3(5,-14,0),Vector3(.26,0,0)])
	if southwest_review:
		poses.append_array([Vector3(.26,0,0),Vector3(.52,0,0),Vector3(.98,0,0),Vector3(2.2,14,0),Vector3(5,-14,0),Vector3(.26,0,0)])
		for seam in [1,2]:
			poses.append_array([Vector3(.52,0,seam),Vector3(.98,0,seam),Vector3(2.2,14,seam),Vector3(5,-14,seam)])
	for index in poses.size():
		var pose: Vector3 = poses[index]
		battle.camera.position = Vector2(-5800, -1025)
		if rail_review:
			battle.camera.position = Vector2(-5660,-2200) if OS.get_environment("AGL_TOKYO_RAIL_SEAM_REVIEW")=="1" else Vector2(-5180,-2200)
		if regional and not corridor:
			battle.camera.position=[Vector2(-6550,-2200),Vector2(-6300,-2200),Vector2(-6300,-1700)][int(pose.z)]
		if guarded and not corridor and not nine_seams:
			battle.camera.position=[Vector2(-5800,-2000),Vector2(-6550,-2200)][int(pose.z)]
		if corridor:
			battle.camera.position=[Vector2(-7050,-2200),Vector2(-6800,-2200),Vector2(-6550,-2200),Vector2(-7050,-1800),Vector2(-5600,-2900),Vector2(-5300,-1700),Vector2(-6120,-352.5),Vector2(-5260,-330),Vector2(-6100,-1342.5),Vector2(-5180,-2200),Vector2(-4220,-3400),Vector2(-5660,-2200)][int(pose.z)]
		if residential:
			battle.camera.position=Vector2(-6130,-2195)
			if OS.get_environment("AGL_TOKYO_RESIDENTIAL_WEST_REVIEW")=="1":
				battle.camera.position=Vector2(-6675,-2325)
			if OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_REVIEW")=="1":
				battle.camera.position=Vector2(-6196,-2548)
			if OS.get_environment("AGL_TOKYO_NORTHWEST_REVIEW")=="1":
				battle.camera.position=Vector2(-6755,-3200)
				if OS.get_environment("AGL_TOKYO_NORTHWEST_WEST_REVIEW")=="1":
					battle.camera.position=Vector2(-7140,-3200)
				if OS.get_environment("AGL_TOKYO_NORTHWEST_EAST_REVIEW")=="1":
					battle.camera.position=Vector2(-6415,-3200)
				if OS.get_environment("AGL_TOKYO_NORTHWEST_OUTER_REVIEW")=="1":
					battle.camera.position=Vector2(-7300,-3520)
		if left_seams and index>=8:
			battle.camera.position=[Vector2(-8050,-3700),Vector2(-7800,-4200)][int(pose.z)]
		battle.camera.zoom = Vector2.ONE * pose.x
		if nine_seams and index>=8:
			battle.camera.position=[Vector2(-6550,-4390),Vector2(-6800,-4200),Vector2(-6550,-3700),Vector2(-8050,-3700),Vector2(-7800,-4200)][int(pose.z)]
		battle.camera.rotation = deg_to_rad(pose.y)
		if south_review and index>=28:
			battle.camera.position=Vector2(-6760,-2870)
		if southwest_review and index>=34:
			battle.camera.position=[Vector2(-7800,-2200),Vector2(-7800,-2700),Vector2(-7300,-2200)][int(pose.z)]
		battle.camera.force_update_scroll()
		var deadline := Time.get_ticks_msec() + 15000
		var stable_since := 0
		var settled := false
		var first_image: Image
		var first_state: Dictionary = {}
		while Time.get_ticks_msec()<deadline:
			await RenderingServer.frame_post_draw
			if guarded and first_image==null and map._last_canvas.is_equal_approx(battle.get_viewport().get_canvas_transform()):
				first_image=map._viewport.get_texture().get_image()
				first_state=map.debug_state()
			if ready_at_canvas(map._last_canvas,battle.get_viewport().get_canvas_transform(),map.debug_state()) and (not guarded or source_ready(source)):
				if stable_since==0:
					stable_since=Time.get_ticks_msec()
				if Time.get_ticks_msec()-stable_since>=200:
					settled=true
					break
			else:
				stable_since=0
		var state: Dictionary = map.debug_state()
		if bounded_review and OS.get_environment("AGL_TOKYO_SHADOW_CACHE_REVIEW")=="1":
			var renderer: BuildingRenderer = battle._building_renderer
			var cached_bytes := var_to_bytes(renderer._shadow_packet)
			var selected: Array = []
			for source_id: int in renderer._shadow_sources:
				selected.append({"d":renderer._districts[source_id]})
			var selected_ids := renderer._shadow_sources.duplicate()
			var builds_before := renderer.shadow_cache_builds
			var reused := var_to_bytes(renderer.shadow_packet(selected,selected_ids))==cached_bytes and renderer.shadow_cache_builds==builds_before
			renderer.cache_shadow_geometry=false
			var equal_arrays := var_to_bytes(renderer.shadow_packet(selected,selected_ids))==cached_bytes
			renderer.cache_shadow_geometry=true
			renderer.shadow_packet(selected,selected_ids)
			state["legacy_shadow_cache"]={"sources":selected.size(),"reused":reused,"equal_arrays":equal_arrays,"builds":builds_before,"packet_bytes":cached_bytes.size()}
			fail+=int(not reused or not equal_arrays)
		var name_value := ("r127_region_%02d" if regional else "r63_city_%02d") % index
		if guarded:
			name_value="r129_guarded_%02d"%index
			if corridor:
				name_value="r135_corridor_%02d"%index
			fail+=int(first_image==null)
			if first_image!=null:
				fail+=int(first_image.save_png(output.path_join(name_value+"_first_native.png"))!=OK)
		fail += int(not settled or not Session.state_ready(state))
		if regional or guarded:
			fail+=int(int(state.get("max_transition_triangles",-1))<0 or int(state.get("max_transition_triangles",-1))>240000)
		fail += int(battle.get_viewport().get_texture().get_image().save_png(output.path_join(name_value + ".png")) != OK)
		fail += int(map._viewport.get_texture().get_image().save_png(output.path_join(name_value + "_native.png")) != OK)
		if OS.get_environment("AGL_TOKYO_LEGACY_LAYER_REVIEW")=="1" and index in [0,2,4]:
			# 只诊断旧表现层：同机位隐藏/恢复，不改高度、碰撞、来源屏蔽或性能负载。
			var legacy: Variant = battle.get("_building_renderer")
			if typeof(legacy)!=TYPE_OBJECT or not is_instance_valid(legacy) or not legacy is BuildingRenderer:
				fail+=1
			else:
				var was_visible: bool = legacy.visible
				legacy.visible=false
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				fail+=int(battle.get_viewport().get_texture().get_image().save_png(output.path_join(name_value+"_without_legacy.png"))!=OK)
				legacy.visible=was_visible
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				fail+=int(battle.get_viewport().get_texture().get_image().save_png(output.path_join(name_value+"_legacy_restored.png"))!=OK)
				fail+=int(legacy.visible!=was_visible)
		fail += int(var_to_bytes(BuildingRenderer._cache_entries) != signature)
		rows.append({"center":str(battle.camera.position),"zoom": pose.x, "rotation_deg": pose.y,"settled":settled, "state": state,"first_state":first_state, "collision_unchanged": var_to_bytes(BuildingRenderer._cache_entries) == signature})
	if fixed_set and map._fixed_atlas!=null and map._fixed_atlas.members().size()==6:
		for member: RefCounted in map._fixed_atlas.members():
			fail+=int(int(member._state.get("applications",0))<1)
	tree.paused = paused
	if bounded_review:
		battle._building_renderer.bounded_roof_projection=prior_bounded
		battle._building_renderer.cache_shadow_geometry=prior_shadow_cache
		battle._building_renderer.process_mode=prior_legacy_mode
		battle._building_renderer.queue_redraw()
	source.process_mode=source_mode
	battle.camera.ignore_rotation = ignore
	var file := FileAccess.open(output.path_join("r135_corridor_review.json" if corridor else ("r129_guarded_review.json" if guarded else ("r127_region_review.json" if regional else "r63_city_review.json"))), FileAccess.WRITE)
	if file == null:
		return 1
	file.store_string(JSON.stringify({"rows": rows, "fail": fail, "fps_evidence": false, "formal_route": true,"reuse_reversal_review":reversal}, "\t"))
	file.close()
	print("[R63 city review] poses=", rows.size(), " fail=", fail)
	return fail


static func ready_at_canvas(current: Transform2D, expected: Transform2D, state: Dictionary) -> bool:
	return current.is_finite() and expected.is_finite() and current.is_equal_approx(expected) and Session.state_ready(state)


static func source_state_ready(state: Dictionary) -> bool:
	return state.get("transitioning",true)==false and state.get("pending_count",-1)==0 and state.get("missing_keys",[""]).is_empty() \
		and not str(state.get("current_lod","")).is_empty() and state.get("current_lod") == state.get("target_lod")


static func source_ready(source: Node) -> bool:
	# 仅观察场：整层就绪不足以代表逐瓦片淡入完成，不能拿两个异步阶段做像素A/B。
	if not source_state_ready(source.debug_state()):
		return false
	for item: Dictionary in source.presentation_tiles():
		var sprite: Variant = item.sprite.get_ref()
		if typeof(sprite)!=TYPE_OBJECT or not is_instance_valid(sprite) or not sprite is CanvasItem:
			return false
		if sprite.is_visible_in_tree() and not is_equal_approx(sprite.modulate.a,1.0):
			return false
	return true
