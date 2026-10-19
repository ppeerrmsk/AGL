extends RefCounted
## 只读反事实：调用原Pareto组合逻辑，不放宽运行时16块门。
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")
const Volume := preload("res://scripts/rendering/tokyo_volume_overlay.gd")
const Archive := preload("res://scripts/rendering/tokyo_volume_archive.gd")

static func run(path: String, output: String) -> int:
	if output.is_empty() or FileAccess.file_exists(output) or FileAccess.get_sha256(path) != "6417741a437cf3cca86fc2493491dd881f1f92f46b0c8c22054fe9861e31193b":
		return 1
	var catalog: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if catalog == null or not catalog.valid():
		return 1
	var logical := Vector2(1600,900)
	var rows: Array[Dictionary] = []
	for center: Vector2 in [Vector2(-7800,-2200),Vector2(-5600,-2900)]:
		for scale_value: float in [0.06,0.13,0.26,0.52]:
			var canvas := Transform2D(-deg_to_rad(14.0),Vector2.ZERO).scaled(Vector2.ONE*scale_value)
			canvas.origin = logical*.5-canvas.basis_xform(center)
			var inverse := canvas.affine_inverse()
			var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
			for corner: Vector2 in [Vector2(logical.x,0),logical,Vector2(0,logical.y)]:
				view = view.expand(inverse*corner)
			var ground := Volume.VolumeProjection.ground_basis(canvas,Volume.TILT).inverse()
			var camera := ground*Volume.VolumeProjection.camera_basis(canvas,Volume.TILT).z
			var sun := ground*Basis.from_euler(Vector3(deg_to_rad(-50),deg_to_rad(-35),0)).z
			var roof := -Vector2(camera.x,camera.z)/camera.y
			var shadow := -Vector2(sun.x,sun.z)/sun.y
			var name_value := "lod%d_full" % Archive.choose_level(-1,scale_value)
			var parents: Array[Dictionary] = []
			parents.assign(catalog.configurations[name_value])
			for cap in [16,32,64]:
				var context := {"view":view,"canvas":canvas,"logical":logical,"roof":roof,"shadow":shadow,"cap":cap,"visited":0}
				var frontier: Array[Dictionary] = [{"entries":[],"active":0,"faces":0,"bytes":0}]
				for parent: Dictionary in parents:
					frontier = Cut._combine(frontier,Cut._frontier(parent,context),cap)
				if frontier.is_empty():
					return 1
				var best: Dictionary = {}
				for state: Dictionary in frontier:
					if best.is_empty() or Cut._better(state,best):
						best = state
				if cap == 16:
					var actual := Cut.choose(parents,view,canvas,logical,roof,shadow)
					if actual.triangles != best.faces or actual.bytes != best.bytes or actual.active != best.active:
						return 1
				rows.append({"center":[center.x,center.y],"scale":scale_value,"configuration":name_value,"cap":cap,"active":best.active,"faces":best.faces,"bytes":best.bytes})
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null:
		return 1
	file.store_string(JSON.stringify({"catalog_sha256":FileAccess.get_sha256(path),"metadata_only":true,"runtime_changed":false,"paired_handoff_verified":false,"rows":rows},"\t"))
	file.close()
	print("[Capacity probe] rows=",rows.size()," metadata_only=true")
	return 0
