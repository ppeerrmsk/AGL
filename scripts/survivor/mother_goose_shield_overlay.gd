## Mother Goose 干扰场视觉层 —— 顶层节点
##
## 为什么独立出来：boss 飞机在屏外时其子节点的 _draw 可能不被绘制，但干扰场 AOE
## 是会影响玩家的 gameplay 元素（减速 + jam），无论 boss 是否在画面内都必须可见。
## 因此 shield 的视觉**脱离 boss 的 transform 层级**，作为 scene_root 的直接子节点存在，
## 每帧把 global_position 同步到 boss.global_position 即可。
##
## 状态机本身（MotherGooseJamShield）住在 MotherGooseController；本节点仅做绘制。

class_name MotherGooseShieldOverlay
extends Node2D

var boss_unit: Aircraft = null
var jam_shield: MotherGooseJamShield = null
var _last_visible: bool = false


func _ready() -> void:
	z_index = -5  ## 圈画在飞机/UAV 图标下面，不挡视觉
	z_as_relative = false


func _process(_delta: float) -> void:
	if boss_unit == null or not is_instance_valid(boss_unit) or boss_unit.is_destroyed:
		# boss 没了 → 自毁
		queue_free()
		return
	# 同步位置到 boss（每帧）—— 即便 boss 在屏外，本节点位置仍正确
	global_position = boss_unit.global_position
	# 仅在 shield 可见 / 上一帧可见但本帧不可见 时 redraw（事件驱动，省 CPU）
	var vis: bool = jam_shield != null and jam_shield.is_visible()
	if vis or _last_visible:
		_last_visible = vis
		queue_redraw()


func _draw() -> void:
	if jam_shield == null or not jam_shield.is_visible():
		return
	MotherGooseJamShield.draw_into(self, jam_shield)
