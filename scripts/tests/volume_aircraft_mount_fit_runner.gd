extends "res://scripts/tests/volume_aircraft_multiview_qa_runner.gd"
## 全目录、全槽位接触验图；使用正式共享网格与挂点，不修改正式装备规则。
const Mounts := preload("res://scripts/experiments/volume_aircraft_mount_catalog.gd")

func _build_models() -> void:
	super._build_models()
	for key in _keys:
		var model: MeshInstance3D = _model_by_key[key]
		for kind in Mounts.AIRCRAFT_KINDS:
			for slot in Mounts.local_slots(kind, key):
				var instance := MeshInstance3D.new()
				instance.mesh = Mounts.build(kind)
				instance.position = slot
				var material := Factory.material().duplicate() as StandardMaterial3D
				material.albedo_color = COLORS[_keys.find(key) % COLORS.size()]
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				instance.material_override = material
				model.add_child(instance)
		if key == "mother_goose":
			var offsets: Array[Vector2] = MotherGooseBoss.PROP_OFFSETS_PX.duplicate()
			offsets.append_array(MotherGooseBoss.VLS_OFFSETS_PX)
			for i in offsets.size():
				var layout := Mounts.goose_layout(offsets[i], i < 8)
				var instance := MeshInstance3D.new()
				instance.mesh = Factory.aircraft("prop" if i < 8 else "vls")
				instance.position = layout.position
				model.add_child(instance)
				if layout.has("support"):
					var support := MeshInstance3D.new()
					support.mesh = Mounts.build("support")
					support.transform = layout.support
					model.add_child(support)


func _capture_sequence() -> void:
	DirAccess.make_dir_recursive_absolute("res://tmp/map_visual_qa/mount_fit")
	var failed := false
	var captures: Array[String] = []
	for page in _pages.size():
		_set_page(page)
		for view_id in ["gameplay", "side", "front", "underside"]:
			_set_view("top" if view_id == "underside" else view_id)
			if view_id == "underside":
				for model in _models:
					model.rotation_degrees.z = 180.0
			_title.text = "MOUNT CONTACT QA / ALL SLOT FIXTURE / %s / %d of %d\n%s" % [view_id.to_upper(), page + 1, _pages.size(), " / ".join(_pages[page])]
			for frame in 6:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var path := "res://tmp/map_visual_qa/mount_fit/volume_mount_fit_%02d_%s.png" % [page + 1, view_id]
			var error := get_viewport().get_texture().get_image().save_png(path)
			failed = failed or error != OK
			captures.append(path)
			print("[Mount fit Visual] %s saved=%s" % [path, error == OK])
	var manifest := FileAccess.open("res://tmp/map_visual_qa/mount_fit/volume_mount_fit_manifest.json", FileAccess.WRITE)
	manifest.store_string(JSON.stringify({"keys": _keys, "pages": _pages, "captures": captures}, "\t"))
	manifest.close()
	print("[Mount fit Visual] airframes=%d views=%d failed=%s" % [_keys.size(), captures.size(), failed])
	AudioManager.request_quit(1 if failed else 0)
