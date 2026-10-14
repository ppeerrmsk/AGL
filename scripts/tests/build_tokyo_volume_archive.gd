extends RefCounted
## 显式离线 bench：结果写 bench/results，经校验后再推广资源。
const Archive := preload("res://scripts/rendering/tokyo_volume_archive.gd")
const Factory := preload("res://scripts/experiments/tokyo_volume_preview_factory.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
var _fail := 0


func run() -> void:
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Factory.DATA_PATH))
	var archive := Archive.new()
	archive.bounds = Rect2(-520, -13870, 1640, 1140)
	archive.source_hash = FileAccess.get_sha256(Factory.DATA_PATH) + ":" + FileAccess.get_sha256(Factory.GROUND_PATH)
	archive.building_count = source.buildings.size()
	var packet := Factory.build()
	archive.roads = packet.road_mesh
	archive.rails = packet.rail_mesh
	archive.ground = Factory.build_ground()
	archive.geometry_bytes = _bytes(archive.roads) + _bytes(archive.rails) + _bytes(archive.ground)
	for scale_value: float in Archive.SCALES:
		var low := Geometry.new()
		var known := Geometry.new()
		var counts := [0, 0, 0]
		for raw: Dictionary in source.buildings:
			var points := Factory._points(raw.points)
			var height := maxf(1.6, float(raw.height_m) * 0.5)
			var span := Rect2(points[0], Vector2.ZERO)
			for point: Vector2 in points:
				span = span.expand(point)
			var pixels := maxf(span.size.x, span.size.y) * scale_value
			var is_known := String(raw.height_source) != "fallback"
			var industrial := String(raw.kind) == "industrial"
			var builder: RefCounted = known if is_known else low
			var level := 0 if pixels >= 10.0 else (1 if pixels >= 2.5 else 2)
			if height >= 40.0 and scale_value > 0.10:
				level = mini(level, 1)
			counts[level] += 1
			if level == 0:
				if is_known:
					Factory._add_known(builder, points, height, raw)
				else:
					Factory._add_low(builder, points, height, String(raw.kind))
			else:
				var wall: Color = Factory.INDUSTRIAL_WALL if industrial else Factory.LOW_WALL
				var roof: Color = Factory.INDUSTRIAL_ROOF if industrial else Factory.LOW_ROOF
				if is_known and not industrial:
					wall = Factory.HIGHRISE_WALL if height >= 40.0 else Factory.KNOWN_WALL
					roof = Factory.HIGHRISE_ROOF if height >= 40.0 else Factory.KNOWN_ROOF
				if level == 1:
					Factory._shell(builder, points, 0.12, height, wall)
				# 远档仅省墙，屋顶仍保留原高度和轮廓，避免楼群密度消失。
				Factory._face(builder, points, height, roof)
		var low_mesh: ArrayMesh = low.mesh()
		var known_mesh: ArrayMesh = known.mesh()
		var triangles := Factory._triangles(low_mesh) + Factory._triangles(known_mesh)
		archive.levels.append({"scale": scale_value, "low": low_mesh, "known": known_mesh,
			"triangles": triangles, "counts": counts})
		archive.geometry_bytes += _bytes(low_mesh) + _bytes(known_mesh)
		print("[Tokyo archive] scale=", scale_value, " triangles=", triangles, " LOD0/1/2=", counts)
	var error := ResourceSaver.save(archive, "res://bench/results/downtown_lod.res", ResourceSaver.FLAG_COMPRESS)
	if error != OK or not archive.valid():
		_fail += 1
	print("[Tokyo archive] bytes=", archive.geometry_bytes, " valid=", archive.valid(), " save=", error)


func _bytes(mesh: ArrayMesh) -> int:
	var size := 0
	for channel: Variant in mesh.surface_get_arrays(0):
		if channel != null:
			size += channel.to_byte_array().size()
	return size
