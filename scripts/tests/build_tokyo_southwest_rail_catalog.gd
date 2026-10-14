extends "res://scripts/tests/build_tokyo_rail_catalog.gd"
## 西南有限配方：精确原生序号选择，其他轨道/楼体保持，沿既有分页和覆盖归档。


func run(root: String, output: String) -> int:
	_recipe = {"directory":"r313-near-catalog-a","coverage_directory":"r313-near-coverage-a",
		"source_sha":"22a0c03939f61d6f15fc800a7c676d411cbee72c30806dd4f6fe98c92ef5fd30",
		"plan_sha":"9c6a0382a02d18e5703865480bb27845e8d673069b3093c87a0b21dfc6a31a10","parent":11}
	var source_path := root.path_join("r313-near-catalog-a/catalog.res")
	var plan_path := root.path_join("r324-clean-plan-a/plan.json")
	if root.is_empty() or not Components.Builder.valid_sample_output(root.path_join(_recipe.directory),output) \
		or FileAccess.get_sha256(source_path) != _recipe.source_sha or FileAccess.get_sha256(plan_path) != _recipe.plan_sha:
		return 1
	var original: Resource = load(source_path)
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	if original == null or not original.valid() or plan.get("catalog_sha256") != _recipe.source_sha \
		or plan.get("triangles",[]).size() != 924 or plan.get("selected_triangle_ids",[]).size() != 1748:
		return 1
	var selected := {}
	for value: Variant in plan.selected_triangle_ids:
		var index := int(value)
		if float(index) != float(value) or index < 0 or index >= 113362 or selected.has(index):
			return 1
		selected[index] = true
	var builder := Geometry.new()
	for triangle: Array in plan.triangles:
		if triangle.size() != 3:
			return 1
		var points: Array[Vector3] = []
		for corner: Array in triangle:
			if corner.size() != 2:
				return 1
			var point := Vector3(float(corner[0]),0.5,float(corner[1]))
			if not point.is_finite() or point.x < -8290 or point.x > -7310 or point.z < -2690 or point.z > -1710:
				return 1
			points.append(point)
		var normal_y := (points[1]-points[0]).cross(points[2]-points[0]).y
		if normal_y == 0:
			return 1
		builder.triangle(points[0],points[2] if normal_y < 0 else points[1],points[1] if normal_y < 0 else points[2],Color("858f88"))
	var replacement := Repack.repack(builder.mesh())
	var component_path := root.path_join("r313-near-catalog-a/components/manifest.bin")
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
		if source == null or source.meshes[2].get_surface_count() != 1:
			return 1
		var fixed: ArrayMesh = source.meshes[2]
		var surfaces: Array = [[fixed.surface_get_primitive_type(0),fixed.surface_get_arrays(0)]]
		if var_to_bytes(surfaces).hex_encode().sha256_text() != "f1a39f6d83b4361c0346402c4795e07113a4880dab5a0fba04a2f66fdc54ac18":
			return 1
		var data := Repack._read(fixed)
		if data.indices.size() != 113362*3:
			return 1
		var kept := PackedInt32Array()
		var removed := PackedInt32Array()
		for n in 113362:
			if selected.has(n):
				removed.append_array(data.indices.slice(n*3,n*3+3))
			else:
				kept.append_array(data.indices.slice(n*3,n*3+3))
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
		if changed.is_empty() or changed.triangles[2] != 112538 or changed.triangles[0] != entry.triangles[0] or changed.triangles[1] != entry.triangles[1]:
			return 1
		_catalog.configurations[configuration][11] = changed
		rows.append({"configuration":configuration,"before":Array(entry.triangles),"after":Array(changed.triangles)})
		print("[Southwest rail] ",configuration," fixed=112538 preserved=111614")
	return finish_rails(original,root,rows)
