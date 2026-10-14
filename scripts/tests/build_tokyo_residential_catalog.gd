extends "res://scripts/tests/build_tokyo_rail_catalog.gd"
## 复用规范切线与组件归档，只替换父11低楼；不启用正式默认。
const RESIDENTIAL_REPORT_SHA := "3fd47fc7672a3af62494459e69262b3fd284aff6d17b8095fa473d2adeaf882a"
const BASELINE_SHA := "b2590118e3073a24099ee1b661a89238a796d6c4069d71122238246e7fc620d9"


func run(root: String, output: String) -> int:
	var baseline := root.path_join("r150-native-a")
	var report_path := root.path_join("r161-native-patch-a/report.json")
	var report_sha := RESIDENTIAL_REPORT_SHA
	var north := OS.get_environment("AGL_TOKYO_RESIDENTIAL_NORTH_FULL")=="1"
	if north and OS.get_environment("AGL_TOKYO_RESIDENTIAL_WEST_FULL")=="1":
		return 1
	if OS.get_environment("AGL_TOKYO_RESIDENTIAL_WEST_FULL")=="1":
		report_path=root.path_join("r185-wall-bundle-a/full/report.json")
		report_sha="73595e06940db7984160e9951abae4c8821be5f4f05cb26a4e7be73ef4599843"
	if north:
		report_path=root.path_join("r192-wall-bundle-a/full/report.json")
		report_sha="8275da392426de266fead17981c0be7d3e094267d5e785751b91d695e35bd044"
	if not Components.Builder.valid_sample_output(baseline,output) or FileAccess.get_sha256(baseline.path_join("catalog.res"))!=BASELINE_SHA or FileAccess.get_sha256(report_path)!=report_sha:
		return 1
	var original: Resource = load(baseline.path_join("catalog.res"))
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(report_path))
	if original==null or not original.valid() or report.get("fail",1)!=0 or report.rows.size()!=11:
		return 1
	var component_path := baseline.path_join("components/manifest.bin")
	if Manifest.read(component_path,original,BASELINE_SHA).is_empty():
		return 1
	var file := FileAccess.open(component_path,FileAccess.READ)
	_components=file.get_var(false)
	file.close()
	_catalog=original.duplicate(true)
	_out=output
	_recipe={"directory":"r150-native-a","source_sha":BASELINE_SHA,"plan_sha":report_sha,"parent":11}
	DirAccess.make_dir_recursive_absolute(output.path_join("components"))
	var rows: Array = []
	var names: Dictionary = {}
	for row: Dictionary in report.rows:
		var name: String = row.configuration
		if not original.configurations.has(name) or names.has(name) or FileAccess.get_sha256(row.path)!=row.sha256:
			return 1
		names[name]=true
		var mesh: ArrayMesh = load(row.path)
		var entry: Dictionary = original.configurations[name][11]
		var source := _load(entry)
		if mesh==null or source==null:
			return 1
		# 归档页必须自包含，不能把临时候选的res路径保存成外部依赖。
		mesh=mesh.duplicate(true)
		var context := {"out":output.path_join(name),"configuration":name,"level":int(name.substr(3,1)),"parent_id":11,
			"collision_sha256":original.collision_sha256,"owners_sha256":original.owners_sha256,"game_sources":source.game_sources,
			"source_hash":(source.source_hash+report_sha).sha256_text(),"audit":false}
		DirAccess.make_dir_recursive_absolute(context.out)
		var changed := _replace_layer(entry,mesh,context,0)
		if changed.is_empty() or not verify_pages(entry,changed,mesh):
			return 1
		_catalog.configurations[name][11]=changed
		rows.append({"configuration":name,"before":Array(entry.triangles),"after":Array(changed.triangles)})
		print("[Residential catalog] ",name," low=",entry.triangles[0]," -> ",changed.triangles[0])
	if finish_rails(original,root,rows)!=0:
		return 1
	print("[Residential catalog] low/known/fixed/cuts/game_sources saved audit passed")
	return 0


static func verify_pages(before: Dictionary, after: Dictionary, expected: ArrayMesh) -> bool:
	if FileAccess.get_sha256(before.path)!=before.sha256 or FileAccess.get_sha256(after.path)!=after.sha256:
		return false
	var old: Resource = ResourceLoader.load(before.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var saved: Resource = ResourceLoader.load(after.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if old==null or saved==null or not old.valid() or not saved.valid() or old.game_sources!=saved.game_sources:
		return false
	if not Join.conserved(expected,[saved.meshes[0]]):
		return false
	for layer in [1,2]:
		if not Shared.same_mesh(old.meshes[layer],saved.meshes[layer]):
			return false
	if before.get("cuts",[])!=after.get("cuts",[]) or before.get("children",[]).size()!=after.get("children",[]).size():
		return false
	if not before.get("children",[]).is_empty():
		var pieces := Split.split(expected,before.cuts)
		if not Join.conserved(expected,pieces):
			return false
		for index in before.children.size():
			if not verify_pages(before.children[index],after.children[index],pieces[index]):
				return false
	return true
