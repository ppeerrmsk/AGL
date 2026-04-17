class_name ZoneHint
extends CanvasLayer

## 顶部提示条：两种模式
##   - persistent：脉冲提示（"新战区已开放 — Tab"），由 survivor_mode 显式触发 show / hide
##   - temp：临时 toast（"战区 X 攻克！获得 XXX"），N 秒后自动消失

const COLOR_INFO := Color(0.9, 1.0, 0.5, 1.0)    ## 新战区
const COLOR_VICTORY := Color(0.5, 1.0, 0.75, 1.0) ## 攻克 + 奖励
const BG_COLOR := Color(0.05, 0.08, 0.03, 0.7)

## Warning 横幅（BOSS 登场特效）：全宽红底 + 大字闪烁
const WARNING_BG_COLOR := Color(0.7, 0.05, 0.05, 0.85)
const WARNING_TEXT_COLOR := Color(1.0, 0.95, 0.3, 1.0)
const WARNING_FLASH_COUNT := 3                   ## 闪烁次数（on-off 算一轮）
const WARNING_FLASH_ON_SEC := 0.35
const WARNING_FLASH_OFF_SEC := 0.15

var _bg: ColorRect
var _label: Label
var _persistent_visible: bool = false
var _persistent_text: String = ""
var _temp_timer: float = 0.0
var _pulse_t: float = 0.0
var _showing_temp: bool = false

## Warning 横幅独立节点，不占用 persistent/temp 槽
var _warn_bg: ColorRect
var _warn_label: Label
var _warn_timer: float = 0.0
var _warn_phase: int = 0            ## 剩余 on-off 半周期数（每轮闪烁 = 2）
var _warn_on: bool = false

func _ready() -> void:
	layer = 18
	_build()

func _build() -> void:
	_bg = ColorRect.new()
	_bg.anchor_left = 0.2
	_bg.anchor_right = 0.8
	_bg.offset_top = 70
	_bg.offset_bottom = 110
	_bg.color = BG_COLOR
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg.visible = false
	add_child(_bg)

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", COLOR_INFO)
	_bg.add_child(_label)

	# Warning 横幅：全宽、放在屏幕 1/3 高度处，比普通提示更大更醒目
	_warn_bg = ColorRect.new()
	_warn_bg.anchor_left = 0.0
	_warn_bg.anchor_right = 1.0
	_warn_bg.anchor_top = 0.32
	_warn_bg.anchor_bottom = 0.32
	_warn_bg.offset_top = -50
	_warn_bg.offset_bottom = 50
	_warn_bg.color = WARNING_BG_COLOR
	_warn_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_warn_bg.visible = false
	add_child(_warn_bg)

	_warn_label = Label.new()
	_warn_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_warn_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_warn_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_warn_label.add_theme_font_size_override("font_size", 56)
	_warn_label.add_theme_color_override("font_color", WARNING_TEXT_COLOR)
	_warn_label.add_theme_constant_override("outline_size", 6)
	_warn_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_warn_bg.add_child(_warn_label)

# ══════════════════════════════════════════════
#  Persistent（脉冲提示，直到 hide_persistent 调用）
# ══════════════════════════════════════════════

func show_persistent(msg: String) -> void:
	_persistent_visible = true
	_persistent_text = msg
	if not _showing_temp:
		_apply_persistent()

func hide_persistent() -> void:
	_persistent_visible = false
	if not _showing_temp:
		_bg.visible = false

func _apply_persistent() -> void:
	_bg.visible = true
	_label.text = _persistent_text
	_label.add_theme_color_override("font_color", COLOR_INFO)

# ══════════════════════════════════════════════
#  Temp（N 秒自动消失；期间覆盖 persistent）
# ══════════════════════════════════════════════

func show_temp(msg: String, duration: float = 3.5) -> void:
	_showing_temp = true
	_temp_timer = duration
	_bg.visible = true
	_label.text = msg
	_label.add_theme_color_override("font_color", COLOR_VICTORY)

func _process(delta: float) -> void:
	if _showing_temp:
		_temp_timer -= delta
		_pulse_t += delta * 5.0
		_label.modulate = Color(1, 1, 1, 0.85 + 0.15 * sin(_pulse_t))
		if _temp_timer <= 0.0:
			_showing_temp = false
			_label.modulate = Color(1, 1, 1, 1)
			if _persistent_visible:
				_apply_persistent()
			else:
				_bg.visible = false
		return
	# persistent 脉冲
	if _persistent_visible:
		_pulse_t += delta * 2.0
		var a := 0.7 + 0.3 * (sin(_pulse_t) * 0.5 + 0.5)
		_label.modulate = Color(1, 1, 1, a)

	# Warning 横幅：独立的闪烁状态机（on-off-on-off-...）
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

# ══════════════════════════════════════════════
#  Warning 横幅（BOSS 登场）：全宽红底大字，闪烁 N 次后消失
# ══════════════════════════════════════════════

func show_warning_banner(msg: String, flashes: int = WARNING_FLASH_COUNT) -> void:
	_warn_label.text = msg
	# 每轮闪烁 = on + off = 2 个 phase；最后以 on 结束时再追加一次 off 用于收尾
	_warn_phase = flashes * 2
	_warn_on = true
	_warn_bg.visible = true
	_warn_timer = WARNING_FLASH_ON_SEC
