class_name AircraftHologramPreview
extends Control

## 选机页静态全息投影。只在候选项变化时换纹理，不创建可战斗 Aircraft，
## 轮廓与正式 AircraftRenderer 共用 AircraftSilhouetteCatalog。

const AircraftSilhouetteCatalogScript := preload("res://scripts/aircraft_silhouette_catalog.gd")
const TerminalUiStyleScript := preload("res://scripts/ui/terminal_ui_style.gd")

var _ghost_left: TextureRect
var _ghost_right: TextureRect
var _model: TextureRect
var _airframe_label: Label
var _link_label: Label
var _locked: bool = false
var _has_model: bool = false


func _init() -> void:
	name = "AircraftHologramPreview"
	custom_minimum_size = Vector2(246.0, 0.0)
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_children()
	resized.connect(queue_redraw)


func _draw() -> void:
	var accent := TerminalUiStyleScript.accent()
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Color(0.0, 0.0, 0.0, 0.86), true)
	draw_rect(bounds.grow(-0.5), Color(accent, 0.78), false, 1.0)

	# 固定网格、扫描线与准星足以形成终端全息感；不引入逐帧脚本 tick。
	for x in range(18, int(size.x), 18):
		draw_line(Vector2(x, 34.0), Vector2(x, size.y - 62.0),
			Color(accent, 0.055), 1.0)
	for y in range(42, maxi(43, int(size.y - 62.0)), 6):
		draw_line(Vector2(8.0, y), Vector2(size.x - 8.0, y),
			Color(accent, 0.035 if y % 18 else 0.09), 1.0)

	var center := Vector2(size.x * 0.5, maxf(105.0, (size.y - 34.0) * 0.47))
	var reticle_color := Color(accent, 0.30 if not _locked else 0.12)
	draw_line(center - Vector2(35.0, 0.0), center + Vector2(35.0, 0.0), reticle_color, 1.0)
	draw_line(center - Vector2(0.0, 35.0), center + Vector2(0.0, 35.0), reticle_color, 1.0)
	draw_arc(center, 70.0, 0.0, TAU, 48, Color(accent, 0.16), 1.0)
	draw_arc(center, 91.0, -2.65, -0.48, 24, Color(accent, 0.30), 1.0)
	draw_arc(center, 91.0, 0.48, 2.65, 24, Color(accent, 0.30), 1.0)
	_draw_corner_brackets(accent)


func show_profile(profile: PlayableAircraft, index: int, total: int) -> void:
	_locked = false
	var texture: Texture2D = null
	var airframe_name := ""
	if profile != null:
		airframe_name = tr(profile.display_name)
		if profile.base_params != null:
			texture = AircraftSilhouetteCatalogScript.texture_for_display_name(
				profile.base_params.display_name)
	_set_model_texture(texture)
	_airframe_label.text = airframe_name if not airframe_name.is_empty() \
		else tr("SLOT_NAME_UNKNOWN")
	_link_label.text = tr("AIRCRAFT_HOLOGRAM_LINK_FMT") % [index + 1, total] \
		if texture != null else tr("AIRCRAFT_HOLOGRAM_NO_DATA")
	queue_redraw()


func show_locked(index: int, total: int) -> void:
	_locked = true
	_set_model_texture(null)
	_airframe_label.text = tr("AIRCRAFT_HOLOGRAM_LOCKED")
	_link_label.text = tr("AIRCRAFT_HOLOGRAM_LOCKED_SLOT_FMT") % [index + 1, total]
	queue_redraw()


func has_model_texture() -> bool:
	return _has_model


func displayed_airframe() -> String:
	return _airframe_label.text


func _build_children() -> void:
	var title := Label.new()
	title.name = "HologramTitle"
	title.text = tr("AIRCRAFT_HOLOGRAM_TITLE")
	title.position = Vector2(10.0, 8.0)
	title.size = Vector2(226.0, 20.0)
	TerminalUiStyleScript.apply_terminal_label(
		title, 11, Color(TerminalUiStyleScript.accent(), 0.72))
	add_child(title)

	_ghost_left = _make_model_layer(Vector2(-2.0, 1.0), 0.12)
	_ghost_right = _make_model_layer(Vector2(2.0, -1.0), 0.12)
	_model = _make_model_layer(Vector2.ZERO, 0.82)

	_airframe_label = Label.new()
	_airframe_label.name = "HologramAirframeName"
	_airframe_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_airframe_label.offset_left = 8.0
	_airframe_label.offset_top = -58.0
	_airframe_label.offset_right = -8.0
	_airframe_label.offset_bottom = -32.0
	_airframe_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_airframe_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	TerminalUiStyleScript.apply_label(
		_airframe_label, 16, TerminalUiStyleScript.accent(), true)
	add_child(_airframe_label)

	_link_label = Label.new()
	_link_label.name = "HologramLinkStatus"
	_link_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_link_label.offset_left = 8.0
	_link_label.offset_top = -31.0
	_link_label.offset_right = -8.0
	_link_label.offset_bottom = -10.0
	_link_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	TerminalUiStyleScript.apply_terminal_label(
		_link_label, 9, Color(TerminalUiStyleScript.accent(), 0.58))
	add_child(_link_label)


func _make_model_layer(offset: Vector2, alpha: float) -> TextureRect:
	var layer := TextureRect.new()
	layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.offset_left = 18.0 + offset.x
	layer.offset_top = 38.0 + offset.y
	layer.offset_right = -18.0 + offset.x
	layer.offset_bottom = -66.0 + offset.y
	layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	layer.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	layer.modulate = Color(TerminalUiStyleScript.accent(), alpha)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(layer)
	return layer


func _set_model_texture(texture: Texture2D) -> void:
	_has_model = texture != null
	for layer in [_ghost_left, _ghost_right, _model]:
		layer.texture = texture
		layer.visible = texture != null


func _draw_corner_brackets(accent: Color) -> void:
	var color := Color(accent, 0.58)
	var top := 36.0
	var bottom := size.y - 65.0
	var left := 8.0
	var right := size.x - 8.0
	var arm := 15.0
	for corner in [Vector2(left, top), Vector2(right, top),
			Vector2(left, bottom), Vector2(right, bottom)]:
		var x_dir := 1.0 if corner.x == left else -1.0
		var y_dir := 1.0 if corner.y == top else -1.0
		draw_line(corner, corner + Vector2(x_dir * arm, 0.0), color, 1.0)
		draw_line(corner, corner + Vector2(0.0, y_dir * arm), color, 1.0)
