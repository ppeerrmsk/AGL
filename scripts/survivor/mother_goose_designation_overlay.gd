## Mother Goose 指定猎杀视觉层 —— 顶层节点
##
## 与 MotherGooseShieldOverlay 同思路：脱离 boss transform，挂在 _scene_root 下，
## 这样 boss 在屏外时 tether 仍能正确绘制（玩家始终知道自己被锁定）。
##
## 状态机本身（MotherGooseDesignation）住在 MotherGooseController；本节点仅做绘制。
## 绘制：从 boss 当前世界坐标 → 玩家世界坐标 一条红线；玩家端画"目标"圆环。
##   - WARNING 阶段：细线 + 暗红（预警 3s）
##   - ACTIVE 阶段：粗线 + 鲜红 + 玩家端圆环脉动（视觉冲击）

class_name MotherGooseDesignationOverlay
extends Node2D

var boss_unit: Aircraft = null
var player_ref: Aircraft = null
var designation: MotherGooseDesignation = null
var _last_drawing: bool = false


func _ready() -> void:
	z_index = -4  ## 比 shield_overlay 略上层，但仍在飞机图标之下
	z_as_relative = false


func _process(_delta: float) -> void:
	if boss_unit == null or not is_instance_valid(boss_unit) or boss_unit.is_destroyed:
		queue_free()
		return
	# tether 起点跟随 boss
	global_position = Vector2.ZERO   ## 我们在 _draw 用世界坐标直接画线，不需要 local transform
	var drawing: bool = designation != null and designation.is_drawing()
	if drawing or _last_drawing:
		_last_drawing = drawing
		queue_redraw()


func _draw() -> void:
	if designation == null or not designation.is_drawing():
		return
	if boss_unit == null or not is_instance_valid(boss_unit) or boss_unit.is_destroyed:
		return
	if player_ref == null or not is_instance_valid(player_ref) or player_ref.is_destroyed:
		return
	var a: Vector2 = boss_unit.global_position
	var b: Vector2 = player_ref.global_position
	var col: Color
	var w: float
	var ring_r: float
	if designation.is_warning():
		col = Color(1.0, 0.25, 0.25, 0.55)
		w = 2.0
		ring_r = 50.0
	else:
		col = Color(1.0, 0.10, 0.10, 0.85)
		w = 3.5
		ring_r = 65.0
	draw_line(a, b, col, w, true)
	## 玩家端"目标锁定"圆环
	draw_arc(b, ring_r, 0.0, TAU, 32, col, 2.0, true)
	## boss 端起点小标记
	var src_col := col
	src_col.a *= 0.85
	draw_arc(a, 18.0, 0.0, TAU, 16, src_col, 1.5, true)
