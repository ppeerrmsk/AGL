extends Node2D
## 真实 MapFeatureRenderer 接线的多倍率截图，不另造三维观察场。
var camera := Camera2D.new()
var features := MapFeatureRenderer.new()
var _fail := 0


func _ready() -> void:
	DisplayServer.window_set_size(Vector2i(1600, 900))
	add_child(camera)
	camera.position = Vector2(300, -13300)
	camera.zoom = Vector2.ONE * 0.98
	camera.make_current()
	camera.force_update_scroll()
	add_child(features)
	features.setup(camera, Rect2(-16000, -16000, 32000, 32000))
	if not is_instance_valid(features._tokyo_volume):
		get_tree().quit(1)
		return
	_capture_sequence.call_deferred()


func _capture_sequence() -> void:
	var records: Array[Dictionary] = []
	for zoom_value: float in [0.06, 0.13, 0.26, 0.52, 0.98, 2.2, 5.0]:
		camera.zoom = Vector2.ONE * zoom_value
		camera.force_update_scroll()
		await get_tree().create_timer(2.0).timeout
		await RenderingServer.frame_post_draw
		var image := get_viewport().get_texture().get_image()
		var path := "res://bench/results/tokyo_lod_r4_%03d.png" % roundi(zoom_value * 100)
		if image.save_png(path) != OK:
			_fail += 1
		var state: Dictionary = features._tokyo_volume.debug_state()
		state["zoom"] = zoom_value
		records.append(state)
		print("[Tokyo LOD Visual] ", state)
		if not state.active or state.output_size != Vector2i(image.get_size()):
			_fail += 1
	var file := FileAccess.open("res://bench/results/tokyo_lod_r4_manifest.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(records, "\t"))
	file.close()
	get_tree().quit(1 if _fail else 0)
