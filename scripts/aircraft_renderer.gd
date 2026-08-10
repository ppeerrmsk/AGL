class_name AircraftRenderer
extends RefCounted

const AircraftSilhouetteCatalog = preload("res://scripts/aircraft_silhouette_catalog.gd")

## 玩家飞机全局引用（由 main.gd / survivor_mode.gd 在玩家生成/销毁时维护）
## draw_data_label 里每帧为每架飞机算 RNG 用，避免在 _draw 里 O(N) 扫 parent.get_children()
static var player_ref: Aircraft = null

const LABEL_COMPACT_ENTER_SCALE: float = 0.35
const LABEL_COMPACT_EXIT_SCALE: float = 0.40

## 锁定框以现有尺寸为高空上限，地面与低空目标按真实高度连续缩小。
const LOCK_BOX_ALTITUDE_SCALE_KEYS := [
	[0.0, 0.55],
	[2000.0, 0.70],
	[5500.0, 0.85],
	[10000.0, 1.00],
]


## 生命周期边界净化：先用 Variant 接住可能已释放的对象，再验证、收窄类型。
## 不能直接赋给 `var ac: Aircraft` 后再判有效；Godot 会先在强类型赋值阶段报错。
static func safe_aircraft_ref(value: Variant) -> Aircraft:
	if typeof(value) != TYPE_OBJECT or not is_instance_valid(value):
		return null
	if not (value is Aircraft):
		return null
	return value as Aircraft


## 安全读 player_ref：自动清理 freed 引用。所有消费者必须走此 getter。
static func safe_player_ref() -> Aircraft:
	var candidate: Variant = player_ref
	var safe_ref: Aircraft = safe_aircraft_ref(candidate)
	if safe_ref == null:
		player_ref = null
	return safe_ref

## 世界内 CanvasItem 上的 HUD 符号使用这个比例抵消实际视口缩放。
## 读 viewport transform 而不是 CameraController.target_zoom，才能覆盖平滑缩放、
## 电影镜头系数以及其它已经应用到 Canvas 的变换。
static func inverse_screen_scale_for(view_scale: float) -> float:
	return 1.0 / maxf(absf(view_scale), 0.01)


static func screen_space_inverse_scale(item: CanvasItem) -> float:
	if item == null or not item.is_inside_tree():
		return 1.0
	return inverse_screen_scale_for(item.get_viewport_transform().get_scale().x)


static func lock_box_altitude_scale_for(altitude_m: float) -> float:
	var altitude := maxf(altitude_m, 0.0)
	for i in range(LOCK_BOX_ALTITUDE_SCALE_KEYS.size() - 1):
		var lo: Array = LOCK_BOX_ALTITUDE_SCALE_KEYS[i]
		var hi: Array = LOCK_BOX_ALTITUDE_SCALE_KEYS[i + 1]
		if altitude <= float(hi[0]):
			var span := maxf(float(hi[0]) - float(lo[0]), 0.001)
			var t := clampf((altitude - float(lo[0])) / span, 0.0, 1.0)
			return lerpf(float(lo[1]), float(hi[1]), t)
	return float(LOCK_BOX_ALTITUDE_SCALE_KEYS[-1][1])


static func lock_box_altitude_scale(node: Node2D) -> float:
	if node is CombatUnit:
		return lock_box_altitude_scale_for((node as CombatUnit).altitude)
	return 1.0


## 标签 LOD 只跟相机/画布缩放走，不能把窗口拉伸倍率算进去。
## get_viewport_transform() 同时包含 Camera2D zoom 与 canvas_items 的窗口拉伸；
## 最大化到 4K 时后者约为 2.0，会把最远 zoom 0.20 抬成 0.40，导致永远进不了 0.35 简略档。
static func label_lod_scale_for(view_scale: float, stretch_scale: float) -> float:
	return absf(view_scale) / maxf(absf(stretch_scale), 0.01)


static func label_lod_scale(item: CanvasItem) -> float:
	if item == null or not item.is_inside_tree():
		return 1.0
	var viewport: Viewport = item.get_viewport()
	var stretch_scale: float = 1.0
	if viewport != null:
		stretch_scale = viewport.get_stretch_transform().get_scale().x
	return label_lod_scale_for(
		item.get_viewport_transform().get_scale().x, stretch_scale)


## 远景标签迟滞：缩到 0.35 进入，拉回 0.40 退出。
static func next_compact_label_state(was_compact: bool, view_scale: float) -> bool:
	if was_compact:
		return view_scale < LABEL_COMPACT_EXIT_SCALE
	return view_scale <= LABEL_COMPACT_ENTER_SCALE


static func compact_label_visible(compact_state: bool, force_full: bool) -> bool:
	return compact_state and not force_full


static func should_draw_compact_label(ac: Aircraft) -> bool:
	var view_scale: float = label_lod_scale(ac)
	ac._compact_data_label_active = next_compact_label_state(
		ac._compact_data_label_active, view_scale)
	# Alt 只临时覆盖显示，不重置迟滞状态；松开即可回到当前缩放档。
	return compact_label_visible(ac._compact_data_label_active,
		Input.is_key_pressed(KEY_ALT))

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
##
## 不再因 flat_altitude 走离散 tier 跳变 —— 始终走连续插值，跟着真实 altitude 米数走
## 高度只提供温和空间感；机型真实尺寸由 visual_model_scale 独立处理。
## 这样玩家爬升/俯冲时图标会平滑放大缩小，能直观看到高度变化
const ALT_SCALE_KEYS := [
	[0.0, 0.85],
	[2000.0, 0.90],   # CombatUnit.TIER_ALTITUDE.LOW
	[5500.0, 1.00],   # CombatUnit.TIER_ALTITUDE.MID
	[10000.0, 1.15],  # CombatUnit.TIER_ALTITUDE.HIGH
	[15000.0, 1.20],  # 接近 max_altitude 上限
]


static func altitude_base_scale(ac: Aircraft) -> float:
	var alt: float = ac.altitude
	# 在锚点表中线性插值
	for i in range(ALT_SCALE_KEYS.size() - 1):
		var lo: Array = ALT_SCALE_KEYS[i]
		var hi: Array = ALT_SCALE_KEYS[i + 1]
		if alt <= float(hi[0]):
			var t := (alt - float(lo[0])) / maxf(float(hi[0]) - float(lo[0]), 0.001)
			return lerpf(float(lo[1]), float(hi[1]), clampf(t, 0.0, 1.0))
	# 超出最高锚点
	return float(ALT_SCALE_KEYS[ALT_SCALE_KEYS.size() - 1][1])

## 世界真实尺寸经过压缩幂律映射，既保留轰炸机/直升机的相对比例，又保证缩放后可读。
## 目标像素 = 7.9 × max(长度, 翼展/旋翼直径)^0.55；再除以各轮廓的原生最大尺寸。
static func visual_model_scale(ac: Aircraft) -> float:
	if ac.params == null or ac.get_meta("silhouette", "") == "mother_goose":
		return 1.0
	var real_extent_m: float = maxf(ac.params.visual_length_m, ac.params.visual_span_m)
	var desired_px: float = 7.9 * pow(maxf(real_extent_m, 1.0), 0.55)
	var silhouette: String = str(ac.get_meta("silhouette", ""))
	var native_px: float = 36.0
	match silhouette:
		"bomber": native_px = 70.0
		"apache": native_px = 32.0
		"chinook": native_px = 44.0
	return desired_px / native_px

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

# 武器/装备行的品牌色 —— 与右下角"机体&武器栏"（survivor_hud._update_status_panel）共用同一套色板。
# 飞机旁边"状态栏"data label 里的同名行直接调用这里，避免两边色码漂移。
# 详见 docs/architecture/known-seams.md（HUD 配色统一）。
static func _wpn_color(tag: String, ctx: Dictionary = {}) -> Color:
	if tag == "MSL_RELOAD":
		return Color.html("#5599ff")
	elif tag == "SP_RELOAD":
		return Color.html("#ffaa55")
	elif tag == "GUN_RELOAD":
		return Color.html("#aa7733")
	elif tag == "FLR_RELOAD":
		var empty_flash: bool = int(Time.get_ticks_msec() / 180) % 2 == 0
		return Color.html("#ff4433") if empty_flash else Color.html("#ffbb33")
	elif tag == "FLR_READY":
		return Color.html("#ffdd66")
	elif tag == "FLR_EMPTY":
		return Color.html("#666666")
	elif tag == "RAIL_CHG":
		return Color.html("#aaccff")
	elif tag == "RAIL_CD":
		return Color.html("#aa8833")
	elif tag == "RAIL_READY":
		return Color.html("#88ddff")
	elif tag == "LSR_OVERHEAT" or tag == "STALL":
		var flash: bool = int(Time.get_ticks_msec() / 250) % 2 == 0
		return Color.html("#ff3322") if flash else Color.html("#ff7733")
	elif tag == "LSR_HEAT":
		var pct: int = int(ctx.get("pct", 0))
		if pct < 50:
			return Color.html("#88dd88")
		elif pct < 80:
			return Color.html("#ffcc33")
		else:
			return Color.html("#ff6633")
	return Color.WHITE


## 当前操控机保留武器品牌色；敌机、僚机与第三方友军的导弹装填统一用白字。
static func weapon_label_color(tag: String, is_controlled: bool,
		ctx: Dictionary = {}) -> Color:
	if not is_controlled and (tag == "MSL_RELOAD" or tag == "SP_RELOAD"):
		return Color.WHITE
	return _wpn_color(tag, ctx)


static func _status_effect_is_active(ac: Aircraft, sid: String, timed: bool,
		include_direct_invulnerable: bool) -> bool:
	if timed:
		return true
	match sid:
		StatusEffects.INVINCIBLE:
			return ac.status_invincible_active or (include_direct_invulnerable and ac.invulnerable)
		StatusEffects.STEALTH:
			return ac.status_stealth_active or ac.is_cloaked
		StatusEffects.BLOODLUST:
			return ac.status_bloodlust_active
		StatusEffects.OVERLOAD:
			return ac.status_overload_active
		StatusEffects.FEAR:
			return ac.status_fear_active
		StatusEffects.JAM:
			return ac.status_jam_active
		StatusEffects.SLOW:
			return ac.status_slow_active
	return false


## 完整、精简与折叠标签共用同一状态快照，避免缩放 LOD 后漏掉 buff/debuff。
static func status_label_entries(ac: Aircraft,
		include_direct_invulnerable: bool = false) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for sid in StatusEffects.DISPLAY_ORDER:
		var timed: bool = ac.status_effects.has(sid)
		if not _status_effect_is_active(ac, sid, timed, include_direct_invulnerable):
			continue
		var label := StatusEffects.english_label(sid)
		if timed:
			var remaining: float = float(ac.status_effects[sid])
			var initial: float = float(ac.status_initial_durations.get(sid, remaining))
			var pct := clampi(roundi(remaining / maxf(initial, 0.001) * 100.0), 0, 100)
			label += " %d%%" % pct
		entries.append({
			"id": sid,
			"text": label,
			"color": StatusEffects.icon_color(sid),
		})
	return entries


static func _append_status_label_lines(ac: Aircraft, lines: PackedStringArray,
		color_indices: Dictionary, include_direct_invulnerable: bool = false) -> void:
	for entry in status_label_entries(ac, include_direct_invulnerable):
		color_indices[lines.size()] = entry["color"]
		lines.append(entry["text"])

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
	var radar_r := ac.effective_radar_range_px()
	var half_deg := ac.params.radar_half_angle if ac.params else 30.0
	var half_rad := deg_to_rad(half_deg)

	# 扇形在本地坐标绘制，飞机 rotation = heading
	# 本地坐标中飞机朝上（-Y），所以扇形中心轴 = -Y 方向 = -PI/2
	var center_angle := -PI / 2.0
	var start_angle := center_angle - half_rad
	var end_angle := center_angle + half_rad
	var segments := 24

	# 扇形颜色（FactionPalette 三分支：玩家青 / ALLY 海绿 / 敌红）
	var cone_color: Color = GameConstants.team_radar_color(ac.team, 0.12)

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

## 副导弹槽锁定锥（仅装备副弹的玩家 + hover 时可见）
## 完全独立于主雷达锥：橙色更暖、透明度低，画在主锥之上
## 仅 hover 显示：避免战斗中长期占据视觉，与主雷达锥同遵守 hover-only 规则
## 详见 docs/changelogs/2026-05-10-secondary-slot-revival.md
static func draw_secondary_lock_cone(ac: Aircraft) -> void:
	if ac.params == null: return
	if not ac.secondary_missile_enabled: return
	if not ac.is_hovered: return  # hover-only：避免视觉污染（与主雷达 draw_radar_cone 同规则）
	var sec: MissileParams = ac.params.secondary_missile
	if sec == null: return

	var half_deg: float = sec.lock_cone_half_angle_deg if sec.lock_cone_half_angle_deg > 0.0 \
			else (ac.params.radar_half_angle if ac.params else 30.0)
	var radar_r: float = sec.lock_max_range_px if sec.lock_max_range_px > 0.0 \
			else ac.effective_radar_range_px()
	var half_rad: float = deg_to_rad(half_deg)

	# 本地坐标飞机朝 -Y，扇形中心轴 = -PI/2
	var center_angle := -PI / 2.0
	var start_angle := center_angle - half_rad
	var end_angle := center_angle + half_rad
	var segments := 24

	# 橙色（暖色）半透明，与主雷达蓝色 / fear 紫色都区分
	# 装填中褪色（提示玩家副槽不可用）/ 弹尽更淡
	var alpha: float
	if ac._secondary_reload_active:
		alpha = 0.10
	elif ac.secondary_missiles_remaining <= 0:
		alpha = 0.06
	else:
		alpha = 0.18
	var cone_color := Color(1.0, 0.55, 0.15, alpha)

	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(segments + 1):
		var angle := start_angle + (end_angle - start_angle) * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * radar_r)

	ac.draw_colored_polygon(points, cone_color)

	# 边缘线 + 弧线
	var edge_color := Color(1.0, 0.55, 0.15, alpha * 2.5)
	ac.draw_line(Vector2.ZERO, points[1], edge_color, 1.0, true)
	ac.draw_line(Vector2.ZERO, points[points.size() - 1], edge_color, 1.0, true)
	for i in range(1, points.size() - 1):
		ac.draw_line(points[i], points[i + 1], edge_color, 1.0, true)

## 副槽锁定指示：在已锁定满的目标上画橙色括号（玩家世界坐标系）
## 长期可见（与锥不同）—— 给玩家"QMAAM 已就绪可以放手"的明确反馈
## 注：此函数在 ac 的本地坐标系 _draw 里调用，需要 to_local 转换
static func draw_secondary_lock_indicators(ac: Aircraft) -> void:
	if ac.params == null: return
	if not ac.secondary_missile_enabled: return
	var sec: MissileParams = ac.params.secondary_missile
	if sec == null: return
	# 弹空 / 装填中：不显示（避免误导玩家以为可以打）
	if ac.secondary_missiles_remaining <= 0 or ac._secondary_reload_active:
		return
	if ac._secondary_cooldown > 0.05:
		return

	var lock_time_val: float = ac.params.lock_time
	var base_radius := 18.0  # 当前尺寸是高空目标的最大尺寸
	# 颜色：用 QMAAM 同色橙
	var ring_color := Color(1.0, 0.65, 0.15, 0.95)
	var fill_color := Color(1.0, 0.55, 0.15, 0.22)
	var inv_zoom: float = screen_space_inverse_scale(ac)
	var inv_rot: float = -ac.rotation

	for unit in ac.secondary_radar_targets.keys():
		if unit == null or not is_instance_valid(unit): continue
		var prog: float = ac.secondary_radar_targets[unit]
		if prog < lock_time_val: continue  # 仅锁满显示
		# 光学隐形：不得在隐形机位置画锁定框（否则等于把隐形目标的精确坐标画给玩家）。
		# 累积侧已在 update_secondary_radar 清除，但那是 0.5s tick —— 这里兜住 tick 间隙
		if unit is Aircraft and (unit as Aircraft).is_cloaked: continue
		# 锚点保留在目标世界位置；只对锚点周围的括号几何做反缩放。
		var local_pos: Vector2 = ac.to_local(unit.global_position)
		var altitude_scale := lock_box_altitude_scale(unit)
		var radius := base_radius * altitude_scale
		ac.draw_set_transform(local_pos, inv_rot, Vector2.ONE * inv_zoom)
		# 4 个角的 corner brackets（开口朝内）
		var arm := 6.0 * altitude_scale
		var corners := [
			[Vector2(-radius, -radius), Vector2(arm, 0), Vector2(0, arm)],   # 左上
			[Vector2(radius, -radius),  Vector2(-arm, 0), Vector2(0, arm)],  # 右上
			[Vector2(-radius, radius),  Vector2(arm, 0), Vector2(0, -arm)],  # 左下
			[Vector2(radius, radius),   Vector2(-arm, 0), Vector2(0, -arm)], # 右下
		]
		# 浅填充（+ 4 个 corner，明确"锁定"语义）
		ac.draw_circle(Vector2.ZERO, radius - 4.0 * altitude_scale, fill_color)
		for c in corners:
			var origin: Vector2 = c[0]
			ac.draw_line(origin, origin + c[1], ring_color, 1.5, true)
			ac.draw_line(origin, origin + c[2], ring_color, 1.5, true)
	ac.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 玩家光环范围预览（hover 玩家时显示）：
##   - jam_aura：全圆绿色 ring
##   - rear_aura_slow：后半球弧（dot(my_back, to_enemy) > 0.3 → ±72.5°）
##   - fear_on_lock（凝视压迫）：与雷达锥同形状的紫色外弧（持续锁定 N 秒后施 FEAR）
## 仅在 ac.team == 0 且 ac.is_hovered 时绘制；本地坐标里飞机朝 -Y，所以"back"=+Y（角度 PI/2）
static func draw_aura_ranges(ac: Aircraft) -> void:
	if ac.team != 0 or not ac.is_hovered:
		return
	if ac.jam_aura_radius_px > 0.0:
		var jam_col := Color(0.40, 1.00, 0.55, 0.55)
		ac.draw_arc(Vector2.ZERO, ac.jam_aura_radius_px, 0.0, TAU, 48, jam_col, 1.2, true)
	if ac.rear_aura_slow_radius_px > 0.0:
		# dot > 0.3 → 半角 acos(0.3) ≈ 72.54°，关于 +Y（local back）
		var slow_col := Color(0.55, 0.80, 1.00, 0.55)
		var half := deg_to_rad(72.54)
		var center := PI / 2.0  # local +Y = back
		ac.draw_arc(Vector2.ZERO, ac.rear_aura_slow_radius_px,
			center - half, center + half, 32, slow_col, 1.2, true)
	# 凝视压迫：技能没有独立"AOE 范围" —— 真实触发条件 = 玩家雷达持续锁中某敌 N 秒，
	# 所以"视线范围"就是雷达锁定锥本身。在 draw_radar_cone 已画的淡色填充之上，
	# 叠一道紫色外弧 + 中轴线 + 边缘线，明示"在这个锥里被盯久了会上 FEAR"。
	if ac.fear_on_lock_threshold > 0.0 and ac.params:
		var radar_r: float = ac.effective_radar_range_px()
		var half_rad: float = deg_to_rad(ac.params.radar_half_angle)
		var fear_center: float = -PI / 2.0   # 本地朝 -Y = 机头方向
		var fear_col := Color(0.80, 0.45, 0.95, 0.65)
		ac.draw_arc(Vector2.ZERO, radar_r,
			fear_center - half_rad, fear_center + half_rad, 32, fear_col, 1.5, true)
		# 两条边缘线（从飞机指向锥端点），让锥角清楚
		var edge_a := Vector2(cos(fear_center - half_rad), sin(fear_center - half_rad)) * radar_r
		var edge_b := Vector2(cos(fear_center + half_rad), sin(fear_center + half_rad)) * radar_r
		ac.draw_line(Vector2.ZERO, edge_a, fear_col, 1.0, true)
		ac.draw_line(Vector2.ZERO, edge_b, fear_col, 1.0, true)

## 敌方机炮意图锥身份门：Mother Goose 蜂群降噪，其他敌机（含普通无人机/MQ-X）照常显示。
static func should_show_enemy_gun_threat(ac: Aircraft) -> bool:
	if ac.team == 0 or ac._gun_threat_timer < Aircraft.GUN_THREAT_DISPLAY_DELAY:
		return false
	return ac.get_meta(&"category", "") != "boss_mother_goose_uav"


static func draw_gun_cone(ac: Aircraft) -> void:
	if not ac.params or not ac.params.gun:
		return
	# 友方 hover 时显示参考锥；敌方对玩家提交机炮攻击 ≥0.3s 显示威胁锥（同为橙黄）
	var show_friendly: bool = (ac.team == 0 and ac.is_hovered)
	var show_enemy_threat: bool = should_show_enemy_gun_threat(ac)
	if not show_friendly and not show_enemy_threat:
		return
	# 敌方锥开火期间淡出（见 Aircraft._update_gun_threat_indicator）；全透时直接跳过绘制
	var fade: float = ac._gun_threat_fade if show_enemy_threat else 1.0
	if fade <= 0.01:
		return
	var gun_r := ac.effective_gun_range_m() * Aircraft.PIXELS_PER_METER
	var half_rad := deg_to_rad(ac.effective_gun_cone_half_angle_deg())
	if ac.gunship_mode_active:
		var ring_color := Color(0.9, 0.7, 0.2, 0.55)
		ac.draw_circle(Vector2.ZERO, gun_r, Color(0.9, 0.7, 0.2, 0.07))
		ac.draw_arc(Vector2.ZERO, gun_r, 0.0, TAU, 64, ring_color, 1.0, true)
		return

	var center_angle := -PI / 2.0
	var start_angle := center_angle - half_rad
	var end_angle := center_angle + half_rad
	var segments := 16

	# 友方/敌方威胁同一橙黄色锥。敌方锥会同时挂在多架敌机上，太实会糊住战场 ——
	# 2026-07-28 从 0.22 调淡到 0.12，再乘开火淡出系数
	var cone_alpha: float = (0.12 * fade) if show_enemy_threat else 0.15
	var cone_color := Color(0.9, 0.7, 0.2, cone_alpha)

	var points := PackedVector2Array()
	points.append(Vector2.ZERO)
	for i in range(segments + 1):
		var angle := start_angle + (end_angle - start_angle) * float(i) / float(segments)
		points.append(Vector2(cos(angle), sin(angle)) * gun_r)

	ac.draw_colored_polygon(points, cone_color)

	var edge_color := Color(cone_color, (0.24 * fade) if show_enemy_threat else 0.4)
	ac.draw_line(Vector2.ZERO, points[1], edge_color, 1.0, true)
	ac.draw_line(Vector2.ZERO, points[points.size() - 1], edge_color, 1.0, true)
	for i in range(1, points.size() - 1):
		ac.draw_line(points[i], points[i + 1], edge_color, 1.0, true)

static func draw_lock_indicator(ac: Aircraft) -> void:
	var p: float = clampf(ac.incoming_lock_progress, 0.0, 1.0)
	if p <= 0.0 and not ac.is_locked:
		return
	# 反旋转 + 反缩放：方框始终对齐屏幕并保持固定屏幕尺寸。
	var inv_rot: float = -ac.rotation
	var inv_zoom: float = screen_space_inverse_scale(ac)
	ac.draw_set_transform(Vector2.ZERO, inv_rot, Vector2.ONE * inv_zoom)
	draw_lock_box(ac, p, ac.is_locked)
	ac.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 通用锁定方框绘制（Aircraft / GroundUnit 共用）
## progress (0..1) 驱动动画：旋转一圈 + 从大到小收缩，绿色；locked=true 时切红色静止
static func draw_lock_box(node: Node2D, progress: float, locked: bool) -> void:
	var altitude_scale := lock_box_altitude_scale(node)
	if locked:
		var blink: float = absf(sin(Time.get_ticks_msec() * 0.006))
		var alpha: float = lerpf(0.55, 1.0, blink)
		var red: Color = Color(1.0, 0.15, 0.1, alpha)
		_draw_corner_brackets(node, 22.0 * altitude_scale, red, 0.0)
	else:
		var size: float = lerpf(68.0, 24.0, progress) * altitude_scale
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
	var s := altitude_base_scale(ac) * visual_model_scale(ac)
	var pitch_compress := lerpf(1.0, Aircraft.VERTICAL_BREAK_PITCH_MIN_SCALE, ac._active_special_pitch_visual)
	# 机头前方小闪光
	var tip := Vector2(0, -20.0 * s * pitch_compress)
	ac.draw_circle(tip, 4.0 * s, flash_color)
	var flash2 := Color(1.0, 0.6, 0.1, flash_alpha * 0.5)
	ac.draw_circle(tip, 7.0 * s, flash2)

static func draw_afterburner_glow(ac: Aircraft) -> void:
	var flicker := randf_range(0.7, 1.0)
	var glow_color := Color(1.0, 0.5, 0.1, 0.8 * flicker)
	var core_color := Color(1.0, 0.85, 0.4, 0.9 * flicker)
	# 基础大小与机身图标一致（乘 altitude_base_scale）
	var s := altitude_base_scale(ac) * visual_model_scale(ac)
	# 再叠 cobra/herbst 各向同性收缩
	var sy_compress: float = s
	var _mv := ac.get_maneuver()
	if _mv and _mv.visual_offset > 0.0:
		sy_compress *= lerpf(1.0, 0.35, _mv.visual_offset)
	var _hm := ac.get_herbst()
	if _hm and _hm.visual_offset > 0.0:
		sy_compress *= lerpf(1.0, 0.4, _hm.visual_offset)
	# 垂直越过的俯仰投影同步压缩尾喷口纵向锚点，避免尾焰脱离机体。
	sy_compress *= lerpf(1.0, Aircraft.VERTICAL_BREAK_PITCH_MIN_SCALE, ac._active_special_pitch_visual)
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

## DEADAIR 暴露八段环；只在跨段时由 CombatUnit 请求重绘。
static func draw_deadair_exposure(ac: CombatUnit) -> void:
	var ratio := ac.deadair_exposure_ratio
	if ac.is_destroyed or ratio <= 0.0:
		return
	var zoom_scale := ac.get_viewport_transform().get_scale()
	var inv_zoom: float = 1.0 / maxf(zoom_scale.x, 0.01)
	var radius := 25.0 * inv_zoom
	var width := 2.4 * inv_zoom
	var lit := ceili(clampf(ratio, 0.0, 1.0) * 8.0)
	var transform := Transform2D(-ac.rotation, Vector2.ZERO)
	ac.draw_set_transform_matrix(transform)
	for i in range(8):
		var start := -PI * 0.5 + TAU * float(i) / 8.0 + 0.06
		var finish := -PI * 0.5 + TAU * float(i + 1) / 8.0 - 0.06
		var color := Color(0.68, 0.08, 0.47, 0.95) if i < lit else Color(0.22, 0.05, 0.18, 0.42)
		ac.draw_arc(Vector2.ZERO, radius, start, finish, 5, color, width, true)
	ac.draw_set_transform_matrix(Transform2D.IDENTITY)


## 状态效果条：单位正上方一摞水平进度条（buff 在前 / debuff 在后）
## 每条 = 半透明背景 + 按 remaining/initial 比例缩减的彩色填充 + 中文标签
## 抵消飞机 rotation → 始终水平 / 抵消摄像机 zoom → 大小固定不随缩放
## 接受任何 CombatUnit（飞机 / 地面单位 / 船等），地面单位通常只显示 JAM
static func draw_status_icons(ac: CombatUnit) -> void:
	draw_deadair_exposure(ac)
	if ac.is_destroyed or ac.status_effects.is_empty():
		return
	var active_ids: Array[String] = []
	for id in StatusEffects.DISPLAY_ORDER:
		if ac.status_effects.has(id):
			active_ids.append(id)
	if active_ids.is_empty():
		return

	# 抵消摄像机缩放：UI 元素保持固定屏幕尺寸（与 draw_data_label 同思路）
	var zoom_scale := ac.get_viewport_transform().get_scale()
	var inv_zoom: float = 1.0 / maxf(zoom_scale.x, 0.01)
	var w := StatusEffects.BAR_WIDTH * inv_zoom
	var h := StatusEffects.BAR_HEIGHT * inv_zoom
	var gap := StatusEffects.BAR_GAP * inv_zoom
	var step := h + gap

	# 抵消飞机 rotation；最底下的条贴近 BAR_OFFSET_Y，往上摞
	var t := Transform2D(-ac.rotation, Vector2.ZERO)
	ac.draw_set_transform_matrix(t)

	var font := ThemeDB.fallback_font
	var font_size := StatusEffects.BAR_FONT_SIZE
	var x0 := -w * 0.5
	var n := active_ids.size()

	for i in n:
		var id: String = active_ids[i]
		var col: Color = StatusEffects.icon_color(id)
		# 第 0 条最靠近飞机，第 n-1 条最靠上
		var y := StatusEffects.BAR_OFFSET_Y * inv_zoom - step * float(i)
		var bg_rect := Rect2(x0, y, w, h)

		# 背景（半透明黑）
		ac.draw_rect(bg_rect, Color(0.05, 0.05, 0.05, 0.75), true)

		# 进度填充（按 remaining/initial 比例从左往右铺，右侧空出表示已消耗）
		var remaining: float = float(ac.status_effects[id])
		var initial: float = float(ac.status_initial_durations.get(id, remaining))
		var ratio: float = clampf(remaining / maxf(initial, 0.001), 0.0, 1.0)
		if ratio > 0.0:
			var fill_w: float = w * ratio
			var fill_col := Color(col.r, col.g, col.b, 0.85)
			ac.draw_rect(Rect2(x0, y, fill_w, h), fill_col, true)

		# 边框（buff 金 / debuff 红）
		var border_col: Color = Color(1.0, 0.85, 0.2, 0.9) if StatusEffects.is_buff(id) else Color(0.95, 0.2, 0.2, 0.9)
		ac.draw_rect(bg_rect, border_col, false, 1.0 * inv_zoom)

		# 标签：黑底色高亮，居中显示中文短标签
		var label := StatusEffects.short_label(id)
		var sized_font := float(font_size) * inv_zoom
		var text_w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, int(sized_font)).x
		var text_pos := Vector2(x0 + (w - text_w) * 0.5, y + h - h * 0.22)
		# 描边（黑色 1px 偏移 4 方向）
		var outline := Color(0, 0, 0, 0.9)
		var off: float = 1.0 * inv_zoom
		for dx in [-off, off]:
			for dy in [-off, off]:
				ac.draw_string(font, text_pos + Vector2(dx, dy), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, int(sized_font), outline)
		ac.draw_string(font, text_pos, label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(sized_font), Color.WHITE)

	ac.draw_set_transform_matrix(Transform2D.IDENTITY)


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
	var base_scale: float = altitude_base_scale(ac) * visual_model_scale(ac)

	# 滚转变形（常规 bank + 规避时的原地滚转相位）
	var bank_compress := cos(ac.bank_angle + ac._evade_roll_phase + ac._active_special_roll_visual)
	var sx := base_scale * bank_compress
	var sy := base_scale
	# 垂直越过：俯视投影只压缩机体纵轴，保留翼展，明确表现抬头/压头姿态。
	sy *= lerpf(1.0, Aircraft.VERTICAL_BREAK_PITCH_MIN_SCALE, ac._active_special_pitch_visual)
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

	# 每个真实/概念机型只消费一张白色 alpha PNG；阵营与王牌差异统一由参数颜色着色。
	# 未登记的 UGC/临时探针安全回退到下方旧 polygon 绘制。
	if AircraftSilhouetteCatalog.draw_icon(ac, color, size, xform):
		if ac.selected:
			var ring_color := color
			ring_color.a = 0.5
			var ring_scale := AircraftSilhouetteCatalog.draw_scale_for(ac)
			ac.draw_arc(Vector2.ZERO, size * 1.8 * base_scale * ring_scale, 0, TAU, 48, ring_color, 1.5)
		return

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
	# 忠诚僚机无人机外观（XQ-58 Valkyrie / MQ-28 Ghost Bat 灵感）：
	# 比战斗机小 ~40% + 尖锐机头 + 高后掠三角翼 + V 形尾翼
	if silhouette == "drone":
		draw_drone_icon(ac, color, outline_color, size, base_scale, xform)
		return
	# Mother Goose 巨型空中航母（Arsenal Bird Liberty 灵感）：宽阔飞翼 + 6 发动机舱 + 中部船桥
	if silhouette == "mother_goose":
		draw_mother_goose_icon(ac, color, outline_color, size, base_scale, xform)
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

	# 常规科技树敌版只替换既有 5 个多边形的顶点；不增加 CanvasItem/draw 次数或逐帧扫描。
	match silhouette:
		"deadair":
			# 双菱形 EW 核心：短机身、宽后掠翼，和 Snowblind/普通战机在轮廓上可区分。
			body = PackedVector2Array([Vector2(0, -size * 0.85), Vector2(size * 0.34, -size * 0.18), Vector2(size * 0.26, size * 0.72), Vector2(0, size), Vector2(-size * 0.26, size * 0.72), Vector2(-size * 0.34, -size * 0.18)])
			wing_r = PackedVector2Array([Vector2(size * 0.20, -size * 0.28), Vector2(size * 1.35, size * 0.12), Vector2(size * 0.78, size * 0.55), Vector2(size * 0.20, size * 0.30)])
			wing_l = PackedVector2Array([Vector2(-size * 0.20, -size * 0.28), Vector2(-size * 1.35, size * 0.12), Vector2(-size * 0.78, size * 0.55), Vector2(-size * 0.20, size * 0.30)])
		"delta":
			wing_r = PackedVector2Array([Vector2(size * 0.15, -size * 0.35), Vector2(size * 1.2, size * 0.55), Vector2(size * 0.18, size * 0.38)])
			wing_l = PackedVector2Array([Vector2(-size * 0.15, -size * 0.35), Vector2(-size * 1.2, size * 0.55), Vector2(-size * 0.18, size * 0.38)])
		"canard_delta":
			wing_r = PackedVector2Array([Vector2(size * 0.14, -size * 0.48), Vector2(size * 0.55, -size * 0.30), Vector2(size * 0.25, -size * 0.18), Vector2(size * 1.15, size * 0.48), Vector2(size * 0.18, size * 0.35)])
			wing_l = PackedVector2Array([Vector2(-size * 0.14, -size * 0.48), Vector2(-size * 0.55, -size * 0.30), Vector2(-size * 0.25, -size * 0.18), Vector2(-size * 1.15, size * 0.48), Vector2(-size * 0.18, size * 0.35)])
		"swing_wing":
			wing_r = PackedVector2Array([Vector2(size * 0.18, -size * 0.05), Vector2(size * 1.25, size * 0.50), Vector2(size * 0.85, size * 0.58), Vector2(size * 0.18, size * 0.20)])
			wing_l = PackedVector2Array([Vector2(-size * 0.18, -size * 0.05), Vector2(-size * 1.25, size * 0.50), Vector2(-size * 0.85, size * 0.58), Vector2(-size * 0.18, size * 0.20)])
		"attacker":
			body = PackedVector2Array([Vector2(0, -size), Vector2(size * 0.24, -size * 0.55), Vector2(size * 0.28, size * 0.75), Vector2(0, size), Vector2(-size * 0.28, size * 0.75), Vector2(-size * 0.24, -size * 0.55)])
			wing_r = PackedVector2Array([Vector2(size * 0.22, -size * 0.05), Vector2(size * 1.25, size * 0.02), Vector2(size * 1.15, size * 0.28), Vector2(size * 0.22, size * 0.25)])
			wing_l = PackedVector2Array([Vector2(-size * 0.22, -size * 0.05), Vector2(-size * 1.25, size * 0.02), Vector2(-size * 1.15, size * 0.28), Vector2(-size * 0.22, size * 0.25)])
		"stealth":
			body = PackedVector2Array([Vector2(0, -size * 1.1), Vector2(size * 0.34, -size * 0.28), Vector2(size * 0.28, size * 0.75), Vector2(0, size * 0.9), Vector2(-size * 0.28, size * 0.75), Vector2(-size * 0.34, -size * 0.28)])
			wing_r = PackedVector2Array([Vector2(size * 0.20, -size * 0.25), Vector2(size * 1.25, size * 0.28), Vector2(size * 0.55, size * 0.52), Vector2(size * 0.22, size * 0.32)])
			wing_l = PackedVector2Array([Vector2(-size * 0.20, -size * 0.25), Vector2(-size * 1.25, size * 0.28), Vector2(-size * 0.55, size * 0.52), Vector2(-size * 0.22, size * 0.32)])
		"vtol":
			wing_r = PackedVector2Array([Vector2(size * 0.18, -size * 0.10), Vector2(size * 0.90, size * 0.08), Vector2(size * 0.78, size * 0.35), Vector2(size * 0.18, size * 0.22)])
			wing_l = PackedVector2Array([Vector2(-size * 0.18, -size * 0.10), Vector2(-size * 0.90, size * 0.08), Vector2(-size * 0.78, size * 0.35), Vector2(-size * 0.18, size * 0.22)])
		"light_fighter":
			wing_r = PackedVector2Array([Vector2(size * 0.17, -size * 0.02), Vector2(size * 0.92, size * 0.28), Vector2(size * 0.70, size * 0.38), Vector2(size * 0.18, size * 0.20)])
			wing_l = PackedVector2Array([Vector2(-size * 0.17, -size * 0.02), Vector2(-size * 0.92, size * 0.28), Vector2(-size * 0.70, size * 0.38), Vector2(-size * 0.18, size * 0.20)])
		"twin_tail":
			tail_r = PackedVector2Array([Vector2(size * 0.15, size * 0.48), Vector2(size * 0.65, size * 0.68), Vector2(size * 0.48, size * 0.90), Vector2(size * 0.18, size * 0.78)])
			tail_l = PackedVector2Array([Vector2(-size * 0.15, size * 0.48), Vector2(-size * 0.65, size * 0.68), Vector2(-size * 0.48, size * 0.90), Vector2(-size * 0.18, size * 0.78)])

	# 机翼可选副色（黑机身 + 红翼 等；alpha=0 时走主色）
	var wing_color: Color = color
	if ac.params and ac.params.wing_color.a > 0.01:
		wing_color = ac.params.wing_color
	var wing_outline := wing_color.darkened(0.3)

	# 应用变换并绘制填充（body + tails 用主色；wings 可走副色）
	var part_defs := [
		{"pts": body, "col": color, "outline": outline_color},
		{"pts": wing_r, "col": wing_color, "outline": wing_outline},
		{"pts": wing_l, "col": wing_color, "outline": wing_outline},
		{"pts": tail_r, "col": color, "outline": outline_color},
		{"pts": tail_l, "col": color, "outline": outline_color},
	]
	for def in part_defs:
		var transformed: PackedVector2Array = PackedVector2Array()
		for p in def["pts"]:
			transformed.append(xform * p)
		ac.draw_colored_polygon(transformed, def["col"])
		# 轮廓线
		for i in range(transformed.size()):
			var from := transformed[i]
			var to := transformed[(i + 1) % transformed.size()]
			ac.draw_line(from, to, def["outline"], 1.0, true)

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


## 忠诚僚机无人机外观（XQ-58 Valkyrie / MQ-28 Ghost Bat 灵感）
##   - 尺寸比战斗机小（s = size × 0.55）
##   - 锐利尖头 + 极后掠三角翼 + V 形尾翼
##   - 没有座舱泡（无人机标识）
##   - 单色填充 + 深色描边，简洁科技感
static func draw_drone_icon(ac: Aircraft, color: Color, outline_color: Color, size: float, base_scale: float, xform: Transform2D) -> void:
	var s := size * 0.55  # 整体比战斗机小约 45%

	# ── 机身（细长流线，无座舱泡）──
	var body: PackedVector2Array = PackedVector2Array([
		Vector2(0, -s * 1.15),             # 机头尖端（比战斗机更尖）
		Vector2(s * 0.10, -s * 0.75),
		Vector2(s * 0.13, -s * 0.20),      # 翼根前
		Vector2(s * 0.13, s * 0.45),       # 翼根后
		Vector2(s * 0.18, s * 0.75),       # 尾段加宽（容纳 V 尾根部）
		Vector2(s * 0.10, s * 0.95),
		Vector2(0, s * 1.0),               # 尾喷口
		Vector2(-s * 0.10, s * 0.95),
		Vector2(-s * 0.18, s * 0.75),
		Vector2(-s * 0.13, s * 0.45),
		Vector2(-s * 0.13, -s * 0.20),
		Vector2(-s * 0.10, -s * 0.75),
	])

	# ── 主翼（极后掠三角翼，更接近 Valkyrie）──
	var wing_r: PackedVector2Array = PackedVector2Array([
		Vector2(s * 0.13, -s * 0.05),      # 翼根前缘
		Vector2(s * 0.95, s * 0.50),       # 翼尖
		Vector2(s * 0.85, s * 0.62),
		Vector2(s * 0.13, s * 0.30),       # 翼根后缘
	])
	var wing_l: PackedVector2Array = PackedVector2Array([
		Vector2(-s * 0.13, -s * 0.05),
		Vector2(-s * 0.13, s * 0.30),
		Vector2(-s * 0.85, s * 0.62),
		Vector2(-s * 0.95, s * 0.50),
	])

	# ── V 尾（两片倾斜的尾翼，从尾段斜向后伸）──
	var vtail_r: PackedVector2Array = PackedVector2Array([
		Vector2(s * 0.13, s * 0.55),
		Vector2(s * 0.40, s * 0.95),
		Vector2(s * 0.32, s * 1.0),
		Vector2(s * 0.13, s * 0.70),
	])
	var vtail_l: PackedVector2Array = PackedVector2Array([
		Vector2(-s * 0.13, s * 0.55),
		Vector2(-s * 0.13, s * 0.70),
		Vector2(-s * 0.32, s * 1.0),
		Vector2(-s * 0.40, s * 0.95),
	])

	# 应用变换 + 绘制（顺序：尾翼 → 主翼 → 机身，让机身覆盖在最上）
	var pieces: Array = [vtail_l, vtail_r, wing_l, wing_r, body]
	for piece in pieces:
		var transformed: PackedVector2Array = PackedVector2Array()
		for p in piece:
			transformed.append(xform * p)
		ac.draw_colored_polygon(transformed, color)
		# 轮廓
		for i in range(transformed.size()):
			ac.draw_line(transformed[i], transformed[(i + 1) % transformed.size()],
				outline_color, 1.0, true)

	# 中线（隐约的脊线，给"流线机身"质感）
	var accent := color.lightened(0.4)
	accent.a = 0.4
	ac.draw_line(xform * Vector2(0, -s * 0.6), xform * Vector2(0, s * 0.7), accent, 1.0, true)

	# 选中指示（drone 通常不被玩家选中，但保留以防万一）
	if ac.selected:
		var ring_color := color
		ring_color.a = 0.5
		ac.draw_arc(Vector2.ZERO, s * 1.4 * base_scale, 0, TAU, 32, ring_color, 1.2)


## Mother Goose 巨型空中航母外观（Arsenal Bird "Liberty" 灵感）
## 整体放大 ~9×（战斗机 16px → goose 翼端 ~220px @ MID 高度），宽展飞翼 + 6 发动机舱 +
## 中部船桥 + 6 尾部螺旋桨槽位标记 + 2 VLS 标记
## 螺旋桨/VLS v1 仅视觉占位；v2 接入 MountTarget 后变成可锁定目标
static func draw_mother_goose_icon(ac: Aircraft, color: Color, outline_color: Color, size: float, base_scale: float, xform: Transform2D) -> void:
	var s := size * 9.0  # 巨型航母翼展 ≈ 战斗机 9 倍
	var wing_color: Color = ac.params.wing_color if (ac.params and ac.params.wing_color.a > 0.01) else color
	var wing_outline := wing_color.darkened(0.3)

	# ── 飞翼主体（极宽 V 字飞翼）──
	var wing_body: PackedVector2Array = PackedVector2Array([
		Vector2(0, -s * 0.45),              # 机头中央
		Vector2(s * 0.20, -s * 0.35),       # 机头右
		Vector2(s * 1.40, s * 0.05),        # 右翼前缘尖端（极宽）
		Vector2(s * 1.55, s * 0.22),
		Vector2(s * 1.20, s * 0.30),        # 右翼后缘
		Vector2(s * 0.55, s * 0.28),        # 右翼根后缘
		Vector2(s * 0.30, s * 0.50),        # 右尾段
		Vector2(s * 0.10, s * 0.55),        # 中部尾段
		Vector2(0, s * 0.45),               # 中央尾凹（小 V）
		Vector2(-s * 0.10, s * 0.55),
		Vector2(-s * 0.30, s * 0.50),
		Vector2(-s * 0.55, s * 0.28),
		Vector2(-s * 1.20, s * 0.30),
		Vector2(-s * 1.55, s * 0.22),
		Vector2(-s * 1.40, s * 0.05),
		Vector2(-s * 0.20, -s * 0.35),
	])
	var transformed: PackedVector2Array = PackedVector2Array()
	for p in wing_body:
		transformed.append(xform * p)
	ac.draw_colored_polygon(transformed, wing_color)
	for i in range(transformed.size()):
		var from := transformed[i]
		var to := transformed[(i + 1) % transformed.size()]
		ac.draw_line(from, to, wing_outline, 1.5, true)

	# ── 中部船桥（圆形扫描窗）──
	var bridge_col := color.lightened(0.15)
	var bridge_outline := bridge_col.darkened(0.4)
	var bridge_pos := xform * Vector2(0, -s * 0.05)
	ac.draw_circle(bridge_pos, s * 0.18 * base_scale, bridge_col)
	ac.draw_arc(bridge_pos, s * 0.18 * base_scale, 0, TAU, 32, bridge_outline, 1.5, true)

	# ── 6 个发动机舱（沿翼前缘等距分布，左右对称）──
	var engine_col := color.darkened(0.25)
	var engine_outline := engine_col.darkened(0.3)
	var engine_xs := [-1.20, -0.75, -0.30, 0.30, 0.75, 1.20]
	for ex in engine_xs:
		var center := xform * Vector2(s * float(ex), -s * 0.05)
		var rx: float = s * 0.10 * base_scale
		var ry: float = s * 0.18 * base_scale
		# 椭圆用 16 段近似
		var pts: PackedVector2Array = PackedVector2Array()
		for k in range(20):
			var t := TAU * float(k) / 20.0
			pts.append(center + Vector2(cos(t) * rx, sin(t) * ry))
		ac.draw_colored_polygon(pts, engine_col)
		for k in range(pts.size()):
			ac.draw_line(pts[k], pts[(k + 1) % pts.size()], engine_outline, 1.0, true)

	# ── 8 个尾部螺旋桨槽位标记 ──
	## prop_xs / ry=0.42 与 [mother_goose_boss.gd:PROP_OFFSETS_PX] 严格对齐
	## 任意一处改动需同步另一处，否则雷达锁定框会和飞机模型脱节
	# 已损毁挂点：跳过绘制，玩家直接看到"哪些还在/还没打"——boss 设了 mg_mounts meta（10 项）
	var mg_mounts: Array = ac.get_meta(&"mg_mounts", []) if ac.has_meta(&"mg_mounts") else []
	var prop_col := color.darkened(0.35)
	var prop_outline := prop_col.darkened(0.3)
	var prop_xs := [-0.95, -0.68, -0.41, -0.14, 0.14, 0.41, 0.68, 0.95]
	for i in range(prop_xs.size()):
		if i < mg_mounts.size():
			var m = mg_mounts[i]
			if m and m is WeaponMount and m.destroyed:
				continue
		var px: float = float(prop_xs[i])
		var c := xform * Vector2(s * px, s * 0.42)
		var r: float = s * 0.045 * base_scale
		ac.draw_circle(c, r, prop_col)
		ac.draw_arc(c, r, 0, TAU, 12, prop_outline, 1.0, true)
	# 中央两个 VLS 标记（机身中段）—— mounts[8] / mounts[9]
	var vls_col := color.lightened(0.05)
	var vls_outline := vls_col.darkened(0.4)
	var vls_xs := [-0.18, 0.18]
	for j in range(vls_xs.size()):
		var mount_idx: int = 8 + j
		if mount_idx < mg_mounts.size():
			var m = mg_mounts[mount_idx]
			if m and m is WeaponMount and m.destroyed:
				continue
		var vx: float = float(vls_xs[j])
		var c := xform * Vector2(s * vx, s * 0.10)
		var w: float = s * 0.08 * base_scale
		var h: float = s * 0.18 * base_scale
		var rect := Rect2(c - Vector2(w * 0.5, h * 0.5), Vector2(w, h))
		ac.draw_rect(rect, vls_col, true)
		ac.draw_rect(rect, vls_outline, false, 1.0)

	# ── 翼面纵向参考线（增加规模感）──
	var accent := outline_color
	accent.a = 0.6
	for ly in [-0.2, 0.05, 0.2]:
		var l_from := xform * Vector2(-s * 1.30, s * float(ly))
		var l_to := xform * Vector2(s * 1.30, s * float(ly))
		ac.draw_line(l_from, l_to, accent, 0.8, true)

	# 选中指示（玩家通常不会选中 boss，但保留）
	if ac.selected:
		var ring_color := color
		ring_color.a = 0.5
		ac.draw_arc(Vector2.ZERO, s * 1.7 * base_scale, 0, TAU, 64, ring_color, 1.5)


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

## 极简标签：忠诚僚机 / 漂浮装置等不需要 callsign / altitude 的小型单位
## 只显示一行 "DRONE  482 kt"（kind 名 + 速度）
static func draw_data_label_drone(ac: Aircraft) -> void:
	if ac._font == null:
		return
	var speed_kmh := ac.speed * 3.6
	var line: String = "DRONE  %d kt" % roundi(speed_kmh * 0.5399)
	var font_size := 11
	var pad := 4.0
	var text_w: float = ac._font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var box_w := text_w + pad * 2.0
	var box_h := 13.0 + pad * 2.0
	var origin_local: Vector2 = Vector2(14.0, -box_h * 0.5)
	# 抵消机身旋转 + 摄像机缩放
	var inv_zoom: float = 1.0
	if ac.is_inside_tree():
		var cam: Camera2D = ac.get_viewport().get_camera_2d()
		if cam != null:
			inv_zoom = 1.0 / maxf(cam.zoom.x, 0.0001)
	ac.draw_set_transform(origin_local, -ac.global_rotation, Vector2.ONE * inv_zoom)
	ac.draw_rect(Rect2(Vector2.ZERO, Vector2(box_w, box_h)), Color(0.05, 0.08, 0.05, 0.55), true)
	ac.draw_string(ac._font, Vector2(pad, pad + ac._font.get_ascent(font_size)), line,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.7, 0.95, 0.7, 0.85))
	ac.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 当前操控机显示纯机型编号 + 完整呼号；其它单位缩机名后缀、不缩呼号。
static func draw_data_label_compact(ac: Aircraft) -> void:
	if ac._font == null:
		return
	var display_name := compact_aircraft_name(ac.params.display_name) if ac.params else "???"
	var is_player: bool = ac == safe_player_ref()
	var identity := controlled_identity_label(ac) if is_player \
			else ally_identity_label(ac) if ac.team == CombatUnit.TEAM_ALLY \
			else "%s [%s]" % [display_name, ac.callsign]
	var lines := PackedStringArray([identity])
	lines.append("%d kt" % roundi(ac.speed * 3.6 * 0.5399))
	var status_line_indices: Dictionary = {}
	_append_status_label_lines(ac, lines, status_line_indices, ac == safe_player_ref())

	var inv_rot: float = -ac.rotation
	var inv_zoom: float = screen_space_inverse_scale(ac)
	var font_size := 11
	var line_height := 14.0
	var label_offset := Vector2(24 * inv_zoom, -12 * inv_zoom).rotated(inv_rot)
	var max_w := 0.0
	for line in lines:
		max_w = maxf(max_w, ac._font.get_string_size(
			_digit_stable(line), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)

	var colors := GameConstants.aircraft_label_colors(ac.team)
	var bg_color: Color = colors[0]
	var text_color: Color = colors[1]
	if is_player:
		bg_color = GameConstants.PLAYER_CTRL_LABEL_BG
		text_color = GameConstants.PLAYER_CTRL_LABEL_TEXT

	ac.draw_set_transform(label_offset, inv_rot, Vector2.ONE * inv_zoom)
	var box := Rect2(0, 0, max_w + 10.0, lines.size() * line_height + 6.0)
	ac.draw_rect(box, bg_color)
	ac.draw_rect(box, text_color * Color(1, 1, 1, 0.4), false, 1.0)
	for i in range(lines.size()):
		var color: Color = text_color
		if status_line_indices.has(i):
			color = status_line_indices[i]
		if is_player and color != text_color:
			color = GameConstants.darken_for_light_bg(color)
		ac.draw_string(ac._font, Vector2(5, 12 + i * line_height), lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
	ac.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## 玩家装填提示独立于右侧数据标签，固定在机体屏幕空间左上角。
static func draw_reload_indicators(ac: Aircraft) -> void:
	if ac._font == null or not reload_indicator_team_visible(ac.team):
		return
	var flare_reloading := (ac.enable_flare_reload and ac.flares_remaining <= 0
		and ac.flare_reload_progress > 0.0)
	var labels := reload_indicator_tokens(ac._gun_reload_active,
		ac._missile_reload_active, flare_reloading)
	var inverted: bool = int(Time.get_ticks_msec() / 220) % 2 != 0
	if labels.is_empty():
		return
	var inv_zoom := screen_space_inverse_scale(ac)
	var inv_rot := -ac.rotation
	var is_controlled := ac == safe_player_ref()
	var anchor := Vector2(-44.0 * inv_zoom, -38.0 * inv_zoom).rotated(inv_rot)
	ac.draw_set_transform(anchor, inv_rot, Vector2.ONE * inv_zoom)
	for i in range(labels.size()):
		var style := reload_indicator_style(labels[i], inverted, is_controlled)
		var text_color: Color = style[0]
		var bg_color: Color = style[1]
		var text_w := ac._font.get_string_size(labels[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		var top := float(i) * 20.0
		ac.draw_rect(Rect2(-3.0, top, text_w + 6.0, 18.0), bg_color)
		ac.draw_rect(Rect2(-3.0, top, text_w + 6.0, 18.0), text_color, false, 1.0)
		ac.draw_string(ac._font, Vector2(0.0, top + 14.0), labels[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, text_color)
	ac.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func reload_indicator_team_visible(team: int) -> bool:
	return team == CombatUnit.TEAM_PLAYER


## 返回 [文字色, 底色]；每 220ms 由调用方切换 inverted，始终保持可见。
static func reload_indicator_style(label: String, inverted: bool,
		is_controlled: bool = true) -> Array[Color]:
	if label == "MSL" and not is_controlled:
		return [Color.WHITE, Color(0.04, 0.05, 0.07, 0.88)]
	var primary := Color.html("#5599ff")
	var secondary := Color(1.0, 1.0, 1.0, 0.96)
	match label:
		"FLR":
			primary = Color.html("#ff9d2e")
			secondary = Color.html("#00237d")
		"GUN":
			primary = Color.html("#8b5a2b")
	var style: Array[Color] = []
	style.append(primary if inverted else secondary)
	style.append(secondary if inverted else primary)
	return style


static func reload_indicator_tokens(gun_reloading: bool, missile_reloading: bool,
		flare_reloading: bool) -> PackedStringArray:
	var labels := PackedStringArray()
	if flare_reloading:
		labels.append("FLR")
	if gun_reloading:
		labels.append("GUN")
	if missile_reloading:
		labels.append("MSL")
	return labels


static func secondary_reload_progress(ac: Aircraft) -> float:
	if not ac._secondary_reload_active or not ac.params or not ac.params.secondary_missile:
		return 0.0
	var sec: MissileParams = ac.params.secondary_missile
	var duration := sec.cooldown * float(maxi(sec.max_count, 1))
	return clampf(ac._secondary_reload_timer / maxf(duration, 0.001), 0.0, 1.0)


## 第三方绿色友军标签只去掉旧 ALLY- 前缀；机型名称后缀缩写，呼号始终完整。
static func ally_identity_label(ac: Aircraft) -> String:
	var display_name := compact_aircraft_name(ac.params.display_name) if ac.params else "???"
	var callsign := ac.callsign
	if callsign.begins_with("ALLY-"):
		callsign = callsign.substr(5)
	if callsign == "":
		return display_name
	return "%s %s" % [display_name, callsign]


## 保留带数字的机型编号，把后续整段名称只压成第一个首字母：
## F-15 Eagle → F-15 E；Su-35 Super Flanker → Su-35 S。
static func compact_aircraft_name(display_name: String) -> String:
	var clean_name := display_name.strip_edges()
	var model := aircraft_model_designation(clean_name)
	if model == clean_name:
		return clean_name
	var suffix := clean_name.substr(model.length()).strip_edges()
	return model if suffix.is_empty() else "%s %s" % [model, suffix.substr(0, 1).to_upper()]


## 从显示名里只取真正的机型编号：F-14 Tomcat → F-14，JAS 39C Gripen → JAS 39C。
static func aircraft_model_designation(display_name: String) -> String:
	var clean_name := display_name.strip_edges()
	var words := clean_name.split(" ", false)
	var model_end := -1
	for i in range(words.size()):
		for c in words[i]:
			if c >= "0" and c <= "9":
				model_end = i
				break
		if model_end >= 0:
			break
	if model_end < 0:
		return clean_name
	var model_words := PackedStringArray()
	for i in range(model_end + 1):
		model_words.append(words[i])
	return " ".join(model_words)


## 生存模式在拼接主角代号前保存的纯机型编号；非生存实例安全回落到显示名。
static func airframe_identity_label(ac: Aircraft) -> String:
	var airframe := String(ac.get_meta("airframe_label", "")).strip_edges()
	if not airframe.is_empty():
		return aircraft_model_designation(airframe)
	return aircraft_model_designation(ac.params.display_name) if ac.params else "???"


## 当前操控机不显示 profile 机名后缀，但完整保留飞行员呼号。
static func controlled_identity_label(ac: Aircraft) -> String:
	var airframe := airframe_identity_label(ac)
	return airframe if ac.callsign.is_empty() else "%s [%s]" % [airframe, ac.callsign]


## 在飞机旁边绘制数据标签框（逐行列出所有参数）
## 是否使用精简标签（无导弹/无热诱弹的简单单位）
## 生存模式玩家用精简标签：只显示朝向、速度、高度、G、耐力
static func draw_data_label_minimal(ac: Aircraft) -> void:
	var speed_kmh := ac.speed * 3.6
	var heading_deg := rad_to_deg(ac.heading)
	if heading_deg < 0:
		heading_deg += 360.0

	var is_player := ac == safe_player_ref()
	var lines := PackedStringArray()
	lines.append(controlled_identity_label(ac) if is_player \
			else ally_identity_label(ac) if ac.team == CombatUnit.TEAM_ALLY else ac.callsign)
	lines.append("HDG %03d" % roundi(heading_deg))
	lines.append("%d kt" % roundi(speed_kmh * 0.5399))
	var alt_line_idx := lines.size()
	if ac.flat_altitude:
		var tier_now: int = ac.get_altitude_tier()
		var vs_abs: float = absf(ac.vertical_speed)
		if vs_abs > 5.0:
			var arrow: String = "↑" if ac.vertical_speed > 0.0 else "↓"
			lines.append("ALT %s %s" % [Aircraft.TIER_NAMES[tier_now], arrow])
		else:
			lines.append("ALT %s" % Aircraft.TIER_NAMES[tier_now])
	else:
		lines.append("ALT %dm" % roundi(ac.altitude))
	lines.append("G %.1f" % ac.g_load)
	# 武器行品牌色映射（与右下角武器栏同源 _wpn_color）
	var wpn_color_indices: Dictionary = {}
	var is_player_label := ac == safe_player_ref()
	# 详细档统一显示全部可装填武器；装填完自动消失。
	if ac._gun_reload_active:
		wpn_color_indices[lines.size()] = _wpn_color("GUN_RELOAD")
		lines.append("GUN RELOAD %d%%" % roundi(ac.gun_reload_progress * 100.0))
	if ac._missile_reload_active:
		wpn_color_indices[lines.size()] = weapon_label_color("MSL_RELOAD", is_player_label)
		lines.append("MSL RELOAD %d%%" % roundi(ac.missile_reload_progress * 100.0))
	if ac._secondary_reload_active and ac.params and ac.params.secondary_missile:
		var sec_name_min := ac.params.secondary_missile.display_name
		if sec_name_min.is_empty(): sec_name_min = "SP"
		wpn_color_indices[lines.size()] = weapon_label_color("SP_RELOAD", is_player_label)
		lines.append("%s RELOAD %d%%" % [sec_name_min,
			roundi(secondary_reload_progress(ac) * 100.0)])
	if ac.enable_flare_reload and ac.flares_remaining <= 0 and ac.flare_reload_progress > 0.0:
		wpn_color_indices[lines.size()] = _wpn_color("FLR_RELOAD")
		lines.append("FLR RELOAD %d%%" % roundi(ac.flare_reload_progress * 100.0))
		# 电磁炮 / 激光（commit 11+）
		if ac.params != null:
			var rg_min: RailgunEquipment = ac.params.get_equipment_of_kind("railgun")
			if rg_min != null:
				var rg_st: Dictionary = ac.equipment_state.get(RailgunEquipment.STATE_KEY, {})
				if rg_st.get("charging", false):
					wpn_color_indices[lines.size()] = _wpn_color("RAIL_CHG")
					lines.append("RAIL CHG %d%%" % int(rg_st.get("charge_progress", 0.0) * 100))
				elif rg_st.get("cooldown", 0.0) > 0.01:
					var rg_cd: float = float(rg_st.get("cooldown", 0.0))
					var rg_pct: int = int(clampf(rg_cd / rg_min.cooldown, 0.0, 1.0) * 100) if rg_min.cooldown > 0.0 else 0
					wpn_color_indices[lines.size()] = _wpn_color("RAIL_CD")
					lines.append("RAIL CD %d%%" % rg_pct)
			var le_min: LaserEquipment = ac.params.get_equipment_of_kind("laser")
			if le_min != null:
				var le_st: Dictionary = ac.equipment_state.get(LaserEquipment.STATE_KEY, {})
				if le_st.get("overheating", false):
					wpn_color_indices[lines.size()] = _wpn_color("LSR_OVERHEAT")
					lines.append("LSR OVERHEAT")
				else:
					var heat_pct := int(le_st.get("heat", 0.0) / le_min.heat_max * 100)
					if heat_pct >= 50:
						wpn_color_indices[lines.size()] = _wpn_color("LSR_HEAT", {"pct": heat_pct})
						lines.append("LSR HEAT %d%%" % heat_pct)

	# 状态效果（buff/debuff）：英文简称 + 百分比 + 颜色
	# 玩家标签：对 INVINCIBLE / STEALTH 用权威标志兜底，让走直写 invulnerable / is_cloaked
	# 或派生 status_stealth_active 的玩家通路（KIA 复活、规避加力隐形、导弹弹尽隐形等）
	# 也能在 HUD 上显示。无字典条目时不带百分比。
	var status_line_indices: Dictionary = {}
	_append_status_label_lines(ac, lines, status_line_indices, true)

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
	var default_text_color := Color(0.85, 0.9, 0.85, 0.9)
	# 当前操控机=白底（偏蓝，spec squad-control-switching §2.2）+ 默认文字转深色
	if is_player:
		bg_color = GameConstants.PLAYER_CTRL_LABEL_BG
		default_text_color = GameConstants.PLAYER_CTRL_LABEL_TEXT

	ac.draw_set_transform(label_offset, inv_rot, scale_v)
	ac.draw_rect(Rect2(-2, -2, max_w + 6, lines.size() * line_height + 4), bg_color)
	# 仅玩家自己标 ALT 颜色；敌机保持统一色
	var alt_color := altitude_tier_color(ac.get_altitude_tier(), ac.flat_altitude and absf(ac.vertical_speed) > 5.0) if is_player else default_text_color
	for i in range(lines.size()):
		var col := default_text_color
		if is_player and i == alt_line_idx:
			col = alt_color
		elif status_line_indices.has(i):
			col = status_line_indices[i]
		elif wpn_color_indices.has(i):
			col = wpn_color_indices[i]
		# 白底压暗：彩色行（status/wpn/alt）原本是高亮浅色，在白底上看不清 → 压暗保色相
		if is_player and col != default_text_color:
			col = GameConstants.darken_for_light_bg(col)
		ac.draw_string(ac._font, Vector2(0, i * line_height + 11), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
	ac.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func draw_data_label(ac: Aircraft) -> void:
	var display_name := compact_aircraft_name(ac.params.display_name) if ac.params else "???"
	var speed_kmh := ac.speed * 3.6
	var heading_deg := rad_to_deg(ac.heading)
	if heading_deg < 0:
		heading_deg += 360.0
	var status := "STALL" if ac.is_stalled else ""

	# 计算到玩家的距离（米）——用全局玩家引用，避免每帧扫 parent.get_children() 的 O(N)
	var dist_m := 0.0
	var pref := safe_player_ref()
	if pref and pref != ac and is_instance_valid(pref) and not pref.is_destroyed:
		dist_m = ac.global_position.distance_to(pref.global_position) / Aircraft.PIXELS_PER_METER

	# 统一标签格式（所有飞机通用）
	var lines: PackedStringArray = PackedStringArray()
	# 第 1 行：当前操控机只写机型编号；其它单位保留代号信息。
	lines.append(controlled_identity_label(ac) if ac == pref \
			else ally_identity_label(ac) if ac.team == CombatUnit.TEAM_ALLY \
			else "%s [%s]" % [ac.callsign, display_name])
	# 第 2 行：速度（kt）
	lines.append("%d kt" % roundi(speed_kmh * 0.5399))
	# 第 3 行：朝向
	lines.append("HDG %03d" % roundi(heading_deg))
	# 第 4 行：高度（vs 非零时附箭头表示正在升降）
	var alt_line_idx := lines.size()
	if ac.flat_altitude:
		var tier_now: int = ac.get_altitude_tier()
		var vs_abs: float = absf(ac.vertical_speed)
		if vs_abs > 5.0:
			var arrow: String = "↑" if ac.vertical_speed > 0.0 else "↓"
			lines.append("ALT %s %s" % [Aircraft.TIER_NAMES[tier_now], arrow])
		else:
			lines.append("ALT %s" % Aircraft.TIER_NAMES[tier_now])
	else:
		lines.append("ALT %dm" % roundi(ac.altitude))
	# 第 5 行：距离（到玩家）
	if dist_m < 1000.0:
		lines.append("RNG %dm" % roundi(dist_m))
	else:
		lines.append("RNG %.1fkm" % (dist_m / 1000.0))
	# 武器行品牌色映射：line_idx → Color，draw 阶段优先于 text_color。
	# 约定：武器/装备颜色只标在玩家自己 label 上（玩家需要知道的信息）；
	# 敌机/友机走 team text_color，buff/debuff 仍由 status_line_indices 单独上色。
	var wpn_color_indices: Dictionary = {}
	var is_player_label := ac == safe_player_ref()
	# 第 6 行：热诱弹（玩家才染色，敌机/友机保留 text_color）
	if ac.params and ac.params.flare:
		if is_player_label:
			wpn_color_indices[lines.size()] = _wpn_color("FLR_READY" if ac.flares_remaining > 0 else "FLR_EMPTY")
		lines.append("FLR %d" % ac.flares_remaining)
	# 电磁炮 / 激光（仅玩家显示，避免 AF-03 头顶暴露状态）
	if ac == safe_player_ref() and ac.params:
		var rg2: RailgunEquipment = ac.params.get_equipment_of_kind("railgun")
		if rg2 != null:
			var rg_st: Dictionary = ac.equipment_state.get(RailgunEquipment.STATE_KEY, {})
			if rg_st.get("charging", false):
				wpn_color_indices[lines.size()] = _wpn_color("RAIL_CHG")
				lines.append("RAIL CHG %d%%" % int(rg_st.get("charge_progress", 0.0) * 100))
			elif rg_st.get("cooldown", 0.0) > 0.01:
				# CD 显示与右下角武器栏统一为百分比（current/max × 100）
				var rg_cd: float = float(rg_st.get("cooldown", 0.0))
				var rg_pct: int = int(clampf(rg_cd / rg2.cooldown, 0.0, 1.0) * 100) if rg2.cooldown > 0.0 else 0
				wpn_color_indices[lines.size()] = _wpn_color("RAIL_CD")
				lines.append("RAIL CD %d%%" % rg_pct)
			else:
				wpn_color_indices[lines.size()] = _wpn_color("RAIL_READY")
				lines.append("RAIL READY")
		var le2: LaserEquipment = ac.params.get_equipment_of_kind("laser")
		if le2 != null:
			var le_st: Dictionary = ac.equipment_state.get(LaserEquipment.STATE_KEY, {})
			if le_st.get("overheating", false):
				wpn_color_indices[lines.size()] = _wpn_color("LSR_OVERHEAT")
				lines.append("LSR OVERHEAT")
			else:
				var le_pct: int = int(le_st.get("heat", 0.0) / le2.heat_max * 100)
				wpn_color_indices[lines.size()] = _wpn_color("LSR_HEAT", {"pct": le_pct})
				lines.append("LSR HEAT %d%%" % le_pct)
	# 详细档统一显示全部可装填武器及进度。
	if ac._gun_reload_active:
		wpn_color_indices[lines.size()] = _wpn_color("GUN_RELOAD")
		lines.append("GUN RELOAD %d%%" % roundi(ac.gun_reload_progress * 100.0))
	if ac._missile_reload_active:
		wpn_color_indices[lines.size()] = weapon_label_color("MSL_RELOAD", is_player_label)
		lines.append("MSL RELOAD %d%%" % roundi(ac.missile_reload_progress * 100.0))
	if ac._secondary_reload_active and ac.params and ac.params.secondary_missile:
		var sec_name := ac.params.secondary_missile.display_name
		if sec_name.is_empty(): sec_name = "SP"
		wpn_color_indices[lines.size()] = weapon_label_color("SP_RELOAD", is_player_label)
		lines.append("%s RELOAD %d%%" % [sec_name,
			roundi(secondary_reload_progress(ac) * 100.0)])
	if ac.enable_flare_reload and ac.flares_remaining <= 0 and ac.flare_reload_progress > 0.0:
		wpn_color_indices[lines.size()] = _wpn_color("FLR_RELOAD")
		lines.append("FLR RELOAD %d%%" % roundi(ac.flare_reload_progress * 100.0))
	# 失速提示（仅玩家染色，敌机走 text_color）
	if status != "":
		if is_player_label:
			wpn_color_indices[lines.size()] = _wpn_color("STALL")
		lines.append(status)

	# 状态效果（buff/debuff）：英文简称 + 百分比 + 颜色
	# 敌人/友机标签：仅 STEALTH 用 is_cloaked 兜底（让 F-47 光学隐形阶段能被玩家看到）。
	# INVINCIBLE 不兜底——F-14 出生 4s 起飞保护是纯演出效果，走直写 invulnerable，
	# 不进字典 → 不在 HUD 暴露。
	var status_line_indices: Dictionary = {}
	_append_status_label_lines(ac, lines, status_line_indices)

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

	# 背景色（spec squad-control-switching §2.2）：当前操控机=白底，其余友机=蓝底，敌机=红底。
	# 白底只标"玩家当前亲控那一架"（safe_player_ref），让玩家一眼看出"我现在是谁"。
	var _alc := GameConstants.aircraft_label_colors(ac.team)
	var bg_color: Color = _alc[0]
	var text_color: Color = _alc[1]
	var is_player := ac == safe_player_ref()
	if is_player:
		bg_color = GameConstants.PLAYER_CTRL_LABEL_BG   # 偏蓝白底（不纯白，避免刺眼）
		text_color = GameConstants.PLAYER_CTRL_LABEL_TEXT  # 深色基础文字

	var scale_v := Vector2(inv_zoom, inv_zoom)
	ac.draw_set_transform(label_offset, inv_rot, scale_v)
	ac.draw_rect(Rect2(0, 0, box_w, box_h), bg_color)
	ac.draw_rect(Rect2(0, 0, box_w, box_h), text_color * Color(1, 1, 1, 0.4), false, 1.0)

	# 高度变化检测：用 vs 而不是 tier 跨边界（vs > 5 m/s 视为真在升降）
	var alt_changing: bool = ac.flat_altitude and absf(ac.vertical_speed) > 5.0
	var alt_color := altitude_tier_color(ac.get_altitude_tier(), alt_changing) if is_player else text_color
	for i in range(lines.size()):
		var col := text_color
		if is_player and i == alt_line_idx:
			col = alt_color
		elif status_line_indices.has(i):
			col = status_line_indices[i]
		elif wpn_color_indices.has(i):
			col = wpn_color_indices[i]
		# 白底压暗：彩色行（status/wpn/alt 等高亮浅色）在白底上看不清 → 压暗保色相
		if is_player and col != text_color:
			col = GameConstants.darken_for_light_bg(col)
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

	# 规避模式：玩家不需要看到 target_position 抖动出来的预测线（每帧扭头会让线扭动）
	# 战斗连接线也无意义（规避中不主动接战）
	if ac.evasion_mode:
		return

	# 有战斗目标时：连接线指向敌机
	if ac.combat_target and is_instance_valid(ac.combat_target) and not ac.combat_target.is_destroyed:
		# 普通线跟随当前操控机线框色；双击突击保留独立黄线语义。
		var body_color: Color = ac.params.icon_color if ac.params else GameConstants.team_color(ac.team)
		var ct_color := Color(1.0, 0.78, 0.2, 0.84) if ac.charge_attack else Color(body_color, 0.68)
		var ct_width: float = 1.8 if ac.charge_attack else 1.5
		var ct_local := ac.to_local(ac.combat_target.global_position)
		# 单层中细线：兼顾地图上的可读性与轻量感，不恢复深色粗描边。
		ac.draw_line(Vector2.ZERO, ct_local, ct_color, ct_width, true)
		var ct_d := 8.0
		var marker_width: float = 1.6 if ac.charge_attack else 1.3
		ac.draw_line(ct_local + Vector2(-ct_d, 0), ct_local + Vector2(ct_d, 0), ct_color, marker_width)
		ac.draw_line(ct_local + Vector2(0, -ct_d), ct_local + Vector2(0, ct_d), ct_color, marker_width)

		# 战斗目标外围方框：4 个 L 角"瞄准框"风格，跟随当前连线色。
		# 仅玩家（team=0）画，因为 AI 的 combat_target 不需要 UI 指示
		if ac.team == 0:
			var box_half: float = 18.0   # 方框半边长
			var corner_len: float = 6.0  # 每个 L 角的边长
			var box_col := Color(ct_color, 0.66 if ac.charge_attack else 0.62)
			var box_w: float = 1.4
			var corners: Array = [
					Vector2(-box_half, -box_half),  # 左上
					Vector2( box_half, -box_half),  # 右上
					Vector2( box_half,  box_half),  # 右下
					Vector2(-box_half,  box_half),  # 左下
			]
			# 每角画两段：水平 + 垂直
			for k in range(4):
				var corner: Vector2 = corners[k]
				var sx: float = -1.0 if corner.x > 0 else 1.0
				var sy: float = -1.0 if corner.y > 0 else 1.0
				ac.draw_line(ct_local + corner, ct_local + corner + Vector2(corner_len * sx, 0), box_col, box_w)
				ac.draw_line(ct_local + corner, ct_local + corner + Vector2(0, corner_len * sy), box_col, box_w)
		return

	if ac.target_position == Vector2.INF:
		return

	if ac.team != 0:
		return

	# 硬规则（command-wheel spec §3.8）：移动指示线只画在**当前操控机**上，僚机——
	# 包括带命令、执行编队/巡航移动的僚机——一律不画。
	# 不能用 formation_mode 之类宽条件：僚机执行命令/交战时 clear_formation() 后照样
	# 满足旧条件而画线；且 formation_mode / target_position 被 AI 按 tick 频率翻转时，
	# 线会同频出现消失（闪烁）。player_ref 由 _set_player_aircraft 切控时原子更新，
	# 天然跟随 1-4 切控。
	if safe_player_ref() != ac:
		return

	# 预测线统一用蓝色（与玩家机身 icon_color 解耦）—— 减速着色由 draw_predicted_path 自己根据
	# speed_cache 算出 yellow/brown/red 渐变，base_color 只决定"全速健康状态"的色调
	var color := Color(0.35, 0.7, 1.0)  ## 标准玩家蓝（HUD/UI 系一致）

	var local_target := ac.to_local(ac.target_position)

	# 预测飞行路径
	draw_predicted_path(ac, local_target, color)

	# 航点标记 — 加粗双环 + 加大十字 + 双脉冲 + 暗角光晕，远距/混乱战场也能立刻定位
	var d := 16.0   # 主圆半径（11→16）
	var marker_color := Color(0.35, 0.85, 1.0, 1.0)
	# 暗角光晕：让目标点在杂乱地形/烟雾里也能"浮"出来
	ac.draw_circle(local_target, d * 2.6, Color(marker_color.r, marker_color.g, marker_color.b, 0.08))
	ac.draw_circle(local_target, d * 1.8, Color(marker_color.r, marker_color.g, marker_color.b, 0.13))
	# 中心填充 + 加粗主环
	ac.draw_circle(local_target, d, Color(marker_color.r, marker_color.g, marker_color.b, 0.28))
	ac.draw_arc(local_target, d, 0, TAU, 36, marker_color, 3.0)            # 2.0 → 3.0
	# 次内环
	ac.draw_arc(local_target, d * 0.55, 0, TAU, 28, Color(marker_color, 0.95), 2.0)
	# 加大加粗的十字（外伸更远 + 加宽）
	var gap := d * 0.45
	var tail := d * 2.1   # 1.55 → 2.1
	var cross_col := Color(marker_color, 1.0)
	var cross_w := 2.4    # 1.6 → 2.4
	ac.draw_line(local_target + Vector2(gap, 0), local_target + Vector2(tail, 0), cross_col, cross_w)
	ac.draw_line(local_target + Vector2(-gap, 0), local_target + Vector2(-tail, 0), cross_col, cross_w)
	ac.draw_line(local_target + Vector2(0, gap), local_target + Vector2(0, tail), cross_col, cross_w)
	ac.draw_line(local_target + Vector2(0, -gap), local_target + Vector2(0, -tail), cross_col, cross_w)
	# 双脉冲外圈（错相，让"呼吸"持续可见而非有空隙）
	var pulse_t1 := fmod(float(Time.get_ticks_msec()) * 0.0018, 1.0)
	var pulse_t2 := fmod(float(Time.get_ticks_msec()) * 0.0018 + 0.5, 1.0)
	ac.draw_arc(local_target, d * (1.4 + pulse_t1 * 1.0), 0, TAU, 36,
			Color(marker_color.r, marker_color.g, marker_color.b, (1.0 - pulse_t1) * 0.65), 2.2)
	ac.draw_arc(local_target, d * (1.4 + pulse_t2 * 1.0), 0, TAU, 36,
			Color(marker_color.r, marker_color.g, marker_color.b, (1.0 - pulse_t2) * 0.45), 1.8)
	# 中心十字小实心点（精确点击位置标记）
	ac.draw_circle(local_target, 3.0, Color(1.0, 1.0, 1.0, 1.0))
	ac.draw_circle(local_target, 1.5, marker_color)

## 玩家飞行轨迹精确预测（同源 step_X 演化版）
##
## 设计：调 AircraftPhysics.predict_player_path（与实物理 tick 共享 step_target_heading
## / step_bank / step_heading / step_speed），PHYSICS_DT = 1/60s 与物理 tick 严格同步。
## 默认 180 步 ≈ 3 秒预测窗口；到达目标自动终止。
## 缓存 20Hz refresh（PREDICTED_PATH_REFRESH_MS=50ms），每帧只做 to_local 转换。
##
## 战斗中（combat_target != null）不画 —— 那时 target_position 由 update_combat 每 tick
## 改写成 lead pursuit 点，预测必然跟着乱跳。L 角方框已经标了战斗目标，足够。
static func draw_predicted_path(ac: Aircraft, _local_target: Vector2, base_color: Color) -> void:
	if ac.target_position == Vector2.INF:
		return
	if ac.combat_target != null and is_instance_valid(ac.combat_target):
		return  # 战斗中走 L 角方框，不画预测线

	# 20Hz 缓存重算
	var now_ms := Time.get_ticks_msec()
	if now_ms - ac._predicted_path_cache_ms > Aircraft.PREDICTED_PATH_REFRESH_MS \
			or ac._predicted_path_world.size() < 2:
		# 留住上一次结果，下面算两次预测之间的形状偏移用
		ac._predicted_path_prev_world = ac._predicted_path_world
		var pred: Dictionary = AircraftPhysics.predict_player_path(ac, Aircraft.PRED_MAX_STEPS)
		ac._predicted_path_world = pred.get("points", PackedVector2Array())
		ac._predicted_path_healths = pred.get("healths", PackedFloat32Array())
		ac._predicted_path_cache_ms = now_ms

		# ── 诊断日志：每次 cache refresh 都打 PRED_DIAG，按需 F9 导出 ──
		# 想抓"抽搐瞬间"就 grep PRED_JUMP（max_div > 阈值）
		# 想看完整时间线就 grep PRED_DIAG，按 step= 排序
		var n: int = ac._predicted_path_world.size()
		var prev_n: int = ac._predicted_path_prev_world.size()
		var max_div: float = 0.0
		var mean_div: float = 0.0
		var div_n: int = mini(n, prev_n)
		if div_n > 0:
			var sum_div: float = 0.0
			for i in range(div_n):
				var d: float = ac._predicted_path_world[i].distance_to(ac._predicted_path_prev_world[i])
				if d > max_div:
					max_div = d
				sum_div += d
			mean_div = sum_div / float(div_n)
		var hdg_to_target: float = 0.0
		var diff: Vector2 = ac.target_position - ac.global_position
		if diff.length_squared() > 1.0:
			hdg_to_target = atan2(diff.x, -diff.y)
		var hdiff: float = Aircraft._angle_diff(hdg_to_target, ac.heading)
		var end_pt: Vector2 = ac._predicted_path_world[n - 1] if n > 0 else ac.global_position
		var end_local: Vector2 = ac.to_local(end_pt)
		var end_h: float = ac._predicted_path_healths[n - 1] if (n > 0 and n - 1 < ac._predicted_path_healths.size()) else 0.0
		var start_h: float = ac._predicted_path_healths[0] if ac._predicted_path_healths.size() > 0 else 0.0
		var msg: String = "step=%d hdg=%d° hdiff=%+d° spd=%dkt bank=%d° g=%.1f vs=%dms alt=%dm tspd=%dkt tdist=%dpx tsign=%+d evas=%d n=%d/%d end_local=(%d,%d) hstart=%.2f hend=%.2f max_div=%dpx mean_div=%dpx prev_n=%d" % [
			ac._predicted_path_diag_step,
			int(rad_to_deg(ac.heading)),
			int(rad_to_deg(hdiff)),
			int(ac.speed * 3.6 / 1.852),  # m/s -> kt
			int(rad_to_deg(ac.bank_angle)),
			ac.g_load,
			int(ac.vertical_speed),
			int(ac.altitude),
			int(ac.target_speed_kmh / 1.852),
			int(diff.length()),
			int(ac._committed_turn_sign),
			int(ac.evasion_mode),
			n, Aircraft.PRED_MAX_STEPS,
			int(end_local.x), int(end_local.y),
			start_h, end_h,
			int(max_div), int(mean_div),
			prev_n,
		]
		EventLogger.log_event("PRED_DIAG", ac._log_name(), msg)
		if max_div > Aircraft.PRED_JUMP_PX_THRESHOLD and prev_n > 0:
			EventLogger.log_event("PRED_JUMP", ac._log_name(),
				"step=%d max_div=%dpx mean_div=%dpx (n=%d, prev_n=%d) — 看上一条 PRED_DIAG 找原因" % [
					ac._predicted_path_diag_step, int(max_div), int(mean_div), n, prev_n])
		ac._predicted_path_diag_step += 1

	var target_world: PackedVector2Array = ac._predicted_path_world
	var target_healths: PackedFloat32Array = ac._predicted_path_healths
	if target_world.size() < 2:
		return

	# ── 时间平滑（解决"6 秒预测每 50ms 离散更新看起来在瞬移"的视觉问题）──
	# cache 是 20Hz 离散刷新，每次刷新所有 360 个 world point 同时跳到新值。
	# 平滑视图（_predicted_path_smooth_*）每帧 lerp 向 target，把 50ms 的台阶
	# 摊成连续过渡。target_position 大变 / 数组长度变了就 snap 重置，避免跨目标插值。
	var dt_ms: int = mini(now_ms - ac._predicted_path_last_draw_ms, 200)
	ac._predicted_path_last_draw_ms = now_ms
	var dt: float = maxf(float(dt_ms) / 1000.0, 0.0)
	var target_pos: Vector2 = ac.target_position
	var snap_reset: bool = ac._predicted_path_last_target == Vector2.INF \
			or target_pos.distance_to(ac._predicted_path_last_target) > Aircraft.PRED_TARGET_RESET_PX \
			or ac._predicted_path_smooth_world.size() != target_world.size()
	if snap_reset:
		ac._predicted_path_smooth_world = target_world.duplicate()
		ac._predicted_path_smooth_healths = target_healths.duplicate()
		ac._predicted_path_visible_n_smooth = float(target_world.size())
	else:
		var k: float = clampf(dt * Aircraft.PRED_SMOOTH_LERP_RATE, 0.0, 1.0)
		var n_pts: int = target_world.size()
		for i in range(n_pts):
			ac._predicted_path_smooth_world[i] = ac._predicted_path_smooth_world[i].lerp(target_world[i], k)
			if i < ac._predicted_path_smooth_healths.size() and i < target_healths.size():
				ac._predicted_path_smooth_healths[i] = lerpf(
						ac._predicted_path_smooth_healths[i],
						target_healths[i],
						k)
		# visible_n 用更慢的 lerp，避免 arrival_dist 边界穿越时长度跳
		ac._predicted_path_visible_n_smooth = lerpf(
				ac._predicted_path_visible_n_smooth,
				float(target_world.size()),
				clampf(dt * Aircraft.PRED_LEN_LERP_RATE, 0.0, 1.0))
	ac._predicted_path_last_target = target_pos

	var visible_n: int = clampi(
			int(round(ac._predicted_path_visible_n_smooth)),
			2, ac._predicted_path_smooth_world.size())

	# 每帧把世界坐标转本地（飞机在动，本地坐标系跟着飞机走 → 转换不可缓存）
	var points := PackedVector2Array()
	points.resize(visible_n)
	for i in range(visible_n):
		points[i] = ac.to_local(ac._predicted_path_smooth_world[i])
	var healths := PackedFloat32Array()
	healths.resize(visible_n)
	for i in range(visible_n):
		healths[i] = ac._predicted_path_smooth_healths[i] if i < ac._predicted_path_smooth_healths.size() else 1.0

	# ── 颜色：health 渐变 blue → yellow → brown → red ──
	# health = (sim_speed - stall_floor_at_g) / (cruise - stall_floor_1g)
	#   ≥ 1.0   蓝（cruise 或更快，能量充裕）
	#   0.7~1.0 蓝 → 黄（轻度丢速）
	#   0.4~0.7 黄 → 棕（中度，贴 corner 区）
	#   0.15~0.4 棕 → 红（严重，接近 stall floor）
	#   < 0.15  红（被 stall 卡住，转向不可持续）
	var col_blue: Color = base_color
	var col_yellow := Color(1.0, 0.85, 0.2)
	var col_brown := Color(0.65, 0.40, 0.15)
	var col_red := Color(1.0, 0.25, 0.2)
	var glow_colors := PackedColorArray()
	var core_colors := PackedColorArray()
	glow_colors.resize(points.size())
	core_colors.resize(points.size())
	for i in range(points.size()):
		var h: float = healths[i] if i < healths.size() else 1.0
		var c: Color
		if h >= 1.0:
			c = col_blue
		elif h >= 0.7:
			c = col_blue.lerp(col_yellow, (1.0 - h) / 0.30)
		elif h >= 0.4:
			c = col_yellow.lerp(col_brown, (0.7 - h) / 0.30)
		elif h >= 0.15:
			c = col_brown.lerp(col_red, (0.4 - h) / 0.25)
		else:
			c = col_red
		glow_colors[i] = Color(c.r, c.g, c.b, 0.55)
		core_colors[i] = Color(
				clampf(c.r + 0.25, 0.0, 1.0),
				clampf(c.g + 0.25, 0.0, 1.0),
				clampf(c.b + 0.25, 0.0, 1.0),
				1.0)

	# 三层加粗（外晕 + 中晕 + 实芯），即使在杂乱战场也能立刻锁定预测轨迹
	ac.draw_polyline_colors(points, glow_colors, 8.0, true)
	ac.draw_polyline_colors(points, glow_colors, 4.5, true)
	ac.draw_polyline_colors(points, core_colors, 2.2, true)

	# ── 末端三角箭头 ──
	var tip_pt: Vector2 = points[points.size() - 1]
	var lookback_idx: int = maxi(0, points.size() - 3)
	var prev_pt: Vector2 = points[lookback_idx]
	var tangent: Vector2 = tip_pt - prev_pt
	var tlen: float = tangent.length()
	if tlen < 0.5 and points.size() >= 5:
		prev_pt = points[points.size() - 5]
		tangent = tip_pt - prev_pt
		tlen = tangent.length()
	var fwd: Vector2 = tangent / tlen if tlen > 0.5 else Vector2(0, -1)
	var side: Vector2 = Vector2(-fwd.y, fwd.x)

	var head_len := 16.0
	var barb_w := 10.0
	var head_base: Vector2 = tip_pt - fwd * head_len

	var tip_core_src: Color = core_colors[core_colors.size() - 1]
	var tip_glow_src: Color = glow_colors[glow_colors.size() - 1]
	var core_col := Color(tip_core_src.r, tip_core_src.g, tip_core_src.b, 0.95)
	var glow_col := Color(tip_glow_src.r, tip_glow_src.g, tip_glow_src.b, 0.55)
	var ge := 2.0

	var head_glow := PackedVector2Array([
			head_base + side * (barb_w + ge),
			tip_pt + fwd * ge,
			head_base - side * (barb_w + ge),
	])
	ac.draw_colored_polygon(head_glow, glow_col)
	var head_core := PackedVector2Array([
			head_base + side * barb_w,
			tip_pt,
			head_base - side * barb_w,
	])
	ac.draw_colored_polygon(head_core, core_col)

## ─────────── 电磁炮 telegraph 扇形（commit 8/13） ───────────
## 攻击者机头出发，向充能目标方向，扇形从 INITIAL_HALF_ANGLE 收缩为 0°
static func draw_railgun_telegraph(ac: Aircraft) -> void:
	var s = ac.equipment_state.get(RailgunEquipment.STATE_KEY, null)
	if s == null:
		return
	var charging: bool = s.get("charging", false)
	var awaiting: bool = s.get("awaiting_fire", false)
	if not charging and not awaiting:
		return
	# awaiting_fire 阶段允许 tgt 已死（锁早就定好），只需 locked_aim_pos
	var tgt = s.get("charge_target", null)
	if charging and (tgt == null or not is_instance_valid(tgt)):
		return
	# 取装备实例以拿到颜色 / 初始扇角 / 距离限制
	var rg: RailgunEquipment = null
	for eq in ac.params.equipment:
		if eq is RailgunEquipment:
			rg = eq
			break
	if rg == null:
		return

	# Anchor 选择：
	# - awaiting_fire 阶段（最高优先）：弹道解已由 _commit_fire_solution 定死（含机头
	#   直射冻结 + miss 扰动），锁在 locked_aim_pos —— 指示线即实际发射线
	# - charging + fire_along_nose（机头直射型，如 MQ-112）：沿当前机头延长线收缩
	# - charging + AT_CHARGE_START：locked_aim_pos（早就锁死）
	# - charging + AT_FIRE_TIME：跟踪当前目标 tgt.global_position
	# 射程与 _fire 同源（_effective_max_range_m = 本机雷达范围），别用 max_range_m 兜底值
	var range_px: float = rg._effective_max_range_m(ac) * CombatUnit.PIXELS_PER_METER
	var aim_anchor: Vector2
	if awaiting:
		aim_anchor = s.get("locked_aim_pos", ac.global_position)
	elif rg.fire_along_nose:
		var nose_dir := Vector2(sin(ac.heading), -cos(ac.heading))
		aim_anchor = ac.global_position + nose_dir * range_px
	elif rg.lock_trajectory_at == RailgunEquipment.LockTrajectory.AT_CHARGE_START:
		aim_anchor = s.get("locked_aim_pos", tgt.global_position if is_instance_valid(tgt) else ac.global_position)
	else:
		aim_anchor = tgt.global_position
	var to_tgt: Vector2 = aim_anchor - ac.global_position
	var dist: float = to_tgt.length()
	if dist < 1.0:
		return
	# 不在射程内不画（仅 charging 阶段；awaiting 已锁定不再校验）。
	# ⚠ fire_along_nose 必须排除：其 aim_anchor = nose_dir × range_px，dist = |nose_dir|×range_px，
	# 而 |Vector2(sin,-cos)| 有 float epsilon（≈1±1e-7）→ dist 每帧在 range_px 上下微跳，约半数帧
	# dist > range_px 成立 → 扇形隔帧被 return 掉 → ~30Hz 频闪（用户实测 MQ-112 telegraph"伤眼睛"）。
	# 该模式弹道恒 = 机头线满射程，本就无需射程校验（原注释"必通过"的假设被浮点打破）。
	if charging and not rg.fire_along_nose and dist > range_px:
		return
	var aim_dir: Vector2 = to_tgt.normalized()
	# awaiting_fire 阶段 progress 视觉上为 1.0（fan 完全收缩成线）
	var progress: float = 1.0 if awaiting else clampf(s["charge_progress"], 0.0, 1.0)
	var initial_half_rad := deg_to_rad(RailgunEquipment.TELEGRAPH_INITIAL_HALF_ANGLE_DEG)
	var half_rad: float = lerpf(initial_half_rad, 0.0, progress)
	# awaiting：画全射程 —— 实弹 hitscan 会穿透延伸到 max_range，不止到锁定点；
	# 指示线必须覆盖整条杀伤线，否则玩家以为"线外安全"仍会被穿透段命中
	var beam_len := range_px if awaiting else minf(dist, range_px)

	# 扇形颜色：敌方红 / 友方蓝
	var color: Color = rg.beam_color
	if ac.team != 0:
		color = rg.enemy_beam_color
	color.a = 0.25 + 0.55 * progress  # 越收缩越亮（玩家更紧迫感）

	# 用三角形扇形：以 ac.global_position 为顶点，远端两个切点
	var ac_local := Vector2.ZERO
	var ac_pos := ac.global_position
	# Aircraft 是 Node2D，draw 调用是相对自身 transform 的；但 Aircraft.rotation = heading
	# 在 _draw 中我们想画"世界对齐"的扇形 → 用 ac.to_local()
	var dir_local: Vector2 = ac.to_local(ac_pos + aim_dir * beam_len) - ac.to_local(ac_pos)
	var angle_to_dir := dir_local.angle()
	var p1 := Vector2.from_angle(angle_to_dir - half_rad) * beam_len
	var p2 := Vector2.from_angle(angle_to_dir + half_rad) * beam_len
	# 三角填充
	var pts := PackedVector2Array([Vector2.ZERO, p1, p2])
	ac.draw_colored_polygon(pts, color)
	# 边框
	color.a = minf(color.a + 0.3, 1.0)
	ac.draw_line(Vector2.ZERO, p1, color, 1.5, true)
	ac.draw_line(Vector2.ZERO, p2, color, 1.5, true)


## ─────────── 电磁炮闪电光束（commit 8/13） ───────────
## hitscan 发射后短暂淡出
static func draw_railgun_beam(ac: Aircraft) -> void:
	var s = ac.equipment_state.get(RailgunEquipment.STATE_KEY, null)
	if s == null:
		return
	var fade: float = s.get("beam_fade", 0.0)
	if fade <= 0.0:
		return

	var rg: RailgunEquipment = null
	for eq in ac.params.equipment:
		if eq is RailgunEquipment:
			rg = eq
			break
	if rg == null:
		return

	var t: float = clampf(fade / maxf(rg.beam_fade_duration, 0.01), 0.0, 1.0)
	var color: Color = rg.beam_color
	if ac.team != 0:
		color = rg.enemy_beam_color
	color.a = t  # 线性淡出

	var start_local := ac.to_local(s["beam_start"])
	var end_local := ac.to_local(s["beam_end"])

	# 主光束：粗白心 + 外彩边
	var core := Color(1.0, 1.0, 1.0, t)
	ac.draw_line(start_local, end_local, color, 6.0 * t, true)
	ac.draw_line(start_local, end_local, core, 2.0 * t, true)

	# 闪电抖动：沿光束方向插 4 个 jitter 点
	var diff := end_local - start_local
	var perp := diff.orthogonal().normalized()
	var prev := start_local
	var jitter_color := color
	jitter_color.a *= 0.7
	for i in range(1, 5):
		var seg_t := float(i) / 5.0
		var p := start_local + diff * seg_t + perp * randf_range(-15.0, 15.0) * t
		ac.draw_line(prev, p, jitter_color, 1.5, true)
		prev = p
	ac.draw_line(prev, end_local, jitter_color, 1.5, true)


## ─────────── 激光照射光束（commit 9/13） ───────────
## 360° 同时画 N 条到目标的细线；过热 → 闪烁 + 红边
static func draw_laser_beams(ac: Aircraft) -> void:
	var s = ac.equipment_state.get(LaserEquipment.STATE_KEY, null)
	if s == null:
		return
	var beams: Array = s.get("active_beams", [])
	var overheating: bool = s.get("overheating", false)
	var heat_ratio: float = clampf(float(s.get("heat", 0.0)) / 100.0, 0.0, 1.0)

	# 取装备实例拿颜色
	var le: LaserEquipment = null
	for eq in ac.params.equipment:
		if eq is LaserEquipment:
			le = eq
			break
	if le == null:
		return

	for beam in beams:
		var unit = beam["unit"]
		if not is_instance_valid(unit):
			continue
		var end_local := ac.to_local(unit.global_position)
		var color: Color = le.beam_color
		color.a = beam["alpha"]
		var is_hack_focus: bool = bool(beam.get("hack_focus", false))
		if is_hack_focus:
			color = Color(0.15, 0.95, 1.0, color.a)
		# 过热边缘：beam 染红
		if heat_ratio > 0.7:
			color = color.lerp(Color(1.0, 0.4, 0.3, color.a), (heat_ratio - 0.7) / 0.3)
		var t: float = beam["thickness"]
		# 主光束 + 高亮中心
		ac.draw_line(Vector2.ZERO, end_local, color, t, true)
		var core := Color(1.0, 1.0, 1.0, color.a * 0.7)
		ac.draw_line(Vector2.ZERO, end_local, core, t * 0.4, true)
		if is_hack_focus:
			var hack_ratio: float = clampf(float(beam.get("hack_ratio", 0.0)), 0.0, 1.0)
			ac.draw_arc(end_local, 16.0, -PI * 0.5, -PI * 0.5 + TAU * hack_ratio,
				24, Color(0.15, 0.95, 1.0, 0.9), 2.5, true)

	# 过热时画一个红色光环警告（玩家友方才画）
	if overheating and ac.team == 0:
		ac.draw_arc(Vector2.ZERO, 30.0, 0.0, TAU, 32, Color(1.0, 0.3, 0.3, 0.6), 2.0, true)

## ESM 范围始终可见；静态半径只随飞机画布一起移动，不做额外场景扫描。
static func draw_esm_aura(ac: Aircraft) -> void:
	if ac.params == null:
		return
	var esm: EquipmentParams = ac.params.get_equipment_of_kind("esm_pod")
	if esm == null:
		return
	var radius_px: float = float(esm.get("aura_radius_m")) * CombatUnit.PIXELS_PER_METER
	ac.draw_arc(Vector2.ZERO, radius_px, 0.0, TAU, 96,
		Color(0.15, 0.85, 1.0, 0.42), 2.0, true)
