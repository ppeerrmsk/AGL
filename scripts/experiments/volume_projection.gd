extends RefCounted
## 斜俯视只改变显示：底面与原 Canvas 精确重合，二维命中/标签权威不变。
const TILT_DEGREES := 30.0
const TILT := TILT_DEGREES * PI / 180.0
const DESERT_TILT_DEGREES := 38.0
const DESERT_TILT := DESERT_TILT_DEGREES * PI / 180.0


static func top_basis(canvas: Transform2D) -> Basis:
	var right := canvas.affine_inverse().x.normalized()
	return Basis(Vector3(right.x, 0, right.y), Vector3(right.y, 0, -right.x), Vector3.UP)


static func camera_basis(canvas: Transform2D, tilt: float = TILT) -> Basis:
	var top := top_basis(canvas)
	return Basis(top.x, top.y * cos(tilt) + top.z * sin(tilt), top.z * cos(tilt) - top.y * sin(tilt))


static func ground_basis(canvas: Transform2D, tilt: float = TILT) -> Basis:
	var top := top_basis(canvas)
	return top * Basis.from_scale(Vector3(1, 1.0 / cos(tilt), 1)) * top.inverse()


static func actor_transform(source: Transform3D, canvas: Transform2D, tilt: float = TILT) -> Transform3D:
	var ground := ground_basis(canvas, tilt)
	var anchor := source.origin - top_basis(canvas).y * source.origin.y * sin(tilt)
	return Transform3D(ground * source.basis, ground * anchor)
