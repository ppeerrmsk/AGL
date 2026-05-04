class_name AOEPulseVFX
extends Node2D

## §1.3 表现层：AOE 状态广播触发的瞬时视觉脉冲
##
## 设计：
##   - 紫色圆环勾勒生效范围（线条，不填充——避免遮挡战场）
##   - 命中目标位置画一个小爆裂圈
##   - 1.2s 内 alpha 从 1 → 0 线性淡出，圆环略微外扩
##   - 单次 spawn，倒计时归零自动 queue_free
##
## 性能：每次 AOE 触发一个节点，1.2s 后释放。低频事件（击杀 / flare / 受击），
## 单帧只画一次（无 _process per frame 扫描）。
##
## 使用：
##   AOEPulseVFX.spawn(scene_root, center_world, radius_px, hit_world_positions, color?)

const DEFAULT_DURATION: float = 1.2
const RING_LINE_WIDTH: float = 2.0
const HIT_BURST_BASE_RADIUS_PX: float = 28.0
const RING_EXPAND_RATIO: float = 0.12   ## 1.2s 内圆环额外外扩 12%
const FILL_PEAK_ALPHA: float = 0.06     ## 圆内填充非常淡（不挡视线）
const RING_PEAK_ALPHA: float = 0.85
const HIT_PEAK_ALPHA: float = 0.95

# 配色（可由 spawn 参数覆盖）
const COLOR_FEAR := Color(0.78, 0.30, 1.00)        ## 紫色 — 默认（恐惧 / 玩家施法）
const COLOR_JAM := Color(0.40, 1.00, 0.55)         ## 干扰绿
const COLOR_INVUL := Color(1.00, 0.85, 0.30)       ## 金色

var center_world: Vector2
var radius_px: float
var color: Color
var hit_positions: Array = []          ## 命中目标的世界坐标列表（小爆裂用）
var time_left: float = DEFAULT_DURATION
var max_time: float = DEFAULT_DURATION


## 工厂：在 scene_root 下挂一个 VFX 节点；倒计时归零自动释放
##   center: 圆环中心（世界坐标）
##   radius_px: 半径像素
##   hits: 命中目标世界坐标数组
##   col: 圆环颜色（默认紫）
##   duration: 持续秒数（默认 1.2s）
static func spawn(scene_root: Node, center: Vector2, radius_px_in: float,
		hits: Array = [], col: Color = COLOR_FEAR,
		duration: float = DEFAULT_DURATION) -> void:
	if scene_root == null or not is_instance_valid(scene_root):
		return
	if radius_px_in <= 0.0:
		return
	var vfx := AOEPulseVFX.new()
	vfx.center_world = center
	vfx.radius_px = radius_px_in
	vfx.color = col
	vfx.hit_positions = hits.duplicate()
	vfx.max_time = duration
	vfx.time_left = duration
	# 节点挂到 scene_root 下，但 _draw 用世界坐标（global_position 设为 center 简化）
	vfx.global_position = center
	# z_index：略高于地形/单位但不挡 HUD（HUD 在 CanvasLayer，自然在上层）
	vfx.z_index = 5
	scene_root.add_child(vfx)


func _process(delta: float) -> void:
	time_left -= delta
	if time_left <= 0.0:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var t: float = clampf(time_left / max_time, 0.0, 1.0)  # 1→0
	# 圆环略微外扩 + 淡出
	var expand: float = 1.0 + (1.0 - t) * RING_EXPAND_RATIO
	var current_r: float = radius_px * expand

	# 内层很淡的填充（让玩家立刻看见范围"亮了一下"）
	var fill_alpha: float = FILL_PEAK_ALPHA * t
	if fill_alpha > 0.001:
		draw_circle(Vector2.ZERO, current_r, Color(color.r, color.g, color.b, fill_alpha))

	# 主圆环
	var ring_alpha: float = RING_PEAK_ALPHA * t
	if ring_alpha > 0.001:
		draw_arc(Vector2.ZERO, current_r, 0.0, TAU, 64,
			Color(color.r, color.g, color.b, ring_alpha), RING_LINE_WIDTH, true)

	# 命中目标小爆裂：用本地坐标（global_position 已等于 center_world，所以减 center 转本地）
	if hit_positions.is_empty():
		return
	var burst_r: float = HIT_BURST_BASE_RADIUS_PX * (1.0 - (1.0 - t) * 0.4)  # 略缩
	var hit_alpha: float = HIT_PEAK_ALPHA * t
	if hit_alpha < 0.001:
		return
	for hp_v in hit_positions:
		var hp: Vector2 = hp_v
		var local: Vector2 = hp - center_world
		# 小圆环（不是实心，避免遮挡飞机图标）
		draw_arc(local, burst_r, 0.0, TAU, 20,
			Color(color.r, color.g, color.b, hit_alpha), 1.5, true)
		# 中心点提示
		draw_circle(local, 2.5,
			Color(color.r, color.g, color.b, hit_alpha))
