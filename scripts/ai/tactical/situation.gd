class_name Situation extends RefCounted

## 战术态势快照 —— TacticalPlanner / BfmIntent 的输入。
##
## 设计要点：
## 1. **纯数据**。构造完成后只读，不持有 Aircraft 引用，不读 world state。
##    所有几何派生量在 _recompute() 一次性算好。
## 2. **可手工构造**。单元测试用 new_for_test() 直接填字段，不需要假飞机。
## 3. **便于 log**。to_dict() 返回所有字段，便于 EventLogger 一行打出。
## 4. **几何约定**（与 aircraft_combat_tracking 现有公式一致）：
##    - heading: 0=北, 顺时针, 弧度
##    - my_fwd / tgt_fwd: 单位向量，由 heading 推出
##    - aim_align = my_fwd · to_target_dir，1=我对准敌人, 0=90°, -1=我背对敌人
##    - head_on_dot = -tgt_fwd · to_target_dir，1=对头, -1=同向追尾
##    - aspect_angle_deg = acos(-tgt_fwd · to_me_dir) 度，0=我在敌正后, 180=我在敌正前
##    - in_rear_hemisphere = aspect_angle_deg < 90
##    - closing_rate_px_s = aim_align × my_speed + head_on_dot × tgt_speed
##      （沿 LOS 的真实闭合率投影，正=接近）

# ── 我方 ──
var my_pos: Vector2 = Vector2.ZERO
var my_heading: float = 0.0
var my_speed_ms: float = 0.0
var my_alt: float = 0.0
var my_bank_deg: float = 0.0
var ammo: int = 0
var missiles: int = 0
var fuel: float = 9999.0

# ── 目标 ──
var has_target: bool = false
var tgt_pos: Vector2 = Vector2.ZERO
var tgt_heading: float = 0.0
var tgt_speed_ms: float = 0.0
var tgt_alt: float = 0.0
var tgt_bank_deg: float = 0.0
var tgt_is_surface: bool = false   ## 地面单位 / 舰船：非机动表面目标，走 strafe 高速掠过

# ── 玩家意图（可空，仅玩家飞机有）──
var weapon_lock: int = WEAPON_LOCK_NONE   ## 玩家对武器的强制要求
var charge_intent: bool = false           ## 双击冲锋
var evasion_intent: bool = false          ## E 键规避
var missile_auto_fire: bool = true        ## 导弹自动发射开关（HUD 切换）
var has_radar_lock: bool = false          ## 当前雷达至少锁住一个敌方单位
var altitude_preference: int = 0          ## 玩家高度偏好（0=PREFER_CLIMB, 1=PREFER_LOW），仅 use_tactical_preference 有效
var target_lock_progress: float = 0.0     ## combat_target 的锁定进度（秒），0=未追踪
var target_locked: bool = false           ## combat_target 是否已锁定（progress >= lock_time）
var lock_time_threshold: float = 3.0      ## 自身雷达锁定阈值（秒），来自 params.lock_time

# ── 小队协同（仅僚机有意义）──
var is_wingman: bool = false              ## 我是僚机（squad 存在 + 长机不是自己）
var squad_index: int = 0                  ## 我在小队中的位置：0=长机/单机, 1/2/3...=僚机槽位
var following_leader_target: bool = false ## 我的 combat_target == 长机 combat_target（协同攻击）
var leader_intent: int = -1               ## 长机当前 plan.intent（用于僚机角色互补），-1 表示无/未跑过
var squad_role: int = 0                   ## AIController.SquadRole：NONE/FLANK_LEFT/FLANK_RIGHT/HIGH_COVER

# ── AI 性格（来自 AIController；玩家无此 component → 使用默认值）──
var ai_aggression: float = 0.5            ## AI 攻击欲 [0..1]：高=committed Gladiator, 低=careful Lancer
var combat_altitude_m: float = 0.0        ## 自身偏好作战高度（来自 AIController.patrol_altitude；玩家用 my_alt）
const WEAPON_LOCK_NONE := 0
const WEAPON_LOCK_FORCE_GUN := 1
const WEAPON_LOCK_FORCE_MISSILE := 2

# ── 武器射程（米，由 params 注入）──
var gun_range_m: float = 1000.0
var missile_max_range_m: float = 8000.0
var missile_min_range_m: float = 500.0

# ── 武器竞选（spec weapon-employment-doctrine 阶段2）──
var railgun_ready: bool = false          ## 电磁炮冷却就绪
var railgun_band_min_m: float = 0.0      ## 电磁炮最近射程（live）
var railgun_band_max_m: float = -1.0     ## 电磁炮最远射程 = 本机雷达距离（live）；<0 = 未装备
var primary_weapon_prev: String = ""     ## 上次竞选胜者（滞回输入，来自 Aircraft 状态）
var primary_weapon_hold_s: float = 999.0 ## 上次胜者已保持秒数

# ── 飞行性能（米/秒，由 params 注入）──
var max_speed_kmh: float = 2100.0
var cruise_speed_kmh: float = 900.0
var corner_speed_kmh: float = 700.0
var stall_speed_kmh: float = 220.0
var radar_half_angle_deg: float = 30.0   ## 雷达扇形半角（度），决定 crank 角度上限

# ── 几何派生（_recompute 算）──
var to_target_dir: Vector2 = Vector2.ZERO
var dist_m: float = INF
var dist_px: float = INF
var my_fwd: Vector2 = Vector2.UP
var tgt_fwd: Vector2 = Vector2.UP
var aim_align: float = 0.0
var head_on_dot: float = 0.0
var aspect_angle_deg: float = 180.0
var heading_diff_to_target_deg: float = 0.0
var in_rear_hemisphere: bool = false
var closing_rate_ms: float = 0.0
var alt_diff_m: float = 0.0
var tgt_in_my_rear: bool = false  ## 敌人在我的后半球（被咬尾警告）

# ── 威胁（可选，TacticalPlanner 关注）──
var has_incoming_missile: bool = false
var nearest_threat_dist_m: float = INF

# ── 状态效果（FEAR 等会改变高层决策）──
var is_feared: bool = false              ## FEAR debuff 激活：planner 强制脱离
var is_boss_attacker: bool = false       ## BOSS 攻击手豁免：FEAR 不会让其脱离（仅吃 stress 副作用）
var is_tactical_preference_user: bool = false  ## 玩家（use_tactical_preference）：高度走 altitude_preference，不匹配目标

# ── 时序状态（防 intent 抖动）──
var current_time: float = 0.0          ## 当前游戏时间（秒）
var prev_intent: int = -1              ## 上一帧选定的 intent，-1 表示无
var prev_intent_held_for: float = 0.0  ## 上一 intent 已持续秒数
var extend_remaining: float = 0.0      ## EXTEND_RECOVER 剩余时间，>0 表示强制保持脱离

# ══════════════════════════════════════════════
#  构造工厂
# ══════════════════════════════════════════════

## 从 Aircraft 实例构造（运行时用）
static func from_aircraft(ac) -> Situation:
	var s := Situation.new()
	s.my_pos = ac.global_position
	s.my_heading = ac.heading
	s.my_speed_ms = ac.speed
	s.my_alt = ac.altitude
	s.is_feared = ac.status_fear_active
	s.combat_altitude_m = ac.altitude  # 默认：保持当前高度；AIController 分支会覆写为 patrol_altitude
	s.my_bank_deg = rad_to_deg(ac.bank_angle)
	s.ammo = ac.ammo
	s.missiles = ac.missiles_remaining
	s.fuel = ac.fuel

	if ac.params:
		# ⚠ 性能/机动参考一律走 AircraftPhysics.effective_*() accessor
		# 零 buff 下与旧 params.* 直读完全一致；buff 通过 accessor 内部 if 块自动透传
		# 详见 aircraft_physics.gd "effective_*() — AI 战术层 buff-aware accessor 层" 段
		s.max_speed_kmh = AircraftPhysics.effective_max_speed_kmh(ac)
		s.cruise_speed_kmh = AircraftPhysics.effective_cruise_speed_kmh(ac)
		s.stall_speed_kmh = AircraftPhysics.effective_stall_speed_kmh(ac)
		s.corner_speed_kmh = AircraftPhysics.effective_corner_speed_kmh(ac)
		s.radar_half_angle_deg = ac.params.radar_half_angle
		s.lock_time_threshold = ac.params.lock_time
		if ac.params.gun:
			s.gun_range_m = ac.params.gun.max_range
		if ac.params.missile:
			s.missile_max_range_m = ac.params.missile.max_range_rear
			s.missile_min_range_m = ac.params.missile.min_range
		# 电磁炮竞选输入（spec weapon-employment-doctrine：距离带实时读 live 参数，
		# 升级/强化即时生效——禁止烘焙常量）
		var _rg = ac.params.get_equipment_of_kind("railgun")
		if _rg != null:
			s.railgun_band_min_m = _rg.min_engage_range_m
			s.railgun_band_max_m = _rg._effective_max_range_m(ac)
			var _rgs = ac.equipment_state.get("railgun", null)
			s.railgun_ready = _rgs == null or float(_rgs.get("cooldown", 0.0)) <= 0.0

	# 武器竞选滞回状态（住 Aircraft，_apply_tactical_plan 回写）
	s.primary_weapon_prev = ac._primary_weapon_kind
	s.primary_weapon_hold_s = ac._primary_weapon_hold_s

	# 时序状态（防抖动用）
	s.current_time = Time.get_ticks_msec() / 1000.0
	if "_bfm_prev_intent" in ac:
		s.prev_intent = ac._bfm_prev_intent
	if "_bfm_intent_started_at" in ac and ac._bfm_intent_started_at > 0.0:
		s.prev_intent_held_for = maxf(0.0, s.current_time - ac._bfm_intent_started_at)
	if "_bfm_extend_until" in ac:
		s.extend_remaining = maxf(0.0, ac._bfm_extend_until - s.current_time)

	# 玩家意图
	if "evasion_mode" in ac:
		s.evasion_intent = ac.evasion_mode
	if "charge_attack" in ac:
		s.charge_intent = ac.charge_attack
	if "missile_auto_fire" in ac:
		s.missile_auto_fire = ac.missile_auto_fire
	if "altitude_preference" in ac:
		s.altitude_preference = ac.altitude_preference
	if "use_tactical_preference" in ac:
		s.is_tactical_preference_user = ac.use_tactical_preference
	# 雷达锁：radar_targets 是 Dictionary[CombatUnit → lock_progress]，
	# 任意一个 progress >= lock_time 即视为已锁
	if "radar_targets" in ac and ac.params:
		var lock_threshold: float = ac.params.lock_time
		for tgt in ac.radar_targets:
			if not is_instance_valid(tgt):
				continue
			var t: CombatUnit = tgt as CombatUnit
			if t == null or t.is_destroyed:
				continue
			if t.team == ac.team:
				continue
			if ac.radar_targets[tgt] >= lock_threshold:
				s.has_radar_lock = true
				break
	if "weapon_preference" in ac:
		# 0 = PREFER_MISSILE, 1 = PREFER_GUN
		# 仅玩家飞机有 use_tactical_preference；AI 用默认 NONE
		var has_pref: bool = "use_tactical_preference" in ac and ac.use_tactical_preference
		if has_pref:
			s.weapon_lock = WEAPON_LOCK_FORCE_GUN if ac.weapon_preference == 1 else WEAPON_LOCK_NONE

	# 目标
	var tgt = ac.combat_target
	if tgt != null and is_instance_valid(tgt) and not tgt.is_destroyed:
		s.has_target = true
		s.tgt_pos = tgt.global_position
		s.tgt_speed_ms = tgt.speed
		s.tgt_alt = tgt.altitude
		# 宽松定义：任何非 Aircraft 的目标都视为 surface（GroundUnit / NavalUnit / MountTarget /
		# WeakPoint / 未来的巨型 BOSS 等）。它们共同特征是慢速或不机动，攻击模式都是 strafe 高速掠过。
		s.tgt_is_surface = not (tgt is Aircraft)
		# 目标的 heading 与 bank 仅在 Aircraft 上有意义；地面单位 heading 取 0、bank=0
		if tgt is Aircraft:
			s.tgt_heading = tgt.heading
			s.tgt_bank_deg = rad_to_deg(tgt.bank_angle)
		else:
			s.tgt_heading = 0.0
			s.tgt_bank_deg = 0.0
		# 锁定进度：自身雷达对当前目标的累积追踪秒数
		if "radar_targets" in ac:
			s.target_lock_progress = ac.radar_targets.get(tgt, 0.0)
			s.target_locked = s.target_lock_progress >= s.lock_time_threshold

	# 小队协同 + AI 性格：从子节点 AIController 读
	for child in ac.get_children():
		if child is AIController:
			var ai_ctrl: AIController = child
			s.ai_aggression = ai_ctrl.aggression
			s.is_boss_attacker = ai_ctrl.is_boss_attacker()
			if ai_ctrl.patrol_altitude > 0.0:
				s.combat_altitude_m = ai_ctrl.patrol_altitude
			if ai_ctrl.squad and ai_ctrl.squad.leader and ai_ctrl.squad.leader != ac \
					and is_instance_valid(ai_ctrl.squad.leader) and not ai_ctrl.squad.leader.is_destroyed:
				s.is_wingman = true
				s.squad_index = ai_ctrl.squad_index
				var leader: Aircraft = ai_ctrl.squad.leader
				if leader.combat_target != null and leader.combat_target == ac.combat_target:
					s.following_leader_target = true
				# 读长机最近 plan，用于角色互补决策（玩家长机也有 _last_plan）
				if "_last_plan" in leader and leader._last_plan != null:
					s.leader_intent = leader._last_plan.intent
				s.squad_role = ai_ctrl._squad_lateral_role
			break

	s._recompute()
	return s

## 测试用：直接传字段构造，不需要 Aircraft 实例
static func new_for_test(d: Dictionary) -> Situation:
	var s := Situation.new()
	# 测试默认给足机炮弹药（游戏内 from_aircraft 恒有真实值；旧武器决策不读 ammo，
	# 存量测试夹具从不设它——武器竞选制引入 ammo 就绪门后补此默认，夹具可显式覆盖）
	s.ammo = 500
	for k in d:
		s.set(k, d[k])
	s._recompute()
	return s

# ══════════════════════════════════════════════
#  几何重算
# ══════════════════════════════════════════════

func _recompute() -> void:
	my_fwd = Vector2(sin(my_heading), -cos(my_heading))
	tgt_fwd = Vector2(sin(tgt_heading), -cos(tgt_heading))

	if not has_target:
		return

	var to_tgt: Vector2 = tgt_pos - my_pos
	dist_px = to_tgt.length()
	dist_m = dist_px / CombatUnit.PIXELS_PER_METER if CombatUnit.PIXELS_PER_METER > 0.0 else dist_px
	to_target_dir = to_tgt.normalized() if dist_px > 0.001 else Vector2.UP

	aim_align = my_fwd.dot(to_target_dir)
	head_on_dot = -tgt_fwd.dot(to_target_dir)
	var to_me_dir: Vector2 = -to_target_dir
	aspect_angle_deg = rad_to_deg(acos(clampf(-tgt_fwd.dot(to_me_dir), -1.0, 1.0)))
	in_rear_hemisphere = aspect_angle_deg < 90.0

	# 敌人是否在我的后半球（用于"被咬尾"判定，仅空战目标有意义）
	tgt_in_my_rear = my_fwd.dot(to_target_dir) < 0.0 and not tgt_is_surface

	# 闭合率（沿 LOS 投影，正=接近）
	closing_rate_ms = aim_align * my_speed_ms + head_on_dot * tgt_speed_ms

	# heading 与 LOS 的角差（度）
	var hdg_to_tgt: float = atan2(to_target_dir.x, -to_target_dir.y)
	heading_diff_to_target_deg = rad_to_deg(absf(_angle_diff(hdg_to_tgt, my_heading)))

	alt_diff_m = my_alt - tgt_alt

# ══════════════════════════════════════════════
#  辅助
# ══════════════════════════════════════════════

static func _angle_diff(a: float, b: float) -> float:
	var d := a - b
	while d > PI: d -= TAU
	while d < -PI: d += TAU
	return d

func gun_range_px() -> float:
	return gun_range_m * CombatUnit.PIXELS_PER_METER

func missile_max_range_px() -> float:
	return missile_max_range_m * CombatUnit.PIXELS_PER_METER

func missile_min_range_px() -> float:
	return missile_min_range_m * CombatUnit.PIXELS_PER_METER

func to_dict() -> Dictionary:
	return {
		"my_pos": my_pos, "my_hdg_deg": rad_to_deg(my_heading), "my_spd": my_speed_ms,
		"tgt_pos": tgt_pos, "dist_m": dist_m, "asp_deg": aspect_angle_deg,
		"aim": aim_align, "head_on": head_on_dot, "in_rear": in_rear_hemisphere,
		"closing": closing_rate_ms, "tgt_bank": tgt_bank_deg,
		"weapon_lock": weapon_lock, "charge": charge_intent, "evade": evasion_intent,
	}
