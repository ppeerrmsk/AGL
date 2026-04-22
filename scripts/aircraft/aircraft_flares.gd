class_name AircraftFlares
extends RefCounted

## 热诱弹子系统（静态工具类）
## 从 aircraft.gd 提取的 _update_flares / _release_flares / _calc_jam_chance /
## _update_flare_particles / _spawn_flare_wave 全套逻辑。
##
## 状态仍住在 Aircraft（flares_remaining / _flare_cooldown / _flare_particles /
## _flare_spawn_queue / _flare_ignored_missiles / missile_phase_timer / _lock_immunity_timer）。
## 本模块不持有状态，只在 ac 上读写 + 调 missile_manager。
##
## 调用约定（来自 aircraft.gd _physics_process）：
##   AircraftFlares.update(self, delta)

const MISSILE_PHASE_DURATION: float = 1.0     ## 热诱弹释放后的导弹穿透窗口（秒）
const FLARE_IGNORE_CLEANUP_S := 2.0            ## 已忽略导弹清理间隔（秒）
const FLARE_PARTICLE_DRAG := 0.96              ## 粒子速度衰减率
const FLARE_PARTICLE_JITTER := 3.0             ## 粒子随机抖动幅度
const FLARE_WAVE_MIN := 2                      ## 每波热诱弹最少数
const FLARE_WAVE_MAX := 3                      ## 每波热诱弹最多数
const FLARE_SPREAD_MAX := 0.6                  ## 扩散角最大值
const FLARE_VEL_MIN := 70.0                    ## 粒子速度下限
const FLARE_VEL_MAX := 130.0                   ## 粒子速度上限
const FLARE_SPAWN_DIST_MIN := 8.0              ## 生成距离下限
const FLARE_SPAWN_DIST_MAX := 15.0             ## 生成距离上限
const FLARE_SPAWN_PERP_MAX := 4.0              ## 生成横向偏移最大值
const FLARE_LIFE_MIN := 2.0                    ## 粒子寿命下限（秒）
const FLARE_LIFE_MAX := 3.5                    ## 粒子寿命上限（秒）

const _BURST_WAVE_COUNT := 6                   ## 视觉分波数
const _BURST_WAVE_INTERVAL := 0.12             ## 每波间隔（秒）

## 主入口：每帧由 aircraft._physics_process 调用
static func update(ac: Aircraft, delta: float) -> void:
	# 定期清理失误记录中已失效的导弹引用
	ac._flare_ignored_cleanup += delta
	if ac._flare_ignored_cleanup >= FLARE_IGNORE_CLEANUP_S:
		ac._flare_ignored_cleanup = 0.0
		var to_remove: Array = []
		for mid in ac._flare_ignored_missiles:
			if not is_instance_id_valid(mid):
				to_remove.append(mid)
		for mid in to_remove:
			ac._flare_ignored_missiles.erase(mid)

	# 更新锁定免疫计时
	if ac._lock_immunity_timer > 0.0:
		ac._lock_immunity_timer = maxf(ac._lock_immunity_timer - delta, 0.0)
	# 更新导弹穿透计时
	if ac.missile_phase_timer > 0.0:
		ac.missile_phase_timer = maxf(ac.missile_phase_timer - delta, 0.0)

	# 粒子
	_update_particles(ac, delta)

	# 释放冷却
	ac._flare_cooldown = maxf(ac._flare_cooldown - delta, 0.0)

	if not ac.params or not ac.params.flare:
		return

	# 自动装填（生存模式）
	if ac.enable_flare_reload and ac.flares_remaining <= 0:
		if ac._flare_cooldown > 0.0:
			ac.flare_reload_progress = 1.0 - (ac._flare_cooldown / ac.params.flare.reload_time)
		else:
			ac.flares_remaining = ac.params.flare.max_flares
			ac.flare_reload_progress = 0.0
		return

	ac.flare_reload_progress = 0.0
	if ac.flares_remaining <= 0:
		return
	if ac._flare_cooldown > 0.0:
		return
	if not ac.missile_manager:
		return
	# 战术机动中不释放（机动本身提供免疫）
	var _mf := ac.get_maneuver()
	if _mf and _mf.is_active:
		return
	# 导弹穿透窗口期：再放浪费
	if ac.missile_phase_timer > 0.0:
		return
	# 隐形中或隐形即将可用时不释放
	if ac.is_cloaked or ac.suppress_flares:
		return

	# 检测最近来袭导弹
	var nearest_missile: Missile = null
	var nearest_dist := 99999.0
	for child in ac.missile_manager.get_children():
		if not child is Missile:
			continue
		var m: Missile = child
		if not m.is_active or m.is_flare_jammed:
			continue
		if m.target != ac:
			continue
		var dist_px := m.global_position.distance_to(ac.global_position)
		if dist_px < nearest_dist:
			nearest_dist = dist_px
			nearest_missile = m

	if not nearest_missile:
		return

	# 根据性格计算释放距离
	var fp := ac.params.flare
	var release_dist_m := lerpf(fp.calm_distance, fp.panic_distance, fp.nervousness)
	var release_dist_px := release_dist_m * CombatUnit.PIXELS_PER_METER

	if nearest_dist > release_dist_px:
		return

	# 失误判定
	if fp.fail_chance > 0.0:
		var mid := nearest_missile.get_instance_id()
		if ac._flare_ignored_missiles.has(mid):
			return
		var actual_fail := fp.fail_chance
		# Lancer 对头冲刺更警觉
		if fp.head_on_fail_reduction > 0.0:
			var my_dir := Vector2(sin(ac.heading), -cos(ac.heading))
			var missile_dir := (nearest_missile.global_position - ac.global_position).normalized()
			if my_dir.dot(missile_dir) > 0.5:
				actual_fail = maxf(actual_fail - fp.head_on_fail_reduction, 0.0)
		if randf() < actual_fail:
			ac._flare_ignored_missiles[mid] = true
			return

	release(ac, nearest_missile)

## target_missile：本次释放"瞄准"的那枚来袭导弹。
## 一次热诱弹释放只能诱骗一枚导弹（flare 是一次性诱饵），
## 不会连带把同期在飞的其它导弹全部干扰。
static func release(ac: Aircraft, target_missile: Missile = null) -> void:
	var fp := ac.params.flare
	var count := mini(fp.burst_count, ac.flares_remaining)
	ac.flares_remaining -= count
	# 用完后进入长装填冷却
	if ac.flares_remaining <= 0 and ac.enable_flare_reload:
		ac._flare_cooldown = fp.reload_time
	else:
		ac._flare_cooldown = fp.cooldown
	EventLogger.log_event("FLARE", ac._log_name(),
		"deployed %d flares (remaining=%d)" % [count, ac.flares_remaining])

	# 导弹穿透窗口：玩家 / BOSS 享有
	if ac.flares_guaranteed or ac.boss_flare_immunity:
		ac.missile_phase_timer = MISSILE_PHASE_DURATION

	# 电子对抗升级：清除所有雷达锁定 + 锁定免疫
	if ac.flare_lock_immunity > 0.0:
		ac._lock_immunity_timer = ac.flare_lock_immunity
		for ac_ref in ac.locked_by.duplicate():
			if is_instance_valid(ac_ref):
				ac_ref.radar_targets.erase(ac)
		ac.locked_by.clear()
		ac.is_locked = false

	# 分批释放视觉粒子（逐颗弹出）
	for w in range(_BURST_WAVE_COUNT):
		ac._flare_spawn_queue.append({
			"delay": float(w) * _BURST_WAVE_INTERVAL,
			"heading": ac.heading,
			"pos": ac.global_position,
		})

	# 只对触发释放的这枚判定干扰
	if target_missile == null or not is_instance_valid(target_missile):
		return
	if not target_missile.is_active or target_missile.is_flare_jammed:
		return
	if target_missile.target != ac:
		return

	var jam_chance: float
	if ac.flares_guaranteed:
		# 后侧方 + 斜前方 100% 干扰，只有正面对冲走概率
		var missile_to_me := (ac.global_position - target_missile.global_position).normalized()
		var my_fwd := Vector2(sin(ac.heading), -cos(ac.heading))
		var dot := my_fwd.dot(missile_to_me)
		if dot <= 0.6:
			jam_chance = 1.0
		else:
			jam_chance = calc_jam_chance(ac, target_missile)
	else:
		jam_chance = calc_jam_chance(ac, target_missile)
	if randf() < jam_chance:
		target_missile.is_flare_jammed = true
		var msl_name: String = target_missile.params.display_name if target_missile.params else "MSL"
		EventLogger.log_event("MISSILE", msl_name,
			"flare jammed (target was %s, jam_chance=%.0f%%)" % [
				ac._log_name(), jam_chance * 100.0])
		# 热诱弹成功干扰时触发一次滚转动画
		if ac._evade_roll_remaining <= 0.0 and ac._evade_roll_cooldown <= 0.0:
			ac._evade_roll_remaining = Aircraft._EVADE_ROLL_DURATION

static func calc_jam_chance(ac: Aircraft, m: Missile) -> float:
	var fp := ac.params.flare
	var chance := fp.base_jam_chance

	# 来袭角度
	var missile_to_me := (ac.global_position - m.global_position).normalized()
	var my_fwd := Vector2(sin(ac.heading), -cos(ac.heading))
	var dot := my_fwd.dot(missile_to_me)
	if dot < 0.0:
		chance += fp.aspect_bonus

	# 大幅机动
	if ac.g_load > 4.0:
		chance += fp.maneuvering_bonus

	# 极近距离惩罚
	var dist_m := m.global_position.distance_to(ac.global_position) / CombatUnit.PIXELS_PER_METER
	if dist_m < 150.0:
		chance -= fp.close_range_penalty

	# 低能量
	if m.age > m.params.motor_burn_time:
		chance += fp.low_energy_bonus

	return clampf(chance, 0.05, 0.95)

## 热诱弹冷却比例（0=就绪, 1=刚释放），HUD 读取用
static func cooldown_ratio(ac: Aircraft) -> float:
	if not ac.params or not ac.params.flare or ac.params.flare.cooldown <= 0.0:
		return 0.0
	var divisor := ac.params.flare.reload_time if (ac.enable_flare_reload and ac.flares_remaining <= 0) else ac.params.flare.cooldown
	return clampf(ac._flare_cooldown / divisor, 0.0, 1.0)

static func _update_particles(ac: Aircraft, delta: float) -> void:
	# 处理延迟释放队列
	var remaining_queue: Array[Dictionary] = []
	for q in ac._flare_spawn_queue:
		q["delay"] -= delta
		q["pos"] = ac.global_position   # 跟随飞机
		q["heading"] = ac.heading
		if float(q["delay"]) <= 0.0:
			_spawn_wave(ac, q["pos"] as Vector2, float(q["heading"]))
		else:
			remaining_queue.append(q)
	ac._flare_spawn_queue = remaining_queue

	# 更新已有粒子
	var kept: Array[Dictionary] = []
	for p in ac._flare_particles:
		p["life"] -= delta
		if float(p["life"]) <= 0.0:
			continue
		p["pos"] = (p["pos"] as Vector2) + (p["vel"] as Vector2) * delta
		var vel: Vector2 = p["vel"] as Vector2
		vel *= FLARE_PARTICLE_DRAG
		vel += Vector2(randf_range(-FLARE_PARTICLE_JITTER, FLARE_PARTICLE_JITTER), randf_range(-FLARE_PARTICLE_JITTER, FLARE_PARTICLE_JITTER))
		p["vel"] = vel
		kept.append(p)
	ac._flare_particles = kept

## 生成一波热诱弹粒子（从飞机当前位置向后方喷射）
static func _spawn_wave(ac: Aircraft, spawn_pos: Vector2, spawn_heading: float) -> void:
	var back_dir := Vector2(-sin(spawn_heading), cos(spawn_heading))
	var perp := Vector2(back_dir.y, -back_dir.x)
	var wave_count := randi_range(FLARE_WAVE_MIN, FLARE_WAVE_MAX)
	for k in range(wave_count):
		var spread := randf_range(-FLARE_SPREAD_MAX, FLARE_SPREAD_MAX)
		var vel := (back_dir + perp * spread) * randf_range(FLARE_VEL_MIN, FLARE_VEL_MAX)
		var is_bright := k == 0
		ac._flare_particles.append({
			"pos": spawn_pos + back_dir * randf_range(FLARE_SPAWN_DIST_MIN, FLARE_SPAWN_DIST_MAX) + perp * randf_range(-FLARE_SPAWN_PERP_MAX, FLARE_SPAWN_PERP_MAX),
			"vel": vel,
			"life": randf_range(FLARE_LIFE_MIN, FLARE_LIFE_MAX),
			"bright": is_bright,
		})
