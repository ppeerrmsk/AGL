extends RefCounted
## 仅静态远档合并对拍；不冒充连续流送/急拉近恢复/实战FPS。
const Utility := preload("res://scripts/tests/tokyo_lod_spatial_review.gd")
const Pixels := preload("res://scripts/tests/tokyo_shell_review.gd")
const Indexed := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
var _fail := 0
var _rows: Dictionary = {}
var _ground_shaders: Dictionary = {}


func run(owner: Node2D, directory: String, output: String) -> int:
	if output.is_empty() or DirAccess.dir_exists_absolute(output):
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
	for row: Dictionary in manifest.rows:
		if FileAccess.get_sha256(row.path) != row.sha256 or FileAccess.get_sha256(row.source) != row.source_sha256:
			return 1
		_rows["%d:%d" % [row.cell_id, row.level]] = row
	var overlay: Node = owner.features._tokyo_volume
	var original_shadow: bool = overlay._sun.shadow_enabled
	var shadow_control := OS.get_environment("AGL_TOKYO_NO_SHADOW_REVIEW") == "1"
	if shadow_control:
		overlay._sun.shadow_enabled = false
	var utility := Utility.new()
	var poses: Array = []
	var zooms: Array[float] = [0.13, 0.21, 0.26, 0.4]
	if OS.get_environment("AGL_TOKYO_FAR_CLUSTER_LEVELS")=="3":
		zooms.append_array([.65,.9])
	if OS.get_environment("AGL_TOKYO_FAR_CLUSTER_LEVELS")=="5":
		zooms=[1.95,2.4,3.5,5.0]
	if OS.get_environment("AGL_TOKYO_FAR_CLUSTER_LEVELS")=="4":
		# 本Visual逻辑1920/实际1600，按实际输出尺度覆盖中档上界及LOD5，不将zoom当输出尺度。
		zooms=[0.98,1.2,1.85,1.95]
	for place: Array in [["north", Vector2(-5600, -2900), 0.0], ["seam", Vector2(-5300, -1700), deg_to_rad(14)], ["port", Vector2(-5150, -480), 0.0]]:
		for zoom: float in zooms:
			poses.append([place[0], place[1], zoom, place[2]])
	poses.append_array([["near_original", Vector2(-5600, -2900), 0.98, 0.0], ["close_original", Vector2(-5600, -2900), 5.0, 0.0]])
	if OS.get_environment("AGL_TOKYO_FAR_CLUSTER_LEVELS")=="4":
		# 补充单父区内部，不替代既有宽镜头及其双份驻留失败证据。
		for zoom: float in [1.3,1.85,1.95]:
			poses.append(["north_interior",Vector2(-5900,-3200),zoom,0.0])
		poses.append(["north_return",Vector2(-5900,-3200),1.3,0.0])
	var records: Array[Dictionary] = []
	for pose: Array in poses:
		owner.camera.position = pose[1]
		owner.camera.zoom = Vector2.ONE * float(pose[2])
		owner.camera.rotation = pose[3]
		owner.camera.force_update_scroll()
		await owner.get_tree().create_timer(0.3).timeout
		var state: Dictionary = overlay.debug_state()
		var deadline := Time.get_ticks_msec() + 15000
		while (state.ready_cells != state.desired_cells or state.ready_cells == 0 or state.stream.pending > 0) and Time.get_ticks_msec() < deadline:
			await owner.get_tree().process_frame
			state = overlay.debug_state()
		if state.ready_cells == 0 or state.ready_cells != state.desired_cells or not state.stream.failures.is_empty():
			_fail += 1
			records.append({"pose": pose[0], "zoom": pose[2], "blocked": "source cut", "state": state})
			continue
		_fail += int(not await utility._wait_basemap(owner))
		overlay.set_process(false)
		var ground := preload("res://scripts/experiments/tokyo_tile_ground_candidate.gd").new()
		ground.shader_cache = _ground_shaders
		if OS.get_environment("AGL_TOKYO_FAR_SAME_GROUND")=="1" and not ground.bind(overlay,owner.features._raster_basemap,true,true):
			ground.close()
			_fail += 1
			return _fail
		var stem := output.path_join("%s_%03d" % [pose[0], roundi(pose[2] * 100)])
		var result := await _compare(owner, overlay, utility, state, stem, int(ground.stats.get("extra_faces",0)))
		if OS.get_environment("AGL_TOKYO_FAR_CLUSTER_LEVELS")=="4" and not result.has("blocked"):
			var original_expected := float(pose[2])>=1.95
			var untouched: bool = original_expected or (overlay._mid_relief and overlay._relief_active)
			_fail += int(int(state.level)!=(5 if original_expected else 4))
			_fail += int(untouched and not bool(result.near_original))
			_fail += int(str(pose[0]).begins_with("north") and not untouched and int(result.groups)==0)
		result["ground"] = ground.stats.duplicate(true)
		ground.close()
		result.merge({"pose": pose[0], "zoom": pose[2], "state": state, "stem": stem})
		records.append(result)
		overlay._viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		overlay.set_process(true)
		print("[R57 far Visual] pose=", pose[0], " zoom=", pose[2], " before=", result.get("original_faces",state.triangles), " after=", result.get("faces", -1), " restored=", result.get("restore_error", -1))
	_fail += utility._fail
	var file := FileAccess.open(output.path_join("review.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"fail": _fail, "records": records, "fps_evidence": false, "continuous_lod": false, "shadow_control": shadow_control}, "\t"))
	file.close()
	overlay._sun.shadow_enabled = original_shadow
	print("[R57 far Visual] COMPLETE poses=", records.size(), " fail=", _fail)
	return _fail


func _compare(owner: Node2D, overlay: Node, utility: RefCounted, state: Dictionary, stem: String, ground_faces: int = 0) -> Dictionary:
	var selected: Dictionary = {}
	var extra := 0
	for id: int in overlay._batches:
		var key := "%d:%d" % [id, state.level]
		if _rows.has(key) and not _rows[key].groups.is_empty():
			var row: Dictionary = _rows[key]
			# LOD4有full/mid两种正式组合；候选只替换full，精确认证的mid源必须原样保留。
			if int(row.level)==4 and overlay._mid_relief and overlay._relief_active \
					and overlay._batches[id].path==str(overlay._archive.cells[id].mid.path):
				continue
			if state.output_scale > row.max_scale or overlay._batches[id].path != row.source:
				_fail += 1
				return {"blocked": "scale or source identity"}
			selected[id] = row
			extra += int(row.bytes)
	var source: RasterBasemapRenderer = owner.features._raster_basemap
	var projected := not source.source_projection.is_empty()
	# 此静态双份几何审查不走正式派生overlay；在装入候选前计入同一源几何上界。
	var projection_allowance := RasterBasemapRenderer.PROJECTED_GEOMETRY_RESERVE if projected else 0
	var resident := int(state.stream.bytes) + int(state.stream.reserved_bytes) + int(overlay._stream.summary().get("auxiliary_bytes",0)) + extra + projection_allowance
	if resident > 96 * 1024 * 1024:
		_fail += 1
		return {"blocked": "old plus candidate memory", "resident_bytes": resident}
	var resources: Dictionary = {}
	var sources: Array[Dictionary] = []
	for id: int in selected:
		resources[id] = ResourceLoader.load(selected[id].path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if resources[id] == null or not resources[id].valid():
			_fail += 1
			return {"blocked": "candidate invalid"}
		sources.append_array(selected[id].groups)
	var before: Image = await utility._capture(owner, overlay, stem + "_original.png")
	var original_faces := ground_faces
	for batch: Dictionary in overlay._batches.values():
		for node: MeshInstance3D in batch.nodes:
			if node.visible:
				original_faces += Indexed.triangles(node.mesh)
	var saved: Dictionary = {}
	for id: int in selected:
		saved[id] = overlay._batches[id].nodes[0].mesh
		overlay._batches[id].nodes[0].mesh = resources[id].meshes[0]
	var faces := ground_faces
	for batch: Dictionary in overlay._batches.values():
		for node: MeshInstance3D in batch.nodes:
			if node.visible:
				faces += Indexed.triangles(node.mesh)
	await utility._capture(owner, overlay, stem + "_candidate.png")
	var masks := Pixels._screen_bounds(overlay, sources)
	for id: int in saved:
		overlay._batches[id].nodes[0].mesh = saved[id]
	var restored: Image = await utility._capture(owner, overlay, stem + "_restored.png")
	var error := Pixels._pixel_error(before, restored)
	_fail += int(error > 1)
	return {"faces": faces, "original_faces":original_faces, "face_budget_pass": faces <= 240000, "restore_error": error, "resident_bytes": resident,
		"groups": sources.size(), "allowed_screen_bounds": masks, "mask_padding_px": 2, "near_original": selected.is_empty(),
		"projected_source":projected,"projected_geometry_bytes":source.projected_geometry_bytes(),"projection_allowance":projection_allowance}
