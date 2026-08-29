class_name BrakeSteeringOverlay
extends Control

## 右键急刹的屏幕空间反馈。仅由输入/飞行状态变化驱动重绘，不做实体扫描。

const TerminalTextScript := preload("res://scripts/ui/terminal_text.gd")
const HudPreferencesScript := preload("res://scripts/ui/hud_preferences.gd")

const OUTER_RADIUS := 54.0
const KNOB_RADIUS := 12.0
const KNOB_TRAVEL := 40.0
const EDGE_MARGIN := Vector2(184.0, 104.0)
const LABEL_SIZE := Vector2(360.0, 22.0)
const FONT_SIZE := 13

var _active: bool = false
var _anchor_screen := Vector2.ZERO
var _steer_input: float = 0.0
var _stall_locked: bool = false
var _speed_kmh: int = -1
var _gun_range_m: int = 0
var _gun_ammo: int = 0
var _gun_max_ammo: int = 0
var _gun_ammo_infinite: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(_on_visibility_changed)


func begin(screen_pos: Vector2) -> void:
	_active = true
	_anchor_screen = screen_pos
	_steer_input = 0.0
	_stall_locked = false
	_speed_kmh = -1
	_gun_range_m = 0
	_gun_ammo = 0
	_gun_max_ammo = 0
	_gun_ammo_infinite = false
	visible = true
	queue_redraw()


func update_steer(_screen_pos: Vector2, steer_input: float) -> void:
	if not _active:
		return
	var next_input := clampf(steer_input, -1.0, 1.0)
	if is_equal_approx(next_input, _steer_input):
		return
	_steer_input = next_input
	queue_redraw()


func set_stall_locked(locked: bool) -> void:
	if not _active or _stall_locked == locked:
		return
	_stall_locked = locked
	queue_redraw()


func set_flight_data(speed_kmh: float, gun_range_m: float,
		gun_ammo: int, gun_max_ammo: int, gun_ammo_infinite: bool) -> void:
	if not _active:
		return
	var next_speed := maxi(0, roundi(speed_kmh))
	var next_gun_range := maxi(0, roundi(gun_range_m))
	var next_gun_ammo := maxi(0, gun_ammo)
	var next_gun_max_ammo := maxi(0, gun_max_ammo)
	if next_speed == _speed_kmh and next_gun_range == _gun_range_m \
			and next_gun_ammo == _gun_ammo and next_gun_max_ammo == _gun_max_ammo \
			and gun_ammo_infinite == _gun_ammo_infinite:
		return
	_speed_kmh = next_speed
	_gun_range_m = next_gun_range
	_gun_ammo = next_gun_ammo
	_gun_max_ammo = next_gun_max_ammo
	_gun_ammo_infinite = gun_ammo_infinite
	queue_redraw()


func end() -> void:
	if not _active and not visible:
		return
	_active = false
	_steer_input = 0.0
	_stall_locked = false
	_speed_kmh = -1
	_gun_range_m = 0
	_gun_ammo = 0
	_gun_max_ammo = 0
	_gun_ammo_infinite = false
	visible = false


static func display_center_for(anchor: Vector2, viewport_size: Vector2) -> Vector2:
	if viewport_size.x <= EDGE_MARGIN.x * 2.0 or viewport_size.y <= EDGE_MARGIN.y * 2.0:
		return viewport_size * 0.5
	return anchor.clamp(EDGE_MARGIN, viewport_size - EDGE_MARGIN)


static func knob_offset_for(steer_input: float) -> Vector2:
	return Vector2(clampf(steer_input, -1.0, 1.0) * KNOB_TRAVEL, 0.0)


func debug_snapshot() -> Dictionary:
	return {
		"active": _active,
		"anchor": _anchor_screen,
		"steer": _steer_input,
		"stall_locked": _stall_locked,
		"speed_kmh": _speed_kmh,
		"gun_range_m": _gun_range_m,
		"gun_ammo": _gun_ammo,
		"gun_max_ammo": _gun_max_ammo,
		"gun_ammo_infinite": _gun_ammo_infinite,
		"display_center": display_center_for(_anchor_screen, size),
		"knob_offset": knob_offset_for(_steer_input),
	}


func _draw() -> void:
	if not _active:
		return
	var center := display_center_for(_anchor_screen, size)
	var accent := ThemeColors.UI_DANGER_RED if _stall_locked \
		else HudPreferencesScript.hud_color()
	var muted := Color(accent, 0.34)
	var strong := Color(accent, 0.92)

	# 靠近屏幕边缘时夹紧摇杆，但以短线保留原始按下点的空间关系。
	if center.distance_squared_to(_anchor_screen) > 1.0:
		draw_line(_anchor_screen, center, Color(accent, 0.28), 1.0, true)

	# 黑底只包住提示文字；摇杆本体保持通透，不遮挡近距目标。
	var label_rect := Rect2(center - Vector2(LABEL_SIZE.x * 0.5, OUTER_RADIUS + 31.0), LABEL_SIZE)
	draw_rect(label_rect, ThemeColors.UI_BLOCK_BACKGROUND, true)
	draw_rect(label_rect, strong, false, 1.0)

	draw_arc(center, OUTER_RADIUS, 0.0, TAU, 48, muted, 1.5, true)
	draw_arc(center, OUTER_RADIUS - 5.0, -0.58, 0.58, 12, strong, 2.0, true)
	draw_arc(center, OUTER_RADIUS - 5.0, PI - 0.58, PI + 0.58, 12, strong, 2.0, true)
	draw_line(center - Vector2(KNOB_TRAVEL, 0.0), center + Vector2(KNOB_TRAVEL, 0.0), muted, 1.0, true)
	# 12/110 的实际输入死区直接映射为中心短刻度。
	var deadzone_visual := KNOB_TRAVEL * AircraftPhysics.BRAKE_STEER_DEADZONE_PX \
		/ AircraftPhysics.BRAKE_STEER_FULL_PX
	draw_line(center - Vector2(deadzone_visual, 5.0), center - Vector2(deadzone_visual, -5.0), muted, 1.0)
	draw_line(center + Vector2(deadzone_visual, 5.0), center + Vector2(deadzone_visual, -5.0), muted, 1.0)

	var effective_input := 0.0 if _stall_locked else _steer_input
	var knob_center := center + knob_offset_for(effective_input)
	draw_circle(knob_center, KNOB_RADIUS, Color(accent, 0.16))
	draw_arc(knob_center, KNOB_RADIUS, 0.0, TAU, 24, strong, 2.0, true)
	draw_circle(knob_center, 2.4, strong)

	var title := tr("HUD_BRAKE_STALL_LOCK") if _stall_locked else tr("HUD_BRAKE_ACTIVE")
	draw_string(TerminalTextScript.SILKSCREEN_FONT_SOURCE,
		label_rect.position + Vector2(8.0, 15.0), title,
		HORIZONTAL_ALIGNMENT_CENTER, LABEL_SIZE.x - 16.0, FONT_SIZE, strong)
	var hint := tr("HUD_BRAKE_STEER_HINT")
	if not _stall_locked and absf(_steer_input) > 0.001:
		hint = "%s  %02d%%" % [
			tr("HUD_BRAKE_STEER_RIGHT") if _steer_input > 0.0 else tr("HUD_BRAKE_STEER_LEFT"),
			roundi(absf(_steer_input) * 100.0),
		]
	draw_string(TerminalTextScript.SILKSCREEN_FONT_SOURCE,
		center + Vector2(-LABEL_SIZE.x * 0.5, OUTER_RADIUS + 21.0), hint,
		HORIZONTAL_ALIGNMENT_CENTER, LABEL_SIZE.x, FONT_SIZE - 2, strong)
	if _speed_kmh >= 0:
		var telemetry: String
		if _gun_range_m <= 0:
			telemetry = tr("HUD_BRAKE_TELEMETRY_NO_GUN_FMT") % _speed_kmh
		else:
			var ammo_text := "∞" if _gun_ammo_infinite \
				else "%d/%d" % [_gun_ammo, _gun_max_ammo]
			telemetry = tr("HUD_BRAKE_TELEMETRY_FMT") % [
				_speed_kmh, ammo_text, _gun_range_m]
		draw_string(TerminalTextScript.SILKSCREEN_FONT_SOURCE,
			center + Vector2(-LABEL_SIZE.x * 0.5, OUTER_RADIUS + 38.0), telemetry,
			HORIZONTAL_ALIGNMENT_CENTER, LABEL_SIZE.x, FONT_SIZE - 1, strong)


func _on_visibility_changed() -> void:
	# 外部 HUD 若整体隐藏本控件，恢复显示时不能带回已经结束的手势。
	if not visible and not _active:
		_stall_locked = false
