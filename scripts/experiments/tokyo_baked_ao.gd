extends "res://scripts/experiments/tokyo_static_shadow.gd"
## 局部显式AO试验：复用材质槽与回滚，不新增绘制或更改几何。
var _height_texture: ImageTexture
var _height_palette: ImageTexture
var _budget_stream: WeakRef
var _derived_materials: Array[WeakRef] = []
var _strength := 0.45


func bind_preloaded(overlay: Node, directory: String) -> bool:
	if _owner != null or _budget_stream != null:
		return false
	if not FileAccess.file_exists(directory.path_join("manifest.json")):
		return false
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
	if not manifest is Dictionary or preload("res://scripts/experiments/tokyo_height_bits.gd").storage_width(manifest)==0:
		return false
	var row := choose_row(manifest.get("rows", []), 5.12)
	if row.is_empty() or int(row.get("size", 0)) != 2048 or row_bytes(manifest,row)<=0:
		return false
	if manifest.get("ao_encoding", "")=="bc4_unorm_mips" and not OS.has_feature("rgtc"):
		return false
	if not overlay._stream.reserve_auxiliary(get_instance_id(), int(row.conservative_bytes)):
		return false
	_budget_stream = weakref(overlay._stream)
	if not bind_ao(overlay, directory, 5.12):
		close()
		return false
	stats["preloaded"] = true
	stats["mip_resident"] = true
	stats["texture_id"] = _texture.get_instance_id()
	stats["height_id"] = _height_texture.get_instance_id()
	return true


static func bc4_mip_bytes(size: int) -> int:
	if size not in [512,1024,2048]:
		return 0
	var result := 0
	while size>0:
		result+=maxi(1,(size+3)/4)*maxi(1,(size+3)/4)*8
		size=size/2
	return result


static func row_bytes(manifest: Dictionary, row: Dictionary) -> int:
	var size := int(row.get("size",0))
	if size not in [512,1024,2048]:
		return 0
	var height_encoding: String = manifest.get("height_encoding", "")
	if height_encoding not in ["","global_palette_r8","global_palette_r5_lsb"]:
		return 0
	var indexed := not height_encoding.is_empty()
	var width := preload("res://scripts/experiments/tokyo_height_bits.gd").storage_width(manifest)
	if indexed and width==0:
		return 0
	var encoding: String = manifest.get("ao_encoding", "")
	if encoding not in ["","bc4_unorm_mips"] or (encoding!="" and not indexed):
		return 0
	var result := size*size*4+width*2048*3+1536 if indexed else size*size*12
	if encoding=="bc4_unorm_mips":
		var payload := bc4_mip_bytes(size)
		if row.get("ao_data_bytes",-1)!=payload:
			return 0
		result=payload*3+width*2048*3+1536
	return result if row.get("conservative_bytes",-1)==result else 0


static func make_shader(original: String, indexed: bool = false, packed_height: bool = false) -> String:
	# 尚无多候选共同纹理预算/回滚栈；拒绝静态阴影等未知叠加，不能漏算另一层。
	if original != preload("res://resources/shaders/tokyo_volume_surface.gdshader").code or (packed_height and not indexed):
		return ""
	var declarations := """
uniform sampler2D baked_ao : filter_linear_mipmap, repeat_disable;
uniform sampler2D baked_height : filter_nearest, repeat_disable;
uniform vec4 ao_bounds;
uniform float ao_strength = 0.45;
varying vec3 ao_local;
varying float ao_up;
"""
	var emission := """
	float occlusion = 0.0;
	vec2 local_uv = (ao_local.xz - ao_bounds.xy) / ao_bounds.zw;
	vec2 edges = min(local_uv, vec2(1.0)-local_uv) * ao_bounds.zw;
	float coverage = smoothstep(0.0, 12.0, min(edges.x, edges.y));
	if (coverage > 0.0 && ao_up > 0.99) {
		vec2 raw_height = floor(texture(baked_height, local_uv).rg * 255.0 + 0.5);
		float height_code = raw_height.x * 256.0 + raw_height.y;
		float receiver = height_code / 256.0 - 1.0;
		float same_surface = 1.0 - smoothstep(0.04, 0.15, abs(ao_local.y - receiver));
		if (height_code < 65534.5) {
			occlusion = texture(baked_ao, local_uv).r * same_surface * coverage;
		}
	}
	EMISSION = base * 0.50 * (1.0 - ao_strength * occlusion);
"""
	if indexed:
		declarations += "uniform sampler2D baked_height_palette : filter_nearest, repeat_disable;\n"
		emission = emission.replace("texture(baked_height, local_uv).rg", "texture(baked_height_palette, vec2((floor(texture(baked_height, local_uv).r * 255.0 + 0.5) + 0.5) / 256.0, 0.5)).rg")
	if packed_height:
		declarations += preload("res://scripts/experiments/tokyo_height_bits.gd").SHADER_CODE
		emission = emission.replace("floor(texture(baked_height, local_uv).r * 255.0 + 0.5)","agl_height_index(local_uv)")
	return original.replace("void vertex() {", declarations + "\nvoid vertex() {\n ao_local = VERTEX; ao_up = NORMAL.y;") \
		.replace("EMISSION = base * 0.50;", emission)


func bind_ao(overlay: Node, directory: String, scale: float) -> bool:
	if _owner != null or not overlay.has_method("bind_legacy"):
		return false
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
	if not raw is Dictionary or raw.get("schema") != 1 or raw.get("method") != "local_heightfield_horizon" \
			or raw.get("catalog_sha256") != overlay._canonical_sha or raw.get("collision_sha256") != overlay._canonical.collision_sha256:
		return false
	var row := choose_row(raw.get("rows", []), scale)
	if row.is_empty():
		return false
	var size := int(row.get("size", 0))
	var packed_height: bool = raw.get("height_encoding", "") == "global_palette_r5_lsb"
	var indexed: bool = raw.get("height_encoding", "") == "global_palette_r8" or packed_height
	if raw.get("height_encoding", "") not in ["", "global_palette_r8", "global_palette_r5_lsb"]:
		return false
	var height_size := 2048 if indexed else size
	var height_width := preload("res://scripts/experiments/tokyo_height_bits.gd").storage_width(raw) if indexed else height_size
	var expected_bytes := row_bytes(raw,row)
	if indexed and int(raw.get("height_size", 0)) != height_size:
		return false
	if expected_bytes<=0:
		return false
	var compressed: bool = raw.get("ao_encoding", "")=="bc4_unorm_mips"
	if compressed and not OS.has_feature("rgtc"):
		return false
	var bounds: Array = raw.get("bounds", [])
	if bounds.size() != 4 or float(bounds[2]) <= float(bounds[0]) or float(bounds[3]) <= float(bounds[1]) \
			or float(row.max_scale) > float(size) / maxf(float(bounds[2])-float(bounds[0]), float(bounds[3])-float(bounds[1])):
		return false
	var state: Dictionary = overlay.debug_state()
	var resident := int(state.stream.bytes) + int(state.stream.reserved_bytes)
	# 旧显式绑定也不能漏算别的纹理租约；预热已经预留的自身额只计一次。
	var own_reservation := 0
	if _budget_stream != null and _budget_stream.get_ref() == overlay._stream:
		own_reservation = int(overlay._stream._auxiliary.get(get_instance_id(), 0))
	resident += int(state.stream.get("auxiliary_bytes", 0)) - own_reservation
	if resident + int(row.conservative_bytes) > 96 * 1024 * 1024:
		return false
	for field: String in ["ao", "height"]:
		var name_value := String(row.get(field, ""))
		if name_value != name_value.get_file() or FileAccess.get_sha256(directory.path_join(name_value)) != row.get(field + "_sha256", ""):
			return false
	var shader := Shader.new()
	shader.code = make_shader(overlay._materials[0].shader.code, indexed, packed_height)
	if shader.code.is_empty():
		return false
	var picture: Image
	if compressed:
		var payload := FileAccess.get_file_as_bytes(directory.path_join(row.ao))
		if payload.size()!=bc4_mip_bytes(size):
			return false
		picture=Image.create_from_data(size,size,true,Image.FORMAT_RGTC_R,payload)
	else:
		picture=Image.load_from_file(directory.path_join(row.ao))
	if picture == null or picture.get_size() != Vector2i(size, size):
		return false
	if not compressed:
		picture.convert(Image.FORMAT_R8)
		if picture.generate_mipmaps() != OK:
			return false
	var ao_bytes := picture.get_data().size()
	var ao_texture := ImageTexture.create_from_image(picture)
	picture = null
	if compressed:
		# Loading内回读一次，确认压缩格式/mip没有被后端静默展开；保守三份额覆盖回读。
		var uploaded := ao_texture.get_image()
		if uploaded==null or uploaded.get_format()!=Image.FORMAT_RGTC_R or not uploaded.has_mipmaps() or uploaded.get_data().size()!=ao_bytes:
			return false
	picture = Image.load_from_file(directory.path_join(row.height))
	if picture == null or picture.get_size() != Vector2i(height_width, height_size):
		return false
	picture.convert(Image.FORMAT_R8 if indexed else Image.FORMAT_RG8)
	var height_bytes := picture.get_data().size()
	var height_texture := ImageTexture.create_from_image(picture)
	if packed_height:
		var uploaded := height_texture.get_image()
		if uploaded==null or uploaded.get_format()!=Image.FORMAT_R8 or uploaded.has_mipmaps() or uploaded.get_size()!=picture.get_size() or uploaded.get_data()!=picture.get_data():
			return false
	picture = null
	var palette_texture: ImageTexture
	if indexed:
		var palette_name := String(raw.get("palette", ""))
		if palette_name.is_empty() or palette_name != palette_name.get_file() or FileAccess.get_sha256(directory.path_join(palette_name)) != raw.get("palette_sha256", ""):
			return false
		picture = Image.load_from_file(directory.path_join(palette_name))
		if picture == null or picture.get_size() != Vector2i(256, 1):
			return false
		picture.convert(Image.FORMAT_RG8)
		height_bytes += picture.get_data().size()
		palette_texture = ImageTexture.create_from_image(picture)
		picture = null
	for original: ShaderMaterial in overlay._materials:
		var replacement: ShaderMaterial = original.duplicate()
		replacement.shader = shader
		replacement.set_shader_parameter("baked_ao", ao_texture)
		replacement.set_shader_parameter("baked_height", height_texture)
		if indexed:
			replacement.set_shader_parameter("baked_height_palette", palette_texture)
		replacement.set_shader_parameter("ao_bounds", Vector4(bounds[0], bounds[1], bounds[2]-bounds[0], bounds[3]-bounds[1]))
		_original.append(original)
		_replacement.append(replacement)
	for batch: Dictionary in overlay._batches.values():
		for node: MeshInstance3D in batch.nodes:
			var index := _original.find(node.material_override)
			if index >= 0:
				node.material_override = _replacement[index]
	overlay._materials = _replacement.duplicate()
	_texture = ao_texture
	_height_texture = height_texture
	_height_palette = palette_texture
	_owner = weakref(overlay)
	overlay.tree_exiting.connect(close, CONNECT_ONE_SHOT)
	stats = {"size": size, "max_scale": row.max_scale, "bounds": bounds, "horizontal_only": true,
		"ao_encoding":raw.get("ao_encoding","r8"),"ao_gpu_format":ao_texture.get_format(),"rgtc_supported":OS.has_feature("rgtc"),
		"height_size": height_size, "height_storage_width":height_width, "height_encoding": raw.get("height_encoding", "rg16"),
		"texture_bytes": ao_bytes + height_bytes, "conservative_bytes": int(row.conservative_bytes),
		"conservative_resident_bytes": resident + int(row.conservative_bytes), "dynamic_pass_removed": false}
	return true


func track_material(material: ShaderMaterial) -> bool:
	# 派生显示层共享纹理和强度，不延长其材质或纹理生命周期。
	if material == null or _texture == null or material.get_shader_parameter("baked_ao") != _texture:
		return false
	for reference: WeakRef in _derived_materials:
		if reference.get_ref() == material:
			return true
	_derived_materials.append(weakref(material))
	material.set_shader_parameter("ao_strength", _strength)
	return true


func strength(value: float) -> void:
	if not is_finite(value):
		return
	_strength = clampf(value, 0.0, 1.0)
	for material: ShaderMaterial in _replacement:
		material.set_shader_parameter("ao_strength", _strength)
	for index in range(_derived_materials.size()-1, -1, -1):
		var material: Variant = _derived_materials[index].get_ref()
		if typeof(material) == TYPE_OBJECT and is_instance_valid(material) and material is ShaderMaterial:
			material.set_shader_parameter("ao_strength", _strength)
		else:
			_derived_materials.remove_at(index)


func close() -> void:
	_derived_materials.clear()
	_strength = 0.45
	var overlay: Variant = _owner.get_ref() if _owner != null else null
	if typeof(overlay) == TYPE_OBJECT and is_instance_valid(overlay) and overlay.tree_exiting.is_connected(close):
		overlay.tree_exiting.disconnect(close)
	super.close()
	_height_texture = null
	_height_palette = null
	var stream: Variant = _budget_stream.get_ref() if _budget_stream != null else null
	if typeof(stream) == TYPE_OBJECT and is_instance_valid(stream):
		stream.release_auxiliary(get_instance_id())
	_budget_stream = null
