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

const DESTROY_FADE_DURATION := 3.0  ## 与 Aircraft._destroy_timer 初值一致

func _ready() -> void:
	_commander = get_parent() as Aircraft
	_aura = _commander.get_node_or_null("CommanderAura") as CommanderAura
	queue_redraw()  # 初次画光环圈

func _process(_delta: float) -> void:
	# 数据链线需要跟随僚机位置每帧刷新；父节点 transform 也在动，不能节流
	queue_redraw()

func _draw() -> void:
	if not _commander:
		return

	# 坠落淡出：基于 commander._destroy_timer（3→0）计算 alpha 倍率
	var alpha_mult := 1.0
	if _commander.is_destroyed:
		alpha_mult = clampf(_commander._destroy_timer / DESTROY_FADE_DURATION, 0.0, 1.0)
		if alpha_mult <= 0.01:
			return

	# ── 影响范围圈 ──
	var fill := FILL_COLOR
	fill.a *= alpha_mult
	draw_circle(Vector2.ZERO, CommanderAura.AURA_RADIUS, fill)
	var ring := RING_COLOR
	ring.a *= alpha_mult
	draw_arc(Vector2.ZERO, CommanderAura.AURA_RADIUS, 0, TAU, 64, ring, 1.0)

	# ── 数据链虚线 + 端点菱形（所有僚机合并成 2 次 GPU 提交）──
	# 性能守则 R3：不得循环调 draw_line/draw_polygon，批量提交
	if not _aura:
		return
	_draw_datalinks(alpha_mult)

const DASH_SEG := 12.0
const DASH_GAP := 8.0
const DIAMOND_R := 4.0

## 把所有僚机的虚线段 + 菱形合并为 2 次 GPU 命令：
## - 一条 draw_multiline 画所有虚线
## - 一次 RenderingServer.canvas_item_add_triangle_array 画所有菱形
func _draw_datalinks(alpha_mult: float) -> void:
	var link_col := LINK_COLOR
	link_col.a *= alpha_mult
	var diamond_col := DIAMOND_COLOR
	diamond_col.a *= alpha_mult

	var dash_points := PackedVector2Array()  # 两两一对，表示线段端点
	var tri_verts := PackedVector2Array()
	var tri_colors := PackedColorArray()
	var tri_indices := PackedInt32Array()

	for ac in _aura.buffed_aircraft:
		if not is_instance_valid(ac) or ac.is_destroyed:
			continue
		var local_pos := to_local(ac.global_position)
		var dist := local_pos.length()
		if dist < 1.0:
			continue
		var dir := local_pos / dist

		# 虚线：交替 DASH_SEG / DASH_GAP，只往 dash_points 里塞端点对
		var drawn := 0.0
		var is_seg := true
		while drawn < dist:
			var step_len := DASH_SEG if is_seg else DASH_GAP
			var seg_end := minf(drawn + step_len, dist)
			if is_seg:
				dash_points.append(dir * drawn)
				dash_points.append(dir * seg_end)
			drawn = seg_end
			is_seg = not is_seg

		# 菱形：4 个顶点 + 2 个三角形索引
		var base := tri_verts.size()
		tri_verts.append(local_pos + Vector2(0, -DIAMOND_R))
		tri_verts.append(local_pos + Vector2(DIAMOND_R, 0))
		tri_verts.append(local_pos + Vector2(0, DIAMOND_R))
		tri_verts.append(local_pos + Vector2(-DIAMOND_R, 0))
		for _i in 4:
			tri_colors.append(diamond_col)
		tri_indices.append(base)
		tri_indices.append(base + 1)
		tri_indices.append(base + 2)
		tri_indices.append(base)
		tri_indices.append(base + 2)
		tri_indices.append(base + 3)

	# 一次性提交：虚线
	if dash_points.size() >= 2:
		draw_multiline(dash_points, link_col, 1.0)

	# 一次性提交：所有菱形（低层 API，比多次 draw_colored_polygon 快）
	if tri_indices.size() >= 3:
		RenderingServer.canvas_item_add_triangle_array(
			get_canvas_item(), tri_indices, tri_verts, tri_colors
		)
