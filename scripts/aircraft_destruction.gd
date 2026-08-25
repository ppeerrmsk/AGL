class_name AircraftDestruction
extends RefCounted

const AircraftSilhouetteCatalog = preload("res://scripts/aircraft_silhouette_catalog.gd")
const CRASH_MODEL_END_SCALE: float = 0.55
const CRASH_SHRINK_START_PROGRESS: float = 0.08
const POST_BREAKUP_LINGER_S: float = 0.85
const POST_BREAKUP_OPAQUE_S: float = 0.25
const POST_BREAKUP_END_SCALE: float = 0.30
const SMALL_AIRFRAME_BREAKUP_SCALE: float = 0.72
const UNMANNED_BREAKUP_SCALE: float = 0.50
const MISSILE_BREAKUP_SCALE: float = 0.45
const LARGE_AIRFRAME_THRESHOLD_M: float = 28.0
const HIT_NOSE: StringName = &"nose"
const HIT_TAIL_ENGINE: StringName = &"tail_engine"
const HIT_PORT_WING: StringName = &"port_wing"
const HIT_STARBOARD_WING: StringName = &"starboard_wing"
const HIT_CENTER: StringName = &"center"
const SIZE_SMALL: StringName = &"small"
const SIZE_LARGE: StringName = &"large"

## 飞机坠毁动画系统（静态工具类）
## 从 aircraft.gd 提取：支持三种坠落风格（fighter / bomber / heli）
## 状态变量 (_destroy_timer/_destroy_spin/_destroy_bank_rate) 保留在 Aircraft，
## 因为外部代码（commander_overlay, survivor_mode）会读取 _destroy_timer 做淡出等。
##
## 用法（在 aircraft.gd 中）：
##   AircraftDestruction.start(self)     # 开始坠毁
##   AircraftDestruction.update(self, delta)  # 每帧推进

## 把真实命中世界坐标映射到机体结构分区；返回贴合当前轮廓的命中坐标供单方框 VFX 使用。
static func record_hit(ac: Aircraft, hit_world_pos: Vector2,
		incoming_velocity: Vector2 = Vector2.ZERO) -> Vector2:
	var extents := _airframe_half_extents(ac)
	var fwd := Vector2(sin(ac.heading), -cos(ac.heading))
	var right := Vector2(cos(ac.heading), sin(ac.heading))
	var delta := hit_world_pos - ac.global_position
	if not is_finite(delta.x) or not is_finite(delta.y):
		delta = Vector2.ZERO
	# 近炸/旧中心命中没有表面坐标时，以弹体入射方向反推最先接触的一侧。
	if delta.length_squared() < 0.25 and incoming_velocity.length_squared() > 0.01:
		var incoming_dir := incoming_velocity.normalized()
		delta = -incoming_dir * minf(extents.x, extents.y) * 0.92
	var local_norm := Vector2(
		clampf(delta.dot(fwd) / maxf(extents.x, 1.0), -1.0, 1.0),
		clampf(delta.dot(right) / maxf(extents.y, 1.0), -1.0, 1.0))
	ac._last_hit_local_norm = local_norm
	ac._last_hit_zone = hit_zone_for_local(local_norm)
	ac._last_hit_incoming_velocity = incoming_velocity
	ac._last_hit_world_pos = ac.global_position \
		+ fwd * local_norm.x * extents.x \
		+ right * local_norm.y * extents.y
	return ac._last_hit_world_pos


static func hit_zone_for_local(local_norm: Vector2) -> StringName:
	if local_norm.x >= 0.35:
		return HIT_NOSE
	if local_norm.x <= -0.35:
		return HIT_TAIL_ENGINE
	if local_norm.y <= -0.22:
		return HIT_PORT_WING
	if local_norm.y >= 0.22:
		return HIT_STARBOARD_WING
	return HIT_CENTER


## 体型分级优先显式 meta；无人机固定 small，避免大翼展侦察无人机误触连续爆炸。
static func destruction_size_class(ac: Aircraft) -> StringName:
	var override := StringName(ac.get_meta("destruction_class", &"")) \
		if ac.has_meta("destruction_class") else &""
	if override == SIZE_LARGE or override == SIZE_SMALL:
		return override
	if ac.params != null and ac.params.is_unmanned:
		return SIZE_SMALL
	var style := String(ac.get_meta("crash_style", "default")) \
		if ac.has_meta("crash_style") else "default"
	if style == "bomber":
		return SIZE_LARGE
	if ac.params != null and maxf(
			ac.params.visual_length_m, ac.params.visual_span_m) >= LARGE_AIRFRAME_THRESHOLD_M:
		return SIZE_LARGE
	return SIZE_SMALL


## 开始坠毁：根据 crash_style、真实受击部位与一次性局部随机配置动画参数。
static func start(ac: Aircraft) -> void:
	# 回收 callsign
	CallsignDB.recycle(ac.callsign)
	ac.is_destroyed = true
	ac.is_firing = false
	ac.combat_target = null
	ac._destroy_breakup_emitted = false
	ac._destroy_linger_timer = 0.0
	ac._destroy_duration_total = 0.0
	ac._destroy_start_altitude = maxf(ac.altitude, 1.0)
	ac._destroy_visual_scale = 1.0
	ac._destroy_visual_alpha = 1.0
	ac._destroy_size_class = destruction_size_class(ac)
	_configure_crash_motion(ac)
	var style: String = ac.get_meta("crash_style", "default") if ac.has_meta("crash_style") else "default"
	ac._destroy_status_timer = Aircraft.DESTROY_STATUS_HOLD_S
	# 坠落风格：不同机种有不同的坠毁动画参数
	# "bomber" = 重型轰炸机，小幅旋转 + 持续侧翻，下坠更久
	# "heli"   = 直升机，尾桨失效快速自旋 + 中速下坠
	# 默认      = 战斗机，失控旋转下坠
	if style == "bomber":
		ac._destroy_timer = Aircraft.BOMBER_CRASH_DURATION
	elif style == "heli":
		ac._destroy_timer = Aircraft.HELI_CRASH_DURATION
	else:
		ac._destroy_timer = Aircraft.FIGHTER_CRASH_DURATION
	# 自然随机只改变演出，不消费玩法 RNG；所有量在开始时冻结，物理帧不再分配。
	var duration_mult := _crash_duration_mult(ac)
	ac._destroy_timer *= duration_mult
	ac._destroy_duration_total = ac._destroy_timer
	EventLogger.log_event("DESTROY", ac._log_name(),
		"destroyed (alt=%.0fm spd=%.0fm/s zone=%s size=%s seed=%d)" % [
			ac.altitude, ac.speed, String(ac._last_hit_zone),
			String(ac._destroy_size_class), ac._destroy_random_seed])
	_update_crash_visual_state(ac)


static func _configure_crash_motion(ac: Aircraft) -> void:
	var qx := roundi((ac._last_hit_local_norm.x + 1.0) * 1000.0)
	var qy := roundi((ac._last_hit_local_norm.y + 1.0) * 1000.0)
	ac._destroy_random_seed = absi(
		int(ac.get_instance_id()) * 1103515245 \
		+ qx * 73856093 + qy * 19349663 + Time.get_ticks_usec())
	var rng := RandomNumberGenerator.new()
	rng.seed = ac._destroy_random_seed
	ac._destroy_descent_mult = rng.randf_range(0.90, 1.15)
	ac._destroy_speed_decay_mult = rng.randf_range(0.85, 1.20)
	ac._destroy_move_mult = rng.randf_range(0.92, 1.08)
	ac.set_meta(&"_destroy_duration_mult", rng.randf_range(0.90, 1.12))
	var sign_dir := -1.0 if rng.randf() < 0.5 else 1.0
	var style := String(ac.get_meta("crash_style", "default")) \
		if ac.has_meta("crash_style") else "default"
	if style == "bomber":
		ac._destroy_spin = Aircraft.BOMBER_YAW_SPIN_RANGE \
			* rng.randf_range(0.45, 1.0) * sign_dir
		ac._destroy_bank_rate = rng.randf_range(
			Aircraft.BOMBER_ROLL_RATE_MIN, Aircraft.BOMBER_ROLL_RATE_MAX) * sign_dir
	elif style == "heli":
		ac._destroy_spin = Aircraft.HELI_YAW_SPIN_RANGE \
			* rng.randf_range(0.60, 1.0) * sign_dir
		ac._destroy_bank_rate = Aircraft.HELI_ROLL_RATE_RANGE \
			* rng.randf_range(0.35, 1.0) * sign_dir
	else:
		ac._destroy_spin = Aircraft.FIGHTER_YAW_SPIN_RANGE \
			* rng.randf_range(0.45, 1.0) * sign_dir
		ac._destroy_bank_rate = rng.randf_range(0.25, 0.75) * sign_dir
	ac._destroy_spin *= rng.randf_range(0.82, 1.18)
	match ac._last_hit_zone:
		HIT_NOSE:
			ac._destroy_descent_mult *= 1.25
			ac._destroy_spin *= 0.80
			ac._destroy_bank_rate *= 0.75
		HIT_TAIL_ENGINE:
			ac._destroy_speed_decay_mult *= 1.65
			ac._destroy_spin *= 1.35
			ac._destroy_bank_rate *= 1.15
		HIT_PORT_WING:
			ac._destroy_spin = -absf(ac._destroy_spin) * 1.10
			ac._destroy_bank_rate = -maxf(absf(ac._destroy_bank_rate), 1.80)
		HIT_STARBOARD_WING:
			ac._destroy_spin = absf(ac._destroy_spin) * 1.10
			ac._destroy_bank_rate = maxf(absf(ac._destroy_bank_rate), 1.80)
		_:
			pass


static func _crash_duration_mult(ac: Aircraft) -> float:
	return float(ac.get_meta(&"_destroy_duration_mult", 1.0))

## 每帧推进坠落动画
static func update(ac: Aircraft, delta: float) -> void:
	var style: String = ac.get_meta("crash_style", "default") if ac.has_meta("crash_style") else "default"
	ac._destroy_status_timer = maxf(ac._destroy_status_timer - delta, 0.0)

	if style == "bomber":
		# 轰炸机坠落：偏航慢、下坠慢、持续侧翻
		ac.heading += ac._destroy_spin * delta
		ac.altitude -= Aircraft.BOMBER_DESCENT_MPS * ac._destroy_descent_mult * delta
		ac.speed = maxf(ac.speed - Aircraft.BOMBER_SPEED_DECAY \
			* ac._destroy_speed_decay_mult * delta, Aircraft.BOMBER_MIN_SPEED)
		# 持续侧翻：bank_angle 一直累加（会越过 ±PI 进入倒飞视觉）
		ac.bank_angle += ac._destroy_bank_rate * delta
		var velocity := Vector2(sin(ac.heading), -cos(ac.heading)) * ac.speed \
			* Aircraft.BOMBER_MOVE_SCALE * ac._destroy_move_mult * GameConstants.PIXELS_PER_METER
		ac.global_position += velocity * delta
		ac.rotation = ac.heading
	elif style == "heli":
		# 直升机坠落：尾桨失效 → 极快自旋 + 中等下坠（约 220 m/s），几乎原地打转下坠
		ac.heading += ac._destroy_spin * delta
		ac.altitude -= Aircraft.HELI_DESCENT_MPS * ac._destroy_descent_mult * delta
		ac.speed = maxf(ac.speed - Aircraft.HELI_SPEED_DECAY \
			* ac._destroy_speed_decay_mult * delta, Aircraft.HELI_MIN_SPEED)
		ac.bank_angle += ac._destroy_bank_rate * delta
		var velocity := Vector2(sin(ac.heading), -cos(ac.heading)) * ac.speed \
			* Aircraft.HELI_MOVE_SCALE * ac._destroy_move_mult * GameConstants.PIXELS_PER_METER
		ac.global_position += velocity * delta
		ac.rotation = ac.heading
	else:
		# 战斗机失控旋转下坠
		ac.heading += ac._destroy_spin * delta
		ac.altitude -= Aircraft.FIGHTER_DESCENT_MPS * ac._destroy_descent_mult * delta
		ac.speed = maxf(ac.speed - Aircraft.FIGHTER_SPEED_DECAY \
			* ac._destroy_speed_decay_mult * delta, Aircraft.FIGHTER_MIN_SPEED)
		ac.bank_angle += ac._destroy_bank_rate * delta
		var velocity := Vector2(sin(ac.heading), -cos(ac.heading)) * ac.speed \
			* ac._destroy_move_mult * GameConstants.PIXELS_PER_METER
		ac.global_position += velocity * delta
		ac.rotation = ac.heading

	ac._destroy_timer -= delta
	if ac._destroy_breakup_emitted:
		_update_post_breakup_linger(ac, delta)
		return
	_update_crash_visual_state(ac)
	if ac._destroy_timer <= 0.0 or ac.altitude <= 0.0:
		ac._destroy_breakup_emitted = true
		ac._destroy_linger_timer = POST_BREAKUP_LINGER_S
		# 爆炸触发帧仍保留清晰机体；禁止“爆一下模型同帧消失”。
		ac._destroy_visual_scale = CRASH_MODEL_END_SCALE
		ac._destroy_visual_alpha = 1.0
		_stop_trail(ac)
		if ac.is_inside_tree():
			_emit_terminal_breakup(ac, style)


## 时间进度与真实高度损失取较大值：低空提前触地时也会缩到终点，
## 高空则严格按各机种的 3.0/3.5/5.0s 演出时长推进。
static func crash_visual_progress(ac: Aircraft) -> float:
	var time_progress := 1.0
	if ac._destroy_duration_total > 0.001:
		time_progress = 1.0 - ac._destroy_timer / ac._destroy_duration_total
	var altitude_progress := 1.0 - clampf(
		ac.altitude / maxf(ac._destroy_start_altitude, 1.0), 0.0, 1.0)
	return clampf(maxf(time_progress, altitude_progress), 0.0, 1.0)


static func _update_crash_visual_state(ac: Aircraft) -> void:
	var progress := crash_visual_progress(ac)
	var shrink_t := smoothstep(CRASH_SHRINK_START_PROGRESS, 1.0, progress)
	ac._destroy_visual_scale = lerpf(1.0, CRASH_MODEL_END_SCALE, shrink_t)
	# 失控与终点爆炸触发帧始终可见；透明度只在爆炸后的保留阶段下降。
	ac._destroy_visual_alpha = 1.0


## 终点爆炸后继续保留真实机体并沿原失控轨迹运动。先完全不透明停留 0.25s，
## 再平滑淡出；只有 0.85s 保留期结束才释放，杜绝爆炸与模型消失同帧发生。
static func _update_post_breakup_linger(ac: Aircraft, delta: float) -> void:
	ac._destroy_linger_timer = maxf(ac._destroy_linger_timer - delta, 0.0)
	var elapsed := POST_BREAKUP_LINGER_S - ac._destroy_linger_timer
	var fade_t := smoothstep(POST_BREAKUP_OPAQUE_S, POST_BREAKUP_LINGER_S, elapsed)
	ac._destroy_visual_scale = lerpf(
		CRASH_MODEL_END_SCALE, POST_BREAKUP_END_SCALE, fade_t)
	ac._destroy_visual_alpha = 1.0 - fade_t
	if ac._destroy_linger_timer <= 0.0:
		ac.queue_free()


static func _breakup_scale_for(style: String) -> float:
	match style:
		"bomber":
			return 1.65
		"heli":
			return 1.15
		_:
			return 1.0


static func _emit_terminal_breakup(ac: Aircraft, style: String) -> void:
	if ac._destroy_size_class == SIZE_LARGE:
		_emit_airframe_wave(ac, _breakup_scale_for(style), 0.0,
			_large_breakup_route(ac))
		return
	var scale := UNMANNED_BREAKUP_SCALE \
		if ac.params != null and ac.params.is_unmanned else SMALL_AIRFRAME_BREAKUP_SCALE
	ExplosionVFX.emit(ac.get_tree(), ac.global_position, ac.heading, scale)


static func _large_breakup_route(ac: Aircraft) -> int:
	match ac._last_hit_zone:
		HIT_NOSE:
			return 0 if ac._last_hit_local_norm.y <= 0.0 else 1
		HIT_TAIL_ENGINE:
			return 2
		HIT_PORT_WING, HIT_STARBOARD_WING:
			return 3
		_:
			return ac._destroy_random_seed % 4


## 从飞机实际绘制尺度反推局部半长/半翼展；爆点因此贴合不同机型，而非固定圆环。
static func _airframe_half_extents(ac: Aircraft) -> Vector2:
	var length_m := 18.0
	var span_m := 12.0
	if ac.params != null:
		length_m = maxf(ac.params.visual_length_m, 1.0)
		span_m = maxf(ac.params.visual_span_m, 1.0)
	var max_extent_m := maxf(length_m, span_m)
	var icon_radius := AircraftRenderer.AIRCRAFT_ICON_HALF_EXTENT_WORLD \
		* AircraftRenderer.altitude_base_scale(ac) \
		* AircraftRenderer.visual_model_scale(ac) \
		* AircraftSilhouetteCatalog.draw_scale_for(ac)
	return Vector2(
		maxf(icon_radius * length_m / max_extent_m, 8.0),
		maxf(icon_radius * span_m / max_extent_m, 8.0))


static func _emit_airframe_wave(ac: Aircraft, scale: float, initial_delay: float,
		route: int = -1) -> void:
	if not ac.is_inside_tree():
		return
	var half_extents := _airframe_half_extents(ac)
	ExplosionVFX.emit_airframe_wave(
		ac.get_tree(), ac.global_position, ac.heading,
		half_extents.x, half_extents.y, scale, route, initial_delay)


static func _stop_trail(ac: Aircraft) -> void:
	ac.clear_trail()
	if ac._trail_ribbon != null and is_instance_valid(ac._trail_ribbon):
		ac._trail_ribbon.set_emission_enabled(false)
