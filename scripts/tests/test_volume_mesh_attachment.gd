extends RefCounted
## 仅验收：沿制作部件之间真实的接合关系验证整个网格，支座不能挂在悬空的零件上。

static func check(mesh: ArrayMesh) -> String:
	var faces := mesh.get_faces()
	if faces.is_empty():
		return "空网格"
	var parents := PackedInt32Array()
	var point_ids := {}
	var first_triangle := PackedInt32Array()
	var edge_uses := {}
	for t in range(faces.size() / 3):
		parents.append(t)
		var ids := PackedInt32Array()
		for offset in 3:
			var point := Vector3i((faces[t * 3 + offset] * 10000.0).round())
			if not point_ids.has(point):
				point_ids[point] = first_triangle.size()
				first_triangle.append(t)
			var id: int = point_ids[point]
			ids.append(id)
			parents[_root(parents, t)] = _root(parents, first_triangle[id])
		for side in 3:
			var a := ids[side]
			var b := ids[(side + 1) % 3]
			var edge := Vector2i(mini(a, b), maxi(a, b))
			edge_uses[edge] = int(edge_uses.get(edge, 0)) + 1
	for uses: int in edge_uses.values():
		if uses % 2 != 0:
			return "表面有未封口的边"
	var grouped := {}
	for t in parents.size():
		var root := _root(parents, t)
		if not grouped.has(root):
			grouped[root] = []
		var group: Array = grouped[root]
		group.append(faces[t * 3])
		group.append(faces[t * 3 + 1])
		group.append(faces[t * 3 + 2])
	var parts: Array[Dictionary] = []
	for group: Array in grouped.values():
		var vertices := PackedVector3Array(group)
		var bounds := AABB(vertices[0], Vector3.ZERO)
		for v in vertices:
			bounds = bounds.expand(v)
		var tree := TriangleMesh.new()
		if not tree.create_from_faces(vertices):
			return "无法检查三角形表面"
		parts.append({"faces": vertices, "bounds": bounds.grow(0.0001), "tree": tree})
	var joined := PackedByteArray()
	joined.resize(parts.size())
	joined[0] = 1
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var part: Dictionary = parts[queue.pop_back()]
		for i in parts.size():
			if joined[i] or not part.bounds.intersects(parts[i].bounds):
				continue
			if _touch(part, parts[i]) or _touch(parts[i], part):
				joined[i] = 1
				queue.append(i)
	for i in joined.size():
		if not joined[i]:
			return "部件与主体分离，局部包围盒 %s" % parts[i].bounds
	return ""


static func _root(parents: PackedInt32Array, id: int) -> int:
	while parents[id] != id:
		id = parents[id]
	return id


static func _touch(a: Dictionary, b: Dictionary) -> bool:
	var vertices: PackedVector3Array = a.faces
	var tree: TriangleMesh = b.tree
	var bounds: AABB = b.bounds
	for i in range(0, vertices.size(), 3):
		for edge in 3:
			var p := vertices[i + edge]
			var q := vertices[i + (edge + 1) % 3]
			if bounds.intersects_segment(p, q) != null and not tree.intersect_segment(p, q).is_empty():
				return true
	# 一个封闭部件也可能完全嵌在另一个内部，此时表面没有相交边。
	var probe := (vertices[0] + vertices[1] + vertices[2]) / 3.0
	return bounds.has_point(probe) and _inside(probe, b.faces, bounds)


static func _inside(point: Vector3, faces: PackedVector3Array, bounds: AABB) -> bool:
	var ray := Vector3(0.813, 0.421, 0.397) * (bounds.size.length() + 1.0) * 2.0
	var crossings := 0
	for i in range(0, faces.size(), 3):
		var hit: Variant = Geometry3D.segment_intersects_triangle(point, point + ray,
			faces[i], faces[i + 1], faces[i + 2])
		if hit != null:
			crossings += 1
	return crossings % 2 != 0
