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
## 躲弹中放焰距离（像素，≈3km）：AI 躲弹是满加力朝远点猛冲，会把追来的导弹一直甩在
## 常规 release_dist 之外 → 永远不放焰 → 导弹烧到寿命尽头才解除（十几秒乱飞、脱队"查无此人"）。
## 躲弹中把释放距离抬到这里，让飞机尽早放焰干扰；guaranteed-jam 飞行员一发即 jam → 下一 tick
## find_nearest_incoming_missile 过滤掉它 → process_evade 退出 → 立刻归位。
const EVADE_FLARE_RELEASE_DIST: float = 1500.0
const FLARE_IGNORE_CLEANUP_S := 2.0            ## 已忽略导弹清理间隔（秒）
const FLARE_PARTICLE_DRAG := 0.96              ## 粒子速度衰减率
const FLARE_PARTICLE_JITTER := 3.0             ## 粒子随机抖动幅度
const FLARE_SPREAD_MAX := 0.6                  ## 扩散角最大值
const FLARE_VEL_MIN := 70.0                    ## 粒子速度下限
const FLARE_VEL_MAX := 130.0                   ## 粒子速度上限
const FLARE_SPAWN_DIST_MIN := 8.0              ## 生成距离下限
const FLARE_SPAWN_DIST_MAX := 15.0             ## 生成距离上限
const FLARE_SPAWN_PERP_MAX := 4.0              ## 生成横向偏移最大值
const FLARE_LIFE_MIN := 2.0                    ## 粒子寿命下限（秒）
const FLARE_LIFE_MAX := 3.5                    ## 粒子寿命上限（秒）

# ── 玩家方智能放焰（TTI 触发，2026-06-14）──
# 用户反馈：玩家/僚机经常在导弹还很远、甚至对速度慢追不上的导弹就放焰，很浪费。
# 玩家方改为按"命中剩余时间(TTI)"判定：只对【正在逼近(会命中)且即将到达】的导弹放焰。
# 敌方 AI 路径不变（维持难度）。
const FLARE_TTI_THRESHOLD := 1.5      ## 命中剩余时间 ≤ 此值(s)才放焰（确保导弹确实即将命中）
const FLARE_MIN_DIST_M := 300.0       ## 距离 ≤ 此值(m)的逼近导弹无条件放焰（终端兜底，防慢速 TTI 偏大漏放）
const FLARE_MIN_CLOSING_MS := 30.0    ## 闭合速度 < 此值(m/s) → 追不上/在远离 → 不是会命中的威胁，绝不放焰

# ── 僚机护卫 flare（spec wingman-escort-evasion §2.2）──
# 玩家按 E 进护卫姿态时，编队待命的僚机替长机投焰干扰追长机的导弹。
const ESCORT_FLARE_LEADER_RANGE_M := 800.0  ## 僚机距长机 ≤ 此值才能护卫投焰（约编队槽位尺度）
const ESCORT_BASE_JAM := 0.70               ## 僚机紧贴长机(距离≈0)时干扰概率上限；按近度线性衰减到 0

const _BURST_WAVE_COUNT := 6                   ## 视觉分波数
const _BURST_WAVE_INTERVAL := 0.12             ## 每波间隔（秒）
const FLARE_VISUAL_WAVE_COUNTS := [2, 2, 1, 2, 2, 1]  ## 保留六波节奏，总数严格 10

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
		# 护卫 flare 单弹单次记录同节奏清理失效引用
		var esc_remove: Array = []
		for mid2 in ac._escort_flare_tried:
			if not is_instance_id_valid(mid2):
				esc_remove.append(mid2)
		for mid2 in esc_remove:
			ac._escort_flare_tried.erase(mid2)

	# 更新锁定免疫计时
	if ac._lock_immunity_timer > 0.0:
		ac._lock_immunity_timer = maxf(ac._lock_immunity_timer - delta, 0.0)
	# 更新导弹穿透计时
	if ac.missile_phase_timer > 0.0:
		ac.missile_phase_timer = maxf(ac.missile_phase_timer - delta, 0.0)

	# 粒子
	_update_particles(ac, delta)

	# 释放/装填冷却：规避与低血修饰统一由 cd_rate("flare") 结算。
	var cd_decrement: float = delta * ac.cd_rate("flare")
	if ac.enable_flare_reload and ac.flares_remaining <= 0:
		cd_decrement *= ac.esm_reload_rate_multiplier()
	ac._flare_cooldown = maxf(ac._flare_cooldown - cd_decrement, 0.0)

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
	# 嘘！：JAM 敌机不能释放热诱弹；装填与冷却本身仍正常推进。
	if SkillHooks.hush_blocks_flare(ac):
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

	# 胆大妄为：禁普通自动 flare——受控机交给 R，AI 僚机交给 Aircraft 的威胁自动入口
	if ac.manual_dodge_active:
		return

	# 检测最近来袭导弹（玩家方同时挑选"会命中且即将到达"的最近一枚作为放焰目标）
	var nearest_missile: Missile = null
	var nearest_dist := 99999.0
	var player_trigger_missile: Missile = null
	var player_trigger_dist := 99999.0
	var is_player_side: bool = ac.is_player_squad()
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
		# 玩家方智能放焰：只把"正在逼近(会命中) + TTI 够短/已很近"的导弹列为放焰目标
		if is_player_side and dist_px < player_trigger_dist and player_flare_should_trigger(ac, m):
			player_trigger_dist = dist_px
			player_trigger_missile = m

	if not nearest_missile:
		return

	# ── AI 机动优先（Cobra / Herbst）──
	# AI 僚机持有眼镜蛇或危机赫尔贝特技能且机动可用时，
	# 让机动在 ~300px (COBRA_MISSILE_TRIGGER_PX) 处接管这枚导弹（机动期间物理免疫，
	# 比 flare 概率拦截更稳）。这里抑制 flare 释放，避免提前烧 flare 后让机动闲置。
	# 当前操控机的大机动只听 R，未按 R 时不得压住正常自动 flare。
	# 若 AI 机动正在冷却 / 已经用完 → 落回 flare 兜底。
	if not ac.is_manual_maneuver_controlled():
		var cobra_ready: bool = false
		if ac.cobra_skill_active and ac._cobra_skill_cooldown <= 0.0:
			var mf := ac.get_maneuver()
			cobra_ready = mf != null and not mf.is_active
		var herbst_ready: bool = false
		if ac.evasion_herbst_active:
			var hm := ac.get_herbst()
			herbst_ready = hm != null and hm.can_activate
		if cobra_ready or herbst_ready:
			return

	var fp := ac.params.flare
	if is_player_side:
		# ── 玩家方智能放焰：导弹必须"会命中且即将到达"（player_flare_should_trigger）才放 ──
		# 替代旧的"性格距离 + 躲弹 3km 抬升"：不再对慢速/追不上的导弹浪费诱饵，也不再在导弹
		# 还在远处就提前甩光仅有的几发。无符合条件的来袭导弹 → 直接不放。
		if player_trigger_missile == null:
			return
		nearest_missile = player_trigger_missile
		nearest_dist = player_trigger_dist
	else:
		# 敌方 AI：保留原"性格距离 + 躲弹 3km 抬升"逻辑（维持难度，不变）
		var release_dist_m := lerpf(fp.calm_distance, fp.panic_distance, fp.nervousness)
		var release_dist_px := release_dist_m * CombatUnit.PIXELS_PER_METER
		var is_evading: bool = ac.evasion_mode \
				or (ac._ai_ref != null and ac._ai_ref._evading)
		if is_evading:
			release_dist_px = maxf(release_dist_px, EVADE_FLARE_RELEASE_DIST)
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

## 玩家方智能放焰判定：这枚导弹是否值得现在放焰。
## 规则（满足"会命中(逼近) 且 即将到达"才放）：
##   1. 闭合速度 < FLARE_MIN_CLOSING_MS → 追不上/在远离 → 不会命中 → 不放（杜绝对慢速导弹浪费）。
##   2. 否则按命中剩余时间 TTI = 距离 / 闭合速度：TTI ≤ 阈值 → 即将命中 → 放。
##   3. 兜底：距离 ≤ FLARE_MIN_DIST_M 的逼近导弹无条件放（防慢速逼近 TTI 偏大却已贴脸漏放）。
## 纯几何判断（无副作用），可单测。closing = (导弹速度 − 本机速度) 在 LOS 上的投影。
static func player_flare_should_trigger(ac: Aircraft, m: Missile) -> bool:
	var los: Vector2 = ac.global_position - m.global_position
	var dist_px: float = los.length()
	if dist_px < 1.0:
		return true
	var los_n: Vector2 = los / dist_px
	var v_ac: Vector2 = Vector2(sin(ac.heading), -cos(ac.heading)) * ac.speed
	var v_m: Vector2 = Vector2(sin(m.heading), -cos(m.heading)) * m.speed
	var closing_ms: float = (v_m - v_ac).dot(los_n)   # >0 = 间距在缩小（导弹在逼近）
	if closing_ms < FLARE_MIN_CLOSING_MS:
		return false
	var dist_m: float = dist_px / CombatUnit.PIXELS_PER_METER
	if dist_m <= FLARE_MIN_DIST_M:
		return true
	return (dist_m / closing_ms) <= FLARE_TTI_THRESHOLD


## target_missile：本次释放"瞄准"的那枚来袭导弹。
## 一次热诱弹释放只能诱骗一枚导弹（flare 是一次性诱饵），
## 不会连带把同期在飞的其它导弹全部干扰。
static func release(ac: Aircraft, target_missile: Missile = null) -> void:
	if SkillHooks.hush_blocks_flare(ac):
		return
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

	# §1.3 + §1.4 玩家技能：发射 flare 给周围敌方施加 JAM
	# 早退检查：仅玩家小队 + 持有 SKILL_FLARE_AOE_JAM
	if ac.is_player_squad() and ac.has_meta("upgrade_stacks"):
		var stacks: Dictionary = ac.get_meta("upgrade_stacks")
		if int(stacks.get(SkillHooks.SKILL_FLARE_AOE_JAM, 0)) > 0:
			var fa_hits: int = AOEBroadcast.apply_status_in_radius(
				ac.global_position,
				SkillHooks.FLARE_AOE_JAM_RADIUS_PX,
				1, StatusEffects.JAM,
				SkillHooks.FLARE_AOE_JAM_DURATION,
				ac)
			SkillHooks.on_player_jam_landed(ac, fa_hits)

	# 玩家技能"焰诱共振"：释放热诱弹后获得 OVERLOAD（与 jam 是否成功无关）
	if ac.is_player_squad():
		SkillHooks.on_flare_release(ac)

	# 722 sig_mirage3·幻影：flare 保护窗（穿透窗 + 锁定豁免）时长 ×1.6
	var sig_m3: bool = ac.has_meta("upgrade_stacks") \
			and int((ac.get_meta("upgrade_stacks") as Dictionary).get("sig_mirage3", 0)) > 0
	# 导弹穿透窗口：玩家 / BOSS 享有
	if ac.flares_guaranteed or ac.boss_flare_immunity:
		ac.missile_phase_timer = MISSILE_PHASE_DURATION * (1.6 if sig_m3 else 1.0)

	# 电子对抗升级：清除所有雷达锁定 + 锁定免疫
	if ac.flare_lock_immunity > 0.0:
		ac._lock_immunity_timer = ac.flare_lock_immunity * (1.6 if sig_m3 else 1.0)
		for ac_ref in ac.locked_by.duplicate():
			if is_instance_valid(ac_ref):
				ac_ref.radar_targets.erase(ac)
		ac.locked_by.clear()
		ac.is_locked = false

	_queue_visual_burst(ac)

	# 只对触发释放的这枚判定干扰
	if target_missile == null or not is_instance_valid(target_missile):
		return
	if not target_missile.is_active or target_missile.is_flare_jammed:
		return
	if target_missile.target != ac:
		return

	var jam_chance: float
	if AceTier.is_ace(ac):
		# 王牌中队：热诱弹即命数，干扰恒定 100%（spec ace-squadron-tier §3.3）。
		# 引入概率会让"1 枚 = 1 条命"不成立 —— 玩家无法从"骗掉几发"推断剩余命数，
		# 且迎头交战时命数会随机蒸发（正是 Wraith"偶尔一发就死"的体感来源）
		jam_chance = 1.0
	elif ac.flares_guaranteed:
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
		# §1.4 玩家技能钩子：成功回避导弹 → 给自己 OVERLOAD 4s
		SkillHooks.on_evade_missile(ac)
		# 722 签名技能（低频事件，就地读 meta；此处独有 target_missile 上下文）：
		if ac.is_player_squad() and ac.has_meta("upgrade_stacks"):
			var sig_stacks: Dictionary = ac.get_meta("upgrade_stacks")
			# 幻影（Mirage III）：成功偏转瞬间 1.5s 无敌（no_refresh 严格窗）
			if int(sig_stacks.get("sig_mirage3", 0)) > 0:
				ac.apply_status(StatusEffects.INVINCIBLE, 1.5, "no_refresh")
			# SPECTRA（Rafale）：对该弹发射者施加 5s JAM
			if int(sig_stacks.get("sig_rafale", 0)) > 0 \
					and is_instance_valid(target_missile.source) \
					and target_missile.source is CombatUnit:
				(target_missile.source as CombatUnit).apply_status(StatusEffects.JAM, 5.0)
				EventLogger.log_event("SKILL", ac._log_name(),
					"SPECTRA: jam shooter %s for 5s" % target_missile.source.callsign)
				# 729 补：SPECTRA 也是玩家 JAM 来源，须走同一钩子（共振反馈的前置之一）
				SkillHooks.on_player_jam_landed(ac, 1)
	else:
		# 失败也记日志（2026-07-03 补观测盲区：旧版只记成功，"投了焰仍被命中"无法归因）
		var msl_name_f: String = target_missile.params.display_name if target_missile.params else "MSL"
		EventLogger.log_event("MISSILE", msl_name_f,
			"flare FAILED to jam (target %s, jam_chance=%.0f%%, missile still tracking)" % [
				ac._log_name(), jam_chance * 100.0])

## 护卫 flare（spec wingman-escort-evasion §3.2）：编队待命的僚机替长机投焰，
## 干扰【追长机】且【即将命中长机】的导弹。仅玩家方僚机在长机护卫广播期间由
## SquadCoordination.process_squad_follow 调用。返回是否投了焰。
## 门：玩家方 + 长机有效 + flare 就绪（与自卫同套门）+ 距长机 ≤ 800m + 有合格目标导弹。
## ★全队协调（一次只有一架）：选定目标导弹后，只有「同队就绪僚机中离长机最近」的那架出手；
##   它若没干扰成功（进 CD + 标记已试），下一帧次近的僚机才接手 → 任一时刻只一架在喷焰，
##   且优先让位置最好（jam 概率最高）的去做，失败有顺序兜底。
static func try_cover_flare(ac: Aircraft, leader: Aircraft) -> bool:
	if leader == null or not is_instance_valid(leader) or leader.is_destroyed:
		return false
	if not flare_ready(ac):
		return false
	# 距长机门
	var d_leader_m: float = ac.global_position.distance_to(leader.global_position) / CombatUnit.PIXELS_PER_METER
	if d_leader_m > ESCORT_FLARE_LEADER_RANGE_M:
		return false
	# 选目标：本机可护卫（追长机 + 即将命中 + 未试过）的最近一枚导弹
	var best: Missile = null
	var best_dist := 99999.0
	for child in ac.missile_manager.get_children():
		if not child is Missile:
			continue
		var m: Missile = child
		if not _escort_missile_qualifies(ac, leader, m):
			continue
		var d := m.global_position.distance_to(ac.global_position)
		if d < best_dist:
			best_dist = d
			best = m
	if best == null:
		return false
	# 全队裁决：仅当本机是这枚导弹的"最佳护卫者"（就绪僚机里离长机最近）才出手
	if not _is_best_escort_for(ac, leader, best):
		return false
	ac._escort_flare_tried[best.get_instance_id()] = true
	release_cover(ac, leader, best, d_leader_m)
	return true

## 护卫 jam 概率（纯函数，可单测）：贴脸 ESCORT_BASE_JAM → 距长机 ≥800m 时趋 0 线性衰减。
static func escort_jam_chance(d_leader_m: float) -> float:
	var proximity: float = clampf(1.0 - d_leader_m / ESCORT_FLARE_LEADER_RANGE_M, 0.0, 1.0)
	return ESCORT_BASE_JAM * proximity

## flare 就绪门（护卫 flare / 自卫 flare / 规避入口门三方共用同套：
## 玩家方 + 有 flare + 弹量/CD/隐身/穿透/机动）
## B1 分层规避（2026-07-02）也用它判定"flare 还能兜底 → 不进运动学规避"。
static func flare_ready(ac: Aircraft) -> bool:
	if ac == null or not is_instance_valid(ac) or ac.is_destroyed:
		return false
	if not ac.is_player_squad() or not ac.params or not ac.params.flare or not ac.missile_manager:
		return false
	if ac.flares_remaining <= 0 or ac._flare_cooldown > 0.0:
		return false
	if ac.is_cloaked or ac.suppress_flares or ac.missile_phase_timer > 0.0:
		return false
	var mf := ac.get_maneuver()
	if mf and mf.is_active:
		return false
	return true

## 这枚导弹是否是 ac 可护卫的合格目标：在追长机 + 即将命中长机 + ac 本机还没试过
static func _escort_missile_qualifies(ac: Aircraft, leader: Aircraft, m: Missile) -> bool:
	if not m.is_active or m.is_flare_jammed:
		return false
	if m.target != leader:
		return false
	if ac._escort_flare_tried.has(m.get_instance_id()):
		return false
	return player_flare_should_trigger(leader, m)

## 全队裁决：在同队、就绪、且这枚导弹对其同样合格的僚机中，ac 是否离长机最近（一次只一架）。
## 平局用 instance_id 决断，保证多架同帧 tick 结果一致、恰好一架通过。
static func _is_best_escort_for(ac: Aircraft, leader: Aircraft, m: Missile) -> bool:
	var ai: AIController = ac._ai_ref
	if ai == null or ai.squad == null:
		return true  # 无队信息（理论不至）→ 退化为本机自行护卫
	var range_px: float = ESCORT_FLARE_LEADER_RANGE_M * CombatUnit.PIXELS_PER_METER
	var my_d: float = ac.global_position.distance_to(leader.global_position)
	for other in ai.squad.members:
		if other == ac or other == leader:
			continue
		if not flare_ready(other):
			continue
		if other.global_position.distance_to(leader.global_position) > range_px:
			continue
		if not _escort_missile_qualifies(other, leader, m):
			continue
		var od: float = other.global_position.distance_to(leader.global_position)
		# 更近的僚机优先；等距用 instance_id 决断
		if od < my_d or (od == my_d and other.get_instance_id() < ac.get_instance_id()):
			return false
	return true

## 护卫投焰落地：粒子 / 弹量 / CD 复用 release 的逻辑，但 jam 判定对【追 leader 的导弹】，
## 概率用近度公式 escort_jam_chance（贴脸 ESCORT_BASE_JAM → 800m 处趋 0），不走 calc_jam_chance
## 那套自卫视角的角度/机动加成。不触发玩家自卫技能钩子（护卫是僚机行为，非玩家自卫）。
static func release_cover(ac: Aircraft, leader: Aircraft, target_missile: Missile, d_leader_m: float) -> void:
	var fp := ac.params.flare
	var count := mini(fp.burst_count, ac.flares_remaining)
	ac.flares_remaining -= count
	if ac.flares_remaining <= 0 and ac.enable_flare_reload:
		ac._flare_cooldown = fp.reload_time
	else:
		ac._flare_cooldown = fp.cooldown

	# 分批释放视觉粒子（与 release 同款，从机尾逐颗弹出）
	_queue_visual_burst(ac)

	if target_missile == null or not is_instance_valid(target_missile):
		return
	if not target_missile.is_active or target_missile.is_flare_jammed:
		return
	if target_missile.target != leader:
		return

	var jam_chance: float = escort_jam_chance(d_leader_m)
	EventLogger.log_event("ESCORT_FLARE", ac._log_name(),
		"covering %s (d=%.0fm jam=%.0f%%)" % [leader.callsign, d_leader_m, jam_chance * 100.0])
	if randf() < jam_chance:
		target_missile.is_flare_jammed = true
		var msl_name: String = target_missile.params.display_name if target_missile.params else "MSL"
		EventLogger.log_event("MISSILE", msl_name,
			"escort flare jammed (was chasing %s)" % leader.callsign)
	else:
		var msl_name_f: String = target_missile.params.display_name if target_missile.params else "MSL"
		EventLogger.log_event("MISSILE", msl_name_f,
			"escort flare FAILED (still chasing %s, jam_chance=%.0f%%)" % [
				leader.callsign, jam_chance * 100.0])
		# 成功护卫触发一次滚转动画（视觉反馈）
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
			var wave_count: int = int(q.get("count", 0))
			_spawn_wave(ac, q["pos"] as Vector2, float(q["heading"]), wave_count)
			ac.flare_visual_burst_emitted = mini(
				ac.flare_visual_burst_emitted + wave_count, 10)
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

## 保留既有 6 波 / 0.12s 节奏，但固定每波数量，使一次投放严格等于 HUD 的 10 颗星。
static func _queue_visual_burst(ac: Aircraft) -> void:
	ac.flare_visual_burst_emitted = 0
	for w in range(_BURST_WAVE_COUNT):
		ac._flare_spawn_queue.append({
			"delay": float(w) * _BURST_WAVE_INTERVAL,
			"heading": ac.heading,
			"pos": ac.global_position,
			"count": int(FLARE_VISUAL_WAVE_COUNTS[w]),
		})


## 生成一波热诱弹粒子（从飞机当前位置向后方喷射）
static func _spawn_wave(ac: Aircraft, spawn_pos: Vector2, spawn_heading: float, wave_count: int) -> void:
	var back_dir := Vector2(-sin(spawn_heading), cos(spawn_heading))
	var perp := Vector2(back_dir.y, -back_dir.x)
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
