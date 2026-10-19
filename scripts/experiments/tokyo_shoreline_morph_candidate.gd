extends RefCounted
## 离线共拓扑岸线原生消费；UV保存窄档相对位移，不在运行时生成网格。
const Layer := preload("res://scripts/rendering/tokyo_shoreline_layer.gd")


static func factor(scale: float) -> float:
	return Layer.morph_factor(scale)


static func shader_code(original: String) -> String:
	return Layer.morph_shader_code(original)


static func valid_point(point: Variant) -> bool:
	if not point is Array or point.size()!=2:
		return false
	for value: Variant in point:
		if not typeof(value) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value))>32768:
			return false
	return true


static func area(a: Vector2,b: Vector2,c: Vector2) -> float:
	return (float(b.x)-a.x)*(float(c.y)-a.y)-(float(b.y)-a.y)*(float(c.x)-a.x)


static func orientation_safe(wide: Array[Vector2],narrow: Array[Vector2]) -> bool:
	var start := area(wide[0],wide[1],wide[2])
	var end := area(narrow[0],narrow[1],narrow[2])
	var sign_value := 1.0 if start>0 else -1.0
	if minf(start*sign_value,end*sign_value)<=0:
		return false
	# 双精度标量直接展开边向量，避免中点Vector2舍入污染二次系数。
	var ex := float(wide[1].x)-wide[0].x
	var ey := float(wide[1].y)-wide[0].y
	var fx := float(wide[2].x)-wide[0].x
	var fy := float(wide[2].y)-wide[0].y
	var dx := (float(narrow[1].x)-narrow[0].x)-ex
	var dy := (float(narrow[1].y)-narrow[0].y)-ey
	var gx := (float(narrow[2].x)-narrow[0].x)-fx
	var gy := (float(narrow[2].y)-narrow[0].y)-fy
	var q := dx*gy-dy*gx
	var linear := ex*gy+dx*fy-ey*gx-dy*fx
	if absf(q)>1e-15:
		var t := -linear/(2.0*q)
		if t>0 and t<1 and (q*t*t+linear*t+start)*sign_value<=0:
			return false
	return true


static func build_mesh(groups: Array,slot: int) -> ArrayMesh:
	if slot<0 or slot>3:
		return null
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var offsets := PackedVector2Array()
	var bounds := AABB()
	var started := false
	for group: Variant in groups:
		if not group is Dictionary or not group.get("mode","") in ["morph","fallback"]:
			return null
		if (group.mode=="morph")!=(slot==0):
			continue
		if slot>0 and (not group.get("meshes") is Array or group.meshes.size()!=3):
			return null
		var data: Variant = group.get("mesh") if slot==0 else group.meshes[slot-1]
		if not data is Dictionary:
			return null
		var points: Variant = data.get("wide") if slot==0 else data.get("points")
		var targets: Variant = data.get("narrow") if slot==0 else points
		var indices: Variant = data.get("indices")
		if not points is Array or not targets is Array or points.size()!=targets.size() or not indices is Array or indices.size()>12000:
			return null
		if int(data.get("faces",-1))!=indices.size():
			return null
		for i in points.size():
			if not valid_point(points[i]) or not valid_point(targets[i]):
				return null
		for face: Variant in indices:
			if not face is Array or face.size()!=3:
				return null
			var wide: Array[Vector2] = []
			var narrow: Array[Vector2] = []
			for id: Variant in face:
				if not typeof(id) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(id)) or float(id)!=floorf(float(id)) or int(id)<0 or int(id)>=points.size():
					return null
				wide.append(Vector2(points[int(id)][0],points[int(id)][1]))
				narrow.append(Vector2(targets[int(id)][0],targets[int(id)][1]))
			if not orientation_safe(wide,narrow):
				return null
			# xz平面二维正面积对应Godot从上方看的顺时针正面。
			var order := [0,1,2] if area(wide[0],wide[1],wide[2])>0 else [0,2,1]
			for i: int in order:
				var position := Vector3(wide[i].x,.03,wide[i].y)
				var target := Vector3(narrow[i].x,.03,narrow[i].y)
				vertices.append(position)
				offsets.append(narrow[i]-wide[i])
				normals.append(Vector3.UP)
				colors.append(Color8(70,82,83))
				if not started:
					bounds = AABB(position,Vector3.ZERO)
					started = true
				bounds = bounds.expand(position).expand(target)
	if vertices.is_empty() or vertices.size()>36000:
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	arrays[Mesh.ARRAY_TEX_UV]=offsets
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	mesh.custom_aabb=bounds.grow(.005)
	return mesh
