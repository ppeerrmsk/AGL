class_name HudPreferences
extends RefCounted

## 玩家仪表的轻量持久化偏好。静态服务，不新增 AutoLoad。

const CONFIG_PATH := "user://hud.cfg"
const SPEED_KT := "kt"
const SPEED_KMH := "kmh"
const DEFAULT_COLOR := Color("53d13a")
const PRESET_GREEN := Color("53d13a")
const PRESET_CYAN := Color("42d9e8")
const PRESET_AMBER := Color("f0b43c")
const PRESET_WHITE := Color("e8f2e8")

static var _loaded: bool = false
static var _speed_unit: String = SPEED_KT
static var _hud_color: Color = DEFAULT_COLOR


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	var saved_unit: String = str(cfg.get_value("hud", "speed_unit", SPEED_KT))
	_speed_unit = saved_unit if saved_unit in [SPEED_KT, SPEED_KMH] else SPEED_KT
	var saved_color: Variant = cfg.get_value("hud", "accent_color", DEFAULT_COLOR)
	if saved_color is Color:
		_hud_color = Color(saved_color, 1.0)


static func speed_unit() -> String:
	ensure_loaded()
	return _speed_unit


static func uses_knots() -> bool:
	return speed_unit() == SPEED_KT


static func cycle_speed_unit() -> String:
	ensure_loaded()
	_speed_unit = SPEED_KMH if _speed_unit == SPEED_KT else SPEED_KT
	_save()
	return _speed_unit


static func set_speed_unit(unit: String) -> void:
	ensure_loaded()
	if unit not in [SPEED_KT, SPEED_KMH]:
		return
	_speed_unit = unit
	_save()


static func hud_color() -> Color:
	ensure_loaded()
	return _hud_color


static func set_hud_color(color: Color) -> void:
	ensure_loaded()
	_hud_color = Color(color.r, color.g, color.b, 1.0)
	_save()


static func speed_value(kmh: float) -> int:
	return speed_value_for(kmh, speed_unit())


static func speed_value_for(kmh: float, unit: String) -> int:
	return roundi(kmh / 1.852) if unit == SPEED_KT else roundi(kmh)


static func reset_for_test() -> void:
	_loaded = false
	_speed_unit = SPEED_KT
	_hud_color = DEFAULT_COLOR


static func _save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("hud", "speed_unit", _speed_unit)
	cfg.set_value("hud", "accent_color", _hud_color)
	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		push_warning("HudPreferences: failed to save settings (%s)" % error_string(err))
