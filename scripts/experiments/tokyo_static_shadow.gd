extends RefCounted
## 局部静态阴影候选；不新增tick/节点/面，范围外保留现有实时阴影。
var _owner: WeakRef
var _original: Array[ShaderMaterial] = []
var _replacement: Array[ShaderMaterial] = []
var _texture: ImageTexture
var stats: Dictionary = {}


static func choose_row(rows: Array, scale: float) -> Dictionary:
	if not is_finite(scale) or scale <= 0:
		return {}
	for row: Dictionary in rows:
		if scale <= float(row.max_scale):
			return row
	return {}


static func shader_code(original: String) -> String:
	if not original.contains("void vertex() {") or not original.contains("ALBEDO * ATTENUATION *"):
		return ""
	var declarations := """
uniform sampler2D static_mask : filter_linear_mipmap, repeat_disable;
uniform vec4 static_bounds;
uniform float static_strength = 0.5;
uniform bool static_receiver = false;
varying vec3 static_local;
varying float static_coverage;
varying float static_visibility;
"""
	var fragment := """
	vec2 local_uv = (static_local.xz - static_bounds.xy) / static_bounds.zw;
	vec2 edge_distance = min(local_uv, vec2(1.0) - local_uv) * static_bounds.zw;
	static_coverage = smoothstep(0.0, 12.0, min(edge_distance.x, edge_distance.y));
	static_visibility = 1.0;
	if (static_receiver && static_coverage > 0.0) {
		static_visibility -= static_strength * texture(static_mask, local_uv).r;
	}
"""
	return original.replace("void vertex() {", declarations + "\nvoid vertex() {\n static_local = VERTEX;") \
		.replace("void fragment() {", "void fragment() {\n" + fragment) \
		.replace("ALBEDO * ATTENUATION *", "ALBEDO * mix(vec3(ATTENUATION), vec3(static_visibility), static_coverage) *")


func bind(overlay: Node, directory: String, scale: float) -> bool:
	if _owner != null:
		return false
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("manifest.json")))
	if manifest.get("schema", 0) != 1 or manifest.get("source_sha256", "") != preload("res://scripts/tests/build_tokyo_far_clusters.gd").CITY_HASH:
		return false
	var row := choose_row(manifest.rows, scale)
	if row.is_empty():
		return false
	var path := directory.path_join(row.file)
	if FileAccess.get_sha256(path) != row.sha256:
		return false
	var state: Dictionary = overlay.debug_state()
	var resident := int(state.stream.bytes) + int(state.stream.reserved_bytes)
	# 同时计入CPU解码与GPU上传副本，不以压缩PNG体积冒充内存。
	if resident + ceili(int(row.base_bytes) * 4.0 / 3.0) * 2 > 96 * 1024 * 1024:
		return false
	var picture := Image.load_from_file(path)
	if picture == null or picture.get_size() != Vector2i(row["size"], row["size"]):
		return false
	picture.convert(Image.FORMAT_R8)
	if picture.generate_mipmaps() != OK:
		return false
	var bytes := picture.get_data().size()
	_texture = ImageTexture.create_from_image(picture)
	var shader := Shader.new()
	shader.code = shader_code(overlay._materials[0].shader.code)
	if shader.code.is_empty():
		_texture = null
		return false
	var bounds: Array = manifest.bounds
	for index in overlay._materials.size():
		var original: ShaderMaterial = overlay._materials[index]
		var replacement: ShaderMaterial = original.duplicate()
		replacement.shader = shader
		replacement.set_shader_parameter("static_mask", _texture)
		replacement.set_shader_parameter("static_bounds", Vector4(bounds[0], bounds[1], bounds[2]-bounds[0], bounds[3]-bounds[1]))
		replacement.set_shader_parameter("static_receiver", index == 4)
		_original.append(original)
		_replacement.append(replacement)
		for batch: Dictionary in overlay._batches.values():
			for node: MeshInstance3D in batch.nodes:
				if node.material_override == original:
					node.material_override = replacement
	overlay._materials = _replacement.duplicate()
	_owner = weakref(overlay)
	stats = {"size": row["size"], "texture_bytes": bytes, "conservative_resident_bytes": resident + bytes * 2,
		"source_count": manifest.source_count, "max_scale": row.max_scale, "bounds": bounds,
		"direction": manifest.direction, "dynamic_pass_removed": false}
	return true


func set_strength(value: float) -> void:
	for material: ShaderMaterial in _replacement:
		material.set_shader_parameter("static_strength", clampf(value, 0.0, 1.0))


func close() -> void:
	var overlay: Variant = _owner.get_ref() if _owner != null else null
	if typeof(overlay) == TYPE_OBJECT and is_instance_valid(overlay):
		for batch: Dictionary in overlay._batches.values():
			for node: MeshInstance3D in batch.nodes:
				var index := _replacement.find(node.material_override)
				if index >= 0:
					node.material_override = _original[index]
		overlay._materials = _original.duplicate()
	_owner = null
	_original.clear()
	_replacement.clear()
	_texture = null
