extends Node3D
## 东京站—丸之内小片的独立视觉样张；不修改正式地图入口、点击或玩法权威。

const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const MapFactory := preload("res://scripts/experiments/volume_map_factory.gd")
const PreviewFactory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const SatelliteGround := preload("res://scripts/experiments/tokyo_preview_ground.gd")
const SurfaceShader := preload("res://resources/shaders/tokyo_preview_surface.gdshader")
const Archive := preload("res://scripts/experiments/volume_terrain_archive.gd")
const VolumeProjection := preload("res://scripts/experiments/volume_projection.gd")
const TOKYO_TILT := 38.0 * PI / 180.0

const CAPTURE_SIZE := Vector2i(1600, 900)
const DEFAULT_CENTER := Vector2(300.0, -13300.0)
const CLOSE_CENTER := Vector2(330.0, -13420.0)
const OUTPUT_PREFIX := "res://bench/results/tokyo_volume_r3_"
@export var city_data_path := PreviewFactory.DATA_PATH
@export var ground_data_path := PreviewFactory.GROUND_PATH
@export var output_prefix := OUTPUT_PREFIX
@export var preview_center := DEFAULT_CENTER
@export var close_center := CLOSE_CENTER
@export var overview_zoom := 0.98
@export var inspect_original_station := false
@export var region_archive_path := ""

var _camera := Camera3D.new()
var _sun := DirectionalLight3D.new()
var _raster_camera := Camera2D.new()
var _raster_source := RasterBasemapRenderer.new()
var _map_root := Node3D.new()
var _ground := SatelliteGround.new()
var _geometry_root := Node3D.new()
var _packet: Dictionary = {}
var _previous_msaa := -1


func _ready() -> void:
	_previous_msaa = get_viewport().msaa_3d
	if _previous_msaa < Viewport.MSAA_4X:
		get_viewport().msaa_3d = Viewport.MSAA_4X
	DisplayServer.window_set_size(CAPTURE_SIZE)
	_configure_environment()
	add_child(_camera)
	_camera.make_current()
	MapFactory.configure_sun(_sun)
	_sun.directional_shadow_max_distance = 6000.0
	_sun.shadow_bias = 0.035
	_sun.shadow_normal_bias = 1.1
	add_child(_sun)
	_raster_camera.position = preview_center
	_raster_camera.zoom = Vector2.ONE * 0.98
	_raster_camera.enabled = false
	add_child(_raster_camera)
	add_child(_raster_source)
	_raster_source.hide()
	var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/maps/tokyo_bay_bg.json"))
	if not _raster_source.setup(_raster_camera, Archive.source_rect(metadata), "tokyo"):
		push_error("Tokyo volume preview could not initialize the official tile renderer")
		get_tree().quit(1)
		return
	_map_root.name = "TokyoVolumePreview"
	add_child(_map_root)
	_map_root.add_child(_ground)
	_geometry_root.name = "StaticCityBatches"
	_map_root.add_child(_geometry_root)
	if not _load_geometry():
		get_tree().quit(1)
		return
	_set_view(preview_center, overview_zoom)
	set_process(false)
	print("[TokyoVolumePreview] %s" % _packet)
	if get_tree().has_meta("bench_mode"):
		_capture_sequence.call_deferred()


func _load_geometry() -> bool:
	var region_archive: Resource = null
	if not region_archive_path.is_empty():
		region_archive = load(region_archive_path)
		if region_archive == null or not region_archive.valid():
			return false
		_packet = region_archive.packet()
	else:
		_packet = PreviewFactory.build(city_data_path)
	if not bool(_packet.get("ok", false)):
		push_error("Tokyo volume preview mesh failed: %s" % String(_packet.get("reason", "unknown")))
		return false
	_add_batch("FallbackLowBuildings", _packet.low_mesh, true)
	_add_batch("KnownHeightBuildings", _packet.known_mesh, true)
	_add_batch("CrispRoadNetwork", _packet.road_mesh, false)
	_add_batch("CrispRailNetwork", _packet.rail_mesh, false)
	_add_batch("ReconstructedGround", region_archive.meshes[4] if region_archive != null else PreviewFactory.build_ground(ground_data_path), false)
	return true


func _exit_tree() -> void:
	if _previous_msaa >= 0 and is_instance_valid(get_viewport()):
		get_viewport().msaa_3d = _previous_msaa


func _configure_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("17242a")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c9d9e5")
	environment.ambient_light_energy = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_camera.environment = environment
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 48000.0
	_camera.far = 52000.0
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT


func _add_batch(name_value: String, mesh: ArrayMesh, casts_shadow: bool) -> void:
	var instance := MeshInstance3D.new()
	instance.name = name_value
	instance.mesh = mesh
	var material := ShaderMaterial.new()
	material.shader = SurfaceShader
	material.set_shader_parameter("facade_detail", name_value == "KnownHeightBuildings")
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts_shadow \
		else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_geometry_root.add_child(instance)


func _set_view(center: Vector2, zoom_value: float) -> void:
	_raster_camera.position = center
	_raster_camera.zoom = Vector2.ONE * zoom_value
	var canvas := Transform2D.IDENTITY.scaled_local(Vector2.ONE * zoom_value)
	var ground_basis := VolumeProjection.ground_basis(canvas, TOKYO_TILT)
	var view_basis := VolumeProjection.camera_basis(canvas, TOKYO_TILT)
	_map_root.basis = ground_basis
	_camera.size = float(CAPTURE_SIZE.y) / zoom_value
	_camera.transform = Transform3D(
		view_basis,
		ground_basis * Vector3(center.x, 0.0, center.y) + view_basis.z * 50000.0)
	var span := _camera.size * 0.65 + 1200.0
	_camera.near = 50000.0 - span
	_camera.far = 50000.0 + span
	_sun.directional_shadow_max_distance = _camera.far


func _capture_sequence() -> void:
	var failed := false
	var captures: Array[Dictionary] = []
	_set_view(preview_center, overview_zoom)
	failed = await _settle() or failed
	failed = await _capture("overview_%03d" % roundi(overview_zoom * 100), preview_center, overview_zoom, true, captures) or failed
	_geometry_root.hide()
	failed = await _capture("tile_baseline_%03d" % roundi(overview_zoom * 100), preview_center, overview_zoom, true, captures) or failed
	_geometry_root.show()
	_set_view(close_center, 1.35)
	failed = await _settle() or failed
	failed = await _capture("close_135", close_center, 1.35, true, captures) or failed
	_sun.shadow_enabled = false
	failed = await _capture("close_135_no_shadow", close_center, 1.35, false, captures) or failed
	_sun.shadow_enabled = true
	_set_view(close_center, 2.20)
	failed = await _settle() or failed
	failed = await _capture("street_detail_220", close_center, 2.20, true, captures) or failed
	if inspect_original_station:
		_set_view(CLOSE_CENTER, 2.2)
		failed = await _settle() or failed
		failed = await _capture("station_220", CLOSE_CENTER, 2.2, true, captures) or failed
	var report := {
		"schema_version": 1,
		"status": "regional candidate; unresolved source issues are not graduation evidence",
		"engine": Engine.get_version_info().get("string", "unknown"),
		"projection_tilt_degrees": rad_to_deg(TOKYO_TILT),
		"capture_size": [CAPTURE_SIZE.x, CAPTURE_SIZE.y],
		"source_data": region_archive_path if not region_archive_path.is_empty() else city_data_path,
		"deferred_buildings": _packet.deferred_buildings,
		"part_assembly_outlines": _packet.part_assembly_outlines,
		"source_buildings": _packet.source_buildings,
		"fallback_buildings": _packet.fallback_buildings,
		"known_height_buildings": _packet.known_height_buildings,
		"highrises": _packet.highrises,
		"roads": _packet.roads,
		"rails": _packet.rails,
		"triangle_counts": _packet.triangle_counts,
		"triangles": _packet.triangles,
		"ground_triangles": (_geometry_root.get_node("ReconstructedGround") as MeshInstance3D).mesh.surface_get_array_len(0) / 3,
		"batch_nodes": _geometry_root.get_child_count(),
		"captures": captures,
	}
	var file := FileAccess.open(output_prefix + "manifest.json", FileAccess.WRITE)
	if file == null:
		failed = true
	else:
		file.store_string(JSON.stringify(report, "\t") + "\n")
		file.close()
	print("[TokyoVolumePreview] capture report=%s failed=%s" % [report, failed])
	get_tree().quit(1 if failed else 0)


func _settle() -> bool:
	await get_tree().create_timer(4.0).timeout
	await RenderingServer.frame_post_draw
	var state: Dictionary = _raster_source.debug_state()
	var ready := String(state.get("current_lod", "")) == "detail" \
		and String(state.get("target_lod", "")) == "detail" \
		and int(state.get("resident_tiles", 0)) > 0 \
		and int(state.get("pending_count", 0)) == 0 \
		and (state.get("missing_keys", []) as Array).is_empty()
	if not ready:
		push_error("Tokyo volume preview Detail tiles did not settle: %s" % state)
	_ground.snapshot(_raster_source)
	return not ready


func _capture(id: String, center: Vector2, zoom_value: float,
		shadows: bool, output: Array[Dictionary]) -> bool:
	for _frame in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := output_prefix + id + ".png"
	var capture_image := get_viewport().get_texture().get_image()
	var error := capture_image.save_png(path)
	var logical_size := get_viewport().get_visible_rect().size
	var actual_size := Vector2(capture_image.get_size())
	var max_projection_error := 0.0
	for offset: Vector2 in [Vector2.ZERO, Vector2(-200, -150), Vector2(200, -150), Vector2(-200, 150), Vector2(200, 150)]:
		var point := center + offset
		var actual := _camera.unproject_position(_map_root.to_global(Vector3(point.x, 0, point.y))) * actual_size / logical_size
		var expected := actual_size * 0.5 + offset * zoom_value
		max_projection_error = maxf(max_projection_error, actual.distance_to(expected))
	if max_projection_error > 0.5:
		push_error("Tokyo preview ground projection exceeds 0.5 px: %f" % max_projection_error)
	output.append({
		"id": id,
		"file": path.get_file(),
		"center": [center.x, center.y],
		"zoom": zoom_value,
		"shadows": shadows,
		"max_ground_projection_error_px": max_projection_error,
		"tile_state": _raster_source.debug_state(),
	})
	print("[TokyoVolumePreview] capture %s result=%d" % [path, error])
	return error != OK or max_projection_error > 0.5
