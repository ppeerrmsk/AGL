class_name SurvivorPlayableSetup
extends RefCounted

## 把 PlayableAircraft 档案应用到一个具体的 Aircraft 实例上。
##
## 调用前请确保 aircraft.params 已经是 deep duplicate（这里只负责应用差异，
## 不负责复制 base_params）。
##
## 这里是数据驱动版的"主角飞机改造"——
## 替代原 survivor_mode.gd 里硬编码的 F-16 buff 块。
##
## 用法（玩家长机）：
##   var profile: PlayableAircraft = load("res://resources/playable_f16.tres")
##   player.params = profile.base_params.duplicate(true)
##   SurvivorPlayableSetup.deep_dup_weapons(player.params)
##   SurvivorPlayableSetup.apply(player, profile)
##
## 用法（起始僚机）：与玩家完全相同的属性，但不带 codename 后缀
##   wingman.params = profile.base_params.duplicate(true)
##   SurvivorPlayableSetup.deep_dup_weapons(wingman.params)
##   SurvivorPlayableSetup.apply(wingman, profile, true)
##
## is_wingman=true 时跳过 display_name 修改（僚机保留 base_params 自带的短名，
## 例如 "F-14"，而不是带主角 codename 的 "F-14 TopGun"）。其它所有属性/武器/
## 实例标志都和长机一致，保证起始数值完全对齐。
static func apply(aircraft: Node, profile: PlayableAircraft, is_wingman: bool = false) -> void:
	if not aircraft or not profile:
		return
	var p: AircraftParams = aircraft.params
	if not p:
		return

	# ── 显示名 ──
	# HUD/数据标签里显示的是 base_params.display_name（短名，例如 "F-16"），
	# 这里把 codename 拼上去，得到 "F-16 SmartFalcon"。
	# PlayableAircraft.display_name（"F-16C Block 50"）只用于选择卡片，不写回 params。
	# 僚机不带 codename，保留基础名（"F-14" 而不是 "F-14 TopGun"）。
	if not is_wingman and profile.codename != "":
		p.display_name = "%s %s" % [p.display_name, profile.codename]

	# ── 基础属性倍率/加成 ──
	p.radar_range *= profile.radar_range_mult
	p.max_speed *= profile.max_speed_mult
	p.cruise_speed *= profile.cruise_speed_mult
	p.acceleration *= profile.acceleration_mult
	p.roll_rate *= profile.roll_rate_mult
	p.lock_time *= profile.lock_time_mult
	p.max_g += profile.max_g_bonus

	# ── 主导弹 ──
	if p.missile and profile.missile_count_override >= 0:
		p.missile.max_count = profile.missile_count_override

	# ── 副导弹（AGM）属性继承主导弹 ──
	# 设计决策：AGM 只是对地显示名，数值完全复用主导弹，这样所有"导弹"升级
	# （数量/制导/装填/数量上限）在对地时一样生效，不会出现"升了 AAM 升级 AGM
	# 还是原始弱鸡"的情况。显示名保留 "AGM-xx" 满足军事细节党。
	if p.missile and p.secondary_missile:
		var agm_name := p.secondary_missile.display_name
		p.secondary_missile = p.missile.duplicate()
		p.secondary_missile.display_name = agm_name

	# ── 机炮 ──
	if p.gun:
		if profile.gun_damage_mult != 1.0:
			p.gun.bullet_damage *= profile.gun_damage_mult
		if profile.gun_range_override > 0.0:
			p.gun.max_range = profile.gun_range_override
		if profile.gun_cone_override > 0.0:
			p.gun.fire_cone_half_angle = profile.gun_cone_override

	# ── 战斗风格覆盖 ──
	if profile.combat_override:
		p.combat = profile.combat_override.duplicate()

	# ── 热诱弹覆盖 ──
	if profile.flare_override:
		p.flare = profile.flare_override.duplicate()

	# ── 实例标志 ──
	aircraft.flares_guaranteed = profile.flares_guaranteed
	aircraft.enable_missile_reload = profile.enable_missile_reload
	aircraft.enable_flare_reload = profile.enable_flare_reload
	aircraft.enable_gun_reload = profile.enable_gun_reload
	aircraft.infinite_fuel = profile.infinite_fuel
	aircraft.survivor_missile_damage_cap = profile.missile_damage_cap
	aircraft.survivor_bullet_damage_cap = profile.bullet_damage_cap
	aircraft.bullet_dodge_chance = profile.bullet_dodge_chance


## 工具：把 AircraftParams 上的所有外部子资源 deep duplicate 一份，
## 防止生存模式的运行时修改污染原 .tres
static func deep_dup_weapons(p: AircraftParams) -> void:
	if not p:
		return
	if p.missile:
		p.missile = p.missile.duplicate()
	if p.secondary_missile:
		p.secondary_missile = p.secondary_missile.duplicate()
	if p.gun:
		p.gun = p.gun.duplicate()
	if p.rocket:
		p.rocket = p.rocket.duplicate()
	if p.flare:
		p.flare = p.flare.duplicate()
	if p.combat:
		p.combat = p.combat.duplicate()
	# 装备数组深拷贝（commit 10/13）：每件 EquipmentParams 都 dup，避免运行时
	# 修改（如电磁炮 cooldown 升级）污染共享 .tres
	if p.equipment != null and not p.equipment.is_empty():
		var dup_arr: Array[EquipmentParams] = []
		for eq in p.equipment:
			if eq != null:
				dup_arr.append(eq.duplicate())
			else:
				dup_arr.append(null)
		p.equipment = dup_arr
