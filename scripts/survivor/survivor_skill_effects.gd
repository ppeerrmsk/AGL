class_name SurvivorSkillEffects
extends RefCounted

## 技能静态效果执行器。显式接收目标飞机，禁止通过临时改写 SurvivorPlayer.aircraft 来复用逻辑。
## 自动触发型 skill_flag 仍由 SkillHooks/消费点读取有效层数，本模块只处理获得时的静态投影。

static func apply(owner: Node, aircraft: Aircraft, upgrade: Dictionary) -> void:
	if not aircraft or not aircraft.params:
		return
	var p := aircraft.params
	var stat: String = upgrade["stat"]

	match stat:
		"max_hp":
			# 纯 HP 提升；机炮闪避现由座舱护甲的复合效果提供
			var add: float = upgrade["value"]
			p.max_hp += add
			aircraft.hp += add  # 升级时也恢复
		"missile_count":
			# 玩家无副导弹（2026-04-29），只 +主槽
			if p.missile:
				p.missile.max_count += int(upgrade["value"])
				aircraft.missiles_remaining += int(upgrade["value"])
		"missile_tracking":
			# 制导升级：导弹过载 +30%，导引常数 +0.5
			if p.missile:
				p.missile.max_g *= (1.0 + float(upgrade["value"]))
				p.missile.nav_constant += 0.5
		"missile_bounce":
			# 战区次世代“连锁弹头”：命中后沿原航向继续，逐弹逐目标只伤一次。
			aircraft.missile_chain_active = true
		"proximity_fuze":
			# 进化：近炸引信，导弹爆炸产生 AOE 区域
			aircraft.missile_proximity_aoe = true
		"missile_reload":
			aircraft.missile_reload_duration *= (1.0 - float(upgrade["value"]))
		"multi_lock":
			aircraft.max_simultaneous_locks += int(upgrade["value"])
		"missile_swarm":
			# 弹舱 +4、锁定目标数 +3；齐射消费点按锁数截断候选目标。
			# 负面：导弹 max_g ×0.85（轻微追踪减劣，弹群压火力不靠单发精度）
			var swarm_n: int = int(upgrade["value"])
			var penalty: float = float(upgrade.get("tracking_penalty", 0.85))
			if p.missile:
				p.missile = p.missile.duplicate()
				p.missile.max_count += swarm_n
				p.missile.max_g *= penalty
				aircraft.missiles_remaining += swarm_n
			aircraft.max_simultaneous_locks += int(upgrade.get("lock_bonus", 3))
		"gun_damage":
			if p.gun:
				p.gun.bullet_damage *= (1.0 + float(upgrade["value"]))
				var ammo_bonus: int = int(round(
					p.gun.max_ammo * float(upgrade.get("ammo_bonus", 0.0))))
				p.gun.max_ammo += ammo_bonus
				aircraft.ammo += ammo_bonus
		"gun_multishot":
			# 进化：多管齐射，额外射出左右两道子弹
			aircraft.gun_extra_barrels = int(upgrade["value"])
		"gun_ammo":
			if p.gun:
				p.gun.max_ammo += int(upgrade["value"])
				aircraft.ammo += int(upgrade["value"])
		"gun_reload":
			aircraft.gun_reload_duration *= (1.0 - float(upgrade["value"]))
		"gun_firerate":
			if p.gun:
				p.gun.fire_rate *= (1.0 + float(upgrade["value"]))
		"gun_range":
			if p.gun:
				p.gun = p.gun.duplicate()
				p.gun.max_range *= (1.0 + float(upgrade["value"]))
		"gun_ciws":
			aircraft.gun_ciws_active = true
		"gunship_mode":
			# 全向自动炮塔：固定 360° 火界；极速永久降至 60%，不改 AI 的 ASSAULT 选点。
			if p.gun:
				p.gun = p.gun.duplicate()
				p.gun.fire_cone_half_angle = 180.0
			p.max_speed *= 0.60
			aircraft.gunship_mode_active = true
		"heavy_gun":
			if p.gun:
				p.gun = p.gun.duplicate()
				p.gun.max_range += float(upgrade["value"])
		"berserk_virus":
			aircraft.berserk_virus_active = true
			aircraft.enforce_berserk_virus_free_mode()
		"hunter":
			aircraft.hunter_unlocked = true
		"radar_range":
			p.radar_range *= (1.0 + float(upgrade["value"]))
		"lock_time":
			p.lock_time = maxf(p.lock_time + float(upgrade["value"]), float(upgrade.get("min_lock_time", 0.5)))
		"speed":
			# 只抬最大速度天花板 + 加速度；不动 cruise_speed。
			# aircraft.gd 用 max(corner_speed, cruise*0.85) 作为转弯最低速度地板，
			# 若 cruise 同步放大，堆层后会把飞机压在高速上转不动弯。
			var mult := 1.0 + float(upgrade["value"])
			p.max_speed *= mult
			p.acceleration *= (1.0 + float(upgrade["value"]) * float(upgrade.get("accel_ratio", 0.5)))
		"maneuver":
			p.roll_rate *= (1.0 + float(upgrade["value"]))
			p.max_g += float(upgrade.get("max_g_bonus", 1.0))
			p.max_g_structural += float(upgrade.get("structural_g_bonus", 0.5))
		"flare_cooldown":
			if p.flare:
				p.flare.cooldown *= (1.0 - float(upgrade["value"]))
				p.flare.reload_time *= (1.0 - float(upgrade["value"]))
		"rocket_firerate_range":
			# A-10 火箭弹专属：齐射 CD 减少 + 飞行射程增加
			# value 0.25 → CD ×0.75，max_range ×1.25，max_fire_range ×1.25
			# 衰减末端 (min_damage_mult) 不动，保留"远端略弱"身份
			if p.rocket:
				p.rocket = p.rocket.duplicate()
				var v: float = float(upgrade["value"])
				p.rocket.burst_cooldown *= (1.0 - v)
				p.rocket.max_range *= (1.0 + v)
				p.rocket.max_fire_range *= (1.0 + v)
		"torpedo_tracking_boost":
			# A-10 漂浮雷专属：scan_range + turn_rate 双倍强化
			# value 0.6 → scan ×1.6，turn ×2.0
			if p.torpedo:
				p.torpedo = p.torpedo.duplicate()
				var v2: float = float(upgrade["value"])
				p.torpedo.tracking_scan_range_m *= (1.0 + v2)
				p.torpedo.tracking_turn_rate_dps *= (1.0 + v2 + v2)  ## 1 + 0.6 + 0.6 = ×2.2，第二层 ×3.4 阈值递增明显
		# ── 720 批：装备门控强化组（spec skills-720-rework §2.2，同 railgun 模式 params 直改）──
		"torpedo_extra":
			# 漂浮雷·额外：每层单次投放数量 +1
			if p.torpedo:
				p.torpedo = p.torpedo.duplicate()
				p.torpedo.drop_count += int(upgrade["value"])
		"qmaam_boost":
			# QAAM 强化：格斗弹 +1/层，射程 +10%/层（后向包线与锁定距离同乘）
			if p.secondary_missile:
				p.secondary_missile = p.secondary_missile.duplicate()
				p.secondary_missile.max_count += int(upgrade["value"])
				var qr: float = 1.0 + float(upgrade.get("range_bonus", 0.10))
				p.secondary_missile.max_range_rear *= qr
				if p.secondary_missile.lock_max_range_px > 0.0:
					p.secondary_missile.lock_max_range_px *= qr
				aircraft.secondary_missiles_remaining += int(upgrade["value"])
		"wingman_extra":
			# 忠诚僚机·额外：单层同屏上限 +2；即时部署由 SurvivorMode 统一获得入口执行。
			if p.loyal_wingman:
				p.loyal_wingman = p.loyal_wingman.duplicate()
				p.loyal_wingman.max_simultaneous += int(upgrade["value"])
		"wingman_armed":
			# 忠诚僚机·武装：无人机武器伤害/射程 + 自爆 AOE 伤害提升
			if p.loyal_wingman:
				p.loyal_wingman = p.loyal_wingman.duplicate()
				var wd: float = 1.0 + float(upgrade["value"])
				if p.loyal_wingman.drone_aircraft_params:
					p.loyal_wingman.drone_aircraft_params = p.loyal_wingman.drone_aircraft_params.duplicate(true)
					var dp := p.loyal_wingman.drone_aircraft_params
					if dp.gun:
						dp.gun.bullet_damage *= wd
						dp.gun.max_range *= (1.0 + float(upgrade.get("range_bonus", 0.20)))
				p.loyal_wingman.kamikaze_aoe_damage *= wd
		"cockpit_armor":
			# 座舱护甲：地面火力减伤 + 机炮闪避（闪避由 take_bullet_damage 的全局 cap 兜底）
			aircraft.ground_damage_taken_mult *= float(upgrade["value"])
			aircraft.bullet_dodge_chance += float(upgrade.get("bullet_dodge_bonus", 0.0))
		"flare_shield":
			# 电子对抗套件：释放时解除锁定，并延长锁定免疫时间；不增加载弹量
			aircraft.flare_lock_immunity += float(upgrade["value"])
		"fear_squad_spread":
			# 恐惧扩散：玩家击杀任意敌机后对同小队成员施加 FEAR
			aircraft.fear_squad_spread_duration = float(upgrade["value"])
		"fear_chills":
			# 寒颤：所有由玩家施加的 FEAR 同步附带 SLOW
			aircraft.fear_applies_slow = true
		"armor":
			# 复合装甲：DR 软上限公式 armor/(armor+100)；导弹按 50% 穿甲计算
			p.armor += float(upgrade["value"])
		"xp_mult":
			# 经验倍率（队级单实例）：每层 +20% 累加，硬顶 ×1.4。
			# 720 T2 起记在 SurvivorPlayer 层（切控/换帅不丢；消费点 survivor_spawner 折算 XP）
			owner.xp_multiplier = minf(
				float(owner.xp_multiplier) + float(upgrade["value"]),
				float(upgrade.get("xp_cap", 1.4)))
		"radar_angle":
			# 广角扫描：radar_half_angle ×(1+value)，硬 cap max_deg
			p.radar_half_angle = minf(p.radar_half_angle * (1.0 + float(upgrade["value"])), float(upgrade.get("max_deg", 90.0)))
		"seeker_fov":
			# 广角导引头：MissileParams.seeker_fov ×(1+value)，硬 cap max_deg
			# 2026-04-21：同步 AGM（AGM 是 AAM 克隆，所有导弹升级都该覆盖）
			var fov_mult := 1.0 + float(upgrade["value"])
			var fov_cap := float(upgrade.get("max_deg", 120.0))
			if p.missile:
				p.missile = p.missile.duplicate()
				p.missile.seeker_fov = minf(p.missile.seeker_fov * fov_mult, fov_cap)
		"gun_accuracy":
			# 合并“瞄准辅助 + 枪械精度”：散布、引导误差、弹寿命与自动开火锥同层成长。
			if p.gun:
				p.gun = p.gun.duplicate()
				p.gun.spread_angle = maxf(p.gun.spread_angle * (1.0 - float(upgrade["value"])), float(upgrade.get("min_deg", 0.1)))
			# 同时提升飞行员 aim_skill（lead 误差减小），与 spread 减小复合
			var aim_boost: float = float(upgrade.get("aim_skill_boost", 0.0))
			if aim_boost > 0.0:
				aircraft.pilot_aim_skill = clampf(aircraft.pilot_aim_skill + aim_boost, 0.0, 1.0)
			# 720 批追加：子弹生存时间加长（远端弹道延伸，bullet_manager 用 gun.lifetime 定寿命）
			if p.gun and float(upgrade.get("lifetime_bonus", 0.0)) > 0.0:
				p.gun.lifetime *= (1.0 + float(upgrade["lifetime_bonus"]))
			# cap 对"已超 cap"的锥角不倒退（722 sig_x44 置 90° 后再拿本技能不得缩回 45°）
			if p.gun:
				var aa_cap: float = maxf(float(upgrade.get("max_deg", 45.0)), p.gun.fire_cone_half_angle)
				p.gun.fire_cone_half_angle = minf(
					p.gun.fire_cone_half_angle * (1.0 + float(upgrade.get("fire_cone_bonus", 0.0))),
					aa_cap)
		"missile_boost":
			# 火箭助推：cooldown ×0.85 + burn_time ×1.15 + motor_accel ×1.10（每层复合）
			if p.missile:
				p.missile = p.missile.duplicate()
				p.missile.cooldown *= float(upgrade.get("cooldown_mult", 0.85))
				p.missile.motor_burn_time *= float(upgrade.get("burn_mult", 1.15))
				p.missile.motor_acceleration *= float(upgrade.get("accel_mult", 1.10))
		"vapor_dodge":
			# 云雾机动（战区奖励）：高度切换 ×2 + 云中任意档位锁定速率 ×0.1
			aircraft.altitude_authority_mult *= float(upgrade.get("altitude_mult", 2.0))
			aircraft.cloud_lock_stealth = true
		"ecm_pod":
			# ECM 吊舱（战区奖励）：敌方雷达对我的有效距离 ×0.75
			aircraft.ecm_range_mult *= float(upgrade.get("range_mult", 0.75))
		"shock_absorb":
			# 冲击吸收（战区奖励）：伤害的 40% 慢慢回血
			aircraft.shock_absorb_active = true
		"cobra_skill":
			# 眼镜蛇机动：当前操控机按 R，AI 僚机威胁自动；确保模块存在
			aircraft.cobra_skill_active = true
			var has_cobra := false
			for child in aircraft.get_children():
				if child is CobraManeuver:
					has_cobra = true
					break
			if not has_cobra:
				var cobra := CobraManeuver.new()
				cobra.name = "CobraManeuver"
				aircraft.add_child(cobra)
		"executioner":
			# 侩子手（战区奖励）：连续不受伤击杀堆层，最高 5 层
			aircraft.executioner_active = true
		# ── X-02 电磁炮升级 ──
		"railgun_charge":
			# 充能时间 -20%（每层）
			var rg := p.get_equipment_of_kind("railgun") as RailgunEquipment
			if rg:
				rg.charge_duration *= (1.0 - float(upgrade["value"]))
		"railgun_range":
			var rg2 := p.get_equipment_of_kind("railgun") as RailgunEquipment
			if rg2:
				rg2.max_range_m += float(upgrade["value"])
		# （railgun_damage 电磁炮强化已随 720 批移除——spec skills-720-rework §2.3）
		"railgun_double":
			# 双发（720 批）：蓄力完成连发两发（RailgunEquipment 发射序列）
			var rgd := p.get_equipment_of_kind("railgun") as RailgunEquipment
			if rgd:
				rgd.double_shot = true
		"missile_second_stage":
			# 二段推进（720 批）：本机导弹燃尽后续推 + 转弯渐强（missile_manager spawn 打标）
			aircraft.missile_second_stage_active = true
		"manual_dodge":
			# 胆大妄为：全队禁普通自动 flare + flare +6；受控机按 R，AI 僚机威胁自动
			aircraft.manual_dodge_active = true
			if p.flare:
				p.flare = p.flare.duplicate()
				p.flare.max_flares += 6
				aircraft.flares_remaining += 6
		"displacement_roll":
			# 位移滚转：共享 R 槽；轨迹、命中窗和 AI 威胁门由 Aircraft 协调器统一处理。
			aircraft.displacement_roll_active = true
		"vertical_break":
			# 垂直越过：共享 R 槽；高度曲线不通过常规爬升倍率注入。
			aircraft.vertical_break_active = true
		# ── X-02 激光升级 ──
		"laser_cooldown":
			# 激光散热合并过载：每层同时提高散热效率与过热阈值
			var le := p.get_equipment_of_kind("laser") as LaserEquipment
			if le:
				le.heat_cooldown_per_second *= (1.0 + float(upgrade["value"]))
				le.heat_max *= (1.0 + float(upgrade.get("heat_bonus", 0.0)))
		"laser_range":
			var le2 := p.get_equipment_of_kind("laser") as LaserEquipment
			if le2:
				le2.max_range_m *= (1.0 + float(upgrade["value"]))
				le2.max_simultaneous_targets += int(upgrade.get("extra_targets", 0))
		"lock_resistance":
			# 强化吊舱：敌人对我累积锁定速率 ÷ lock_resistance_mult（可堆叠）
			aircraft.lock_resistance_mult *= (1.0 + float(upgrade["value"]))
		"data_link":
			# F-14 数据链：长机 aura_skill 标记开启 + 现役队友（team 0 飞机）雷达范围加成
			# 锁定共享由 survivor_mode._update_radar_locks 读 aura_skill 触发；发射仍受
			# cone/envelope/range 校验（aircraft_weapons.gd），"看不见就能射" 不会发生
			aircraft.aura_skill = &"data_link"
			var radar_mult := 1.0 + float(upgrade["value"])
			for u in CombatUnit.all_units:
				if not is_instance_valid(u):
					continue
				if u is Aircraft and u.is_player_squad() and u != aircraft and u.params:
					u.params.radar_range *= radar_mult
		"dogfight":
			# 格斗大师：降低失速速度、增强减速、改善低速追踪
			p.stall_speed_base *= float(upgrade.get("stall_speed_mult", 0.88))
			p.deceleration *= float(upgrade.get("decel_mult", 1.3))
			p.g_drag_factor *= float(upgrade.get("g_drag_mult", 0.85))
			if p.combat:
				p.combat = p.combat.duplicate()
				p.combat.overshoot_speed_margin *= float(upgrade.get("overshoot_speed_margin_mult", 0.97))
				p.combat.turn_slow_speed_mult *= float(upgrade.get("turn_slow_speed_mult", 0.9))
		# ── §1.2 模式修饰器（现役肉鸽技能按加力窗口消费）──
		"evasion_speed_boost":
			# 加力窗口顶速倍率（physics effective_* 统一消费）
			_set_evasion_modifier(aircraft, "cruise_speed_mult", float(upgrade["value"]))
		"evasion_weapon_cd":
			# 加力窗口武器 cd 时间倍率（gun + missile + rocket + 副槽；tick 侧换算 rate）
			_set_evasion_modifier(aircraft, "weapon_cd_mult", float(upgrade["value"]))
		"evasion_flare_cd":
			# evasion 模式 flare cd 倍率
			_set_evasion_modifier(aircraft, "flare_cd_mult", float(upgrade["value"]))
		"evasion_missile_reload":
			# evasion 模式导弹装填倍率
			_set_evasion_modifier(aircraft, "missile_reload_mult", float(upgrade["value"]))
		# ── C 阶段数值技能 ──
		"lock_panic_g":
			# 被锁时机动加成（每层 +20%，physics.effective_max_g 末乘）
			aircraft.lock_panic_g_mult *= (1.0 + float(upgrade["value"]))
		"low_hp_flare_reload":
			# hp < 50% 时 flare reload 倍率（flares.update reload 累加时查）
			aircraft.low_hp_flare_reload_mult = float(upgrade["value"])
		"high_alt_lock_speed":
			# HIGH 档时锁定速率 bonus（main.gd 雷达循环）
			aircraft.high_alt_lock_speed_bonus = float(upgrade["value"])
		"close_range_lock":
			# 近距捕获：距离曲线由 survivor_mode 雷达循环消费；max 保证重放幂等。
			aircraft.close_range_lock_max_mult = maxf(
				aircraft.close_range_lock_max_mult, float(upgrade["value"]))
		"ab_gun_regen":
			# AB 时机炮 regen/sec（weapons.update_gun 在 ab=true 时累加）
			aircraft.ab_gun_regen_per_sec = float(upgrade["value"])
		"altitude_energy_cycle":
			# DIVE 单机超储供弹 + CLIMB 当前操控机贡献共享加力。
			aircraft.altitude_cycle_gun_regen_per_sec = float(upgrade["value"])
			aircraft.altitude_cycle_gun_overstock_mult = float(
				upgrade.get("gun_overstock_mult", 2.0))
			aircraft.altitude_cycle_ab_regen_per_sec = float(
				upgrade.get("ab_regen_per_sec", 0.2))
		"alt_change_stealth":
			# 高度变化时 lock_rate 衰减系数（main.gd 雷达循环）
			aircraft.alt_change_stealth_factor = float(upgrade["value"])
		"head_on_gun_dodge":
			# 对头时机炮闪避加成（take_bullet_damage 几何检查）
			aircraft.head_on_gun_dodge_bonus = float(upgrade["value"])
		"gun_fire_dr":
			# 机炮发射时减伤窗口（aircraft_weapons 开火后刷时间戳；_apply_damage 查）
			aircraft.gun_fire_dr_window = float(upgrade.get("window", 0.4))
			aircraft.gun_fire_dr_amount = float(upgrade["value"])
		"fear_on_lock":
			# 锁定累积达 N 秒后给目标施 FEAR（survivor_mode._update_radar_locks 维护）
			aircraft.fear_on_lock_threshold = float(upgrade["value"])
		"cloud_overload":
			# 云中按天气采样频率刷新短时 OVERLOAD，统一触发持续时间/嗜血联动。
			aircraft.cloud_overload_active = true
			if aircraft.cloud_state >= 1:
				aircraft.apply_status(StatusEffects.OVERLOAD,
					StatusEffects.CLOUD_OVERLOAD_BASE_DURATION, "max")
		"evac_shift":
			# 阵地转移（720 批）：撤离冲刺提速 + 受伤减半（physics accessor / _apply_damage 消费）
			aircraft.evac_shift_active = true
		"cloud_weapon_cd":
			# 云中并入武器 CD 速率模型；拾取时无需改写现有倒计时。
			aircraft.cloud_weapon_cd_mult = float(upgrade["value"])
		"evasion_stealth":
			# 进入 evasion 时启用 STEALTH（独立 bool + 派生 OR；不进 status_effects 避免冲突）
			aircraft.evasion_stealth_active = true
			# 若当前已在 evasion → 立刻同步进派生
			if aircraft.is_afterburner_mode_active():
				aircraft._in_evasion_stealth = true
		"evasion_overstock":
			# evasion 期间每 N 秒装填 1 发导弹，突破 max_count×2
			aircraft.evasion_overstock_interval = float(upgrade["value"])
		"missile_cd_stealth":
			# 导弹 cd / 装填期间获得 STEALTH（独立 bool + 派生 OR）
			aircraft.missile_cd_stealth_active = true
		"head_on_jam":
			# 我对头某敌人累积 N 秒后给该敌人 JAM
			aircraft.head_on_jam_threshold = float(upgrade["value"])
		"rear_aura_slow":
			# 后半球内敌人每 0.5s 获得 SLOW
			aircraft.rear_aura_slow_radius_px = float(upgrade["value"])
		"low_alt_gun_dodge":
			# 低空时机炮闪避加成（take_bullet_damage LOW/GROUND 分支）
			aircraft.low_alt_gun_dodge_bonus = float(upgrade["value"])
		"jam_aura":
			# 全向 JAM 光环（每 0.5s 半径内敌人 JAM 1.5s）
			aircraft.jam_aura_radius_px = float(upgrade["value"])
		"f14_squad_lock_slow":
			# F-14 专属：全僚机锁定同一敌机时给该敌机施加 SLOW（survivor_mode 雷达循环维护）
			aircraft.f14_squad_lock_slow_active = true
		"evasion_herbst":
			# J-Turn：当前操控机按 R，AI 僚机在 evasion 威胁下自动启动
			# 必须确保 HerbstManeuver 子节点存在
			aircraft.evasion_herbst_active = true
			var has_herbst := false
			for child in aircraft.get_children():
				if child is HerbstManeuver:
					has_herbst = true
					break
			if not has_herbst:
				var hm := HerbstManeuver.new()
				hm.name = "HerbstManeuver"
				aircraft.add_child(hm)
		# ── 722 批：机体签名技能（spec aircraft-signature-skills；skill_flag 型走 meta 无需分支）──
		"sig_relaxed_stability":
			# 幻影 2000·静不稳定：永久 G+2 / 滚转 ×1.3（类别 1：AI 经 effective_*() 自动感知）
			p.max_g += 2.0
			p.roll_rate *= 1.3
		"sig_lock_retention":
			# 维京·唯一的锁定：雷达 +250px（=500m）；出锥锁定保持 3s（锁定循环读字段）
			p.radar_range += float(upgrade["value"])
			aircraft.sig_lock_retention_sec = 3.0
		"sig_viffing":
			# 鹞·VIFFing：减速效率 ×1.5；低速无敌判定走 aircraft 字段（tick 消费）
			p.deceleration *= 1.5
			aircraft.sig_viffing_active = true
		"sig_vectored_canard":
			# S/MTD·矢量鸭翼：G+2 收紧转弯半径；拉 G 掉速惩罚 ×0.65
			p.max_g += 2.0
			p.g_drag_factor *= 0.65
		"sig_status_immunity":
			# 鹰狮 E·电战预算：免疫 JAM/SLOW/FEAR（combat_unit.apply_status 早退）
			aircraft.sig_status_immune = true
		"sig_multiband":
			# Su-57·多波段搜索：雷达锥半角 +40°（签名特权 cap 120°，可破常规 90°）
			p.radar_half_angle = minf(p.radar_half_angle + float(upgrade["value"]), 120.0)
		"sig_long_spear":
			# J-20·霹雳长矛：导弹 +1 / 包线射程 ×1.4 / 生存时间 ×1.5
			if p.missile:
				p.missile = p.missile.duplicate()
				p.missile.max_count += 1
				p.missile.max_range_rear *= 1.4
				if p.missile.lock_max_range_px > 0.0:
					p.missile.lock_max_range_px *= 1.4
				p.missile.max_lifetime *= 1.5
				aircraft.missiles_remaining += 1
		"sig_xp_wisdom":
			# F-16·智能鹰：XP 第二乘区 ×1.25（SurvivorPlayer 层，切控/换机不丢；不占 xp_mult 硬顶）
			owner.sig_xp_mult = 1.0 + float(upgrade["value"])
		# 高频判定组：apply 只置位字段，效果在锁定循环 / physics accessor / 武器扫描消费
		"sig_f15":
			aircraft.sig_f15_active = true
		"sig_f15c":
			aircraft.sig_f15c_active = true
		"sig_f15e":
			aircraft.sig_f15e_active = true
		"sig_a6e":
			aircraft.sig_a6e_active = true
		"sig_mig41":
			aircraft.sig_mig41_active = true
		"sig_tornado":
			aircraft.sig_tornado_active = true
		"sig_typhoon":
			aircraft.sig_typhoon_active = true
		"sig_su34":
			aircraft.sig_su34_active = true
		"sig_mig31":
			aircraft.sig_mig31_active = true
		"sig_x44":
			# 高速炮艇：前方 180°绝对射界（与其它扩角取大值，不做角度加法）+ 机炮弹穿透。
			# 扫描/物理锥门/渲染扇形/AI 开火判定全消费点自动生效；已超 90 的不缩
			if p.gun:
				p.gun = p.gun.duplicate()
				p.gun.fire_cone_half_angle = maxf(p.gun.fire_cone_half_angle, float(upgrade["value"]))
			aircraft.gun_bullet_penetration_active = true
		# sig_wyvern（X-02·突击翼龙）在 survivor_mode 获得点特判（railgun 入库走武器库）
		"skill_flag", "axis_focus", "sig_wyvern":
			pass  # 自动词条 / 纯轴卡 / 一次性武器入库分别由各自权威入口处理
		_:
			push_warning("SurvivorSkillEffects: 未实现技能 stat '%s'" % stat)

## 写 evasion_modifiers 倍率。CD 速率模型每帧读取当前值，无需切换模式刷新。
static func _set_evasion_modifier(ac: Aircraft, key: String, mult: float) -> void:
	if ac == null:
		return
	ac.evasion_modifiers[key] = mult
