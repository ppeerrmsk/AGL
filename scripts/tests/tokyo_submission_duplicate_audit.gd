extends RefCounted
## 仅离线检查已记录峰值；完整角点相等不代表可直接删运行时节点。
const Signature := preload("res://scripts/tests/tokyo_mesh_signature.gd")


static func run(root: String, output: String) -> int:
	var catalog_path := root.path_join("r162-native-b/catalog.res")
	var snapshot_path := root.path_join("r163-review-a-images/r129_guarded_review.json")
	var catalog_sha := "c0311651371c29025b8db0a8618adb57a2faeb39ab59c4751ee743b3d9c346ca"
	var snapshot_sha := "6db23c1a94ab4ccd3963b7c3402a6221504b6c0b8a9eac62a28c121b6a67c30e"
	var northwest := OS.get_environment("AGL_TOKYO_SUBMISSION_NORTHWEST")=="1"
	if northwest:
		catalog_path=root.path_join("r204-northwest-catalog-a/catalog.res")
		snapshot_path=root.path_join("r206-review-b-images/r188_wall_review.json")
		catalog_sha="9a0985a329beffa9ec3188d2485d2102b0d2e50e2e37c35464fce07e21da551e"
		snapshot_sha="dfe1c5991f09680ccc00441cce1b4e0ee764ccbd1f3a8734f948d1c5610f8255"
	if output.is_empty() or FileAccess.file_exists(output) or FileAccess.get_sha256(catalog_path)!=catalog_sha or FileAccess.get_sha256(snapshot_path)!=snapshot_sha:
		return 1
	var catalog: Resource = load(catalog_path)
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(snapshot_path))
	if catalog==null or not catalog.valid():
		return 1
	var peak: Dictionary = report.geometry.runtime_peak_record if northwest else report.rows[1].state.peak_snapshot
	var colors: Dictionary = {}
	var seen: Dictionary = {}
	var total := 0
	var duplicate := 0
	var unique := 0
	var rows: Array = []
	for cell: Dictionary in peak.cells.values():
		var layers: Array = cell.layers if northwest else cell.submitted
		var count := int(layers[2])
		if count==0:
			continue
		if not catalog.descriptors.has(cell.path):
			return 1
		var page: Resource = ResourceLoader.load(cell.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var expected_sha := entry_digest(catalog.configurations[page.configuration],cell.path) if page!=null else ""
		if page==null or not page.valid() or page.stream_identity()!=catalog.descriptors[cell.path].canonical_identity or expected_sha.is_empty() or FileAccess.get_sha256(cell.path)!=expected_sha:
			return 1
		var signature := Signature.of_mesh(page.meshes[2])
		var actual := 0
		var repeated := 0
		var local_colors: Dictionary = {}
		for raw: PackedByteArray in signature:
			# 循环起点不同仍视作同向三角；每角40字节，保留XYZ/NXYZ/RGBA。
			var a := raw.hex_encode()
			var b := (raw.slice(40)+raw.slice(0,40)).hex_encode()
			var c := (raw.slice(80)+raw.slice(0,80)).hex_encode()
			var key: String = [a,b,c].min()
			var copies := int(signature[raw])
			# 颜色仅作诊断分桶；原有重复判据仍使用完整XYZ/法线/颜色字节。
			var color_key := ""
			for corner in 3:
				var offset := corner*40+24
				color_key+=Color(raw.decode_float(offset),raw.decode_float(offset+4),raw.decode_float(offset+8),raw.decode_float(offset+12)).to_html()+":"
			local_colors[color_key]=int(local_colors.get(color_key,0))+copies
			colors[color_key]=int(colors.get(color_key,0))+copies
			actual+=copies
			repeated+=copies if seen.has(key) else maxi(0,copies-1)
			if not seen.has(key):
				unique+=1
			seen[key]=true
		if actual!=count:
			return 1
		total+=actual
		duplicate+=repeated
		rows.append({"path":cell.path,"file_sha256":FileAccess.get_sha256(cell.path),"faces":actual,"layers":layers,"colors":local_colors,"duplicate_in_iteration":repeated})
	if northwest and total!=int(peak.layers[2]):
		return 1
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify({"rows":rows,"fixed_faces":total,"colors":colors,"catalog_sha256":catalog_sha,"snapshot_sha256":snapshot_sha,"exact_duplicate_faces":duplicate,"unique_faces":unique,"runtime_changed":false,"overlap_or_material_equivalence_proven":false},"\t"))
	file.close()
	print("[Submission duplicate audit] fixed=",total," exact duplicates=",duplicate," unique=",unique)
	return 0


static func entry_digest(entries: Array, path: String) -> String:
	for entry: Dictionary in entries:
		if entry.path==path:
			return entry.get("sha256","")
		var found := entry_digest(entry.get("children",[]),path)
		if not found.is_empty():
			return found
	return ""
