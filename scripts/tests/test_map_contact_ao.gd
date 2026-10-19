extends RefCounted
const AO := preload("res://scripts/rendering/map_contact_ao.gd")
const Bake := preload("res://scripts/tests/build_map_contact_ao.gd")
const Geometry := preload("res://scripts/experiments/volume_mesh_factory.gd")
const Factory := preload("res://scripts/experiments/volume_map_factory.gd")
var _pass := 0
var _fail := 0


func run() -> void:
	var visual: GDScript = load("res://scripts/tests/map_contact_ao_visual.gd")
	_check(visual != null and visual.can_instantiate(), "menu Visual compiles")
	var combat: GDScript = load("res://scripts/tests/desert_contact_ao_combat.gd")
	_check(combat != null and combat.can_instantiate(), "industrial C1 compiles")
	var rays := Bake.directions()
	_check(rays.size() == 32 and rays == Bake.directions(), "deterministic hemisphere")
	var normalized := true
	for ray in rays:
		normalized = normalized and is_equal_approx(ray.length(), 1.0) and ray.y > 0.0
	_check(normalized, "unit upward rays")
	var builder := Geometry.new()
	builder.quad(Vector3(-100, 4, -100), Vector3(100, 4, -100), Vector3(100, 4, 100), Vector3(-100, 4, 100), Color.WHITE)
	var triangles := TriangleMesh.new()
	_check(triangles.create_from_faces(builder.mesh().get_faces()), "real BVH")
	var near := Bake.occlusion(triangles, Vector3.ZERO, rays)
	var far := Bake.occlusion(triangles, Vector3(0, -35, 0), rays)
	_check(near > 0.8 and near > far and far > 0, "finite radius soft attenuation")
	_check(Bake.occlusion(triangles, Vector3(200, 0, 200), rays) == 0, "open ground stays unchanged")
	_check(Bake.occlusion(triangles, Vector3(0, 8, 0), rays) == 0, "upward rays do not invent underfloor blockers")
	var previous := OS.get_environment("AGL_MAP_CONTACT_AO")
	OS.set_environment("AGL_MAP_CONTACT_AO", "")
	var bytes := 0
	for key: String in AO.RECTS:
		var texture := AO.load_field(key)
		_check(texture != null, key + " production field valid")
		if texture == null: continue
		var image := texture.get_image()
		bytes += image.get_data().size()
		_check(image.get_format() == Image.FORMAT_R8 and image.has_mipmaps(), key + " linear single channel mip data")
		var border := 0.0
		for i in AO.SIZE:
			border = maxf(border, maxf(image.get_pixel(i, 0).r, image.get_pixel(i, AO.SIZE - 1).r))
			border = maxf(border, maxf(image.get_pixel(0, i).r, image.get_pixel(AO.SIZE - 1, i).r))
		_check(border == 0.0, key + " zero perimeter cannot form regional seam")
		_check(float(texture.get_meta("ao_maximum", 0.0)) > 0.1, key + " occlusion is not empty")
		var copy := texture.duplicate() as Texture2D
		copy.set_meta("ao_document_hash", "stale")
		_check(not AO.valid(copy, key), key + " stale source fails closed")
		var material := ShaderMaterial.new()
		material.shader = load("res://resources/shaders/ocean_contact_ao_structure.gdshader")
		var before_refs := texture.get_reference_count()
		_check(not AO.bind(material, "tokyo", texture), key + " unknown destination rejected")
		_check(not AO.bind(material, "ocean" if key == "desert" else "desert", texture), key + " cross-map field rejected")
		_check(texture.get_reference_count() == before_refs, key + " rejected fields retain no reference")
		_check(AO.bind(material, key, texture) and material.get_shader_parameter("contact_ao_texture") == texture, key + " shared texture binding")
		OS.set_environment("AGL_MAP_CONTACT_AO", "off")
		_check(not AO.bind(material, key, texture) and material.get_shader_parameter("contact_ao_strength") == 0.0, key + " explicit off overrides resident field")
		OS.set_environment("AGL_MAP_CONTACT_AO", "")
	_check(bytes <= 700000, "both mip fields within 700000 bytes")
	_check(AO.load_field("tokyo") == null, "Tokyo has no accidental field")
	var doc := MapDocument.load_from(AO.DOCUMENTS.desert)
	var packet := Factory.build(doc, true, true)
	var root := MeshInstance3D.new()
	Factory.configure_instance(root, packet, Geometry.material())
	_check(root.material_override.get_shader_parameter("contact_ao_strength") == 0.65, "desert apron binds during original map construction")
	_check(root.get_child(0).material_override.shader == Factory.LINE_SHADER, "crisp routes untouched")
	_check(root.get_child(1).material_override.get_shader_parameter("contact_ao_strength") == 0.65, "actual structure material receives AO")
	root.free()
	OS.set_environment("AGL_MAP_CONTACT_AO", "off")
	var original := Geometry.material()
	var fallback := MeshInstance3D.new()
	Factory.configure_instance(fallback, packet, original)
	_check(fallback.material_override == original, "off retains exact original apron material")
	fallback.free()
	OS.set_environment("AGL_MAP_CONTACT_AO", previous)
	print("[Contact AO] pass=", _pass, " fail=", _fail, " bytes=", bytes)


func _check(ok: bool, label: String) -> void:
	if ok: _pass += 1
	else:
		_fail += 1
		push_error("Contact AO: " + label)
