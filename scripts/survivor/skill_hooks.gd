class_name SkillHooks
extends RefCounted

## §1.4 击杀 / 受击钩子链：所有"击杀触发 / 受击触发"型生存模式技能的统一入口。
##
## 设计原则：
##   - 每个钩子是一个静态函数，按 stack flag early-return —— 不命中只付一个 dict.has 开销
##   - 集中放在本文件，不让 status_effects.gd 膨胀
##   - 钩子只读 killer.upgrade_stacks（玩家技能层级），不读私有字段
##   - 僚机归因：默认 killer.team == 0 即触发玩家系技能（不区分玩家本人 vs 僚机）；
##     少数"被你击杀"语义的技能需额外校验 killer == AircraftRenderer.player_ref
##
## 接入：StatusEffects.on_kill 末尾调用 SkillHooks.dispatch_on_kill(killer, victim)
##       Aircraft._apply_damage 末尾（致死前）调用 SkillHooks.dispatch_on_hit(victim, attacker, kind)
##
## 当前入口由后续技能逐个填，本文件维护钩子目录 + 公共工具。

## ── 升级 ID 常量（与 SurvivorData.UPGRADES 中 id 字段一致） ──
const SKILL_GUN_KILL_FEAR := "skill_gun_kill_fear"
const SKILL_KILL_BLOODLUST := "skill_kill_bloodlust"
const SKILL_DAMAGED_BLOODLUST := "skill_damaged_bloodlust"
const SKILL_HEAD_ON_PERMA_HP := "skill_head_on_perma_hp"
const SKILL_HEAD_ON_AOE_FEAR := "skill_head_on_aoe_fear"
const SKILL_LOWEST_ALT_KILL_INVUL := "skill_lowest_alt_kill_invul"
const SKILL_MISSILE_HIT_INVUL := "skill_missile_hit_invul"
const SKILL_KILL_STATUS_HEAL := "skill_kill_status_heal"
const SKILL_FLARE_AOE_JAM := "skill_flare_aoe_jam"
const SKILL_GUN_KILL_FLARE_DROP := "skill_gun_kill_flare_drop"
const SKILL_MISSILE_HIT_AOE_JAM := "skill_missile_hit_aoe_jam"
const SKILL_EVADE_MISSILE_OVERLOAD := "skill_evade_missile_overload"
const SKILL_FLARE_OVERLOAD := "skill_flare_overload"
const SKILL_OVERLOAD_DURATION_4X := "overload_duration_4x"
const SKILL_OVERLOAD_EXTENDED_AMMO := "overload_extended_ammo"
const SKILL_OVERLOAD_TO_BLOODLUST := "overload_to_bloodlust"
const SKILL_BLOODLUST_ARMOR_MOBILITY := "bloodlust_armor_mobility"
const SKILL_FULL_HP_KILL_PERMA_HP := "full_hp_kill_perma_hp"
const SKILL_JAM_SELF_OVERLOAD := "jam_self_overload"
const SKILL_EVASION_HERBST := "evasion_herbst"   ## evasion 模式被攻击启动 J-Turn（与 UPGRADES id 对齐）
## ── A-10 实验武器技能（火箭弹 / 漂浮雷专属） ──
const SKILL_TORPEDO_AOE_JAM := "skill_torpedo_aoe_jam"     ## 漂浮雷引爆后范围干扰
const SKILL_ROCKET_HOMING := "skill_rocket_homing"         ## 火箭弹弱追踪
## ── 激光技能 ──
const SKILL_LASER_DAMAGE := "skill_laser_damage"           ## 激光恢复 DPS 伤害（默认只减速）

# 数值常量（粗调，后续按手感）
const HEAD_ON_DOT_THRESHOLD := 0.7
const HEAD_ON_RANGE_PX := 1500.0   ## 3km；超过此距离的"对头几何"不算对头（PIXELS_PER_METER=0.5）
const HEAD_ON_PERMA_HP_BONUS := 5.0
const HEAD_ON_AOE_FEAR_RADIUS_PX := 1500.0  # 3km
const HEAD_ON_AOE_FEAR_DURATION := 6.0
## 玩家 buff 时长（INVINCIBLE / BLOODLUST / OVERLOAD）统一 +2s 调长，
## 让"两秒就没了"的体验改善；debuff 类（FEAR / JAM / SLOW）不受影响
const LOWEST_ALT_KILL_INVUL_DURATION := 8.0
const MISSILE_HIT_INVUL_DURATION := 8.0
const KILL_BLOODLUST_DURATION := 8.0
const DAMAGED_BLOODLUST_DURATION := 8.0
const EVADE_MISSILE_OVERLOAD_DURATION := 8.0
const FLARE_OVERLOAD_DURATION := 8.0
const OVERLOAD_DURATION_MULT := 2.0
const OVERLOAD_DURATION_FLAT_BONUS := 6.0   ## "燃尽自如"额外 +6s
const BLOODLUST_ARMOR_DR := 0.30            ## BLOODLUST 期间额外减伤 30%
const BLOODLUST_G_MULT := 1.20              ## BLOODLUST 期间 max_g ×1.2
const BLOODLUST_ACCEL_MULT := 1.30          ## BLOODLUST 期间加/减速 ×1.3（与 OVERLOAD 1.6 区别开）
const FULL_HP_KILL_HP_BONUS := 8.0          ## 满血 + BL 击杀 +8 max_hp/+8 hp
const JAM_SELF_OVERLOAD_DURATION := 8.0     ## JAM 命中至少 1 个敌人 -> 自身 OVERLOAD 8s
const KILL_STATUS_HEAL_AMOUNT := 30.0
const FLARE_AOE_JAM_RADIUS_PX := 600.0
const FLARE_AOE_JAM_DURATION := 5.0
const GUN_KILL_FLARE_DROP_JAM_RADIUS_PX := 700.0
const GUN_KILL_FLARE_DROP_JAM_DURATION := 4.0
const MISSILE_HIT_AOE_JAM_RADIUS_PX := 1200.0
const MISSILE_HIT_AOE_JAM_DURATION := 5.0
const GUN_KILL_FEAR_RADIUS_PX := 1200.0
const GUN_KILL_FEAR_DURATION := 5.0
## 漂浮雷 AOE 干扰：引爆时除了正常 AOE，再向外发射一圈 JAM
const TORPEDO_AOE_JAM_RADIUS_PX := 800.0
const TORPEDO_AOE_JAM_DURATION := 5.0
## 激光默认减速效果：每帧刷新到目标的 SLOW 持续时间（短：脱离光束 0.4s 内消失）
const LASER_SLOW_REFRESH_DURATION := 0.4
## 激光对导弹的减速：导弹没有 SLOW 状态系统，单独走 Missile._laser_slow_timer
## 减速更猛（速度 cap 45% / 转弯 G cap 50%），让玩家有机动时间躲开
const LASER_MISSILE_SLOW_DURATION := 0.5
const LASER_MISSILE_SPEED_MULT := 0.45
const LASER_MISSILE_G_MULT := 0.5
## 火箭弹弱追踪：scan + turn 极慢，给"贴脸糊脸"调一点修正空间
const ROCKET_HOMING_SCAN_PX := 1200.0
const ROCKET_HOMING_TURN_DPS := 35.0     ## 比鱼雷略快但比导弹弱很多
const ROCKET_HOMING_RETARGET_INTERVAL := 0.4


## ── 击杀钩子分发入口 ──
## 由 StatusEffects.on_kill 调用。在 BLOODLUST 已处理之后追加跑技能链。
##   killer: Aircraft（团队 0 = 玩家系；nil-safe 检查在 caller 已做）
##   victim: Aircraft
static func dispatch_on_kill(killer: Aircraft, victim: Aircraft) -> void:
	if killer == null or victim == null:
		return
	if not is_instance_valid(killer) or not is_instance_valid(victim):
		return
	# 仅玩家小队触发玩家技能（ALLY 第三方击杀不触发）
	if not killer.is_player_squad():
		return
	var stacks: Dictionary = _get_upgrade_stacks(killer)
	if stacks.is_empty():
		return
	# 致死伤害类型（_last_damage_kind meta；可能为 ""）
	var kind: String = ""
	if victim.has_meta("_last_damage_kind"):
		kind = String(victim.get_meta("_last_damage_kind"))
	# 对头几何（_record_kill_attribution 写过）
	var head_on_dot: float = 0.0
	if victim.has_meta("kill_head_on_dot"):
		head_on_dot = float(victim.get_meta("kill_head_on_dot"))
	var aim_dot: float = 0.0
	if victim.has_meta("kill_attacker_aim"):
		aim_dot = float(victim.get_meta("kill_attacker_aim"))
	# 对头判定：几何（双向 dot）+ 距离 ≤ 3km。远距 BVR 几何巧合不算"对冲冲锋"
	var dist_sq: float = killer.global_position.distance_squared_to(victim.global_position)
	var is_head_on: bool = head_on_dot > HEAD_ON_DOT_THRESHOLD \
			and aim_dot > HEAD_ON_DOT_THRESHOLD \
			and dist_sq <= HEAD_ON_RANGE_PX * HEAD_ON_RANGE_PX

	# ── 钩子：机炮击杀施加大范围 FEAR ──
	if kind == "gun" and stacks.get(SKILL_GUN_KILL_FEAR, 0) > 0:
		AOEBroadcast.apply_status_in_radius(
			victim.global_position, GUN_KILL_FEAR_RADIUS_PX,
			1, StatusEffects.FEAR, GUN_KILL_FEAR_DURATION, killer)

	# 注：击杀小队成员 FEAR 由 fear_squad_spread 走 survivor_spawner._trigger_squad_fear 触发
	# （已删除原 skill_kill_squad_fear 冗余路径，避免双发）

	# ── 钩子：机炮击杀目标位置生成一片 flare（AOE JAM） ──
	if kind == "gun" and stacks.get(SKILL_GUN_KILL_FLARE_DROP, 0) > 0:
		var jam_hits: int = AOEBroadcast.apply_status_in_radius(
			victim.global_position, GUN_KILL_FLARE_DROP_JAM_RADIUS_PX,
			-1, StatusEffects.JAM, GUN_KILL_FLARE_DROP_JAM_DURATION, killer)
		on_player_jam_landed(killer, jam_hits)

	# ── 钩子：击杀进入 BLOODLUST ──
	if stacks.get(SKILL_KILL_BLOODLUST, 0) > 0:
		killer.apply_status(StatusEffects.BLOODLUST, KILL_BLOODLUST_DURATION)

	# ── 钩子：击杀有异常状态者回 30 HP ──
	if stacks.get(SKILL_KILL_STATUS_HEAL, 0) > 0:
		if not victim.status_effects.is_empty():
			var max_hp: float = killer.params.max_hp if killer.params else 100.0
			killer.hp = minf(killer.hp + KILL_STATUS_HEAL_AMOUNT, max_hp)

	# ── 钩子：对头击杀 +5 max_hp + +5 hp（永久局内） ──
	if is_head_on and stacks.get(SKILL_HEAD_ON_PERMA_HP, 0) > 0:
		if killer.params:
			killer.params.max_hp += HEAD_ON_PERMA_HP_BONUS
			killer.hp = minf(killer.hp + HEAD_ON_PERMA_HP_BONUS, killer.params.max_hp)
			EventLogger.log_event("SKILL_HOOK", killer.callsign,
				"head_on_perma_hp → max_hp+%d (now %.0f)" % [int(HEAD_ON_PERMA_HP_BONUS), killer.params.max_hp])

	# ── 钩子：对头击杀大范围 FEAR ──
	# fear_chills 联动（FEAR → 同步 SLOW）由 AOEBroadcast.apply_status_in_radius
	# 内部统一处理，覆盖所有 AOE FEAR 入口（gun_kill / head_on / 凝视压迫）
	if is_head_on and stacks.get(SKILL_HEAD_ON_AOE_FEAR, 0) > 0:
		AOEBroadcast.apply_status_in_radius(
			victim.global_position, HEAD_ON_AOE_FEAR_RADIUS_PX,
			1, StatusEffects.FEAR, HEAD_ON_AOE_FEAR_DURATION, killer)

	# ── 钩子：超载-嗜血联动击杀刷新 ──
	# 击杀时若 OVERLOAD 或 BLOODLUST 仍在 → 刷新两者到 initial duration（重置进度条）
	if stacks.get(SKILL_OVERLOAD_TO_BLOODLUST, 0) > 0:
		_refresh_status(killer, StatusEffects.OVERLOAD)
		_refresh_status(killer, StatusEffects.BLOODLUST)

	# ── 钩子：满血 + BLOODLUST 期间击杀 → 永久 +8 max_hp ──
	if stacks.get(SKILL_FULL_HP_KILL_PERMA_HP, 0) > 0 and killer.status_bloodlust_active:
		var max_hp_now: float = killer.params.max_hp if killer.params else 100.0
		# 满血判定（容差 0.5 以容纳 BLOODLUST_HEAL_PER_KILL clamp 误差）
		if killer.hp >= max_hp_now - 0.5 and killer.params:
			killer.params.max_hp += FULL_HP_KILL_HP_BONUS
			killer.hp = minf(killer.hp + FULL_HP_KILL_HP_BONUS, killer.params.max_hp)
			EventLogger.log_event("SKILL_HOOK", killer.callsign,
				"full_hp_kill_perma_hp → max_hp+%d (now %.0f)" % [int(FULL_HP_KILL_HP_BONUS), killer.params.max_hp])

	# ── 钩子：最低空击杀 INVINCIBLE（自身） ──
	# 用 max 模式（不是 no_refresh）：击杀是奖励，应该能延长已有 INVINCIBLE，
	# 否则与 SKILL_MISSILE_HIT_INVUL 的 no_refresh 互锁（命中后 4s 内击杀奖励静默失效）
	if stacks.get(SKILL_LOWEST_ALT_KILL_INVUL, 0) > 0:
		var tier: int = killer.get_altitude_tier()
		if tier == CombatUnit.AltitudeTier.LOW or tier == CombatUnit.AltitudeTier.GROUND:
			killer.apply_status(StatusEffects.INVINCIBLE, LOWEST_ALT_KILL_INVUL_DURATION)


## ── 受击钩子分发入口 ──
## 由 Aircraft._apply_damage 中调用（受伤但未致死时即可，已死的走 on_kill）。
##   victim: Aircraft（被击中者）
##   attacker: Node（射手，可能为 null）
##   kind: String（damage_kind）
##   amount: float（实际伤害）
static func dispatch_on_hit(victim: Aircraft, attacker: Node, kind: String, _amount: float) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	# 仅玩家小队触发"我方受击"型技能
	if not victim.is_player_squad():
		return
	var stacks: Dictionary = _get_upgrade_stacks(victim)
	if stacks.is_empty():
		return

	# ── 钩子：受伤进入 BLOODLUST（被打反击）— 已有状态时刷新持续时间 ──
	if stacks.get(SKILL_DAMAGED_BLOODLUST, 0) > 0:
		# 用 max 模式：被多次打中刷新到完整 duration（用户 Q8 要求"嗜血被打刷新"）
		victim.apply_status(StatusEffects.BLOODLUST, DAMAGED_BLOODLUST_DURATION)

	# ── 钩子：被导弹命中后 INVINCIBLE 2s（不刷新） ──
	if (kind == "missile" or kind == "aoe") and stacks.get(SKILL_MISSILE_HIT_INVUL, 0) > 0:
		victim.apply_status(StatusEffects.INVINCIBLE, MISSILE_HIT_INVUL_DURATION, "no_refresh")

	# ── 钩子：被导弹击中后周围 AOE JAM ──
	if (kind == "missile" or kind == "aoe") and stacks.get(SKILL_MISSILE_HIT_AOE_JAM, 0) > 0:
		var hj_hits: int = AOEBroadcast.apply_status_in_radius(
			victim.global_position, MISSILE_HIT_AOE_JAM_RADIUS_PX,
			-1, StatusEffects.JAM, MISSILE_HIT_AOE_JAM_DURATION, victim)
		on_player_jam_landed(victim, hj_hits)

	# 注：危机赫尔贝特（evasion_herbst）改为预测式触发，逻辑迁移到 aircraft.gd._update_evasion_herbst_skill
	# 触发条件与眼镜蛇等价（导弹命中前 / 后方机炮追尾），on_hit 事后触发已废弃 —— 不在这里触发。


## ── 成功回避导弹钩子（aircraft_flares.release 在 jam 命中后调用） ──
## 由 aircraft_flares 在确认导弹丢制导后调用一次
static func on_evade_missile(evader: Aircraft) -> void:
	if evader == null or not is_instance_valid(evader):
		return
	if not evader.is_player_squad():
		return
	var stacks: Dictionary = _get_upgrade_stacks(evader)
	if stacks.is_empty():
		return
	if stacks.get(SKILL_EVADE_MISSILE_OVERLOAD, 0) > 0:
		evader.apply_status(StatusEffects.OVERLOAD, EVADE_MISSILE_OVERLOAD_DURATION)


## ── 释放热诱弹钩子（aircraft_flares.release 在扣减弹量后调用） ──
## 与 on_evade_missile 区别：触发于"释放动作"本身，不依赖 jam 是否成功
static func on_flare_release(ac: Aircraft) -> void:
	if ac == null or not is_instance_valid(ac):
		return
	if not ac.is_player_squad():
		return
	var stacks: Dictionary = _get_upgrade_stacks(ac)
	if stacks.is_empty():
		return
	if stacks.get(SKILL_FLARE_OVERLOAD, 0) > 0:
		ac.apply_status(StatusEffects.OVERLOAD, FLARE_OVERLOAD_DURATION)


## ── JAM 命中钩子：玩家施加的 JAM 至少命中 1 个敌人 → 自身 OVERLOAD ──
## 各 JAM 来源（flare_aoe_jam / gun_kill_flare_drop / missile_hit_aoe_jam / jam_aura / head_on_jam）
## 在 apply 之后调用本函数，传入命中数；命中 0 不触发
static func on_player_jam_landed(player: Aircraft, hit_count: int) -> void:
	if hit_count <= 0:
		return
	if player == null or not is_instance_valid(player) or not player.is_player_squad():
		return
	var stacks: Dictionary = _get_upgrade_stacks(player)
	if stacks.is_empty():
		return
	if int(stacks.get(SKILL_JAM_SELF_OVERLOAD, 0)) > 0:
		player.apply_status(StatusEffects.OVERLOAD, JAM_SELF_OVERLOAD_DURATION)


## ── 内部：刷新某状态的剩余时间到当初施加的 initial duration ──
## 不走 apply_status（那是"max"语义，状态当前剩余可能就 < initial），
## 直接覆写 status_effects[id]。状态不存在时静默跳过。
static func _refresh_status(ac: Aircraft, id: String) -> void:
	if ac == null or not is_instance_valid(ac):
		return
	if not ac.status_effects.has(id):
		return
	var initial: float = float(ac.status_initial_durations.get(id, 0.0))
	if initial <= 0.0:
		return
	ac.status_effects[id] = initial


## ── 内部：从 Aircraft 拿 upgrade_stacks（生存模式飞机才有） ──
## 不在 Aircraft 上时返回空 Dict，钩子链早退
static func _get_upgrade_stacks(ac: Aircraft) -> Dictionary:
	# survivor_mode 在玩家飞机上写 set_meta("upgrade_stacks", { id → int })
	if ac.has_meta("upgrade_stacks"):
		return ac.get_meta("upgrade_stacks")
	return {}


