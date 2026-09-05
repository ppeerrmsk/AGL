extends RefCounted
## 首批低模资产的纯几何门；不冒充 Visual 观感与战斗帧率验收。

const Catalog := preload("res://scripts/experiments/volume_aircraft_catalog.gd")


static func run() -> bool:
	var failures: Array[String] = []
	var signatures: Array[int] = []
	var shared_material: Material
	var keys := Catalog.supported_keys()
	_expect(keys == ["f14", "a10", "f47"], "首批 key 清单确定且没有伪造覆盖", failures)
	for kind in keys:
		var mesh: ArrayMesh = Catalog.build(kind)
		var metadata := Catalog.metadata_for(kind)
		_expect(mesh != null, "%s 可构建" % kind, failures)
		if mesh == null:
			continue
		_expect(mesh == Catalog.build(kind), "%s 共用已构建缓存" % kind, failures)
		_expect(mesh.get_surface_count() == 1, "%s 单 surface" % kind, failures)
		if mesh.get_surface_count() != 1:
			continue
		var material: Material = mesh.surface_get_material(0)
		_expect(material is StandardMaterial3D, "%s 一个标准材质" % kind, failures)
		if shared_material == null:
			shared_material = material
		_expect(material == shared_material, "%s 三种机型共享材质" % kind, failures)
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var triangles := vertices.size() / 3
		_expect(mesh.surface_get_primitive_type(0) == Mesh.PRIMITIVE_TRIANGLES,
			"%s 三角网格" % kind, failures)
		_expect(vertices.size() % 3 == 0 and triangles > 0 and triangles <= Catalog.TRIANGLE_BUDGET,
			"%s 最多 600 三角形" % kind, failures)
		_expect(triangles == int(metadata.get("triangles", -1)), "%s 预算记录等于真实面数" % kind, failures)
		_expect(normals.size() == vertices.size() and colors.size() == vertices.size(),
			"%s 每顶点法线与颜色完整" % kind, failures)
		if normals.size() == vertices.size() and colors.size() == vertices.size():
			_expect(_valid_triangles(vertices, normals, colors), "%s 有效面/向外法线/顺时针正面" % kind, failures)
		var bounds := mesh.get_aabb()
		_expect(bounds.size.y > 3.0 and bounds.position.y < 0.0 and bounds.end.y > 2.0,
			"%s 机腹到上部结构有真实厚度" % kind, failures)
		_expect(bounds.size.x >= 30.0 and bounds.size.x <= 34.01
			and bounds.size.z >= 29.0 and bounds.size.z <= 34.01,
			"%s 保留约 34 像素原型尺度" % kind, failures)
		_expect(absf(bounds.get_center().x) < 0.001, "%s 横向中心不漂移" % kind, failures)
		_expect(_symmetric(vertices), "%s 每个顶点均有镜像对应" % kind, failures)
		_expect(_forward_nose(vertices, bounds), "%s 细机鼻在 -Z 且尾部在 +Z" % kind, failures)
		var signature := hash(vertices)
		_expect(not signatures.has(signature), "%s 独立几何而非同网格改名" % kind, failures)
		signatures.append(signature)
		_expect(not String(metadata.get("source", "")).is_empty()
			and not String(metadata.get("fidelity", "")).is_empty(), "%s 来源及非写实边界明确" % kind, failures)
		print("[Volume catalog] %s triangles=%d bounds=%s" % [kind, triangles, bounds.size])
	# 三机均有不同的纵向/高度分布，而不是仅改变同一模板的全局尺寸。
	_expect(_profile_signature(Catalog.build("f14")) != _profile_signature(Catalog.build("a10"))
		and _profile_signature(Catalog.build("f14")) != _profile_signature(Catalog.build("f47"))
		and _profile_signature(Catalog.build("a10")) != _profile_signature(Catalog.build("f47")),
		"归一化三维结构不能只是同一模板缩放", failures)
	_expect(Catalog.build("unknown") == null and Catalog.build("") == null,
		"未知 key 安全拒绝而非套壳", failures)
	_expect(Catalog.metadata_for("unknown").is_empty(), "未知 key 不伪报制作记录", failures)
	var altered := Catalog.metadata_for("f14")
	altered["triangles"] = -1
	_expect(int(Catalog.metadata_for("f14").get("triangles", -1)) == 432,
		"调用者修改 metadata 不污染后续查询", failures)
	for failure in failures:
		push_error("Volume aircraft catalog: " + failure)
	print("[Volume catalog] failures=%d (geometry only, not a Visual/FPS gate)" % failures.size())
	return failures.is_empty()


static func _valid_triangles(vertices: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> bool:
	for index in range(0, vertices.size(), 3):
		var cross := (vertices[index + 1] - vertices[index]).cross(vertices[index + 2] - vertices[index])
		if not cross.is_finite() or cross.length_squared() < 0.00000001:
			return false
		for offset in 3:
			var normal := normals[index + offset]
			if not normal.is_finite() or absf(normal.length() - 1.0) > 0.001:
				return false
			if cross.normalized().dot(normal) > -0.999 or colors[index + offset].a < 0.999:
				return false
	return true


static func _symmetric(vertices: PackedVector3Array) -> bool:
	var positions: Dictionary = {}
	for vertex in vertices:
		positions[Vector3i((vertex * 10000.0).round())] = true
	for vertex in vertices:
		var mirror := Vector3i((Vector3(-vertex.x, vertex.y, vertex.z) * 10000.0).round())
		if not positions.has(mirror):
			return false
	return true


static func _forward_nose(vertices: PackedVector3Array, bounds: AABB) -> bool:
	if bounds.position.z > -14.9 or bounds.end.z < 14.9:
		return false
	for vertex in vertices:
		if vertex.z < bounds.position.z + 0.01 and absf(vertex.x) > 0.21:
			return false
	return true


static func _profile_signature(mesh: ArrayMesh) -> int:
	if mesh == null or mesh.get_surface_count() != 1:
		return 0
	var bounds := mesh.get_aabb()
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var occupied: Dictionary = {}
	for vertex in vertices:
		var normalized := (vertex - bounds.position) / bounds.size
		occupied[Vector3i((normalized * 20.0).round())] = true
	var cells := occupied.keys()
	cells.sort()
	return hash(cells)


static func _expect(ok: bool, message: String, failures: Array[String]) -> void:
	if not ok:
		failures.append(message)
