class_name DamageVignette
extends Control

## 屏幕外圈反馈边框（生存模式 HUD）。
## 红 = 受伤 / 黄 = 异常状态（锁定/FEAR/JAM/SLOW）/ 绿 = HP 上升。
## 三色按 红>黄>绿 优先级单层渲染，不叠加。
## 厚度按短边 1.5% 缩放，停在 ThreatOverlay 箭头尖（18px）以外；
## add_child 顺序早于 ThreatOverlay，让箭头/文字盖在边框上。

const COLOR_HURT := Color(1.0, 0.15, 0.15)
const COLOR_WARN := Color(1.0, 0.85, 0.20)
const COLOR_HEAL := Color(0.25, 1.0, 0.40)

const ATTACK_RATE := 6.0       ## 进入 1.0 ~ 0.17s
const DECAY_RATE  := 2.5       ## 淡出 ~ 0.4s
const MAX_ALPHA   := 0.55
const HURT_HOLD   := 0.15      ## 受伤后这么久内仍视为"正在受伤"
const BAND_RATIO  := 0.015     ## 1080p ≈ 16px, 2160p ≈ 32px

var player_ref: Node = null    ## 由 SurvivorHUD 在 _process 中按需注入

var _hurt_alpha: float = 0.0
var _warn_alpha: float = 0.0
var _heal_alpha: float = 0.0
var _last_hp_seen: float = -1.0

var _draw_color: Color = Color(0, 0, 0, 0)
var _draw_thickness: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = -1   ## 同 CanvasLayer 内尽量靠下；add_child 顺序兜底


func _process(delta: float) -> void:
	var ac := player_ref
	var hurt_active := false
	var warn_active := false
	var heal_active := false

	if ac and is_instance_valid(ac) and not ac.get("is_destroyed"):
		var now := EventLogger.get_game_time()
		var last_dmg: float = ac.get_meta(&"hud_last_damage_at", -999.0)
		hurt_active = (now - last_dmg) < HURT_HOLD

		if bool(ac.get("is_locked")):
			warn_active = true
		var se: Dictionary = ac.get("status_effects")
		if se and (se.has("fear") or se.has("jam") or se.has("slow")):
			warn_active = true

		var cur_hp: float = ac.get("hp")
		if _last_hp_seen < 0.0:
			_last_hp_seen = cur_hp
		elif cur_hp > _last_hp_seen + 0.01:
			heal_active = true
		_last_hp_seen = cur_hp
	else:
		_last_hp_seen = -1.0

	_hurt_alpha = _advance(_hurt_alpha, hurt_active, delta)
	_warn_alpha = _advance(_warn_alpha, warn_active, delta)
	_heal_alpha = _advance(_heal_alpha, heal_active, delta)

	var color: Color
	var a: float
	if _hurt_alpha > 0.02:
		color = COLOR_HURT
		a = _hurt_alpha
	elif _warn_alpha > 0.02:
		color = COLOR_WARN
		a = _warn_alpha
	elif _heal_alpha > 0.02:
		color = COLOR_HEAL
		a = _heal_alpha
	else:
		color = Color(0, 0, 0, 0)
		a = 0.0

	color.a = a * MAX_ALPHA
	var thickness := minf(size.x, size.y) * BAND_RATIO

	if not _approx_color(color, _draw_color) or not is_equal_approx(thickness, _draw_thickness):
		_draw_color = color
		_draw_thickness = thickness
		queue_redraw()


func _advance(cur: float, active: bool, delta: float) -> float:
	var target := 1.0 if active else 0.0
	var rate := ATTACK_RATE if active else DECAY_RATE
	return move_toward(cur, target, rate * delta)


func _approx_color(a: Color, b: Color) -> bool:
	return is_equal_approx(a.r, b.r) and is_equal_approx(a.g, b.g) \
		and is_equal_approx(a.b, b.b) and is_equal_approx(a.a, b.a)


func _draw() -> void:
	if _draw_color.a <= 0.001 or _draw_thickness <= 0.5:
		return
	var w := size.x
	var h := size.y
	var t := _draw_thickness
	var c_out := _draw_color
	var c_in := Color(c_out.r, c_out.g, c_out.b, 0.0)

	## 四条梯形边带：外缘满 alpha，内缘 0。对角缝隙在屏幕四角，视觉上自然融合。
	_draw_band(Vector2(0, 0),     Vector2(w, 0),     Vector2(w - t, t),     Vector2(t, t),         c_out, c_in)  # top
	_draw_band(Vector2(w, 0),     Vector2(w, h),     Vector2(w - t, h - t), Vector2(w - t, t),     c_out, c_in)  # right
	_draw_band(Vector2(w, h),     Vector2(0, h),     Vector2(t, h - t),     Vector2(w - t, h - t), c_out, c_in)  # bottom
	_draw_band(Vector2(0, h),     Vector2(0, 0),     Vector2(t, t),         Vector2(t, h - t),     c_out, c_in)  # left


func _draw_band(out_a: Vector2, out_b: Vector2, in_b: Vector2, in_a: Vector2, c_out: Color, c_in: Color) -> void:
	var verts := PackedVector2Array([out_a, out_b, in_b, in_a])
	var cols := PackedColorArray([c_out, c_out, c_in, c_in])
	draw_polygon(verts, cols)
