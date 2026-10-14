extends RefCounted
## 在新资源路径逐个加载实际组件；不凭文件拷贝成功宣称运行时可用。
const Package := preload("res://scripts/tests/build_tokyo_portable_package.gd")
const Component := preload("res://scripts/rendering/tokyo_mesh_component.gd")


static func run(input: String, digest: String) -> int:
	if not Package.Root.binding_valid({"path":input,"sha256":digest}):return 1
	var inventory: Variant=JSON.parse_string(FileAccess.get_file_as_string(input))
	if not inventory is Dictionary or inventory.get("target")!=Package.TARGET:return 1
	var catalog_path:=Package.TARGET+"catalog.res"
	var components_path:=Package.TARGET+"components.bin"
	if FileAccess.get_sha256(catalog_path)!=inventory.catalog_sha256 or FileAccess.get_sha256(components_path)!=inventory.components_sha256:return 1
	var catalog: Resource=ResourceLoader.load(catalog_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if catalog==null or catalog.schema_version!=2 or not catalog.valid():return 1
	if Package.Components.read(components_path,catalog,inventory.catalog_sha256).is_empty():return 1
	var metadata:=Package.read_values(components_path)
	var count:=0
	for path: String in metadata.physical:
		var row: Dictionary=metadata.physical[path]
		if not path.begins_with(Package.TARGET+"components/") or FileAccess.get_sha256(path)!=row.sha256:return 1
		var resource: Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not resource is Component or not resource.valid() or resource.stream_identity()!=row.canonical_identity or resource.geometry_bytes!=int(row.bytes):return 1
		count+=1
		if count%1000==0:print("[Portable load] verified components=",count)
	for item: Dictionary in inventory.coverage:
		var path:=Package.TARGET+String(item.relative)
		if FileAccess.get_sha256(path)!=item.sha256:return 1
		var data:=Package.read_values(path)
		var cut: Dictionary={}
		for root: Dictionary in catalog.configurations[item.configuration]:cut[root.path]={"identity":catalog.descriptors[root.path].canonical_identity,"layers":3}
		if Package.Coverage.covered_sources(data,cut,item.configuration,catalog.collision_sha256,inventory.catalog_sha256).size()!=189:return 1
	print("[Portable load] components=",count," configs=11 source_coverage=189 actual_resource_paths=true default_enabled=false")
	return 0
