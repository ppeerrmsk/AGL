extends Node3D
## 共享纹理的有界桥接：最多17个节点，运行时不构建网格。
const SHADER := preload("res://resources/shaders/ocean_volume_ground.gdshader")
const ContactAO := preload("res://scripts/rendering/map_contact_ao.gd")
const PARAMS := ["tint", "saturation", "brightness", "contrast", "edge_floor", "edge_gain",
	"edge_cap", "edge_color", "grain_texture", "grain_strength", "grain_repeat", "vignette_strength",
	"level_size_px", "tile_origin_px", "tile_texture_size_px"]
var _source: WeakRef
var _archive: Resource
var _planes: Dictionary = {}
var source_scans := 0
var _source_revision := -1
var _retired_dirty := false
var misses := 0
var peak_planes := 0
var _ao_field: Texture2D


func setup(source: Node2D, archive: Resource) -> void:
	_source = weakref(source)
	source.presentation_tile_retiring.connect(_on_tile_retiring)
	source.tree_exiting.connect(clear)
	_archive = archive
	_ao_field = ContactAO.load_field("ocean")
	set_process(false)


func sync(_delta: float) -> bool:
	var source: Variant = _source.get_ref() if _source != null else null
	if typeof(source) != TYPE_OBJECT or not is_instance_valid(source):
		var changed := not _planes.is_empty()
		clear()
		return changed
	var changed := _retired_dirty
	_retired_dirty = false
	# owner已在所有增删入口推进版本；稳定时不重复构造瓦片Dictionary/WeakRef快照。
	# 透明度与目标层顺序仍逐帧同步，不能把它们一起降频。
	if _source_revision != source.presentation_revision:
		source_scans += 1
		_source_revision = source.presentation_revision
		var wanted := {}
		var records: Array[Dictionary] = source.presentation_tiles()
		for record in records:
			var sprite: Variant = record.sprite.get_ref()
			if typeof(sprite) == TYPE_OBJECT and is_instance_valid(sprite):
				wanted[sprite.get_instance_id()] = true
		# 先退役再绑定，避免满额换块时丢失新块。
		for key: int in _planes.keys():
			if not wanted.has(key):
				_planes[key].node.free()
				_planes.erase(key)
				changed = true
		for record in records:
			var sprite: Variant = record.sprite.get_ref()
			if typeof(sprite) != TYPE_OBJECT or not is_instance_valid(sprite):
				continue
			var key: int = sprite.get_instance_id()
			if not _planes.has(key) and _planes.size() < 17:
				var entry := _bind(sprite, record)
				if not entry.is_empty():
					_planes[key] = entry
					changed = true
		peak_planes = maxi(peak_planes, _planes.size())
	for key: int in _planes.keys():
		var entry: Dictionary = _planes[key]
		var sprite: Variant = entry.sprite.get_ref()
		if typeof(sprite) != TYPE_OBJECT or not is_instance_valid(sprite):
			entry.node.free()
			_planes.erase(key)
			changed = true
			continue
		var layer: Variant = entry.layer.get_ref() if entry.layer != null else null
		var has_layer := typeof(layer) == TYPE_OBJECT and is_instance_valid(layer)
		var visible_now: bool = sprite.visible and (layer.visible if has_layer else entry.layer == null)
		var opacity: float = sprite.modulate.a * (layer.modulate.a if has_layer else 1.0)
		# 缩远时目标Operational置顶；不能固定让旧Detail压住整个淡入。
		var priority := -100 if not has_layer else (-80 if layer.z_index == 2 else -90)
		if entry.material.render_priority != priority:
			entry.material.render_priority = priority
			changed = true
		if entry.node.visible != visible_now or not is_equal_approx(entry.alpha, opacity):
			entry.node.visible = visible_now
			entry.material.set_shader_parameter("opacity", opacity)
			entry.alpha = opacity
			changed = true
	return changed


func _bind(sprite: Sprite2D, record: Dictionary) -> Dictionary:
	var layout: Dictionary = _archive.terrain.get(String(sprite.name), {})
	var texture_size := Vector2(sprite.texture.get_size())
	var region := sprite.region_rect if sprite.region_enabled else Rect2(Vector2.ZERO, texture_size)
	var bounds := Rect2(sprite.position, region.size * sprite.scale)
	var uv := Rect2(region.position / texture_size, region.size / texture_size)
	if layout.is_empty() or layout.bounds != bounds or layout.uv != uv:
		misses += 1
		return {}
	var material := ShaderMaterial.new()
	material.shader = SHADER
	if _ao_field != null:
		ContactAO.bind(material, "ocean", _ao_field)
	material.set_shader_parameter("map_texture", sprite.texture)
	material.set_shader_parameter("relief_texture", _archive.relief_texture)
	material.set_shader_parameter("luma_scale", sprite.self_modulate.r)
	for key: String in PARAMS:
		material.set_shader_parameter(key, sprite.material.get_shader_parameter(key))
	material.render_priority = -100 if record.lod == &"strategic" else (-90 if record.lod == &"operational" else -80)
	var node := MeshInstance3D.new()
	node.mesh = layout.mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
	return {"node": node, "material": material, "sprite": record.sprite, "layer": record.layer, "alpha": -1.0}


func _on_tile_retiring(instance_id: int) -> void:
	if _planes.has(instance_id):
		_planes[instance_id].node.free()
		_planes.erase(instance_id)
		_retired_dirty = true
	_source_revision = -1


func clear() -> void:
	var source: Variant = _source.get_ref() if _source != null else null
	if typeof(source) == TYPE_OBJECT and is_instance_valid(source):
		if source.presentation_tile_retiring.is_connected(_on_tile_retiring):
			source.presentation_tile_retiring.disconnect(_on_tile_retiring)
		if source.tree_exiting.is_connected(clear):
			source.tree_exiting.disconnect(clear)
	for entry: Dictionary in _planes.values():
		entry.node.free()
	_planes.clear()
	_archive = null
	_source = null
	_ao_field = null
	_source_revision = -1


func _exit_tree() -> void:
	clear()


func debug_state() -> Dictionary:
	var triangles := 0
	for entry: Dictionary in _planes.values():
		if entry.node.visible:
			triangles += entry.node.mesh.surface_get_array_index_len(0) / 3
	return {"planes": _planes.size(), "peak_planes": peak_planes, "misses": misses,
		"source_scans": source_scans,
		"terrain_triangles": triangles, "shared_textures": true, "runtime_mesh_builds": 0,
		"contact_ao_active": _ao_field != null}
