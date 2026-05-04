class_name Missile
extends Node2D

const PIXELS_PER_METER: float = GameConstants.PIXELS_PER_METER
const GRAVITY: float = GameConstants.GRAVITY

var params: MissileParams
var source: CombatUnit        ## 发射单位（SARH 需要持续照射）
var target: CombatUnit        ## 目标
var team: int = 0

var heading: float = 0.0     ## 弧度, 0=北
var speed: float = 300.0     ## m/s
var altitude: float = 5000.0 ## 米
var age: float = 0.0         ## 存活时间
var is_active: bool = true
var has_guidance: bool = true
var is_flare_jammed: bool = false  ## 被热诱弹干扰，永久失去制导
var bounces_remaining: int = 0     ## 剩余弹跳次数（连锁弹头进化）
var proximity_aoe: bool = false    ## 近炸引信：爆炸时产生 AOE 区域

## CIWS 拦截累积伤害 —— 只有 CIWS 子弹能减这个，归零时导弹 is_active=false
## 并非通用受击血量：导弹仍然是"一发命中目标即爆炸"，这里只表示"被拦截弹击落"
## 初始值在 _ready 时从 params.intercept_hp 读取（所有型号 / 队伍共用同一套机制）
var intercept_hp: float = 60.0

## ── VLS 三段式弹道状态（仅 params.is_vls_salvo=true 的导弹用）──
## 0 = VERTICAL（垂直爬升），1 = TRANSITION（过渡俯冲），2 = TERMINAL（末端追踪）
var vls_phase: int = 0
var _vls_phase_timer: float = 0.0
## 发射瞬间锁死的玩家位置（不会更新）—— 阶段 2 朝这个点倾斜
var vls_locked_point: Vector2 = Vector2.INF
## 每发齐射弹的速度随机系数，0.8~1.2 之间 —— 让齐射弹错开，不重叠
var speed_multiplier: float = 1.0

var _prev_los_angle: float = 0.0  ## 上一帧 LOS 角（有限差分算角速率）
var _prev_heading: float = 0.0   ## 上一帧航向（用于计算模拟 bank）
var bank_angle: float = 0.0      ## 模拟 bank（由航向变化率推算）
var _trail_ribbon: TrailRibbon
var _font: Font

## VLS phase 0/1 降帧 tick 状态（详见 SurvivorData.ENABLE_VLS_LOW_RATE_TICK）
var _vls_low_rate_counter: int = 0
const VLS_LOW_RATE_DIVISOR: int = 3   ## 60Hz / 3 = 20Hz

## 缓存的 MissileManager 引用（首次 _physics_process 时解析）
var _mm = null

## 寿命到期 / 能量耗尽 / 制导彻底丢失时进入 coasting fade，而不是瞬间消失。
## 命中爆炸由 MissileManager 直接 queue_free，已有 ExplosionVFX 替代视觉，不走 fade。
const FADE_OUT_DURATION: float = 0.5
var _fading_out: bool = false

## 激光减速计时（敌方激光照射导弹时由 LaserEquipment 写入）
## > 0 时导弹速度 cap 到 max_speed × LASER_MISSILE_SPEED_MULT，max_g cap 同理
## 让玩家有机动时间躲开 — 不直接击落导弹（默认；致命输出技能下走另一条 intercept 路径）
var _laser_slow_timer: float = 0.0
var _fade_timer: float = 0.0

## ── 云层穿越累计衰减 ──
var _cloud_guidance_loss: float = 0.0   ## 0~(1-FLOOR) 累加不回复

## 建筑遮挡相关
## spawn 时检查源是否在街区内：是则导弹永久免疫建筑拦截（"从内部射出"规则）
var spawned_in_building: bool = false
## spawn 时记录发射源的高度档位 — 用于查建筑拦截概率
var source_tier: int = 0  # CombatUnit.AltitudeTier
## 上一帧是否在街区内 — 用来检测"从外部进入"事件，每次进入触发一次 roll
var _was_in_building: bool = false
const CLOUD_LOSS_PER_SECOND: float = 0.12
const CLOUD_LOSS_FLOOR: float = 0.3     ## 至少保留 30% 追踪

func _ready() -> void:
	_trail_ribbon = TrailRibbon.new()
	_trail_ribbon.ribbon_width = 3.0
	_trail_ribbon.max_points = 220
	_trail_ribbon.sample_interval = 0.03
	var trail_color := Color(GameConstants.team_trail_color(team), 0.4)
	_trail_ribbon.ribbon_color = trail_color
	add_child(_trail_ribbon)
	_prev_heading = heading
	# 从 params 读取拦截抗性（不同型号可以配置不同的抗 CIWS 能力）
	if params:
		intercept_hp = params.intercept_hp

func _physics_process(delta: float) -> void:
	if not is_active:
		return

	age += delta

	# 激光减速倒数：VLS / 渐隐 / 主路径都需要倒计时（否则 VLS 弹被照射后永久减速）
	# 倒数放在所有分支之前，确保 timer 不被旁路
	_laser_slow_timer = maxf(_laser_slow_timer - delta, 0.0)

	# 缓存 MissileManager 引用（用于读取帧级共享快照；CSG/VLS 群弹优化）
	if _mm == null:
		_mm = get_parent()

	# 渐隐 coasting：寿命到期/能量耗尽进入此分支，跳过制导，仅按当前速度滑行 + 淡出
	if _fading_out:
		_fade_timer -= delta
		var ratio: float = clampf(_fade_timer / FADE_OUT_DURATION, 0.0, 1.0)
		modulate.a = ratio  # 影响自身 + 子节点 (TrailRibbon)
		if _fade_timer <= 0.0:
			is_active = false  # 让 MissileManager 下一帧 queue_free
			return
		# 继续滑行（无制导）：靠现有 heading + speed 平移，缓慢减速
		speed = maxf(speed - params.drag_deceleration * delta, 0.0)
		var fwd_f := Vector2(sin(heading), -cos(heading))
		global_position += fwd_f * speed * PIXELS_PER_METER * delta
		queue_redraw()
		return

	# VLS 齐射弹：前两段完全接管物理（第三段 TERMINAL 走标准 PN 路径下沉到 params.nav_constant 决定）
	if params and params.is_vls_salvo and vls_phase < 2:
		# phase 0/1 是确定性弹道（爬升+固定点转向），可降帧 tick
		if SurvivorData.ENABLE_VLS_LOW_RATE_TICK:
			_vls_low_rate_counter += 1
			if _vls_low_rate_counter < VLS_LOW_RATE_DIVISOR:
				return
			# 累积 N 帧 delta 一次性传入，保证位移/速度积分总量不变
			_update_vls_non_terminal(delta * _vls_low_rate_counter)
			_vls_low_rate_counter = 0
		else:
			_update_vls_non_terminal(delta)
		return
	# 进入 TERMINAL（或非 VLS 弹）后立刻恢复 60Hz tick，重置降帧计数
	_vls_low_rate_counter = 0

	# 0) 云层穿越：导弹自身在云中飞行 → 追踪能力永久衰减（不回复）
	# 云层只存在于高空（HIGH tier，>=7500m）
	# get_in_cloud 走 MissileManager 的 256px 网格快照（同帧同区域只查一次）
	if _cloud_guidance_loss < 1.0 - CLOUD_LOSS_FLOOR and altitude >= 7500.0:
		if _mm and _mm.has_method("get_in_cloud"):
			if _mm.get_in_cloud(global_position):
				_cloud_guidance_loss = minf(_cloud_guidance_loss + CLOUD_LOSS_PER_SECOND * delta, 1.0 - CLOUD_LOSS_FLOOR)

	# 0.5) 激光减速倍率（_laser_slow_timer 已在函数顶部倒数，这里仅取当前帧的 mult）
	var _laser_speed_mult: float = SkillHooks.LASER_MISSILE_SPEED_MULT if _laser_slow_timer > 0.0 else 1.0
	var _laser_g_mult: float = SkillHooks.LASER_MISSILE_G_MULT if _laser_slow_timer > 0.0 else 1.0

	# 1) 存活时间检查 → 进入渐隐 coasting，而不是瞬间消失
	if age > params.max_lifetime:
		_start_fade_out()
		return

	# 2) 动力阶段
	if age < params.motor_burn_time:
		speed = minf(speed + params.motor_acceleration * delta, params.max_speed * _laser_speed_mult)
	else:
		speed = maxf(speed - params.drag_deceleration * delta, 0.0)
	# 激光减速生效时强制 cap（即使在制动段也限上限，防止突然脱离激光后速度暴涨）
	if _laser_slow_timer > 0.0:
		speed = minf(speed, params.max_speed * _laser_speed_mult)

	# 3) 能量耗尽（发动机燃烧阶段跳过，允许地面发射的低初速导弹加速）→ 渐隐
	if speed < 80.0 and age >= params.motor_burn_time:
		_start_fade_out()
		return

	# ── 解析目标状态（优先从 MissileManager 帧快照读，未命中走直接属性）──
	# 同源同目标的多枚导弹（VLS 齐射 / 玩家多弹齐射）共用同一份快照，避免每枚重复查询
	var t_valid: bool = is_instance_valid(target) and target != null
	var t_pos: Vector2 = global_position
	var t_heading: float = 0.0
	var t_speed: float = 0.0
	var t_alt: float = altitude
	var t_destroyed: bool = true
	var t_is_aircraft: bool = false
	var t_is_cloaked: bool = false
	var t_flat_altitude: bool = false
	var t_alt_tier: int = 0
	if t_valid:
		var snap: Dictionary = _mm.get_target_snap(target) if (_mm and _mm.has_method("get_target_snap")) else {}
		if snap.is_empty():
			t_pos = target.global_position
			t_heading = target.heading
			t_speed = target.speed
			t_alt = target.altitude
			t_destroyed = target.is_destroyed
			t_is_aircraft = target is Aircraft
			t_is_cloaked = t_is_aircraft and (target as Aircraft).is_cloaked
			t_flat_altitude = target.flat_altitude
			t_alt_tier = target.get_altitude_tier()
		else:
			t_pos = snap["pos"]
			t_heading = snap["heading"]
			t_speed = snap["speed"]
			t_alt = snap["alt"]
			t_destroyed = snap["is_destroyed"]
			t_is_aircraft = snap["is_aircraft"]
			t_is_cloaked = snap["is_cloaked"]
			t_flat_altitude = snap["flat_altitude"]
			t_alt_tier = snap["alt_tier"]

	# 4) 制导模式判定
	if params.fire_and_forget:
		# 发射后不管（AGM 等）：不需要持续照射，不受热诱弹干扰
		if not t_valid or t_destroyed:
			has_guidance = false
		elif t_is_cloaked:
			has_guidance = false  # 光学隐形：导弹丢失制导
		else:
			has_guidance = true
	else:
		# SARH 照射检查 + 热诱弹干扰
		if is_flare_jammed:
			has_guidance = false
		elif not t_valid or t_destroyed:
			has_guidance = false
		elif t_is_cloaked:
			has_guidance = false  # 光学隐形：SARH 导弹丢失
		elif source == null or not is_instance_valid(source) or source.is_destroyed:
			has_guidance = false
		else:
			var lock_progress: float = -1.0
			if _mm and _mm.has_method("get_lock_progress"):
				lock_progress = _mm.get_lock_progress(source, target)
			if lock_progress < 0.0:
				lock_progress = source.radar_targets.get(target, 0.0)
			var lock_time_val: float = 3.0
			if source is Aircraft and source.params:
				lock_time_val = source.params.lock_time
			elif source is GroundUnit and source.params:
				lock_time_val = source.params.lock_time
			has_guidance = lock_progress >= lock_time_val

	# 4b) Seeker FOV：目标脱离导引头视场 → 导弹丢锁
	# 仅在制导阶段（发射后 guidance_delay 之后）生效；丢锁后惯性飞行直到 max_lifetime
	if has_guidance and age > params.guidance_delay and t_valid:
		var los_tgt := t_pos - global_position
		if los_tgt.length() > 1.0:
			var tgt_angle := atan2(los_tgt.x, -los_tgt.y)
			var off := absf(_angle_diff(tgt_angle, heading))
			if off > deg_to_rad(params.seeker_fov * 0.5):
				has_guidance = false

	# 5) 制导
	if has_guidance and t_valid and age > params.guidance_delay:
		var los := t_pos - global_position
		var dist_px := los.length()
		var dist_m := dist_px / PIXELS_PER_METER

		# 发射后不管 + 目标静止/慢速 → 纯追踪（最精确）
		var target_is_slow := t_speed < 10.0
		if params.fire_and_forget and target_is_slow:
			# 对静止目标直接纯追踪，不用 PN（避免数值误差）
			var pure_heading := atan2(los.x, -los.y)
			var diff := _angle_diff(pure_heading, heading)
			var max_turn := params.max_g * _laser_g_mult * GRAVITY / maxf(speed, 50.0) * delta
			heading += clampf(diff, -max_turn, max_turn)
		else:
			# 低空目标：地面杂波干扰导引头，降低追踪过载
			var effective_max_g := params.max_g * _guidance_degradation_for(t_flat_altitude, t_alt_tier) * _laser_g_mult

			if dist_m < 200.0:
				# 近距纯追踪，避免 PN 振荡
				var pure_heading := atan2(los.x, -los.y)
				var diff := _angle_diff(pure_heading, heading)
				var max_turn := effective_max_g * GRAVITY / maxf(speed, 50.0) * delta
				heading += clampf(diff, -max_turn, max_turn)
			else:
				# 比例导引 (PN)
				var los_angle := atan2(los.x, -los.y)
				var omega := _angle_diff(los_angle, _prev_los_angle) / delta  # LOS 角速率

				# 闭合速度
				var los_dir := los.normalized()
				var my_vel := Vector2(sin(heading), -cos(heading)) * speed * PIXELS_PER_METER
				var tgt_vel := Vector2(sin(t_heading), -cos(t_heading)) * t_speed * PIXELS_PER_METER
				var rel_vel := tgt_vel - my_vel
				var v_closure := -rel_vel.dot(los_dir)

				# 指令加速度
				var a_cmd := params.nav_constant * v_closure * omega
				var max_accel := effective_max_g * GRAVITY
				a_cmd = clampf(a_cmd, -max_accel, max_accel)

				# 转弯率 = a / v
				var turn_rate := a_cmd / maxf(speed, 50.0)
				heading += turn_rate * delta

				_prev_los_angle = los_angle

	# 6) 高度趋近
	if has_guidance and t_valid:
		altitude += (t_alt - altitude) * 3.0 * delta

	# 7) 位移
	var vel_dir := Vector2(sin(heading), -cos(heading))
	global_position += vel_dir * speed * PIXELS_PER_METER * delta
	rotation = heading

	# 8) 模拟 bank（航向变化率 → 侧倾感）
	var hdg_diff := _angle_diff(heading, _prev_heading)
	var turn_rate_now := hdg_diff / maxf(delta, 0.001)
	bank_angle = clampf(turn_rate_now * 0.5, -1.0, 1.0)  # 轻微扭转
	_prev_heading = heading

	queue_redraw()

## 进入渐隐滑行状态：寿命到期 / 能量耗尽时调用，替代瞬间 is_active=false。
## 命中爆炸路径不走这里（MissileManager 直接 queue_free，由 ExplosionVFX 替代视觉）
func _start_fade_out() -> void:
	if _fading_out:
		return
	_fading_out = true
	_fade_timer = FADE_OUT_DURATION
	has_guidance = false  # 渐隐期间不再做任何制导

## ════════════════════════════════════════════════════════════
##  VLS 三段式弹道（阶段 1 VERTICAL + 阶段 2 TRANSITION）
## ════════════════════════════════════════════════════════════
## 阶段 1（VERTICAL）：维持初始朝向（发射时统一朝世界北），50% 速度爬升；画面上一串"火柱冲天"
## 阶段 2（TRANSITION）：朝 vls_locked_point 转向（弹道弯曲），速度爬升到满；不追踪移动的玩家
## 阶段 3（TERMINAL）：回到 _physics_process 主流程走标准 PN（nav_constant 低 → 末端精度差）
## 每发齐射弹的 speed_multiplier 在 NavalWeapons._fire_one_vls_missile 随机设定，打散弹道观感
func _update_vls_non_terminal(delta: float) -> void:
	_vls_phase_timer += delta

	# 激光减速倍率（laser timer 已在 _physics_process 顶部倒数）
	var _laser_speed_mult_vls: float = SkillHooks.LASER_MISSILE_SPEED_MULT if _laser_slow_timer > 0.0 else 1.0
	var _laser_g_mult_vls: float = SkillHooks.LASER_MISSILE_G_MULT if _laser_slow_timer > 0.0 else 1.0

	match vls_phase:
		0:  # VERTICAL 爬升段：维持初始 heading，速度爬到 max_speed 的 50%
			speed = minf(speed + params.motor_acceleration * delta, params.max_speed * 0.5 * _laser_speed_mult_vls)
			if _vls_phase_timer >= params.vls_climb_time:
				vls_phase = 1
				_vls_phase_timer = 0.0
		1:  # TRANSITION 过渡段：朝锁定点转向，速度爬满
			if vls_locked_point != Vector2.INF:
				var to_pt: Vector2 = vls_locked_point - global_position
				if to_pt.length() > 1.0:
					var target_hdg: float = atan2(to_pt.x, -to_pt.y)
					var diff: float = atan2(sin(target_hdg - heading), cos(target_hdg - heading))
					var max_turn: float = deg_to_rad(params.vls_transition_turn_rate_degs) * _laser_g_mult_vls * delta
					heading += clampf(diff, -max_turn, max_turn)
			speed = minf(speed + params.motor_acceleration * delta, params.max_speed * _laser_speed_mult_vls)
			if _vls_phase_timer >= params.vls_transition_time:
				vls_phase = 2
				_vls_phase_timer = 0.0
				# 切末端前：重置 PN 的 LOS 角以避免第一帧爆转
				if target and is_instance_valid(target):
					var los: Vector2 = target.global_position - global_position
					if los.length() > 1.0:
						_prev_los_angle = atan2(los.x, -los.y)

	# 位移（两段共用）—— 乘 speed_multiplier 让齐射弹各自快慢不同
	var fwd := Vector2(sin(heading), -cos(heading))
	var actual_speed: float = speed * speed_multiplier
	global_position += fwd * actual_speed * PIXELS_PER_METER * delta

	# 视觉尾迹更新（模拟轻微"侧滚"）
	var hdg_diff: float = _angle_diff(heading, _prev_heading)
	var turn_rate_now: float = hdg_diff / maxf(delta, 0.001)
	bank_angle = clampf(turn_rate_now * 0.5, -1.0, 1.0)
	_prev_heading = heading

	queue_redraw()

func _draw() -> void:
	if not is_active:
		return
	_draw_body()
	if age < params.motor_burn_time:
		_draw_motor_flame()
	_draw_data_label()

func _draw_body() -> void:
	# 细长"子弹+尾翼"造型，heading=0 朝上，与飞机圆点图标明显区分
	var color := GameConstants.missile_body_color(team)
	var length := 10.0   ## 弹身总长
	var nose := 3.0      ## 头锥长度
	var w := 1.2         ## 弹身半宽
	var half_len := length * 0.5

	# 弹身：尖头五边形（尖锥 + 矩形身）
	var body := PackedVector2Array([
		Vector2(0, -half_len),               # 尖头
		Vector2(w, -half_len + nose),        # 头锥右肩
		Vector2(w, half_len),                # 右后
		Vector2(-w, half_len),               # 左后
		Vector2(-w, -half_len + nose),       # 头锥左肩
	])
	draw_colored_polygon(body, color)

	# 前翼（中段十字）
	var mid_fin := 2.0
	var mid_y := -half_len + nose + 1.5
	draw_line(Vector2(-mid_fin, mid_y), Vector2(mid_fin, mid_y), color, 1.2)

	# 尾翼（后段十字，稍宽）
	var tail_fin := 2.6
	var tail_y := half_len - 0.8
	draw_line(Vector2(-tail_fin, tail_y), Vector2(tail_fin, tail_y), color, 1.4)

func _draw_motor_flame() -> void:
	var flicker := randf_range(0.6, 1.0)
	var glow := Color(1.0, 0.5, 0.1, 0.7 * flicker)
	var tail := Vector2(0, 5.0)
	var flame_len := randf_range(6.0, 10.0)
	var flame := PackedVector2Array([
		tail + Vector2(-2.0, 0),
		tail + Vector2(2.0, 0),
		tail + Vector2(0, flame_len),
	])
	draw_colored_polygon(flame, glow)

func _draw_data_label() -> void:
	if not _font:
		_font = ThemeDB.fallback_font
	var display_name: String = params.display_name if params else "MSL"

	# 到目标的距离
	var dist_to_tgt_m := 0.0
	if target and is_instance_valid(target) and not target.is_destroyed:
		dist_to_tgt_m = global_position.distance_to(target.global_position) / 0.5  # PIXELS_PER_METER

	var lines: PackedStringArray = PackedStringArray()
	lines.append(display_name)
	if dist_to_tgt_m > 0.0:
		if dist_to_tgt_m < 1000.0:
			lines.append("RNG %dm" % roundi(dist_to_tgt_m))
		else:
			lines.append("RNG %.1fkm" % (dist_to_tgt_m / 1000.0))
	else:
		lines.append("RNG --")

	var inv_rot := -rotation
	var font_size := 10
	var line_height := 12.0
	# 缩放补偿：标签大小不随摄像机缩放变化（与 AircraftRenderer.draw_data_label 一致）
	var zoom_scale := get_viewport_transform().get_scale()
	var inv_zoom := 1.0 / maxf(zoom_scale.x, 0.01)
	var label_offset := (Vector2(14, -8) * inv_zoom).rotated(inv_rot)

	# 测量最大宽度（把数字替换成 "0" 再测，避免 label 框因 hdg/rng/mach 每帧抽搐）
	# 详见 docs/changelogs/player-ai-log.md 2026-04-21 (10)
	var max_w := 0.0
	for line in lines:
		var stable := ""
		for i in range(line.length()):
			var c := line[i]
			if c >= "0" and c <= "9":
				stable += "0"
			else:
				stable += c
		var w := _font.get_string_size(stable, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		max_w = maxf(max_w, w)
	var box_w := max_w + 8.0
	var box_h := lines.size() * line_height + 4.0

	var _lc := GameConstants.missile_label_colors(team)
	var bg_color: Color = _lc[0]
	var text_color: Color = _lc[1]

	draw_set_transform(label_offset, inv_rot, Vector2(inv_zoom, inv_zoom))
	draw_rect(Rect2(0, 0, box_w, box_h), bg_color)
	draw_rect(Rect2(0, 0, box_w, box_h), text_color * Color(1, 1, 1, 0.3), false, 1.0)

	for i in range(lines.size()):
		draw_string(_font, Vector2(4, 10 + i * line_height), lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, text_color)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

## 低空目标导引头性能衰减（地面杂波干扰 + 云层穿越累计损耗）
## 低空衰减仅在扁平高度模式（生存模式）下生效
## 优先用 _guidance_degradation_for() — 由 _physics_process 传入已解析的 (flat, tier) 避免重复属性查
func _guidance_degradation() -> float:
	var t_flat: bool = false
	var t_tier: int = 0
	if is_instance_valid(target):
		t_flat = target.flat_altitude
		t_tier = target.get_altitude_tier()
	return _guidance_degradation_for(t_flat, t_tier)

func _guidance_degradation_for(t_flat: bool, t_tier: int) -> float:
	var base := 1.0
	if t_flat:
		match t_tier:
			CombatUnit.AltitudeTier.GROUND:
				base = 0.5  # 地面目标：严重杂波
			CombatUnit.AltitudeTier.LOW:
				base = 0.7  # 低空目标：中等杂波
	# 云层穿越衰减：每次穿过都累加，不回复
	return base * (1.0 - _cloud_guidance_loss)

## 角度差（-PI 到 PI）
static func _angle_diff(a: float, b: float) -> float:
	var d := fmod(a - b + PI, TAU)
	if d < 0:
		d += TAU
	return d - PI
