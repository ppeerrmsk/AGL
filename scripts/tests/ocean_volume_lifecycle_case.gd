extends RefCounted
const Overlay := preload("res://scripts/rendering/ocean_volume_overlay.gd")
const Archive := preload("res://scripts/rendering/ocean_volume_archive.gd")
var _fail := 0


func run(parent: Node) -> int:
	var previous := OS.get_environment("AGL_OCEAN_VOLUME")
	OS.set_environment("AGL_OCEAN_VOLUME", "off")
	var host := Node2D.new()
	parent.add_child(host)
	var camera := Camera2D.new()
	host.add_child(camera)
	camera.position = Vector2(-10300, -6500)
	camera.zoom = Vector2.ONE * 0.65
	camera.make_current()
	camera.force_update_scroll()
	var source := MapFeatureRenderer.new()
	source.ugc_vector_only = true
	source.basemap_map_key = "ocean"
	source.basemap_meta_path = Archive.METADATA
	host.add_child(source)
	source.setup(camera, Rect2(-16000, -16000, 32000, 32000))
	var overlay := Overlay.new()
	host.add_child(overlay)
	_check(overlay.setup(source, camera), "bind real raster owner")
	OS.set_environment("AGL_OCEAN_VOLUME", previous)
	await parent.get_tree().create_timer(0.3).timeout
	overlay._process(0.3)
	_check(overlay.debug_state().misses == 0 and overlay.debug_state().planes > 0, "bind actual resident textures")
	# 用正式owner的退役/新增入口，在10Hz复核间隔内换块，不能靠等待掩盖错帧。
	var raster: RasterBasemapRenderer = source._raster_basemap
	raster.set_process(false)
	var ground: Node3D = overlay._ocean_ground
	ground.sync(1.0)
	var scans: int = ground.source_scans
	for frame in 120:
		ground.sync(1.0 / 60.0)
	_check(ground.source_scans == scans, "unchanged owner performs zero snapshot scans across 120 frames")
	var replaced := false
	for record: Dictionary in raster.presentation_tiles():
		if record.lod == &"strategic":
			continue
		var sprite: Sprite2D = record.sprite.get_ref()
		var layer: Node2D = record.layer.get_ref()
		var key := String(sprite.name).trim_prefix(String(record.lod) + "_")
		var identity := sprite.get_instance_id()
		var texture: Texture2D = sprite.texture
		layer.z_index = 0
		ground.sync(0.0)
		_check(ground._planes[identity].material.render_priority == -90, "non-target detail no longer permanently covers target layer")
		layer.z_index = 2
		ground.sync(0.0)
		_check(ground._planes[identity].material.render_priority == -80, "target layer is on top while zooming out")
		var alpha := layer.modulate.a
		layer.modulate.a = 0.375
		ground.sync(0.0)
		_check(is_equal_approx(ground._planes[identity].alpha, sprite.modulate.a * 0.375), "alpha updates without a membership scan")
		_check(ground.source_scans == scans, "alpha and priority changes allocate no membership snapshots")
		layer.modulate.a = alpha
		raster._remove_resident(String(record.lod) + ":" + key)
		_check(not ground._planes.has(identity), "retirement releases borrowed texture before owner reuses slot")
		raster._add_tile(record.lod, key, raster._records[record.lod][key], texture, false)
		ground.sync(0.0)
		var next: Sprite2D = raster._sprites[record.lod][key]
		_check(ground._planes.has(next.get_instance_id()), "new ready tile binds without 100ms delay")
		_check(ground.source_scans == scans + 1, "remove and reinsert require one membership scan")
		layer.z_index = 0
		ground.sync(0.0)
		if ground._planes.has(next.get_instance_id()):
			_check(ground._planes[next.get_instance_id()].material.render_priority == -90, "settled layer priority restored")
		replaced = true
		break
	_check(replaced, "real resident tile exercised replacement assertions")
	raster.set_process(true)
	overlay.covered_raster_enabled = true
	overlay._process(0.3)
	_check(raster.visibility_layer == 0 and raster.is_processing() and raster.visible,
		"covered raster skips only canvas submission, retaining visible flags and live streaming")
	overlay.set_enabled(false)
	_check(raster.visibility_layer == 1, "disabled 3D restores original raster immediately")
	overlay.set_enabled(true)
	overlay._process(0.3)
	_check(raster.visibility_layer == 0, "reactivation requalifies opaque coverage")
	var safe: Rect2 = overlay._opaque_inner_bounds
	overlay._opaque_inner_bounds = Rect2()
	overlay._process(0.3)
	_check(raster.visibility_layer == 1, "unproven edge coverage retains fallback draw")
	overlay._opaque_inner_bounds = safe
	if OS.get_environment("AGL_MAP_CONTACT_AO").to_lower() not in ["off", "0", "false"]:
		_check(overlay._ocean_ground._ao_field != null, "AO shares one field within terrain owner")
	var max_error := 0.0
	for angle: float in [-0.24, 0, 0.24]:
		camera.ignore_rotation = false
		camera.rotation = angle
		camera.force_update_scroll()
		overlay._process(0.3)
		var canvas := source.get_viewport().get_canvas_transform()
		var stretch := source.get_viewport().get_stretch_transform().get_scale()
		for point: Vector2 in [Vector2(-10300, -6500), Vector2(-11000, -7000), Vector2(-9500, -6000)]:
			var actual := overlay._camera.unproject_position(overlay._city.basis * Vector3(point.x, 0, point.y))
			max_error = maxf(max_error, actual.distance_to((canvas * point) * stretch))
	_check(max_error < 0.5, "rotated base anchors retain screen registration")
	source.hide()
	overlay._process(0.3)
	_check(not overlay.debug_state().active, "hidden owner deactivates viewport")
	source.show()
	overlay._process(0.3)
	_check(overlay.debug_state().active, "visible owner reactivates")
	source.queue_free()
	await parent.get_tree().process_frame
	await parent.get_tree().create_timer(0.2).timeout
	overlay._process(0.3)
	_check(not overlay.debug_state().active and overlay.debug_state().planes == 0, "freed owner clears borrowed textures across next tick")
	_check(overlay._ocean_ground._ao_field == null, "freed source releases terrain AO field at next consumer tick")
	camera.queue_free()
	await parent.get_tree().process_frame
	overlay._process(0.3)
	_check(not overlay.debug_state().active, "freed camera reaches consumer end safely")
	var viewport_ref: WeakRef = weakref(overlay._viewport)
	var overlay_ref: WeakRef = weakref(overlay)
	host.queue_free()
	await parent.get_tree().process_frame
	_check(overlay_ref.get_ref() == null and viewport_ref.get_ref() == null, "owner exit releases map and render target")
	print("[Ocean lifecycle] fail=", _fail, " projection_error_px=", max_error)
	return _fail


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fail += 1
		push_error("Ocean lifecycle: " + label)
