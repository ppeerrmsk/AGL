class_name SupportRangeOverlay
extends Node2D

## 随宿主移动的静态支援范围层：几何只构建一次，父节点 transform 会自动带着画布移动。

## 不依赖 AircraftRenderer 的新增静态成员：Godot 编辑器热重载时可能先解析本脚本，
## 此时全局类缓存仍是旧版 AircraftRenderer，会误报成员不存在。
const RANGE_FILL_ALPHA: float = 0.07
const RANGE_RING_ALPHA: float = 0.42
const RANGE_RING_WIDTH: float = 2.0
const RANGE_SEGMENTS: int = 96

var radius_px: float = 0.0
var team_id: int = CombatUnit.TEAM_ALLY


func setup(value_px: float, value_team: int) -> void:
	radius_px = maxf(value_px, 0.0)
	team_id = value_team
	if is_inside_tree():
		queue_redraw()


func _ready() -> void:
	show_behind_parent = true
	queue_redraw()


func _draw() -> void:
	if radius_px <= 0.0:
		return
	draw_circle(Vector2.ZERO, radius_px,
		GameConstants.team_radar_color(team_id, RANGE_FILL_ALPHA))
	draw_arc(Vector2.ZERO, radius_px, 0.0, TAU, RANGE_SEGMENTS,
		GameConstants.team_radar_color(team_id, RANGE_RING_ALPHA),
		RANGE_RING_WIDTH, true)
