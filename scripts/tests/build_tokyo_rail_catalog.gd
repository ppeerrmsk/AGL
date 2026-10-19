extends "res://scripts/tests/build_tokyo_block_catalog.gd"
## 父12所有配置共用铁路场坪；沿既有固定层切线归档，不修改楼体。
const Diff := preload("res://scripts/experiments/tokyo_packed_mesh_difference.gd")
const Repack := preload("res://scripts/experiments/tokyo_packed_mesh_reindex.gd")
const PathLOD := preload("res://scripts/tests/build_tokyo_path_lod.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const SOURCE_SHA := "f4139942c2708b515de82aa32f48c1de1f7cac6fe7b2eab37d9eee9047e2bc85"
const PLAN_SHA := "4a1b800482c20844ec3eda5be9cad63351d25f233b69b94e92deb58b40fe44b3"
var _recipe: Dictionary = {}


static func recipe(neighbor: bool = false) -> Dictionary:
	if neighbor:
		return {"directory":"r149-native-a","source_sha":"6cce469c95be5631fb46dcb405fe87c4f9ede0fee31df819dc8041b58f4f9f2d",
			"plan_directory":"r150-neighbor-rail-a","plan_sha":"13a7bd2e6f0fce560161fc0e504c787d19537cfa0b2bc980a69695b5433b3b30",
			"parent":11,"before":922,"after":525,"bounds":Rect2(-7300,-2700,1640,1000)}
	return {"directory":"r143-native-a","source_sha":SOURCE_SHA,"plan_directory":"r149-shared-rail-a","plan_sha":PLAN_SHA,
		"parent":12,"before":3579,"after":1417,"bounds":Rect2(-5660,-2700,960,1000)}


static func partition(mesh: ArrayMesh, replacement: bool = false) -> Dictionary:
	if not Diff.supported(mesh) or mesh.get_surface_count() != 1:
		return {}
	var data := Repack._read(mesh)
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if colors.size() != vertices.size():
		return {}
	var kept := PackedInt32Array()
	var removed := PackedInt32Array()
	var heights := PackedFloat32Array([0.5,0.58])
	var palette: Array[Color] = [Color("465253"),Color("a4aaa2")]
	if replacement:
		heights = PackedFloat32Array([0.5])
		palette = [Color("858f88")]
	for first in range(0,data.indices.size(),3):
		var selected := false
		for kind in heights.size():
			var match_all := true
			for offset in 3:
				var index: int = data.indices[first+offset]
				match_all = match_all and vertices[index].y == heights[kind] and colors[index] == palette[kind]
			selected = selected or match_all
		if selected:
			removed.append_array(data.indices.slice(first,first+3))
		else:
			kept.append_array(data.indices.slice(first,first+3))
	var a := PathLOD.subset(mesh,kept)
	var b := PathLOD.subset(mesh,removed)
	return {"kept":a,"removed":b,"count":removed.size()/3} if Diff.conserved(mesh,a,b) else {}


static func planned_mesh(plan: Dictionary, neighbor: bool = false) -> ArrayMesh:
	var rules := recipe(neighbor)
	var bounds: Rect2 = rules.bounds
	if plan.get("catalog_sha256") != SOURCE_SHA or plan.get("parent") != rules.parent or plan.get("height") != 0.5 \
		or plan.get("color") != "858f88" or not plan.get("shared_across_configurations",false) or plan.get("triangles",[]).size() != rules.after:
		return null
	var builder := Geometry.new()
	for triangle: Array in plan.triangles:
		if triangle.size() != 3:
			return null
		var points: Array[Vector3] = []
		for corner: Array in triangle:
			if corner.size() != 2:
				return null
			var point := Vector3(float(corner[0]),0.5,float(corner[1]))
			if not point.is_finite() or point.x < bounds.position.x or point.x > bounds.end.x or point.z < bounds.position.y or point.z > bounds.end.y:
				return null
			points.append(point)
		var normal_y := (points[1]-points[0]).cross(points[2]-points[0]).y
		if normal_y == 0.0:
			return null
		builder.triangle(points[0],points[2] if normal_y < 0 else points[1],points[1] if normal_y < 0 else points[2],Color("858f88"))
	return Repack.repack(builder.mesh())


func run(root: String, output: String) -> int:
	var neighbor := OS.get_environment("AGL_TOKYO_RAIL_NEIGHBOR") == "1"
	_recipe = recipe(neighbor)
	var source_path := root.path_join(_recipe.directory+"/catalog.res")
	var plan_path := root.path_join(_recipe.plan_directory+"/plan.json")
	if not Components.Builder.valid_sample_output(root.path_join(_recipe.directory),output) \
		or FileAccess.get_sha256(source_path) != _recipe.source_sha or FileAccess.get_sha256(plan_path) != _recipe.plan_sha:
		return 1
	var original: Resource = load(source_path)
	if original == null or not original.valid():
		return 1
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	var replacement := planned_mesh(plan,neighbor)
	if replacement == null or plan.configurations != Catalog.CONFIGURATIONS:
		# 顺序不具语义；随后按排序后的配置集核验。
		if replacement == null:
			return 1
		var names: Array = plan.configurations.duplicate()
		var expected: Array = Array(Catalog.CONFIGURATIONS)
		names.sort()
		expected.sort()
		if names != expected:
			return 1
	var component_path := root.path_join(_recipe.directory+"/components/manifest.bin")
	if Manifest.read(component_path,original,_recipe.source_sha).is_empty():
		return 1
	var input := FileAccess.open(component_path,FileAccess.READ)
	_components = input.get_var(false)
	input.close()
	_catalog = original.duplicate(true)
	_out = output
	DirAccess.make_dir_recursive_absolute(output.path_join("components"))
	var rows: Array = []
	for configuration: String in Catalog.CONFIGURATIONS:
		var entry: Dictionary = original.configurations[configuration][_recipe.parent]
		var source := _load(entry)
		if source == null:
			return 1
		var split := partition(source.meshes[2])
		if split.is_empty() or split.count != _recipe.before:
			push_error("Rail source mismatch: "+configuration)
			return 1
		var mesh := Repack.repack(Join.join([split.kept,replacement]))
		if not Join.conserved(mesh,[split.kept,replacement]):
			return 1
		var context := {"out":output.path_join(configuration),"configuration":configuration,"level":int(configuration.substr(3,1)),"parent_id":_recipe.parent,
			"collision_sha256":original.collision_sha256,"owners_sha256":original.owners_sha256,"game_sources":source.game_sources,
			"source_hash":(source.source_hash+_recipe.plan_sha).sha256_text(),"audit":false}
		DirAccess.make_dir_recursive_absolute(context.out)
		var changed := _replace_layer(entry,mesh,context,2)
		if changed.is_empty():
			return 1
		_catalog.configurations[configuration][_recipe.parent] = changed
		rows.append({"configuration":configuration,"before":Array(entry.triangles),"after":Array(changed.triangles)})
		print("[Rail catalog] ",configuration," fixed=",entry.triangles[2]," -> ",changed.triangles[2])
	return finish_rails(original,root,rows)


func finish_rails(original: Resource, root: String, rows: Array) -> int:
	for configuration: String in Catalog.CONFIGURATIONS:
		for parent in 16:
			if parent != _recipe.parent and original.configurations[configuration][parent] != _catalog.configurations[configuration][parent]:
				return 1
	var path := _out.path_join("catalog.res")
	if not _catalog.valid() or ResourceSaver.save(_catalog,path,ResourceSaver.FLAG_COMPRESS) != OK:
		return 1
	var saved: Resource = ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if saved == null or not saved.valid() or saved.configurations != _catalog.configurations or saved.descriptors != _catalog.descriptors:
		return 1
	var digest := FileAccess.get_sha256(path)
	for configuration: String in Catalog.CONFIGURATIONS:
		var input := FileAccess.open(root.path_join(str(_recipe.get("coverage_directory",_recipe.directory))+"/coverage-"+configuration+".bin"),FileAccess.READ)
		var previous: Dictionary = input.get_var(false)
		input.close()
		if previous.catalog_sha256 != _recipe.source_sha or not previous.verified:
			return 1
		var coverage := rewrite_coverage(previous,_changes,digest)
		if coverage.is_empty() or coverage.pages.size() != previous.pages.size() or coverage.sources.size() != previous.sources.size():
			return 1
		var file := FileAccess.open(_out.path_join("coverage-"+configuration+".bin"),FileAccess.WRITE)
		file.store_var(coverage)
		file.close()
	_components.catalog_sha256 = digest
	var physical: Dictionary = {}
	for row: Dictionary in _components.pages.values():
		for component: String in row.components:
			physical[component] = _components.physical[component]
	_components.physical = physical
	var component_path := _out.path_join("components/manifest.bin")
	var output := FileAccess.open(component_path,FileAccess.WRITE)
	output.store_var(_components)
	output.close()
	if Manifest.read(component_path,_catalog,digest).is_empty():
		return 1
	output = FileAccess.open(_out.path_join("report.json"),FileAccess.WRITE)
	output.store_string(JSON.stringify({"source_catalog_sha256":_recipe.source_sha,"plan_sha256":_recipe.plan_sha,"catalog_sha256":digest,
		"rows":rows,"changes":_changes,"changed_pages":_changes.size(),"production_enabled":false,"visual_acceptance":false},"\t"))
	output.close()
	print("[Rail catalog] saved changed=",_changes.size())
	return 0


static func audit_entry(before: Dictionary, after: Dictionary, counts: Dictionary) -> bool:
	if FileAccess.get_sha256(before.path) != before.sha256 or FileAccess.get_sha256(after.path) != after.sha256:
		return false
	var original: Resource = ResourceLoader.load(before.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var current: Resource = ResourceLoader.load(after.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if original == null or current == null or not original.valid() or not current.valid() or original.game_sources != current.game_sources:
		return false
	for layer in 2:
		if not Shared.same_mesh(original.meshes[layer],current.meshes[layer]):
			return false
	var old := partition(original.meshes[2])
	var changed := partition(current.meshes[2],true)
	if old.is_empty() or changed.is_empty() or not Join.conserved(old.kept,[changed.kept]):
		return false
	counts.pages += 1
	if before.get("children",[]).size() != after.get("children",[]).size() or before.get("cuts",[]) != after.get("cuts",[]):
		return false
	for index in before.get("children",[]).size():
		if not audit_entry(before.children[index],after.children[index],counts):
			return false
	return true


static func audit(root: String, directory: String, neighbor: bool = false) -> int:
	var rules := recipe(neighbor)
	var source_path := root.path_join(rules.directory+"/catalog.res")
	if FileAccess.get_sha256(source_path) != rules.source_sha:
		return 1
	var before: Resource = ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var after: Resource = ResourceLoader.load(directory.path_join("catalog.res"),"",ResourceLoader.CACHE_MODE_IGNORE)
	if before == null or after == null or not before.valid() or not after.valid() or before.regional_extension != after.regional_extension:
		return 1
	var digest := FileAccess.get_sha256(directory.path_join("catalog.res"))
	if Manifest.read(directory.path_join("components/manifest.bin"),after,digest).is_empty():
		return 1
	var counts := {"pages":0}
	for configuration: String in Catalog.CONFIGURATIONS:
		for parent in 16:
			if parent == rules.parent:
				if not audit_entry(before.configurations[configuration][parent],after.configurations[configuration][parent],counts):
					return 1
			elif before.configurations[configuration][parent] != after.configurations[configuration][parent]:
				return 1
		var file := FileAccess.open(directory.path_join("coverage-"+configuration+".bin"),FileAccess.READ)
		var coverage: Dictionary = file.get_var(false)
		file.close()
		if coverage.catalog_sha256 != digest or not coverage.verified:
			return 1
		for path: String in coverage.pages:
			if coverage.pages[path].sha256 != FileAccess.get_sha256(path) or coverage.pages[path].identity != after.descriptors[path].canonical_identity:
				return 1
	if counts.pages != 231:
		return 1
	print("[Rail saved audit] pages=",counts.pages," nonrail/low/known/cuts/other_parents unchanged=true")
	return 0
