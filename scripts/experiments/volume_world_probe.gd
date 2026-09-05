extends Node3D
## 只读表现适配器；正式单位继续拥有物理、AI、伤害、装备与终态。
const Factory := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Airframes := preload("res://scripts/experiments/volume_aircraft_catalog.gd")
const MapFactory := preload("res://scripts/experiments/volume_map_factory.gd")
const Renderer := preload("res://scripts/aircraft_renderer.gd")
const Catalog := preload("res://scripts/aircraft_silhouette_catalog.gd")
const MAP_PATH := "res://resources/maps/desert_railway_preview.aglmap"
const BODY_META := &"volume_3d_body"
const AIR_HEIGHT := 600.0
const KINDS := ["fighter", "a10", "f14", "f47", "mother_goose", "prop", "vls"]
const BASELINE_KINDS := ["fighter", "a10", "mother_goose", "prop", "vls"]

var _mode_ref: WeakRef
var _camera := Camera3D.new()
var _sun := DirectionalLight3D.new()
var _root_map := MeshInstance3D.new()
var _batches: Dictionary = {}
var _counts: Dictionary = {}
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
var goose_visible_frames := 0
var _update_us := 0
var _updates := 0
var _initial_ms := 0.0
var _model_triangles := 0
var _map_triangles := 0
var _production_batch := true
var _kinds: Array = KINDS
var max_dedicated_bodies := 0
var dedicated_visible_frames := 0


func setup(mode: Node, scenario: String) -> void:
	var started := Time.get_ticks_usec()
	_mode_ref = weakref(mode)
	_scenario = scenario
	_production_batch = not scenario.contains("_baseline_")
	_kinds = KINDS if _production_batch else BASELINE_KINDS
	bodies_enabled = scenario.begins_with("volume_3d_")
	process_priority = 1000
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("777a67")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c9d9e5")
	environment.ambient_light_energy = 0.35
	_camera.environment = environment
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 0.1
	_camera.far = 100000.0
	add_child(_camera)
	_camera.make_current()
	_sun.rotation_degrees = Vector3(-58, -30, 0)
	_sun.light_energy = 0.8
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 80000.0
	add_child(_sun)
	var shared_material := Factory.material()
	var doc := MapDocument.load_from(MAP_PATH)
	assert(doc != null, "volume map document must load")
	if _production_batch:
		var map_packet := MapFactory.build(doc)
		assert(map_packet.get("ok", false), "volume map build failed: " + String(map_packet.get("reason", "")))
		_root_map.mesh = map_packet.mesh
	else:
		_root_map.mesh = Factory.map_mesh(doc)
	_root_map.material_override = shared_material
	_map_triangles = _root_map.mesh.surface_get_array_len(0) / 3
	add_child(_root_map)
	for kind in _kinds:
		var batch := MultiMeshInstance3D.new()
		batch.multimesh = MultiMesh.new()
		batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		batch.multimesh.use_colors = true
		batch.multimesh.mesh = Airframes.build(kind) if _production_batch and kind in Airframes.supported_keys() else Factory.aircraft(kind)
		batch.multimesh.instance_count = 128
		batch.multimesh.visible_instance_count = 0
		batch.material_override = shared_material
		_model_triangles += batch.multimesh.mesh.surface_get_array_len(0) / 3
		add_child(batch)
		_batches[kind] = batch
		_counts[kind] = 0
	# 只停掉被替换的地图绘制，不销毁其玩法查询数据，也不隐藏天气/单位/UI。
	for property in ["_map_features", "_building_renderer"]:
		var layer: Variant = mode.get(property)
		if typeof(layer) == TYPE_OBJECT and is_instance_valid(layer) and layer is CanvasItem and layer.visible:
			_hidden_layers.append(weakref(layer))
			layer.hide()
	_initial_ms = float(Time.get_ticks_usec() - started) / 1000.0
	print("[Volume] enabled=%s map=desert-document batch_a=%s meshes=%d build_ms=%.2f" % [bodies_enabled, _production_batch, _kinds.size(), _initial_ms])
	_refresh_members()
	_process(0.0)


func _refresh_members() -> void:
	_members.clear()
	for raw: Variant in CombatUnit.all_units:
		if typeof(raw) == TYPE_OBJECT and is_instance_valid(raw) and raw is Aircraft:
			_members.append(weakref(raw))
			if String(raw.get_meta("silhouette", "")) == "mother_goose":
				_goose_ref = weakref(raw)


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
	var viewport := get_viewport()
	var canvas := viewport.canvas_transform
	var inverse := canvas.affine_inverse()
	var viewport_size := viewport.get_visible_rect().size
	_camera.size = viewport_size.y * inverse.y.length()
	_camera.transform = Transform3D(camera_basis(canvas), world_point(inverse * (viewport_size * 0.5), 50000.0))


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
	for kind in _kinds:
		_counts[kind] = 0
	var dedicated_bodies := 0
	last_body_count = 0
	last_fallback_count = 0
	last_live_mounts = 0
	var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).grow(250.0)
	for member in _members:
		var raw: Variant = member.get_ref()
		if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not (raw is Aircraft):
			continue
		var ac: Aircraft = raw
		var is_goose := String(ac.get_meta("silhouette", "")) == "mother_goose"
		var supported := not ac.has_meta("category") or String(ac.get_meta("category", "")) != "boss" or is_goose
		# 尚未做旋翼结构时保持原来的直升机，不能将它替换为喷气机冒充覆盖。
		supported = supported and not Catalog.key_for(ac) in ["ah64", "ch47"] \
			and not String(ac.get_meta("silhouette", "")) in ["apache", "chinook"]
		# 渐隐沿用旧透明路径，避免三维不透明材质泄露隐身/传感器状态。
		var opaque := ac.is_visible_in_tree() and not ac.sensor_hidden and not ac.is_destroyed \
			and ac._cloak_alpha >= 0.999 and ac._sensor_contact_visual_alpha >= 0.999 \
			and ac.self_modulate.a >= 0.999 and ac.modulate.a >= 0.999 and not ac.is_hidden_from_player_sensors()
		var screen_point := ac.get_global_transform_with_canvas().origin
		var key_unit := is_goose or ac == Renderer.safe_player_ref() or String(ac.get_meta("enemy_type", "")) == "uav_commander"
		var active := bodies_enabled and supported and opaque and (key_unit or view.has_point(screen_point))
		_set_body_override(ac, active)
		if not active:
			last_fallback_count += 1
			continue
		var silhouette_key := Catalog.key_for(ac)
		var kind := "mother_goose" if is_goose else (silhouette_key if silhouette_key in ["a10", "f14", "f47"] else "fighter")
		if not _production_batch and kind in ["f14", "f47"]:
			kind = "fighter"
		var scale_value := Renderer.altitude_base_scale(ac) * Renderer.visual_model_scale(ac)
		if not is_goose:
			scale_value *= Catalog.draw_scale_for(ac)
		var bank := ac.bank_angle + ac._evade_roll_phase + ac._active_special_roll_visual
		var basis := Basis(Vector3.UP, -ac.heading) * Basis(Vector3.FORWARD, bank)
		basis = basis.scaled(Vector3.ONE * scale_value)
		var transform := Transform3D(basis, world_point(ac.global_position, AIR_HEIGHT))
		var color := ac.params.icon_color if ac.params else Color.WHITE
		_submit(kind, transform, color)
		if _production_batch and kind in ["a10", "f14", "f47"]:
			dedicated_bodies += 1
			if get_viewport().get_visible_rect().has_point(screen_point):
				dedicated_visible_frames += 1
		last_body_count += 1
		max_projection_error_px = maxf(max_projection_error_px,
			_camera.unproject_position(transform.origin).distance_to(screen_point))
		if is_goose:
			goose_seen = true
			if get_viewport().get_visible_rect().has_point(screen_point):
				goose_visible_frames += 1
			_sync_goose_mounts(ac, color)
	for kind in _kinds:
		var batch: MultiMeshInstance3D = _batches[kind]
		batch.multimesh.visible_instance_count = int(_counts[kind])
	max_body_count = maxi(max_body_count, last_body_count)
	max_dedicated_bodies = maxi(max_dedicated_bodies, dedicated_bodies)
	_update_us += Time.get_ticks_usec() - started
	_updates += 1
	# 性能窗口内不读回/编码截图；BenchRunner 封存结果后才采集终帧。


static func _set_body_override(ac: Aircraft, active: bool) -> void:
	if ac.has_meta(BODY_META) == active:
		return
	if active:
		ac.set_meta(BODY_META, true)
	else:
		ac.remove_meta(BODY_META)
	ac.queue_redraw()


func _submit(kind: String, transform: Transform3D, color: Color) -> void:
	var batch: MultiMeshInstance3D = _batches[kind]
	var index := int(_counts[kind])
	if index >= batch.multimesh.instance_count:
		batch.multimesh.instance_count *= 2
		# 容量增长应在成员刷新期预留；异常峰值显式失败，不能悄悄截断单位。
		push_error("Volume batch capacity exceeded; prewarm larger capacity before comparing performance")
	batch.multimesh.set_instance_transform(index, transform)
	batch.multimesh.set_instance_color(index, color)
	_counts[kind] = index + 1


func _sync_goose_mounts(ac: Aircraft, color: Color) -> void:
	var mounts: Array = ac.get_meta(&"mg_mounts", [])
	for i in mounts.size():
		var raw: Variant = mounts[i]
		if typeof(raw) != TYPE_OBJECT or not is_instance_valid(raw) or not (raw is WeaponMount):
			continue
		var mount: WeaponMount = raw
		if mount.destroyed:
			continue
		var kind := "prop" if i < 8 else "vls"
		var basis := Basis(Vector3.UP, -ac.heading)
		var transform := Transform3D(basis, world_point(mount.world_position(ac.global_position, ac.heading), AIR_HEIGHT + 8.0))
		_submit(kind, transform, color)
		last_live_mounts += 1


func _capture(index: int) -> void:
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var path := "res://bench/results/%s_view_%d.png" % [_scenario, index]
	var result := get_viewport().get_texture().get_image().save_png(path)
	print("[Volume] screenshot=%s result=%d" % [path, result])


func summary() -> String:
	return "volume enabled=%s bodies=%d peak_bodies=%d fallback=%d goose_seen=%s live_mounts=%d projection_error_px=%.5f goose_visible_frames=%d\nvolume shared_viewports=1 batches=%d model_triangles=%d map_triangles=%d shadows=%s build_ms=%.2f update_avg_us=%.1f\nvolume production_batch_a=%s peak_dedicated_bodies=%d dedicated_visible_frames=%d\n" % [
		bodies_enabled, last_body_count, max_body_count, last_fallback_count, goose_seen, last_live_mounts,
		max_projection_error_px, goose_visible_frames, _kinds.size(), _model_triangles, _map_triangles, _sun.shadow_enabled,
		_initial_ms, float(_update_us) / maxf(_updates, 1), _production_batch, max_dedicated_bodies, dedicated_visible_frames]


func _exit_tree() -> void:
	for member in _members:
		var raw: Variant = member.get_ref()
		if typeof(raw) == TYPE_OBJECT and is_instance_valid(raw) and raw is Aircraft:
			_set_body_override(raw, false)
	for member in _hidden_layers:
		var raw: Variant = member.get_ref()
		if typeof(raw) == TYPE_OBJECT and is_instance_valid(raw) and raw is CanvasItem:
			raw.show()
