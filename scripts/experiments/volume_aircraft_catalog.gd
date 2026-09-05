extends RefCounted
## 首批专属低模。只在受控预热时构建，共享只读网格；不持有单位、不新增 tick。
## 坐标与原型一致：X 向右、Y 向上、机头 -Z；顶点色供现有机体颜色乘算。

const Factory := preload("res://scripts/experiments/volume_mesh_factory.gd")
const TRIANGLE_BUDGET := 600
const BODY := Color.WHITE
const CANOPY := Color(0.20, 0.30, 0.37)
const ENGINE := Color(0.74, 0.78, 0.80)
const INTAKE := Color(0.16, 0.19, 0.21)

static var _meshes: Dictionary = {}
static var _shared_material: StandardMaterial3D


static func supported_keys() -> Array[String]:
	return ["f14", "a10", "f47"]


## 未制作类型返回 null，由调用者保留原显示，不能悄悄改成另一架飞机。
static func build(kind: String) -> ArrayMesh:
	if not supported_keys().has(kind):
		return null
	if _meshes.has(kind):
		return _meshes[kind] as ArrayMesh
	var builder := Factory.new()
	match kind:
		"f14":
			_build_f14(builder)
		"a10":
			_build_a10(builder)
		"f47":
			_build_f47(builder)
	var result: ArrayMesh = builder.mesh()
	if _shared_material == null:
		_shared_material = Factory.material()
	result.surface_set_material(0, _shared_material)
	result.resource_name = "AGL_%s_volume_batch_a" % kind
	_meshes[kind] = result
	return result


## 制作记录只描述本批近似模型，不把现有 PNG 的审核结论移植为 3D 写实认证。
static func metadata_for(kind: String) -> Dictionary:
	var record: Dictionary
	match kind:
		"f14":
			record = {
				"name": "F-14", "triangles": 432,
				"source": "res://resources/aircraft_silhouettes/f14_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Grumman_F-14_Tomcat.png",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "public domain, US Army",
				"attribution": "US Army; AGL simplified 3D reconstruction",
				"shape": "展开翼固定姿态、长鼻双座舱、翼根手套、分离双发与双垂尾",
				"fidelity": "按项目已审展开翼顶视轮廓近似；厚度为本批美术设计，不含变后掠动画",
			}
		"a10":
			record = {
				"name": "A-10", "triangles": 412,
				"source": "res://resources/aircraft_silhouettes/a10_detail.png",
				"source_url": "https://commons.wikimedia.org/wiki/File:Fairchild_Republic_A-10_Thunderbolt_II_3-view.svg",
				"source_manifest": "res://resources/aircraft_silhouettes/reference_manifest.json",
				"source_license": "CC BY-SA 3.0",
				"license_url": "https://creativecommons.org/licenses/by-sa/3.0/",
				"attribution": "Kaboldy; AGL simplified 3D adaptation, CC BY-SA 3.0",
				"shape": "宽直翼、短粗机身、后置高双发、H 形尾翼、机鼻炮口",
				"fidelity": "按项目已审顶视比例近似；保留署名与同许可，三维厚度不是测绘数据",
			}
		"f47":
			record = {
				"name": "F-47", "triangles": 416,
				"source": "res://scripts/aircraft_renderer.gd",
				"source_symbol": "draw_aircraft_icon: legacy body / stealth wings / tail polygons",
				"source_license": "AGL project-authored concept geometry",
				"attribution": "AGL project concept; no external F-47 model copied",
				"shape": "宽扁折面机身、菱形后掠翼、低矮双喷口、外倾双垂尾",
				"fidelity": "现有 F-47 无获审 PNG；沿用项目 legacy/stealth 语汇的原创概念，不声称真实 F-47 外形",
			}
		_:
			return {}
	record["key"] = kind
	record["triangle_budget"] = TRIANGLE_BUDGET
	record["surface_count"] = 1
	record["material_count"] = 1
	record["native_max_extent"] = 34.0
	record["forward"] = Vector3.FORWARD
	record["status"] = "experimental_batch_a_visual_pending"
	record["editable_source"] = "res://scripts/experiments/volume_aircraft_catalog.gd"
	return record


static func _build_f14(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.06, 0.06), Vector3(-12, 1.05, 1),
		Vector3(-6, 1.65, 1.5), Vector3(-1, 2.9, 1.65), Vector3(8, 3.25, 1.2),
		Vector3(14, 2.35, 0.9), Vector3(16.7, 0.16, 0.14)], BODY)
	_closed_loft(builder, Vector3(0, 1.3, -8), [Vector3(-4.2, 0.07, 0.07),
		Vector3(-2, 1.05, 1), Vector3(1.5, 1.08, 1.1), Vector3(4, 0.2, 0.1)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(2.5, -1), Vector2(5.6, 1.7), Vector2(17, 6.8),
			Vector2(16.9, 8.3), Vector2(3.1, 7.2)], side, -0.3, 0.3, BODY)
		_planform(builder, [Vector2(1.8, -5.2), Vector2(4.1, -4.6), Vector2(5.7, 1.7),
			Vector2(3.4, 7.9), Vector2(2.8, 7.3), Vector2(2.1, -1)], side, -0.6, 0.65, BODY)
		_planform(builder, [Vector2(2, 10), Vector2(3.7, 9.8), Vector2(10, 14.8),
			Vector2(9.4, 16.5), Vector2(2.2, 14)], side, -0.1, 0.45, BODY)
		_closed_loft(builder, Vector3(2.85 * side, -0.15, 5),
			[Vector3(-9, 0.9, 0.85), Vector3(-6, 1.2, 1.05),
			Vector3(8, 1.2, 1), Vector3(11.5, 0.8, 0.8)], ENGINE, INTAKE, INTAKE)
		_fin(builder, 3 * side, [Vector2(8.5, 0.5), Vector2(10, 5.4),
			Vector2(12.5, 5), Vector2(15.2, 0.5)], 0.225, side * 0.13, BODY)


static func _build_a10(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-15, 0.13, 0.14), Vector3(-13, 1.4, 1.35),
		Vector3(-6, 1.6, 1.65), Vector3(4, 1.8, 1.8), Vector3(11.5, 1.2, 1.4),
		Vector3(15, 0.2, 0.15)], BODY)
	_closed_loft(builder, Vector3(0, 1.45, -8), [Vector3(-3, 0.08, 0.08),
		Vector3(-1.5, 1.15, 1.2), Vector3(1.3, 1.05, 1.1), Vector3(3, 0.15, 0.1)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(1.1, -2.6), Vector2(8, -3), Vector2(17, -1.9),
			Vector2(17, 1.3), Vector2(15.5, 2.2), Vector2(1.5, 3.1)], side, -0.45, 0.2, BODY)
		_closed_loft(builder, Vector3(4.2 * side, 2.2, 6), [Vector3(-3, 0.95, 1.1),
			Vector3(-2, 1.4, 1.55), Vector3(3.5, 1.4, 1.55), Vector3(4.5, 1.1, 1.2)],
			BODY, INTAKE, INTAKE)
		builder.box(Vector3(2.8 * side, 1.25, 6), Vector3(2.5, 0.55, 3.5), ENGINE)
		_planform(builder, [Vector2(1, 11.6), Vector2(6.5, 11.3),
			Vector2(6.5, 14.8), Vector2(1, 14.8)], side, 0.4, 0.95, BODY)
		_fin(builder, 6.3 * side, [Vector2(10.8, 0.7), Vector2(11.5, 4),
			Vector2(14.5, 3.7), Vector2(15, 0.7)], 0.2, 0.0, BODY)
	# 中央简化炮口只作识别特征，不是武器/发射点权威。
	builder.box(Vector3(0, -0.9, -13.3), Vector3(0.45, 0.4, 2.4), INTAKE)


static func _build_f47(builder: RefCounted) -> void:
	_closed_loft(builder, Vector3.ZERO, [Vector3(-17, 0.05, 0.05), Vector3(-10, 2.1, 1),
		Vector3(-4.6, 4.1, 1.65), Vector3(4, 4.3, 1.55), Vector3(12, 3.3, 1.05),
		Vector3(15.8, 0.12, 0.12)], BODY)
	_closed_loft(builder, Vector3(0, 1.3, -8), [Vector3(-3.8, 0.06, 0.06),
		Vector3(-1.8, 1.35, 0.9), Vector3(1.6, 1.25, 0.85), Vector3(3.8, 0.12, 0.1)], CANOPY)
	for side in [-1.0, 1.0]:
		_planform(builder, [Vector2(3.2, -4), Vector2(17, 4.5),
			Vector2(8.8, 8.3), Vector2(3.5, 5.1)], side, -0.25, 0.3, BODY)
		_planform(builder, [Vector2(1.6, -10), Vector2(4.3, -4.5), Vector2(5.8, 1.1),
			Vector2(3, 4), Vector2(2, -4)], side, -0.45, 0.45, BODY)
		_closed_loft(builder, Vector3(2.6 * side, -0.2, 7), [Vector3(-5, 1.35, 0.9),
			Vector3(-2, 1.6, 0.85), Vector3(6.5, 1.45, 0.65), Vector3(8.4, 1.3, 0.5)],
			ENGINE, INTAKE, INTAKE)
		_planform(builder, [Vector2(2.4, 8.8), Vector2(8.8, 12),
			Vector2(7.2, 13.6), Vector2(2.88, 12.8)], side, 0.1, 0.55, BODY)
		_fin(builder, 3.7 * side, [Vector2(7.6, 0.8), Vector2(10, 4.4),
			Vector2(12, 4), Vector2(14.2, 0.5)], 0.18, side * 0.35, BODY)
		builder.box(Vector3(3 * side, -0.15, -2.5), Vector3(2, 0.85, 2.5), INTAKE)


static func _planform(builder: RefCounted, points: Array, side: float,
		bottom: float, top: float, color: Color) -> void:
	var mirrored := PackedVector2Array()
	for point: Vector2 in points:
		mirrored.append(Vector2(point.x * side, point.y))
	builder.prism(mirrored, bottom, top, color)


## 两端封口，避免斜视/大滚转透进空壳；所有端截面保留非零半径，无退化三角形。
static func _closed_loft(builder: RefCounted, center: Vector3, rings: Array, color: Color,
		front_color: Color = Color.TRANSPARENT, back_color: Color = Color.TRANSPARENT) -> void:
	builder.loft(center, rings, color)
	_cap_ring(builder, center, rings[0], true, front_color if front_color.a > 0.0 else color)
	_cap_ring(builder, center, rings[-1], false, back_color if back_color.a > 0.0 else color)


static func _cap_ring(builder: RefCounted, center: Vector3, ring: Vector3,
		front: bool, color: Color) -> void:
	var origin := center + Vector3(0, 0, ring.x)
	for index in 8:
		var angle := TAU * float(index) / 8.0
		var next_angle := TAU * float(index + 1) / 8.0
		var a := origin + Vector3(cos(angle) * ring.y, sin(angle) * ring.z, 0)
		var b := origin + Vector3(cos(next_angle) * ring.y, sin(next_angle) * ring.z, 0)
		if front:
			builder.triangle(origin, b, a, color)
		else:
			builder.triangle(origin, a, b, color)


## 侧面轮廓坐标为 (Z, Y)。整体外倾，但两侧仍有真实厚度及封闭边缘。
static func _fin(builder: RefCounted, x: float, points: Array,
		half_thickness: float, lean: float, color: Color) -> void:
	var outline := PackedVector2Array(points)
	var indices := Geometry2D.triangulate_polygon(outline)
	var centroid := Vector2.ZERO
	for point: Vector2 in points:
		centroid += point
	centroid /= float(points.size())
	for side in [-1.0, 1.0]:
		for index in range(0, indices.size(), 3):
			var vertices: Array[Vector3] = []
			for offset in 3:
				var point := outline[indices[index + offset]]
				vertices.append(Vector3(x + side * half_thickness + lean * point.y, point.y, point.x))
			_outward_triangle(builder, vertices[0], vertices[1], vertices[2], Vector3.RIGHT * side, color)
	for index in outline.size():
		var p := outline[index]
		var q := outline[(index + 1) % outline.size()]
		var a := Vector3(x - half_thickness + lean * p.y, p.y, p.x)
		var b := Vector3(x - half_thickness + lean * q.y, q.y, q.x)
		var c := b + Vector3.RIGHT * half_thickness * 2.0
		var d := a + Vector3.RIGHT * half_thickness * 2.0
		var outward := Vector3(0, (p.y + q.y) * 0.5 - centroid.y, (p.x + q.x) * 0.5 - centroid.x)
		_outward_triangle(builder, a, b, c, outward, color)
		_outward_triangle(builder, a, c, d, outward, color)


static func _outward_triangle(builder: RefCounted, a: Vector3, b: Vector3, c: Vector3,
		outward: Vector3, color: Color) -> void:
	if (b - a).cross(c - a).dot(outward) < 0.0:
		builder.triangle(a, c, b, color)
	else:
		builder.triangle(a, b, c, color)
