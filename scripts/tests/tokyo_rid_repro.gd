extends RefCounted
## 仅显式诊断入口：复现旧后端后台原生加载与主线程RID创建竞争；不得接all。


static func run(parent: Node) -> int:
	print("[Tokyo RID repro] engine=", Engine.get_version_info(), " display=", DisplayServer.get_name(), " driver=", RenderingServer.get_current_rendering_driver_name())
	var catalog: Resource = load("res://resources/maps/tokyo_volume_preview/r34_cells/index.res")
	var paths := PackedStringArray()
	for entry: Dictionary in catalog.cells:
		paths.append(entry.levels[0].path)
		paths.append(entry.fixed)
	var pending := PackedStringArray()
	var completed := 0
	var started := 0
	var deadline := Time.get_ticks_msec() + 15000
	while completed < 128 and Time.get_ticks_msec() < deadline:
		for path: String in pending.duplicate():
			if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED:
				var resource: Resource = ResourceLoader.load_threaded_get(path)
				for mesh: ArrayMesh in resource.meshes:
					if RenderingServer.mesh_get_surface_count(mesh.get_rid()) != mesh.get_surface_count():
						push_error("[Bench] RID repro found invalid native mesh")
				pending.erase(path)
				completed += 1
		while pending.size() < 2 and started < 128:
			var path := paths[started % paths.size()]
			if path in pending:
				break
			if ResourceLoader.load_threaded_request(path, "", false, ResourceLoader.CACHE_MODE_IGNORE) != OK:
				return 1
			pending.append(path)
			started += 1
		# 独立空网格实际分配/释放RID，不涉及地图几何、不碰生产缓存。
		for n in 2000:
			var mesh := ArrayMesh.new()
			mesh.get_rid()
		await parent.get_tree().process_frame
	for path: String in pending:
		ResourceLoader.load_threaded_get(path)
	print("[Tokyo RID repro] completed=", completed, " requested=", started)
	return int(completed != 128)
