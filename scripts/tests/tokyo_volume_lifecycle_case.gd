extends RefCounted
const Overlay := preload("res://scripts/rendering/tokyo_volume_overlay.gd")
var _fail := 0


func run(parent: Node) -> int:
	var host := Node2D.new()
	parent.add_child(host)
	var unconfigured := Overlay.new()
	host.add_child(unconfigured)
	unconfigured._process(0.3)
	_check(not unconfigured.debug_state().active and unconfigured.debug_state().nodes == 0, "unconfigured fallback creates no orphan nodes")
	unconfigured.queue_free()
	var camera := Camera2D.new()
	host.add_child(camera)
	camera.position = Vector2(300, -13300)
	camera.zoom = Vector2.ONE
	camera.make_current()
	camera.force_update_scroll()
	var source := MapFeatureRenderer.new()
	host.add_child(source)
	# 直接绑源，避免 fixture 自行 setup 又创建第二个地图 overlay。
	var overlay := Overlay.new()
	host.add_child(overlay)
	_check(overlay.setup(source, camera), "live source and camera bind")
	await parent.get_tree().process_frame
	overlay._process(0.3)
	var initial: Dictionary = overlay.debug_state()
	_check(initial.active and initial.nodes == 7 and initial.materials == 6, "native bounded city batches")
	var redraws: int = overlay.redraws
	for index in 4:
		overlay._process(0.11)
	_check(overlay.redraws == redraws, "stationary camera does not redraw")
	source.hide()
	overlay._process(0.3)
	_check(not overlay.debug_state().active, "hidden source hides composite")
	source.show()
	source.vector_preview_enabled = true
	overlay._process(0.3)
	_check(not overlay.debug_state().active, "vector inspection excludes volume")
	source.vector_preview_enabled = false
	var max_error := 0.0
	for zoom_value: float in [0.06, 0.13, 0.26, 0.52, 0.98, 2.2, 5.0]:
		for angle: float in [-0.244346, 0.0, 0.244346]:
			camera.zoom = Vector2.ONE * zoom_value
			camera.rotation = angle
			camera.force_update_scroll()
			overlay._process(0.3)
			var canvas := source.get_viewport().get_canvas_transform()
			var stretch := source.get_viewport().get_stretch_transform().get_scale()
			for anchor: Vector2 in [Vector2(300, -13300), Vector2(-400, -13750), Vector2(1000, -13750), Vector2(-400, -12850), Vector2(1000, -12850)]:
				var actual := overlay._camera.unproject_position(overlay._city.basis * Vector3(anchor.x, 0, anchor.y))
				max_error = maxf(max_error, actual.distance_to((canvas * anchor) * stretch))
	_check(max_error <= 0.5, "ground anchors align across zoom and rotation")
	print("[Tokyo projection] max_error_px=", max_error)
	camera.rotation = 0
	camera.zoom = Vector2.ONE
	camera.force_update_scroll()
	overlay._process(0.3)
	overlay.set_enabled(false)
	_check(not overlay.debug_state().active, "explicit disabled stops viewport")
	overlay.set_enabled(true)
	overlay._process(0.3)
	_check(overlay.debug_state().active, "reactivation redraws source")
	camera.position = Vector2(8000, 8000)
	camera.force_update_scroll()
	overlay._process(0.3)
	_check(not overlay.debug_state().active, "outside built district stops viewport")
	camera.position = Vector2(300, -13300)
	camera.zoom = Vector2.ONE * 0.06
	camera.force_update_scroll()
	overlay._process(0.3)
	_check(int(overlay.debug_state().level) <= 1, "far view switches actual mesh")
	source.queue_free()
	await parent.get_tree().process_frame
	overlay._process(0.3)
	_check(not overlay.debug_state().active, "freed source safely deactivates next consumer tick")
	camera.queue_free()
	await parent.get_tree().process_frame
	overlay._process(0.3)
	_check(not overlay.debug_state().active, "freed camera safely reaches end")
	var retained: Variant = overlay._viewport
	host.queue_free()
	await parent.get_tree().process_frame
	_check(not is_instance_valid(retained), "owner teardown releases child viewport")
	print("[Tokyo lifecycle] fail=", _fail)
	return _fail


func _check(ok: bool, label: String) -> void:
	if not ok:
		_fail += 1
		push_error("Tokyo lifecycle: " + label)
