extends RefCounted
## 新目录跨档备用核验，只读资源；不凭驻留可行放开运行时身份门。
const SHA := "90d2378a4f480b9c97609038ac7913fd6f3f6b5f816d9ebe36bd935f88000fab"


static func run(path: String, output: String) -> int:
	if FileAccess.get_sha256(path)!=SHA or output.is_empty() or FileAccess.file_exists(output):
		return 1
	var catalog: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if catalog==null or not catalog.valid():
		return 1
	var rows: Array[Dictionary] = []
	for parent in 16:
		inspect(catalog.configurations.lod1_full[parent],catalog.configurations.lod2_guarded[parent],catalog,rows)
	var fail := 0
	for row: Dictionary in rows:
		fail+=int(not row.identity_equal or not row.layout_equal or not row.fixed_equal)
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify({"catalog_sha256":SHA,"rows":rows,"fail":fail,"runtime_enabled":false,"near_visual_verified":false},"\t"))
	file.close()
	print("[Guard2 catalog audit] pages=",rows.size()," fail=",fail," runtime_enabled=false")
	return fail


static func inspect(a: Dictionary, b: Dictionary, catalog: Resource, rows: Array[Dictionary]) -> void:
	var identity_equal := true
	var left: Dictionary = catalog.descriptors[a.path].canonical_identity
	var right: Dictionary = catalog.descriptors[b.path].canonical_identity
	for key: String in ["collision","owners","game_sources","parent","cell","ancestor"]:
		identity_equal=identity_equal and left.has(key) and typeof(left[key])==typeof(right.get(key)) and left[key]==right.get(key)
	var layout_equal: bool = var_to_bytes(a.get("cuts",[]))==var_to_bytes(b.get("cuts",[])) and a.get("children",[]).size()==b.get("children",[]).size()
	var source_a: Resource = ResourceLoader.load(a.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var source_b: Resource = ResourceLoader.load(b.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var fixed_equal := false
	if source_a!=null and source_b!=null and source_a.valid() and source_b.valid() and FileAccess.get_sha256(a.path)==a.sha256 and FileAccess.get_sha256(b.path)==b.sha256:
		var mesh_a: ArrayMesh = source_a.meshes[2]
		var mesh_b: ArrayMesh = source_b.meshes[2]
		fixed_equal=mesh_a.get_surface_count()==mesh_b.get_surface_count()
		if fixed_equal:
			for surface in mesh_a.get_surface_count():
				fixed_equal=fixed_equal and mesh_a.surface_get_primitive_type(surface)==mesh_b.surface_get_primitive_type(surface) and var_to_bytes(mesh_a.surface_get_arrays(surface))==var_to_bytes(mesh_b.surface_get_arrays(surface))
	rows.append({"a":a.path,"b":b.path,"identity_equal":identity_equal,"layout_equal":layout_equal,"fixed_equal":fixed_equal})
	if a.get("children",[]).size()==b.get("children",[]).size():
		for child in a.get("children",[]).size():
			inspect(a.children[child],b.children[child],catalog,rows)
