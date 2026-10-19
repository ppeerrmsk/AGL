extends RefCounted
## 静态来源快照；借用正式纹理，不创建常驻tick或第二套流送。
const BOUNDS := Rect2(-6300, -3700, 4000, 2000)
const MAX_PLANES := 17
var coverage_bounds := BOUNDS
const ColorTransfer := preload("res://scripts/experiments/tokyo_canvas_color.gd")
var _stream: WeakRef
var _nodes: Array[MeshInstance3D] = []
var _saved: Array[Dictionary] = []
var stats: Dictionary = {}
var _tiles: Array[Rect2] = []
var _replacements: Dictionary = {}
var _replace_fixed := false
var visible_retirement := false
var source_step := Vector2.ZERO
## 只缓存程序对象；不缓存借用Texture或材质。连续拥有者跨租约共享此表。
var shader_cache: Dictionary = {}


static func shader_code(source: String, shadow: bool = false) -> String:
	if not source.begins_with("shader_type canvas_item;") or source.count("\tCOLOR = vec4(clamp(color.rgb, 0.0, 1.0), color.a) * item_modulate;") != 1:
		return ""
	var header := "shader_type spatial;\nrender_mode unshaded, cull_disabled;\nuniform sampler2D map_texture : source_color, filter_linear;\nuniform vec4 source_modulate = vec4(1.0);"
	var finish := ColorTransfer.finish(shadow)
	if shadow:
		header = header.replace("unshaded, ", "ambient_light_disabled, specular_disabled, ")
	var result := source.replace("shader_type canvas_item;", header).replace("item_modulate = COLOR;", "item_modulate = source_modulate;")
	result = result.replace("TEXTURE_PIXEL_SIZE", "(1.0 / vec2(textureSize(map_texture, 0)))").replace("texture(TEXTURE,", "texture(map_texture,")
	result = result.replace("COLOR = vec4(clamp(color.rgb, 0.0, 1.0), color.a) * item_modulate;", finish)
	result = result.replace("void fragment() {",ColorTransfer.SHADER_CODE+"\nvoid fragment() {")
	if shadow:
		# 一盏固定太阳内一次输出75%常量+25%接影；避免GL分pass各编码后相加。
		result += "\nvoid light() { DIFFUSE_LIGHT += vec3(0.75 + ATTENUATION * 0.25); }"
	return result


static func ground_code(source: String) -> String:
	if not source.contains("void vertex() {") or not source.contains("void fragment() {") or source.contains("tile_ground_local"):
		return ""
	return source.replace("shader_type spatial;", "shader_type spatial;\nvarying vec3 tile_ground_local;\nuniform vec4 tile_ground_rects[17];\nuniform int tile_ground_count = 0;").replace("void vertex() {", "void vertex() {\n tile_ground_local = VERTEX;").replace("void fragment() {", "void fragment() {\n if (tile_ground_local.y < 0.0) { for(int i=0;i<tile_ground_count;i++) { vec4 r=tile_ground_rects[i]; if(tile_ground_local.x>=r.x && tile_ground_local.z>=r.y && tile_ground_local.x<=r.z && tile_ground_local.z<=r.w) { discard; } } }")


static func texture_resolved(world_step: Vector2, scale: float) -> bool:
	return world_step.is_finite() and world_step.x > 0 and world_step.y > 0 and is_finite(scale) and scale > 0 and maxf(world_step.x, world_step.y) * scale <= 1.25


static func plane(rect: Rect2, uv: Rect2) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(rect.position.x, 0, rect.position.y), Vector3(rect.end.x, 0, rect.position.y), Vector3(rect.end.x, 0, rect.end.y), Vector3(rect.position.x, 0, rect.end.y)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([uv.position, Vector2(uv.end.x, uv.position.y), uv.end, Vector2(uv.position.x, uv.end.y)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func valid_bounds(bounds: Rect2) -> bool:
	return bounds.position.is_finite() and bounds.size.is_finite() and bounds.end.is_finite() and bounds.size.x > 0.0 and bounds.size.y > 0.0


func bind(map: Node, source: RasterBasemapRenderer, shadow: bool = false, replace_fixed: bool = false) -> bool:
	if _stream != null or source._transitioning or not valid_bounds(coverage_bounds):
		return false
	var records: Array[Dictionary] = []
	for entry: Dictionary in source.presentation_tiles():
		if entry.lod != source._current_lod:
			continue
		var sprite: Variant = entry.sprite.get_ref()
		if typeof(sprite) != TYPE_OBJECT or not is_instance_valid(sprite) or not sprite.visible:
			continue
		var size := Vector2(sprite.texture.get_size())
		var region: Rect2 = sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, size)
		var full := Rect2(sprite.position, region.size * sprite.scale)
		var projected: bool = entry.get("projected",false)
		var step: Vector2 = sprite.maximum_step if projected else sprite.scale.abs()
		if projected:
			full = sprite.projected_rect
		var clipped := full.intersection(coverage_bounds)
		if not clipped.has_area():
			continue
		var output_scale: float = float(map._viewport.size.y) / map._camera.size
		if not texture_resolved(step, output_scale):
			stats = {"planes":0,"extra_materials":0,"extra_faces":0,"geometry_bytes":0,"reserved_bytes":0,"texture_ids":PackedInt64Array(),"texture_copies":0,"lod":source._current_lod,"shadow":shadow,"native_fallback":true,"source_pixel_output":maxf(step.x,step.y)*output_scale}
			return true
		var material: ShaderMaterial = sprite.material
		var code := shader_code(material.shader.code, shadow)
		if code.is_empty() or sprite.modulate.a < 0.999:
			return false
		var uv := Rect2((region.position + (clipped.position - full.position) / sprite.scale) / size, clipped.size / sprite.scale / size)
		records.append({"rect": clipped, "uv": uv, "material": material, "texture": sprite.texture, "modulate": sprite.modulate * sprite.self_modulate, "code": code,"step":step,"projected":projected,"source_node":sprite})
	if records.is_empty() or records.size() > MAX_PLANES or not map._stream.reserve_auxiliary(get_instance_id(), records.size() * 4096):
		return false
	_stream = weakref(map._stream)
	_replace_fixed = replace_fixed
	source_step = Vector2.ZERO
	for entry: Dictionary in records:
		_tiles.append(entry.rect)
		# 投影源取实际各行最大纹素步长；不能用均值掩盖某一行拉伸。
		source_step = source_step.max(entry.step)
	var bytes := 0
	var faces := 0
	var ids := PackedInt64Array()
	for entry: Dictionary in records:
		var mesh: ArrayMesh = entry.source_node.clipped_plane(entry.rect) if entry.projected else plane(entry.rect, entry.uv)
		var surface: Dictionary = mesh.get("_surfaces")[0]
		bytes += surface.vertex_data.size() + surface.attribute_data.size() + surface.index_data.size()
		faces += preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(mesh)
		var material: ShaderMaterial = entry.material.duplicate()
		material.shader = cached_shader(entry.code)
		material.set_shader_parameter("map_texture", entry.texture)
		material.set_shader_parameter("source_modulate", entry.modulate)
		assert(material.get_shader_parameter("map_texture") == entry.texture)
		var node: MeshInstance3D = map._add_mesh(mesh, material, false)
		_nodes.append(node)
		ids.append(entry.texture.get_instance_id())
	assert(bytes<=records.size()*4096,"borrowed projected geometry must fit the pre-reserved bytes")
	stats = {"planes": _nodes.size(), "extra_materials": _nodes.size(), "extra_faces": faces, "geometry_bytes": bytes, "reserved_bytes": records.size() * 4096, "texture_ids": ids, "texture_copies": 0, "lod": source._current_lod, "shadow": shadow,"projected_source":not source.source_projection.is_empty()}
	stats["coverage_bounds"] = coverage_bounds
	if not resume_fixed(map):
		close()
		return false
	return true


func resume_fixed(map: Node) -> bool:
	assert(_saved.is_empty(), "fixed layer must be restored before geometry mutation")
	var retired_faces := 0
	var retired_nodes := 0
	var view := Rect2()
	var roof := Vector2(INF,INF)
	if visible_retirement:
		var canvas: Transform2D = map._last_canvas
		var logical: Vector2 = Vector2(map._viewport.size)*map._screen.scale
		if canvas.is_finite() and absf(canvas.determinant())>0.000001 and logical.is_finite() and logical.x>0 and logical.y>0:
			var inverse := canvas.affine_inverse()
			# 两输出像素余量，防边缘采样/倾斜精度漏接。
			var margin: Vector2 = map._screen.scale*2.0
			view=Rect2(inverse*(-margin),Vector2.ZERO)
			for corner: Vector2 in [Vector2(logical.x+margin.x,-margin.y),logical+margin,Vector2(-margin.x,logical.y+margin.y)]:
				view=view.expand(inverse*corner)
			var ray: Vector3 = map._city.basis.inverse()*map._camera.basis.z
			if ray.is_finite() and absf(ray.y)>0.000001:
				roof=-Vector2(ray.x,ray.z)/ray.y
	for batch: Dictionary in map._batches.values():
		var node: MeshInstance3D = batch.nodes[2]
		var original: ShaderMaterial = node.material_override
		if not _replacements.has(original.get_instance_id()):
			var code := ground_code(original.shader.code)
			if code.is_empty():
				return false
			var material: ShaderMaterial = original.duplicate()
			material.shader = cached_shader(code)
			var rects := PackedVector4Array()
			rects.resize(MAX_PLANES)
			for i in _tiles.size():
				var rect := _tiles[i]
				rects[i] = Vector4(rect.position.x,rect.position.y,rect.end.x,rect.end.y)
			material.set_shader_parameter("tile_ground_rects",rects)
			material.set_shader_parameter("tile_ground_count",_tiles.size())
			_replacements[original.get_instance_id()] = material
		_saved.append({"node": weakref(node), "material": original, "visible":node.visible})
		node.material_override = _replacements[original.get_instance_id()]
		if _replace_fixed and node.visible and node.mesh != null and node.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF \
				and (preload("res://scripts/experiments/tokyo_tile_coverage.gd").flat_covered(node.mesh.get_aabb(),_tiles) \
				or (visible_retirement and preload("res://scripts/experiments/tokyo_tile_coverage.gd").visible_flat_covered(node.mesh.get_aabb(),_tiles,view,roof))):
			retired_faces += preload("res://scripts/experiments/tokyo_indexed_mesh.gd").triangles(node.mesh)
			retired_nodes += 1
			node.hide()
	stats.merge({"extra_materials":_nodes.size()+_replacements.size(),"fixed_replacement":_replace_fixed,"visible_retirement":visible_retirement,"retired_fixed_faces":retired_faces,"retired_fixed_nodes":retired_nodes,"retired_memory_bytes":0},true)
	return true


func cached_shader(code: String) -> Shader:
	if not shader_cache.has(code):
		var shader := Shader.new()
		shader.code = code
		shader_cache[code] = shader
	return shader_cache[code] as Shader


func suspend_fixed() -> void:
	for entry: Dictionary in _saved:
		var node: Variant = entry.node.get_ref()
		if typeof(node) == TYPE_OBJECT and is_instance_valid(node):
			node.material_override = entry.material
			if entry.has("visible"):
				node.visible = entry.visible
	_saved.clear()


func close() -> void:
	suspend_fixed()
	for node: Variant in _nodes:
		if typeof(node) == TYPE_OBJECT and is_instance_valid(node):
			node.free()
	_nodes.clear()
	var stream: Variant = _stream.get_ref() if _stream != null else null
	if typeof(stream) == TYPE_OBJECT and is_instance_valid(stream):
		stream.release_auxiliary(get_instance_id())
	_stream = null
	_tiles.clear()
	_replacements.clear()
	source_step = Vector2.ZERO
