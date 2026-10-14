extends Node2D
## 地图层的原生分辨率静态合成；不接管飞机、天气、输入或地理查询。
const Archive := preload("res://scripts/rendering/tokyo_volume_archive.gd")
const VolumeProjection := preload("res://scripts/experiments/volume_projection.gd")
const SHADER := preload("res://resources/shaders/tokyo_volume_surface.gdshader")
const COMPOSITE_SHADER := preload("res://resources/shaders/tokyo_volume_composite.gdshader")
const TILT := 38.0 * PI / 180.0
const TRANSITION_SECONDS := 0.20
const ENV_OVERRIDE := "AGL_TOKYO_VOLUME"
var _source_ref: WeakRef
var _camera_ref: WeakRef
var _archive: Resource
var _viewport: SubViewport
var _screen: Sprite2D
var _composite := ShaderMaterial.new()
var _camera: Camera3D
var _city: Node3D
var _sun: DirectionalLight3D
var _current: Array[MeshInstance3D] = []
var _old: Array[MeshInstance3D] = []
var _materials: Array[ShaderMaterial] = []
var _fixed: Array[MeshInstance3D] = []
var _level := -1
var _previous_level := -1
var _blend := 1.0
var _last_canvas := Transform2D(0, Vector2(INF, INF))
var _last_size := Vector2.ZERO
var _active := false
var _lod_clock := 0.0
var _enabled := true
var redraws := 0
var lod_switches := 0
var max_transition_triangles := 0
var setup_ms := 0.0
var _warm_until_frame := -1


static func default_enabled(map_key: String, vector_only: bool = false) -> bool:
	return map_key == "tokyo" and not vector_only \
		and OS.get_environment(ENV_OVERRIDE).to_lower() not in ["off", "0", "false", "2d"] \
		and ResourceLoader.exists(Archive.PATH)


func setup(source: Node2D, camera: Camera2D) -> bool:
	var started := Time.get_ticks_usec()
	_archive = _load_archive()
	if _archive == null or not _archive.valid():
		return false
	# 校验成功才创建 Node，损坏归档走二维回退时不留下无父节点资源。
	_viewport = SubViewport.new()
	_screen = Sprite2D.new()
	_camera = Camera3D.new()
	_city = Node3D.new()
	_sun = DirectionalLight3D.new()
	_source_ref = weakref(source)
	_camera_ref = weakref(camera)
	z_as_relative = false
	z_index = -45
	top_level = true
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1100
	_viewport.name = "TokyoMapNativeViewport"
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.gui_disable_input = true
	_viewport.handle_input_locally = false
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)
	_screen.name = "TokyoMapComposite"
	_screen.centered = false
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_screen.texture = _viewport.get_texture()
	_composite.shader = COMPOSITE_SHADER
	_composite.set_shader_parameter("bounds", Vector4(_archive.bounds.position.x, _archive.bounds.position.y, _archive.bounds.end.x, _archive.bounds.end.y))
	_screen.material = _composite
	add_child(_screen)
	_viewport.add_child(_city)
	_viewport.add_child(_camera)
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.make_current()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0, 0, 0, 0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	_camera.environment = environment
	_sun.rotation_degrees = Vector3(-50, -35, 0)
	_sun.light_energy = 0.8
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_fade_start = 1.0
	_sun.shadow_bias = 0.035
	_sun.shadow_normal_bias = 1.1
	_viewport.add_child(_sun)
	for index in 5:
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("facade_detail", index in [1, 3])
		material.set_shader_parameter("outgoing", index in [2, 3])
		_materials.append(material)
	_setup_geometry()
	# 入场阶段隐式绘制两帧，预分配原生 RT / 编译阴影；不把首次成本推迟到玩家平移入区。
	_warm_until_frame = Engine.get_process_frames() + 2
	_process(0.0)
	setup_ms = (Time.get_ticks_usec() - started) / 1000.0
	return true


func _load_archive() -> Resource:
	return load(Archive.PATH)


func _presentation_bounds() -> Rect2:
	return _archive.bounds.grow(350)


func _should_prewarm() -> bool:
	return Engine.get_process_frames() <= _warm_until_frame


func _setup_geometry() -> void:
	for index in 2:
		_current.append(_add_mesh(null, _materials[index], true))
		_old.append(_add_mesh(null, _materials[index + 2], true))
		_old[index].hide()
	for mesh: ArrayMesh in [_archive.ground, _archive.roads, _archive.rails]:
		_fixed.append(_add_mesh(mesh, _materials[4], false))


func _add_mesh(mesh: ArrayMesh, material: ShaderMaterial, casts_shadow: bool) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_city.add_child(instance)
	return instance


func _process(delta: float) -> void:
	# 只在 bench 帧追踪开启时计时；包含全部提前返回，子桶不重复计入根桶。
	var trace := PerfBuckets.frame_trace_enabled
	var start := Time.get_ticks_usec() if trace else 0
	_process_map(delta)
	if trace:
		PerfBuckets.tick("tokyo_map_process", Time.get_ticks_usec() - start)


func _process_map(delta: float) -> void:
	var source: Variant = _source_ref.get_ref() if _source_ref != null else null
	var camera: Variant = _camera_ref.get_ref() if _camera_ref != null else null
	if typeof(source) != TYPE_OBJECT or not is_instance_valid(source) \
			or typeof(camera) != TYPE_OBJECT or not is_instance_valid(camera):
		_deactivate()
		return
	if not _enabled or not source.is_visible_in_tree() \
			or source.get("vector_preview_enabled") == true:
		_deactivate()
		return
	var owner_view := source.get_viewport() as Viewport
	var canvas := owner_view.get_canvas_transform()
	var logical := owner_view.get_visible_rect().size
	var output := logical * owner_view.get_stretch_transform().get_scale()
	if owner_view is SubViewport:
		output = Vector2(owner_view.size)
	output = Vector2(maxf(1, roundf(output.x)), maxf(1, roundf(output.y)))
	var inverse := canvas.affine_inverse()
	var view_bounds := Rect2(inverse * Vector2.ZERO, Vector2.ZERO)
	for corner: Vector2 in [Vector2(logical.x, 0), logical, Vector2(0, logical.y)]:
		view_bounds = view_bounds.expand(inverse * corner)
	# 外扩保留高楼侧面和斜向长影，不只按建筑中心裁掉边缘高楼。
	var prewarming := false
	if not _presentation_bounds().intersects(view_bounds):
		if not _should_prewarm():
			_deactivate()
			return
		prewarming = true
		canvas.origin = logical * 0.5 - canvas.basis_xform(_archive.bounds.get_center())
		inverse = canvas.affine_inverse()
		view_bounds = Rect2(inverse * Vector2.ZERO, Vector2.ZERO)
		for corner: Vector2 in [Vector2(logical.x, 0), logical, Vector2(0, logical.y)]:
			view_bounds = view_bounds.expand(inverse * corner)
	var changed := not _active or not canvas.is_equal_approx(_last_canvas) or output != _last_size
	_active = not prewarming
	_screen.visible = not prewarming
	_lod_clock -= delta
	var trace := PerfBuckets.frame_trace_enabled
	var camera_start := Time.get_ticks_usec() if trace else 0
	if changed:
		global_transform = inverse
		_composite.set_shader_parameter("world_origin", inverse.origin)
		_composite.set_shader_parameter("world_dx", inverse.basis_xform(Vector2(logical.x, 0)))
		_composite.set_shader_parameter("world_dy", inverse.basis_xform(Vector2(0, logical.y)))
		_screen.scale = logical / output
		_viewport.size = Vector2i(output)
		var ground_basis := VolumeProjection.ground_basis(canvas, TILT)
		var camera_basis := VolumeProjection.camera_basis(canvas, TILT)
		var center := inverse * (logical * 0.5)
		# 平移/缩放不改变地面基；避免给全部静态实例传播相同变换。
		if not _city.basis.is_equal_approx(ground_basis): _city.basis = ground_basis
		var scale_value := canvas.x.length() * output.x / logical.x
		_camera.size = output.y / scale_value
		_camera.transform = Transform3D(camera_basis,
			ground_basis * Vector3(center.x, 0, center.y) + camera_basis.z * 50000.0)
		_configure_camera_depth(camera_basis)
		_last_canvas = canvas
		_last_size = output
		if trace:
			PerfBuckets.tick("tokyo_map_camera", Time.get_ticks_usec() - camera_start)
	var geometry_start := Time.get_ticks_usec() if trace else 0
	if _step_geometry(view_bounds, canvas.x.length() * output.x / logical.x, delta):
		changed = true
	if trace:
		PerfBuckets.tick("tokyo_map_geometry", Time.get_ticks_usec() - geometry_start)
	if changed:
		var submit_start := Time.get_ticks_usec() if trace else 0
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		redraws += 1
		if trace:
			# 这里只量 CPU 更新请求，不冒充 GPU 完成时间；不加同步等待。
			PerfBuckets.tick("tokyo_map_update_request", Time.get_ticks_usec() - submit_start)


func _configure_camera_depth(_camera_basis: Basis) -> void:
	var span := _camera.size * 0.65 + 1200.0
	_camera.near = maxf(0.1, 50000.0 - span)
	_camera.far = 50000.0 + span
	_sun.directional_shadow_max_distance = _camera.far


func _step_geometry(_view_bounds: Rect2, scale_value: float, delta: float) -> bool:
	var changed := false
	if _lod_clock <= 0.0:
		_lod_clock = 0.10
		var next := Archive.choose_level(_level, scale_value)
		if next != _level and _blend >= 1.0:
			_switch_level(next)
			changed = true
	if _blend < 1.0:
		_blend = minf(1.0, _blend + delta / TRANSITION_SECONDS)
		for index in 4:
			_materials[index].set_shader_parameter("lod_mix", _blend)
		if _blend >= 1.0:
			for instance in _old:
				instance.hide()
		changed = true
	return changed


func _switch_level(next: int) -> void:
	_previous_level = _level
	if _level >= 0:
		for index in 2:
			_old[index].mesh = _current[index].mesh
			_old[index].cast_shadow = _current[index].cast_shadow
			_old[index].show()
	var entry: Dictionary = _archive.levels[next]
	_current[0].mesh = entry.low
	_current[1].mesh = entry.known
	_current[0].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if next >= 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_current[1].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if next >= 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var peak := int(entry.triangles)
	if _level >= 0:
		peak += int(_archive.levels[_level].triangles)
	max_transition_triangles = maxi(max_transition_triangles, peak)
	_blend = 0.0 if _level >= 0 and peak <= 324000 else 1.0
	for index in 4:
		_materials[index].set_shader_parameter("lod_mix", _blend)
	if _blend >= 1.0:
		for instance in _old:
			instance.hide()
	_level = next
	lod_switches += 1


func _deactivate() -> void:
	if is_instance_valid(_screen):
		_screen.hide()
	if is_instance_valid(_viewport):
		_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_active = false


func set_enabled(enabled: bool) -> void:
	_enabled = enabled
	if not enabled:
		_deactivate()


func debug_state() -> Dictionary:
	return {"active": _active, "enabled": _enabled, "level": _level,
		"previous_level": _previous_level, "blend": _blend, "lod_switches": lod_switches,
		"redraws": redraws, "nodes": _city.get_child_count() if is_instance_valid(_city) else 0, "materials": _materials.size() + 1,
		"output_size": _viewport.size if is_instance_valid(_viewport) else Vector2i.ZERO, "setup_ms": setup_ms,
		"triangles": int(_archive.levels[_level].triangles) if _archive != null and _level >= 0 else 0,
		"counts": _archive.levels[_level].counts if _archive != null and _level >= 0 else [],
		"max_transition_triangles": max_transition_triangles}
