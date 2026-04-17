class_name ZoneArrow
extends CanvasLayer

## 屏外战区指示箭头
##
## 当 ZoneData.selected_id 非空 + 选中战区**不在屏幕内**时，
## 在屏幕边缘（16 px 内缩）绘制绿色箭头指向战区方向 + 距离文字。

const COLOR := Color(0.35, 1.0, 0.45, 0.9)
const COLOR_DIM := Color(0.35, 1.0, 0.45, 0.45)
const EDGE_MARGIN := 40.0       ## 箭头距屏幕边缘
const ARROW_SIZE := 22.0
const LABEL_OFFSET := 28.0

var _player: Aircraft
var _camera: Camera2D
var _zones: ZoneData
var _draw_node: Control

func _ready() -> void:
	layer = 8  # 在一般 HUD 之下，但在战斗画面之上
	_build()

func setup(player: Aircraft, camera: Camera2D, zones: ZoneData) -> void:
	_player = player
	_camera = camera
	_zones = zones

func _build() -> void:
	_draw_node = Control.new()
	_draw_node.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_draw_node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_draw_node.draw.connect(_on_draw)
	add_child(_draw_node)

func _process(_delta: float) -> void:
	_draw_node.queue_redraw()

func _on_draw() -> void:
	if not _zones or _zones.selected_id == &"" or not _camera or not _player:
		return
	var zone := _zones.get_zone_by_id(_zones.selected_id)
	if zone.is_empty():
		return
	var target_world: Vector2 = zone["center"]
	var vp := get_viewport().get_visible_rect().size
	var cam_pos := _camera.global_position
	var zoom := _camera.zoom

	# 世界坐标 → 屏幕坐标（相机为中心）
	var screen_pos := (target_world - cam_pos) * zoom + vp * 0.5

	# 在屏幕内就不画箭头（用 64 px 边界宽松判断，避免抖动）
	var inside_margin := 64.0
	var rect := Rect2(Vector2(inside_margin, inside_margin), vp - Vector2(inside_margin * 2, inside_margin * 2))
	if rect.has_point(screen_pos):
		return

	# 求方向（从屏幕中心指向目标）
	var center := vp * 0.5
	var dir := (screen_pos - center)
	if dir.length_squared() < 1.0:
		return
	dir = dir.normalized()

	# 把箭头位置放到屏幕内缩边缘
	var box := Rect2(Vector2(EDGE_MARGIN, EDGE_MARGIN), vp - Vector2(EDGE_MARGIN * 2, EDGE_MARGIN * 2))
	var pos := _clip_ray_to_rect(center, dir, box)

	# 画三角箭头指向 dir
	var tip := pos + dir * ARROW_SIZE * 0.5
	var left := pos - dir * ARROW_SIZE * 0.5 + Vector2(-dir.y, dir.x) * ARROW_SIZE * 0.4
	var right := pos - dir * ARROW_SIZE * 0.5 + Vector2(dir.y, -dir.x) * ARROW_SIZE * 0.4
	var pts := PackedVector2Array([tip, left, right])
	_draw_node.draw_colored_polygon(pts, COLOR)
	_draw_node.draw_polyline(PackedVector2Array([tip, left, right, tip]), COLOR, 2.0, true)

	# 距离标签（km）
	var dist_m := _player.global_position.distance_to(target_world) / GameConstants.PIXELS_PER_METER
	var label: String = "%s — %.1f km" % [zone["label"], dist_m / 1000.0]
	# 把文字画在箭头偏内侧
	var text_pos := pos - dir * (LABEL_OFFSET + 30.0)
	_draw_node.draw_string(
		ThemeDB.fallback_font, text_pos,
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, COLOR
	)

## 从屏幕中心沿 dir 方向射线 → 求与 rect 边界的交点，确保箭头始终落在边缘
func _clip_ray_to_rect(origin: Vector2, dir: Vector2, rect: Rect2) -> Vector2:
	var tx := INF
	var ty := INF
	if dir.x > 0.001:
		tx = (rect.end.x - origin.x) / dir.x
	elif dir.x < -0.001:
		tx = (rect.position.x - origin.x) / dir.x
	if dir.y > 0.001:
		ty = (rect.end.y - origin.y) / dir.y
	elif dir.y < -0.001:
		ty = (rect.position.y - origin.y) / dir.y
	var t := minf(tx, ty)
	return origin + dir * t
