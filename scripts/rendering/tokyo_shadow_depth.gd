extends RefCounted
## 正交可见面及其日光投影源的相机深度包络；只在相机变化时计算。
const DISTANCE := 50000.0
const PADDING := 8.0
const TILT := 38.0 * PI / 180.0


static func fit(size: float, height: float, camera_basis: Basis, light_basis: Basis) -> Vector2:
	if not is_finite(size) or size <= 0 or not is_finite(height) or height < 0 or absf(light_basis.z.y) < 0.01:
		return Vector2.ZERO
	var half_depth := size * 0.5 * tan(TILT)
	var surface_coefficient := 1.0 / cos(TILT)
	var shadow_coefficient := camera_basis.z.dot(light_basis.z) / light_basis.z.y
	var toward := half_depth + height * maxf(surface_coefficient, maxf(shadow_coefficient, 0.0)) + PADDING
	var away := -half_depth + height * minf(shadow_coefficient, 0.0) - surface_coefficient - PADDING
	var result := Vector2(DISTANCE - toward, DISTANCE - away)
	if result.x < 0.1 or result.y <= result.x:
		return Vector2.ZERO
	return result


static func visible_height(cells: Array, ground: Basis, camera: Transform3D, light: Basis, size: Vector2) -> float:
	# 原来源范围覆盖全部LOD及在途旧包；只在相机变化时扫描16条元数据。
	if absf(light.z.y) < 0.01 or size.x <= 0 or size.y <= 0:
		return INF
	var screen := Rect2(-size * 0.5, size)
	var highest := 0.0
	for cell: Dictionary in cells:
		var height := float(cell.get("max_height_px", INF))
		if not is_finite(height) or height < 0 or not cell.get("content_bounds") is Rect2:
			return INF
		var bounds: Rect2 = cell.content_bounds.grow(PADDING)
		if not is_finite(bounds.position.x) or not is_finite(bounds.position.y) or not is_finite(bounds.end.x) or not is_finite(bounds.end.y):
			return INF
		var projected := Rect2()
		var first := true
		for corner: Vector2 in [bounds.position, Vector2(bounds.end.x, bounds.position.y), bounds.end, Vector2(bounds.position.x, bounds.end.y)]:
			for altitude: float in [-1.0, height]:
				var point := ground * Vector3(corner.x, altitude, corner.y)
				# 接收面可处于地面至源楼顶之间；其投影包含在源点与最低地面阴影的凸包。
				var shadow := point - light.z * ((point.y + 1.0) / light.z.y)
				for world_point: Vector3 in [point, shadow]:
					var relative := world_point - camera.origin
					var pixel := Vector2(camera.basis.x.dot(relative), camera.basis.y.dot(relative))
					if first:
						projected = Rect2(pixel, Vector2.ZERO)
						first = false
					else:
						projected = projected.expand(pixel)
		if screen.intersects(projected, true):
			highest = maxf(highest, height)
	return highest
