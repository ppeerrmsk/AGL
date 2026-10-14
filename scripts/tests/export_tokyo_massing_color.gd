extends RefCounted
## 只导出现成合并街坊的原生属性；不重烘几何、不修改显示/碰撞所有者。
const Contract := preload("res://scripts/rendering/tokyo_hlod_manifest.gd")
const Catalog := preload("res://scripts/rendering/tokyo_canonical_catalog.gd")
const Components := preload("res://scripts/rendering/tokyo_component_manifest.gd")
const Export := preload("res://scripts/tests/tokyo_residential_preview.gd")


static func run(input: String, digest: String, output: String) -> int:
	if not Contract.binding({"path":input,"sha256":digest}) or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var package: Variant = JSON.parse_string(FileAccess.get_file_as_string(input))
	if not package is Dictionary or not package.get("native") is Dictionary: return 1
	var native: Dictionary = package.native
	if not Contract.binding(native.get("catalog")) or not Contract.binding(native.get("components")): return 1
	var catalog: Resource = load(native.catalog.path)
	if not catalog is Catalog or catalog.schema_version!=2 or not catalog.valid(): return 1
	var data := Components.read(native.components.path,catalog,native.catalog.sha256)
	if data.is_empty() or DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var rows: Array[Dictionary] = []
	var configuration := "lod3_full"
	for entry: Dictionary in catalog.configurations[configuration]:
		var row: Dictionary = data.pages[entry.path]
		for kind in 2:
			var mapping: Array = row.mapping[kind]
			var descriptor: Dictionary = row.components[mapping[0]]
			if not Contract.binding(descriptor): return 1
			var component: Resource = ResourceLoader.load(mapping[0],"",ResourceLoader.CACHE_MODE_IGNORE)
			if component==null or not component.valid() or component.stream_identity()!=descriptor.canonical_identity or component.geometry_bytes!=descriptor.bytes: return 1
			var mesh: ArrayMesh = component.meshes[int(mapping[1])]
			var id_value := int(row.canonical_identity.parent)
			var path := output.path_join("root_%02d_%d.attributes" % [id_value,kind])
			if Export.export_attributes(mesh,path)!=0 or FileAccess.get_file_as_bytes(path).size()!=int(entry.triangles[kind])*120: return 1
			var bounds := mesh.get_aabb()
			rows.append({"parent":id_value,"kind":kind,"source":descriptor,"binding":{"path":path,"sha256":FileAccess.get_sha256(path)},
				"faces":int(entry.triangles[kind]),"bounds":[bounds.position.x,bounds.position.z,bounds.end.x,bounds.end.z]})
		print("[Massing color source] roots=",rows.size()/2,"/16 original components unchanged")
	if rows.size()!=32: return 1
	var file := FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"schema":1,"package_sha256":digest,"catalog":native.catalog,"components":native.components,
		"configuration":configuration,"rows":rows,"record_bytes":120,"original_components_unchanged":true,"runtime_integrated":false},"\t"))
	file.close()
	return 0
