extends RefCounted
## 将实际原生像素反投影到地面，区分未制作范围和可见页缺失；只读诊断。


static func run(map: Node, native: Image, output: String) -> int:
	if FileAccess.file_exists(output) or native == null or native.get_size()!=map._viewport.size:
		return 1
	var rows: Array = []
	var rects: Array = []
	for rect: Rect2 in map._archive.coverage_rects:
		rects.append([rect.position.x,rect.position.y,rect.size.x,rect.size.y])
	for pixel: Vector2i in [Vector2i(250,80),Vector2i(650,80),Vector2i(250,250),Vector2i(800,450)]:
		if not Rect2i(Vector2i.ZERO,native.get_size()).has_point(pixel):
			return 1
		var origin: Vector3 = map._city.to_local(map._camera.project_ray_origin(Vector2(pixel)))
		var direction: Vector3 = map._city.global_basis.inverse()*map._camera.project_ray_normal(Vector2(pixel))
		var hit: Variant = Plane(Vector3.UP,0).intersects_ray(origin,direction)
		if not hit is Vector3:
			return 1
		var ground := Vector2(hit.x,hit.z)
		var covered := false
		for rect: Rect2 in map._archive.coverage_rects:
			covered = covered or rect.has_point(ground)
		var roots: Array = []
		for entry: Dictionary in map._canonical.configurations.lod5_full:
			var layers: Array = []
			for layer in 3:
				var box: AABB = entry.boxes[layer]
				if int(entry.triangles[layer])>0 and Rect2(box.position.x,box.position.z,box.size.x,box.size.z).has_point(ground):
					layers.append(layer)
			if not layers.is_empty():
				roots.append({"path":entry.path,"parent":entry.parent_id,"aabb_layers":layers})
		rows.append({"pixel":[pixel.x,pixel.y],"world_ground":[ground.x,ground.y],
			"native_alpha":native.get_pixelv(pixel).a,"archive_covered":covered,"lod5_root_aabb_candidates":roots})
	var corner: Vector2 = map._camera.unproject_position(map._city.to_global(Vector3(-6300,0,-2700)))
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify({"catalog_sha256":map._canonical_sha,"coverage_rects":rects,
		"regional_extension":map._canonical.regional_extension,"corner_pixel":[corner.x,corner.y],
		"state_ready":preload("res://scripts/rendering/tokyo_volume_preload.gd").state_ready(map.debug_state()),
		"rows":rows,"metadata_aabb_not_triangle_coverage":true,"read_only":true},"  "))
	file.close()
	return 0
