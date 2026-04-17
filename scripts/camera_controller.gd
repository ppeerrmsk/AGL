class_name CameraController
extends Node

## 共享相机操控：缩放/平移/hover/坐标转换
## 沙盒和生存模式共用核心操控逻辑。
## 用法：
##   var cam_ctrl := CameraController.new()
##   add_child(cam_ctrl)
##   cam_ctrl.setup(camera)
##   cam_ctrl.set_world_bounds(Rect2(...))  # 可选：开启相机位置钳制

const ZOOM_MIN := 0.55      ## 最大缩小倍率（越小视野越大；0.55 ≈ 可视宽度 3500 px / 7 km）
const ZOOM_MAX := 5.0
const ZOOM_STEP := 0.1
const HOVER_RADIUS := 30.0  ## 鼠标悬停判定半径（像素）

var camera: Camera2D
var target_zoom: float = 1.0

## 当前悬停的战斗单位（由父场景通过 update_hover 更新）
var hovered_unit: CombatUnit = null

## 相机位置钳制矩形（世界坐标）。size 为 0 表示不启用（沙盒默认）。
## 开启后相机不会被拖拽/缩放到该矩形外，配合视口半宽保证画面始终落在矩形内。
var _world_bounds: Rect2 = Rect2()

func setup(p_camera: Camera2D) -> void:
	camera = p_camera
	target_zoom = camera.zoom.x

## 启用相机位置钳制（传入世界矩形；生存模式传 MapBoundary.get_world_rect()）
func set_world_bounds(rect: Rect2) -> void:
	_world_bounds = rect

## 每帧调用：平滑缩放 + 位置钳制
func update_zoom(delta: float) -> void:
	var current_zoom := camera.zoom.x
	var new_zoom := lerpf(current_zoom, target_zoom, delta * 10.0)
	camera.zoom = Vector2(new_zoom, new_zoom)
	_clamp_camera_position()

## 滚轮缩放输入
func handle_zoom_input(factor: float) -> void:
	target_zoom = clampf(target_zoom * factor, ZOOM_MIN, ZOOM_MAX)

## 屏幕坐标 → 世界坐标
func screen_to_world(screen_pos: Vector2) -> Vector2:
	var viewport := camera.get_viewport()
	var canvas_transform := viewport.get_canvas_transform()
	return canvas_transform.affine_inverse() * screen_pos

## 鼠标拖拽平移相机
func handle_drag(relative: Vector2) -> void:
	camera.global_position -= relative / camera.zoom
	_clamp_camera_position()

## 把相机位置钳制到 _world_bounds 内，保留视口半宽余量，使画面不越界
func _clamp_camera_position() -> void:
	if _world_bounds.size.x <= 0.0 or not camera:
		return
	var vp_size := camera.get_viewport().get_visible_rect().size
	var half := vp_size / (2.0 * camera.zoom.x)
	var min_pos := _world_bounds.position + half
	var max_pos := _world_bounds.end - half
	# 如果视口比地图还大（理论上极低 zoom 才会），退化为居中
	if min_pos.x > max_pos.x:
		var cx := (_world_bounds.position.x + _world_bounds.end.x) * 0.5
		min_pos.x = cx
		max_pos.x = cx
	if min_pos.y > max_pos.y:
		var cy := (_world_bounds.position.y + _world_bounds.end.y) * 0.5
		min_pos.y = cy
		max_pos.y = cy
	camera.global_position = camera.global_position.clamp(min_pos, max_pos)

## 世界坐标是否出现在当前相机视野内（含 margin_px 缓冲）
## 用于"不在玩家画面内刷敌"的铁则
func is_world_pos_visible(world_pos: Vector2, margin_px: float = 200.0) -> bool:
	if not camera:
		return false
	var vp_size := camera.get_viewport().get_visible_rect().size
	var half := vp_size / (2.0 * camera.zoom.x) + Vector2(margin_px, margin_px)
	var rel := world_pos - camera.global_position
	return absf(rel.x) <= half.x and absf(rel.y) <= half.y

## hover 检测：遍历单位列表，标记距离最近的单位
func update_hover(screen_pos: Vector2, units: Array) -> CombatUnit:
	var world_pos := screen_to_world(screen_pos)
	# 清除旧悬停
	if hovered_unit and is_instance_valid(hovered_unit):
		hovered_unit.is_hovered = false
	hovered_unit = null

	var best_dist := HOVER_RADIUS
	for child in units:
		if child is CombatUnit:
			var d := world_pos.distance_to(child.global_position)
			if d < best_dist:
				best_dist = d
				hovered_unit = child

	if hovered_unit:
		hovered_unit.is_hovered = true
	return hovered_unit
