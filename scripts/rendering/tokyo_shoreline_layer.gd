extends RefCounted
## 原生岸线辅助层：一次加载，复用地图tick；预算与绘制成本显式报告。
const MAX_BYTES := 6*1024*1024
const MAX_RECTS := 17
var _nodes: Array[MeshInstance3D] = []
var _meshes: Array[ArrayMesh] = []
var _materials: Array[ShaderMaterial] = []
var _faces := PackedInt32Array()
var _stream: WeakRef
var _signature: Array = []
var stats: Dictionary = {}
var warm_mask := 0
var _warm_level := -1
var _morph := false
var _bounds := AABB()
var _material_warmup: WeakRef


static func levels(scale: float) -> Vector3:
	if not is_finite(scale) or scale<=0:
		return Vector3(-1,-1,0)
	if scale<=.85:
		return Vector3(0,0,0)
	if scale<1.15:
		return Vector3(0,1,smoothstep(.85,1.15,scale))
	if scale<=1.7:
		return Vector3(1,1,0)
	if scale<2.3:
		return Vector3(1,2,smoothstep(1.7,2.3,scale))
	return Vector3(2,2,0)


static func shader_code(original: String) -> String:
	if original.count("void vertex() {")!=1 or original.count("void fragment() {")!=1 or original.contains("shoreline_local") or not original.contains("uniform float lod_mix = 1.0;"):
		return ""
	var declarations := "uniform vec4 shoreline_rects[17];\nuniform int shoreline_count=0;\nvarying vec2 shoreline_local;\n"
	var guard := "\nfor(int i=0;i<17;i++){if(i>=shoreline_count){break;} vec4 r=shoreline_rects[i]; if(shoreline_local.x>=r.x && shoreline_local.x<=r.z && shoreline_local.y>=r.y && shoreline_local.y<=r.w){discard;}}\n"
	return original.replace("void vertex() {",declarations+"void vertex() {\nshoreline_local=VERTEX.xz;").replace("void fragment() {","void fragment() {"+guard)


static func morph_factor(scale: float) -> float:
	var choice := levels(scale)
	if choice.x<0:
		return -1.0
	var widths := [2.0,1.0,.35]
	return clampf((2.0-lerpf(widths[int(choice.x)],widths[int(choice.y)],choice.z))/1.65,0.0,1.0)


static func morph_shader_code(original: String) -> String:
	var code := shader_code(original)
	if code.is_empty() or original.contains("shoreline_morph_t"):
		return ""
	return code.replace("void vertex() {","uniform float shoreline_morph_t = 0.0;\nvoid vertex() {\nVERTEX.xz += UV * shoreline_morph_t;")


static func manifest_bytes(data: Dictionary) -> int:
	var schema: Variant = data.get("schema",0)
	var rows: Variant = data.get("meshes")
	if not typeof(schema) in [TYPE_INT,TYPE_FLOAT] or not (schema==1 or schema==2) or not rows is Array or rows.size()!=(3 if schema==1 else 4):
		return -1
	if not data.get("source_sha") is String or data.source_sha.length()!=64:
		return -1
	var total := 0
	for i in rows.size():
		var row: Variant = rows[i]
		if not row is Dictionary:
			return -1
		var faces: Variant = row.get("faces")
		if not typeof(faces) in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(faces)) or faces<=0 or faces!=int(faces) or faces>12000:
			return -1
		var file := "shore_%d.res"%i if schema==1 else ("morph.res" if i==0 else "fallback_%d.res"%(i-1))
		if row.get("file","")!=file:
			return -1
		if schema==1 and row.get("width",0)!=[2.0,1.0,.35][i]:
			return -1
		total+=int(faces)*3*64*3
	if schema==2:
		var widths: Variant = data.get("widths")
		if not widths is Array or widths.size()!=3 or data.get("reserved_bytes",0)!=total or not data.get("plan_sha") is String or data.plan_sha.length()!=64:
			return -1
		for i in 3:
			if widths[i]!=[2.0,1.0,.35][i]:
				return -1
	return total if total<=MAX_BYTES else -1


static func valid_morph_mesh(mesh: ArrayMesh) -> bool:
	var arrays := mesh.surface_get_arrays(0)
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: Variant = arrays[Mesh.ARRAY_TEX_UV]
	if not uv is PackedVector2Array or uv.size()!=points.size() or not mesh.custom_aabb.has_volume():
		return false
	for i in points.size():
		if not points[i].is_finite() or not uv[i].is_finite() or absf(points[i].y-.03)>.000001:
			return false
		if not mesh.custom_aabb.has_point(points[i]) or not mesh.custom_aabb.has_point(points[i]+Vector3(uv[i].x,0,uv[i].y)):
			return false
	return true


func bind(map: Node, directory: String) -> bool:
	if _stream!=null or not FileAccess.file_exists(directory.path_join("manifest.json")):
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
	if not data is Dictionary:
		return false
	var bytes := manifest_bytes(data)
	if bytes<0:
		print("[Tokyo shore reject] manifest contract ",directory)
		return false
	for row: Dictionary in data.meshes:
		if not FileAccess.file_exists(directory.path_join(row.file)) or FileAccess.get_sha256(directory.path_join(row.file))!=row.get("sha256",""):
			print("[Tokyo shore reject] resource identity ",row.file)
			return false
	if bytes>MAX_BYTES or not map._stream.reserve_auxiliary(get_instance_id(),bytes):
		return false
	_stream = weakref(map._stream)
	_morph=data.schema==2
	for row: Dictionary in data.meshes:
		var resource: Resource = ResourceLoader.load(directory.path_join(row.file),"",ResourceLoader.CACHE_MODE_IGNORE)
		if not resource is ArrayMesh or resource.get_surface_count()!=1 or resource.surface_get_array_len(0)!=int(row.faces)*3:
			print("[Tokyo shore reject] native surface ",row.file)
			close()
			return false
		if _morph and not valid_morph_mesh(resource):
			print("[Tokyo shore reject] morph attributes ",row.file," bounds=",resource.custom_aabb)
			close()
			return false
		_meshes.append(resource)
		_faces.append(int(row.faces))
		var bound: AABB = resource.custom_aabb if _morph else resource.get_aabb()
		_bounds = bound if _meshes.size()==1 else _bounds.merge(bound)
	var code := morph_shader_code(map._materials[4].shader.code) if _morph else shader_code(map._materials[4].shader.code)
	if code.is_empty():
		close()
		return false
	var shader := Shader.new()
	shader.code = code
	for i in (3 if _morph else 2):
		var material: ShaderMaterial = map._materials[4].duplicate()
		material.shader = shader
		if _morph:
			material.set_shader_parameter("shoreline_morph_t",0.0)
		var node: MeshInstance3D = map._add_mesh(null,material,false)
		node.hide()
		_nodes.append(node)
		_materials.append(material)
	var ids := PackedInt64Array()
	var resident := 0
	for i in _meshes.size():
		ids.append(_meshes[i].get_instance_id())
		resident+=_faces[i]
	stats = {"ready":true,"schema":data.schema,"reserved_bytes":bytes,"faces":0,"resident_faces":resident,"visible_nodes":0,"pooled_nodes":_nodes.size(),"mesh_ids":ids,"source_sha":data.source_sha,"warm_mask":0,"morph_factor":0.0,"shared_warm_mask":0}
	return true


func start_material_warm(map: Node) -> bool:
	if _materials.is_empty() or _material_warmup != null:
		return false
	var warm := preload("res://scripts/rendering/tokyo_shoreline_warmup.gd").new()
	var configured := warm.configure(map._stream, _materials[0], map._viewport.msaa_3d)
	stats["material_warmup"] = warm.result
	if not configured:
		warm.free()
		return false
	_material_warmup = weakref(warm)
	map.add_child(warm)
	return true


func material_warm_ready() -> bool:
	var state: Dictionary = stats.get("material_warmup", {})
	if state.get("reserved_bytes", -1) != 0:
		return false
	return (state.get("state", "") == "ready" and state.get("rendered", false) and state.get("submitted_frames", 0) >= 2) or (DisplayServer.get_name() == "headless" and state.get("state", "") == "headless_skipped")


func update(scale: float, tiles: Array[Rect2], active: bool) -> bool:
	if _meshes.is_empty() or _warm_level>=0:
		return false
	var choice := levels(scale)
	var rects := PackedVector4Array()
	if tiles.size()>MAX_RECTS:
		active = false
	else:
		for tile: Rect2 in tiles:
			if not preload("res://scripts/experiments/tokyo_tile_ground_candidate.gd").valid_bounds(tile):
				active = false
				break
			rects.append(Vector4(tile.position.x,tile.position.y,tile.end.x,tile.end.y))
	active = active and choice.x>=0 and not preload("res://scripts/experiments/tokyo_tile_coverage.gd").flat_covered(_bounds,tiles)
	var signature := [choice,rects,active]
	if signature==_signature:
		return false
	# Packed数组引用共享，shader补齐17槽不能改写用于静止比较的原始签名。
	_signature = [choice,rects.duplicate(),active]
	var count := rects.size()
	rects.resize(MAX_RECTS)
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter("shoreline_rects",rects)
		material.set_shader_parameter("shoreline_count",count)
	stats["faces"] = 0
	stats["visible_nodes"] = 0
	stats["levels"] = choice
	stats["covered_rects"] = count
	for i in 2:
		var index := int(choice.x if i==0 else choice.y)+int(_morph)
		var visible := active and (i==0 or choice.x!=choice.y)
		_nodes[i].visible = visible
		if not visible:
			continue
		_nodes[i].mesh = _meshes[index]
		_materials[i].set_shader_parameter("outgoing",i==0 and choice.x!=choice.y)
		_materials[i].set_shader_parameter("lod_mix",choice.z if choice.x!=choice.y else 1.0)
		stats["faces"] += _faces[index]
		stats["visible_nodes"] += 1
	if _morph:
		_nodes[2].visible=active
		_nodes[2].mesh=_meshes[0]
		stats["morph_factor"]=morph_factor(scale)
		_materials[2].set_shader_parameter("shoreline_morph_t",stats.morph_factor)
		_materials[2].set_shader_parameter("outgoing",false)
		_materials[2].set_shader_parameter("lod_mix",1.0)
		if active:
			stats["faces"]+=_faces[0]
			stats["visible_nodes"]+=1
	return true


func begin_warm() -> void:
	if _meshes.is_empty():
		return
	warm_mask = 0
	stats["shared_warm_mask"]=0
	_warm_level = 0
	_show_warm()


func warm_draw() -> void:
	if _warm_level<0:
		return
	warm_mask |= 1<<_warm_level
	if _morph:
		stats["shared_warm_mask"]=warm_mask
	stats["warm_mask"] = warm_mask
	_warm_level += 1
	if _warm_level==3:
		_warm_level = -1
		_signature.clear()
		hide()
	else:
		_show_warm()


func _show_warm() -> void:
	_nodes[0].mesh = _meshes[_warm_level+int(_morph)]
	_nodes[0].show()
	_nodes[1].hide()
	_materials[0].set_shader_parameter("shoreline_count",0)
	_materials[0].set_shader_parameter("outgoing",false)
	_materials[0].set_shader_parameter("lod_mix",1.0)
	if _morph:
		_nodes[2].mesh=_meshes[0]
		_nodes[2].show()
		_materials[2].set_shader_parameter("shoreline_count",0)
		_materials[2].set_shader_parameter("outgoing",false)
		_materials[2].set_shader_parameter("lod_mix",1.0)
		_materials[2].set_shader_parameter("shoreline_morph_t",morph_factor([.5,1.5,3.0][_warm_level]))


func hide() -> void:
	for node: Variant in _nodes:
		if typeof(node)==TYPE_OBJECT and is_instance_valid(node):
			node.hide()
	_signature.clear()
	stats["faces"] = 0
	stats["visible_nodes"] = 0


func close() -> void:
	var warm: Variant = _material_warmup.get_ref() if _material_warmup != null else null
	if typeof(warm) == TYPE_OBJECT and is_instance_valid(warm):
		warm.close()
	_material_warmup = null
	for node: Variant in _nodes:
		if typeof(node)==TYPE_OBJECT and is_instance_valid(node):
			node.free()
	_nodes.clear()
	_meshes.clear()
	_materials.clear()
	_faces.clear()
	var stream: Variant = _stream.get_ref() if _stream!=null else null
	if typeof(stream)==TYPE_OBJECT and is_instance_valid(stream):
		stream.release_auxiliary(get_instance_id())
	_stream = null
	_signature.clear()
	stats.clear()
	_morph=false
	_bounds=AABB()
	_warm_level=-1
	warm_mask=0
