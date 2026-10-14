extends RefCounted
## 仅拆已认可街区块面的墙；在当前完整目录上证明精确成员关系。
const Preview := preload("res://scripts/tests/tokyo_residential_preview.gd")
const Diff := preload("res://scripts/experiments/tokyo_packed_mesh_difference.gd")
const Bundle := preload("res://scripts/tests/build_tokyo_wall_bundle.gd")
const Count := preload("res://scripts/experiments/tokyo_indexed_mesh.gd")
const CATALOG_SHA := "9a0985a329beffa9ec3188d2485d2102b0d2e50e2e37c35464fce07e21da551e"
const COMBINED_CATALOG_SHA := "c85682837bb5dd4dff6b8bf4703430a86b6dc5be7875169ac19d70fa7ee61833"


static func partition(blocks: ArrayMesh) -> Dictionary:
	if blocks == null or blocks.get_surface_count()!=1 or not Diff.supported(blocks):
		return {}
	var data := Diff.Read._read(blocks)
	var arrays := blocks.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	if colors.size()!=vertices.size():
		return {}
	var roofs := PackedInt32Array()
	var walls := PackedInt32Array()
	for first in range(0,data.indices.size(),3):
		var ids: PackedInt32Array = data.indices.slice(first,first+3)
		var roof := true
		var wall := true
		for id: int in ids:
			roof=roof and vertices[id].y==PackedFloat32Array([3.2])[0] and colors[id]==Color("a1aaa0")
			wall=wall and colors[id]==Color("69766f")
		if roof:
			roofs.append_array(ids)
		elif wall and (vertices[ids[1]]-vertices[ids[0]]).cross(vertices[ids[2]]-vertices[ids[0]]).y==0.0:
			walls.append_array(ids)
		else:
			return {}
	var persistent := Preview.Subset.subset(blocks,roofs)
	var removed := Preview.Subset.subset(blocks,walls)
	if not Diff.conserved(blocks,persistent,removed):
		return {}
	return {"roofs":persistent,"walls":removed}


static func run(root: String, output: String) -> int:
	var combined := OS.get_environment("AGL_TOKYO_NORTHWEST_COMBINED")=="1"
	var directory := "r212-northwest-catalog-a" if combined else "r204-northwest-catalog-a"
	var catalog_sha := COMBINED_CATALOG_SHA if combined else CATALOG_SHA
	var plan_directory := "r209-northwest-west-blocks-a" if combined else "r198-northwest-blocks-a"
	var plan_sha := "2a98d784a96835c2a6a4916e71568a697c8af3c97aec494a3f581a382264f7a7" if combined else "5eccbf4dc5e169d025c524ff4a432110065358f1fe54636cdb92e205b1d5c8e3"
	var old_directory := "r205-wall-bundle-a" if combined else "r192-wall-bundle-a"
	var old_sha := "26d5bd721176ff1ba8d954230995614251351a3b39e77ac688b550a5f5dc439c" if combined else "779d01fdc1f3545d5140fdb92ab65f62c60350c1f0c32eae1bf22bc477bf0973"
	var block_count := 232 if combined else 109
	var previous_walls := 5287 if combined else 3313
	var added_walls := 3358 if combined else 1974
	var added_roofs := 1219 if combined else 773
	var total_walls := previous_walls+added_walls
	if root.is_empty() or output.is_empty() or not preload("res://scripts/tests/build_tokyo_cells.gd").valid_sample_output(root.path_join(directory),output):
		return 1
	var catalog_path := root.path_join(directory+"/catalog.res")
	var plan_path := root.path_join(plan_directory+"/plan.json")
	var old_path := root.path_join(old_directory+"/report.json")
	if FileAccess.get_sha256(catalog_path)!=catalog_sha or FileAccess.get_sha256(plan_path)!=plan_sha or FileAccess.get_sha256(old_path)!=old_sha:
		return 1
	var catalog: Resource = ResourceLoader.load(catalog_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(plan_path))
	var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(old_path))
	if catalog==null or not catalog.valid() or catalog.configurations.size()!=11 or plan.variants[1].blocks.size()!=block_count or FileAccess.get_sha256(old.walls.path)!=old.walls.sha256:
		return 1
	var split := partition(Preview.blocks_mesh(plan.variants[1].blocks))
	var old_walls: ArrayMesh = ResourceLoader.load(old.walls.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if split.is_empty() or old_walls==null or Count.triangles(old_walls)!=previous_walls or Count.triangles(split.walls)!=added_walls or Count.triangles(split.roofs)!=added_roofs:
		return 1
	var walls := Diff.Join.join([old_walls,split.walls])
	if walls==null or not Diff.Join.conserved(walls,[old_walls,split.walls]) or Count.triangles(walls)!=total_walls:
		return 1
	if DirAccess.make_dir_recursive_absolute(output.path_join("roofs"))!=OK:
		return 1
	var wall_row := Bundle.save_checked(walls,output.path_join("walls.res"))
	if wall_row.is_empty():
		return 1
	var restored_walls: ArrayMesh = ResourceLoader.load(wall_row.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	var rows: Array[Dictionary] = []
	for name: String in catalog.configurations:
		var entry: Dictionary = catalog.configurations[name][11]
		if FileAccess.get_sha256(entry.path)!=entry.sha256:
			return 1
		var source: Resource = ResourceLoader.load(entry.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if source==null or not source.valid():
			return 1
		var difference := Diff.subtract(source.meshes[0],walls)
		if difference.is_empty() or difference.removed!=total_walls or not Diff.conserved(source.meshes[0],difference.mesh,walls):
			push_error("[Northwest walls] exact membership failed: "+name)
			return 1
		var roof_row := Bundle.save_checked(difference.mesh,output.path_join("roofs/"+name+".res"))
		if roof_row.is_empty():
			return 1
		var restored: ArrayMesh = ResourceLoader.load(roof_row.path,"",ResourceLoader.CACHE_MODE_IGNORE)
		if not Diff.conserved(source.meshes[0],restored,restored_walls) or FileAccess.get_sha256(entry.path)!=entry.sha256:
			return 1
		rows.append({"configuration":name,"source":entry.path,"source_sha256":entry.sha256,"roofs":roof_row,"full_faces":Count.triangles(source.meshes[0]),"roof_faces":Count.triangles(restored),"wall_faces":total_walls,"partition_proven":true})
		print("[Northwest walls] ",name," walls=",total_walls," saved partition=true")
	var file := FileAccess.open(output.path_join("report.json"),FileAccess.WRITE)
	if file==null:
		return 1
	file.store_string(JSON.stringify({"catalog_sha256":catalog_sha,"plan_sha256":FileAccess.get_sha256(plan_path),"old_bundle_sha256":FileAccess.get_sha256(old_path),"walls":wall_row,"rows":rows,"partition_proven":true,"runtime_integrated":false,"roof_catalog_requires_wall_owner":true,"fail":0},"  "))
	file.close()
	return 0
