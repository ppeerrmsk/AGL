extends RefCounted
const Archive := preload("res://scripts/experiments/volume_terrain_archive.gd")
const Relief := preload("res://scripts/experiments/volume_desert_relief.gd")
var _pass := 0
var _fail := 0


func run() -> bool:
	var relief := Relief.new()
	_check(relief.archive != null, "current offline archive loaded")
	if relief.archive == null:
		return false
	var archive: Resource = relief.archive
	_check(archive.is_current() and archive.entries.size() == 146,
		"source fingerprint and all strategic/operational/detail meshes present")
	_check(archive.geometry_bytes > 0 and archive.geometry_bytes <= 32 * 1024 * 1024,
		"prebuilt geometry fits independent 32 MiB budget")
	var valid := true
	var measured_bytes := 0
	var layouts := Archive.tile_layouts()
	var fallback := Relief.new(false)
	for key: String in layouts:
		var entry: Dictionary = layouts[key]
		var mesh := relief.presentation_mesh(key, entry.bounds, entry.uv, entry.base_y)
		var expected := fallback.presentation_mesh(key, entry.bounds, entry.uv, entry.base_y)
		valid = valid and mesh == archive.entries[key].mesh and _same_mesh(mesh, expected)
		for channel: Variant in mesh.surface_get_arrays(0):
			if channel != null:
				measured_bytes += channel.to_byte_array().size()
	_check(valid and relief.archive_hits == 146 and relief.archive_misses == 0
		and fallback.archive == null and fallback.archive_misses == 146,
		"every loaded mesh exactly preserves canonical vertices normals UV custom attributes and indices")
	var original := String(archive.fingerprint)
	archive.fingerprint = "stale"
	_check(not archive.is_current(), "stale sources rejected")
	archive.fingerprint = original
	var saved_details: PackedScene = archive.details
	archive.details = null
	_check(not archive.is_current(), "archive missing its single decoration scene is rejected")
	archive.details = saved_details
	_check(not archive.is_current(true), "source archive cannot masquerade as native profile")
	var sample: Dictionary = layouts.StrategicBasemap
	_check(archive.matching_mesh("StrategicBasemap", Rect2(1, 2, 3, 4), sample.uv, sample.base_y) == null
		and archive.matching_mesh("StrategicBasemap", sample.bounds, Rect2(0, 0, 0.5, 1), sample.base_y) == null,
		"mismatched world coordinates or gutter never reuse wrong mesh")
	var generated := Relief.new(false).make_details()
	var cached := relief.make_details()
	valid = generated.get_child_count() == cached.get_child_count()
	for i in generated.get_child_count():
		var a: MeshInstance3D = generated.get_child(i)
		var b: MeshInstance3D = cached.get_child(i)
		valid = valid and a.name == b.name and _same_mesh(a.mesh, b.mesh)
		valid = valid and a.cast_shadow == b.cast_shadow and not b.is_processing()
		valid = valid and a.get_meta("scrub_vertices", 0) == b.get_meta("scrub_vertices", 0)
		valid = valid and a.has_meta("cover_far_mesh") == b.has_meta("cover_far_mesh")
		if a.has_meta("cover_far_mesh") and b.has_meta("cover_far_mesh"):
			valid = valid and a.get_meta("cover_near_mesh") == a.mesh and b.get_meta("cover_near_mesh") == b.mesh
			valid = valid and _same_mesh(a.get_meta("cover_far_mesh"), b.get_meta("cover_far_mesh"))
		var meshes: Array[ArrayMesh] = [b.mesh]
		if b.has_meta("cover_far_mesh"):
			meshes.append(b.get_meta("cover_far_mesh"))
		for mesh: ArrayMesh in meshes:
			for channel: Variant in mesh.surface_get_arrays(0):
				if channel != null:
					measured_bytes += channel.to_byte_array().size()
		var ma := a.material_override
		var mb := b.material_override
		valid = valid and ma.get_class() == mb.get_class()
		if ma is ShaderMaterial and mb is ShaderMaterial:
			valid = valid and ma.shader == mb.shader and ma.render_priority == mb.render_priority
		if ma is StandardMaterial3D and mb is StandardMaterial3D:
			valid = valid and ma.vertex_color_use_as_albedo == mb.vertex_color_use_as_albedo
			valid = valid and ma.vertex_color_is_srgb == mb.vertex_color_is_srgb
			valid = valid and ma.roughness == mb.roughness and ma.specular_mode == mb.specular_mode
			valid = valid and ma.cull_mode == mb.cull_mode
	_check(valid and cached.get_meta("vegetation_count") == 1200 and cached.get_meta("outcrop_count") == 360,
		"packed decoration retains all geometry batching metadata and static shadow policy")
	_test_tactical_details(relief, cached)
	_check(measured_bytes == archive.geometry_bytes and measured_bytes <= 32 * 1024 * 1024,
		"independent array sum includes both near/far resources once within geometry budget")
	_check(preload("res://scripts/tests/test_volume_native_surface.gd").new().run(archive, relief.surface),
		"all clipped tile faces preserve the full native surface height and shader normal field")
	generated.free()
	cached.free()
	print("[Terrain archive] ", _pass, " passed / ", _fail, " failed")
	return _fail == 0


func _same_mesh(a: ArrayMesh, b: ArrayMesh) -> bool:
	return var_to_bytes(a.surface_get_arrays(0)) == var_to_bytes(b.surface_get_arrays(0))


func _test_tactical_details(relief: RefCounted, source: Node3D) -> int:
	var generated: Node3D = Relief.new(false).make_details(true)
	var native := Relief.new(false)
	_check(native.archive == null,"numerical surface construction does not load either archive")
	native.bind_archive(true)
	_check(native.archive != null and native.archive.is_current(true) and not native.archive.is_current(false)
		and native.archive.resource_path == Archive.TACTICAL_PATH,"native profile loads only its explicitly marked archive")
	if native.archive == null:
		generated.free()
		return 0
	var cached: Node3D = native.make_details(true)
	var native_line := cached.get_node("Source_Water_Contours").material_override as ShaderMaterial
	var source_line := source.get_node("Source_Water_Contours").material_override as ShaderMaterial
	_check(native_line.get_shader_parameter("pixel_width_enabled") == true
		and source_line.get_shader_parameter("pixel_width_enabled") == false
		and native_line.shader.code.contains("uniform float minimum_width_px = 1.25;")
		and not native_line.shader.code.contains("depth_test_disabled"),
		"only native archived water enables bounded pixel coverage with real depth testing")
	var valid := generated.get_child_count() == cached.get_child_count()
	var preserved := true
	var bytes := 0
	for key: String in native.archive.entries:
		var mesh: ArrayMesh = native.archive.entries[key].mesh
		valid = valid and _same_mesh(mesh,relief.archive.entries[key].mesh)
		for channel: Variant in mesh.surface_get_arrays(0):
			if channel != null:
				bytes += channel.to_byte_array().size()
	for part: MeshInstance3D in cached.get_children():
		var expected: MeshInstance3D = generated.get_node(NodePath(part.name))
		var original: MeshInstance3D = source.get_node(NodePath(part.name))
		valid = valid and _same_mesh(part.mesh, expected.mesh)
		var meshes: Array[ArrayMesh] = [part.mesh]
		if part.has_meta("cover_far_mesh"):
			valid = valid and _same_mesh(part.get_meta("cover_far_mesh"), expected.get_meta("cover_far_mesh"))
			meshes.append(part.get_meta("cover_far_mesh"))
			for near in [true, false]:
				var a: ArrayMesh = part.mesh if near else part.get_meta("cover_far_mesh")
				var b: ArrayMesh = original.mesh if near else original.get_meta("cover_far_mesh")
				var count := int(original.get_meta("scrub_vertices")) / (1 if near else 3)
				for channel in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_COLOR]:
					preserved = preserved and a.surface_get_arrays(0)[channel].to_byte_array() == b.surface_get_arrays(0)[channel].slice(0,count).to_byte_array()
		else:
			preserved = preserved and _same_mesh(part.mesh, original.mesh)
		for mesh: ArrayMesh in meshes:
			for channel: Variant in mesh.surface_get_arrays(0):
				if channel != null:
					bytes += channel.to_byte_array().size()
	_check(valid and cached.get_meta("outcrop_count") == 0 and source.get_meta("outcrop_count") == 360,
		"native prebuilt removes only decorative rocks while source and raw records retain all 360")
	_check(preserved and cached.get_meta("vegetation_count") == 1200 and relief.data.outcrops.size() == 360,
		"native vegetation near/far and water channels exactly preserve original geometry normals colors")
	_check(bytes == native.archive.geometry_bytes and bytes <= 32*1024*1024,
		"native archive independently includes all terrain and near/far decoration bytes")
	generated.free()
	cached.free()
	return bytes


func _check(ok: bool, label: String) -> void:
	if ok:
		_pass += 1
	else:
		_fail += 1
		push_error("Terrain archive: " + label)
