extends RefCounted
## R32离线色板权威：只改RGBA8的RGB，不重建顶点/法线/索引，不在运行时逐像素查表。
const PAIRS := {"80877e": "949a94", "697d65": "879580", "64765f": "819078",
	"95958a": "919790", "757d77": "858f88", "636d6b": "858b85", "6e7772": "8b948a",
	"929789": "a9ada7", "a09f96": "b0b1a9", "aaa89f": "b9bab3", "858b87": "a1a8a2"}


static func recolor(mesh: ArrayMesh) -> ArrayMesh:
	if mesh.get_surface_count() == 0:
		return ArrayMesh.new()
	assert(mesh.get_surface_count() == 1 and mesh.get_blend_shape_count() == 0)
	var source: Dictionary = mesh.get("_surfaces")[0]
	var format := int(source.format)
	assert((format & Mesh.ARRAY_FORMAT_COLOR) != 0 and (format & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES) == 0)
	assert(RenderingServer.mesh_surface_get_format_attribute_stride(format, int(source.vertex_count)) == 4)
	var attributes: PackedByteArray = source.attribute_data.duplicate()
	assert(attributes.size() == int(source.vertex_count) * 4)
	var lookup: Dictionary = {}
	for old: String in PAIRS:
		lookup[old.hex_to_int()] = String(PAIRS[old]).hex_to_int()
	for offset in range(0, attributes.size(), 4):
		var rgb := (int(attributes[offset]) << 16) | (int(attributes[offset + 1]) << 8) | int(attributes[offset + 2])
		if lookup.has(rgb):
			var target := int(lookup[rgb])
			attributes[offset] = (target >> 16) & 255
			attributes[offset + 1] = (target >> 8) & 255
			attributes[offset + 2] = target & 255
	var changed := source.duplicate()
	changed.attribute_data = attributes
	var result := ArrayMesh.new()
	result.set("_surfaces", [changed])
	return result
