class_name ZoneHint
extends CanvasLayer

## Three notification channels share the same terminal HUD presentation:
## - top: persistent emergency or objective information;
## - bottom: temporary feedback and recoverable errors;
## - warning: an independent flashing BOSS alert.

const NotificationTerminalBarScript := preload(
	"res://scripts/survivor/notification_terminal_bar.gd")

const COLOR_ERROR := Color(1.0, 0.72, 0.45, 1.0)
const WARNING_ACCENT_COLOR := Color("ff493d")
const NOTICE_HEIGHT := NotificationTerminalBarScript.BAR_HEIGHT
const NOTICE_ANCHOR_LEFT := 0.2
const NOTICE_ANCHOR_RIGHT := 0.8
const BOTTOM_RESERVED_HEIGHT := 54.0
const TOP_RESERVED_HEIGHT := 72.0
const NOTIFICATION_LAYER := 9
const SLIDE_DURATION := 0.25

const WARNING_FLASH_COUNT := 3
const WARNING_FLASH_ON_SEC := 0.35
const WARNING_FLASH_OFF_SEC := 0.15

var _bg: Control
var _temp_bg: Control
var _persistent_visible := false
var _persistent_text := ""
var _temp_timer := 0.0
var _showing_temp := false
var _top_tween: Tween
var _bottom_tween: Tween

var _warn_bg: Control
var _warn_timer := 0.0
var _warn_phase := 0
var _warn_on := false


func _ready() -> void:
	layer = NOTIFICATION_LAYER
	_build()


func _build() -> void:
	if _bg != null:
		return
	_bg = NotificationTerminalBarScript.new()
	_bg.anchor_left = NOTICE_ANCHOR_LEFT
	_bg.anchor_right = NOTICE_ANCHOR_RIGHT
	_bg.offset_top = -NOTICE_HEIGHT
	_bg.offset_bottom = 0.0
	_bg.visible = false
	add_child(_bg)

	# Temporary hints settle directly above the permanent 3u bottom HUD bar.
	_temp_bg = NotificationTerminalBarScript.new()
	_temp_bg.anchor_left = NOTICE_ANCHOR_LEFT
	_temp_bg.anchor_right = NOTICE_ANCHOR_RIGHT
	_temp_bg.anchor_top = 1.0
	_temp_bg.anchor_bottom = 1.0
	_temp_bg.offset_top = 0.0
	_temp_bg.offset_bottom = NOTICE_HEIGHT
	_temp_bg.visible = false
	add_child(_temp_bg)

	# The BOSS warning uses the same icon/text cells and only retains its flash behavior.
	_warn_bg = NotificationTerminalBarScript.new()
	_warn_bg.anchor_left = NOTICE_ANCHOR_LEFT
	_warn_bg.anchor_right = NOTICE_ANCHOR_RIGHT
	_warn_bg.anchor_top = 0.32
	_warn_bg.anchor_bottom = 0.32
	_warn_bg.offset_top = -NOTICE_HEIGHT * 0.5
	_warn_bg.offset_bottom = NOTICE_HEIGHT * 0.5
	_warn_bg.visible = false
	add_child(_warn_bg)


func show_persistent(msg: String) -> void:
	_build()
	_persistent_visible = true
	_persistent_text = msg
	_apply_persistent()


func hide_persistent(expected_text: String = "") -> void:
	if expected_text != "" and _persistent_text != expected_text:
		return
	_persistent_visible = false
	_slide_top(false)


func _apply_persistent() -> void:
	_bg.configure(_persistent_text, "⚠")
	_slide_top(true)


func show_temp(msg: String, duration: float = 3.5) -> void:
	_build()
	_showing_temp = true
	_temp_timer = duration
	_temp_bg.configure(msg, "✓")
	_slide_bottom(true)


func show_error_temp(msg: String, duration: float = 8.0) -> void:
	_build()
	_showing_temp = true
	_temp_timer = duration
	_temp_bg.configure(msg, "⚠", COLOR_ERROR, false)
	_slide_bottom(true)


func _slide_top(show: bool) -> void:
	if _top_tween != null and _top_tween.is_valid():
		_top_tween.kill()
	if show:
		_bg.visible = true
	var target_top := TOP_RESERVED_HEIGHT if show else -NOTICE_HEIGHT
	var target_bottom := TOP_RESERVED_HEIGHT + NOTICE_HEIGHT if show else 0.0
	_top_tween = create_tween().set_parallel(true)
	_top_tween.set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT if show else Tween.EASE_IN)
	_top_tween.tween_property(_bg, "offset_top", target_top, SLIDE_DURATION)
	_top_tween.tween_property(_bg, "offset_bottom", target_bottom, SLIDE_DURATION)
	if not show:
		_top_tween.chain().tween_callback(_finish_top_hide)


func _slide_bottom(show: bool) -> void:
	if _bottom_tween != null and _bottom_tween.is_valid():
		_bottom_tween.kill()
	if show:
		_temp_bg.visible = true
	var target_top := -(BOTTOM_RESERVED_HEIGHT + NOTICE_HEIGHT) if show else 0.0
	var target_bottom := -BOTTOM_RESERVED_HEIGHT if show else NOTICE_HEIGHT
	_bottom_tween = create_tween().set_parallel(true)
	_bottom_tween.set_trans(Tween.TRANS_QUAD).set_ease(
		Tween.EASE_OUT if show else Tween.EASE_IN)
	_bottom_tween.tween_property(_temp_bg, "offset_top", target_top, SLIDE_DURATION)
	_bottom_tween.tween_property(_temp_bg, "offset_bottom", target_bottom, SLIDE_DURATION)
	if not show:
		_bottom_tween.chain().tween_callback(_finish_bottom_hide)


func _finish_top_hide() -> void:
	if not _persistent_visible:
		_bg.visible = false


func _finish_bottom_hide() -> void:
	if not _showing_temp:
		_temp_bg.visible = false


func _process(delta: float) -> void:
	if _showing_temp:
		_temp_timer -= delta
		if _temp_timer <= 0.0:
			_showing_temp = false
			_slide_bottom(false)
	if _warn_phase > 0:
		_warn_timer -= delta
		if _warn_timer <= 0.0:
			_warn_phase -= 1
			_warn_on = not _warn_on
			if _warn_phase <= 0:
				_warn_bg.visible = false
			else:
				_warn_bg.visible = _warn_on
				_warn_timer = WARNING_FLASH_ON_SEC if _warn_on else WARNING_FLASH_OFF_SEC


func show_warning_banner(msg: String, flashes: int = WARNING_FLASH_COUNT) -> void:
	_build()
	_warn_bg.configure(msg, "⚠", WARNING_ACCENT_COLOR, false)
	_warn_phase = flashes * 2
	_warn_on = true
	_warn_bg.visible = true
	_warn_timer = WARNING_FLASH_ON_SEC
