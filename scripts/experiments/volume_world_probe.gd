extends Node3D
## 只读表现适配器；正式单位继续拥有物理、AI、伤害、装备与终态。
const Factory := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Airframes := preload("res://scripts/experiments/volume_aircraft_catalog.gd")
const Mounts := preload("res://scripts/experiments/volume_aircraft_mount_catalog.gd")
const GroundCatalog := preload("res://scripts/experiments/volume_ground_catalog.gd")
const GroundPresenter := preload("res://scripts/experiments/volume_ground_presenter.gd")
const MapFactory := preload("res://scripts/experiments/volume_map_factory.gd")
const SatelliteGround := preload("res://scripts/experiments/volume_satellite_ground.gd")
const VolumeProjection := preload("res://scripts/experiments/volume_projection.gd")
const Renderer := preload("res://scripts/aircraft_renderer.gd")
const Catalog := preload("res://scripts/aircraft_silhouette_catalog.gd")
const AIRFRAME_LIVERY_SHADER := preload("res://resources/shaders/volume_aircraft_livery.gdshader")
const AIRFRAME_FADE_SHADER := preload("res://resources/shaders/volume_aircraft_fade.gdshader")
const FADE_ROUTE_PREFIX := "fade_"
const MAP_PATH := "res://resources/maps/desert_railway_preview.aglmap"
const BODY_META := &"volume_3d_body"
const AIR_HEIGHT := 600.0
const BASELINE_KINDS: Array[String] = ["fighter", "a10", "mother_goose", "prop", "vls"]
const MOUNT_DETAIL_ENTER_PX := 22.0
const MOUNT_DETAIL_EXIT_PX := 18.0
const BODY_LOD0_ENTER_PX := 22.0
const BODY_LOD0_EXIT_PX := 18.0
const BODY_LOD2_ENTER_PX := 8.0
const BODY_LOD2_EXIT_PX := 11.0
const BODY_LOD_ROUTE_PREFIX := "lod1_"
const BODY_LOD2_ROUTE_PREFIX := "lod2_"

var _mode_ref: WeakRef
var _ground_presenter := GroundPresenter.new()
var _ground_enabled := true
var _camera := Camera3D.new()
var _sun := DirectionalLight3D.new()
var _root_map: MeshInstance3D
var _satellite_ground: Node3D
var _previous_msaa := -1
var _batches: Dictionary = {}
var _mesh_routes: Dictionary = {}
var _counts: Dictionary = {}
var _active_kinds: Array[String] = []
var _members: Array[WeakRef] = []
var _hidden_layers: Array[WeakRef] = []
var _refresh := 0.0
var _elapsed := 0.0
var _goose_ref: WeakRef
var _scenario := ""
var bodies_enabled := true
var max_projection_error_px := 0.0
var max_body_count := 0
var last_body_count := 0
var last_fallback_count := 0
var goose_seen := false
var last_live_mounts := 0
var last_live_rotors := 0
var last_mount_workload := 0
var last_mount_detail_bodies := 0
var goose_visible_frames := 0
var _update_us := 0
var _updates := 0
var _initial_ms := 0.0
var _model_triangles := 0
var _map_triangles := 0
var _production_batch := true
var _kinds: Array[String] = []
var _supported_key_lookup: Dictionary = {}
var _native_sizes: Dictionary = {}
var max_dedicated_bodies := 0
var dedicated_visible_frames := 0
var _display_ground := Basis.IDENTITY
var _display_anchor_shift := Vector3.ZERO
var _airframe_material: ShaderMaterial
var _fade_material: ShaderMaterial
var _fade_mount_material: ShaderMaterial
var _map_material: StandardMaterial3D
var _mount_material: StandardMaterial3D
var _include_map := true
var _display_tilt := VolumeProjection.TILT
var _hide_2d_map := true
var _mount_detail_states: Dictionary = {}
var _body_lod_states: Dictionary = {}
var last_lod0_bodies := 0
var last_lod1_bodies := 0
var last_lod2_bodies := 0
var last_body_lod_switches := 0
var total_body_lod_switches := 0
var max_lod0_bodies := 0
var max_lod1_bodies := 0
var max_lod2_bodies := 0
var lod0_submissions := 0
var lod1_submissions := 0
var lod2_submissions := 0
var material_warm_state := {"state":"not_requested","rendered":false}
var _weather_volume: Node3D


func setup(mode: Node, scenario: String, options: Dictionary = {}) -> void:
	var started := Time.get_ticks_usec()
	_mode_ref = weakref(mode)
	_ground_enabled = OS.get_environment("AGL_GROUND_VOLUME").to_lower() != "off"
	_scenario = scenario
	_include_map = bool(options.get("include_map", true))
	# 沙漠候选入口独立选视角；正式透明机体层保持原30度。
	_display_tilt = float(options.get("display_tilt", VolumeProjection.DESERT_TILT if _include_map else VolumeProjection.TILT))
	_hide_2d_map = bool(options.get("hide_2d_map", _include_map))
	_previous_msaa = get_viewport().msaa_3d
	# F6 与正式飞机层共用最低 2× MSAA，不能因没有三维地表就关闭机翼边缘抗锯齿。
	if _previous_msaa == Viewport.MSAA_DISABLED:
		get_viewport().msaa_3d = Viewport.MSAA_2X
	_production_batch = not scenario.contains("_baseline_")
	_supported_key_lookup.clear()
	_native_sizes.clear()
	for key in Airframes.supported_keys():
		_supported_key_lookup[key] = true
		var metadata := Airframes.metadata_for(key)
		_native_sizes[key] = Vector2(float(metadata.get("native_span", 34.0)),
			float(metadata.get("native_length", 34.0)))
	_kinds.clear()
	_mesh_routes.clear()
	bodies_enabled = scenario.begins_with("volume_3d_")
	process_priority = 1000
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("777a67") if _include_map else Color(0.0, 0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c9d9e5")
	environment.ambient_light_energy = 0.35
	_camera.environment = environment
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.1
	_camera.far = 100000.0
	add_child(_camera)
	_camera.make_current()
	MapFactory.configure_sun(_sun)
	# 正式飞机覆盖层没有三维受影地表；保留定向光塑形，但关闭不会出现在合成画面里的影图。
	# 地图实验仍保留真实阴影，避免为飞机性能修改地图候选的视觉合同。
	if not _include_map:
		_sun.shadow_enabled = false
	_sun.directional_shadow_max_distance = 80000.0
	add_child(_sun)
	_airframe_material = ShaderMaterial.new()
	_airframe_material.shader = AIRFRAME_LIVERY_SHADER
	_fade_material = ShaderMaterial.new()
	_fade_material.shader = AIRFRAME_FADE_SHADER
	_fade_mount_material = ShaderMaterial.new()
	var fade_mount_shader := Shader.new()
	fade_mount_shader.code = AIRFRAME_FADE_SHADER.code.replace("vertex_lighting", "unshaded")
	_fade_mount_material.shader = fade_mount_shader
	_map_material = Factory.material()
	# 小型挂点/旋翼靠几何轮廓与正式顶点色辨识；无光照材质避免密集编成中为近百个
	# 独立装备重复承担逐像素定向光，机身仍保留完整受光塑形。
	_mount_material = Factory.material()
	_mount_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 正式入口在首帧前创建全部共享 GPU 路由，避免某机型/挂载随巡检镜头首次显形时建网格卡帧。
	# visible_instance_count 仍为 0；运行期只提交屏内真实演员，不增加战斗实体或火力。
	if bool(options.get("prewarm_catalog", false)):
		# 缓存网格不会编译首次淡出的透明/深度预通道；以真实实例格式提前绘制两帧。
		var material_warmup: SubViewport = preload("res://scripts/experiments/volume_material_warmup.gd").new()
		var warm_materials: Array[ShaderMaterial] = [_airframe_material,_fade_material,_fade_mount_material]
		material_warmup.configure_instanced(warm_materials,_camera.environment)
		material_warm_state={"state":"pending","rendered":false}
		material_warmup.finished.connect(_on_material_warmup_finished,CONNECT_ONE_SHOT)
		add_child(material_warmup)
		for key in Airframes.supported_keys():
			_cache_mesh_route(key)
			if Airframes.supports_body_lod(key):
				_cache_mesh_route(BODY_LOD_ROUTE_PREFIX + key)
				_cache_mesh_route(BODY_LOD2_ROUTE_PREFIX + key)
		for mount_kind in Mounts.supported_kinds():
			_cache_mesh_route("mount_" + mount_kind)
		if _ground_enabled:
			for key in GroundCatalog.keys():
				_cache_mesh_route("ground_full_" + key)
				_cache_mesh_route("ground_simple_" + key)
	var prepared_map: Dictionary = options.get("prepared_map", {})
	if _include_map and not prepared_map.is_empty():
		_root_map = prepared_map.root
		_satellite_ground = prepared_map.ground
		_map_triangles = prepared_map.triangles
	elif _include_map:
		_root_map = MeshInstance3D.new()
		var doc := MapDocument.load_from(MAP_PATH)
		assert(doc != null, "volume map document must load")
		if _production_batch:
			var features: Variant = mode.get("_map_features")
			var raster: Variant = features.get("_raster_basemap") if is_instance_valid(features) else null
			var has_raster: bool = typeof(raster) == TYPE_OBJECT and is_instance_valid(raster) \
				and raster is RasterBasemapRenderer
			_satellite_ground = SatelliteGround.new()
			_satellite_ground.enable_relief()
			add_child(_satellite_ground)
			if has_raster:
				_satellite_ground.setup(raster)
			else:
				# 压力 fixture 可能关闭二维底图；仍必须激活候选真实瓦片成本。
				assert(_satellite_ground.setup_lab(mode.camera, String(doc.basemap.meta_path)))
			var map_packet := MapFactory.build(doc, true, true)
			assert(map_packet.get("ok", false), "volume map build failed: " + String(map_packet.get("reason", "")))
			MapFactory.configure_instance(_root_map, map_packet, _map_material)
			_map_triangles = int(map_packet.triangles)
		else:
			_root_map.mesh = Factory.map_mesh(doc)
			_map_triangles = _root_map.mesh.surface_get_array_len(0) / 3
		if not _production_batch:
			_root_map.material_override = _map_material
		add_child(_root_map)
	# 未要求目录预热的隔离候选仍按真实可见机型建 MultiMesh；baseline 固定预热原五类，
	# 正式入口则已在上方预热完整动态目录，但所有批次仍从零可见实例开始。
	if not _production_batch:
		for kind in BASELINE_KINDS:
			_cache_mesh_route(kind)
	# 只停掉被替换的地图绘制，不销毁其玩法查询数据，也不隐藏天气/单位/UI。
	if _hide_2d_map:
		for property in ["_map_features", "_building_renderer"]:
			var layer: Variant = mode.get(property)
			if typeof(layer) == TYPE_OBJECT and is_instance_valid(layer) and layer is CanvasItem and layer.visible:
				_hidden_layers.append(weakref(layer))
				layer.hide()
	_refresh_members()
	_process(0.0)
	_initial_ms = float(Time.get_ticks_usec() - started) / 1000.0
	print("[Volume] enabled=%s map=%s batch_a=%s routes=%d live_batch_nodes=%d build_ms=%.2f" % [
		bodies_enabled, "desert-document" if _include_map else "transparent-aircraft-only",
		_production_batch, _kinds.size(), _batches.size(), _initial_ms])


func _cache_mesh_route(kind: String) -> ArrayMesh:
	if _mesh_routes.has(kind):
		return _mesh_routes[kind] as ArrayMesh
	var mesh: ArrayMesh
	if kind.begins_with(FADE_ROUTE_PREFIX):
		# 只换材质，不复制或替换死亡前的机体几何。
		mesh = _cache_mesh_route(kind.trim_prefix(FADE_ROUTE_PREFIX))
	elif kind.begins_with("mount_"):
		mesh = Mounts.build(kind.trim_prefix("mount_"))
	elif kind.begins_with("ground_full_"):
		mesh = GroundCatalog.build(kind.trim_prefix("ground_full_"), true)
	elif kind.begins_with("ground_simple_"):
		mesh = GroundCatalog.build(kind.trim_prefix("ground_simple_"), false)
	elif kind.begins_with(BODY_LOD2_ROUTE_PREFIX):
		mesh = Airframes.build_runtime_lod(kind.trim_prefix(BODY_LOD2_ROUTE_PREFIX),
			Airframes.BODY_LOD_LOW)
	elif kind.begins_with(BODY_LOD_ROUTE_PREFIX):
		mesh = Airframes.build_runtime_lod(kind.trim_prefix(BODY_LOD_ROUTE_PREFIX),
			Airframes.BODY_LOD_MEDIUM)
	elif _production_batch and _supported_key_lookup.has(kind):
		mesh = Airframes.build_runtime(kind)
	else:
		mesh = Factory.aircraft(kind)
	assert(mesh != null, "volume batch mesh must exist: " + kind)
	_mesh_routes[kind] = mesh
	_counts[kind] = 0
	_kinds.append(kind)
	if not kind.begins_with(FADE_ROUTE_PREFIX):
		_model_triangles += mesh.surface_get_array_len(0) / 3
	return mesh


func _ensure_batch(kind: String) -> MultiMeshInstance3D:
	if _batches.has(kind):
		return _batches[kind] as MultiMeshInstance3D
	var mesh := _cache_mesh_route(kind)
	var batch := MultiMeshInstance3D.new()
	batch.name = "VolumeBatch_%s" % kind
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.use_colors = true
	batch.multimesh.use_custom_data = true
	batch.multimesh.mesh = mesh
	batch.multimesh.instance_count = 128
	batch.multimesh.visible_instance_count = 0
	batch.material_override = _mount_material if kind.begins_with("mount_") else _airframe_material
	if kind.begins_with(FADE_ROUTE_PREFIX):
		batch.material_override = _fade_mount_material if kind.trim_prefix(FADE_ROUTE_PREFIX).begins_with("mount_") else _fade_material
	# 预热网格/材质不等于让空批次常驻 3D 剔除；首个真实实例提交时再打开节点。
	batch.visible = false
	add_child(batch)
	_batches[kind] = batch
	return batch


func _refresh_members() -> void:
	_ground_presenter.refresh_members()
	_members.clear()
	var alive_ids: Dictionary = {}
	for raw: Variant in CombatUnit.all_units:
		if typeof(raw) == TYPE_OBJECT and is_instance_valid(raw) and raw is Aircraft:
			_members.append(weakref(raw))
			alive_ids[raw.get_instance_id()] = true
			if String(raw.get_meta("silhouette", "")) == "mother_goose":
				_goose_ref = weakref(raw)
	for instance_id in _mount_detail_states.keys():
		if not alive_ids.has(instance_id):
			_mount_detail_states.erase(instance_id)
	for instance_id in _body_lod_states.keys():
		if not alive_ids.has(instance_id):
			_body_lod_states.erase(instance_id)


static func world_point(point: Vector2, height: float = 0.0) -> Vector3:
	return Vector3(point.x, height, point.y)


static func camera_basis(canvas: Transform2D) -> Basis:
	var right := canvas.affine_inverse().x.normalized()
	return Basis(Vector3(right.x, 0, right.y), Vector3(right.y, 0, -right.x), Vector3.UP)


func _sync_camera(mode: Node) -> void:
	var camera_2d: Camera2D = mode.get("camera")
	if is_instance_valid(camera_2d):
		# BOSS 成对样本同样跟随真实母机，防止母机在屏外却宣称验证了 BOSS 渲染。
		if _scenario.ends_with("mother_goose") and _goose_ref != null:
			var goose: Variant = _goose_ref.get_ref()
			if typeof(goose) == TYPE_OBJECT and is_instance_valid(goose) and goose is Aircraft:
				camera_2d.global_position = goose.global_position
				camera_2d.zoom = Vector2.ONE * 1.2
		camera_2d.force_update_scroll()
	var viewport := mode.get_viewport()
	var canvas := viewport.canvas_transform
	var inverse := canvas.affine_inverse()
	var viewport_size := viewport.get_visible_rect().size
	var display_basis := VolumeProjection.camera_basis(canvas, _display_tilt)
	_display_ground = VolumeProjection.ground_basis(canvas, _display_tilt)
	_display_anchor_shift = VolumeProjection.top_basis(canvas).y * sin(_display_tilt)
	# 精确去重，不让静止/纯平移镜头反复弄脏整棵静态地图；微小变化仍立即提交。
	if _include_map and _root_map.basis != _display_ground:
		_root_map.basis = _display_ground
	if is_instance_valid(_satellite_ground) and _satellite_ground.basis != _display_ground:
		_satellite_ground.basis = _display_ground
	var camera_size := viewport_size.y * inverse.y.length()
	var depth_span := camera_size * 0.6 + 1200.0
	_camera.set_orthogonal(camera_size, maxf(0.1, 50000.0 - depth_span), 50000.0 + depth_span)
	if _sun.directional_shadow_max_distance != _camera.far:
		_sun.directional_shadow_max_distance = _camera.far
	var camera_transform := Transform3D(display_basis,
		_display_ground * world_point(inverse * (viewport_size * 0.5)) + display_basis.z * 50000.0)
	if _camera.transform != camera_transform:
		_camera.transform = camera_transform


func _process(delta: float) -> void:
	if _mode_ref == null:
		return
	var mode: Variant = _mode_ref.get_ref()
	if typeof(mode) != TYPE_OBJECT or not is_instance_valid(mode):
		return
	var started := Time.get_ticks_usec()
	_elapsed += delta
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.1
		_refresh_members()
	_sync_camera(mode)
	if _weather_volume == null and OS.get_environment("AGL_WEATHER_VOLUME").to_lower() == "on":
		var weather: Variant = mode.get("_weather")
		if typeof(weather) == TYPE_OBJECT and is_instance_valid(weather) and weather is WeatherSystem:
			_weather_volume = preload("res://scripts/rendering/weather_density_presentation.gd").new()
			add_child(_weather_volume)
			_weather_volume.setup(weather)
	if is_instance_valid(_weather_volume):
		_weather_volume.sync(delta, mode.get_viewport().canvas_transform,
			mode.get_viewport().get_visible_rect().size, _display_ground)
	if is_instance_valid(_satellite_ground):
		_satellite_ground.sync(delta)
	var previous_active_kinds := _active_kinds
	_active_kinds = []
	for kind in previous_active_kinds:
		_counts[kind] = 0
	var dedicated_bodies := 0
	last_body_count = 0
	last_fallback_count = 0
	last_live_mounts = 0
	last_live_rotors = 0
	last_mount_workload = 0
	last_mount_detail_bodies = 0
	last_lod0_bodies = 0
	last_lod1_bodies = 0
	last_lod2_bodies = 0
	last_body_lod_switches = 0
	var source_viewport: Viewport = mode.get_viewport()
	var source_rect: Rect2 = source_viewport.get_visible_rect()
	var canvas := source_viewport.canvas_transform
	# Window 的 visible rect 是逻辑尺寸，必须乘输出 stretch 才得到实际显示像素；
	# SubViewport.size 已经是渲染像素，重复乘 stretch 会让挂载 LOD 提前切档。
	var output_pixel_scale := 1.0
	if source_viewport is Window:
		var output_stretch := source_viewport.get_stretch_transform().get_scale()
		output_pixel_scale = maxf(absf(output_stretch.x), absf(output_stretch.y))
	var render_size: Vector2 = get_viewport().get_visible_rect().size
	var projection_to_source := Vector2(source_rect.size.x / maxf(render_size.x, 1.0),
		source_rect.size.y / maxf(render_size.y, 1.0))
	var view := Rect2(Vector2.ZERO, source_rect.size).grow(250.0)
	for member in _members:
		var raw: Variant = member.get_ref()
		if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not (raw is Aircraft):
			continue
		var ac: Aircraft = raw
		var is_goose := String(ac.get_meta("silhouette", "")) == "mother_goose"
		var airframe_key := Catalog.canonical_model_key_for(ac)
		var dedicated := _production_batch and _supported_key_lookup.has(airframe_key)
		var supported := is_goose or dedicated or (not _production_batch \
			and (not ac.has_meta("category") or String(ac.get_meta("category", "")) != "boss"))
		# 渐隐沿用旧透明路径，避免三维不透明材质泄露隐身/传感器状态。
		var opaque := ac.is_visible_in_tree() and not ac.sensor_hidden \
			and ac._cloak_alpha >= 0.999 and ac._sensor_contact_visual_alpha >= 0.999 \
			and ac.self_modulate.a >= 0.999 and ac.modulate.a >= 0.999 and not ac.is_hidden_from_player_sensors()
		var screen_point := ac.get_global_transform_with_canvas().origin
		# 画面剔除同样不读运行时身份；视口外单位保留正式逻辑和 HUD 权威，
		# 但不为玩家/BOSS/指挥机额外提交看不见的三维几何。
		var active := bodies_enabled and supported and opaque and view.has_point(screen_point)
		_set_body_override(ac, active)
		if not active:
			last_fallback_count += 1
			continue
		var opacity := ac._destroy_visual_alpha if ac.is_destroyed else 1.0
		# 完全淡出后仍持有三维显示权，直到真正释放；不能闪回二维轮廓。
		if opacity <= 0.001:
			continue
		var kind := "mother_goose" if is_goose else (airframe_key if dedicated else ("a10" if airframe_key == "a10" else "fighter"))
		var scale_value := Renderer.altitude_base_scale(ac) * Renderer.visual_model_scale(ac)
		if ac.is_destroyed:
			scale_value *= ac._destroy_visual_scale
		if not is_goose:
			scale_value *= Catalog.draw_scale_for(ac)
		var projected_span_px := 0.0
		if dedicated:
			projected_span_px = maxf(_native_sizes[airframe_key].x,
				_native_sizes[airframe_key].y) * scale_value \
				* maxf(canvas.x.length(), canvas.y.length()) * output_pixel_scale
			var instance_id := ac.get_instance_id()
			var previous_body_lod := int(_body_lod_states.get(instance_id, -1))
			var body_lod := body_lod_level_for(previous_body_lod, projected_span_px)
			# 坠毁缩小不触发换模：保持最后一档，直到原网格完成淡出。
			if ac.is_destroyed and previous_body_lod >= 0:
				body_lod = previous_body_lod
			if _body_lod_states.has(instance_id) and body_lod != previous_body_lod:
				last_body_lod_switches += 1
				total_body_lod_switches += 1
			_body_lod_states[instance_id] = body_lod
			match body_lod:
				0:
					last_lod0_bodies += 1
				1:
					kind = BODY_LOD_ROUTE_PREFIX + airframe_key
					last_lod1_bodies += 1
				_:
					kind = BODY_LOD2_ROUTE_PREFIX + airframe_key
					last_lod2_bodies += 1
		var bank := ac.bank_angle + ac._evade_roll_phase + ac._active_special_roll_visual
		var basis := Basis(Vector3.UP, -ac.heading) * Basis(Vector3.FORWARD, bank)
		basis = basis.scaled(Vector3.ONE * scale_value)
		var transform := Transform3D(basis, world_point(ac.global_position, AIR_HEIGHT))
		var anchor_height := AIR_HEIGHT
		var carrier: Variant = ac.get_meta(&"parent_carrier") if ac.has_meta(&"parent_carrier") else null
		if _ground_enabled and typeof(carrier) == TYPE_OBJECT and is_instance_valid(carrier) and carrier is LandCarrierUnit:
			transform.origin.y = GroundCatalog.DECK_HEIGHT + 3.0
			anchor_height = 0.0
		var color := ac.params.icon_color if ac.params else Color.WHITE
		var wing_color := ac.params.wing_color if ac.params else Color.TRANSPARENT
		_submit(kind, transform, color, wing_color, opacity, anchor_height)
		var show_mount_detail := true
		if dedicated:
			var instance_id := ac.get_instance_id()
			show_mount_detail = mount_detail_mode_for(
				bool(_mount_detail_states.get(instance_id, false)), projected_span_px)
			if ac.is_destroyed:
				show_mount_detail = bool(_mount_detail_states.get(instance_id, show_mount_detail))
			_mount_detail_states[instance_id] = show_mount_detail
			if show_mount_detail:
				last_mount_detail_bodies += 1
			_sync_aircraft_mounts(ac, transform, airframe_key, color, show_mount_detail, opacity, anchor_height)
		if dedicated:
			dedicated_bodies += 1
			if source_rect.has_point(screen_point):
				dedicated_visible_frames += 1
		last_body_count += 1
		var projected_source := _camera.unproject_position(
			_display_ground * (transform.origin - _display_anchor_shift * anchor_height)) \
			* projection_to_source
		if anchor_height != 0.0:
			max_projection_error_px = maxf(max_projection_error_px,
				projected_source.distance_to(screen_point))
		if is_goose:
			goose_seen = true
			if source_rect.has_point(screen_point):
				goose_visible_frames += 1
			_sync_goose_mounts(ac, color, show_mount_detail)
	if _ground_enabled:
		_ground_presenter.sync(self, view, canvas, output_pixel_scale)
	# 只关闭上一帧已活跃但本帧没有提交的批次；预热的其余空批次从不进入热循环。
	for kind in previous_active_kinds:
		if int(_counts[kind]) > 0:
			continue
		var batch: MultiMeshInstance3D = _batches[kind]
		batch.multimesh.visible_instance_count = 0
		batch.visible = false
	for kind in _active_kinds:
		var batch: MultiMeshInstance3D = _batches[kind]
		batch.multimesh.visible_instance_count = int(_counts[kind])
	max_body_count = maxi(max_body_count, last_body_count)
	max_dedicated_bodies = maxi(max_dedicated_bodies, dedicated_bodies)
	max_lod0_bodies = maxi(max_lod0_bodies, last_lod0_bodies)
	max_lod1_bodies = maxi(max_lod1_bodies, last_lod1_bodies)
	max_lod2_bodies = maxi(max_lod2_bodies, last_lod2_bodies)
	lod0_submissions += last_lod0_bodies
	lod1_submissions += last_lod1_bodies
	lod2_submissions += last_lod2_bodies
	_update_us += Time.get_ticks_usec() - started
	_updates += 1
	# 性能窗口内不读回/编码截图；BenchRunner 封存结果后才采集终帧。


func set_bodies_enabled(enabled: bool) -> void:
	bodies_enabled = enabled
	_process(0.0)


static func _set_body_override(ac: Aircraft, active: bool) -> void:
	if ac.has_meta(BODY_META) == active:
		return
	if active:
		ac.set_meta(BODY_META, true)
	else:
		ac.remove_meta(BODY_META)
	ac.queue_redraw()


static func mount_detail_mode_for(current: bool, projected_span_px: float) -> bool:
	return projected_span_px >= (MOUNT_DETAIL_EXIT_PX if current else MOUNT_DETAIL_ENTER_PX)


static func body_lod_level_for(current: int, projected_span_px: float) -> int:
	match current:
		0:
			return 1 if projected_span_px < BODY_LOD0_EXIT_PX else 0
		1:
			if projected_span_px >= BODY_LOD0_ENTER_PX:
				return 0
			return 2 if projected_span_px < BODY_LOD2_ENTER_PX else 1
		2:
			return 1 if projected_span_px >= BODY_LOD2_EXIT_PX else 2
		_:
			if projected_span_px >= BODY_LOD0_ENTER_PX:
				return 0
			return 2 if projected_span_px < BODY_LOD2_ENTER_PX else 1


func _submit(kind: String, transform: Transform3D, color: Color,
		wing_color: Color = Color.TRANSPARENT, opacity: float = 1.0, anchor_height: float = NAN) -> void:
	if opacity < 0.999:
		kind = FADE_ROUTE_PREFIX + kind
	# 单个共享相机，所有机体/母机挂点经过同一仿射投影；不更改玩法锚点。
	var height := transform.origin.y if is_nan(anchor_height) else anchor_height
	transform = Transform3D(_display_ground * transform.basis,
		_display_ground * (transform.origin - _display_anchor_shift * height))
	var batch := _ensure_batch(kind)
	var index := int(_counts[kind])
	if index == 0:
		batch.visible = true
		_active_kinds.append(kind)
	if index >= batch.multimesh.instance_count:
		batch.multimesh.instance_count *= 2
		# 容量增长应在成员刷新期预留；异常峰值显式失败，不能悄悄截断单位。
		push_error("Volume batch capacity exceeded; prewarm larger capacity before comparing performance")
	batch.multimesh.set_instance_transform(index, transform)
	batch.multimesh.set_instance_color(index, color)
	var custom := livery_ratio_for(color, wing_color)
	custom.a = opacity
	batch.multimesh.set_instance_custom_data(index, custom)
	_counts[kind] = index + 1


## 自定义数据用比值而非绝对色，保持既有 MultiMesh 顶点色 × 主色路径；当前正式资源
## 的 RGB 分量均为正数。未来若某通道为零则该通道安全保持主色，不能制造无来源颜色。
static func livery_ratio_for(body_color: Color, wing_color: Color) -> Color:
	if wing_color.a <= 0.01:
		return Color.WHITE
	return Color(
		wing_color.r / body_color.r if body_color.r > 0.0001 else 1.0,
		wing_color.g / body_color.g if body_color.g > 0.0001 else 1.0,
		wing_color.b / body_color.b if body_color.b > 0.0001 else 1.0,
		1.0)


func _sync_goose_mounts(ac: Aircraft, color: Color, include_detail: bool = true) -> void:
	var mounts: Array = ac.get_meta(&"mg_mounts", [])
	for i in mounts.size():
		var raw: Variant = mounts[i]
		if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not (raw is WeaponMount):
			continue
		var mount: WeaponMount = raw
		if mount.destroyed:
			continue
		# 潜在工作量与视觉提交分离；隐藏远景挂点不能伪造调度压力下降。
		last_mount_workload += 1
		if not include_detail:
			continue
		var kind := "prop" if i < 8 else "vls"
		var basis := Basis(Vector3.UP, -ac.heading)
		var point := mount.world_position(ac.global_position, ac.heading)
		var opacity := 1.0
		if ac.is_destroyed:
			basis = basis.scaled(Vector3.ONE * ac._destroy_visual_scale)
			point = ac.global_position + (point - ac.global_position) * ac._destroy_visual_scale
			opacity = ac._destroy_visual_alpha
		var transform := Transform3D(basis, world_point(point, AIR_HEIGHT + 8.0))
		_submit(kind, transform, color, Color.TRANSPARENT, opacity)
		last_live_mounts += 1


func _sync_aircraft_mounts(ac: Aircraft, body_transform: Transform3D, airframe_key: String,
		livery: Color, include_equipment: bool = true, opacity: float = 1.0, anchor_height: float = NAN) -> void:
	var native_size: Vector2 = _native_sizes.get(airframe_key, Vector2(34.0, 34.0))
	for mount_kind in Mounts.AIRCRAFT_KINDS:
		var visible_count := Mounts.visible_count(mount_kind, ac)
		if visible_count <= 0:
			continue
		var slots := Mounts.local_slots(mount_kind, native_size.x, native_size.y)
		last_mount_workload += mini(visible_count, slots.size())
		if include_equipment:
			var mount_color := Mounts.state_color(mount_kind, ac, livery)
			for index in mini(visible_count, slots.size()):
				_submit("mount_" + mount_kind,
					body_transform * Transform3D(Basis.IDENTITY, slots[index]), mount_color,
					Color.TRANSPARENT, opacity, anchor_height)
				last_live_mounts += 1
	if airframe_key == "ah64":
		last_mount_workload += 2
		if include_equipment:
			_submit_rotor(body_transform, Vector3(0, 3.15, 0),
				Basis(Vector3.UP, _elapsed * 12.0).scaled(Vector3(16.0, 1.0, 15.8)), livery, opacity, anchor_height)
			var tail_basis := Basis(Vector3.RIGHT, PI * 0.5) * Basis(Vector3.UP, -_elapsed * 15.0)
			_submit_rotor(body_transform, Vector3(0, 1.15, 13.5),
				tail_basis.scaled(Vector3(2.7, 1.0, 2.7)), livery, opacity, anchor_height)
	elif airframe_key == "ch47":
		last_mount_workload += 2
		if include_equipment:
			for rotor_z in [-8.5, 8.5]:
				var direction := -1.0 if rotor_z < 0.0 else 1.0
				_submit_rotor(body_transform, Vector3(0, 4.08, rotor_z),
					Basis(Vector3.UP, _elapsed * 13.0 * direction).scaled(Vector3(13.375, 1.0, 10.25)), livery, opacity, anchor_height)


func _submit_rotor(body_transform: Transform3D, local_position: Vector3,
		local_basis: Basis, livery: Color, opacity: float = 1.0, anchor_height: float = NAN) -> void:
	_submit("mount_rotor", body_transform * Transform3D(local_basis, local_position),
		livery.lerp(Color("c5d0d0"), 0.35), Color.TRANSPARENT, opacity, anchor_height)
	last_live_rotors += 1


func _capture(index: int) -> void:
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var path := "res://bench/results/%s_view_%d.png" % [_scenario, index]
	var result := get_viewport().get_texture().get_image().save_png(path)
	print("[Volume] screenshot=%s result=%d" % [path, result])


func _on_material_warmup_finished(result: Dictionary) -> void:
	material_warm_state=result.duplicate()


func summary() -> String:
	var satellite := "volume satellite=%s\n" % str(_satellite_ground.debug_state()) \
		if is_instance_valid(_satellite_ground) else "volume satellite=disabled\n"
	if is_instance_valid(_weather_volume):
		satellite += _weather_volume.summary()
	return satellite + "volume material_warm="+JSON.stringify(material_warm_state)+"\n" + "volume enabled=%s bodies=%d peak_bodies=%d fallback=%d goose_seen=%s live_mounts=%d live_rotors=%d mount_workload=%d mount_detail_bodies=%d body_lod0=%d body_lod1=%d body_lod2=%d body_lod0_peak=%d body_lod1_peak=%d body_lod2_peak=%d body_lod0_submissions=%d body_lod1_submissions=%d body_lod2_submissions=%d body_lod_switches=%d body_lod_switches_total=%d projection_error_px=%.5f goose_visible_frames=%d\nvolume shared_viewports=1 routes=%d live_batch_nodes=%d model_triangles=%d map_triangles=%d msaa_3d=%d shadows=%s build_ms=%.2f update_avg_us=%.1f\nvolume production_batch_a=%s peak_dedicated_bodies=%d dedicated_visible_frames=%d\n" % [
		bodies_enabled, last_body_count, max_body_count, last_fallback_count, goose_seen, last_live_mounts, last_live_rotors, last_mount_workload, last_mount_detail_bodies,
		last_lod0_bodies, last_lod1_bodies, last_lod2_bodies,
		max_lod0_bodies, max_lod1_bodies, max_lod2_bodies,
		lod0_submissions, lod1_submissions, lod2_submissions,
		last_body_lod_switches, total_body_lod_switches,
		max_projection_error_px, goose_visible_frames, _kinds.size(), _batches.size(), _model_triangles, _map_triangles,
		int(get_viewport().msaa_3d), _sun.shadow_enabled,
		_initial_ms, float(_update_us) / maxf(_updates, 1), _production_batch, max_dedicated_bodies, dedicated_visible_frames]


func _exit_tree() -> void:
	_ground_presenter.restore()
	if _previous_msaa >= 0 and get_viewport().msaa_3d == Viewport.MSAA_2X:
		get_viewport().msaa_3d = _previous_msaa
	for member in _members:
		var raw: Variant = member.get_ref()
		if typeof(raw) == TYPE_OBJECT and is_instance_valid(raw) and raw is Aircraft:
			_set_body_override(raw, false)
	for member in _hidden_layers:
		var raw: Variant = member.get_ref()
		if typeof(raw) == TYPE_OBJECT and is_instance_valid(raw) and raw is CanvasItem:
			raw.show()
