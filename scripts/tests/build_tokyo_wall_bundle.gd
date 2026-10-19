extends RefCounted
## 复用原生解码/重索引/有向属性守恒，生成可供有限归档接线的分层包。
const Patch := preload("res://scripts/tests/tokyo_residential_patch.gd")
const Join := preload("res://scripts/experiments/tokyo_packed_mesh_join.gd")
const Signature := preload("res://scripts/tests/tokyo_mesh_signature.gd")


static func save_checked(mesh: ArrayMesh, path: String) -> Dictionary:
	if mesh==null or ResourceSaver.save(mesh,path,ResourceSaver.FLAG_COMPRESS)!=OK:
		return {}
	var loaded: ArrayMesh = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if loaded==null or Signature.of_mesh(loaded)!=Signature.of_mesh(mesh):
		return {}
	return {"path":path,"sha256":FileAccess.get_sha256(path)}


static func run(root: String, output: String) -> int:
	var north := OS.get_environment("AGL_TOKYO_WALL_BUNDLE_NORTH")=="1"
	var input := root.path_join("r179-joint-patch-b")
	if north:
		input=root.path_join("r192-joint-patch-a")
	var report_path := input.path_join("report.json")
	var report_sha := "2250b64e69a251a7071a81047cc86558368e0d31f3a129a13381cfaed2cc2cc5" if north else "7eb42cc7426a10aa934e70d8f124e110b26398725cbbae23a64def68064f56e1"
	if DirAccess.dir_exists_absolute(output) or FileAccess.get_sha256(report_path)!=report_sha:
		return 1
	var full_path := input.path_join("shared-complete.bin")
	var roof_path := root.path_join("r182-roof-proxy-a/shared-roofs.bin")
	var wall_path := root.path_join("r183-wall-transition-a/walls.bin")
	var full_sha := "159183c9bff5d28c5c99a67c1abca4a611ca1c05d90b8a5da1bb7c6b2007533c"
	var roof_sha := "26af7663d53837adc5f4697ffe6a53f7beb260dce1e448a6c5db56b253861d13"
	var wall_sha := "2c25c0d0aaa8a5cfc9bc9c89c2fcfeb08edff82344f233c8ea4bf9ff5ee7db71"
	var wall_faces := 2689
	if north:
		roof_path=root.path_join("r192-wall-split-a/persistent.bin")
		wall_path=root.path_join("r192-wall-split-a/walls.bin")
		full_sha="b7d27ba94d37fcb018adc65fa5013089443e7d82348c07382db20b3fdd5733e4"
		roof_sha="bf3926a98868271b50d7e632df47f8cc2830fd598d7a66414b930b6689302191"
		wall_sha="6f84f7cedceaca9080c55c0ab0b07384f6e36e5f2cbd1ed0380ba320edcf21bd"
		wall_faces=3313
	if FileAccess.get_sha256(full_path)!=full_sha or FileAccess.get_sha256(roof_path)!=roof_sha or FileAccess.get_sha256(wall_path)!=wall_sha:
		return 1
	var full := Patch.decode(FileAccess.get_file_as_bytes(full_path))
	var roofs := Patch.decode(FileAccess.get_file_as_bytes(roof_path))
	var walls := Patch.decode(FileAccess.get_file_as_bytes(wall_path))
	if full==null or roofs==null or walls==null or not Join.conserved(full,[roofs,walls]):
		return 1
	var source: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	if source.rows.size()!=11 or not source.full_original_source:
		return 1
	DirAccess.make_dir_recursive_absolute(output.path_join("full"))
	DirAccess.make_dir_recursive_absolute(output.path_join("roofs"))
	var wall_row := save_checked(walls,output.path_join("walls.res"))
	if wall_row.is_empty():
		return 1
	var rows: Array = []
	var names: Dictionary = {}
	for row: Dictionary in source.rows:
		var name: String = row.configuration
		if name.contains("/") or name.contains("\\") or names.has(name):
			return 1
		names[name]=true
		var path := input.path_join(name+"-outside.bin")
		if FileAccess.get_sha256(path)!=row.outside_sha256:
			return 1
		var outside := Patch.decode(FileAccess.get_file_as_bytes(path))
		if outside==null:
			return 1
		var complete := Join.join([outside,full])
		var persistent := Join.join([outside,roofs])
		if complete==null or persistent==null or not Join.conserved(complete,[persistent,walls]):
			return 1
		var full_row := save_checked(complete,output.path_join("full/"+name+".res"))
		var roof_row := save_checked(persistent,output.path_join("roofs/"+name+".res"))
		if full_row.is_empty() or roof_row.is_empty():
			return 1
		var reloaded_full: ArrayMesh = ResourceLoader.load(full_row.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var reloaded_roofs: ArrayMesh = ResourceLoader.load(roof_row.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		var reloaded_walls: ArrayMesh = ResourceLoader.load(wall_row.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not Join.conserved(reloaded_full,[reloaded_roofs,reloaded_walls]):
			return 1
		rows.append({"configuration":name,"full":full_row,"roofs":roof_row,"full_faces":row.new_total,"roof_faces":int(row.new_total)-wall_faces,"partition_proven":true})
		print("[R185 native wall bundle] ",name," saved/reloaded partition=true")
	var full_rows: Array = []
	for row: Dictionary in rows:
		full_rows.append({"configuration":row.configuration,"path":row.full.path,"sha256":row.full.sha256})
	var full_report := FileAccess.open(output.path_join("full/report.json"),FileAccess.WRITE)
	if full_report==null:
		return 1
	full_report.store_string(JSON.stringify({"rows":full_rows,"fail":0,"partition_proven":true,"runtime_integrated":false},"  "))
	full_report.close()
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify({"rows":rows,"walls":wall_row,"source_report_sha256":FileAccess.get_sha256(report_path),"full_report_sha256":FileAccess.get_sha256(output.path_join("full/report.json")),"partition_proven":true,"runtime_integrated":false,"roof_catalog_requires_wall_owner":true},"  "))
	file.close()
	return 0
