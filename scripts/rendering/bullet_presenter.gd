class_name BulletPresenter
extends RefCounted

## BulletManager 的纯表现模块；只读取当帧值数据并向宿主 CanvasItem 提交绘制命令。
## 弹丸移动、命中、回收、节流与数组所有权仍全部留在 BulletManager。

const TRACER_LENGTH: float = 8.0
const ROCKET_TRAIL_LENGTH: float = 16.0
const FADE_OUT_DURATION: float = 0.25
const HIT_SPARK_DURATION: float = 0.16


static func draw(canvas: CanvasItem, bombs: Array[Dictionary], airburst_shells: Array[Dictionary],
		area_flashes: Array[Dictionary], bullets: Array[Dictionary],
		visual_positions: PackedVector2Array, visual_velocities: PackedVector2Array,
		hit_sparks: Array[Dictionary], torpedoes: Array[Dictionary]) -> void:
	_draw_special_projectiles(canvas, bombs, airburst_shells)
	_draw_area_flashes(canvas, area_flashes)
	_draw_bullet_streams(canvas, bullets, visual_positions, visual_velocities)
	_draw_hit_sparks(canvas, hit_sparks)
	_draw_torpedoes(canvas, torpedoes)


static func _draw_special_projectiles(canvas: CanvasItem, bombs: Array[Dictionary],
		airburst_shells: Array[Dictionary]) -> void:
	for bomb in bombs:
		var progress: float = 1.0 - float(bomb["life"]) / maxf(float(bomb["max_life"]), 0.01)
		canvas.draw_circle(bomb["pos"], lerpf(2.0, 4.5, progress), Color(0.95, 0.72, 0.28, 0.95))
		canvas.draw_line(bomb["pos"], bomb["pos"] - Vector2(bomb["vel"]).normalized() * 10.0,
			Color(0.35, 0.25, 0.15, 0.7), 2.0)
	for shell in airburst_shells:
		var direction: Vector2 = Vector2(shell["vel"]).normalized()
		canvas.draw_line(shell["pos"], shell["pos"] - direction * 12.0,
			Color(0.78, 0.9, 1.0, 0.9), 1.8)


static func _draw_area_flashes(canvas: CanvasItem, area_flashes: Array[Dictionary]) -> void:
	for flash in area_flashes:
		var t: float = clampf(float(flash["age"]) / maxf(float(flash["duration"]), 0.01), 0.0, 1.0)
		var pos: Vector2 = flash["pos"]
		if flash["kind"] == "bomb":
			var radius: float = float(flash["radius"]) * ease(t, -1.5)
			var color := Color(1.0, 0.58, 0.18, (1.0 - t) * 0.75)
			canvas.draw_arc(pos, maxf(radius, 2.0), 0, TAU, 36, color, 2.0)
			canvas.draw_arc(pos, maxf(radius * 0.65, 1.0), 0, TAU, 28, color, 1.0)
			continue
		_draw_flak_flash(canvas, flash, pos, t)


static func _draw_flak_flash(canvas: CanvasItem, flash: Dictionary, pos: Vector2, t: float) -> void:
	var visual_seed: int = int(flash.get("visual_seed", 0))
	var base_angle := fposmod(float(visual_seed) * 2.399963, TAU)
	var blast_t := clampf(t / 0.22, 0.0, 1.0)
	if t < 0.22:
		var danger_segments := PackedVector2Array()
		var danger_radius: float = float(flash["radius"])
		for segment in range(24):
			if segment % 4 == 3:
				continue
			var a0 := float(segment) / 24.0 * TAU
			var a1 := float(segment + 1) / 24.0 * TAU
			danger_segments.push_back(pos + Vector2.from_angle(a0) * danger_radius)
			danger_segments.push_back(pos + Vector2.from_angle(a1) * danger_radius)
		canvas.draw_multiline(danger_segments, Color(1.0, 0.42, 0.12, (1.0 - blast_t) * 0.7), 1.2, true)

		var blast_rays := PackedVector2Array()
		for ray in range(10):
			var angle := base_angle + float(ray) / 10.0 * TAU \
				+ sin(float(ray * 17 + visual_seed)) * 0.09
			var direction := Vector2.from_angle(angle)
			var length := lerpf(7.0, 34.0 + float(ray % 3) * 3.0, ease(blast_t, -1.6))
			blast_rays.push_back(pos + direction * 3.0)
			blast_rays.push_back(pos + direction * length)
		canvas.draw_multiline(blast_rays, Color(1.0, 0.55, 0.16, (1.0 - blast_t) * 0.95), 2.0, true)
		canvas.draw_circle(pos, lerpf(8.0, 2.0, blast_t),
			Color(1.0, 0.96, 0.72, (1.0 - blast_t) * 0.95))

	var smoke_in := clampf((t - 0.04) / 0.16, 0.0, 1.0)
	var smoke_alpha := smoke_in * (1.0 - t) * 0.72
	var smoke_spread := lerpf(7.0, 20.0, t)
	for puff in range(7):
		var angle := base_angle + float(puff) / 7.0 * TAU \
			+ sin(float(puff * 23 + visual_seed)) * 0.22
		var distance := smoke_spread * (0.45 + 0.08 * float(puff % 4))
		var puff_pos := pos + Vector2.from_angle(angle) * distance
		var puff_radius := (7.0 + float((puff * 5 + absi(visual_seed)) % 6)) * lerpf(0.75, 1.35, t)
		canvas.draw_circle(puff_pos, puff_radius, Color(0.28, 0.31, 0.34, smoke_alpha))
	canvas.draw_circle(pos, lerpf(8.0, 14.0, t), Color(0.12, 0.14, 0.16, smoke_alpha * 0.9))


static func _draw_bullet_streams(canvas: CanvasItem, bullets: Array[Dictionary],
		visual_positions: PackedVector2Array, visual_velocities: PackedVector2Array) -> void:
	var tracer_points := PackedVector2Array()
	for bullet in bullets:
		var direction: Vector2 = bullet["vel"].normalized()
		if bullet.get("is_rocket", false):
			var fade := clampf(float(bullet["life"]) / FADE_OUT_DURATION, 0.0, 1.0)
			var tail: Vector2 = bullet["pos"] - direction * ROCKET_TRAIL_LENGTH
			canvas.draw_line(bullet["pos"], tail, Color(1.0, 0.45, 0.15, 0.85 * fade), 2.2, true)
			canvas.draw_circle(bullet["pos"], 2.0, Color(1.0, 0.95, 0.8, fade))
		else:
			tracer_points.push_back(bullet["pos"])
			tracer_points.push_back(bullet["pos"] - direction * TRACER_LENGTH)
	for index in range(visual_positions.size()):
		var direction: Vector2 = visual_velocities[index].normalized()
		tracer_points.push_back(visual_positions[index])
		tracer_points.push_back(visual_positions[index] - direction * TRACER_LENGTH)
	if not tracer_points.is_empty():
		canvas.draw_multiline(tracer_points, Color(1.0, 0.95, 0.4, 0.9), 1.5)


static func _draw_hit_sparks(canvas: CanvasItem, hit_sparks: Array[Dictionary]) -> void:
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	for spark in hit_sparks:
		var life_ratio := clampf(1.0 - float(spark["age"]) / HIT_SPARK_DURATION, 0.0, 1.0)
		var reach: float = float(spark["scale"]) * life_ratio
		var origin: Vector2 = spark["pos"]
		var base_angle: float = float(spark["angle"])
		for ray in range(3):
			var direction := Vector2.from_angle(base_angle + (float(ray) - 1.0) * 0.68)
			outer.push_back(origin + direction * 1.2)
			outer.push_back(origin + direction * reach)
			inner.push_back(origin + direction * 1.2)
			inner.push_back(origin + direction * reach * 0.55)
	if not outer.is_empty():
		canvas.draw_multiline(outer, Color(1.0, 0.42, 0.08, 0.9), 2.0, true)
		canvas.draw_multiline(inner, Color(1.0, 0.96, 0.65, 1.0), 1.0, true)


static func _draw_torpedoes(canvas: CanvasItem, torpedoes: Array[Dictionary]) -> void:
	for torpedo in torpedoes:
		var pos: Vector2 = torpedo["pos"]
		var params: TorpedoParams = torpedo["params"]
		var canopy_color: Color = params.canopy_color
		var body_color: Color = params.body_color
		var pulse := 0.45 + 0.55 * absf(sin(Time.get_ticks_msec() * 0.009))
		body_color = body_color.lerp(Color(0.55, 0.9, 1.0, body_color.a), pulse)
		var fade := clampf(float(torpedo["life"]) / 0.6, 0.0, 1.0)
		canvas.draw_circle(pos, 3.0 + pulse,
			Color(body_color.r, body_color.g, body_color.b, body_color.a * fade))
		var canopy_center := pos + Vector2(0, -8.0)
		var canopy_points := PackedVector2Array([
			canopy_center + Vector2(-5, 1), canopy_center + Vector2(-3, -2),
			canopy_center + Vector2(0, -3), canopy_center + Vector2(3, -2),
			canopy_center + Vector2(5, 1),
		])
		canvas.draw_polyline(canopy_points,
			Color(canopy_color.r, canopy_color.g, canopy_color.b, canopy_color.a * fade), 1.5, true)
		var line_color := Color(canopy_color.r, canopy_color.g, canopy_color.b, 0.5 * fade)
		canvas.draw_line(canopy_points[0], pos, line_color, 1.0, true)
		canvas.draw_line(canopy_points[4], pos, line_color, 1.0, true)
