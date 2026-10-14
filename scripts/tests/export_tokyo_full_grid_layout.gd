extends RefCounted
## 整图接合读取已保存索引的精确自适应布局，不从日志字符串猜测切线或重切建筑。
const Index := preload("res://scripts/rendering/tokyo_cell_index.gd")


static func rectangle(value: Rect2) -> Array:
	return [value.position.x,value.position.y,value.size.x,value.size.y]


static func partition_valid(bounds: Rect2, cells: Array) -> bool:
	if cells.size()!=16 or not bounds.has_area() or not bounds.position.is_finite() or not bounds.size.is_finite():
		return false
	var area := 0.0
	for n in cells.size():
		var row: Variant = cells[n]
		if not row is Dictionary or row.get("id",-1)!=n or not row.get("bounds") is Rect2:
			return false
		var box: Rect2 = row.bounds
		if not box.has_area() or not box.position.is_finite() or not box.size.is_finite() or not bounds.encloses(box):
			return false
		area+=box.get_area()
		for previous in n:
			if box.intersection(cells[previous].bounds).get_area()>0.01:
				return false
	return absf(area-bounds.get_area())<0.1


static func run(root: String, routes_path: String, expected_sha: String, output: String) -> int:
	root=root.replace("\\","/").simplify_path().trim_suffix("/")
	output=output.replace("\\","/").simplify_path()
	var binary_path := output.get_basename()+".bin"
	if not root.is_absolute_path() or not root.ends_with("/tmp/tokyo-bay-volume") or output.get_base_dir()!=root \
			or FileAccess.file_exists(output) or FileAccess.file_exists(binary_path) or expected_sha.length()!=64 or FileAccess.get_sha256(routes_path)!=expected_sha:
		print("[Full grid layout] invalid output or route binding")
		return 1
	var routes: Variant = JSON.parse_string(FileAccess.get_file_as_string(routes_path))
	var spool_path := root.path_join("r343-full-source-spool-a/manifest.json")
	var spool: Variant = JSON.parse_string(FileAccess.get_file_as_string(spool_path))
	var grid_path := "res://resources/maps/tokyo_bay_detail_tiles_full.json"
	var grid: Variant = JSON.parse_string(FileAccess.get_file_as_string(grid_path))
	if not routes is Dictionary or not routes.get("routes") is Dictionary or routes.routes.size()!=256 \
			or not spool is Dictionary or not grid is Dictionary or spool.get("grid")!=grid.get("grid") \
			or spool.get("grid_sha256")!=FileAccess.get_sha256(grid_path) or not spool.get("scan_complete",false) \
			or spool.get("tiles",[]).size()!=256:
		print("[Full grid layout] incomplete spool/grid/routes")
		return 1
	var result := {"schema":1,"routes_sha256":expected_sha,"grid_sha256":spool.grid_sha256,
		"spool_sha256":FileAccess.get_sha256(spool_path),"tiles":[],"canonical_ready":false,"installed":false}
	var expanded: Dictionary = {}
	var boundary_path := OS.get_environment("AGL_TOKYO_BOUNDARY_LAYOUT")
	var boundary_sha := OS.get_environment("AGL_TOKYO_BOUNDARY_LAYOUT_SHA")
	if not boundary_path.is_empty():
		if boundary_sha.length()!=64 or FileAccess.get_sha256(boundary_path)!=boundary_sha: return 1
		var boundary: Variant=JSON.parse_string(FileAccess.get_file_as_string(boundary_path))
		if not boundary is Dictionary or boundary.get("tiles")!=31 or boundary.get("rows",[]).size()!=31: return 1
		for row: Dictionary in boundary.rows:
			var name:=str(row.get("tile",""))
			var coordinates:=name.split("_")
			if coordinates.size()!=3 or not coordinates[1].is_valid_int() or not coordinates[2].is_valid_int(): return 1
			var x:=int(coordinates[1]);var y:=int(coordinates[2])
			if x<0 or x>15 or y<0 or y>15 or (x!=15 and y!=0) or name!="detail_%02d_%02d"%[x,y] or expanded.has(name): return 1
			var expected: Array=[-16300+x*2000,-16300 if y==0 else -15700+y*2000,16300 if x==15 else -14300+x*2000,-13700+y*2000]
			if not row.get("bounds") is Array or not preload("res://scripts/rendering/tokyo_hlod_manifest.gd").same_numbers(row.bounds,expected) or row.get("family_replay_verified")!=true:
				print("[Boundary layout] bounds/family rejected ",name," actual=",row.get("bounds")," expected=",expected)
				return 1
			if FileAccess.get_sha256(String(row.source).path_join("city.json"))!=row.hashes.city:
				print("[Boundary layout] city digest rejected ",name," source=",row.source)
				return 1
			expanded[name]=row
		result["boundary_source_sha256"]=boundary_sha
	var seen: Dictionary = {}
	var source_count := 0
	for tile: Dictionary in spool.tiles:
		var name := str(tile.get("id",""))
		if seen.has(name) or not routes.routes.has(name):
			print("[Full grid layout] duplicate or missing route ",name)
			return 1
		seen[name]=true
		var path := str(routes.routes[name].get("index",""))
		var proof_path := path.get_base_dir().path_join("batch-status.json")
		var proof: Variant = JSON.parse_string(FileAccess.get_file_as_string(proof_path))
		if not proof is Dictionary or proof.get("tile")!=name or not proof.get("native_ready",false) \
				or proof.get("hashes",{}).get("index.res")!=FileAccess.get_sha256(path):
			print("[Full grid layout] source index binding rejected ",name)
			return 1
		var index: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not index is Index or not index.valid() or not partition_valid(index.bounds,index.cells):
			print("[Full grid layout] invalid index/partition ",name)
			if index is Index:
				print("[Full grid layout] bounds=",index.bounds," cells=",index.cells.map(func(row: Dictionary) -> Variant: return row.bounds))
			return 1
		var bounds: Array = expanded[name].bounds if expanded.has(name) else tile.get("bounds",[])
		if bounds.size()!=4 or index.bounds!=Rect2(bounds[0],bounds[1],bounds[2]-bounds[0],bounds[3]-bounds[1]):
			print("[Full grid layout] bounds differ ",name)
			return 1
		var cells: Array = []
		for entry: Dictionary in index.cells:
			var row := entry.duplicate(true)
			row.bounds=rectangle(entry.bounds)
			row.content_bounds=rectangle(entry.content_bounds)
			cells.append(row)
		result.tiles.append({"tile":name,"index":path,"index_sha256":FileAccess.get_sha256(path),
			"source_hash":index.source_hash,"source_count":index.source_count,"surface_only":index.surface_only,
			"bounds":rectangle(index.bounds),"cells":cells})
		source_count+=index.source_count
	result["source_records_including_boundary_copies"]=source_count
	# Variant二进制是精确权威。Godot JSON解析会将36.160000000000004读成36.16，不能作无损回读器。
	var binary := FileAccess.open(binary_path,FileAccess.WRITE)
	if binary==null:
		return 1
	binary.store_var(result,false)
	binary.close()
	binary=FileAccess.open(binary_path,FileAccess.READ)
	if binary==null:
		return 1
	var saved: Variant = binary.get_var(false)
	binary.close()
	if not saved is Dictionary or var_to_bytes(saved)!=var_to_bytes(result):
		print("[Full grid layout] binary exact roundtrip failed")
		return 1
	# 全精度JSON仅给离线工具浏览；绑定二进制摘要，不从JSON重新定义原生切线。
	result["exact_binary"]={"path":binary_path,"sha256":FileAccess.get_sha256(binary_path)}
	var encoded := JSON.stringify(result,"",true,true)
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(encoded)
	file.close()
	if FileAccess.get_file_as_string(output)!=encoded:
		return 1
	print("[Full grid layout] tiles=256 adaptive_cells=4096 source_records=",source_count," geometry_rebuilt=0 fail=0")
	return 0
