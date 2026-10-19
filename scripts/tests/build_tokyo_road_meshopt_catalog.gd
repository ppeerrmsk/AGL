extends "res://scripts/tests/build_tokyo_rail_catalog.gd"
## 保留R324铁路成品，仅按原生有向三角差集替换次要道路。
const Import := preload("res://scripts/tests/tokyo_residential_patch.gd")

func run(root: String, output: String) -> int:
	_recipe = {"directory":"r324-southwest-rail-catalog-a","parent":11,
		"source_sha":"6417741a437cf3cca86fc2493491dd881f1f92f46b0c8c22054fe9861e31193b",
		"plan_sha":"0a3bb1d946562804019a06fe296e2adfb0f1ac067630fc8665c1ecdf9805ad2a"}
	var source_path := root.path_join(_recipe.directory+"/catalog.res")
	var reference_path := root.path_join("r337-road-reference.bin")
	var candidate_path := root.path_join("r336-road-repaired-a/road.bin")
	if root.is_empty() or not Components.Builder.valid_sample_output(root.path_join(_recipe.directory),output) \
		or FileAccess.get_sha256(source_path) != _recipe.source_sha \
		or FileAccess.get_sha256(reference_path) != "e219a698f41e2aa8bf1d0f6420212014a29c41fe2f109ee0cc14e85647f8ed85" \
		or FileAccess.get_sha256(candidate_path) != _recipe.plan_sha:
		return 1
	var reference := Import.decode(FileAccess.get_file_as_bytes(reference_path))
	var replacement := Import.decode(FileAccess.get_file_as_bytes(candidate_path))
	var original: Resource = load(source_path)
	if reference == null or replacement == null or original == null or not original.valid():
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
		var entry: Dictionary = original.configurations[configuration][11]
		var source := _load(entry)
		if source == null or entry.triangles[2] != 112538:
			return 1
		var fixed: ArrayMesh = source.meshes[2]
		var data := Repack._read(fixed)
		var arrays := fixed.surface_get_arrays(0)
		var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var kept := PackedInt32Array()
		var removed := PackedInt32Array()
		var exported := PackedFloat32Array()
		var road_height := PackedFloat32Array([0.38])[0]
		for first in range(0,data.indices.size(),3):
			var selected := true
			for offset in 3:
				selected = selected and positions[data.indices[first+offset]].y == road_height
			for offset in 3:
				var index: int = data.indices[first+offset]
				if selected:
					removed.append(index)
					var p := positions[index]
					var n := normals[index]
					var c := colors[index]
					exported.append_array(PackedFloat32Array([p.x,p.y,p.z,n.x,n.y,n.z,c.r,c.g,c.b,c.a]))
				else:
					kept.append(index)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(exported.to_byte_array())
		if removed.size() != 51942*3 or hash.finish().hex_encode() != FileAccess.get_sha256(reference_path):
			print("[Road meshopt] native reference mismatch ",configuration)
			return 1
		var retained := PathLOD.subset(fixed,kept)
		if not Diff.conserved(fixed,retained,PathLOD.subset(fixed,removed)):
			return 1
		var mesh := Repack.repack(Join.join([retained,replacement]))
		if not Join.conserved(mesh,[retained,replacement]):
			return 1
		var context := {"out":output.path_join(configuration),"configuration":configuration,"level":int(configuration.substr(3,1)),"parent_id":11,
			"collision_sha256":original.collision_sha256,"owners_sha256":original.owners_sha256,"game_sources":source.game_sources,
			"source_hash":(source.source_hash+str(_recipe.plan_sha)).sha256_text(),"audit":false}
		DirAccess.make_dir_recursive_absolute(context.out)
		var changed := _replace_layer(entry,mesh,context,2)
		if changed.is_empty() or changed.triangles[2] != 109894 or changed.triangles[0] != entry.triangles[0] or changed.triangles[1] != entry.triangles[1]:
			return 1
		_catalog.configurations[configuration][11] = changed
		rows.append({"configuration":configuration,"before":Array(entry.triangles),"after":Array(changed.triangles)})
		print("[Road meshopt] ",configuration," fixed=109894 retained=60596")
	return finish_rails(original,root,rows)
