extends CanvasLayer
## 正式 Survivor 飞机合成层：与 F6 同等输出采样、同一显示帧的相机和机体。

const Probe := preload("res://scripts/experiments/volume_world_probe.gd")
const FORMAL_SCENARIO := "volume_3d_formal"
const ENV_OVERRIDE := "AGL_AIRCRAFT_VOLUME"
const RENDER_SCALE := 1.0

var _mode_ref: WeakRef
var _subviewport := SubViewport.new()
var _screen := TextureRect.new()
var _ground_foreground := preload("res://scripts/rendering/ground_volume_foreground.gd").new()
var _probe: Node3D
var _enabled := true
var _display_updates := 0


static func default_enabled(external_experiment: bool = false) -> bool:
	if external_experiment:
		return false
	var override := OS.get_environment(ENV_OVERRIDE).strip_edges().to_lower()
	return override not in ["0", "false", "off", "png", "2d"]


func setup(mode: Node) -> void:
	_mode_ref = weakref(mode)
	layer = 0
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 与 F6 Probe 相同：先完成正式相机/导演更新，再采样这一显示帧。
	process_priority = 1000
	_subviewport.name = "AircraftVolumeViewport"
	_subviewport.transparent_bg = true
	_subviewport.own_world_3d = true
	_subviewport.gui_disable_input = true
	_subviewport.handle_input_locally = false
	_subviewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_subviewport.msaa_3d = Viewport.MSAA_2X
	add_child(_subviewport)
	_screen.name = "AircraftVolumeComposite"
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_screen.stretch_mode = TextureRect.STRETCH_SCALE
	_screen.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_screen.texture = _subviewport.get_texture()
	if OS.get_environment("AGL_WEATHER_VOLUME").to_lower() == "on":
		var composite := ShaderMaterial.new()
		composite.shader = preload("res://resources/shaders/weather_density_composite_preview.gdshader")
		_screen.material = composite
	add_child(_screen)
	add_child(_ground_foreground)
	_probe = Probe.new()
	_probe.name = "AircraftVolumeRenderer"
	_probe.process_mode = Node.PROCESS_MODE_ALWAYS
	_subviewport.add_child(_probe)
	_sync_size()
	mode.get_viewport().size_changed.connect(_sync_size)
	_probe.setup(mode, FORMAL_SCENARIO, {
		"include_map": false,
		"hide_2d_map": false,
		"prewarm_catalog": true,
	})
	_probe.set_process(false)


func _process(delta: float) -> void:
	if not _enabled or not is_instance_valid(_probe):
		return
	# 权威物理仍为 60 Hz；显示相机与真实姿态每显示帧同拍消费，不跨帧保存旧投影。
	_probe._process(delta)
	_ground_foreground.sync(_probe._ground_presenter)
	_display_updates += 1


func set_volume_enabled(enabled: bool) -> void:
	_enabled = enabled
	_screen.visible = enabled
	_ground_foreground.visible = enabled
	_subviewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if enabled \
		else SubViewport.UPDATE_DISABLED
	if is_instance_valid(_probe):
		_probe.set_bodies_enabled(enabled)
		if is_instance_valid(_probe._weather_volume):
			_probe._weather_volume.set_enabled(enabled)


func toggle_volume() -> bool:
	set_volume_enabled(not _enabled)
	return _enabled


func is_volume_enabled() -> bool:
	return _enabled


func summary() -> String:
	if is_instance_valid(_probe):
		return "formal_aircraft_volume=true transparent_shared_viewport=1 catalog_prewarmed=1 compositor=display_frame viewport_update=always render_scale=1.00 msaa_3d=2x phase_spread=false display_updates=%d render_size=%s\n" % [_display_updates, _subviewport.size] + String(_probe.summary())
	return "formal_aircraft_volume=false transparent_shared_viewport=0\n"


func _sync_size() -> void:
	if _mode_ref == null:
		return
	var mode: Variant = _mode_ref.get_ref()
	if typeof(mode) != TYPE_OBJECT or not is_instance_valid(mode):
		return
	var source: Viewport = mode.get_viewport()
	var logical_size := source.get_visible_rect().size
	# canvas_items stretch 的逻辑尺寸不一定等于屏幕像素；最大化/HiDPI 也保持原生采样。
	var pixel_scale := source.get_stretch_transform().get_scale() if source is Window else Vector2.ONE
	_subviewport.size = Vector2i(maxi(1, roundi(logical_size.x * absf(pixel_scale.x))),
		maxi(1, roundi(logical_size.y * absf(pixel_scale.y))))
	_screen.position = Vector2.ZERO
	_screen.size = logical_size


func _exit_tree() -> void:
	if _mode_ref == null:
		return
	var mode: Variant = _mode_ref.get_ref()
	if typeof(mode) == TYPE_OBJECT and is_instance_valid(mode):
		var source_viewport: Viewport = mode.get_viewport()
		if source_viewport.size_changed.is_connected(_sync_size):
			source_viewport.size_changed.disconnect(_sync_size)
