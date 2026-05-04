class_name EquipmentPart
extends Resource

## 局外配件（Loadout Equipment Part）—— Merit 购买 + 槽位预算装备
##
## 设计：每架飞机有总槽位预算（默认 6 格，PlayableAircraft.slot_budget 可覆盖），
## 配件按等级占 1/2/3 格不等，玩家可自由组合（6×T1 / 2×T3 / 混搭 ...）。
##
## 加成模型与 PlayableAircraft 一致——multiplier（默认 1.0）+ bonus（默认 0.0）。
## 在 SurvivorPlayableSetup.apply 末尾遍历 LoadoutLedger.get_equipped 累加。

# ── 元数据 ──
@export_group("元数据")
@export var id: StringName = &""              ## 唯一 ID（如 "gun_dmg_t1"）
@export var display_name_key: String = ""     ## i18n key（不存在时退回 id）
@export var description_key: String = ""     ## 描述 i18n key
@export var category: StringName = &"weapon" ## "weapon" / "missile" / "radar" / "ecm" / "doctrine"
@export var icon_color: Color = Color(0.8, 0.8, 0.8, 1.0)

## 解锁件专用：拥有此件后，对应 keyword 的 in-run 升级会进入随机池。
## 例：["fear"] → 拥有此件解锁所有 keywords 含 "fear" 的升级。
## 解锁件通常 slot_cost=0（永久许可，不占装备槽），放在货架顶部固定显示。
@export var unlocks_keywords: PackedStringArray = []

## Doctrine 专用：flavor 文 i18n key，按当前 locale 取对应语言一行
## 例："EQUIPMENT_DOCTRINE_FEAR_FLAVOR" → tr() 出 "植入动摇。" / "Sow wavering." / "動揺を植える。"
@export var flavor_text_key: String = ""

# ── 槽位 / 经济 ──
@export_group("槽位 / 经济")
@export_range(1, 3, 1) var slot_cost: int = 1   ## 占用格数（1/2/3）
@export_range(1, 3, 1) var tier: int = 1        ## 1/2/3 — UI 排序 / 边框颜色
@export var merit_cost: int = 100               ## 购买价

# ── 飞行/生存 加成 ──
@export_group("飞行 / 生存")
@export var hp_bonus: float = 0.0
@export var max_speed_mult: float = 1.0
@export var max_g_bonus: float = 0.0
@export var roll_rate_mult: float = 1.0

# ── 机炮加成 ──
@export_group("机炮")
@export var gun_damage_mult: float = 1.0
@export var gun_range_mult: float = 1.0
@export var gun_firerate_mult: float = 1.0
@export var gun_ammo_mult: float = 1.0          ## 应用于 gun.max_ammo + aircraft.ammo

# ── 导弹加成 ──
@export_group("导弹")
@export var missile_tracking_g_mult: float = 1.0     ## missile.max_g
@export var missile_seeker_fov_mult: float = 1.0     ## missile.seeker_fov（cap 120°）
@export var missile_reload_mult: float = 1.0         ## aircraft.missile_reload_duration

# ── 雷达 / 锁定 ──
@export_group("雷达")
@export var radar_range_mult: float = 1.0
@export var radar_angle_mult: float = 1.0       ## params.radar_half_angle（cap 90°）
@export var lock_time_mult: float = 1.0         ## params.lock_time（floor 0.5s）

# ── 电战 ──
@export_group("电战")
@export var flare_cooldown_mult: float = 1.0    ## flare.cooldown + reload_time
@export var lock_resistance_mult: float = 1.0   ## aircraft.lock_resistance_mult（累乘）
@export var flare_shield_seconds_bonus: float = 0.0  ## aircraft.flare_lock_immunity 加成


## 把本配件加成应用到 aircraft 上（params 必须已 deep duplicate）。
## 在 SurvivorPlayableSetup.apply 末尾按 LoadoutLedger 装备列表逐个调用。
func apply_to(aircraft: Node) -> void:
	if aircraft == null or aircraft.params == null:
		return
	var p: AircraftParams = aircraft.params

	# ── 飞行/生存 ──
	if hp_bonus != 0.0:
		p.max_hp += hp_bonus
		aircraft.hp += hp_bonus
	if max_speed_mult != 1.0:
		p.max_speed *= max_speed_mult
	if max_g_bonus != 0.0:
		p.max_g += max_g_bonus
	if roll_rate_mult != 1.0:
		p.roll_rate *= roll_rate_mult

	# ── 机炮 ──
	if p.gun != null:
		if gun_damage_mult != 1.0:
			p.gun.bullet_damage *= gun_damage_mult
		if gun_range_mult != 1.0:
			p.gun.max_range *= gun_range_mult
		if gun_firerate_mult != 1.0:
			p.gun.fire_rate *= gun_firerate_mult
		if gun_ammo_mult != 1.0:
			var ammo_delta: int = int(round(p.gun.max_ammo * (gun_ammo_mult - 1.0)))
			p.gun.max_ammo += ammo_delta
			aircraft.ammo += ammo_delta

	# ── 导弹（玩家只有主槽，副槽已废） ──
	if p.missile != null:
		if missile_tracking_g_mult != 1.0:
			p.missile.max_g *= missile_tracking_g_mult
		if missile_seeker_fov_mult != 1.0:
			p.missile.seeker_fov = minf(p.missile.seeker_fov * missile_seeker_fov_mult, 120.0)
	if missile_reload_mult != 1.0:
		aircraft.missile_reload_duration *= missile_reload_mult

	# ── 雷达 ──
	if radar_range_mult != 1.0:
		p.radar_range *= radar_range_mult
	if radar_angle_mult != 1.0:
		p.radar_half_angle = minf(p.radar_half_angle * radar_angle_mult, 90.0)
	if lock_time_mult != 1.0:
		p.lock_time = maxf(p.lock_time * lock_time_mult, 0.5)

	# ── 电战 ──
	if flare_cooldown_mult != 1.0 and p.flare != null:
		p.flare.cooldown *= flare_cooldown_mult
		p.flare.reload_time *= flare_cooldown_mult
	if lock_resistance_mult != 1.0:
		aircraft.lock_resistance_mult *= lock_resistance_mult
	if flare_shield_seconds_bonus != 0.0:
		aircraft.flare_lock_immunity += flare_shield_seconds_bonus
