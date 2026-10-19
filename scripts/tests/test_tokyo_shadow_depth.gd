extends RefCounted
const Depth := preload("res://scripts/rendering/tokyo_shadow_depth.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	_test_visible_height()
	for degrees in range(0, 360, 15):
		var basis := MapProjection.camera_basis(Transform2D(deg_to_rad(degrees), Vector2.ZERO), Depth.TILT)
		for sun_elevation: float in [15, 50, 85]:
			var light := Basis.from_euler(Vector3(deg_to_rad(-sun_elevation), deg_to_rad(-35), 0))
			for size: float in [60, 900, 18000]:
				var clip := Depth.fit(size, 320, basis, light)
				_check(clip.x > 0 and clip.y > clip.x, "finite ordered camera clip")
				for screen_x: float in [-size, size]:
					for screen_y: float in [-size * 0.5, size * 0.5]:
						for height: float in [-1, 0, 40, 160, 320]:
							# 独立求屏幕射线与目标高度平面的交点，而非复用被测包络公式。
							var receiver := basis.x * screen_x + basis.y * screen_y
							receiver += basis.z * ((height - receiver.y) / basis.z.y)
							_check(_inside(clip, basis, receiver), "visible ground/wall/roof is inside depth")
							for rise: float in [0, (320 - height) * 0.5, 320 - height]:
								var caster := receiver + light.z * (rise / light.z.y)
								_check(_inside(clip, basis, caster), "offscreen shadow caster still inside depth")
	var camera := MapProjection.camera_basis(Transform2D.IDENTITY, Depth.TILT)
	var sun := Basis.from_euler(Vector3(deg_to_rad(-50), deg_to_rad(-35), 0))
	var near_clip := Depth.fit(67.5, 150, camera, sun)
	_check(near_clip.y - near_clip.x < 300, "near viewport does not retain 2400 units of empty depth")
	_check(Depth.fit(100, INF, camera, sun) == Vector2.ZERO, "missing height metadata requests legacy fallback")
	_check(Depth.fit(100, 320, camera, Basis.IDENTITY) == Vector2.ZERO, "horizontal light requests legacy fallback")
	_check(Depth.fit(-1, 320, camera, sun) == Vector2.ZERO, "invalid viewport requests legacy fallback")
	var archive: Resource = load("res://resources/maps/tokyo_volume_preview/r17b_cells/index.res")
	for entry: Dictionary in archive.cells:
		for slot in 7:
			var cell: Resource = load(entry.mid.path if slot == 6 else entry.levels[slot].path)
			for mesh: ArrayMesh in cell.meshes:
				if mesh == null:
					continue
				var bounds := mesh.get_aabb()
				_check(bounds.position.y >= -1 and bounds.end.y <= float(entry.max_height_px) + 0.01,
					"all native LOD geometry lies within independently tested source height envelope")
	print("[Tokyo shadow depth test] pass=", _pass, " fail=", _fail)


func _test_visible_height() -> void:
	for degrees in range(0, 360, 30):
		var canvas := Transform2D(deg_to_rad(degrees), Vector2.ZERO)
		var basis := MapProjection.camera_basis(canvas, Depth.TILT)
		var ground := MapProjection.ground_basis(canvas, Depth.TILT)
		var camera := Transform3D(basis, basis.z * Depth.DISTANCE)
		for elevation: float in [15, 50, 85]:
			var light := Basis.from_euler(Vector3(deg_to_rad(-elevation), deg_to_rad(-35), 0))
			for screen_x: float in [-80, 0, 80]:
				for screen_y: float in [-45, 0, 45]:
					for altitude: float in [0, 40, 160]:
						# 独立从可见平面射线反求源楼/投影源的原地图位置。
						var receiver := basis.x * screen_x + basis.y * screen_y
						receiver += basis.z * ((altitude - receiver.y) / basis.z.y)
						for source: Vector3 in [receiver, receiver + light.z * ((160 - altitude) / light.z.y)]:
							var origin := ground.inverse() * source
							var cells: Array = [{"content_bounds": Rect2(Vector2(origin.x, origin.z) - Vector2.ONE, Vector2(2, 2)), "max_height_px": 160.0}]
							_check(Depth.visible_height(cells, ground, camera, light, Vector2(160, 90)) == 160.0,
								"visible source or offscreen shadow caster retains original height")
			var separated: Array = [{"content_bounds": Rect2(-5, -5, 10, 10), "max_height_px": 20.0},
				{"content_bounds": Rect2(1000000, 1000000, 10, 10), "max_height_px": 1000.0}]
			_check(Depth.visible_height(separated, ground, camera, light, Vector2(160, 90)) == 20.0,
				"unrelated distant tall block does not inflate current depth")
			separated[1].erase("max_height_px")
			_check(is_inf(Depth.visible_height(separated, ground, camera, light, Vector2(160, 90))),
				"unknown metadata fails closed even for distant block")
			separated[1] = {"content_bounds": Rect2(INF, 0, 10, 10), "max_height_px": 1000.0}
			_check(is_inf(Depth.visible_height(separated, ground, camera, light, Vector2(160, 90))),
				"nonfinite footprint fails closed")
	_check(is_inf(Depth.visible_height([], Basis.IDENTITY, Transform3D.IDENTITY, Basis.IDENTITY, Vector2(160, 90))),
		"horizontal sun falls back to global envelope")
	if ResourceLoader.exists("res://resources/maps/tokyo_volume_preview/r26b_cells/index.res"):
		var archive: Resource = load("res://resources/maps/tokyo_volume_preview/r26b_cells/index.res")
		for entry: Dictionary in archive.cells:
			for slot in 7:
				var package: Resource = load(entry.mid.path if slot == 6 else entry.levels[slot].path)
				var meshes: Array = Array(package.meshes)
				if package.precision_original != null:
					meshes.append(package.precision_original)
				for mesh: ArrayMesh in meshes:
					if mesh == null or mesh.get_surface_count() == 0:
						continue
					var box := mesh.get_aabb()
					var footprint := Rect2(Vector2(box.position.x, box.position.z), Vector2(box.size.x, box.size.z))
					_check(box.position.y >= -1 and box.end.y <= float(entry.max_height_px) + 0.01 \
						and entry.content_bounds.grow(0.02).encloses(footprint),
						"joined original metadata contains every LOD and pinned precision fallback")


func _inside(clip: Vector2, basis: Basis, point: Vector3) -> bool:
	var distance := Depth.DISTANCE - basis.z.dot(point)
	return distance >= clip.x and distance <= clip.y


func _check(ok: bool, message: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL shadow depth: ", message)
