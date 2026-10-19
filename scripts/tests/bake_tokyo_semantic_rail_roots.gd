extends RefCounted
## 只删被原生全属性记录准确匹配的站场轨道面；顶点/法线/颜色及其余索引原样保留。
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")
const Components := preload("res://scripts/tests/build_tokyo_mesh_components.gd")


static func record(arrays: Array, ids: PackedInt32Array, face: int) -> PackedByteArray:
	var values := PackedFloat32Array()
	for corner in 3:
		var id := ids[face*3+corner]
		var p: Vector3 = arrays[Mesh.ARRAY_VERTEX][id]
		var n: Vector3 = arrays[Mesh.ARRAY_NORMAL][id]
		var c: Color = arrays[Mesh.ARRAY_COLOR][id]
		values.append_array(PackedFloat32Array([p.x,p.y,p.z,n.x,n.y,n.z,c.r,c.g,c.b,c.a]))
	return values.to_byte_array()


static func select(mesh: ArrayMesh, wanted: Dictionary) -> PackedInt32Array:
	var result := PackedInt32Array()
	if mesh == null or mesh.get_surface_count()!=1: return result
	var arrays := mesh.surface_get_arrays(0)
	if arrays[Mesh.ARRAY_INDEX]==null or arrays[Mesh.ARRAY_NORMAL]==null or arrays[Mesh.ARRAY_COLOR]==null: return result
	var ids: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var actual: Dictionary = {}
	for face in ids.size()/3:
		var h := vertices[ids[face*3]].y
		if h!=float(PackedFloat32Array([0.5])[0]) and h!=float(PackedFloat32Array([0.58])[0]): continue
		if vertices[ids[face*3+1]].y!=h or vertices[ids[face*3+2]].y!=h: continue
		var key := record(arrays,ids,face).hex_encode()
		if not wanted.has(key): continue
		actual[key]=int(actual.get(key,0))+1
		result.append(face)
	# 同几何重复项必须逐重数完全相等，不任取一个来源或只删前N面。
	if actual!=wanted: return PackedInt32Array()
	return result


static func filtered(mesh: ArrayMesh, removed: PackedInt32Array) -> ArrayMesh:
	if mesh==null or mesh.get_surface_count()!=1 or removed.is_empty(): return null
	var source: Dictionary=mesh.get("_surfaces")[0]
	var count:=int(source.get("index_count",0))
	var stride:=RenderingServer.mesh_surface_get_format_index_stride(source.format,source.vertex_count)
	if stride not in [2,4] or count%3!=0 or count<=removed.size()*3: return null
	var bytes: PackedByteArray=source.index_data
	var retained:=PackedByteArray()
	var cursor:=0
	for face in removed:
		if face<cursor or face>=count/3: return null
		retained.append_array(bytes.slice(cursor*3*stride,face*3*stride))
		cursor=face+1
	retained.append_array(bytes.slice(cursor*3*stride))
	var surface:=source.duplicate()
	surface.index_data=retained
	surface.index_count=count-removed.size()*3
	var result:=ArrayMesh.new()
	result.set("_surfaces",[surface])
	return result


static func checks() -> bool:
	if run("","","")!=1: return false
	var fixture:=preload("res://scripts/tests/test_tokyo_full_grid_root.gd")
	var first: ArrayMesh=fixture.triangle(0,true)
	var arrays:=first.surface_get_arrays(0)
	var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
	for id in vertices.size(): vertices[id].y=0.5
	arrays[Mesh.ARRAY_VERTEX]=vertices
	first=ArrayMesh.new()
	first.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var pieces: Array[ArrayMesh]=[first,first,fixture.triangle(4,true)]
	var joined:=Root.Join.join(pieces)
	arrays=joined.surface_get_arrays(0)
	var ids: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
	var key:=record(arrays,ids,0).hex_encode()
	var wanted: Dictionary={key:2}
	if select(joined,wanted)!=PackedInt32Array([0,1]): return false
	wanted[key]=1
	if not select(joined,wanted).is_empty(): return false
	wanted={record(arrays,ids,2).hex_encode():1}
	if not select(joined,wanted).is_empty(): return false
	if filtered(joined,PackedInt32Array([1,0]))!=null or filtered(joined,PackedInt32Array([3]))!=null: return false
	var revised:=filtered(joined,PackedInt32Array([0,1]))
	if revised==null: return false
	var before: Dictionary=joined.get("_surfaces")[0]
	var after: Dictionary=revised.get("_surfaces")[0]
	return before.vertex_data==after.vertex_data and before.attribute_data==after.attribute_data \
		and revised.surface_get_arrays(0)[Mesh.ARRAY_INDEX]==PackedInt32Array([8,6,7])


static func run(input: String, digest: String, output: String) -> int:
	if not Root.binding_valid({"path":input,"sha256":digest}) or not output.is_absolute_path() or DirAccess.dir_exists_absolute(output): return 1
	var plan: Variant=JSON.parse_string(FileAccess.get_file_as_string(input))
	if not plan is Dictionary or plan.get("schema")!=1 or plan.get("tiles",[]).size()!=16: return 1
	for key: String in ["root","removal_manifest","selection_audit"]:
		if not Root.binding_valid(plan.get(key)): return 1
	var audit: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(plan.selection_audit.path))
	if not audit.get("selection_and_seams_pass",false): return 1
	var root: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(plan.root.path))
	if root.get("parent_id")!=plan.get("parent") or root.get("configuration")!="fixed" or root.get("fail",1)!=0 or not Root.binding_valid(root.get("component")): return 1
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(plan.removal_manifest.path))
	if manifest.get("selection_audit")!=plan.selection_audit or manifest.get("tile_count")!=256: return 1
	var tile_names: Dictionary={}
	for source: Dictionary in root.sources: tile_names[source.tile]=true
	var wanted: Dictionary={}
	var selected_tiles: Dictionary={}
	for tile: Dictionary in plan.tiles:
		if not tile_names.has(tile.tile) or selected_tiles.has(tile.tile) or not manifest.rows.has(tile): return 1
		selected_tiles[tile.tile]=true
		for key: String in ["corners","ids","fixed_attributes"]:
			if not Root.binding_valid(tile.get(key)): return 1
		var raw:=FileAccess.get_file_as_bytes(tile.corners.path)
		if raw.size()!=int(tile.faces)*120: return 1
		for face in int(tile.faces):
			var key:=raw.slice(face*120,(face+1)*120).hex_encode()
			wanted[key]=int(wanted.get(key,0))+1
	if selected_tiles.size()!=16: return 1
	var original: Resource=ResourceLoader.load(root.component.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if original==null or not original.valid() or original.meshes.size()!=1: return 1
	var mesh: ArrayMesh=original.meshes[0]
	var removed:=select(mesh,wanted) if not wanted.is_empty() else PackedInt32Array()
	if removed.size()!=plan.faces: return 1
	var revised:=filtered(mesh,removed) if not removed.is_empty() else mesh
	if revised==null: return 1
	if DirAccess.make_dir_recursive_absolute(output)!=OK: return 1
	var meshes: Array[ArrayMesh]=[revised]
	var saved:=Components._save(meshes,str(root.component.sha256)+":"+digest,output.path_join("component.res"))
	if saved.is_empty(): return 1
	var loaded: Resource=ResourceLoader.load(saved.path,"",ResourceLoader.CACHE_MODE_IGNORE)
	if loaded==null or not loaded.valid(): return 1
	var before: Dictionary=mesh.get("_surfaces")[0]
	var after: Dictionary=loaded.meshes[0].get("_surfaces")[0]
	for key: String in before:
		if key not in ["index_count","index_data"] and before[key]!=after.get(key): return 1
	if int(after.index_count)!=int(before.index_count)-removed.size()*3: return 1
	if after.index_data!=revised.get("_surfaces")[0].index_data: return 1
	var file:=FileAccess.open(output.path_join("removed_root_ids.u32"),FileAccess.WRITE)
	if file==null: return 1
	file.store_buffer(removed.to_byte_array()); file.close()
	var ids_path:=output.path_join("removed_root_ids.u32")
	if FileAccess.get_file_as_bytes(ids_path)!=removed.to_byte_array(): return 1
	file=FileAccess.open(output.path_join("manifest.json"),FileAccess.WRITE)
	if file==null: return 1
	file.store_string(JSON.stringify({"parent":plan.parent,"input_sha256":digest,"source":root.component,
		"component":saved,"removed":removed.size(),"original_faces":int(before.index_count)/3,
		"remaining_faces":int(after.index_count)/3,"removed_ids":{"path":ids_path,"sha256":FileAccess.get_sha256(ids_path)},
		"native_full_attribute_match":true,"retained_packed_channels_equal":true,"saved_indices_equal":true,
		"visual_verified":false,"installed":false},"",true,true)); file.close()
	print("[Semantic rail root] parent=",plan.parent," removed=",removed.size()," native saved verified")
	return 0
