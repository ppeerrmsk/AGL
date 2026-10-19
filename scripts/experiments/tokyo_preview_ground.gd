extends Node3D
## 只供静态预览：等正式流送稳定后借用当前纹理，一次建平面，无常驻 tick。
const SHADER := preload("res://resources/shaders/tokyo_preview_ground.gdshader")


func snapshot(source: RasterBasemapRenderer) -> void:
	for child in get_children():
		child.free()
	for record: Dictionary in source.presentation_tiles():
		var sprite: Variant = record.sprite.get_ref()
		if typeof(sprite) != TYPE_OBJECT or not is_instance_valid(sprite):
			continue
		if not sprite.visible:
			continue
		if record.layer != null:
			var layer: Variant = record.layer.get_ref()
			if typeof(layer) != TYPE_OBJECT or not is_instance_valid(layer):
				continue
			if not layer.visible or layer.modulate.a < 0.999:
				continue
		var texture_size := Vector2(sprite.texture.get_size())
		var region: Rect2 = sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, texture_size)
		var rect := Rect2(sprite.position, region.size * sprite.scale)
		var uv := Rect2(region.position / texture_size, region.size / texture_size)
		var y := -0.8 if record.lod == &"strategic" else -0.6
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
			Vector3(rect.position.x, y, rect.position.y), Vector3(rect.end.x, y, rect.position.y),
			Vector3(rect.end.x, y, rect.end.y), Vector3(rect.position.x, y, rect.end.y)])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([uv.position,
			Vector2(uv.end.x, uv.position.y), uv.end, Vector2(uv.position.x, uv.end.y)])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var material := ShaderMaterial.new()
		material.shader = SHADER
		material.set_shader_parameter("map_texture", sprite.texture)
		material.set_shader_parameter("luma_scale", sprite.self_modulate.r)
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = material
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
