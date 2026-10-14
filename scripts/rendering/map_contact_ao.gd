extends RefCounted
## 只读离线接触场；没有静态资源缓存、运行时烘焙或 tick。
const VERSION := 1
const SIZE := 512
const RADIUS := 64.0
const SAMPLES := 32
const RECTS := {"desert": Rect2(3900, -400, 1792, 1664), "ocean": Rect2(-11850, -8000, 3072, 2816)}
const DOCUMENTS := {"desert": "res://resources/maps/desert_railway_preview.aglmap",
	"ocean": "res://resources/maps/ocean_islands_preview.aglmap"}
const COMMON_INPUTS := ["res://scripts/experiments/volume_mesh_factory.gd",
	"res://scripts/experiments/volume_building_factory.gd", "res://scripts/experiments/volume_map_factory.gd",
	"res://scripts/tests/build_map_contact_ao.gd", "res://scripts/rendering/map_contact_ao.gd"]


static func path_for(key: String) -> String:
	return "res://resources/maps/%s_contact_ao.res" % key


static func fingerprint(key: String) -> String:
	var values := PackedStringArray([str(VERSION), FileAccess.get_sha256(DOCUMENTS[key])])
	for path: String in COMMON_INPUTS:
		values.append(FileAccess.get_sha256(path))
	if key == "ocean":
		values.append(FileAccess.get_sha256("res://scripts/experiments/ocean_volume_factory.gd"))
	return "|".join(values).sha256_text()


static func valid(texture: Texture2D, key: String) -> bool:
	return texture != null and RECTS.has(key) and texture.get_size() == Vector2(SIZE, SIZE) \
		and texture.get_meta("ao_version", -1) == VERSION \
		and texture.get_meta("ao_rect", Rect2()) == RECTS[key] \
		and texture.get_meta("ao_document_hash", "") == FileAccess.get_sha256(DOCUMENTS[key]) \
		and (not OS.has_feature("editor") or texture.get_meta("ao_source_hash", "") == fingerprint(key))


static func load_field(key: String) -> Texture2D:
	if not RECTS.has(key) or OS.get_environment("AGL_MAP_CONTACT_AO").to_lower() in ["off", "0", "false"] \
		or not ResourceLoader.exists(path_for(key)):
		return null
	var texture := load(path_for(key)) as Texture2D
	return texture if valid(texture, key) else null


static func bind(material: ShaderMaterial, key: String, field: Texture2D = null) -> bool:
	material.set_shader_parameter("contact_ao_strength", 0.0)
	if not RECTS.has(key) or OS.get_environment("AGL_MAP_CONTACT_AO").to_lower() in ["off", "0", "false"]:
		return false
	var texture := field if field != null else load_field(key)
	if texture == null or texture.get_meta("ao_rect", Rect2()) != RECTS[key]:
		return false
	var rect: Rect2 = RECTS[key]
	material.set_shader_parameter("contact_ao_texture", texture)
	material.set_shader_parameter("contact_ao_rect", Vector4(rect.position.x, rect.position.y, rect.size.x, rect.size.y))
	material.set_shader_parameter("contact_ao_strength", 0.65)
	return true
