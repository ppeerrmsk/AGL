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

## 把字符串里所有数字替换成 "0"，用于测量稳定宽度
## 为什么：字体里 0~9 不是完全等宽（fallback 字体是 proportional，不是 tabular），
## 所以 "HDG 060" 和 "HDG 063" 的像素宽度差 1~2 px。label 每帧按当前文字重算 max_w，
## 导致 box_w 在高频 hdg 变化（如 F-47 J-Turn 3°/帧）下每帧抽 1~2 px，视觉表现为"抽搐"。
## 详见 docs/changelogs/player-ai-log.md 2026-04-21 (10)
static func _digit_stable(s: String) -> String:
	var out := ""
	for i in range(s.length()):
		var c := s[i]
		if c >= "0" and c <= "9":
			out += "0"
		else:
			out += c
	return out

## 高度档位颜色（供数据标签 ALT 行 + HUD 状态面板复用，保持两处一致）
## LOW=暖橙(贴地危险) / MID=中性蓝 / HIGH=冷青(高空稀薄) / 过渡中=黄色
## 返回 [normal_color, hex_string_for_rich_text]
## 高度缩放基准（与 draw_aircraft_icon 保持一致）
## 尾焰 / 枪口闪光 / 其他附件都必须乘这个值，否则图标变大后附件还停在原位
static func altitude_base_scale(ac: Aircraft) -> float:
	if ac.flat_altitude:
		match ac.get_altitude_tier():
			0: return 0.70
			1: return 1.05
			2: return 1.55
			_: return 1.0
	var ref_alt := 5000.0
	var max_alt := ac.params.max_altitude if ac.params else 15000.0
	var alt_ratio := clampf(ac.altitude / max_alt, 0.0, 1.0)
	var ref_ratio := ref_alt / max_alt
	if alt_ratio <= ref_ratio:
		return lerpf(0.60, 1.0, sqrt(alt_ratio / maxf(ref_ratio, 0.001)))
	return lerpf(1.0, 1.55, (alt_ratio - ref_ratio) / maxf(1.0 - ref_ratio, 0.001))

static func altitude_tier_color(tier: int, transitioning: bool) -> Color:
	if transitioning:
		return Color(1.0, 0.80, 0.27)  # #ffcc44
	match tier:
		0:  return Color(1.0, 0.62, 0.40)  # LOW - 暖橙
		1:  return Color(0.67, 0.80, 1.0)  # MID - 中性蓝（原默认）
		2:  return Color(0.70, 0.95, 1.0)  # HIGH - 冷青
		_:  return Color(0.67, 0.80, 1.0)

static func altitude_tier_color_hex(tier: int, transitioning: bool) -> String:
	if transitioning:
		return "ffcc44"
	match tier:
		0:  return "ff9e66"
		1:  return "aaccff"
		2:  return "b3f2ff"
		_:  return "aaccff"

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
	var p: float = clampf(ac.incoming_lock_progress, 0.0, 1.0)
	if p <= 0.0 and not ac.is_locked:
		return
	var pref: Aircraft = player_ref
	# 反旋转，让方框对齐屏幕（不随机身 heading 转）
	var inv_rot: float = -ac.rotation
	ac.draw_set_transform(Vector2.ZERO, inv_rot, Vector2.ONE)
	draw_lock_box(ac, p, ac.is_locked)
	# 玩家被锁定：在周边画红色小三角指向每个锁定者
	if ac == pref and ac.is_locked and ac.locked_by.size() > 0:
		_draw_incoming_lock_arrows(ac)
	ac.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 玩家被锁定时，在周边画小红三角指向每个锁定者（世界方向）
static func _draw_incoming_lock_arrows(ac: Aircraft) -> void:
	const R: float = 52.0       # 距玩家中心的半径
	const TRI: float = 6.0      # 三角尺寸
	var blink: float = absf(sin(Time.get_ticks_msec() * 0.008))
	var alpha: float = lerpf(0.6, 1.0, blink)
	var color: Color = Color(1.0, 0.25, 0.2, alpha)
	for shooter: CombatUnit in ac.locked_by:
		if not is_instance_valid(shooter):
			continue
		var delta: Vector2 = shooter.global_position - ac.global_position
		if delta.length_squared() < 1.0:
			continue
		var dir: Vector2 = delta.normalized()
		var perp: Vector2 = Vector2(-dir.y, dir.x)
		var tip: Vector2 = dir * (R + TRI)
		var base_a: Vector2 = dir * R + perp * TRI * 0.7
		var base_b: Vector2 = dir * R - perp * TRI * 0.7
		ac.draw_colored_polygon(PackedVector2Array([tip, base_a, base_b]), color)

## 通用锁定方框绘制（Aircraft / GroundUnit 共用）
## progress (0..1) 驱动动画：旋转一圈 + 从大到小收缩，绿色；locked=true 时切红色静止
static func draw_lock_box(node: Node2D, progress: float, locked: bool) -> void:
	if locked:
		var blink: float = absf(sin(Time.get_ticks_msec() * 0.006))
		var alpha: float = lerpf(0.55, 1.0, blink)
		var red: Color = Color(1.0, 0.15, 0.1, alpha)
		_draw_corner_brackets(node, 22.0, red, 0.0)
	else:
		var size: float = lerpf(68.0, 24.0, progress)
		var angle: float = progress * TAU
		var alpha: float = lerpf(0.35, 1.0, progress)
		var green: Color = Color(0.35, 1.0, 0.45, alpha)
		_draw_corner_brackets(node, size, green, angle)
		# 进度环：顶部起顺时针扫过的短弧，辅助读进度
		var arc_r: float = size * 0.95
		var seg: int = maxi(8, int(progress * 28.0))
		var start_a: float = -PI * 0.5 + angle
		var pts: PackedVector2Array = PackedVector2Array()
		for i in range(seg + 1):
			var a: float = start_a + (progress * TAU) * float(i) / float(seg)
			pts.append(Vector2(cos(a), sin(a)) * arc_r)
		for i in range(pts.size() - 1):
			node.draw_line(pts[i], pts[i + 1], Color(green, alpha * 0.6), 1.0, true)

## 四角 L 形角标（带整体旋转角），短边 = size*0.35
static func _draw_corner_brackets(node: Node2D, size: float, color: Color, angle: float) -> void:
	var half: float = size * 0.5
	var corner_len: float = size * 0.35
	var width: float = 2.0
	# 四个角：左上、右上、右下、左下
	var corners: Array[Vector2] = [
		Vector2(-half, -half), Vector2(half, -half),
		Vector2(half, half), Vector2(-half, half),
	]
	# 每个角两条短线的方向（沿 x / 沿 y）
	var dirs: Array = [
		[Vector2(1, 0), Vector2(0, 1)],
		[Vector2(-1, 0), Vector2(0, 1)],
		[Vector2(-1, 0), Vector2(0, -1)],
		[Vector2(1, 0), Vector2(0, -1)],
	]
	for i in range(4):
		var c: Vector2 = corners[i].rotated(angle)
		var d1: Vector2 = (dirs[i][0] as Vector2).rotated(angle) * corner_len
		var d2: Vector2 = (dirs[i][1] as Vector2).rotated(angle) * corner_len
		node.draw_line(c, c + d1, color, width, true)
		node.draw_line(c, c + d2, color, width, true)

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
	var s := altitude_base_scale(ac)
	# 机头前方小闪光
	var tip := Vector2(0, -20.0 * s)
	ac.draw_circle(tip, 4.0 * s, flash_color)
	var flash2 := Color(1.0, 0.6, 0.1, flash_alpha * 0.5)
	ac.draw_circle(tip, 7.0 * s, flash2)

static func draw_afterburner_glow(ac: Aircraft) -> void:
	var flicker := randf_range(0.7, 1.0)
	var glow_color := Color(1.0, 0.5, 0.1, 0.8 * flicker)
	var core_color := Color(1.0, 0.85, 0.4, 0.9 * flicker)
	# 基础大小与机身图标一致（乘 altitude_base_scale）
	var s := altitude_base_scale(ac)
	# 再叠 cobra/herbst 各向同性收缩
	var sy_compress: float = s
	var _mv := ac.get_maneuver()
	if _mv and _mv.visual_offset > 0.0:
		sy_compress *= lerpf(1.0, 0.35, _mv.visual_offset)
	var _hm := ac.get_herbst()
	if _hm and _hm.visual_offset > 0.0:
		sy_compress *= lerpf(1.0, 0.4, _hm.visual_offset)
	# 尾喷口位置（本地坐标，飞机朝 -Y）
	var tail := Vector2(0, 16.0 * sy_compress)
	var flame_len := randf_range(10.0, 16.0) * sy_compress
	# 火焰三角（横向半宽也随 s 缩放）
	var half_w := 3.0 * s
	var flame := PackedVector2Array([
		tail + Vector2(-half_w, 0),
		tail + Vector2(half_w, 0),
		tail + Vector2(0, flame_len),
	])
	ac.draw_colored_polygon(flame, glow_color)
	# 内焰
	var inner := PackedVector2Array([
		tail + Vector2(-half_w * 0.5, 0),
		tail + Vector2(half_w * 0.5, 0),
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

	# 高度缩放（档位离散 / 沙盒连续，见 altitude_base_scale）
	var base_scale: float = altitude_base_scale(ac)

	# 滚转变形（常规 bank + 规避时的原地滚转相位）
	var bank_compress := cos(ac.bank_angle + ac._evade_roll_phase)
	var sx := base_scale * bank_compress
	var sy := base_scale
	# 战术机动视觉效果：各向同性收缩（表示"极端机动"），不只压 Y 轴。
	# 为什么各向同性：
	#   旧版只压 sy（本地 Y 轴 = 机体纵轴），heading 旋转时 sy 压缩方向跟着转 →
	#   J-Turn TURN 阶段 180°/秒偏航下，图标屏幕长宽比每帧剧变（每 3°/帧：
	#   偏航 0° 短而宽 → 偏航 90° 高而窄），人眼感知为"机身抽搐、状态框跟着抖"。
	#   这是物理上正确的俯视"机头仰角"效果，但转速太快感官无法接受。
	#   改成 sx/sy 同时压缩后，图标只是变小（表达极端机动），长宽比稳定，不再抖。
	# 详见 docs/changelogs/player-ai-log.md 2026-04-21 (11)
	var _mv := ac.get_maneuver()
	if _mv and _mv.visual_offset > 0.0:
		var f: float = lerpf(1.0, 0.35, _mv.visual_offset)
		sx *= f
		sy *= f
	var _hm := ac.get_herbst()
	if _hm and _hm.visual_offset > 0.0:
		var f: float = lerpf(1.0, 0.4, _hm.visual_offset)
		sx *= f
		sy *= f

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
	var alt_line_idx := lines.size()
	if ac.flat_altitude:
		var tier_now: int = ac.get_altitude_tier()
		var tier_tgt: int = ac.target_altitude_tier
		if tier_now != tier_tgt:
			lines.append("ALT %s>%s" % [Aircraft.TIER_NAMES[tier_now], Aircraft.TIER_NAMES[tier_tgt]])
		else:
			lines.append("ALT %s" % Aircraft.TIER_NAMES[tier_now])
	else:
		lines.append("ALT %dm" % roundi(ac.altitude))
	lines.append("G %.1f" % ac.g_load)
	var max_stam := ac.params.pilot_stamina if ac.params else 100.0
	lines.append("STA %d%%" % roundi(ac.pilot_stamina / maxf(max_stam, 0.01) * 100.0))
	# 装填状态（仅玩家）：临时行，装填完自动消失
	if ac == player_ref:
		if ac._gun_reload_active:
			lines.append("GUN RELOAD %d%%" % roundi(ac.gun_reload_progress * 100.0))
		if ac._missile_reload_active:
			lines.append("MSL RELOAD %d%%" % roundi(ac.missile_reload_progress * 100.0))
		if ac.enable_flare_reload and ac.flares_remaining <= 0 and ac.flare_reload_progress > 0.0:
			lines.append("FLR RELOAD %d%%" % roundi(ac.flare_reload_progress * 100.0))

	var inv_rot := -ac.rotation
	var font_size := 11
	var line_height := 14.0
	# 缩放补偿
	var zoom_scale := ac.get_viewport_transform().get_scale()
	var inv_zoom := 1.0 / maxf(zoom_scale.x, 0.01)
	var label_offset := Vector2(24 * inv_zoom, -12 * inv_zoom).rotated(inv_rot)

	var max_w := 0.0
	for line in lines:
		var w := ac._font.get_string_size(_digit_stable(line), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		max_w = maxf(max_w, w)

	var scale_v := Vector2(inv_zoom, inv_zoom)
	var team_color: Color = ac.params.icon_color if ac.params else Color.GREEN
	var bg_color := Color(team_color.r * 0.15, team_color.g * 0.15, team_color.b * 0.2, 0.7)

	ac.draw_set_transform(label_offset, inv_rot, scale_v)
	ac.draw_rect(Rect2(-2, -2, max_w + 6, lines.size() * line_height + 4), bg_color)
	var default_text_color := Color(0.85, 0.9, 0.85, 0.9)
	# 仅玩家自己标 ALT 颜色；敌机保持统一色
	var is_player := ac == player_ref
	var alt_color := altitude_tier_color(ac.get_altitude_tier(), ac.flat_altitude and ac.get_altitude_tier() != ac.target_altitude_tier) if is_player else default_text_color
	for i in range(lines.size()):
		var col := alt_color if (is_player and i == alt_line_idx) else default_text_color
		ac.draw_string(ac._font, Vector2(0, i * line_height + 11), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
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
	var alt_line_idx := lines.size()
	if ac.flat_altitude:
		var tier_now: int = ac.get_altitude_tier()
		var tier_tgt: int = ac.target_altitude_tier
		if tier_now != tier_tgt:
			lines.append("ALT %s>%s" % [Aircraft.TIER_NAMES[tier_now], Aircraft.TIER_NAMES[tier_tgt]])
		else:
			lines.append("ALT %s" % Aircraft.TIER_NAMES[tier_now])
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
	# 装填状态（仅玩家）：按进度拼出来 — 机炮 / 导弹 / 热诱弹
	if ac == player_ref:
		if ac._gun_reload_active:
			lines.append("GUN RELOAD %d%%" % roundi(ac.gun_reload_progress * 100.0))
		if ac._missile_reload_active:
			lines.append("MSL RELOAD %d%%" % roundi(ac.missile_reload_progress * 100.0))
		if ac.enable_flare_reload and ac.flares_remaining <= 0 and ac.flare_reload_progress > 0.0:
			lines.append("FLR RELOAD %d%%" % roundi(ac.flare_reload_progress * 100.0))
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

	# 测量最大宽度（把数字替换成 "0" 再测，避免 label 框每帧抽搐）
	var max_w := 0.0
	for line in lines:
		var w := ac._font.get_string_size(_digit_stable(line), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
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

	var is_player := ac == player_ref
	var alt_color := altitude_tier_color(ac.get_altitude_tier(), ac.flat_altitude and ac.get_altitude_tier() != ac.target_altitude_tier) if is_player else text_color
	for i in range(lines.size()):
		var col := alt_color if (is_player and i == alt_line_idx) else text_color
		ac.draw_string(ac._font, Vector2(5, 12 + i * line_height), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)

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

	# 航点标记 — 双环 + 十字 + 脉冲外圈，显眼且不遮挡目标位置本身
	var d := 11.0
	var marker_color := Color(0.35, 0.85, 1.0, 1.0)
	var fill := Color(marker_color.r, marker_color.g, marker_color.b, 0.22)
	# 中心填充 + 内环
	ac.draw_circle(local_target, d, fill)
	ac.draw_arc(local_target, d, 0, TAU, 32, marker_color, 2.0)
	# 次内环（更细）
	ac.draw_arc(local_target, d * 0.55, 0, TAU, 24, Color(marker_color, 0.9), 1.5)
	# 十字（四个短线，不穿过中心保留目标点清晰）
	var gap := d * 0.45
	var tail := d * 1.55
	var cross_col := Color(marker_color, 0.95)
	ac.draw_line(local_target + Vector2(gap, 0), local_target + Vector2(tail, 0), cross_col, 1.6)
	ac.draw_line(local_target + Vector2(-gap, 0), local_target + Vector2(-tail, 0), cross_col, 1.6)
	ac.draw_line(local_target + Vector2(0, gap), local_target + Vector2(0, tail), cross_col, 1.6)
	ac.draw_line(local_target + Vector2(0, -gap), local_target + Vector2(0, -tail), cross_col, 1.6)
	# 脉冲外圈（缓慢呼吸）
	var pulse_t := fmod(float(Time.get_ticks_msec()) * 0.002, 1.0)
	var pulse_r := d * (1.4 + pulse_t * 0.8)
	var pulse_a := (1.0 - pulse_t) * 0.55
	ac.draw_arc(local_target, pulse_r, 0, TAU, 32, Color(marker_color.r, marker_color.g, marker_color.b, pulse_a), 1.5)
	# 中心小实心点（精确标记点击位置）
	ac.draw_circle(local_target, 2.0, Color(1.0, 1.0, 1.0, 0.95))

## 绘制预测飞行路径 + 末端彩带箭头
## ⚠ 抽动修复：缓存世界坐标。每帧从 ac.speed/bank/heading 的微抖动重算 240 步仿真，
## 末端会放大到 ±20 px 抽动。现在：① 点击新目标或每 1.0s 才重新仿真 ② 平时直接用缓存
## 里的世界点转本地坐标渲染 ③ 起点从"当前飞机位置"插入，保证线从机头出发不断。
static func draw_predicted_path(ac: Aircraft, local_target: Vector2, base_color: Color) -> void:
	# ── 事件驱动刷新判定 ──
	# 关键：绝大多数帧都不重算，缓存保持世界坐标锁定，线和箭头视觉完全静止。
	# progress_idx 单调递增：每帧只在 [progress_idx, progress_idx+SEARCH_WINDOW] 里
	# 找最近点，避免绕圈路径上"起点"和"绕回来的末尾"同时接近飞机时跳来跳去闪烁。
	var need_refresh := false
	var nearest_idx: int = ac.predicted_path_progress_idx
	var nearest_d_sq: float = INF
	var cur_world: Vector2 = ac.global_position

	if ac.predicted_path_cache.size() < 2:
		need_refresh = true
	elif ac.predicted_path_target == Vector2.INF \
			or ac.predicted_path_target.distance_to(ac.target_position) > Aircraft.PREDICTED_PATH_RETARGET_THRESHOLD:
		need_refresh = true
	else:
		# 局部窗口搜索：从 progress_idx 开始往后找最近点
		var start_i: int = clampi(ac.predicted_path_progress_idx, 0, ac.predicted_path_cache.size() - 1)
		var end_i: int = mini(ac.predicted_path_cache.size(), start_i + Aircraft.PREDICTED_PATH_SEARCH_WINDOW)
		nearest_idx = start_i
		nearest_d_sq = cur_world.distance_squared_to(ac.predicted_path_cache[start_i])
		for i in range(start_i + 1, end_i):
			var dsq: float = cur_world.distance_squared_to(ac.predicted_path_cache[i])
			if dsq < nearest_d_sq:
				nearest_d_sq = dsq
				nearest_idx = i
		var drift_sq: float = Aircraft.PREDICTED_PATH_DRIFT_THRESHOLD * Aircraft.PREDICTED_PATH_DRIFT_THRESHOLD
		var remaining: int = ac.predicted_path_cache.size() - nearest_idx
		if nearest_d_sq > drift_sq or remaining < Aircraft.PREDICTED_PATH_MIN_REMAINING:
			need_refresh = true

	if need_refresh:
		_recompute_predicted_path(ac)
		ac.predicted_path_target = ac.target_position
		# 重算后飞机就在 cache[0]，progress 回到 0
		nearest_idx = 0
		ac.predicted_path_progress_idx = 0
	else:
		# 沿缓存单调前进：progress 只能增不能减
		ac.predicted_path_progress_idx = nearest_idx

	var world_points: PackedVector2Array = ac.predicted_path_cache
	if world_points.size() < 2:
		return

	# trim：从最近点往前截取（飞机已飞过的那段不画）
	var points := PackedVector2Array()
	points.append(Vector2.ZERO)   ## 机头本地原点，线从这里顺滑延伸
	for i in range(nearest_idx + 1, world_points.size()):
		points.append(ac.to_local(world_points[i]))
	if points.size() < 2:
		return

	# ── 绘制路径：双层连续线 ──
	var glow := Color(base_color.r, base_color.g, base_color.b, 0.35)
	var core := Color(
		clampf(base_color.r + 0.25, 0.0, 1.0),
		clampf(base_color.g + 0.25, 0.0, 1.0),
		clampf(base_color.b + 0.25, 0.0, 1.0),
		0.85,
	)
	ac.draw_polyline(points, glow, 2.2, true)
	ac.draw_polyline(points, core, 1.0, true)

	# ── 末端箭头：两个凸多边形（矩形轴 + 三角头） ──
	# 方向计算：从末端往回跳几段做 tangent，避开 arrival_dist 插值尾段（那段可能 < 1 px，
	# 用它算方向会得到噪声），这样箭头方向和线的视觉走向稳定一致。
	var tip_pt: Vector2 = points[points.size() - 1]
	# 从末端往回找一段长度足够的切向量。优先跳回 2 段（第 size-3 个点），
	# 如果点太少就退到第 0 个（机头原点）——这样至少拿到"飞机→末端"的总体方向，
	# 不会再退到"飞机→目标"那种和路径脱钩的方向。
	var lookback_idx: int = maxi(0, points.size() - 3)
	var prev_pt: Vector2 = points[lookback_idx]
	var tangent: Vector2 = tip_pt - prev_pt
	var tlen: float = tangent.length()
	# 再兜底：如果连 2 段跳回都拿不到有效 tangent，就尝试更远的跳回
	if tlen < 0.5 and points.size() >= 5:
		prev_pt = points[points.size() - 5]
		tangent = tip_pt - prev_pt
		tlen = tangent.length()
	var fwd: Vector2
	if tlen > 0.5:
		fwd = tangent / tlen
	else:
		# 极端兜底（点太少且全挤在一起）：本地 -Y = 机头朝向，至少方向合理
		fwd = Vector2(0, -1)
	var side: Vector2 = Vector2(-fwd.y, fwd.x)

	var shaft_len := 8.0    ## 轴段（和 core 线同宽的短延长）
	var head_len := 11.0    ## 箭头头段长度
	var barb_w := 6.0       ## 箭翼半展宽
	var neck_w := 1.2       ## 轴宽

	var shaft_start: Vector2 = tip_pt - fwd * (shaft_len + head_len)
	var head_base: Vector2 = tip_pt - fwd * head_len
	var final_tip: Vector2 = tip_pt

	var core_col := Color(
		clampf(base_color.r + 0.25, 0.0, 1.0),
		clampf(base_color.g + 0.25, 0.0, 1.0),
		clampf(base_color.b + 0.25, 0.0, 1.0),
		0.95,
	)
	var glow_col := Color(base_color.r, base_color.g, base_color.b, 0.35)
	var ge := 1.5

	# 1) 矩形轴（凸四边形）—— 光晕 + 核心
	var shaft_glow := PackedVector2Array([
		shaft_start + side * (neck_w + ge * 0.3),
		head_base + side * (neck_w + ge * 0.3),
		head_base - side * (neck_w + ge * 0.3),
		shaft_start - side * (neck_w + ge * 0.3),
	])
	ac.draw_colored_polygon(shaft_glow, glow_col)
	var shaft_core := PackedVector2Array([
		shaft_start + side * neck_w,
		head_base + side * neck_w,
		head_base - side * neck_w,
		shaft_start - side * neck_w,
	])
	ac.draw_colored_polygon(shaft_core, core_col)

	# 2) 三角箭头（凸三角形）—— 光晕 + 核心
	var head_glow := PackedVector2Array([
		head_base + side * (barb_w + ge),
		final_tip + fwd * ge,
		head_base - side * (barb_w + ge),
	])
	ac.draw_colored_polygon(head_glow, glow_col)
	var head_core := PackedVector2Array([
		head_base + side * barb_w,
		final_tip,
		head_base - side * barb_w,
	])
	ac.draw_colored_polygon(head_core, core_col)

## 重新仿真预测路径，写入 ac.predicted_path_cache（世界坐标点序列）。
## 调用频率：目标改变 / 缓存过期（每秒一次）。
static func _recompute_predicted_path(ac: Aircraft) -> void:
	var cache := PackedVector2Array()
	ac.predicted_path_cancel_reached = false
	if ac.target_position == Vector2.INF:
		ac.predicted_path_cache = cache
		return

	# 仿真参数：直接读真实状态。之前搞的输入平滑在新事件驱动架构下已无必要 —— 因为
	# 仿真只在"真的需要"时跑（目标变 / 飞机偏离 / 缓存耗尽），而不是每帧，所以仿真本身
	# 的抖动性根本看不见，缓存一旦写入就世界坐标锁死。
	var sim_heading := ac.heading
	var sim_pos := ac.global_position
	var sim_speed := maxf(ac.speed, 50.0)
	var sim_bank := ac.bank_angle
	var roll_rate_val := ac.params.roll_rate if ac.params else 4.0
	var accel_rate := ac.params.acceleration if ac.params else 50.0
	var decel_rate := ac.params.deceleration if ac.params else 80.0
	var cruise_ms := (ac.params.cruise_speed if ac.params else 900.0) / 3.6
	var stall_base_ms := (ac.params.stall_speed_base if ac.params else 220.0) / 3.6

	var step := 0.08           ## 粗化一档（0.06→0.08）给更多时间
	var max_steps := 400       ## 拉到 32 秒仿真时间，覆盖长途大转弯
	var record_interval := 2

	cache.append(sim_pos)
	var arrival_dist_real: float = maxf(150.0, sim_speed * Aircraft.PIXELS_PER_METER * 2.0)

	for i in range(max_steps):
		var to_tgt := ac.target_position - sim_pos
		var dist_to_tgt := to_tgt.length()
		if dist_to_tgt < arrival_dist_real:
			# 线性插值出精确末端
			if cache.size() >= 1:
				var prev_world: Vector2 = cache[cache.size() - 1]
				var prev_d: float = (ac.target_position - prev_world).length()
				if prev_d > arrival_dist_real and dist_to_tgt < arrival_dist_real:
					var t: float = (prev_d - arrival_dist_real) / maxf(prev_d - dist_to_tgt, 0.001)
					cache.append(prev_world.lerp(sim_pos, t))
				else:
					cache.append(sim_pos)
			ac.predicted_path_cancel_reached = true
			break

		var tgt_heading := atan2(to_tgt.x, -to_tgt.y)
		var hdiff := Aircraft._angle_diff(tgt_heading, sim_heading)

		# Critical-damping 过冲补偿
		if absf(sim_bank) > 0.05 and absf(hdiff) > 0.001:
			var current_turn_rate := Aircraft.GRAVITY * tan(sim_bank) / maxf(sim_speed, 50.0)
			var t_roll := absf(sim_bank) / maxf(roll_rate_val, 0.5)
			var anticipated := current_turn_rate * t_roll * 0.5
			if signf(anticipated) == signf(hdiff):
				if absf(anticipated) >= absf(hdiff):
					hdiff = 0.0
				else:
					hdiff -= anticipated

		# 玩家战术巡航 bank 曲线
		var max_bank_sim := ac._max_bank_angle_at_speed(sim_speed, stall_base_ms)
		var target_bank: float
		var abs_h := absf(hdiff)
		if abs_h < 0.02:
			target_bank = 0.0
		elif abs_h < 0.15:
			var r: float = (abs_h - 0.02) / (0.15 - 0.02)
			target_bank = signf(hdiff) * max_bank_sim * lerpf(0.5, 1.0, r)
		else:
			target_bank = signf(hdiff) * max_bank_sim

		var bank_diff := target_bank - sim_bank
		var max_roll := roll_rate_val * step
		sim_bank += clampf(bank_diff, -max_roll, max_roll)

		if abs(sim_bank) > 0.001:
			var turn_rate := Aircraft.GRAVITY * tan(sim_bank) / maxf(sim_speed, 1.0)
			sim_heading += turn_rate * step
			sim_heading = fmod(sim_heading + PI, TAU) - PI

		var current_g := 1.0 / maxf(cos(sim_bank), 0.01)
		var drag_decel := (current_g - 1.0) * 8.0
		if sim_speed > cruise_ms:
			sim_speed -= (decel_rate * 0.5 + drag_decel) * step
		else:
			sim_speed += accel_rate * 0.3 * step
		sim_speed = maxf(sim_speed, stall_base_ms * 1.3)

		var vel := Vector2(sin(sim_heading), -cos(sim_heading)) * sim_speed * Aircraft.PIXELS_PER_METER
		sim_pos += vel * step

		if i % record_interval == 0:
			cache.append(sim_pos)

	ac.predicted_path_cache = cache
