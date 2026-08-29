class_name ExplosionPresenter
extends RefCounted

const TrianglePacket = preload("res://scripts/rendering/canvas_triangle_packet.gd")

const HIT_FLASH_DURATION: float = 0.30
const HIT_FLASH_BASE_SIZE: float = 22.0


static func draw(canvas: CanvasItem, aoe_zones: Array, hit_flashes: Array,
		world_origin: Vector2) -> void:
	_draw_aoe_zones(canvas, aoe_zones, world_origin)
	_draw_hit_flashes(canvas, hit_flashes, world_origin)


static func _draw_aoe_zones(canvas: CanvasItem, aoe_zones: Array,
		world_origin: Vector2) -> void:
	for zone in aoe_zones:
		var ratio: float = zone["time_left"] / zone["max_time"]
		var alpha := ratio * 0.35
		var pos: Vector2 = zone["pos"] - world_origin
		var radius: float = zone["radius_px"]
		canvas.draw_circle(pos, radius, Color(1.0, 0.15, 0.1, alpha * 0.4))
		canvas.draw_arc(pos, radius, 0.0, TAU, 48, Color(1.0, 0.2, 0.1, alpha), 2.0)


static func _draw_hit_flashes(canvas: CanvasItem, hit_flashes: Array,
		world_origin: Vector2) -> void:
	var fill_packet := TrianglePacket.create()
	var edge_points := PackedVector2Array()
	var edge_colors := PackedColorArray()
	for flash in hit_flashes:
		if float(flash.get("delay", 0.0)) > 0.0:
			continue
		var packet := hit_flash_draw_packet(flash, world_origin)
		var points: PackedVector2Array = packet["points"]
		var colors: PackedColorArray = packet["colors"]
		var fill_points: PackedVector2Array = fill_packet["points"]
		var fill_colors: PackedColorArray = fill_packet["colors"]
		fill_points.append_array(points)
		fill_colors.append_array(colors)
		edge_points.append_array(packet["edge_points"])
		edge_colors.append_array(packet["edge_colors"])
	fill_packet["indices"] = TrianglePacket.sequential_indices(
		(fill_packet["points"] as PackedVector2Array).size())
	TrianglePacket.submit(canvas.get_canvas_item(), fill_packet)
	if not edge_points.is_empty():
		canvas.draw_multiline_colors(edge_points, edge_colors, 1.6, true)


static func hit_flash_draw_packet(flash: Dictionary, world_origin: Vector2) -> Dictionary:
	var ratio := clampf(float(flash["time_left"]) / HIT_FLASH_DURATION, 0.0, 1.0)
	var age := 1.0 - ratio
	var intensity := 1.0 if age < 0.18 else ratio / 0.82
	var alpha := clampf(intensity, 0.0, 1.0)
	var pulse := 0.72 + 0.46 * sin(age * PI) + 0.08 * age
	var size := HIT_FLASH_BASE_SIZE * pulse * float(flash.get("scale", 1.0))
	var pos: Vector2 = flash["pos"] - world_origin
	var heading := float(flash["heading"]) \
		+ float(flash.get("turn_sign", 1.0)) * sin(age * PI) * 0.14
	return hit_flash_cube_packet(pos, heading, size, alpha)


static func hit_flash_cube_packet(pos: Vector2, heading: float, size: float,
		alpha: float) -> Dictionary:
	var forward := Vector2(sin(heading), -cos(heading))
	var right := Vector2(cos(heading), sin(heading))
	var half := maxf(size, 2.0) * 0.5
	var tilt := Vector2(0.0, -size * 0.55)
	var b_fr := pos + forward * half + right * half
	var b_fl := pos + forward * half - right * half
	var b_bl := pos - forward * half - right * half
	var b_br := pos - forward * half + right * half
	var t_fr := b_fr + tilt
	var t_fl := b_fl + tilt
	var t_bl := b_bl + tilt
	var t_br := b_br + tilt
	var top_color := Color(1.0, 1.0, 1.0, alpha * 0.85)
	var bright_side := Color(0.92, 0.95, 1.0, alpha * 0.65)
	var dim_side := Color(0.78, 0.82, 0.92, alpha * 0.5)
	var edge_color := Color(1.0, 1.0, 1.0, alpha)
	var faces: Array[Dictionary] = []
	if forward.y > 0.0:
		faces.append({"v": PackedVector2Array([b_fr, b_fl, t_fl, t_fr]),
			"c": bright_side if forward.y > 0.5 else dim_side, "y": (b_fr.y + b_fl.y) * 0.5})
	if forward.y < 0.0:
		faces.append({"v": PackedVector2Array([b_bl, b_br, t_br, t_bl]),
			"c": bright_side if forward.y < -0.5 else dim_side, "y": (b_bl.y + b_br.y) * 0.5})
	if right.y > 0.0:
		faces.append({"v": PackedVector2Array([b_br, b_fr, t_fr, t_br]),
			"c": bright_side if right.y > 0.5 else dim_side, "y": (b_br.y + b_fr.y) * 0.5})
	if right.y < 0.0:
		faces.append({"v": PackedVector2Array([b_fl, b_bl, t_bl, t_fl]),
			"c": bright_side if right.y < -0.5 else dim_side, "y": (b_fl.y + b_bl.y) * 0.5})
	faces.sort_custom(func(a, b): return a["y"] < b["y"])
	var fill := TrianglePacket.create()
	for face in faces:
		var vertices: PackedVector2Array = face["v"]
		var color: Color = face["c"]
		TrianglePacket.append_triangle(fill, vertices[0], vertices[1], vertices[2], color, 0.5)
		TrianglePacket.append_triangle(fill, vertices[0], vertices[2], vertices[3], color, 0.5)
	TrianglePacket.append_triangle(fill, t_fr, t_fl, t_bl, top_color)
	TrianglePacket.append_triangle(fill, t_fr, t_bl, t_br, top_color)

	var edge_points := PackedVector2Array()
	var edge_colors := PackedColorArray()
	var bottom_edge := Color(1.0, 1.0, 1.0, alpha * 0.55)
	for edge in [
		[t_fr, t_fl, edge_color], [t_fl, t_bl, edge_color],
		[t_bl, t_br, edge_color], [t_br, t_fr, edge_color],
		[b_fr, b_fl, bottom_edge], [b_fl, b_bl, bottom_edge],
		[b_bl, b_br, bottom_edge], [b_br, b_fr, bottom_edge],
		[b_fr, t_fr, edge_color], [b_fl, t_fl, edge_color],
		[b_bl, t_bl, edge_color], [b_br, t_br, edge_color],
	]:
		edge_points.append(edge[0])
		edge_points.append(edge[1])
		edge_colors.append(edge[2])
	return {
		"points": fill["points"],
		"colors": fill["colors"],
		"edge_points": edge_points,
		"edge_colors": edge_colors,
	}
