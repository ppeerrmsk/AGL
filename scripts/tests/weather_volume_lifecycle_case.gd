extends RefCounted
## 真 SceneTree 退出与源释放，必须跨消费者下一帧。
func run(parent: Node) -> int:
	var failures := 0
	for script in [preload("res://scripts/rendering/weather_volume_presentation.gd"),preload("res://scripts/rendering/weather_density_presentation.gd")]:
		failures += await _run_presenter(parent,script)
	return failures


func _run_presenter(parent: Node, script: Script) -> int:
	var source := WeatherSystem.new()
	source.apply_ugc_config({"seed":12})
	parent.add_child(source)
	var presenter: Node3D = script.new()
	parent.add_child(presenter)
	presenter.setup(source)
	if presenter.get("_ready_density") != null:
		for i in range(600):
			if presenter._ready_density:
				break
			await parent.get_tree().process_frame
	presenter.sync(0.1,Transform2D.IDENTITY,Vector2(640,480),Basis.IDENTITY)
	var failed := 0
	if not source.has_meta(&"weather_volume_owner"):
		failed += 1
	if presenter.get("_ready_density") != null:
		var first_revision: int = presenter._revision
		source.apply_ugc_config({"seed":21,"coverage":1.0})
		presenter.sync(0.6,Transform2D.IDENTITY,Vector2(640,480),Basis.IDENTITY)
		if presenter._revision == first_revision or presenter._chunks.size() > 96:
			failed += 1
		for node: MeshInstance3D in presenter._chunks.values():
			if node.mesh != null:
				failed += 1
	presenter.set_enabled(false)
	if source.has_meta(&"weather_volume_owner") or presenter.visible:
		failed += 1
	presenter.set_enabled(true)
	if not source.has_meta(&"weather_volume_owner"):
		failed += 1
	presenter.queue_free()
	await parent.get_tree().process_frame
	if source.has_meta(&"weather_volume_owner"):
		failed += 1
	var second: Node3D = script.new()
	parent.add_child(second)
	second.setup(source)
	# 在异步纹理仍可能生成时释放源，确保回调不会重建失效owner。
	source.queue_free()
	await parent.get_tree().process_frame
	second.sync(0.6,Transform2D.IDENTITY,Vector2(640,480),Basis.IDENTITY)
	for i in range(3):
		await parent.get_tree().process_frame
	if second.visible:
		failed += 1
	second.queue_free()
	await parent.get_tree().process_frame
	print("WeatherVolume lifecycle: %d fail" % failed)
	return failed
