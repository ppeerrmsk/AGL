class_name SurvivorTutorial
extends CanvasLayer

## 首次进入生存模式时的嵌入式教程。

const ITEM_CLICK_ATTACK := 0
const ITEM_AUTO_FIRE := 1
const ITEM_CAMERA := 2
const ITEM_ZOOM := 3
const ITEM_COUNT := 4

const PER_ITEM_TIMEOUT := 14.0
const FADE_OUT := 0.6
const FINAL_FADE := 0.8
## 前三架轰炸机全部击落后，整个教程消失
const BOMBER_KILL_REQUIRED := 3

const PREF_FILE := "user://tutorial.cfg"
const PREF_SECTION := "survivor"
const PREF_KEY_FIRST_RUN_DONE := "first_run_done"

var _items_done: Array[bool] = [false, false, false, false]
var _items_timer: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _items_fade: Array[float] = [1.0, 1.0, 1.0, 1.0]
var _panel: PanelContainer
var _item_labels: Array[RichTextLabel] = []
var _item_check: Array[Label] = []

var _world_popup: SurvivorTutorialFrame
var _world_target: Node2D
var _world_done: bool = false
var _world_timer: float = 0.0
## 外部注入的查找函数（Callable），返回 Node2D 或 null
var find_target_fn: Callable

var _bomber_kills: int = 0
var _ended: bool = false

func _ready() -> void:
	layer = 20
	_build_ui()
	set_process(true)

static func should_show() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(PREF_FILE) != OK:
		return true
	return not cfg.get_value(PREF_SECTION, PREF_KEY_FIRST_RUN_DONE, false)

static func mark_done() -> void:
	var cfg := ConfigFile.new()
	cfg.load(PREF_FILE)
	cfg.set_value(PREF_SECTION, PREF_KEY_FIRST_RUN_DONE, true)
	cfg.save(PREF_FILE)

func _build_ui() -> void:
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.08, 0.86)
	sb.border_color = Color(1.0, 0.88, 0.54, 0.85)
	sb.set_border_width_all(1)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_panel.add_child(vb)

	var header := Label.new()
	header.text = tr("TUTORIAL_HEADER")
	header.add_theme_font_size_override("font_size", 14)
	header.add_theme_color_override("font_color", Color(1.0, 0.88, 0.54, 1.0))
	vb.add_child(header)

	## ── 游戏规则说明（静态文字，不打勾）──
	var rule_keys := ["TUTORIAL_RULE_AUTOFLY", "TUTORIAL_RULE_CLICKMOVE"]
	for rk in rule_keys:
		var rule := RichTextLabel.new()
		rule.bbcode_enabled = true
		rule.fit_content = true
		rule.scroll_active = false
		rule.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rule.text = tr(rk)
		rule.add_theme_font_size_override("normal_font_size", 13)
		rule.add_theme_color_override("default_color", Color(0.78, 0.88, 1.0, 1.0))
		rule.custom_minimum_size = Vector2(380, 0)
		vb.add_child(rule)

	## 分隔线
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 6)
	vb.add_child(sep)

	var keys := [
		"TUTORIAL_CLICK_ATTACK",
		"TUTORIAL_AUTO_FIRE",
		"TUTORIAL_CAMERA",
		"TUTORIAL_ZOOM",
	]
	for i in range(ITEM_COUNT):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vb.add_child(row)

		var check := Label.new()
		check.text = "·"
		check.add_theme_font_size_override("font_size", 16)
		check.add_theme_color_override("font_color", Color(1.0, 0.88, 0.54, 1.0))
		check.custom_minimum_size = Vector2(14, 0)
		row.add_child(check)
		_item_check.append(check)

		var rtl := RichTextLabel.new()
		rtl.bbcode_enabled = true
		rtl.fit_content = true
		rtl.scroll_active = false
		rtl.autowrap_mode = TextServer.AUTOWRAP_OFF
		rtl.text = tr(keys[i])
		rtl.add_theme_font_size_override("normal_font_size", 14)
		rtl.custom_minimum_size = Vector2(360, 0)
		row.add_child(rtl)
		_item_labels.append(rtl)

	## ── 世界坐标标定框 ──
	_world_popup = SurvivorTutorialFrame.new()
	_world_popup.text = tr("TUTORIAL_WORLD_CLICK")
	_world_popup.header = "TGT · CLICK"
	_world_popup.visible = false
	add_child(_world_popup)

func notify_click_attack() -> void:
	_complete_item(ITEM_CLICK_ATTACK)
	_world_done = true

func notify_pan() -> void:
	_complete_item(ITEM_CAMERA)

func notify_zoom() -> void:
	_complete_item(ITEM_ZOOM)

## 兼容旧调用方
func notify_pan_or_zoom() -> void:
	_complete_item(ITEM_CAMERA)
	_complete_item(ITEM_ZOOM)

func notify_missile_fired() -> void:
	_complete_item(ITEM_AUTO_FIRE)

## 外部通知：一架轰炸机（Tu-160）被击落。累计 3 架后整个教程淡出
func notify_bomber_killed() -> void:
	_bomber_kills += 1

func _complete_item(idx: int) -> void:
	if idx < 0 or idx >= ITEM_COUNT or _items_done[idx]:
		return
	_items_done[idx] = true
	_item_check[idx].text = "✓"
	_item_check[idx].add_theme_color_override("font_color", Color(0.55, 1.0, 0.65, 1.0))

func _process(delta: float) -> void:
	if _ended:
		return
	_layout()
	_update_items(delta)
	_update_world_popup(delta)

	## 整个教程的结束条件：前三架轰炸机全部歼灭
	if _bomber_kills >= BOMBER_KILL_REQUIRED:
		_end_tutorial()

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	_panel.size = Vector2.ZERO
	var panel_size := _panel.get_combined_minimum_size()
	var panel_y := vp.y - 20.0 - 20.0 - 30.0 - panel_size.y
	_panel.position = Vector2((vp.x - panel_size.x) * 0.5, panel_y)

func _update_items(_delta: float) -> void:
	## 条目打勾后仍保留可见（仅变灰 + 绿勾），整个教程由"3 架轰炸机被击落"统一结束
	for i in range(ITEM_COUNT):
		_item_labels[i].modulate.a = _items_fade[i]
		_item_check[i].modulate.a = _items_fade[i]

func _update_world_popup(delta: float) -> void:
	if _world_done:
		if _world_popup.visible:
			_world_popup.modulate.a = maxf(_world_popup.modulate.a - delta / FADE_OUT, 0.0)
			if _world_popup.modulate.a <= 0.001:
				_world_popup.visible = false
		return
	if not is_instance_valid(_world_target) and find_target_fn.is_valid():
		var t: Node2D = find_target_fn.call()
		if t:
			_world_target = t
			_world_popup.visible = true
	if not is_instance_valid(_world_target):
		return
	_world_timer += delta
	if _world_timer >= PER_ITEM_TIMEOUT:
		_world_done = true
		return
	var screen_pos: Vector2 = _world_target.get_global_transform_with_canvas().origin
	## 目标菱形相对框原点的偏移 = (BOX_W + GAP, BOX_H/2)
	_world_popup.position = Vector2(
		screen_pos.x - SurvivorTutorialFrame.BOX_W - SurvivorTutorialFrame.GAP,
		screen_pos.y - SurvivorTutorialFrame.BOX_H * 0.5,
	)

func _end_tutorial() -> void:
	if _ended:
		return
	_ended = true
	mark_done()
	## CanvasLayer 没有 modulate，给两个子 Control 各做一次淡出
	var tw := create_tween().set_parallel(true)
	if is_instance_valid(_panel):
		tw.tween_property(_panel, "modulate:a", 0.0, FINAL_FADE)
	if is_instance_valid(_world_popup):
		tw.tween_property(_world_popup, "modulate:a", 0.0, FINAL_FADE)
	tw.chain().tween_callback(queue_free)
