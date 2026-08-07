class_name RailgunEquipment
extends EquipmentParams

## 电磁炮装备（commit 8/13 — 第一个全新机制装备）
##
## 核心机制：
## 1. **Telegraph 充能**：进入开火意图 → 扇形 UI 从初始角度收缩为 0° （charge_duration 内）
## 2. **弹道锁定时机**：AT_CHARGE_START（敌人版，扇形开始就锁死轨迹）/
##    AT_FIRE_TIME（玩家版，开火瞬间才锁死）。决定玩家能否通过机动躲避
## 3. **Hitscan + 闪电视觉**：发射瞬间命中（projectile_speed = ∞），视觉是闪电抖动线
## 4. **穿透**：弹道路径上所有 CombatUnit / Missile / GroundUnit 都受伤
## 5. **冷却**：单发后 cooldown 秒不能再充能
##
## 状态住在 Aircraft.equipment_state["railgun"] 字典里（避免污染 Aircraft 字段）。
## 视觉由 AircraftRenderer.draw_railgun_telegraph + draw_railgun_beam 承担。

const STATE_KEY := "railgun"
const TELEGRAPH_INITIAL_HALF_ANGLE_DEG := 30.0  ## 扇形初始半角

enum LockTrajectory {
	AT_CHARGE_START,  ## 敌人版：扇形开始时锁死目标位置（玩家可靠机动躲掉）
	AT_FIRE_TIME,     ## 玩家版：开火瞬间锁定（基本必中）
}


@export_group("基本")
@export var damage: float = 60.0                 ## 单发伤害（玩家版 150，敌人版 50-70）
## 米 最大射程（legacy / 防御性兜底）。
## 默认实际射程读 host `params.radar_range` —— 装到任何飞机上都按本机雷达范围生效。
## 仅当 `ac.params == null` 时才回退到此字段，正常游戏路径用不到。
@export var max_range_m: float = 5000.0
## 米 最小开火距离（小于此距离不充能 → 让出近战给机炮 / 激光）。
## 玩家版设 0 让玩家自由选择；AI 多武器机型设 800-1500，避免点射近战目标
@export var min_engage_range_m: float = 0.0

@export_group("充能")
## 双发（720 批 railgun_double 升级写 true）：蓄力完成开火后 0.22s 沿同一承诺弹道补射一发
@export var double_shot: bool = false
@export var charge_duration: float = 2.5         ## 秒 telegraph 时长（玩家 1.2 / 敌人 2.5）
@export var lock_trajectory_at: LockTrajectory = LockTrajectory.AT_CHARGE_START
@export var cooldown: float = 6.0                ## 秒 单发后冷却
## 充能完成到实际开火的延迟（秒）。用于敌人版"锁定后预测命中"机制：
## - 充能完成 → 按目标当前速度预测 fire_delay_after_lock 秒后位置
## - 进入"锁定相位"，扇形冻结在预测线上
## - 倒计时结束后 fire 打预测位置
## 玩家平飞 → 预测 = 实际，命中。玩家变速/转向 → 预测错，miss。
## 玩家版 0.0（充能完即射击，无预测窗口）；敌人版 0.5。
@export var fire_delay_after_lock: float = 0.0

@export_group("瞄准约束")
## 必须沿机头方向开火：目标必须在机头 ±fire_cone_half_angle_deg 锥内才能开始 / 维持充能
## 玩家版严格沿机头线（5°），让玩家"必须主动转向对准"才能发射
@export var fire_cone_half_angle_deg: float = 5.0
## 必须先用雷达锁定目标（target.is_locked = true）才能开始充能
## 配合飞机 params.lock_time，可拉长"瞄准 → 锁定 → 充能 → 发射"全流程
@export var require_radar_lock: bool = true
## 一旦开始充能就不再因目标失锁/出锥/贴脸而取消（仅目标死亡才中断）。
## 充能完成时即使目标已偏离也按 locked_aim_pos 朝原方向射击 —— 玩家有更强压迫感。
## Mother Goose MQ-112 等"无脑狙击型" UAV 用 true；玩家版 / AF-03 保持 false。
@export var charge_persistent: bool = false
## true 时弹道无视 locked_aim_pos，永远沿机头方向延伸到 max_range —— "电磁炮就是直射武器"。
## 命中靠玩家是否在机头延长线上；玩家被减速时反应距离不够 → 容易被命中。
## MQ-112 用 true（机头直射）；玩家版 / AF-03 用 false（向 aim_pos 射击，含散布偏移）
@export var fire_along_nose: bool = false

@export_group("命中（仅 AT_FIRE_TIME 模式）")
## 高速目标 miss 概率 —— 玩家版本基本必中，但极速目标（>1500 km/h）会有少量散布
@export var fast_target_miss_speed_kmh: float = 1500.0
@export var fast_target_max_miss_chance: float = 0.15

@export_group("环境干扰 miss")
## 基础 miss 概率（每发都 roll，0 = 必中除非环境干扰）。AF-03 = 0.15。
@export var base_miss_chance: float = 0.0
## 目标在云中追加 miss 概率（按云密度线性插值 0 → cloud_miss_bonus）。
## AF-03 = 0.30 → 满云时总 miss = base + cloud = 0.45
@export var cloud_miss_bonus: float = 0.0
## 目标低空（< low_alt_threshold_m）追加 miss 概率（地面杂波干扰雷达 + 视线被建筑遮挡）
## AF-03 = 0.20 → 低空满云总 miss = 0.65
@export var low_alt_miss_bonus: float = 0.0
@export var low_alt_threshold_m: float = 3500.0  ## AltitudeTier.LOW 阈值

@export_group("命中 / 视觉")
## 弹道线段命中半径（像素）。25 = ~50 米光束直径。AF-03 等高精度狙击手可降到 10-15 减少命中率
@export var hit_radius_px: float = 25.0
## 发射后光束视觉淡出时长（秒）。延长可让玩家看清弹道方向 → 学习躲避
@export var beam_fade_duration: float = 0.25
@export var beam_color: Color = Color(0.7, 0.95, 1.0, 1.0)  ## 闪电色（蓝白）
@export var enemy_beam_color: Color = Color(1.0, 0.5, 0.4, 1.0) ## 敌方红色版


func _init() -> void:
	equipment_kind = "railgun"


## 有效最大射程（米）：默认绑定 host 飞机的雷达范围。
## require_radar_lock=true 时反正打不到雷达外的目标，所以让射程 = 雷达范围天然吻合。
func _effective_max_range_m(ac) -> float:
	if ac != null and ac.params != null and "radar_range" in ac.params:
		return float(ac.params.radar_range)
	return max_range_m


# ─────────── 状态访问 ───────────

static func _ensure_state(ac) -> Dictionary:
	if not ac.equipment_state.has(STATE_KEY):
		ac.equipment_state[STATE_KEY] = {
			"cooldown": 0.0,
			"charging": false,
			"charge_progress": 0.0,
			"charge_target": null,
			"locked_aim_pos": Vector2.ZERO,
			"awaiting_fire": false,    ## 充能完后的"锁定相位"：等 fire_delay_timer 走完才发射
			"fire_delay_timer": 0.0,
			"beam_start": Vector2.ZERO,
			"beam_end": Vector2.ZERO,
			"beam_fade": 0.0,
		}
	return ac.equipment_state[STATE_KEY]


# ─────────── 主循环 ───────────

func update(ac, delta: float) -> void:
	var s := _ensure_state(ac)
	# beam 视觉淡出
	if s["beam_fade"] > 0.0:
		s["beam_fade"] = maxf(s["beam_fade"] - delta, 0.0)
	# 冷却减时
	if s["cooldown"] > 0.0:
		s["cooldown"] = maxf(s["cooldown"] - delta, 0.0)

	# 双发补射（720 批）：首发后沿同一承诺弹道 0.22s 再射一发（不重蓄力、不再滚 miss）
	if s.get("followup_pending", false):
		s["followup_timer"] = maxf(float(s.get("followup_timer", 0.0)) - delta, 0.0)
		if s["followup_timer"] <= 0.0:
			s["followup_pending"] = false
			s["is_followup"] = true
			_fire(ac, s)
			s["is_followup"] = false
		return

	if s.get("awaiting_fire", false):
		_tick_awaiting_fire(ac, s, delta)
	elif s["charging"]:
		_tick_charging(ac, s, delta)
	else:
		_try_start_charging(ac, s)


## 锁定相位：扇形已收缩完，预测点已锁死，倒计时到 0 即开火。
## 期间不做任何 cancel 检查 —— 锁已经"咔哒"上膛，玩家只能靠机动让预测落空。
func _tick_awaiting_fire(ac, s: Dictionary, delta: float) -> void:
	s["fire_delay_timer"] = maxf(s["fire_delay_timer"] - delta, 0.0)
	if s["fire_delay_timer"] <= 0.0:
		s["awaiting_fire"] = false
		_fire(ac, s)


## 机头直射型的路径提前点：目标当前位置 + 速度 ×（剩余充能时间 + 锁定相位延迟）。
## AI 稳头守卫（ai_controller "Railgun 充能稳头守卫"）把机头钉向此点。
## 直线外推是刻意的：目标平飞 → 锁定时机头恰在拦截线上 → 命中；
## 目标机动 → 外推失效 → miss（"玩家可靠机动躲掉"的设计承诺）。
func _nose_lead_point(tgt, s: Dictionary) -> Vector2:
	var time_to_fire: float = (1.0 - float(s["charge_progress"])) * charge_duration + fire_delay_after_lock
	return tgt.global_position + _target_velocity_px(tgt) * time_to_fire


## 估算目标速度向量（像素/秒）。Aircraft / Missile 用 heading × speed；其他类型默认 0
static func _target_velocity_px(tgt) -> Vector2:
	if tgt is Aircraft:
		var ac_t: Aircraft = tgt
		return Vector2(sin(ac_t.heading), -cos(ac_t.heading)) * ac_t.speed * CombatUnit.PIXELS_PER_METER
	if tgt is Missile:
		var m: Missile = tgt
		if "heading" in m and "speed" in m:
			return Vector2(sin(m.heading), -cos(m.heading)) * m.speed * CombatUnit.PIXELS_PER_METER
	return Vector2.ZERO


## 充能期间的甩头中断阈值（deg/s）：LINE_UP 的小幅航点跟踪修正在阈值内不触发；
## 只有大机动（规避/急转）才取消充能——取消回 IDLE，不进冷却（不白费 CD，可立即重试）
const CHARGE_ABORT_TURN_RATE_DEG := 25.0

## 队友电磁炮"正在充能/待发射"锁定 target 的预期伤害合计（超杀让路记账用，
## spec weapon-employment-doctrine：电磁炮必中 → 充能锁定即视为 inbound 伤害，
## 队友导弹发射纪律据此避免对同一目标补射浪费——修"MRM 目标已消失 46% 脱靶"）
static func team_charging_damage(target, team: int, exclude) -> float:
	var total := 0.0
	for u in CombatUnit.all_units:
		if u == null or not is_instance_valid(u) or u == exclude:
			continue
		if not (u is Aircraft) or u.team != team or u.is_destroyed:
			continue
		var st = u.equipment_state.get(STATE_KEY, null)
		if st == null:
			continue
		if not (bool(st.get("charging", false)) or bool(st.get("awaiting_fire", false))):
			continue
		if st.get("charge_target", null) != target:
			continue
		var rg = u.params.get_equipment_of_kind("railgun") if u.params else null
		if rg != null:
			total += rg.damage
	return total


func _try_start_charging(ac, s: Dictionary) -> void:
	if s["cooldown"] > 0.0:
		return
	# planner 门（spec weapon-employment-doctrine 阶段3）：planner 机只在武器竞选
	# 选中电磁炮时才充能（时机决策上收 planner；发射执行仍在本状态机）。
	# 非 planner 机（sandbox legacy）保留旧自主时机。
	if ac is Aircraft and ac.use_tactical_planner and ac._primary_weapon_kind != "railgun":
		return
	# 需要有效战斗目标
	var tgt = ac.combat_target
	if tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed:
		return
	# 电磁炮也必须消费全队超杀账本：否则多个僚机会同时对同一舰船/Mother Goose 挂点充能，
	# 导弹端虽会让路，电磁炮端自己却继续叠加必中伤害。统一按目标代理当前 hp 截断。
	var committed: float = team_charging_damage(tgt, ac.team, ac)
	if ac.missile_manager != null and is_instance_valid(ac.missile_manager):
		committed += ac.missile_manager.team_inbound_damage(tgt, ac.team, null)
	if committed >= tgt.hp:
		return
	# 射程检查
	var dist: float = ac.global_position.distance_to(tgt.global_position)
	var range_px: float = _effective_max_range_m(ac) * CombatUnit.PIXELS_PER_METER
	if dist > range_px:
		return
	# 最小开火距离（多武器机型用，避免在近战距离消耗电磁炮）
	if min_engage_range_m > 0.0:
		var min_px: float = min_engage_range_m * CombatUnit.PIXELS_PER_METER
		if dist < min_px:
			return
	# 雷达锁定要求：必须先 illuminate 目标到 is_locked = true
	if require_radar_lock and not tgt.is_locked:
		return
	# 机头对准要求：目标必须在机头 ±fire_cone 锥内
	if not _target_in_fire_cone(ac, tgt):
		return
	# 启动 charge
	s["charging"] = true
	s["charge_progress"] = 0.0
	s["charge_target"] = tgt
	if fire_along_nose:
		# 机头直射型：locked_aim_pos 充能期间只是 AI 稳头守卫的瞄准销（真弹道 =
		# 锁定瞬间机头冻结，见 _commit_fire_solution）。销必须钉在路径提前点
		# （spec weapon-employment-doctrine §2 统一瞄准语义：机头指向敌机路径提前点），
		# 否则机头整个充能期追着目标 3s 前的旧位置——平飞目标都打不中
		# （2026-07-05 用户实测：MQ-112 瞄准"不关心玩家往哪飞"）
		s["locked_aim_pos"] = _nose_lead_point(tgt, s)
	elif lock_trajectory_at == LockTrajectory.AT_CHARGE_START:
		s["locked_aim_pos"] = tgt.global_position  # 锁死位置 → 玩家可机动躲


## 目标是否在机头开火锥内
func _target_in_fire_cone(ac, tgt) -> bool:
	var to_tgt: Vector2 = tgt.global_position - ac.global_position
	var heading_to_tgt: float = atan2(to_tgt.x, -to_tgt.y)
	var diff: float = heading_to_tgt - ac.heading
	# 归一到 [-PI, PI]
	while diff > PI:
		diff -= TAU
	while diff < -PI:
		diff += TAU
	return absf(diff) <= deg_to_rad(fire_cone_half_angle_deg)


func _tick_charging(ac, s: Dictionary, delta: float) -> void:
	# 目标失效 → 取消充能（无 cooldown 惩罚）
	var tgt = s["charge_target"]
	if tgt == null or not is_instance_valid(tgt) or tgt.is_destroyed:
		s["charging"] = false
		s["charge_progress"] = 0.0
		return
	# 甩头中断（spec weapon-employment-doctrine §3.2，阶段3）：充能是稳定射击平台，
	# 大机动（规避/急转）即取消——回 IDLE 不进冷却（不白费 CD，稳定后立即重试）。
	# LINE_UP 的小幅航点跟踪修正（PD 微调 <10°/s）在阈值内，不会误触发。
	if ac is Aircraft and absf(ac._turn_rate_filt) > deg_to_rad(CHARGE_ABORT_TURN_RATE_DEG):
		s["charging"] = false
		s["charge_progress"] = 0.0
		EventLogger.log_event("RAILGUN", ac._log_name() if ac.has_method("_log_name") else "RG",
			"charge aborted: turn rate %.0f°/s > %.0f°/s" % [
				rad_to_deg(absf(ac._turn_rate_filt)), CHARGE_ABORT_TURN_RATE_DEG])
		return
	# charge_persistent：跳过失锁/出锥/贴脸 cancel 检查 —— 锁定一旦开始就跑完
	if not charge_persistent:
		# 充能期间持续要求雷达锁 + 机头对准（任一失守即取消，玩家须保持瞄准）
		if require_radar_lock and not tgt.is_locked:
			s["charging"] = false
			s["charge_progress"] = 0.0
			return
		if not _target_in_fire_cone(ac, tgt):
			s["charging"] = false
			s["charge_progress"] = 0.0
			return
		# 充能期间敌机贴脸到 min_engage 内 → 取消（让位给近战武器）
		if min_engage_range_m > 0.0:
			var dist: float = ac.global_position.distance_to(tgt.global_position)
			var min_px: float = min_engage_range_m * CombatUnit.PIXELS_PER_METER
			if dist < min_px:
				s["charging"] = false
				s["charge_progress"] = 0.0
				return
	# 机头直射型：持续刷新提前点瞄准销（提前量 = 剩余充能 + 锁定延迟，随充能推进收敛，
	# 锁定瞬间恰好 = fire_delay_after_lock 预测，与 AT_FIRE_TIME 同式）
	if fire_along_nose:
		s["locked_aim_pos"] = _nose_lead_point(tgt, s)
	# 推进进度
	s["charge_progress"] = clampf(s["charge_progress"] + delta / charge_duration, 0.0, 1.0)
	if s["charge_progress"] >= 1.0:
		# 充能完成 —— 完整弹道解（锁定点 + 机头冻结 + miss 扰动）一次性定死
		_commit_fire_solution(ac, s)
		# 进入开火流程：有延迟则锁定相位等 timer，否则直接开火
		s["charging"] = false
		if fire_delay_after_lock > 0.0:
			s["awaiting_fire"] = true
			s["fire_delay_timer"] = fire_delay_after_lock
		else:
			_fire(ac, s)


## 充能完成瞬间把完整弹道解一次性定死（"所见即所得承诺弹道"，2026-07-05）：
## 1) 锁定点：AT_FIRE_TIME 按目标速度预测 / AT_CHARGE_START 保留开局锁死点 /
##    fire_along_nose 冻结当前机头线（设计承诺"锁定相位扇形冻结在预测线上"）
## 2) miss-roll（环境干扰 + 极速目标）此刻结算，横向扰动直接烘焙进 locked_aim_pos
## 此后 telegraph（awaiting 相位）与 _fire 消费同一个承诺点 —— 锁定相位画的指示线
## 就是实际发射线。旧实现机头方向 / miss 扰动都在发射瞬间才结算，导致
## "锁定完成后的指示线 ≠ 实际发射线"（2026-07-05 用户实测 bug）。
func _commit_fire_solution(ac, s: Dictionary) -> void:
	var muzzle: Vector2 = ac.global_position
	var tgt = s.get("charge_target", null)
	if fire_along_nose:
		# 机头直射型（MQ-112）：锁定相位起机头线冻结。旧实现发射时才读机头，
		# awaiting 期间机头继续追踪 → 玩家躲开指示线仍被追着打
		var nose_dir := Vector2(sin(ac.heading), -cos(ac.heading))
		var nose_range_px: float = _effective_max_range_m(ac) * CombatUnit.PIXELS_PER_METER
		s["locked_aim_pos"] = muzzle + nose_dir * nose_range_px
	elif lock_trajectory_at == LockTrajectory.AT_FIRE_TIME:
		# 按目标当前位置 + 速度 × fire_delay 预测开火点（玩家平飞=命中，机动=落空）
		var vel: Vector2 = _target_velocity_px(tgt)
		s["locked_aim_pos"] = tgt.global_position + vel * fire_delay_after_lock
	# AT_CHARGE_START：locked_aim_pos 早在 _try_start_charging 写好（旧位置），不动

	# 环境干扰 miss：基础 + 云层 + 低空
	# 三项叠加后单次 roll；命中失败 → 在承诺点上加横向角度扰动
	var miss_chance: float = base_miss_chance
	if is_instance_valid(tgt):
		# 云层加成：仅当目标实际"在云中"（HIGH 高度 + 有云密度）才生效。
		# 用 Aircraft.cloud_state == 2（HIGH + 在云中），cloud_state == 1 表示在云下方（LOW/MID）
		# 不算真的接触到云。这样低空玩家不会"借云免疫"——云物理上根本不在他周围。
		if cloud_miss_bonus > 0.0 and tgt is Aircraft:
			var ac_t: Aircraft = tgt
			if ac_t.cloud_state == 2:
				miss_chance += cloud_miss_bonus * clampf(ac_t.cloud_density, 0.0, 1.0)
		# 低空判定（敌机有 altitude 字段；地面单位天然在低空）
		if low_alt_miss_bonus > 0.0 and "altitude" in tgt:
			if float(tgt.altitude) < low_alt_threshold_m:
				miss_chance += low_alt_miss_bonus
		# 慢速目标命中加成：被减速 / 静止的目标"应该更容易被命中"
		# < 300km/h 时按线性内插最多砍 60% miss，把"减速难躲"这条设计承诺接到数值上
		if tgt is Aircraft:
			var spd_kmh_slow: float = float((tgt as Aircraft).speed) * 3.6
			if spd_kmh_slow < 300.0:
				var slow_t: float = 1.0 - clampf(spd_kmh_slow / 300.0, 0.0, 1.0)
				miss_chance *= 1.0 - 0.6 * slow_t
	var env_miss: bool = miss_chance > 0.0 and randf() < clampf(miss_chance, 0.0, 0.95)
	if env_miss:
		EventLogger.log_event("RAILGUN", ac.callsign,
			"miss-roll triggered (chance=%.2f)" % miss_chance)
	# 玩家版极速目标 miss 散布：仅当装备 fast_target_max_miss_chance > 0 时启用
	# （敌人版 enemy_railgun.tres 设 0，没有这个补偿）
	var fast_miss: bool = false
	if fast_target_max_miss_chance > 0.0:
		if is_instance_valid(tgt) and "speed" in tgt:
			var spd_kmh: float = float(tgt.speed) * 3.6
			if spd_kmh > fast_target_miss_speed_kmh:
				var miss_t: float = clampf(
					(spd_kmh - fast_target_miss_speed_kmh) / fast_target_miss_speed_kmh,
					0.0, 1.0)
				if randf() < fast_target_max_miss_chance * miss_t:
					fast_miss = true

	# 扰动烘焙进承诺点：等价于旧版发射时对 dir 的横向扰动，但此刻就写进
	# locked_aim_pos → 锁定相位的指示线直接画出（打偏的）实际弹道
	if env_miss or fast_miss:
		var to_aim: Vector2 = s["locked_aim_pos"] - muzzle
		var aim_dist: float = to_aim.length()
		if aim_dist > 1.0:
			var dir: Vector2 = to_aim / aim_dist
			if env_miss:
				var jitter: float = randf_range(0.04, 0.10) * (1.0 if randf() < 0.5 else -1.0)
				dir = (dir + dir.orthogonal() * jitter).normalized()
			if fast_miss:
				var jitter2: float = 0.05 * (1.0 if randf() < 0.5 else -1.0)
				dir = (dir + dir.orthogonal() * jitter2).normalized()
			s["locked_aim_pos"] = muzzle + dir * aim_dist


func _fire(ac, s: Dictionary) -> void:
	# 弹道解已在 _commit_fire_solution 定死（锁定点 + 机头冻结 + miss 扰动）——
	# 这里纯执行，不再有任何随机 / 机头读取。
	# 锁定相位（awaiting_fire）期间 tgt 可能变 null（被打掉）也无所谓 — 锁已经定了。
	var muzzle: Vector2 = ac.global_position
	var to_aim: Vector2 = s["locked_aim_pos"] - muzzle
	var dir: Vector2
	if to_aim.length() > 1.0:
		dir = to_aim.normalized()
	else:
		# 防御兜底：承诺点与炮口重合（理论不可达）→ 退化沿机头
		dir = Vector2(sin(ac.heading), -cos(ac.heading))
	# 弹道：从炮口穿过承诺点延长到 max_range（穿透到底）
	var range_px: float = _effective_max_range_m(ac) * CombatUnit.PIXELS_PER_METER
	var beam_end: Vector2 = muzzle + dir * range_px

	# Hitscan 命中检测：穿透 = 线段沿途所有 unit
	_apply_hitscan_damage(ac, muzzle, beam_end)

	# 写入视觉状态
	s["beam_start"] = muzzle
	s["beam_end"] = beam_end
	s["beam_fade"] = beam_fade_duration

	# 进入冷却
	s["charging"] = false
	s["charge_progress"] = 0.0
	s["charge_target"] = null
	s["cooldown"] = cooldown

	# 双发（720 批）：首发后排队补射（locked_aim_pos 保留 → 补射消费同一承诺点）
	if double_shot and not bool(s.get("is_followup", false)):
		s["followup_pending"] = true
		s["followup_timer"] = 0.22

	EventLogger.log_event("RAILGUN", ac.callsign,
		"fire team=%d range=%dm%s" % [ac.team,
			int(beam_end.distance_to(muzzle) / CombatUnit.PIXELS_PER_METER),
			"（双发补射）" if bool(s.get("is_followup", false)) else ""])


# ─────────── 命中检测 ───────────

func _apply_hitscan_damage(ac, beam_start: Vector2, beam_end: Vector2) -> void:
	# 1) 所有 CombatUnit（敌机 / 地面单位）
	#
	# 同一发炮弹对同一艘舰只结算一次：船体和它的挂点 / 弱点代理同时挂在 all_units 里，
	# 而代理的 take_damage 会把伤害原样转发母舰 —— 一条 hit_radius_px 半径的射线能同时
	# 扫到船体 + 多个 CIWS 代理，一发就打出 N×damage（航母"被一炮秒"的真正来源）。
	# 这里按母舰归并，只保留沿弹道最靠前的那个命中点：炮弹先撞上什么就打什么。
	var naval_hit: Dictionary = {}    ## NavalUnit → 该舰被命中的节点（船体或某个代理）
	var naval_hit_t: Dictionary = {}  ## NavalUnit → 该命中点在弹道上的归一化位置 0~1
	for unit in CombatUnit.all_units:
		if not is_instance_valid(unit):
			continue
		if unit == ac:
			continue
		if not CombatUnit.teams_hostile(unit.team, ac.team):
			continue
		if unit.is_destroyed:
			continue
		if unit is Aircraft and (unit as Aircraft).is_cloaked:
			continue
		if not unit.can_accept_new_hit("railgun"):
			continue
		var d := _point_to_segment_distance(unit.global_position, beam_start, beam_end)
		if d > hit_radius_px:
			continue
		var ship: Node = _naval_damage_sink(unit)
		if ship == null:
			unit.take_damage_from(damage, ac, "railgun")
			continue
		var t := _segment_param(unit.global_position, beam_start, beam_end)
		if not naval_hit.has(ship) or t < float(naval_hit_t[ship]):
			naval_hit[ship] = unit
			naval_hit_t[ship] = t
	for ship in naval_hit:
		var hit_node = naval_hit[ship]
		if is_instance_valid(hit_node):
			hit_node.take_damage_from(damage, ac, "railgun")

	# 2) 在飞导弹（如果当前 ac 持有 missile_manager 引用）
	var mm = ac.missile_manager
	if mm != null and is_instance_valid(mm):
		for child in mm.get_children():
			if not (child is Missile):
				continue
			var m: Missile = child
			if not m.is_active or not CombatUnit.teams_hostile(m.team, ac.team):
				continue
			var d := _point_to_segment_distance(m.global_position, beam_start, beam_end)
			if d <= hit_radius_px:
				# 导弹被电磁炮命中 → 直接销毁
				m.queue_free()


## 该单位的伤害最终落到哪艘舰上（用于一发一舰去重）；非海军单位返回 null
static func _naval_damage_sink(unit) -> Node:
	if unit is MountTarget:
		var ps = (unit as MountTarget).parent_ship
		return ps if (ps != null and is_instance_valid(ps)) else null
	if unit is NavalUnit:
		return unit
	return null


## 点在弹道线段上的归一化投影位置（0=炮口，1=弹道末端）
static func _segment_param(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.001:
		return 0.0
	return clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)


static func _point_to_segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len_sq := ab.length_squared()
	if len_sq <= 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	var closest := a + ab * t
	return p.distance_to(closest)


# ─────────── 状态查询 ───────────

func cooldown_ratio(ac) -> float:
	var s = ac.equipment_state.get(STATE_KEY, null)
	if s == null or cooldown <= 0.0:
		return 1.0
	return clampf(1.0 - float(s["cooldown"]) / cooldown, 0.0, 1.0)


func desired_engagement(_situation):
	var pref := EngagementPreference.new()
	pref.preferred_intent = TacticalPlan.Intent.TAIL_CHASE
	pref.preferred_range_m = max_range_m * 0.7  # 略短于最大射程的甜点
	pref.priority = 0.8  # 高于导弹（0.7）
	pref.needs_lock = true
	pref.needs_los = true
	pref.rationale = "railgun"
	return pref
