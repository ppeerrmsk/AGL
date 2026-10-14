extends RefCounted
## 离线描边的原生消费端；不参与正式流送或每帧生成。
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")


static func build(data: Dictionary) -> ArrayMesh:
	if not data.get("width",0.0) in [0.35,1.0,2.0] or data.get("height",0.0)!=0.03:
		return null
	# JSON数字解码为float；逐通道比较数值，数组类型不应成为误拒绝条件。
	var rgb: Variant = data.get("rgb",[])
	if not rgb is Array or rgb.size()!=3:
		return null
	for i in 3:
		if not typeof(rgb[i]) in [TYPE_INT,TYPE_FLOAT] or float(rgb[i])!=float([70,82,83][i]):
			return null
	var points: Array = data.get("triangles",[])
	if points.is_empty() or points.size()%3!=0 or points.size()>36000 or points.size()*192>4*1024*1024:
		return null
	for point: Variant in points:
		if not point is Array or point.size()!=2:
			return null
		for value: Variant in point:
			if not typeof(value) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(value)) or absf(float(value))>32768.0:
				return null
	var builder := Geometry.new()
	for i in range(0,points.size(),3):
		var a := Vector3(points[i][0],0.03,points[i][1])
		var b := Vector3(points[i+1][0],0.03,points[i+1][1])
		var c := Vector3(points[i+2][0],0.03,points[i+2][1])
		var normal := (b-a).cross(c-a).y
		if normal==0.0 or not is_finite(normal):
			return null
		if normal>0:
			builder.triangle(a,b,c,Color8(70,82,83))
		else:
			builder.triangle(a,c,b,Color8(70,82,83))
	return builder.mesh()
