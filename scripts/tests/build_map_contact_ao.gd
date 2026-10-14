extends RefCounted
## 只由离线 build bench 调用；直接查询现有模型的三角形 BVH，而非手绘黑边。
const AO := preload("res://scripts/rendering/map_contact_ao.gd")
const Desert := preload("res://scripts/experiments/volume_map_factory.gd")
const Ocean := preload("res://scripts/experiments/ocean_volume_factory.gd")
var _fail := 0


static func directions() -> PackedVector3Array:
	var result := PackedVector3Array()
	for i in AO.SAMPLES:
		var r := sqrt((float(i) + 0.5) / AO.SAMPLES)
		var angle := float(i) * 2.399963229728653
		result.append(Vector3(cos(angle) * r, sqrt(1.0 - r * r), sin(angle) * r))
	return result


static func occlusion(mesh: TriangleMesh, origin: Vector3, rays: PackedVector3Array) -> float:
	var sum := 0.0
	for direction in rays:
		var hit := mesh.intersect_segment(origin, origin + direction * AO.RADIUS)
		if not hit.is_empty():
			sum += 1.0 - smoothstep(0.0, AO.RADIUS, origin.distance_to(hit.position))
	return sum / float(rays.size())


func run() -> void:
	for key: String in AO.RECTS:
		var started := Time.get_ticks_msec()
		var doc := MapDocument.load_from(AO.DOCUMENTS[key])
		var meshes: Array[ArrayMesh] = []
		if key == "ocean":
			meshes.append(Ocean.build(doc, true))
		else:
			meshes.assign(Desert.build(doc, true, true).structure_meshes)
		var faces := PackedVector3Array()
		var bounds: Rect2 = AO.RECTS[key]
		for mesh in meshes:
			var source := mesh.get_faces()
			for index in range(0, source.size(), 3):
				var center := (source[index] + source[index + 1] + source[index + 2]) / 3.0
				if not bounds.grow(AO.RADIUS).has_point(Vector2(center.x, center.z)):
					continue
				for corner in 3:
					var point := source[index + corner]
					if key == "desert": point.y *= Desert.STRUCTURE_HEIGHT_SCALE
					faces.append(point)
		var triangles := TriangleMesh.new()
		if not triangles.create_from_faces(faces):
			_fail += 1
			return
		var image := Image.create(AO.SIZE, AO.SIZE, false, Image.FORMAT_R8)
		var rays := directions()
		var maximum := 0.0
		for y in AO.SIZE:
			for x in AO.SIZE:
				var point := bounds.position + (Vector2(x, y) + Vector2.ONE * 0.5) / AO.SIZE * bounds.size
				var shade := occlusion(triangles, Vector3(point.x, 0.8, point.y), rays)
				maximum = maxf(maximum, shade)
				image.set_pixel(x, y, Color(shade, 0, 0))
			if y % 128 == 0: print("[AO bake] ", key, " rows=", y, "/", AO.SIZE)
		image.generate_mipmaps()
		if OS.get_environment("AGL_AO_VERIFY_REBAKE") == "1":
			var prior := load(AO.path_for(key)) as Texture2D
			var identical := prior != null and prior.get_image().get_data() == image.get_data()
			if not identical: _fail += 1
			print("[AO bake] ", key, " unchanged_pixels=", identical)
		var texture := ImageTexture.create_from_image(image)
		texture.set_meta("ao_version", AO.VERSION)
		texture.set_meta("ao_rect", bounds)
		texture.set_meta("ao_document_hash", FileAccess.get_sha256(AO.DOCUMENTS[key]))
		texture.set_meta("ao_source_hash", AO.fingerprint(key))
		texture.set_meta("ao_triangles", faces.size() / 3)
		texture.set_meta("ao_maximum", maximum)
		var error := ResourceSaver.save(texture, "res://bench/results/%s_contact_ao.res" % key, ResourceSaver.FLAG_COMPRESS)
		if error != OK or maximum <= 0.1: _fail += 1
		print("[AO bake] ", key, " triangles=", faces.size() / 3, " bytes=", image.get_data().size(),
			" max=", maximum, " elapsed_ms=", Time.get_ticks_msec() - started, " error=", error)
