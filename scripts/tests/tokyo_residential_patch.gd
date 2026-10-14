extends RefCounted
## 道路共享区的原生导入/重载/同机位检查；不替换正式目录。
const Repack := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Signature := preload("res://scripts/tests/tokyo_mesh_signature.gd")


static func checks() -> bool:
	if decode(PackedByteArray())!=null or decode(PackedByteArray([0]))!=null:
		return false
	var raw := PackedFloat32Array([0,0,0,0,1,0,1,1,1,1,0,0,1,0,1,0,1,1,1,1,1,0,0,0,1,0,1,1,1,1]).to_byte_array()
	if decode(raw)==null:
		return false
	raw.encode_float(16,0)
	if decode(raw)!=null:
		return false
	raw.encode_float(16,1)
	raw.encode_float(24,2)
	return decode(raw)==null


static func decode(raw: PackedByteArray) -> ArrayMesh:
	if raw.is_empty() or raw.size()%120!=0:
		return null
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for offset in range(0,raw.size(),40):
		var p := Vector3(raw.decode_float(offset),raw.decode_float(offset+4),raw.decode_float(offset+8))
		var n := Vector3(raw.decode_float(offset+12),raw.decode_float(offset+16),raw.decode_float(offset+20))
		var c := Color(raw.decode_float(offset+24),raw.decode_float(offset+28),raw.decode_float(offset+32),raw.decode_float(offset+36))
		if not p.is_finite() or not n.is_finite() or absf(n.length()-1)>0.0001:
			return null
		for value: float in [c.r,c.g,c.b,c.a]:
			if not is_finite(value) or value<0 or value>1:
				return null
		positions.append(p)
		normals.append(n)
		colors.append(c)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=positions
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return Repack.repack(mesh)


static func run(parent: Node, root: String, output: String) -> int:
	var input := root.path_join("r161-original-patch-a")
	var catalog_path := root.path_join("r150-native-a/catalog.res")
	if DisplayServer.get_name()=="headless" or DirAccess.dir_exists_absolute(output) \
		or FileAccess.get_sha256(input.path_join("report.json"))!="41294349fb910f0706c9be9612c89358c0f17abf7af896b2345292f72bfe5bd6" \
		or FileAccess.get_sha256(catalog_path)!="b2590118e3073a24099ee1b661a89238a796d6c4069d71122238246e7fc620d9" \
		or FileAccess.get_sha256(input.path_join("shared-complete.bin"))!="92dcb6006889fb3ed6d141dca81bb1a932f0dd8506ba91db622dd3a5eef9aea9":
		return 1
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(input.path_join("report.json")))
	var catalog: Resource = load(catalog_path)
	var common := decode(FileAccess.get_file_as_bytes(input.path_join("shared-complete.bin")))
	if catalog==null or not catalog.valid() or common==null or report.rows.size()!=11 or report.get("full_original_source")!=true:
		return 1
	DirAccess.make_dir_recursive_absolute(output)
	var rows: Array = []
	for row: Dictionary in report.rows:
		var name: String = row.configuration
		if not catalog.configurations.has(name):
			return 1
		var path := input.path_join(name+"-outside.bin")
		if FileAccess.get_sha256(path)!=row.outside_sha256:
			return 1
		var outside := decode(FileAccess.get_file_as_bytes(path))
		if outside==null:
			return 1
		var mesh := Join.join([outside,common])
		var saved_path := output.path_join(name+".res")
		if ResourceSaver.save(mesh,saved_path,ResourceSaver.FLAG_COMPRESS)!=OK:
			return 1
		var saved: ArrayMesh = ResourceLoader.load(saved_path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if saved==null or Signature.of_mesh(mesh)!=Signature.of_mesh(saved):
			return 1
		rows.append({"configuration":name,"path":saved_path,"sha256":FileAccess.get_sha256(saved_path)})
		print("[R160 native patch] saved/reloaded ",name)
	var fail := await capture(parent,catalog,rows,output)
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"rows":rows,"fail":fail,"runtime_integrated":false,"continuous_camera_evidence":false},"\t"))
	file.close()
	return fail


static func capture(parent: Node, catalog: Resource, rows: Array, output: String) -> int:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1200,900)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.far=2000
	camera.size=450
	camera.position=Vector3(-6130,800,-1995)
	camera.look_at(Vector3(-6130,0,-2195),Vector3.UP)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-35,0)
	sun.light_energy=.8
	sun.shadow_enabled=false
	viewport.add_child(sun)
	var material := ShaderMaterial.new()
	material.shader=preload("res://resources/shaders/tokyo_volume_surface.gdshader")
	var nodes: Array[MeshInstance3D] = []
	for i in 3:
		var node := MeshInstance3D.new()
		node.material_override=material
		viewport.add_child(node)
		nodes.append(node)
	var fail := 0
	for row: Dictionary in rows:
		var entry: Dictionary = catalog.configurations[row.configuration][11]
		if FileAccess.get_sha256(entry.path)!=entry.sha256:
			fail+=1
			break
		var page: Resource = load(entry.path)
		for i in 3:
			nodes[i].mesh=page.meshes[i]
		for candidate: bool in [false,true]:
			nodes[0].mesh=load(row.path) if candidate else page.meshes[0]
			for frame in 3:
				await RenderingServer.frame_post_draw
			fail+=int(viewport.get_texture().get_image().save_png(output.path_join(row.configuration+("_candidate.png" if candidate else "_baseline.png")))!=OK)
	viewport.queue_free()
	await parent.get_tree().process_frame
	print("[R160 native patch] fixed_camera_pairs=",rows.size()," fail=",fail)
	return fail
