extends RefCounted
## 实际三层候选的引擎成本与同位画面；不提供正式目录或全图覆盖凭据。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Read := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const MapProjection := preload("res://scripts/experiments/volume_projection.gd")
const Cut := preload("res://scripts/experiments/tokyo_spatial_cut.gd")


static func mesh(binding: Dictionary) -> ArrayMesh:
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return null
	if binding.has("mesh"):
		if not Contract.binding(binding.mesh) or FileAccess.get_sha256(binding.mesh.path)!=binding.mesh.sha256: return null
		var native: Resource=ResourceLoader.load(binding.mesh.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		return native if native is ArrayMesh else null
	var bytes := FileAccess.get_file_as_bytes(binding.path)
	if bytes.is_empty() or bytes.size()%120!=0: return null
	var values := bytes.to_float32_array()
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for i in range(0,values.size(),10):
		for j in 10:
			if not is_finite(values[i+j]): return null
		vertices.append(Vector3(values[i],values[i+1],values[i+2]))
		normals.append(Vector3(values[i+3],values[i+4],values[i+5]))
		colors.append(Color(values[i+6],values[i+7],values[i+8],values[i+9]))
	var arrays: Array=[]
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices
	arrays[Mesh.ARRAY_NORMAL]=normals
	arrays[Mesh.ARRAY_COLOR]=colors
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return Read.repack(result)


static func run(parent: Node, path: String, expected: String) -> int:
	if not Contract.sha(expected) or FileAccess.get_sha256(path)!=expected: return 1
	var input: Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not input is Dictionary: return 1
	var output: String=input.get("output","")
	if not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	# 完整来源片按真实档位导出；不能以固定机位截取代替可移动范围。
	if input.has("export_index"):
		if not Contract.binding(input.export_index) or not input.get("source_count") is float \
			or input.source_count!=int(input.source_count) or not input.get("level") is float or input.level!=int(input.level): return 1
		return preload("res://scripts/tests/tokyo_residential_preview.gd").export_index(input.export_index.path,
			input.export_index.sha256,int(input.source_count),output,int(input.level),bool(input.get("middle",false)))
	if not input.get("layers") is Array or input.layers.size()!=3: return 1
	var meshes: Array[ArrayMesh]=[]
	var entry := {"path":"candidate_root","children":[],"boxes":[],"triangles":[],"bytes":0}
	for binding: Dictionary in input.layers:
		var value := mesh(binding)
		if value==null: return 1
		meshes.append(value)
		entry.boxes.append(value.get_aabb())
		entry.triangles.append(Count.triangles(value))
		entry.bytes+=Read.decoded_bytes(value)
	var source := mesh(input.original_known)
	if source==null: return 1
	if input.has("keep_mask"):
		var replacement := preserve_known(source,meshes[1],input.layers[1],input.keep_mask)
		if replacement==null: return 1
		meshes[1]=replacement
		entry.boxes[1]=replacement.get_aabb()
		entry.triangles[1]=Count.triangles(replacement)
		entry.bytes=0
		for value: ArrayMesh in meshes: entry.bytes+=Read.decoded_bytes(value)
	var probe := preload("res://scripts/tests/tokyo_native_refinement_probe.gd").new()
	probe.branching=2
	var writer: RefCounted
	if input.get("save_pages",false):
		if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
		writer=preload("res://scripts/tests/tokyo_partition_page_writer.gd").new()
		writer.output=output.path_join("pages")
		probe.page_sink=writer.emit
	var tree: Dictionary=probe._split(entry,meshes,8)
	if probe.failed: return 1
	var partition: Dictionary={}
	if writer!=null:
		partition=writer.finish(tree,expected)
		if partition.is_empty(): return 1
	var roots: Array[Dictionary]=[tree]
	var rows: Array=[]
	for pose: Dictionary in input.poses:
		var center := Vector2(pose.center[0],pose.center[1])
		var scale_value: float=pose.scale
		var size := Vector2(1600,900)
		var canvas := Transform2D(float(pose.rotation),Vector2.ZERO).scaled(Vector2.ONE*scale_value)
		canvas.origin=size*.5-canvas*center
		var inverse := canvas.affine_inverse()
		var view := Rect2(inverse*Vector2.ZERO,Vector2.ZERO)
		for corner in [Vector2(size.x,0),size,Vector2(0,size.y)]: view=view.expand(inverse*corner)
		var ray := MapProjection.ground_basis(canvas,deg_to_rad(38)).inverse()*MapProjection.camera_basis(canvas,deg_to_rad(38)).z
		var cut := Cut.choose(roots,view,canvas,size,-Vector2(ray.x,ray.z)/ray.y,Vector2.ZERO,16)
		rows.append({"pose":pose,"faces":cut.triangles,"bytes":cut.bytes,"pages":cut.active,"within_budget":cut.within_budget,"solver_usec":cut.solver_usec})
		print("[tagged low actual cut] ",rows[-1])
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	for kind in 3:
		if ResourceSaver.save(meshes[kind],output.path_join("layer_%d.res"%kind),ResourceSaver.FLAG_COMPRESS)!=OK: return 1
	var captures: Array=[]
	if input.get("visual",false):
		if DisplayServer.get_name()=="headless": return 1
		captures=await capture(parent,meshes,source,input.poses[0],output)
		if captures.size()!=6: return 1
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"input_sha256":expected,"rows":rows,"conserved_splits":probe.conserved_splits,"captures":captures,"partition":partition,
		"runtime_integrated":false,"full_map_coverage_verified":false,"performance_accepted":false},"\t"))
	file.close()
	return 0


static func preserve_known(source: ArrayMesh, candidate: ArrayMesh, attributes: Dictionary, binding: Dictionary) -> ArrayMesh:
	if not Contract.binding(binding) or FileAccess.get_sha256(binding.path)!=binding.sha256: return null
	var flags := FileAccess.get_file_as_bytes(binding.path)
	if flags.size()!=Count.triangles(source): return null
	var owners := PackedInt32Array()
	var kept := 0
	for flag: int in flags:
		if flag not in [0,1]: return null
		owners.append(flag)
		kept+=int(flag==0)
	var split := preload("res://scripts/experiments/tokyo_spatial_split.gd")
	var original := split.partition(source,owners,2)
	if original.size()!=2 or not preload("res://scripts/experiments/tokyo_packed_mesh_join.gd").conserved(source,original): return null
	# Python候选前缀必须逐字节等于真实原生保留面的解码属性，拒绝错序/错mask。
	var payload := preload("res://scripts/tests/tokyo_residential_preview.gd").export_payload(original[0])
	var data := FileAccess.get_file_as_bytes(attributes.path)
	if payload.is_empty() or kept>Count.triangles(candidate) or payload.attributes!=data.slice(0,kept*120): return null
	owners.resize(Count.triangles(candidate))
	owners.fill(1)
	for n in kept: owners[n]=0
	var parts := split.partition(candidate,owners,2)
	if parts.size()!=2: return null
	var inputs: Array[ArrayMesh]=[original[0],parts[1]]
	var joined := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd").join(inputs)
	return joined if preload("res://scripts/experiments/tokyo_packed_mesh_join.gd").conserved(joined,inputs) else null


static func capture(parent: Node, meshes: Array[ArrayMesh], original: ArrayMesh, pose: Dictionary, output: String) -> Array:
	var viewport := SubViewport.new()
	viewport.size=Vector2i(1600,900)
	viewport.own_world_3d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	parent.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.far=10000
	var canvas := Transform2D.IDENTITY
	var basis := MapProjection.camera_basis(canvas,deg_to_rad(38))
	var ground := MapProjection.ground_basis(canvas,deg_to_rad(38))
	var center := ground*Vector3(pose.center[0],0,pose.center[1])
	camera.transform=Transform3D(basis,center+basis.z*3000)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-50,-35,0)
	sun.light_energy=.8
	sun.shadow_enabled=false
	viewport.add_child(sun)
	var nodes: Array[MeshInstance3D]=[]
	for kind in 3:
		var material := ShaderMaterial.new()
		material.shader=preload("res://resources/shaders/tokyo_volume_surface.gdshader")
		material.set_shader_parameter("facade_detail",kind==1)
		var node := MeshInstance3D.new()
		node.mesh=meshes[kind]
		node.basis=ground
		node.material_override=material
		viewport.add_child(node)
		nodes.append(node)
	var results: Array=[]
	for scale_value: float in [pose.scale,2.5,5.0]:
		camera.size=900/scale_value
		for candidate in [false,true]:
			nodes[1].mesh=meshes[1] if candidate else original
			for frame in 3: await RenderingServer.frame_post_draw
			var image_path := output.path_join("scale_%.3f_%s.png"%[scale_value,"candidate" if candidate else "original"])
			if viewport.get_texture().get_image().save_png(image_path)!=OK:
				viewport.queue_free()
				await parent.get_tree().process_frame
				return []
			results.append(image_path)
	viewport.queue_free()
	await parent.get_tree().process_frame
	return results
