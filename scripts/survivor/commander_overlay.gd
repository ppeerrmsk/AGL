class_name CommanderOverlay
extends Node2D

## 指挥 UAV 视觉效果：影响范围圈 + 数据链连接线

var _commander: Aircraft = null
var _aura: CommanderAura = null

# ── 颜色方案 ──
const FILL_COLOR := Color(0.3, 0.8, 0.9, 0.06)    ## 范围填充（极淡青色）
const RING_COLOR := Color(0.3, 0.8, 0.9, 0.2)      ## 范围边缘
const LINK_COLOR := Color(0.3, 0.8, 0.9, 0.35)     ## 数据链线
const DIAMOND_COLOR := Color(0.3, 0.8, 0.9, 0.5)   ## 端点菱形

func _ready() -> void:
	_commander = get_parent() as Aircraft
	_aura = _commander.get_node_or_null("CommanderAura") as CommanderAura

func _process(_delta: float) -> void:
	if _commander and not _commander.is_destroyed:
		queue_redraw()

func _draw() -> void:
	if not _commander or _commander.is_destroyed:
		return

	# ── 影响范围圈 ──
	draw_circle(Vector2.ZERO, CommanderAura.AURA_RADIUS, FILL_COLOR)
	draw_arc(Vector2.ZERO, CommanderAura.AURA_RADIUS, 0, TAU, 64, RING_COLOR, 1.0)

	# ── 数据链连接线 ──
	if not _aura:
		return
	for ac in _aura.buffed_aircraft:
		if not is_instance_valid(ac) or ac.is_destroyed:
			continue
		var local_pos := to_local(ac.global_position)
		# 虚线效果：交替绘制短线段
		var dist := local_pos.length()
		if dist < 1.0:
			continue
		var dir := local_pos / dist
		var seg_len := 12.0
		var gap_len := 8.0
		var drawn := 0.0
		var is_seg := true
		while drawn < dist:
			var step := seg_len if is_seg else gap_len
			step = minf(step, dist - drawn)
			if is_seg:
				var from := dir * drawn
				var to := dir * (drawn + step)
				draw_line(from, to, LINK_COLOR, 1.0, true)
			drawn += step
			is_seg = not is_seg

		# 端点菱形
		var d := 4.0
		var diamond := PackedVector2Array([
			local_pos + Vector2(0, -d),
			local_pos + Vector2(d, 0),
			local_pos + Vector2(0, d),
			local_pos + Vector2(-d, 0),
		])
		draw_colored_polygon(diamond, DIAMOND_COLOR)
