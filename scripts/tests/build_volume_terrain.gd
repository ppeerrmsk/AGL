extends RefCounted
## 显式 bench 构建任务；仅写 bench/results，由调用者检查后复制产物。
const Archive := preload("res://scripts/experiments/volume_terrain_archive.gd")
const Relief := preload("res://scripts/experiments/volume_desert_relief.gd")
var _fail := 0


func run() -> void:
	var started := Time.get_ticks_usec()
	# 素材导入仅发生在显式离线构建；游戏直接加载已序列化纹理，不在运行时解码/缩图。
	var rock_image := Image.load_from_file("res://resources/desert_material_source/desert_rock_albedo_r40.png")
	if rock_image == null:
		_fail += 1
		return
	rock_image.convert(Image.FORMAT_RGBA8)
	rock_image.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	var mean_linear := Vector3.ZERO
	var mean_srgb := Vector3.ZERO
	for y in 512:
		for x in 512:
			var encoded := rock_image.get_pixel(x, y)
			mean_srgb += Vector3(encoded.r, encoded.g, encoded.b)
			var pixel := encoded.srgb_to_linear()
			mean_linear += Vector3(pixel.r, pixel.g, pixel.b)
	mean_linear /= 512.0 * 512.0
	mean_srgb /= 512.0 * 512.0
	rock_image.generate_mipmaps()
	var rock_bytes := rock_image.get_data().size()
	var rock_texture := ImageTexture.create_from_image(rock_image)
	rock_texture.set_meta("mean_linear", mean_linear)
	rock_texture.set_meta("mean_srgb", mean_srgb)
	var rock_error := ResourceSaver.save(rock_texture, "res://bench/results/desert_rock_albedo_r40.res", ResourceSaver.FLAG_COMPRESS)
	if rock_error != OK or rock_bytes > 1398100:
		_fail += 1
		return
	print("[Rock material bake] bytes=", rock_bytes, " size=512x512 mean_linear=", mean_linear, " mipmaps=", rock_image.has_mipmaps())
	# 旧机场清理使用同一份纯地形源图；预构建为资源，避免导出包运行时依赖裸 PNG 解码。
	var clean_image := Image.load_from_file("res://resources/maps/source/desert_railway_terrain_texture.png")
	if clean_image == null or clean_image.is_empty():
		_fail += 1
		return
	clean_image.convert(Image.FORMAT_RGB8)
	clean_image.generate_mipmaps()
	var clean_bytes := clean_image.get_data().size()
	var clean_texture := ImageTexture.create_from_image(clean_image)
	var clean_error := ResourceSaver.save(clean_texture,
		"res://bench/results/desert_clean_terrain_r52.res", ResourceSaver.FLAG_COMPRESS)
	if clean_error != OK or clean_bytes > 8388608:
		_fail += 1
		return
	print("[Clean terrain bake] bytes=", clean_bytes, " size=", clean_image.get_width(), "x",
		clean_image.get_height(), " mipmaps=", clean_image.has_mipmaps())
	var relief := Relief.new(false)
	var layouts := Archive.tile_layouts()
	var terrain_bytes := 0
	for key: String in layouts:
		var entry: Dictionary = layouts[key]
		entry.mesh = relief.plane_mesh(entry.render_bounds, entry.uv, entry.base_y, entry.bounds)
		terrain_bytes += _mesh_bytes(entry.mesh)
	for tactical: bool in [false, true]:
		var archive := Archive.new()
		archive.fingerprint = Archive.source_fingerprint()
		archive.entries = layouts
		archive.tactical_profile = tactical
		archive.geometry_bytes = terrain_bytes
		var root := relief.make_details(tactical)
		for child: MeshInstance3D in root.get_children():
			child.owner = root
			archive.geometry_bytes += _mesh_bytes(child.mesh)
			if child.has_meta("cover_far_mesh"):
				archive.geometry_bytes += _mesh_bytes(child.get_meta("cover_far_mesh"))
		var scene := PackedScene.new()
		var error := scene.pack(root)
		root.free()
		archive.details = scene
		var path := "res://bench/results/" + (Archive.TACTICAL_PATH if tactical else Archive.PATH).get_file()
		if error == OK and archive.geometry_bytes <= 32 * 1024 * 1024:
			error = ResourceSaver.save(archive, path, ResourceSaver.FLAG_COMPRESS)
		if error != OK or archive.geometry_bytes > 32 * 1024 * 1024:
			_fail += 1
			push_error("terrain archive failed or exceeded 32 MiB geometry budget")
		print("[Terrain bake] tactical=",tactical," meshes=", archive.entries.size(), " geometry_bytes=", archive.geometry_bytes,
			" elapsed_ms=", (Time.get_ticks_usec() - started) / 1000.0, " status=", error)


func _mesh_bytes(mesh: ArrayMesh) -> int:
	var bytes := 0
	for channel: Variant in mesh.surface_get_arrays(0):
		if channel != null:
			bytes += channel.to_byte_array().size()
	return bytes
