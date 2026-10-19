extends RefCounted
## 显式离线构建；产物仅写bench/results，核验后复制到resources。
const Archive := preload("res://scripts/rendering/ocean_volume_archive.gd")
const Factory := preload("res://scripts/experiments/ocean_volume_factory.gd")
const SharedArchive := preload("res://scripts/experiments/volume_terrain_archive.gd")
const Surface := preload("res://scripts/experiments/volume_terrain_surface.gd")
var _fail := 0


func run() -> void:
	var started := Time.get_ticks_usec()
	var doc := MapDocument.load_from(Archive.DOCUMENT)
	var archive := Archive.new()
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Archive.METADATA))
	archive.terrain_bounds = SharedArchive.source_rect(meta)
	archive.bounds = archive.terrain_bounds
	archive.building_count = doc.buildings.size()
	archive.source_buildings.assign(doc.buildings.duplicate(true))
	var low := Factory.build(doc, false)
	var detail := Factory.build(doc, true)
	var empty := ArrayMesh.new()
	archive.ground = Factory.runway(doc)
	archive.roads = empty
	archive.rails = empty
	for level in 6:
		var mesh: ArrayMesh = detail if level >= 2 else low
		archive.levels.append({"low": mesh, "known": empty,
			"triangles": mesh.surface_get_array_len(0) / 3, "counts": [16]})
	archive.geometry_bytes = _mesh_bytes(low) + _mesh_bytes(detail) + _mesh_bytes(archive.ground)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Archive.ELEVATION))
	assert(data.metadata_sha256 == FileAccess.get_sha256(Archive.METADATA))
	var heights := PackedFloat32Array(data.heights_m)
	var size := int(data.grid_size)
	for y in size:
		for x in size:
			var point := archive.terrain_bounds.position + Vector2(x, y) / float(size - 1) * archive.terrain_bounds.size
			var distance := point.distance_to(point.clamp(Factory.BASE_RECT.position, Factory.BASE_RECT.end))
			heights[y * size + x] = maxf(0, heights[y * size + x] - 10) * 0.12 * smoothstep(0, 180, distance)
	var cover := PackedFloat32Array()
	cover.resize(heights.size())
	var surface := Surface.new(archive.terrain_bounds, size, heights, cover)
	archive.relief_texture = relief_texture(heights, size, archive.terrain_bounds)
	archive.geometry_bytes += size * size * 12
	var layouts := tile_layouts(archive.terrain_bounds)
	for key: String in layouts:
		var entry: Dictionary = layouts[key]
		entry.mesh = surface.plane_mesh(entry.render_bounds, entry.uv, -0.10, entry.bounds)
		archive.geometry_bytes += _mesh_bytes(entry.mesh)
		archive.terrain[key] = entry
	archive.source_hash = Archive.fingerprint()
	archive.data_hash = Archive.data_fingerprint()
	if not archive.valid():
		_fail += 1
		push_error("invalid ocean archive: entries=%d bytes=%d" % [archive.terrain.size(), archive.geometry_bytes])
		return
	var error := ResourceSaver.save(archive, "res://bench/results/ocean_volume.res", ResourceSaver.FLAG_COMPRESS)
	if error != OK:
		_fail += 1
	print("[Ocean bake] tiles=", archive.terrain.size(), " buildings=", archive.building_count,
		" triangles_near=", archive.levels[2].triangles, " geometry_bytes=", archive.geometry_bytes,
		" elapsed_ms=", (Time.get_ticks_usec() - started) / 1000.0, " status=", error)


static func relief_texture(heights: PackedFloat32Array, size: int, bounds: Rect2) -> ImageTexture:
	# 独立于三角剖分的连续法线场；先以1-2-1核滤去高程采样噪声，再中心差分。
	var smooth := PackedFloat32Array()
	smooth.resize(heights.size())
	for y in size:
		for x in size:
			var total := 0.0
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					total += heights[clampi(y + dy, 0, size - 1) * size + clampi(x + dx, 0, size - 1)] * (2 if dx == 0 else 1) * (2 if dy == 0 else 1)
			smooth[y * size + x] = total / 16.0
	var image := Image.create(size, size, false, Image.FORMAT_RGBF)
	var step := bounds.size / float(size - 1)
	for y in size:
		for x in size:
			var x0 := maxi(0, x - 1)
			var x1 := mini(size - 1, x + 1)
			var y0 := maxi(0, y - 1)
			var y1 := mini(size - 1, y + 1)
			var dx := (smooth[y * size + x1] - smooth[y * size + x0]) / ((x1 - x0) * step.x)
			var dz := (smooth[y1 * size + x] - smooth[y0 * size + x]) / ((y1 - y0) * step.y)
			image.set_pixel(x, y, Color(-dx, 1, -dz))
	return ImageTexture.create_from_image(image)


static func tile_layouts(rect: Rect2) -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Archive.MANIFEST))
	var result := {}
	for lod: String in ["strategic", "operational", "detail"]:
		var level: Dictionary = manifest.levels[lod]
		var size := Vector2(level["size"][0], level["size"][1])
		for tile: Dictionary in level.tiles:
			if lod == "strategic":
				result["StrategicBasemap"] = {"bounds": Rect2(rect.position, size * (rect.size / size)),
					"render_bounds": SharedArchive.canonical_tile_rect(rect.position, rect.end), "uv": Rect2(0, 0, 1, 1)}
				continue
			var c: Array = tile.content_rect
			var content := Vector2(c[2], c[3])
			var texture_size := Vector2.ONE * (float(manifest.content_size) + 2 * float(manifest.gutter))
			var start := rect.position + Vector2(c[0], c[1]) / size * rect.size
			var end := rect.position + Vector2(c[0] + c[2], c[1] + c[3]) / size * rect.size
			result["%s_r%02d_c%02d" % [lod, tile.row, tile.column]] = {
				"bounds": Rect2(start, content * (rect.size / size)),
				"render_bounds": SharedArchive.canonical_tile_rect(start, end),
				"uv": Rect2(Vector2.ONE * float(manifest.gutter) / texture_size, content / texture_size)}
	return result


static func _mesh_bytes(mesh: ArrayMesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		for channel: Variant in mesh.surface_get_arrays(surface):
			if channel != null:
				count += channel.to_byte_array().size()
	return count
