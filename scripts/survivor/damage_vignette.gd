class_name DamageVignette
extends Control

## 屏幕外圈反馈：红=受伤，黄=锁定/FEAR/JAM/SLOW，绿=治疗。
## 只保存玩家实例 ID；跨帧读取先从 Variant 验证有效性，再收窄为 Aircraft。

const COLOR_HURT := Color("ff2626")
const COLOR_WARN := Color("ffd933")
const COLOR_HEAL := Color("40ff66")

const ATTACK_RATE := 6.0
const DECAY_RATE := 2.5
const MAX_ALPHA := 0.55
const HURT_HOLD := 0.15
const BAND_RATIO := 0.015

var _player_instance_id: int = 0
var _hurt_alpha: float = 0.0
var _warn_alpha: float = 0.0
var _heal_alpha: float = 0.0
var _last_hp_seen: float = -1.0
var _draw_color := Color(0.0, 0.0, 0.0, 0.0)
var _draw_thickness: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = -1


func set_player(value: Variant) -> void:
	var aircraft := AircraftRenderer.safe_aircraft_ref(value)
	var next_id := aircraft.get_instance_id() if aircraft != null else 0
	if next_id == _player_instance_id:
		return
	_player_instance_id = next_id
	_last_hp_seen = aircraft.hp if aircraft != null else -1.0


func _live_player() -> Aircraft:
	if _player_instance_id == 0:
		return null
	var value: Variant = instance_from_id(_player_instance_id)
	var aircraft := AircraftRenderer.safe_aircraft_ref(value)
	if aircraft == null:
		_player_instance_id = 0
		_last_hp_seen = -1.0
	return aircraft


func _process(delta: float) -> void:
	var aircraft := _live_player()
	var hurt_active := false
	var warn_active := false
	var heal_active := false
	if aircraft != null and not aircraft.is_destroyed:
		var last_damage_at := float(aircraft.get_meta(
			AircraftRenderer.STATUS_DAMAGE_LAST_META, -999.0))
		hurt_active = EventLogger.get_game_time() - last_damage_at < HURT_HOLD
		warn_active = aircraft.is_locked or aircraft.status_fear_active \
			or aircraft.status_jam_active or aircraft.status_slow_active
		if _last_hp_seen < 0.0:
			_last_hp_seen = aircraft.hp
		elif aircraft.hp > _last_hp_seen + 0.01:
			heal_active = true
		_last_hp_seen = aircraft.hp
	else:
		_last_hp_seen = -1.0

	_hurt_alpha = advance_alpha(_hurt_alpha, hurt_active, delta)
	_warn_alpha = advance_alpha(_warn_alpha, warn_active, delta)
	_heal_alpha = advance_alpha(_heal_alpha, heal_active, delta)
	var next_color := feedback_color(_hurt_alpha, _warn_alpha, _heal_alpha)
	var next_thickness := band_thickness(size)
	if not _approx_color(next_color, _draw_color) \
			or not is_equal_approx(next_thickness, _draw_thickness):
		_draw_color = next_color
		_draw_thickness = next_thickness
		queue_redraw()


static func advance_alpha(current: float, active: bool, delta: float) -> float:
	return move_toward(current, 1.0 if active else 0.0,
		(ATTACK_RATE if active else DECAY_RATE) * delta)


static func feedback_color(hurt_alpha: float, warn_alpha: float,
		heal_alpha: float) -> Color:
	var color := Color(0.0, 0.0, 0.0, 0.0)
	var alpha := 0.0
	if hurt_alpha > 0.02:
		color = COLOR_HURT
		alpha = hurt_alpha
	elif warn_alpha > 0.02:
		color = COLOR_WARN
		alpha = warn_alpha
	elif heal_alpha > 0.02:
		color = COLOR_HEAL
		alpha = heal_alpha
	color.a = alpha * MAX_ALPHA
	return color


static func band_thickness(view_size: Vector2) -> float:
	return minf(view_size.x, view_size.y) * BAND_RATIO


static func _approx_color(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) \
		and is_equal_approx(a.b, b.b) and is_equal_approx(a.a, b.a)


func _draw() -> void:
	if _draw_color.a <= 0.001 or _draw_thickness <= 0.5:
		return
	var width := size.x
	var height := size.y
	var thickness := _draw_thickness
	var inner := Color(_draw_color.r, _draw_color.g, _draw_color.b, 0.0)
	_draw_band(Vector2.ZERO, Vector2(width, 0.0),
		Vector2(width - thickness, thickness), Vector2(thickness, thickness), inner)
	_draw_band(Vector2(width, 0.0), Vector2(width, height),
		Vector2(width - thickness, height - thickness), Vector2(width - thickness, thickness), inner)
	_draw_band(Vector2(width, height), Vector2(0.0, height),
		Vector2(thickness, height - thickness), Vector2(width - thickness, height - thickness), inner)
	_draw_band(Vector2(0.0, height), Vector2.ZERO,
		Vector2(thickness, thickness), Vector2(thickness, height - thickness), inner)


func _draw_band(outer_a: Vector2, outer_b: Vector2, inner_b: Vector2,
		inner_a: Vector2, inner_color: Color) -> void:
	draw_polygon(PackedVector2Array([outer_a, outer_b, inner_b, inner_a]),
		PackedColorArray([_draw_color, _draw_color, inner_color, inner_color]))
