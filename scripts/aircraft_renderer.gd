class_name AircraftRenderer
extends RefCounted

## 玩家飞机全局引用（由 main.gd / survivor_mode.gd 在玩家生成/销毁时维护）
## draw_data_label 里每帧为每架飞机算 RNG 用，避免在 _draw 里 O(N) 扫 parent.get_children()
static var player_ref: Aircraft = null

## 飞机绘制系统（静态工具类）
## 从 aircraft.gd 提取的所有 _draw_* 子函数
## _draw() 入口仍保留在 aircraft.gd（Godot CanvasItem 回调必须是方法）
## 本类方法通过 ac.draw_rect() 等调用父 aircraft 的 CanvasItem 绘制方法
##
## 用法（在 aircraft.gd 的 _draw() 中）：
##   AircraftRenderer.draw_radar_cone(self)
##   AircraftRenderer.draw_aircraft_icon(self)
##   AircraftRenderer.draw_data_label(self)
##   等等

## 云层状态视觉：云中（HIGH）画冷白光晕，云下（LOW/MID）画淡蓝灰阴影
## 必须在图标之前调用（作底）
static func draw_cloud_state(ac: Aircraft) -> void:
	if ac.cloud_state == 2:
		# 云中：被云雾包裹的柔光晕（冷白偏蓝）
		var halo_r: float = 22.0
		var halo_col := Color(0.90, 0.95, 1.0, 0.32 + 0.12 * ac.cloud_density)
		ac.draw_circle(Vector2.ZERO, halo_r, halo_col)
		# 次级内晕，强化"被雾吞"感
		ac.draw_circle(Vector2.ZERO, halo_r * 0.6, Color(0.85, 0.92, 1.0, 0.18))
	elif ac.cloud_state == 1:
		# 云下：淡灰蓝椭圆阴影，略偏一侧模拟云影掠过
		var shadow_r: float = 16.0
		var shadow_alpha: float = 0.22 * ac.cloud_density
		ac.draw_circle(Vector2(4.0, 5.0), shadow_r, Color(0.35, 0.42, 0.52, shadow_alpha))

## 编队调试覆盖层（仅 formation_debug=true 时绘制）
## 显示：当前分支、阵型槽位、当前/目标航向射线、bank 差异
##
## 注：_draw 已在飞机的 local space（rotation=heading）下运行。
## 想要绘制"机头朝上"的本地几何（航向射线/槽位连线），直接使用 local 坐标即可：
##   - 当前 heading 在 local 中始终是 (0, -L)
##   - 槽位 local = (slot_world - global_position).rotated(-rotation)
## 想要文本不跟随机身旋转，用 draw_set_transform 反旋转回世界对齐。
static func draw_formation_debug(ac: Aircraft) -> void:
	# ── 1. 阵型槽位标记 + 连线（local space）──
	if ac._dbg_slot_pos != Vector2.INF and ac._dbg_slot_dist > 0.0:
		var slot_local := (ac._dbg_slot_pos - ac.global_position).rotated(-ac.rotation)
		var slot_color := Color(1.0, 0.4, 0.0, 0.7)  # 橙色
		ac.draw_line(Vector2.ZERO, slot_local, slot_color, 1.5)
		# 槽位 X 标记
		var sx := 8.0
		ac.draw_line(slot_local + Vector2(-sx, -sx), slot_local + Vector2(sx, sx), slot_color, 2.0)
		ac.draw_line(slot_local + Vector2(-sx, sx), slot_local + Vector2(sx, -sx), slot_color, 2.0)
		# CLOSE_DIST 阈值圆
		ac.draw_arc(slot_local, 50.0, 0, TAU, 32, Color(0.2, 1.0, 0.5, 0.4), 1.0)

	# ── 2. 当前/目标 heading 射线（local space，机头朝 -Y）──
	var ray_len := 80.0
	# 当前 heading 在 local 中始终朝上
	ac.draw_line(Vector2.ZERO, Vector2(0, -ray_len), Color(0.4, 0.7, 1.0, 0.85), 2.0)
	# 目标 heading 相对当前的角度差
	var rel := ac._dbg_target_heading - ac.heading
	var tgt_dir := Vector2(sin(rel), -cos(rel)) * ray_len
	ac.draw_line(Vector2.ZERO, tgt_dir, Color(1.0, 0.9, 0.2, 0.85), 2.0)

	# ── 3. 文本面板（用 transform 反旋转 + 缩放补偿，保持世界对齐 + 同屏字号）──
	var inv_rot := -ac.rotation
	var zoom_scale := ac.get_viewport_transform().get_scale()
	var inv_zoom := 1.0 / maxf(zoom_scale.x, 0.01)
	var label_offset := Vector2(-110 * inv_zoom, 36 * inv_zoom).rotated(inv_rot)
	ac.draw_set_transform(label_offset, inv_rot, Vector2(inv_zoom, inv_zoom))

	var lines := PackedStringArray()
	lines.append("[%s]" % ac._dbg_branch)
	lines.append("slot_d=%d" % int(ac._dbg_slot_dist))
	lines.append("hdg→%d Δ%+.1f°" % [int(rad_to_deg(ac._dbg_target_heading)), rad_to_deg(ac._dbg_hdiff)])
	lines.append("bank %+.0f→%+.0f" % [rad_to_deg(ac.bank_angle), rad_to_deg(ac._dbg_desired_bank)])
	if ac._dbg_branch == "MID":
		# 复用 _dbg_slot_heading 字段：现在是横向偏置角度（不再是世界方位角）
		lines.append("bias=%+.0f°" % rad_to_deg(ac._dbg_slot_heading))
	lines.append("spd→%d/%d" % [int(ac._dbg_chase_target_kmh), int(ac.speed * 3.6)])

	var line_h := 12.0
	var max_w := 110.0
	ac.draw_rect(Rect2(Vector2(-2, -2), Vector2(max_w + 4, lines.size() * line_h + 4)),
		Color(0.0, 0.0, 0.0, 0.65))
	for i in range(lines.size()):
		var color := Color(1.0, 0.9, 0.5, 1.0)
		if i == 0:
			match ac._dbg_branch:
				"CLOSE": color = Color(0.4, 1.0, 0.5, 1.0)
				"MID":   color = Color(1.0, 0.9, 0.3, 1.0)
				"FAR":   color = Color(1.0, 0.5, 0.3, 1.0)
		ac.draw_string(ac._font, Vector2(0, i * line_h + 9), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)

	ac.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func draw_radar_cone(ac: Aircraft) -> void:
	var radar_r := ac.params.radar_range if ac.params else 300.0
	var half_deg := ac.params.radar_half_angle if ac.params else 30.0
	var half_rad := deg_to_rad(half_deg)

	# 扇形在本地坐标绘制，飞机 rotation = heading
	# 本地坐标中飞机朝上（-Y），所以扇形中心轴 = -Y 方向 = -PI/2
	var center_angle := -PI / 2.0
	var start_angle := center_angle - half_rad
	var end_angle := center_angle + half_rad
	var segments := 24

	# 扇形颜色
	var cone_color: Color
	if ac.team == 0:
		cone_color = Color(0.2, 0.7, 0.8, 0.12)
	else:
		cone_color = Color(0.8, 0.2, 0.2, 0.12)

	# 构建扇形多边形（圆心 + 弧线上的点）
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(segments + 1):
		var angle := start_angle + (end_angle - start_angle) * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radar_r)

	ac.draw_colored_polygon(points, cone_color)

	# 扇形边缘线
	var edge_color := Color(cone_color, 0.35)
	ac.draw_line(Vector2.ZERO, points[1], edge_color, 1.0, true)
	ac.draw_line(Vector2.ZERO, points[points.size() - 1], edge_color, 1.0, true)
	# 弧线
	for i in range(1, points.size() - 1):
		ac.draw_line(points[i], points[i + 1], edge_color, 1.0, true)

static func draw_gun_cone(ac: Aircraft) -> void:
	if not ac.params or not ac.params.gun:
		return
	if ac.team != 0:
		return  # 只对友方显示机炮射程锥
	var gun_r := ac.params.gun.max_range * Aircraft.PIXELS_PER_METER
	var half_rad := deg_to_rad(ac.params.gun.fire_cone_half_angle)

	var center_angle := -PI / 2.0
	var start_angle := center_angle - half_rad
	var end_angle := center_angle + half_rad
	var segments := 16

	var cone_color := Color(0.9, 0.7, 0.2, 0.15)

	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(segments + 1):
		var angle := start_angle + (end_angle - start_angle) * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * gun_r)

	ac.draw_colored_polygon(points, cone_color)

	var edge_color := Color(cone_color, 0.4)
	ac.draw_line(Vector2.ZERO, points[1], edge_color, 1.0, true)
	ac.draw_line(Vector2.ZERO, points[points.size() - 1], edge_color, 1.0, true)
	for i in range(1, points.size() - 1):
		ac.draw_line(points[i], points[i + 1], edge_color, 1.0, true)

static func draw_lock_indicator(ac: Aircraft) -> void:
	if not ac.is_locked:
		return
	# 红色警告菱形，闪烁效果
	var blink := absf(sin(Time.get_ticks_msec() * 0.005))
	var alpha := lerpf(0.5, 1.0, blink)
	var warn_color := Color(1.0, 0.15, 0.1, alpha)
	var d := 22.0
	# 四个小三角围绕飞机
	var offsets: Array[Vector2] = [Vector2(0, -d), Vector2(d, 0), Vector2(0, d), Vector2(-d, 0)]
	var tri_size := 5.0
	for offset: Vector2 in offsets:
		var dir: Vector2 = offset.normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var tip: Vector2 = offset + dir * tri_size
		var base_a: Vector2 = offset + perp * tri_size * 0.6
		var base_b: Vector2 = offset - perp * tri_size * 0.6
		ac.draw_colored_polygon(PackedVector2Array([tip, base_a, base_b]), warn_color)

## 任务目标 TGT 括号（皇牌空战风格）：四角方括号 + 上方 "TGT" 文字
## 与 lock_indicator 区分：黄色非闪烁，尺寸更大
static func draw_target_bracket(node: Node2D, is_target: bool) -> void:
	if not is_target:
		return
	var color := Color(1.0, 0.85, 0.2, 0.95)
	var size := 28.0
	var corner := 10.0
	var w := 2.0
	# 四个角各两条短线（L 形）
	# 左上
	node.draw_line(Vector2(-size, -size), Vector2(-size + corner, -size), color, w)
	node.draw_line(Vector2(-size, -size), Vector2(-size, -size + corner), color, w)
	# 右上
	node.draw_line(Vector2(size, -size), Vector2(size - corner, -size), color, w)
	node.draw_line(Vector2(size, -size), Vector2(size, -size + corner), color, w)
	# 左下
	node.draw_line(Vector2(-size, size), Vector2(-size + corner, size), color, w)
	node.draw_line(Vector2(-size, size), Vector2(-size, size - corner), color, w)
	# 右下
	node.draw_line(Vector2(size, size), Vector2(size - corner, size), color, w)
	node.draw_line(Vector2(size, size), Vector2(size, size - corner), color, w)
	# "TGT" 文字（反旋转以保持屏幕水平）
	var rot := 0.0
	if "rotation" in node:
		rot = -node.rotation
	node.draw_set_transform(Vector2(-size * 0.55, -size - 8.0).rotated(rot), rot)
	node.draw_string(ThemeDB.fallback_font, Vector2.ZERO, "TGT",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)
	node.draw_set_transform(Vector2.ZERO, 0.0)

static func draw_muzzle_flash(ac: Aircraft) -> void:
	var flash_alpha := randf_range(0.6, 1.0)
	var flash_color := Color(1.0, 0.9, 0.3, flash_alpha)
	# 机头前方小闪光
	var tip := Vector2(0, -20.0)
	ac.draw_circle(tip, 4.0, flash_color)
	var flash2 := Color(1.0, 0.6, 0.1, flash_alpha * 0.5)
	ac.draw_circle(tip, 7.0, flash2)

static func draw_afterburner_glow(ac: Aircraft) -> void:
	var flicker := randf_range(0.7, 1.0)
	var glow_color := Color(1.0, 0.5, 0.1, 0.8 * flicker)
	var core_color := Color(1.0, 0.85, 0.4, 0.9 * flicker)
	# 尾喷口位置（本地坐标，飞机朝 -Y）
	var tail := Vector2(0, 16.0)
	var flame_len := randf_range(10.0, 16.0)
	# 火焰三角
	var flame := PackedVector2Array([
		tail + Vector2(-3.0, 0),
		tail + Vector2(3.0, 0),
		tail + Vector2(0, flame_len),
	])
	ac.draw_colored_polygon(flame, glow_color)
	# 内焰
	var inner := PackedVector2Array([
		tail + Vector2(-1.5, 0),
		tail + Vector2(1.5, 0),
		tail + Vector2(0, flame_len * 0.6),
	])
	ac.draw_colored_polygon(inner, core_color)

static func draw_flare_particles(ac: Aircraft) -> void:
	for p in ac._flare_particles:
		var pos: Vector2 = p["pos"]
		var life: float = p["life"]
		var is_bright: bool = p.get("bright", false)
		var local_pos := ac.to_local(pos)
		var alpha := clampf(life / 1.5, 0.0, 1.0)
		if is_bright:
			# 核心亮点：大且白亮
			var size := lerpf(2.0, 5.0, alpha)
			var core := Color(1.0, 1.0, 0.9, alpha * 0.95)
			ac.draw_circle(local_pos, size, core)
			# 外发光
			var glow := Color(1.0, 0.7, 0.2, alpha * 0.3)
			ac.draw_circle(local_pos, size * 2.5, glow)
		else:
			# 拖尾：橙黄色，较小
			var size := lerpf(1.0, 3.0, alpha)
			var color := Color(1.0, 0.8, 0.3, alpha * 0.7)
			ac.draw_circle(local_pos, size, color)

static func draw_aircraft_icon_destroyed(ac: Aircraft) -> void:
	# 灰色闪烁图标
	var blink := absf(sin(Time.get_ticks_msec() * 0.008))
	var gray := Color(0.5, 0.5, 0.5, lerpf(0.3, 0.7, blink))
	var size := 12.0
	var body := PackedVector2Array([
		Vector2(0, -size), Vector2(size * 0.5, size * 0.3),
		Vector2(0, size), Vector2(-size * 0.5, size * 0.3),
	])
	ac.draw_colored_polygon(body, gray)

static func draw_aircraft_icon(ac: Aircraft) -> void:
	var color: Color = ac.params.icon_color if ac.params else Color.GREEN
	var outline_color := color.darkened(0.3)

	var size := 16.0

	# 高度缩放：以 5000m 为基准（scale=1.0），低空缩小、高空放大
	# 使用 sqrt 曲线让中低空的变化更明显
	var ref_alt := 5000.0
	var max_alt := ac.params.max_altitude if ac.params else 15000.0
	var alt_ratio := clampf(ac.altitude / max_alt, 0.0, 1.0)
	var ref_ratio := ref_alt / max_alt
	# 基准以下：0.65~1.0，基准以上：1.0~1.4
	var base_scale: float
	if alt_ratio <= ref_ratio:
		base_scale = lerpf(0.65, 1.0, sqrt(alt_ratio / ref_ratio))
	else:
		base_scale = lerpf(1.0, 1.4, (alt_ratio - ref_ratio) / (1.0 - ref_ratio))

	# 滚转变形（常规 bank + 规避时的原地滚转相位）
	var bank_compress := cos(ac.bank_angle + ac._evade_roll_phase)
	var sx := base_scale * bank_compress
	var sy := base_scale
	# 战术机动视觉效果：俯视视角下 Y 轴压缩（模拟机头大仰角）
	var _mv := ac.get_maneuver()
	if _mv and _mv.visual_offset > 0.0:
		sy *= lerpf(1.0, 0.35, _mv.visual_offset)
	var _hm := ac.get_herbst()
	if _hm and _hm.visual_offset > 0.0:
		sy *= lerpf(1.0, 0.4, _hm.visual_offset)

	var xform := Transform2D(0.0, Vector2.ZERO)
	xform = xform.scaled(Vector2(sx, sy))

	# 指挥 UAV（哨兵）使用独立的飞翼外观
	var is_commander: bool = ac.has_meta("enemy_type") and ac.get_meta("enemy_type") == "uav_commander"
	if is_commander:
		draw_commander_icon(ac, color, outline_color, size, base_scale, xform)
		return

	# 轰炸机外观：更大翼展 + 长机身（Tu-160 / 战略轰炸机）
	var is_bomber: bool = ac.has_meta("silhouette") and ac.get_meta("silhouette") == "bomber"
	if is_bomber:
		draw_bomber_icon(ac, color, outline_color, size, base_scale, xform)
		return

	# 攻击直升机外观（AH-64 Apache）：细长机身 + 短翼挂架 + 主/尾旋翼盘
	var silhouette: String = ac.get_meta("silhouette", "") if ac.has_meta("silhouette") else ""
	if silhouette == "apache":
		draw_apache_icon(ac, color, outline_color, size, base_scale, xform)
		return
	# 运输直升机外观（CH-47 Chinook）：方形机身 + 前后双旋翼盘
	if silhouette == "chinook":
		draw_chinook_icon(ac, color, outline_color, size, base_scale, xform)
		return

	# 机身主体（填充多边形）
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(0, -size * 1.1),        # 机头尖端
		Vector2(size * 0.15, -size * 0.7),
		Vector2(size * 0.18, -size * 0.2),
		Vector2(size * 0.15, size * 0.5),
		Vector2(size * 0.20, size * 0.85),
		Vector2(0, size * 0.95),         # 尾喷口
		Vector2(-size * 0.20, size * 0.85),
		Vector2(-size * 0.15, size * 0.5),
		Vector2(-size * 0.18, -size * 0.2),
		Vector2(-size * 0.15, -size * 0.7),
	])

	# 主翼（三角翼，后掠）
	var wing_r: PackedVector2Array = PackedVector2Array([
		Vector2(size * 0.18, -size * 0.05),
		Vector2(size * 1.1, size * 0.25),
		Vector2(size * 0.9, size * 0.35),
		Vector2(size * 0.18, size * 0.20),
	])
	var wing_l: PackedVector2Array = PackedVector2Array([
		Vector2(-size * 0.18, -size * 0.05),
		Vector2(-size * 1.1, size * 0.25),
		Vector2(-size * 0.9, size * 0.35),
		Vector2(-size * 0.18, size * 0.20),
	])

	# 尾翼
	var tail_r: PackedVector2Array = PackedVector2Array([
		Vector2(size * 0.15, size * 0.55),
		Vector2(size * 0.55, size * 0.75),
		Vector2(size * 0.45, size * 0.85),
		Vector2(size * 0.18, size * 0.80),
	])
	var tail_l: PackedVector2Array = PackedVector2Array([
		Vector2(-size * 0.15, size * 0.55),
		Vector2(-size * 0.55, size * 0.75),
		Vector2(-size * 0.45, size * 0.85),
		Vector2(-size * 0.18, size * 0.80),
	])

	# 应用变换并绘制填充
	var parts := [body, wing_r, wing_l, tail_r, tail_l]
	for part in parts:
		var transformed: PackedVector2Array = PackedVector2Array()
		for p in part:
			transformed.append(xform * p)
		ac.draw_colored_polygon(transformed, color)
		# 轮廓线
		for i in range(transformed.size()):
			var from := transformed[i]
			var to := transformed[(i + 1) % transformed.size()]
			ac.draw_line(from, to, outline_color, 1.0, true)

	# 选中指示 - 细圆环
	if ac.selected:
		var ring_color := color
		ring_color.a = 0.5
		ac.draw_arc(Vector2.ZERO, size * 1.8 * base_scale, 0, TAU, 48, ring_color, 1.5)

## 指挥 UAV "哨兵" 专用飞翼外观
static func draw_commander_icon(ac: Aircraft, color: Color, outline_color: Color, size: float, base_scale: float, xform: Transform2D) -> void:
	var s := size  # 简写

	# ── 飞翼主体：宽扁的 V 形无尾翼体 ──
	# 从机头到两侧翼尖再收回，一体化飞翼造型
	var wing_body: PackedVector2Array = PackedVector2Array([
		Vector2(0, -s * 0.7),              # 机头（钝头）
		Vector2(s * 0.2, -s * 0.5),        # 机头右侧
		Vector2(s * 1.3, s * 0.1),         # 右翼前缘尖端（宽展）
		Vector2(s * 1.2, s * 0.25),        # 右翼后缘
		Vector2(s * 0.5, s * 0.2),         # 右翼根部后缘
		Vector2(s * 0.15, s * 0.5),        # 右侧尾部
		Vector2(0, s * 0.4),               # 尾部中心（浅 V 形凹口）
		Vector2(-s * 0.15, s * 0.5),       # 左侧尾部
		Vector2(-s * 0.5, s * 0.2),        # 左翼根部后缘
		Vector2(-s * 1.2, s * 0.25),       # 左翼后缘
		Vector2(-s * 1.3, s * 0.1),        # 左翼前缘尖端
		Vector2(-s * 0.2, -s * 0.5),       # 机头左侧
	])

	# 应用缩放变换并绘制
	var transformed: PackedVector2Array = PackedVector2Array()
	for p in wing_body:
		transformed.append(xform * p)
	ac.draw_colored_polygon(transformed, color)
	# 轮廓线
	for i in range(transformed.size()):
		var from := transformed[i]
		var to := transformed[(i + 1) % transformed.size()]
		ac.draw_line(from, to, outline_color, 1.0, true)

	# ── 机背中线标记（传感器/天线阵列） ──
	var accent := color.lightened(0.3)
	accent.a = 0.6
	var line_from := xform * Vector2(0, -s * 0.4)
	var line_to := xform * Vector2(0, s * 0.25)
	ac.draw_line(line_from, line_to, accent, 1.5, true)

	# ── 天线顶点标记 ──
	var antenna_base := xform * Vector2(0, -s * 0.7)
	var antenna_tip := xform * Vector2(0, -s * 1.1)
	ac.draw_line(antenna_base, antenna_tip, accent, 1.0, true)
	ac.draw_circle(antenna_tip, 2.5 * base_scale, accent)

	# 选中指示
	if ac.selected:
		var ring_color := color
		ring_color.a = 0.5
		ac.draw_arc(Vector2.ZERO, s * 1.8 * base_scale, 0, TAU, 48, ring_color, 1.5)

## 轰炸机专用外观（Tu-160 / 战略轰炸机）：超大翼展 + 长机身
## 相比战斗机图标整体放大 ~1.6x，并加深色机腹以示"重型单位"
static func draw_bomber_icon(ac: Aircraft, color: Color, outline_color: Color, size: float, base_scale: float, xform: Transform2D) -> void:
	var s := size * 1.15  # 机身整体比战斗机大一点

	# 机身主体（长梭形，前尖后收）
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(0, -s * 1.6),          # 机头尖端（更长）
		Vector2(s * 0.12, -s * 1.1),
		Vector2(s * 0.22, -s * 0.3),
		Vector2(s * 0.25, s * 0.4),
		Vector2(s * 0.22, s * 1.0),
		Vector2(s * 0.15, s * 1.25),   # 尾部
		Vector2(0, s * 1.30),
		Vector2(-s * 0.15, s * 1.25),
		Vector2(-s * 0.22, s * 1.0),
		Vector2(-s * 0.25, s * 0.4),
		Vector2(-s * 0.22, -s * 0.3),
		Vector2(-s * 0.12, -s * 1.1),
	])

	# 主翼（超大后掠翼，Tu-160 可变后掠特征 → 固定展开态）
	var wing_r: PackedVector2Array = PackedVector2Array([
		Vector2(s * 0.22, -s * 0.05),
		Vector2(s * 1.9, s * 0.50),     # 翼尖远远伸出
		Vector2(s * 1.75, s * 0.70),
		Vector2(s * 0.22, s * 0.55),
	])
	var wing_l: PackedVector2Array = PackedVector2Array([
		Vector2(-s * 0.22, -s * 0.05),
		Vector2(-s * 1.9, s * 0.50),
		Vector2(-s * 1.75, s * 0.70),
		Vector2(-s * 0.22, s * 0.55),
	])

	# 尾翼（大平尾）
	var tail_r: PackedVector2Array = PackedVector2Array([
		Vector2(s * 0.20, s * 0.95),
		Vector2(s * 0.85, s * 1.15),
		Vector2(s * 0.70, s * 1.30),
		Vector2(s * 0.22, s * 1.25),
	])
	var tail_l: PackedVector2Array = PackedVector2Array([
		Vector2(-s * 0.20, s * 0.95),
		Vector2(-s * 0.85, s * 1.15),
		Vector2(-s * 0.70, s * 1.30),
		Vector2(-s * 0.22, s * 1.25),
	])

	var parts := [body, wing_r, wing_l, tail_r, tail_l]
	for part in parts:
		var transformed: PackedVector2Array = PackedVector2Array()
		for p in part:
			transformed.append(xform * p)
		ac.draw_colored_polygon(transformed, color)
		for i in range(transformed.size()):
			var from := transformed[i]
			var to := transformed[(i + 1) % transformed.size()]
			ac.draw_line(from, to, outline_color, 1.0, true)

	# 选中指示
	if ac.selected:
		var ring_color := color
		ring_color.a = 0.5
		ac.draw_arc(Vector2.ZERO, s * 2.2 * base_scale, 0, TAU, 48, ring_color, 1.5)

## AH-64 Apache 攻击直升机外观：细长机身 + 短翼挂架 + 主旋翼盘 + 尾桨
static func draw_apache_icon(ac: Aircraft, color: Color, outline_color: Color, size: float, base_scale: float, xform: Transform2D) -> void:
	var s := size

	# 机身（细长，机头含传感器球，尾梁延伸）
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(0, -s * 1.15),           # 机头（尖端）
		Vector2(s * 0.08, -s * 0.85),
		Vector2(s * 0.14, -s * 0.45),
		Vector2(s * 0.18, -s * 0.05),    # 驾驶舱段
		Vector2(s * 0.20, s * 0.35),     # 机身中段（翼根）
		Vector2(s * 0.15, s * 0.65),
		Vector2(s * 0.08, s * 0.95),     # 尾梁开始收窄
		Vector2(s * 0.06, s * 1.25),
		Vector2(s * 0.04, s * 1.45),     # 尾端
		Vector2(0, s * 1.50),
		Vector2(-s * 0.04, s * 1.45),
		Vector2(-s * 0.06, s * 1.25),
		Vector2(-s * 0.08, s * 0.95),
		Vector2(-s * 0.15, s * 0.65),
		Vector2(-s * 0.20, s * 0.35),
		Vector2(-s * 0.18, -s * 0.05),
		Vector2(-s * 0.14, -s * 0.45),
		Vector2(-s * 0.08, -s * 0.85),
	])

	# 短翼挂架（武器翼）
	var wing_r: PackedVector2Array = PackedVector2Array([
		Vector2(s * 0.20, s * 0.10),
		Vector2(s * 0.75, s * 0.15),
		Vector2(s * 0.75, s * 0.35),
		Vector2(s * 0.20, s * 0.40),
	])
	var wing_l: PackedVector2Array = PackedVector2Array([
		Vector2(-s * 0.20, s * 0.10),
		Vector2(-s * 0.75, s * 0.15),
		Vector2(-s * 0.75, s * 0.35),
		Vector2(-s * 0.20, s * 0.40),
	])

	# 尾桨（小横杆在尾端）
	var tail_rotor: PackedVector2Array = PackedVector2Array([
		Vector2(-s * 0.30, s * 1.15),
		Vector2(s * 0.30, s * 1.15),
		Vector2(s * 0.30, s * 1.25),
		Vector2(-s * 0.30, s * 1.25),
	])

	# 填充并画轮廓
	var parts := [body, wing_r, wing_l, tail_rotor]
	for part in parts:
		var transformed: PackedVector2Array = PackedVector2Array()
		for p in part:
			transformed.append(xform * p)
		ac.draw_colored_polygon(transformed, color)
		for i in range(transformed.size()):
			var from := transformed[i]
			var to := transformed[(i + 1) % transformed.size()]
			ac.draw_line(from, to, outline_color, 1.0, true)

	# 主旋翼圆盘（半透明模拟旋转，随 Time 轻微闪变）
	var spin := float(Time.get_ticks_msec()) * 0.012
	var disc_alpha := 0.22 + 0.05 * sin(spin)
	var disc_color := Color(outline_color.r, outline_color.g, outline_color.b, disc_alpha)
	var disc_radius := s * 1.0 * base_scale
	ac.draw_circle(Vector2(0, s * 0.15 * base_scale), disc_radius, disc_color)
	# 旋翼叶片（十字线，随时间旋转，强调"这是直升机"）
	var blade_color := Color(outline_color.r, outline_color.g, outline_color.b, 0.55)
	for k in range(4):
		var ang := spin + k * PI / 2.0
		var tip := Vector2(cos(ang), sin(ang)) * disc_radius
		ac.draw_line(Vector2(0, s * 0.15 * base_scale), Vector2(0, s * 0.15 * base_scale) + tip, blade_color, 1.0, true)

	# 选中指示
	if ac.selected:
		var ring_color := color
		ring_color.a = 0.5
		ac.draw_arc(Vector2.ZERO, s * 1.8 * base_scale, 0, TAU, 48, ring_color, 1.5)

## CH-47 Chinook 运输直升机外观：方形宽机身 + 前后双旋翼盘
static func draw_chinook_icon(ac: Aircraft, color: Color, outline_color: Color, size: float, base_scale: float, xform: Transform2D) -> void:
	var s := size * 1.1

	# 机身（方正的货舱，前后对称，后部有货舱斜坡）
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(-s * 0.45, -s * 1.15),    # 左前（机头驾驶舱）
		Vector2(-s * 0.25, -s * 1.30),    # 前部斜坡
		Vector2(s * 0.25, -s * 1.30),
		Vector2(s * 0.45, -s * 1.15),     # 右前
		Vector2(s * 0.52, -s * 0.8),
		Vector2(s * 0.52, s * 0.8),
		Vector2(s * 0.45, s * 1.15),      # 右后
		Vector2(s * 0.30, s * 1.25),      # 后货舱斜坡
		Vector2(-s * 0.30, s * 1.25),
		Vector2(-s * 0.45, s * 1.15),     # 左后
		Vector2(-s * 0.52, s * 0.8),
		Vector2(-s * 0.52, -s * 0.8),
	])

	# 前后两座驻驾塔（旋翼支架）
	var pylon_front: PackedVector2Array = PackedVector2Array([
		Vector2(-s * 0.18, -s * 1.0),
		Vector2(s * 0.18, -s * 1.0),
		Vector2(s * 0.15, -s * 0.75),
		Vector2(-s * 0.15, -s * 0.75),
	])
	var pylon_rear: PackedVector2Array = PackedVector2Array([
		Vector2(-s * 0.18, s * 0.75),
		Vector2(s * 0.18, s * 0.75),
		Vector2(s * 0.22, s * 1.05),
		Vector2(-s * 0.22, s * 1.05),
	])

	# 填充机身 + 支架
	var parts := [body, pylon_front, pylon_rear]
	for part in parts:
		var transformed: PackedVector2Array = PackedVector2Array()
		for p in part:
			transformed.append(xform * p)
		ac.draw_colored_polygon(transformed, color)
		for i in range(transformed.size()):
			var from := transformed[i]
			var to := transformed[(i + 1) % transformed.size()]
			ac.draw_line(from, to, outline_color, 1.0, true)

	# 前后双旋翼圆盘（Chinook 标志性双桨）
	var spin := float(Time.get_ticks_msec()) * 0.013
	var disc_alpha := 0.22 + 0.05 * sin(spin)
	var disc_color := Color(outline_color.r, outline_color.g, outline_color.b, disc_alpha)
	var disc_radius := s * 0.95 * base_scale
	var front_pos := Vector2(0, -s * 0.85 * base_scale)
	var rear_pos := Vector2(0, s * 0.90 * base_scale)
	ac.draw_circle(front_pos, disc_radius, disc_color)
	ac.draw_circle(rear_pos, disc_radius, disc_color)
	# 旋翼叶片（前后桨反向旋转：Chinook 双桨反转）
	var blade_color := Color(outline_color.r, outline_color.g, outline_color.b, 0.55)
	for k in range(3):
		var ang_f := spin + k * TAU / 3.0
		var ang_r := -spin + k * TAU / 3.0
		var tip_f := Vector2(cos(ang_f), sin(ang_f)) * disc_radius
		var tip_r := Vector2(cos(ang_r), sin(ang_r)) * disc_radius
		ac.draw_line(front_pos, front_pos + tip_f, blade_color, 1.0, true)
		ac.draw_line(rear_pos, rear_pos + tip_r, blade_color, 1.0, true)

	# 选中指示
	if ac.selected:
		var ring_color := color
		ring_color.a = 0.5
		ac.draw_arc(Vector2.ZERO, s * 1.8 * base_scale, 0, TAU, 48, ring_color, 1.5)

## 在飞机旁边绘制数据标签框（逐行列出所有参数）
## 是否使用精简标签（无导弹/无热诱弹的简单单位）
## 生存模式玩家用精简标签：只显示朝向、速度、高度、G、耐力
static func draw_data_label_minimal(ac: Aircraft) -> void:
	var speed_kmh := ac.speed * 3.6
	var heading_deg := rad_to_deg(ac.heading)
	if heading_deg < 0:
		heading_deg += 360.0

	var lines := PackedStringArray()
	lines.append(ac.callsign)
	lines.append("HDG %03d" % roundi(heading_deg))
	lines.append("%d kt" % roundi(speed_kmh * 0.5399))
	if ac.flat_altitude:
		lines.append("ALT %s" % Aircraft.TIER_NAMES[ac.get_altitude_tier()])
	else:
		lines.append("ALT %dm" % roundi(ac.altitude))
	lines.append("G %.1f" % ac.g_load)
	var max_stam := ac.params.pilot_stamina if ac.params else 100.0
	lines.append("STA %d%%" % roundi(ac.pilot_stamina / maxf(max_stam, 0.01) * 100.0))

	var inv_rot := -ac.rotation
	var font_size := 11
	var line_height := 14.0
	# 缩放补偿
	var zoom_scale := ac.get_viewport_transform().get_scale()
	var inv_zoom := 1.0 / maxf(zoom_scale.x, 0.01)
	var label_offset := Vector2(24 * inv_zoom, -12 * inv_zoom).rotated(inv_rot)

	var max_w := 0.0
	for line in lines:
		var w := ac._font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		max_w = maxf(max_w, w)

	var scale_v := Vector2(inv_zoom, inv_zoom)
	var team_color: Color = ac.params.icon_color if ac.params else Color.GREEN
	var bg_color := Color(team_color.r * 0.15, team_color.g * 0.15, team_color.b * 0.2, 0.7)

	ac.draw_set_transform(label_offset, inv_rot, scale_v)
	ac.draw_rect(Rect2(-2, -2, max_w + 6, lines.size() * line_height + 4), bg_color)
	for i in range(lines.size()):
		ac.draw_string(ac._font, Vector2(0, i * line_height + 11), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.85, 0.9, 0.85, 0.9))
	ac.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func draw_data_label(ac: Aircraft) -> void:
	var display_name: String = ac.params.display_name if ac.params else "???"
	var speed_kmh := ac.speed * 3.6
	var heading_deg := rad_to_deg(ac.heading)
	if heading_deg < 0:
		heading_deg += 360.0
	var status := "STALL" if ac.is_stalled else ""

	# 计算到玩家的距离（米）——用全局玩家引用，避免每帧扫 parent.get_children() 的 O(N)
	var dist_m := 0.0
	var pref := player_ref
	if pref and pref != ac and is_instance_valid(pref) and not pref.is_destroyed:
		dist_m = ac.global_position.distance_to(pref.global_position) / Aircraft.PIXELS_PER_METER

	# 统一标签格式（所有飞机通用）
	var lines: PackedStringArray = PackedStringArray()
	# 第 1 行：代号 + 机种
	lines.append("%s [%s]" % [ac.callsign, display_name])
	# 第 2 行：速度（kt）
	lines.append("%d kt" % roundi(speed_kmh * 0.5399))
	# 第 3 行：朝向
	lines.append("HDG %03d" % roundi(heading_deg))
	# 第 4 行：高度
	if ac.flat_altitude:
		lines.append("ALT %s" % Aircraft.TIER_NAMES[ac.get_altitude_tier()])
	else:
		lines.append("ALT %dm" % roundi(ac.altitude))
	# 第 5 行：距离（到玩家）
	if dist_m < 1000.0:
		lines.append("RNG %dm" % roundi(dist_m))
	else:
		lines.append("RNG %.1fkm" % (dist_m / 1000.0))
	# 第 6 行：热诱弹
	if ac.params and ac.params.flare:
		lines.append("FLR %d" % ac.flares_remaining)
	# 失速提示
	if status != "":
		lines.append(status)

	var inv_rot := -ac.rotation
	var font_size := 11
	var line_height := 14.0
	# 缩放补偿：标签大小不随摄像机缩放变化
	var zoom_scale := ac.get_viewport_transform().get_scale()
	var inv_zoom := 1.0 / maxf(zoom_scale.x, 0.01)
	var label_offset := Vector2(24 * inv_zoom, -12 * inv_zoom).rotated(inv_rot)

	# 测量最大宽度
	var max_w := 0.0
	for line in lines:
		var w := ac._font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		max_w = maxf(max_w, w)
	var box_w := max_w + 10.0
	var box_h := lines.size() * line_height + 6.0

	# 背景色（基于阵营）
	var _alc := GameConstants.aircraft_label_colors(ac.team)
	var bg_color: Color = _alc[0]
	var text_color: Color = _alc[1]

	var scale_v := Vector2(inv_zoom, inv_zoom)
	ac.draw_set_transform(label_offset, inv_rot, scale_v)
	ac.draw_rect(Rect2(0, 0, box_w, box_h), bg_color)
	ac.draw_rect(Rect2(0, 0, box_w, box_h), text_color * Color(1, 1, 1, 0.4), false, 1.0)

	for i in range(lines.size()):
		ac.draw_string(ac._font, Vector2(5, 12 + i * line_height), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

	ac.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func draw_tactic_popup(ac: Aircraft) -> void:
	if ac._tactic_popup_timer <= 0.0 or ac._tactic_popup_text == "":
		return
	var inv_rot := -ac.rotation
	var font_size := 12
	# 渐隐：最后 0.5 秒淡出
	var alpha := clampf(ac._tactic_popup_timer / 0.5, 0.0, 1.0)
	# 上浮效果：随时间向上飘
	var elapsed := Aircraft.TACTIC_POPUP_DURATION - ac._tactic_popup_timer
	var float_offset := elapsed * 15.0  # 向上飘动速度
	var text_w := ac._font.get_string_size(ac._tactic_popup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var popup_pos := Vector2(-text_w * 0.5, -30.0 - float_offset).rotated(inv_rot)
	var bg_color := Color(0.1, 0.1, 0.1, 0.7 * alpha)
	var text_color := Color(1.0, 0.9, 0.3, alpha)
	var pad := Vector2(4, 2)
	ac.draw_set_transform(popup_pos, inv_rot, Vector2.ONE)
	ac.draw_rect(Rect2(-pad.x, -12 - pad.y, text_w + pad.x * 2, 14 + pad.y * 2), bg_color)
	ac.draw_string(ac._font, Vector2(0, 0), ac._tactic_popup_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)
	ac.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func draw_target_line(ac: Aircraft) -> void:
	if not ac.selected and ac.team != 0:
		return

	# 有战斗目标时：连接线指向敌机
	if ac.combat_target and is_instance_valid(ac.combat_target) and not ac.combat_target.is_destroyed:
		var ct_color := Color(GameConstants.team_color(ac.team), 0.6)
		var ct_local := ac.to_local(ac.combat_target.global_position)
		ac.draw_line(Vector2.ZERO, ct_local, ct_color, 1.5, true)
		var ct_d := 8.0
		ac.draw_line(ct_local + Vector2(-ct_d, 0), ct_local + Vector2(ct_d, 0), ct_color, 1.5)
		ac.draw_line(ct_local + Vector2(0, -ct_d), ct_local + Vector2(0, ct_d), ct_color, 1.5)
		ac.draw_circle(ct_local, ct_d, Color(ct_color, 0.2))
		return

	if ac.target_position == Vector2.INF:
		return

	if ac.team != 0:
		return

	# 编队僚机不显示预测线/航点：它们跟随长机指令，target_position 只是阵型槽位
	if ac.formation_mode:
		return

	var color: Color = ac.params.icon_color if ac.params else Color.GREEN

	var local_target := ac.to_local(ac.target_position)

	# 预测飞行路径
	draw_predicted_path(ac, local_target, color)

	# 航点标记 — 十字 + 圆环
	var d := 10.0
	var marker_color := Color(0.3, 0.8, 1.0, 0.7)
	ac.draw_circle(local_target, d, Color(marker_color, 0.15))
	ac.draw_arc(local_target, d, 0, TAU, 32, marker_color, 1.5)
	ac.draw_line(local_target + Vector2(-d * 1.3, 0), local_target + Vector2(d * 1.3, 0), marker_color, 1.0)
	ac.draw_line(local_target + Vector2(0, -d * 1.3), local_target + Vector2(0, d * 1.3), marker_color, 1.0)

## 绘制预测飞行路径：模拟转弯弧线 + 直线段
## 模拟真实物理：滚转速率、速度衰减、G力限制
static func draw_predicted_path(ac: Aircraft, local_target: Vector2, base_color: Color) -> void:
	var path_color := Color(base_color.r, base_color.g, base_color.b, 0.35)

	# 模拟参数（从当前飞机状态初始化）
	var sim_heading := ac.heading
	var sim_pos := ac.global_position
	var sim_speed := maxf(ac.speed, 50.0)  # m/s
	var sim_bank := ac.bank_angle          # 当前坡度
	var roll_rate_val := ac.params.roll_rate if ac.params else 4.0
	var accel_rate := ac.params.acceleration if ac.params else 50.0
	var decel_rate := ac.params.deceleration if ac.params else 80.0
	var cruise_ms := (ac.params.cruise_speed if ac.params else 900.0) / 3.6
	var stall_base_ms := (ac.params.stall_speed_base if ac.params else 220.0) / 3.6

	var step := 0.08  # 更细的模拟步长
	var max_steps := 180
	var record_interval := 3  # 每3步记录一个点

	var points := PackedVector2Array()
	points.append(Vector2.ZERO)

	for i in range(max_steps):
		var to_tgt := ac.target_position - sim_pos
		var dist_to_tgt := to_tgt.length()
		if dist_to_tgt < sim_speed * Aircraft.PIXELS_PER_METER * step * 2.0:
			points.append(ac.to_local(sim_pos))
			break

		# 目标航向
		var tgt_heading := atan2(to_tgt.x, -to_tgt.y)
		var hdiff := Aircraft._angle_diff(tgt_heading, sim_heading)

		# 模拟目标坡度（与实际 _update_bank 逻辑一致）
		var max_bank_sim := ac._max_bank_angle_at_speed(sim_speed, stall_base_ms)
		var target_bank: float
		if abs(hdiff) < 0.05:
			target_bank = 0.0
		elif abs(hdiff) < 0.4:
			target_bank = sign(hdiff) * max_bank_sim * 0.3
		else:
			target_bank = sign(hdiff) * max_bank_sim
		# 接近目标时衰减坡度
		var prox := clampf((dist_to_tgt - 150.0) / 300.0, 0.0, 1.0)
		target_bank *= prox

		# 滚转速率限制
		var bank_diff := target_bank - sim_bank
		var max_roll := roll_rate_val * step
		sim_bank += clampf(bank_diff, -max_roll, max_roll)

		# 转弯（基于当前坡度）
		if abs(sim_bank) > 0.001:
			var turn_rate := Aircraft.GRAVITY * tan(sim_bank) / maxf(sim_speed, 1.0)
			sim_heading += turn_rate * step
			sim_heading = fmod(sim_heading + PI, TAU) - PI

		# 速度模拟：转弯时减速（G力阻力），直飞时恢复巡航速度
		var current_g := 1.0 / maxf(cos(sim_bank), 0.01)
		var drag_decel := (current_g - 1.0) * 8.0  # G力越大减速越快
		var target_speed := cruise_ms
		if sim_speed > target_speed:
			sim_speed -= (decel_rate * 0.5 + drag_decel) * step
		else:
			sim_speed += accel_rate * 0.3 * step
		sim_speed = maxf(sim_speed, stall_base_ms * 1.3)

		# 前进
		var vel := Vector2(sin(sim_heading), -cos(sim_heading)) * sim_speed * Aircraft.PIXELS_PER_METER
		sim_pos += vel * step

		if i % record_interval == 0:
			points.append(ac.to_local(sim_pos))

	# 绘制路径（虚线效果：交替绘制段）
	if points.size() >= 2:
		for i in range(points.size() - 1):
			if i % 2 == 0:
				var alpha := lerpf(0.4, 0.1, float(i) / float(points.size()))
				var seg_color := Color(path_color.r, path_color.g, path_color.b, alpha)
				ac.draw_line(points[i], points[i + 1], seg_color, 1.5)
