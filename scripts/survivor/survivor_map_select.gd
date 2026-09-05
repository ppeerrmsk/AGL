extends Node2D

## 生存模式 — 地图选择界面
## 选中地图后进入 survivor_select（机型选择）。

const TerminalPageShellScript := preload("res://scripts/ui/terminal_page_shell.gd")
const TerminalUiStyleScript := preload("res://scripts/ui/terminal_ui_style.gd")
const TerminalMapPreviewScript := preload("res://scripts/ui/terminal_map_preview.gd")
const BG_COLOR := Color("010202")

var _canvas: CanvasLayer
var _cards_container: HBoxContainer

## 字段里的 name/desc/tags 值均为翻译 key，由消费端 tr() 翻译。
const MAP_LIST: Array[Dictionary] = [
	{"id": "default", "name": "MAP_DEFAULT_NAME",
		"tags": ["TAG_PLAIN", "TAG_COAST", "TAG_HILLS"],
		"desc": "MAP_DEFAULT_DESC", "locked": false},
	{"id": "desert_railway_preview", "name": "MAP_DESERT_RAILWAY_NAME",
		"tags": ["TAG_DESERT", "TAG_RAILWAY", "TAG_GROUND_WAR"],
		"desc": "MAP_DESERT_RAILWAY_DESC",
		"map_path": "res://resources/maps/desert_railway_preview.aglmap",
		"preview_only": false, "locked": false},
	{"id": "ocean_islands_preview", "name": "MAP_OCEAN_ISLANDS_NAME",
		"tags": ["TAG_OCEAN", "TAG_ISLANDS", "TAG_PREVIEW"],
		"desc": "MAP_OCEAN_ISLANDS_DESC",
		"map_path": "res://resources/maps/ocean_islands_preview.aglmap",
		"preview_only": true, "locked": false},
	{"id": "tba_4", "name": "SLOT_TBA_NAME", "tags": ["TAG_LOCKED"],
		"desc": "SLOT_MAP_DESC", "locked": true},
	{"id": "tba_5", "name": "SLOT_TBA_NAME", "tags": ["TAG_LOCKED"],
		"desc": "SLOT_MAP_DESC", "locked": true},
]


func _ready() -> void:
	RenderingServer.set_default_clear_color(BG_COLOR)
	_build_ui()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			_on_back_pressed()
		elif event.keycode == KEY_B:
			get_tree().change_scene_to_file("res://scenes/boss_debug_select.tscn")


func _build_ui() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 10
	add_child(_canvas)
	var shell := TerminalPageShellScript.new()
	_canvas.add_child(shell)
	var frame := TerminalUiStyleScript.build_page(
		shell.content, tr("MAP_SELECT_TITLE"), tr("MAP_SELECT_SUBTITLE"), "THEATER // 01")
	var body := frame["body"] as PanelContainer
	var footer := frame["footer"] as HBoxContainer
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(scroll)
	_cards_container = HBoxContainer.new()
	_cards_container.alignment = BoxContainer.ALIGNMENT_BEGIN
	_cards_container.add_theme_constant_override("separation", 0)
	_cards_container.custom_minimum_size = Vector2(870, 0)
	_cards_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_cards_container)
	for index in range(MAP_LIST.size()):
		_build_map_card(index)
	TerminalUiStyleScript.build_footer_hint(footer,
		"%s  //  %s" % [tr("MAP_SELECT_HINT_ESC"), tr("BOSS_DEBUG_ENTRY_HINT")])
	TerminalUiStyleScript.build_footer_button(
		footer, tr("LOADOUT_BACK"), _on_back_pressed, 200.0)


func _build_map_card(index: int) -> void:
	var data: Dictionary = MAP_LIST[index]
	var locked: bool = data.get("locked", false)
	var accent := TerminalUiStyleScript.accent()
	var panel := PanelContainer.new()
	TerminalUiStyleScript.apply_panel(panel,
		Color(accent, 0.20 if locked else 0.82),
		Color(0.0, 0.0, 0.0, 0.54 if locked else 0.80), 9.0)
	panel.custom_minimum_size = Vector2(174, 340)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 7)
	panel.add_child(inner)

	var idx_label := Label.new()
	idx_label.text = tr("SLOT_MAP_INDEX_FMT") % (index + 1)
	TerminalUiStyleScript.apply_terminal_label(idx_label, 11,
		Color(accent, 0.74) if not locked else TerminalUiStyleScript.LOCKED_TEXT)
	inner.add_child(idx_label)
	var name_label := Label.new()
	name_label.text = tr(data["name"])
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size = Vector2(150, 42)
	TerminalUiStyleScript.apply_label(name_label, 18,
		TerminalUiStyleScript.LOCKED_TEXT if locked else accent, true)
	inner.add_child(name_label)
	var sep_line := ColorRect.new()
	sep_line.color = Color(accent, 0.62 if not locked else 0.18)
	sep_line.custom_minimum_size = Vector2(0, 1)
	inner.add_child(sep_line)
	inner.add_child(TerminalMapPreviewScript.new(index, locked, accent))

	var tags_box := HBoxContainer.new()
	tags_box.add_theme_constant_override("separation", 3)
	inner.add_child(tags_box)
	for tag_text in data["tags"] as Array:
		var tag := Label.new()
		tag.text = tr("SLOT_TAG_WRAP_FMT") % tr(tag_text)
		TerminalUiStyleScript.apply_terminal_label(tag, 9,
			TerminalUiStyleScript.LOCKED_TEXT if locked else Color(accent, 0.68))
		tags_box.add_child(tag)
	var desc_label := Label.new()
	desc_label.text = tr(data["desc"])
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(150, 0)
	TerminalUiStyleScript.apply_label(desc_label, 11,
		TerminalUiStyleScript.LOCKED_TEXT if locked else Color(accent, 0.72))
	inner.add_child(desc_label)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner.add_child(spacer)
	var button := Button.new()
	button.custom_minimum_size = Vector2(150, 38)
	button.text = tr("SLOT_LOCKED_BUTTON") if locked else tr("SLOT_SELECT_BUTTON")
	button.disabled = locked
	TerminalUiStyleScript.apply_button(button, accent)
	if not locked:
		var captured_index := index
		button.pressed.connect(func() -> void: _on_map_selected(captured_index))
	inner.add_child(button)
	_cards_container.add_child(panel)


func _on_map_selected(index: int) -> void:
	var data: Dictionary = MAP_LIST[index]
	get_tree().set_meta("survivor_map_id", data["id"])
	if data.has("map_path"):
		get_tree().set_meta("ugc_map_path", data["map_path"])
	elif get_tree().has_meta("ugc_map_path"):
		get_tree().remove_meta("ugc_map_path")
	get_tree().set_meta("map_preview_only", bool(data.get("preview_only", false)))
	get_tree().change_scene_to_file("res://scenes/survivor_select.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
