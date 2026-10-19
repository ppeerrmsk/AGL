extends RefCounted
const Root := preload("res://scripts/tests/build_tokyo_full_grid_root.gd")


static func triangle(offset: float, indexed: bool) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(offset,0,0),Vector3(offset+1,0,0),Vector3(offset,0,1)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
	arrays[Mesh.ARRAY_COLOR]=PackedColorArray([Color.RED,Color.GREEN,Color.BLUE])
	if indexed:
		arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([2,0,1])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh


static func checks() -> bool:
	if Root.run("","","","")!=1 or not Root.selection("lod5_guarded").is_empty() or not Root.selection("lod4_guarded").is_empty():
		return false
	if Root.selection("fixed")!={"slot":-1,"guarded":false,"kinds":1} or Root.selection("lod4_mid").slot!=6:
		return false
	for n in 4:
		if Root.selection("lod%d_guarded" % n)!={"slot":n,"guarded":true,"kinds":2}:
			return false
	if Root.binding_valid({}) or Root.binding_valid({"path":"relative","sha256":"c".repeat(64)}):
		return false
	var sources: Array[ArrayMesh] = [triangle(0,false),ArrayMesh.new(),triangle(4,true)]
	var result := Root.Join.join(sources)
	if not Root.joined_exact(sources,result) or Root.joined_exact([sources[2],sources[1],sources[0]],result) \
			or Root.joined_exact(sources,sources[0]) or Root.joined_exact([],result) or not Root.joined_exact([],ArrayMesh.new()):
		return false
	var altered: ArrayMesh = result.duplicate(true)
	var surfaces: Array = altered.get("_surfaces").duplicate(true)
	var raw: PackedByteArray = surfaces[0].vertex_data
	raw.encode_float(0,100.0)
	surfaces[0].vertex_data=raw
	altered.set("_surfaces",surfaces)
	if Root.joined_exact(sources,altered):
		return false
	altered=result.duplicate(true)
	surfaces=altered.get("_surfaces").duplicate(true)
	raw=surfaces[0].attribute_data
	raw[0]=raw[0]^255
	surfaces[0].attribute_data=raw
	altered.set("_surfaces",surfaces)
	return not Root.joined_exact(sources,altered)
