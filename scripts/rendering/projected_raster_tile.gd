extends MeshInstance2D
## 与原瓦片共享只读region元数据；真正提交静态投影网格，没有第二张Sprite重叠。
const Geo := preload("res://scripts/experiments/tokyo_raster_projection.gd")
var region_enabled := false
var region_rect := Rect2()
var region_filter_clip_enabled := false
var centered := false
var offset := Vector2.ZERO
var world_vertices := PackedVector2Array()
var source_uv := PackedVector2Array()
var projected_rect := Rect2()
var maximum_step := Vector2.ZERO
var geometry_bytes := 0


func configure(meta: Dictionary) -> void:
	var size := Vector2(texture.get_size())
	var region := region_rect if region_enabled else Rect2(Vector2.ZERO,size)
	var raw := Rect2(position,region.size*scale)
	var uv := Rect2(region.position/size,region.size/size)
	var world_mesh := Geo.mesh(raw,uv,meta)
	var arrays := world_mesh.surface_get_arrays(0)
	world_vertices = arrays[Mesh.ARRAY_VERTEX]
	source_uv = arrays[Mesh.ARRAY_TEX_UV]
	projected_rect = Rect2(world_vertices[0],world_vertices[world_vertices.size()-1]-world_vertices[0])
	maximum_step.x = absf(scale.x)
	for row in world_vertices.size()/2-1:
		var step := absf((world_vertices[row*2+2].y-world_vertices[row*2].y)/((source_uv[row*2+2].y-source_uv[row*2].y)*size.y))
		maximum_step.y = maxf(maximum_step.y,step)
	var local := PackedVector2Array()
	for point in world_vertices:
		local.append((point-position)/scale)
	arrays[Mesh.ARRAY_VERTEX] = local
	mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var surface: Dictionary = mesh.get("_surfaces")[0]
	geometry_bytes = surface.vertex_data.size()+surface.attribute_data.size()+surface.index_data.size()+world_vertices.size()*8+source_uv.size()*8


func clipped_plane(bounds: Rect2) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	for row in world_vertices.size()/2-1:
		var a := row*2
		var strip := Rect2(world_vertices[a],world_vertices[a+3]-world_vertices[a])
		var clipped := strip.intersection(bounds)
		if not clipped.has_area():
			continue
		var t0 := (clipped.position-strip.position)/strip.size
		var t1 := (clipped.end-strip.position)/strip.size
		var start := source_uv[a]
		var span := source_uv[a+3]-start
		var u0 := start+t0*span
		var u1 := start+t1*span
		var n := vertices.size()
		vertices.append_array(PackedVector3Array([Vector3(clipped.position.x,0,clipped.position.y),Vector3(clipped.end.x,0,clipped.position.y),Vector3(clipped.position.x,0,clipped.end.y),Vector3(clipped.end.x,0,clipped.end.y)]))
		normals.append_array(PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP,Vector3.UP]))
		uv.append_array(PackedVector2Array([u0,Vector2(u1.x,u0.y),Vector2(u0.x,u1.y),u1]))
		indices.append_array(PackedInt32Array([n,n+2,n+1,n+1,n+2,n+3]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	if not vertices.is_empty():
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return result
