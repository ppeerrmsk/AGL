extends "res://scripts/rendering/tokyo_cluster_overlay.gd"
## 显式规范候选：全部配置共用原有Stream、切面事务与节点池。
const Canonical := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const Coverage := preload("res://scripts/experiments/tokyo_source_coverage.gd")
const GuardReuse := preload("res://scripts/experiments/tokyo_guarded_pair_reuse.gd")
const LowWalls := preload("res://scripts/rendering/tokyo_low_wall_binding.gd")
var _low_wall_nodes: Dictionary = {}
var _low_wall_required := false
var _low_wall_fade_enabled := false
var _low_wall_material: ShaderMaterial
var _low_wall_mix := 0.0
var _low_wall_scale := 0.0
var _low_wall_full_override := false
var _canonical: Resource
var _canonical_sha := ""
var _coverage: Dictionary = {}
var _paired: Dictionary = {}
var _legacy: WeakRef
var _hidden_sources := PackedInt32Array()
var _metadata_disk_bytes := 0
var _coverage_updates := 0
var _max_coverage_usec := 0
var _unpaired_selections := 0
var _coverage_active := false
var _preloaded_ao: RefCounted
var _ao_error := ""
var _component_pages: Dictionary = {}
var _restore_trace_enabled := false
var _restore_trace: Array[Dictionary] = []
var _guard2_parents: Array[Dictionary] = []
var _guard2_adoptions := 0
var _guard2_max_usec := 0
var _near_dominance := false
var _near_adoptions := 0
var _near_max_usec := 0
var _near_native: Dictionary = {}


func setup(source: Node2D, camera: Camera2D) -> bool:
	return super.setup(source, camera) and _ao_error.is_empty()


func _load_archive() -> Resource:
	_restore_trace_enabled = OS.get_environment("AGL_TOKYO_RESTORE_TRACE") == "1"
	var path := OS.get_environment("AGL_TOKYO_CANONICAL_CATALOG")
	var prefix := OS.get_environment("AGL_TOKYO_COVERAGE_PREFIX")
	if path.is_empty() or prefix.is_empty() or not ResourceLoader.exists(path):
		return null
	_canonical = load(path)
	if not _canonical is Canonical or not _canonical.valid():
		return null
	_canonical_sha = FileAccess.get_sha256(path)
	_near_dominance=OS.get_environment("AGL_TOKYO_NEAR_DOMINANCE")=="1"
	if _near_dominance and _canonical_sha!=GuardReuse.NEAR_SOURCE_SHA:
		return null
	var nine_guard2 := OS.get_environment("AGL_TOKYO_NINE_GUARD2")=="1"
	var reuse_guard2 := OS.get_environment("AGL_TOKYO_REUSE_GUARD2")=="1"
	if nine_guard2 and (not reuse_guard2 or _canonical_sha!="90d2378a4f480b9c97609038ac7913fd6f3f6b5f816d9ebe36bd935f88000fab"):
		return null
	if reuse_guard2 and not nine_guard2 and _canonical_sha not in Canonical.UNCHANGED_FIXED_LOD12_CATALOGS:
		return null
	_metadata_disk_bytes = FileAccess.get_file_as_bytes(path).size()
	var components := OS.get_environment("AGL_TOKYO_COMPONENTS")
	if not components.is_empty():
		var data := preload("res://scripts/rendering/tokyo_component_manifest.gd").read(components, _canonical, _canonical_sha)
		if data.is_empty():
			return null
		_component_pages = data.pages
		_metadata_disk_bytes += int(data.metadata_bytes)
	var wall_path := OS.get_environment("AGL_TOKYO_LOW_WALL_MANIFEST")
	_low_wall_required = not wall_path.is_empty()
	_low_wall_fade_enabled = OS.get_environment("AGL_TOKYO_LOW_WALL_FADE") == "1"
	if _low_wall_fade_enabled and not _low_wall_required:
		return null
	if _low_wall_required:
		var data := preload("res://scripts/rendering/tokyo_low_wall_manifest.gd").read(wall_path,_canonical_sha,_component_pages)
		if data.is_empty():
			return null
		_component_pages = data.pages
		_metadata_disk_bytes += int(data.metadata_bytes)
	for configuration: String in Canonical.CONFIGURATIONS:
		var side_path := prefix + configuration + ".bin"
		var file := FileAccess.open(side_path, FileAccess.READ)
		if file == null:
			return null
		var data: Variant = file.get_var(false)
		_metadata_disk_bytes += file.get_length()
		file.close()
		if not data is Dictionary or data.get("schema") != 1 or not data.get("verified", false) \
				or data.get("configuration") != configuration or data.get("catalog_sha256") != _canonical_sha \
				or data.get("collision_sha256") != _canonical.collision_sha256 or data.get("owners_sha256") != _canonical.owners_sha256 \
				or data.get("pages", {}).size() != _canonical.pages_per_configuration() or data.get("sources", {}).size() != _canonical.gameplay_source_count():
			return null
		for page_path: String in data.pages:
			if data.pages[page_path].identity != _canonical.descriptors.get(page_path, {}).get("canonical_identity"):
				return null
		_coverage[configuration] = data
	_candidate = "R63 canonical"
	_layer_culling = true
	_directional_cull = true
	_exact_view = true
	_tight_depth = true
	# 完整规范包含新增街区高度，不用旧地图局部包络截断新增楼顶。
	_local_depth = false
	_mid_relief = true
	return _canonical.presentation_archive(load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res"))


func _setup_geometry() -> void:
	_composite.set_shader_parameter("edge_feather", 0.0)
	_sun.shadow_normal_bias = 2.0
	_warm_deadline = Time.get_ticks_msec() + 2000
	_extent = _archive.bounds
	_descriptors = _canonical.descriptors.duplicate()
	_descriptors.merge(_component_pages, true)
	if _near_dominance:
		_near_native=GuardReuse.native_index(_canonical.configurations.lod4_full)
		_near_native.merge(GuardReuse.native_index(_canonical.configurations.lod5_full))
	for configuration: String in Canonical.CONFIGURATIONS:
		for root: Dictionary in _canonical.configurations[configuration]:
			for kind in 3:
				if int(root.triangles[kind]) > 0:
					_source_max_height = maxf(_source_max_height, root.boxes[kind].end.y)
					_extent = _extent.merge(layer_bounds(root.boxes[kind]).grow(root.boxes[kind].end.y * 1.6 + 8.0))
		var level := int(configuration.substr(3, 1))
		if configuration.ends_with("guarded") or level == 5:
			continue
		var fallback := "lod%d_guarded" % level if level < 4 else "lod5_full"
		var roots: Array[Dictionary] = []
		for n in 16:
			roots.append(Pair.decorate(_canonical.configurations[configuration][n], _canonical.configurations[fallback][n], _descriptors))
		_paired[configuration] = roots
	if OS.get_environment("AGL_TOKYO_REUSE_GUARD2")=="1":
		for n in 16:
			_guard2_parents.append(Pair.decorate(_canonical.configurations.lod1_full[n],_canonical.configurations.lod2_guarded[n],_descriptors))
	_stream = preload("res://scripts/rendering/tokyo_component_stream.gd").new() if not _component_pages.is_empty() else Stream.new()
	_stream.name = "TokyoCellStream"
	_stream.configure(self, _descriptors)
	var ao_directory := OS.get_environment("AGL_TOKYO_AO_PRELOAD")
	if not ao_directory.is_empty():
		_preloaded_ao = preload("res://scripts/experiments/tokyo_baked_ao.gd").new()
		if not _preloaded_ao.bind_preloaded(self, ao_directory):
			_ao_error = "AO preload rejected"
			_enabled = false
	get_tree().root.add_child.call_deferred(_stream)
	if _low_wall_fade_enabled:
		_low_wall_material = _materials[0].duplicate(false)
		_low_wall_material.set_shader_parameter("outgoing",true)
		_low_wall_material.set_shader_parameter("lod_mix",0.0)
		_materials.append(_low_wall_material)
	for slot in 16:
		var nodes: Array = []
		for kind in 3:
			var node := _add_mesh(null, _materials[4 if kind == 2 else kind], kind < 2)
			node.hide()
			nodes.append(node)
		_slots.append(nodes)
		if _low_wall_required:
			var wall := LowWalls.create_slot(nodes[0])
			if _low_wall_fade_enabled:
				wall.material_override = _low_wall_material
			_low_wall_nodes[nodes[0].get_instance_id()] = wall


func _select_cut(view: Rect2) -> Array[Dictionary]:
	_cut_solves += 1
	var configuration := "lod%d_full" % _level
	if _level == 4 and _relief_active:
		configuration = "lod4_mid"
	var inverse := _city.basis.inverse()
	var camera_ray := inverse * _camera.basis.z
	var light_ray := inverse * _sun.basis.z
	var parents: Array[Dictionary] = []
	parents.assign(_paired.get(configuration, _canonical.configurations[configuration]))
	var query := Cut.choose(parents, view, _last_canvas, Vector2(_viewport.size) * _screen.scale,
		-Vector2(camera_ray.x, camera_ray.z) / camera_ray.y, -Vector2(light_ray.x, light_ray.z) / light_ray.y,16,_stream.geometry_budget())
	_max_solver_usec = maxi(_max_solver_usec, int(query.solver_usec))
	if int(query.bytes) > _stream.geometry_budget() and _paired.has(configuration):
		var fallback := "lod%d_guarded" % _level if _level < 4 else "lod5_full"
		parents.assign(_canonical.configurations[fallback])
		query = Cut.choose(parents, view, _last_canvas, Vector2(_viewport.size) * _screen.scale,
			-Vector2(camera_ray.x, camera_ray.z) / camera_ray.y, -Vector2(light_ray.x, light_ray.z) / light_ray.y,16,_stream.geometry_budget())
		_max_solver_usec = maxi(_max_solver_usec, int(query.solver_usec))
		_unpaired_selections += 1
	var entries: Array[Dictionary] = []
	entries.assign(query.entries)
	if _near_dominance and configuration=="lod4_full":
		var started := Time.get_ticks_usec()
		var context := {"view":view,"canvas":_last_canvas,"logical":Vector2(_viewport.size)*_screen.scale,
			"roof":-Vector2(camera_ray.x,camera_ray.z)/camera_ray.y,"shadow":-Vector2(light_ray.x,light_ray.z)/light_ray.y}
		parents.assign(_canonical.configurations.lod5_full)
		var alternative := GuardReuse.near_choice(entries,parents,_descriptors,context,_stream.geometry_budget(),_near_native)
		if not alternative.is_empty():
			entries=alternative
			_near_adoptions+=1
		_near_max_usec=maxi(_near_max_usec,Time.get_ticks_usec()-started)
	return entries


func _step_geometry(view: Rect2, scale_value: float, _delta: float) -> bool:
	# 分段墙钟是 geometry 的子桶，不能再与父桶相加；仅诊断开启时取时钟。
	var trace := PerfBuckets.frame_trace_enabled
	var stage_start := Time.get_ticks_usec() if trace else 0
	var changed := _refresh_low_wall_lod(scale_value)
	if _is_cluster(_current_cut) and scale_value > float(Archive.CUTS[int(_current_cut[0].level)]) * 1.08:
		_restore_original()
		_selection_canvas = Transform2D(0, Vector2(INF, INF))
		_lod_clock = 0.0
		changed = true
	# 等待中的旧目标也受当前尺度约束；安全原形在场时不能跳过检查再提交过期低档。
	if _is_cluster(_target_cut) and scale_value > float(Archive.CUTS[int(_target_cut[0].level)]) * 1.08:
		_selection_canvas = Transform2D(0, Vector2(INF, INF))
		_lod_clock = 0.0
	if trace:
		PerfBuckets.tick("tokyo_map_restore", Time.get_ticks_usec() - stage_start)
	if _lod_clock <= 0.0:
		_lod_clock = 0.1
		var next := Archive.choose_level(_level, scale_value)
		var relief := relief_enabled(_relief_active, scale_value)
		if next != _level or relief != _relief_active or _selection_canvas != _last_canvas \
				or _selection_size != _viewport.size or _selection_sun != _sun.basis:
			_previous_level = _level
			lod_switches += int(next != _level)
			_level = next
			_relief_active = relief
			_selection_canvas = _last_canvas
			_selection_size = _viewport.size
			_selection_sun = _sun.basis
			stage_start = Time.get_ticks_usec() if trace else 0
			_planned_cut = _select_cut(view)
			if trace:
				PerfBuckets.tick("tokyo_map_select", Time.get_ticks_usec() - stage_start)
			stage_start = Time.get_ticks_usec() if trace else 0
			changed = _prepare_target(view) or changed
			if trace:
				PerfBuckets.tick("tokyo_map_prepare", Time.get_ticks_usec() - stage_start)
	if _transition_blocked.is_empty() and (_target_paths != _current_paths or _committed_level != _level):
		stage_start = Time.get_ticks_usec() if trace else 0
		var ready := true
		for path: String in _target_paths:
			if _stream.resource(path) == null:
				ready = false
				break
		if trace:
			PerfBuckets.tick("tokyo_map_ready", Time.get_ticks_usec() - stage_start)
		if ready:
			stage_start = Time.get_ticks_usec() if trace else 0
			_bind_target(_level)
			if trace:
				PerfBuckets.tick("tokyo_map_bind", Time.get_ticks_usec() - stage_start)
			changed = true
			if _phase == "stage":
				_stage_commits += 1
				stage_start = Time.get_ticks_usec() if trace else 0
				_prepare_target(view)
				if trace:
					PerfBuckets.tick("tokyo_map_prepare", Time.get_ticks_usec() - stage_start)
	if changed or view != _cull_view or _camera.basis != _cull_camera or _sun.basis != _cull_light:
		stage_start = Time.get_ticks_usec() if trace else 0
		changed = _apply_visibility(view) or changed
		if trace:
			PerfBuckets.tick("tokyo_map_visibility", Time.get_ticks_usec() - stage_start)
		_cull_view = view
		_cull_camera = _camera.basis
		_cull_light = _sun.basis
	if changed or _coverage_active != (_active and _screen.visible):
		stage_start = Time.get_ticks_usec() if trace else 0
		_sync_legacy()
		if trace:
			PerfBuckets.tick("tokyo_map_legacy_sync", Time.get_ticks_usec() - stage_start)
	if _warm_ready_frame < 0 and not _current_cut.is_empty() and _target_paths == _current_paths and _phase == "target":
		_warm_ready_frame = Engine.get_process_frames()
	return changed


func _prepare_target(view: Rect2) -> bool:
	if not _guard2_parents.is_empty() and _level==1 and _is_cluster(_current_cut) \
			and union_bytes(Pair.paths(_planned_cut),_current_paths,_descriptors)>_stream.geometry_budget():
		var started := Time.get_ticks_usec()
		var inverse := _city.basis.inverse()
		var camera_ray := inverse*_camera.basis.z
		var light_ray := inverse*_sun.basis.z
		var context := {"view":view,"canvas":_last_canvas,"logical":Vector2(_viewport.size)*_screen.scale,
			"roof":-Vector2(camera_ray.x,camera_ray.z)/camera_ray.y,"shadow":-Vector2(light_ray.x,light_ray.z)/light_ray.y}
		var alternative := GuardReuse.choose(_planned_cut,_current_cut,_guard2_parents,_descriptors,_current_paths,context,_stream.geometry_budget())
		if not alternative.is_empty():
			_planned_cut=alternative
			_guard2_adoptions+=1
		_guard2_max_usec=maxi(_guard2_max_usec,Time.get_ticks_usec()-started)
	return super._prepare_target(view)


func _refresh_low_wall_lod(scale_value: float) -> bool:
	if not _low_wall_fade_enabled:
		return false
	_low_wall_scale = scale_value
	var next := 0.0 if _low_wall_full_override else LowWalls.fade_for_scale(scale_value)
	if next == _low_wall_mix:
		return false
	_low_wall_mix = next
	_low_wall_material.set_shader_parameter("lod_mix",next)
	for batch: Dictionary in _batches.values():
		LowWalls.apply_fade(batch,next)
	return true


func set_low_wall_full_override(enabled: bool) -> void:
	_low_wall_full_override = enabled
	if _refresh_low_wall_lod(_low_wall_scale):
		# 只变墙子节点，不重算全部三层可见性：那会误恢复地表借用者已经隐藏的固定层。
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _bind_target(_actual_level: int) -> void:
	# 选择档与实际备用页档不同：材质/投影用真实页档，事务就绪仍记录目标选择档。
	var desired := _level
	super._bind_target(int(_target_cut[0].level) if not _target_cut.is_empty() else desired)
	if _low_wall_required:
		for batch: Dictionary in _batches.values():
			LowWalls.bind(batch,_low_wall_nodes[batch.nodes[0].get_instance_id()])
			LowWalls.apply_fade(batch,_low_wall_mix)
			batch.layer_bounds[0] = layer_bounds(batch.boxes[0])
	_committed_level = desired


func _remove_cell(id: Variant) -> void:
	if _low_wall_required:
		LowWalls.clear(_batches[id])
	super._remove_cell(id)


func _restore_original() -> void:
	if _restore_trace_enabled and _restore_trace.size()<32:
		var logical := Vector2(_viewport.size)*_screen.scale
		var ground := _city.basis.inverse()
		var camera := ground*_camera.basis.z
		var light := ground*_sun.basis.z
		_restore_trace.append({"frame":Engine.get_process_frames(),"level":_level,"relief":_relief_active,
			"fallback_configuration":GuardReuse.family(_current_cut,_descriptors,true),
			"catalog_sha256":_canonical_sha,"scale":float(_viewport.size.y)/_camera.size,"configuration":_descriptors[_current_cut[0].path].canonical_identity.configuration,
			"current":paths_for(_current_cut),"planned":paths_for(_planned_cut),"pinned":_current_paths.duplicate(),"budget":_stream.geometry_budget(),
			"canvas":[_last_canvas.x.x,_last_canvas.x.y,_last_canvas.y.x,_last_canvas.y.y,_last_canvas.origin.x,_last_canvas.origin.y],
			"logical":[logical.x,logical.y],"roof":[-camera.x/camera.y,-camera.z/camera.y],"shadow":[-light.x/light.y,-light.z/light.y],
			"current_bytes":union_bytes(_current_paths,PackedStringArray(),_descriptors),
			"target_bytes":union_bytes(_target_paths,PackedStringArray(),_descriptors),
			"union_bytes":union_bytes(_target_paths,_current_paths,_descriptors),"phase":_phase})
	var saved_cut := _target_cut
	var saved_paths := _target_paths
	_target_cut = Pair.original_cut(_current_cut)
	_target_paths = paths_for(_target_cut)
	for path: String in _target_paths:
		assert(_stream.resource(path) != null, "canonical original fallback must already be resident")
	_bind_target(_level)
	_target_cut = saved_cut
	_target_paths = saved_paths
	_stream.request(_current_paths, _current_paths)
	_instant_restores += 1


func bind_legacy(renderer: BuildingRenderer) -> bool:
	if var_to_bytes(renderer._districts).hex_encode().sha256_text() != _canonical.collision_sha256 \
			or var_to_bytes(BuildingRenderer._cache_entries).hex_encode().sha256_text() != _canonical.collision_sha256:
		return false
	_legacy = weakref(renderer)
	_sync_legacy()
	return true


func _sync_legacy() -> void:
	_coverage_active = _active and is_instance_valid(_screen) and _screen.visible
	var renderer: Variant = _legacy.get_ref() if _legacy != null else null
	if typeof(renderer) != TYPE_OBJECT or not is_instance_valid(renderer):
		return
	var start := Time.get_ticks_usec()
	var sources := PackedInt32Array()
	if _active and _screen.visible and not _current_cut.is_empty():
		var configuration: String = _descriptors[_current_cut[0].path].canonical_identity.configuration
		var committed: Dictionary = {}
		for entry: Dictionary in _current_cut:
			var batch: Dictionary = _batches[entry.key]
			var layers := 0
			for kind in 2:
				if batch.nodes[kind].visible and batch.nodes[kind].mesh == batch.building.meshes[kind]:
					layers |= 1 << kind
			committed[entry.path] = {"identity": batch.building.stream_identity(), "layers": layers}
		sources = Coverage.covered_sources(_coverage[configuration], committed, configuration, _canonical.collision_sha256, _canonical_sha)
	if renderer.set_volume_coverage(self, sources):
		_hidden_sources = sources
	_coverage_updates += 1
	_max_coverage_usec = maxi(_max_coverage_usec, Time.get_ticks_usec() - start)


func _deactivate() -> void:
	super._deactivate()
	_sync_legacy()


func debug_state() -> Dictionary:
	var state := super.debug_state()
	var walls := 0
	var visible := 0
	var bound := 0
	if _low_wall_required:
		for batch: Dictionary in _batches.values():
			var count := LowWalls.faces(batch)
			walls += count
			visible += int(count > 0)
			bound += int(batch.has("low_wall_node"))
	state["low_wall_required"] = _low_wall_required
	state["low_wall_pooled_nodes"] = _low_wall_nodes.size()
	state["low_wall_visible_nodes"] = visible
	state["low_wall_bound_nodes"] = bound
	state["low_wall_faces"] = walls
	state["low_wall_mode"] = "fade" if _low_wall_fade_enabled else "full"
	state["low_wall_mix"] = _low_wall_mix
	state["low_wall_scale"] = _low_wall_scale
	state["low_wall_full_override"] = _low_wall_full_override
	state["canonical_configuration"] = _descriptors[_current_cut[0].path].canonical_identity.configuration if not _current_cut.is_empty() else ""
	state["hidden_legacy_sources"] = _hidden_sources
	state["coverage_updates"] = _coverage_updates
	state["max_coverage_usec"] = _max_coverage_usec
	state["metadata_serialized_bytes"] = _metadata_disk_bytes
	state["unpaired_selections"] = _unpaired_selections
	state["local_depth"] = _local_depth
	state["ao_preloaded"] = _preloaded_ao.stats.duplicate(true) if _preloaded_ao != null else {}
	state["ao_error"] = _ao_error
	state["ao_required"] = _preloaded_ao != null
	state["ao_ready"] = _preloaded_ao != null and _preloaded_ao._texture != null and _preloaded_ao._budget_stream != null
	state["restore_trace"] = _restore_trace.duplicate(true)
	state["guard2_reuse_required"]=not _guard2_parents.is_empty()
	state["guard2_reuse_adoptions"]=_guard2_adoptions
	state["guard2_reuse_max_usec"]=_guard2_max_usec
	state["near_dominance_required"]=_near_dominance
	state["near_dominance_adoptions"]=_near_adoptions
	state["near_dominance_max_usec"]=_near_max_usec
	state["fallback_configuration"]=GuardReuse.family(_current_cut,_descriptors,true) if not _guard2_parents.is_empty() else ""
	return state
