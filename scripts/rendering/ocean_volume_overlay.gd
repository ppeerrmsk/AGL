extends "res://scripts/rendering/tokyo_volume_overlay.gd"
## 海洋图接入相同的原生分辨率投影与静止重绘门，资源和纹理owner独立。
const OceanArchive := preload("res://scripts/rendering/ocean_volume_archive.gd")
const Ground := preload("res://scripts/rendering/ocean_volume_ground.gd")
const ContactAO := preload("res://scripts/rendering/map_contact_ao.gd")
const AO_STRUCTURE := preload("res://resources/shaders/ocean_contact_ao_structure.gdshader")
var _ocean_ground: Node3D
var _raster_ref: WeakRef
var _raster_visibility_layer := 1
var _raster_covered := false
var covered_raster_enabled := OS.get_environment("AGL_OCEAN_COVERED_RASTER") == "1"
var _opaque_inner_bounds := Rect2()


static func ocean_enabled(map_key: String, source_document: String) -> bool:
	return map_key == "ocean" and source_document == OceanArchive.DOCUMENT \
		and OS.get_environment("AGL_OCEAN_VOLUME").to_lower() not in ["off", "0", "false", "2d"] \
		and ResourceLoader.exists(OceanArchive.OCEAN_PATH)


func _load_archive() -> Resource:
	return load(OceanArchive.OCEAN_PATH)


func _setup_geometry() -> void:
	var ao_field := ContactAO.load_field("ocean")
	for material: ShaderMaterial in _materials:
		material.shader = AO_STRUCTURE
		if ao_field != null:
			ContactAO.bind(material, "ocean", ao_field)
	super._setup_geometry()
	_ocean_ground = Ground.new()
	_ocean_ground.name = "OceanSharedTerrain"
	_city.add_child(_ocean_ground)
	var source: Variant = _source_ref.get_ref()
	_ocean_ground.setup(source._raster_basemap, _archive)
	_raster_ref = weakref(source._raster_basemap)
	_raster_visibility_layer = source._raster_basemap.visibility_layer
	var strategic: Dictionary = _archive.terrain.get("StrategicBasemap", {})
	if not strategic.is_empty():
		var bounds: AABB = strategic.mesh.get_aabb()
		# 2倍最高地形量保守覆盖38度投影位移，另留80px合成羽化；边缘不获抑制资格。
		var padding := maxf(absf(bounds.position.y), absf(bounds.end.y)) * 2.0 + 80.0
		_opaque_inner_bounds = _archive.terrain_bounds.grow(-padding)


func _step_geometry(view_bounds: Rect2, scale_value: float, delta: float) -> bool:
	var changed := super._step_geometry(view_bounds, scale_value, delta)
	changed = _ocean_ground.sync(delta) or changed
	# 未启用的试验不进入逐帧覆盖计算；撤销试验时仍立即归还原mask。
	if not covered_raster_enabled:
		if _raster_covered:
			_set_raster_covered(false)
		return changed
	var raster: Variant = _raster_ref.get_ref() if _raster_ref != null else null
	var ready := false
	if typeof(raster) == TYPE_OBJECT and is_instance_valid(raster):
		var strategic: Variant = raster._strategic_sprite
		if typeof(strategic) == TYPE_OBJECT and is_instance_valid(strategic):
			var entry: Dictionary = _ocean_ground._planes.get(strategic.get_instance_id(), {})
			ready = not entry.is_empty() and entry.node.visible and entry.alpha == 1.0
	_set_raster_covered(covered_raster_enabled and _active and ready and _opaque_inner_bounds.encloses(view_bounds))
	return changed


func _set_raster_covered(covered: bool) -> void:
	var raster: Variant = _raster_ref.get_ref() if _raster_ref != null else null
	if typeof(raster) == TYPE_OBJECT and is_instance_valid(raster):
		var mask := 0 if covered else _raster_visibility_layer
		if raster.visibility_layer != mask:
			raster.visibility_layer = mask
	_raster_covered = covered


func _exit_tree() -> void:
	_set_raster_covered(false)


func _deactivate() -> void:
	_set_raster_covered(false)
	super._deactivate()
	var source: Variant = _source_ref.get_ref() if _source_ref != null else null
	if is_instance_valid(_ocean_ground) and (typeof(source) != TYPE_OBJECT or not is_instance_valid(source)):
		_ocean_ground.clear()


func debug_state() -> Dictionary:
	var state := super.debug_state()
	if is_instance_valid(_ocean_ground):
		state.merge(_ocean_ground.debug_state())
	state["nodes"] = int(state.get("nodes", 0)) + int(state.get("planes", 0))
	state["materials"] = int(state.get("materials", 0)) + int(state.get("planes", 0))
	state["map"] = "ocean"
	state["covered_raster_suppressed"] = _raster_covered
	state["map_msaa"] = _viewport.msaa_3d if is_instance_valid(_viewport) else -1
	return state
