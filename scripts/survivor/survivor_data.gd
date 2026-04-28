class_name SurvivorData
extends RefCounted

## 生存模式静态数据：敌人波次、升级定义、经验曲线

# ── 升级定义 ─────────────────────────────────────────────
# 每种升级直接修改 Aircraft 的 params（AircraftParams / GunParams / MissileParams）
#
# 必填字段：
#   id / name / desc / stat / value / max_stacks / category
# category: "combat" = 战斗轴, "survival" = 生存轴
#
# 可选字段：
#   evolved: true = 进化技能，不出现在随机池中，由基础技能满级自动触发
#   evolves_to: "xxx" = 满级后自动进化为指定技能
#   requires: 数组 — 飞机必须具备的硬件标签才能获得此升级
#               可选值: "gun" / "missile" / "flare" / "rocket"
#               例：["gun"] 表示无机炮的飞机不会出现该升级
#               留空 = 无硬件要求
#   exclusive_to: 数组 — 仅允许指定的 PlayableAircraft.id 获得（专属升级）
#               例：["f14"] 表示只有 F-14 主角能 roll 到
#               留空 = 通用升级，所有飞机可获取
#
# 技能可用性判定见 SurvivorData.is_upgrade_available_for()

const UPGRADES: Array[Dictionary] = [
	# ── 生存轴 ──
	{
		"id": "hp_up",
		"name": "UPGRADE_HP_UP_NAME",
		"desc": "UPGRADE_HP_UP_DESC",
		"stat": "max_hp",
		"value": 30.0,
		"max_stacks": 5,
		"category": "survival",
		"dodge_per_stack": 0.08,   ## 每层 +8% 机炮闪避
		"dodge_cap": 0.40,         ## 机炮闪避上限
	},
	{
		"id": "speed_up",
		"name": "UPGRADE_SPEED_UP_NAME",
		"desc": "UPGRADE_SPEED_UP_DESC",
		"stat": "speed",
		"value": 0.18,
		"max_stacks": 4,
		"category": "mobility",
		"accel_ratio": 0.5,        ## 加速提升 = value × 此值
	},
	{
		"id": "maneuver_up",
		"name": "UPGRADE_MANEUVER_UP_NAME",
		"desc": "UPGRADE_MANEUVER_UP_DESC",
		"stat": "maneuver",
		"value": 0.25,
		"max_stacks": 3,
		"category": "mobility",
		"max_g_bonus": 1.0,        ## 每层 +1.0 G
		"structural_g_bonus": 0.5, ## 每层 +0.5 结构 G
	},
	{
		"id": "flare_cooldown",
		"name": "UPGRADE_FLARE_COOLDOWN_NAME",
		"desc": "UPGRADE_FLARE_COOLDOWN_DESC",
		"stat": "flare_cooldown",
		"value": 0.20,
		"max_stacks": 3,
		"category": "electronic_warfare",
		"evolves_to": "flare_shield",
		"requires": ["flare"],
	},
	{
		"id": "flare_shield",
		"name": "UPGRADE_FLARE_SHIELD_NAME",
		"desc": "UPGRADE_FLARE_SHIELD_DESC",
		"stat": "flare_shield",
		"value": 3.0,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"evolved": true,
		"requires": ["flare"],
		"bonus_flares": 2,         ## 额外赠送热诱弹数
	},
	{
		"id": "armor_up",
		"name": "UPGRADE_ARMOR_UP_NAME",
		"desc": "UPGRADE_ARMOR_UP_DESC",
		"stat": "armor",
		"value": 40.0,             ## 每层 +40 armor（DR 软上限，100=50%，200=66.7%）
		"max_stacks": 4,
		"category": "survival",
		## 公式在 aircraft.gd _apply_armor：dr = armor / (armor + 100)
		## 导弹穿甲 50%（MISSILE_ARMOR_PENETRATION=0.5），机炮全额生效
		## 1 层=40 → 29%/机炮 17%/导弹
		## 2 层=80 → 44%/机炮 29%/导弹
		## 3 层=120 → 55%/机炮 38%/导弹
		## 4 层=160 → 62%/机炮 44%/导弹
	},
	{
		"id": "stealth_pod",
		"name": "UPGRADE_STEALTH_POD_NAME",
		"desc": "UPGRADE_STEALTH_POD_DESC",
		"stat": "lock_resistance",
		"value": 0.35,             ## 每层 lock_resistance_mult ×1.35
		"max_stacks": 3,
		"category": "electronic_warfare",
		## 敌人锁定速率 ÷ lock_resistance_mult
		## 1 层 ×1.35 → 敌人要 35% 更长时间锁定
		## 2 层 ×1.82 → 82% 更长
		## 3 层 ×2.46 → 146% 更长
	},
	{
		"id": "kill_heal",
		"name": "UPGRADE_KILL_HEAL_NAME",
		"desc": "UPGRADE_KILL_HEAL_DESC",
		"stat": "kill_heal",
		"value": 10.0,
		"max_stacks": 3,
		"category": "survival",
	},
	# ── 战斗轴 ──
	{
		"id": "missile_count",
		"name": "UPGRADE_MISSILE_COUNT_NAME",
		"desc": "UPGRADE_MISSILE_COUNT_DESC",
		"stat": "missile_count",
		"value": 1,
		"max_stacks": 4,
		"category": "missile",
		"requires": ["missile"],
	},
	{
		"id": "missile_tracking",
		"name": "UPGRADE_MISSILE_TRACKING_NAME",
		"desc": "UPGRADE_MISSILE_TRACKING_DESC",
		"stat": "missile_tracking",
		"value": 0.30,
		"max_stacks": 4,
		"category": "missile",
		"evolves_to": "proximity_fuze",
		"requires": ["missile"],
	},
	{
		"id": "proximity_fuze",
		"name": "UPGRADE_PROXIMITY_FUZE_NAME",
		"desc": "UPGRADE_PROXIMITY_FUZE_DESC",
		"stat": "proximity_fuze",
		"value": 1,
		"max_stacks": 1,
		"category": "missile",
		"evolved": true,
		"requires": ["missile"],
	},
	{
		"id": "missile_bounce",
		"name": "UPGRADE_MISSILE_BOUNCE_NAME",
		"desc": "UPGRADE_MISSILE_BOUNCE_DESC",
		"stat": "missile_bounce",
		"value": 1,
		"max_stacks": 1,
		"category": "missile",
		"evolved": true,
		"requires": ["missile"],
	},
	{
		"id": "missile_reload",
		"name": "UPGRADE_MISSILE_RELOAD_NAME",
		"desc": "UPGRADE_MISSILE_RELOAD_DESC",
		"stat": "missile_reload",
		"value": 0.15,
		"max_stacks": 3,
		"category": "missile",
		"evolves_to": "missile_bounce",
		"requires": ["missile"],
	},
	{
		"id": "multi_lock",
		"name": "UPGRADE_MULTI_LOCK_NAME",
		"desc": "UPGRADE_MULTI_LOCK_DESC",
		"stat": "multi_lock",
		"value": 1,
		"max_stacks": 1,
		"category": "missile",
		"requires": ["missile"],
	},
	{
		"id": "gun_damage",
		"name": "UPGRADE_GUN_DAMAGE_NAME",
		"desc": "UPGRADE_GUN_DAMAGE_DESC",
		"stat": "gun_damage",
		"value": 0.20,
		"max_stacks": 5,
		"category": "secondary",
		"evolves_to": "gun_multishot",
		"requires": ["gun"],
	},
	{
		"id": "gun_multishot",
		"name": "UPGRADE_GUN_MULTISHOT_NAME",
		"desc": "UPGRADE_GUN_MULTISHOT_DESC",
		"stat": "gun_multishot",
		"value": 2,
		"max_stacks": 1,
		"category": "secondary",
		"evolved": true,
		"requires": ["gun"],
	},
	{
		"id": "gun_ammo",
		"name": "UPGRADE_GUN_AMMO_NAME",
		"desc": "UPGRADE_GUN_AMMO_DESC",
		"stat": "gun_ammo",
		"value": 100,
		"max_stacks": 5,
		"category": "secondary",
		"requires": ["gun"],
	},
	{
		"id": "gun_reload",
		"name": "UPGRADE_GUN_RELOAD_NAME",
		"desc": "UPGRADE_GUN_RELOAD_DESC",
		"stat": "gun_reload",
		"value": 0.15,
		"max_stacks": 3,
		"category": "secondary",
		"requires": ["gun"],
	},
	{
		"id": "gun_firerate",
		"name": "UPGRADE_GUN_FIRERATE_NAME",
		"desc": "UPGRADE_GUN_FIRERATE_DESC",
		"stat": "gun_firerate",
		"value": 0.25,
		"max_stacks": 4,
		"category": "secondary",
		"requires": ["gun"],
	},
	{
		"id": "gun_range",
		"name": "UPGRADE_GUN_RANGE_NAME",
		"desc": "UPGRADE_GUN_RANGE_DESC",
		"stat": "gun_range",
		"value": 0.20,
		"max_stacks": 4,
		"category": "secondary",
		"evolves_to": "gun_ciws",
		"requires": ["gun"],
	},
	{
		"id": "gun_ciws",
		"name": "UPGRADE_GUN_CIWS_NAME",
		"desc": "UPGRADE_GUN_CIWS_DESC",
		"stat": "gun_ciws",
		"value": 1,
		"max_stacks": 1,
		"category": "secondary",
		"evolved": true,
		"requires": ["gun"],
	},
	{
		"id": "gun_kill_fear",
		"name": "UPGRADE_GUN_KILL_FEAR_NAME",
		"desc": "UPGRADE_GUN_KILL_FEAR_DESC",
		"stat": "gun_kill_fear",
		"value": 1.0,
		"max_stacks": 3,
		"category": "secondary",
		"requires": ["gun"],
		"radius_per_stack": 800.0,  ## 每层 +800px 半径（满级 3 层 = 2400px）
	},
	{
		"id": "radar_range",
		"name": "UPGRADE_RADAR_RANGE_NAME",
		"desc": "UPGRADE_RADAR_RANGE_DESC",
		"stat": "radar_range",
		"value": 0.20,
		"max_stacks": 3,
		"category": "electronic_warfare",
	},
	{
		"id": "lock_time",
		"name": "UPGRADE_LOCK_TIME_NAME",
		"desc": "UPGRADE_LOCK_TIME_DESC",
		"stat": "lock_time",
		"value": -0.5,
		"max_stacks": 3,
		"category": "electronic_warfare",
		"min_lock_time": 0.5,      ## 锁定时间不低于此值（秒）
	},
	{
		"id": "dogfight",
		"name": "UPGRADE_DOGFIGHT_NAME",
		"desc": "UPGRADE_DOGFIGHT_DESC",
		"stat": "dogfight",
		"value": 1,
		"max_stacks": 3,
		"category": "mobility",
		"stall_speed_mult": 0.88,           ## -12% 失速速度
		"decel_mult": 1.3,                  ## +30% 减速
		"g_drag_mult": 1.2,                 ## +20% G 力阻力
		"overshoot_speed_margin_mult": 0.97, ## 更精确速度匹配
		"turn_slow_speed_mult": 0.9,        ## 大角度减速更多
	},
	{
		"id": "cobra_skill",
		"name": "UPGRADE_COBRA_SKILL_NAME",
		"desc": "UPGRADE_COBRA_SKILL_DESC",
		"stat": "cobra_skill",
		"value": 1,
		"max_stacks": 1,
		"category": "mobility",
		## 单层；规避模式下被来袭导弹/后方追尾自动触发眼镜蛇机动
		## 实现：apply_upgrade 时给玩家挂 CobraManeuver 子节点 + 设 cobra_skill_active=true
		## 触发与冷却逻辑见 aircraft.gd._update_cobra_skill
	},
	# ── 新增常规升级（v2026.4.21）──
	{
		"id": "xp_mult",
		"name": "UPGRADE_XP_MULT_NAME",
		"desc": "UPGRADE_XP_MULT_DESC",
		"stat": "xp_mult",
		"value": 0.20,             ## 每层累加 +20%，2 层上限 +40%
		"max_stacks": 2,
		"category": "survival",
		"xp_cap": 1.4,             ## 硬顶 ×1.4
	},
	{
		"id": "radar_angle",
		"name": "UPGRADE_RADAR_ANGLE_NAME",
		"desc": "UPGRADE_RADAR_ANGLE_DESC",
		"stat": "radar_angle",
		"value": 0.15,             ## 每层 ×1.15
		"max_stacks": 3,
		"category": "electronic_warfare",
		"max_deg": 90.0,           ## 硬 cap 90°
	},
	{
		"id": "seeker_fov",
		"name": "UPGRADE_SEEKER_FOV_NAME",
		"desc": "UPGRADE_SEEKER_FOV_DESC",
		"stat": "seeker_fov",
		"value": 0.20,             ## 每层 ×1.20
		"max_stacks": 3,
		"category": "missile",
		"requires": ["missile"],
		"max_deg": 120.0,          ## 硬 cap 120°
	},
	{
		"id": "gun_accuracy",
		"name": "UPGRADE_GUN_ACCURACY_NAME",
		"desc": "UPGRADE_GUN_ACCURACY_DESC",
		"stat": "gun_accuracy",
		"value": 0.20,             ## 每层 spread ×(1-value)=×0.80
		"max_stacks": 4,
		"category": "secondary",
		"requires": ["gun"],
		"min_deg": 0.1,            ## 散布下限 0.1°
		"aim_skill_boost": 0.18,   ## 每层飞行员 aim_skill +0.18，4 层 = +0.72（基础 0.3 → 1.02 cap 1.0）
	},
	{
		"id": "aim_assist",
		"name": "UPGRADE_AIM_ASSIST_NAME",
		"desc": "UPGRADE_AIM_ASSIST_DESC",
		"stat": "aim_assist",
		"value": 0.25,             ## 每层 fire_cone ×1.25
		"max_stacks": 3,
		"category": "secondary",
		"requires": ["gun"],
		"max_deg": 45.0,
	},
	{
		"id": "missile_boost",
		"name": "UPGRADE_MISSILE_BOOST_NAME",
		"desc": "UPGRADE_MISSILE_BOOST_DESC",
		"stat": "missile_boost",
		"value": 1,
		"max_stacks": 3,
		"category": "missile",
		"requires": ["missile"],
		"cooldown_mult": 0.85,     ## 每层 cooldown ×0.85
		"burn_mult": 1.15,         ## 每层 motor_burn_time ×1.15
		"accel_mult": 1.10,        ## 每层 motor_acceleration ×1.10
	},
	# ── 战区奖励（evolved=true 进入战区奖励池，不参与随机升级池）──
	{
		"id": "vapor_dodge",
		"name": "UPGRADE_VAPOR_DODGE_NAME",
		"desc": "UPGRADE_VAPOR_DODGE_DESC",
		"stat": "vapor_dodge",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"evolved": true,
		## 效果两件套：
		##   ① altitude_authority_mult ×2.0 — 切档速度翻倍（LOW↔HIGH 约 45s → 20s）
		##   ② cloud_lock_stealth = true — 云中任意档位 lock_rate ×0.1
		"altitude_mult": 2.0,
	},
	{
		"id": "ecm_pod",
		"name": "UPGRADE_ECM_POD_NAME",
		"desc": "UPGRADE_ECM_POD_DESC",
		"stat": "ecm_pod",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"evolved": true,
		## 效果：ecm_range_mult = 0.75 — 敌方雷达对我的有效距离缩短 25%
		## 在 main.gd / survivor_mode.gd 的雷达循环中，若 dist > radar_range × 此值 则视同脱锥
		"range_mult": 0.75,
	},
	{
		"id": "fire_and_forget",
		"name": "UPGRADE_FIRE_AND_FORGET_NAME",
		"desc": "UPGRADE_FIRE_AND_FORGET_DESC",
		"stat": "fire_and_forget",
		"value": 1,
		"max_stacks": 1,
		"category": "missile",
		"evolved": true,
		"requires": ["missile"],
		## 效果：params.missile.fire_and_forget = true，发射后无需照射，玩家可立刻转向
	},
	{
		"id": "shock_absorb",
		"name": "UPGRADE_SHOCK_ABSORB_NAME",
		"desc": "UPGRADE_SHOCK_ABSORB_DESC",
		"stat": "shock_absorb",
		"value": 1,
		"max_stacks": 1,
		"category": "survival",
		"evolved": true,
		## 效果：受到 ≥2 dmg 时排队回复 floor(dmg × 0.4) HP（5 HP/秒慢速回填）
		## 一击致死无效（必死）；1 dmg 自然 floor=0 不回血
	},
	{
		"id": "executioner",
		"name": "UPGRADE_EXECUTIONER_NAME",
		"desc": "UPGRADE_EXECUTIONER_DESC",
		"stat": "executioner",
		"value": 1,
		"max_stacks": 1,
		"category": "mobility",
		"evolved": true,
		## 效果：连续不受伤击杀，每 2 杀 +1 层（max 5 层）
		## 每层加成（详见 aircraft.gd _executioner_*_mult）：
		##   max_speed +5%、deceleration +10%、missile_reload ×0.92、lock_time ×0.90
		## 受到任意伤害立即清零所有层数 + 计数
	},
	# ── X-02 专属：电磁炮 ──────────────────────────────────────
	{
		"id": "railgun_charge",
		"name": "UPGRADE_RAILGUN_CHARGE_NAME",
		"desc": "UPGRADE_RAILGUN_CHARGE_DESC",
		"stat": "railgun_charge",
		"value": 0.20,
		"max_stacks": 3,
		"category": "weapon",
		"requires": ["railgun"],
	},
	{
		"id": "railgun_range",
		"name": "UPGRADE_RAILGUN_RANGE_NAME",
		"desc": "UPGRADE_RAILGUN_RANGE_DESC",
		"stat": "railgun_range",
		"value": 500.0,
		"max_stacks": 3,
		"category": "weapon",
		"requires": ["railgun"],
	},
	{
		"id": "railgun_damage",
		"name": "UPGRADE_RAILGUN_DAMAGE_NAME",
		"desc": "UPGRADE_RAILGUN_DAMAGE_DESC",
		"stat": "railgun_damage",
		"value": 0.25,
		"max_stacks": 3,
		"category": "weapon",
		"requires": ["railgun"],
	},
	# ── X-02 专属：激光照射 ────────────────────────────────────
	{
		"id": "laser_cooldown",
		"name": "UPGRADE_LASER_COOLDOWN_NAME",
		"desc": "UPGRADE_LASER_COOLDOWN_DESC",
		"stat": "laser_cooldown",
		"value": 0.25,
		"max_stacks": 3,
		"category": "weapon",
		"requires": ["laser"],
	},
	{
		"id": "laser_range",
		"name": "UPGRADE_LASER_RANGE_NAME",
		"desc": "UPGRADE_LASER_RANGE_DESC",
		"stat": "laser_range",
		"value": 0.20,
		"max_stacks": 3,
		"category": "weapon",
		"requires": ["laser"],
	},
	{
		"id": "laser_heat",
		"name": "UPGRADE_LASER_HEAT_NAME",
		"desc": "UPGRADE_LASER_HEAT_DESC",
		"stat": "laser_heat",
		"value": 0.30,
		"max_stacks": 3,
		"category": "weapon",
		"requires": ["laser"],
	},
]

# ── 升级筛选 ─────────────────────────────────────────────

## 判断某个升级是否适用于指定主角
##   upgrade: UPGRADES 表中的一条
##   aircraft_id: PlayableAircraft.id（如 &"f16" / &"f14"）
##   p: 主角飞机当前的 AircraftParams（用于检测硬件存在性）
##
## 拒绝条件：
##   - upgrade.requires 中列出的硬件，主角缺失任意一项
##   - upgrade.exclusive_to 非空，且 aircraft_id 不在其中
static func is_upgrade_available_for(upgrade: Dictionary, aircraft_id: StringName, p: AircraftParams) -> bool:
	# ── 硬件要求 ──
	# 走 AircraftParams.has_equipment_of_kind：双查 equipment 数组 + 老字段（gun/missile/...）
	# 自动支持任意 equipment_kind（railgun / laser / cobra / herbst / ecm 未来扩展）
	var reqs: Variant = upgrade.get("requires", null)
	if reqs != null:
		for req in reqs:
			if p == null or not p.has_equipment_of_kind(str(req)):
				return false

	# ── 专属机型限制 ──
	var excl: Variant = upgrade.get("exclusive_to", null)
	if excl != null and excl.size() > 0:
		var matched := false
		for id_str in excl:
			if StringName(id_str) == aircraft_id:
				matched = true
				break
		if not matched:
			return false

	return true

# ── 经验曲线 ─────────────────────────────────────────────

## 基数 15（之前 20）：全局节奏提速 ~25%，配合 Adds 全额 XP，让玩家进 BOSS 战时能到 L16-18
static func xp_for_level(level: int) -> int:
	return int(15.0 * pow(level, 1.15))

## Adds 类（Tu-160/AH-64/CH-47）经验：单只 = 当前等级所需经验全额
## 设计意图（已撤销之前 /3 的削弱）：
##   - 轰炸机 / 直升机在事件波次整组出现，给足经验让玩家升级感强
##   - flock（3-4 架）全杀一次可升 3-4 级，显著推进等级曲线
const ADDS_XP_DIVISOR := 1
static func adds_xp_per_kill(level: int, _flock_size: int = 0) -> int:
	return int(ceil(float(xp_for_level(level)) / float(ADDS_XP_DIVISOR)))

# ── 刷怪参数 ─────────────────────────────────────────────

const BASE_SPAWN_INTERVAL := 8.0    ## 初始刷怪间隔（秒，保留作沙盒/无战区 fallback；生存模式走 TRAVEL_SPAWN_INTERVAL_*）
const MIN_SPAWN_INTERVAL := 3.0     ## 最小刷怪间隔（同上）
## 旅途刷怪：玩家在战区之间移动时的节奏。比战区驻守放宽，一趟路一波足够。
const TRAVEL_SPAWN_INTERVAL_BASE := 45.0   ## 玩家等级 1 时的旅途刷怪间隔（秒）
const TRAVEL_SPAWN_INTERVAL_MIN := 25.0    ## 玩家高等级时的下限
## 旅途刷怪方向扇形半角（弧度）。刷怪角度限制在玩家 heading ± 本值 = 前方约 140° 扇形。
const TRAVEL_SPAWN_FAN_HALF := PI * 70.0 / 180.0
const ENEMIES_PER_WAVE_BASE := 1    ## 每波基础敌人数
const ENEMIES_PER_WAVE_GROWTH := 0.3  ## 每级额外敌人数
const SPAWN_DISTANCE := 3200.0      ## 刷怪距离（像素）；需 > 最小 zoom 下的可视对角半径 + VIEW_SPAWN_MARGIN_PX（当前 ZOOM_MIN=0.4 下对角半径 ≈ 2750 px）
const MAX_ENEMIES_HARD := 40          ## 绝对上限
const MAX_ENEMIES_DEFAULT := 30       ## 默认上限
const MIN_ENEMIES_CAP := 8            ## 动态下限（至少允许这么多敌人）
const TARGET_FPS := 30                ## 目标最低帧率
## UAV 与 UCAV 是等权重的杂鱼 adds，1~UAV_RETIRE_LEVEL 级出现，之后不再刷
const UAV_RETIRE_LEVEL := 4  ## 玩家达到此等级后，UAV/UCAV 不再出现
const MIG_UNLOCK_LEVEL := 7         ## MiG 解锁等级
const MIG_CHANCE_PER_LEVEL := 0.08  ## 每超过解锁等级，MiG 出现概率增加
const MIG_CHANCE_MAX := 0.5         ## MiG 最大出现概率
const INTERCEPTOR_UNLOCK_LEVEL := 5  ## 截击机（J-7）解锁等级
const INTERCEPTOR_CHANCE_PER_LEVEL := 0.12  ## 每超过解锁等级，截击机出现概率增加
const INTERCEPTOR_CHANCE_MAX := 0.35 ## 截击机最大出现概率
const F86_UNLOCK_LEVEL := 2          ## F-86（Gladiator）解锁等级
const F86_CHANCE_PER_LEVEL := 0.14   ## 每超过解锁等级，F-86 出现概率增加
const F86_CHANCE_MAX := 0.45         ## F-86 最大出现概率
const MIG23_UNLOCK_LEVEL := 4        ## MiG-23（Gladiator，带导弹编队）解锁等级
const MIG23_CHANCE_PER_LEVEL := 0.10 ## 每超过解锁等级，MiG-23 出现概率增加
const MIG23_CHANCE_MAX := 0.35       ## MiG-23 最大出现概率
const F100_UNLOCK_LEVEL := 6         ## F-100（Lancer 编队，雷达弹）解锁等级
const F100_CHANCE_PER_LEVEL := 0.10  ## 每超过解锁等级，F-100 出现概率增加
const F100_CHANCE_MAX := 0.30        ## F-100 最大出现概率
const MIG31_UNLOCK_LEVEL := 9        ## MiG-31（最强 Lancer，单机）解锁等级
const MIG31_CHANCE_PER_LEVEL := 0.08 ## 每超过解锁等级，MiG-31 出现概率增加
const MIG31_CHANCE_MAX := 0.25       ## MiG-31 最大出现概率
const SU27_UNLOCK_LEVEL := 8         ## Su-27（主力威胁 + 眼镜蛇机动）解锁等级
const SU27_CHANCE_PER_LEVEL := 0.07  ## 每超过解锁等级，Su-27 出现概率增加
const SU27_CHANCE_MAX := 0.25        ## Su-27 最大出现概率
const A7_UNLOCK_LEVEL := 3           ## A-7（Lancer 亚音速攻击机，机炮+火箭弹）解锁等级
const A7_CHANCE_PER_LEVEL := 0.14    ## 每超过解锁等级，A-7 出现概率增加
const A7_CHANCE_MAX := 0.40          ## A-7 最大出现概率
const Q5_UNLOCK_LEVEL := 5           ## Q-5（Lancer 超音速攻击机，机炮+火箭弹）解锁等级
const Q5_CHANCE_PER_LEVEL := 0.10    ## 每超过解锁等级，Q-5 出现概率增加
const Q5_CHANCE_MAX := 0.30          ## Q-5 最大出现概率
const COMMANDER_UNLOCK_LEVEL := 4    ## 指挥 UAV 解锁等级
const COMMANDER_CHANCE_BASE := 0.04  ## 解锁时的基础出现概率（稀有首领，一个战区约一架）
const COMMANDER_CHANCE_PER_LEVEL := 0.015  ## 每超过解锁等级，指挥 UAV 出现概率增加
const COMMANDER_CHANCE_MAX := 0.08   ## 指挥 UAV 最大出现概率
const COMMANDER_SQUAD_MIN := 5       ## 指挥 UAV 自带僚机数量（固定 5 架，Sentinel 不会单独出现）
const COMMANDER_SQUAD_MAX := 5       ## 指挥 UAV 自带僚机数量（固定 5 架，Sentinel 不会单独出现）
const COMMANDER_MAX_SQUAD := 9       ## 指挥 UAV 分队总上限（含自己；实际招募限制在 CommanderAura.MAX_WINGMEN=8）
const XP_PER_KILL_COMMANDER := 50    ## 指挥 UAV 击杀经验

# ── Adds（杂兵）──
# Adds = 无反击、无威胁、纯经验奖励的单位；走独立刷新系统（族群 Flock），
# 不占用 Token 预算，也不受远距清理影响（它们沿固定航线穿越战场）。
# Adds（杂兵）类敌人不走随机刷新，由未来的事件系统触发 spawn。
# 以下常量只定义"单次波次生成什么样的阵型" — 不再有解锁等级/刷新间隔/首次延迟。

## Tu-160 白天鹅（横列 4 架）
## Adds 类经验改走 adds_xp_per_kill()（整组击杀恰好 +1 级），不再用固定值
const TU160_FLOCK_SIZE := 4          ## 每次波次的轰炸机数量
const TU160_FLIGHT_DISTANCE := 8000.0  ## Tu-160 从起点到终点的直线距离（像素）
const TU160_LATERAL_SPACING := 260.0 ## 编队成员之间的横向间距（像素）
const TU160_STAGGER_SPACING := 180.0 ## 前后错位距离（像素）

## AH-64 Apache（Adds 攻击直升机，4 架菱形层次编队）
const AH64_FLOCK_SIZE := 4           ## 4 架编队
const AH64_FLIGHT_DISTANCE := 6000.0 ## 直升机慢，航线短一些
const AH64_FORWARD_SPACING := 280.0  ## 前后层级间距（像素）
const AH64_LATERAL_SPACING := 260.0  ## 横向展宽间距（像素）

## CH-47 Chinook（Adds 重型运输机，纵阵 3 架）

## F-47 王牌狙击小队（BOSS，事件触发，4 架编队）
const XP_PER_KILL_F47 := 100       ## F-47 击杀经验（王牌级，4 架共 400 XP）
const F47_SQUAD_SIZE := 4           ## 编队成员数（固定 4 架）
const F47_STANDOFF_RADIUS_MIN := 1800.0  ## 被追时逃跑最小距离（像素）— 不飞太远
const F47_STANDOFF_RADIUS_MAX := 2500.0  ## 被追时逃跑最大距离（像素）
const F47_FLEE_DISTANCE := 2000.0   ## 被盯飞机的逃跑距离（像素）
const F47_INTRO_DURATION := 4.0     ## 登场通场表演时长（秒）
const F47_INTRO_PASS_DIST := 800.0  ## 通场时经过玩家前方的距离（像素）
const F47_CLOAK_CYCLE := 110.0      ## 隐形基础 CD（秒）
const F47_CLOAK_DURATION := 5.5     ## 隐形持续时间（秒）
const F47_CLOAK_FADE := 0.5         ## 隐形淡入/淡出时间（秒）
const F47_CLOAK_CYCLE_JITTER := 25.0 ## CD 到了随机 0~25s 内触发，玩家无法按表躲

## 地面单位
const XP_PER_KILL_GROUND := 25   ## SAM / AA 炮击毁经验（与 UAV 相当）
const CH47_FLOCK_SIZE := 3
const CH47_FLIGHT_DISTANCE := 5500.0 ## 更慢，航线更短
const CH47_COLUMN_SPACING := 320.0   ## Chinook 体型大，间距更大

# ── Token 烈度预算 ─────────────────────────────────────────
# Token 系统用于精细控制同屏战斗烈度：
# - 每种敌人消耗不同 Token 值（杂鱼 1~2，精英 4~6）
# - 全局 Token 上限随等级增长
# - 部分敌人设独立实例上限（即使预算够也不再刷）
# - 远距清理飞出战区的敌机，释放 Token

const TOKEN_BUDGET_BASE := 5           ## 1 级时的 Token 预算
const TOKEN_BUDGET_PER_LEVEL := 1.5    ## 每级 Token 预算增量
const TOKEN_BUDGET_MAX := 45           ## Token 预算绝对上限

## 每种敌人的 Token 消耗
## key 是 survivor_mode.gd::EnemyType 的 int 值
## UAV=0, UCAV=1, MIG=2, INTERCEPTOR=3, UAV_COMMANDER=4, F86=5, MIG31=6, MIG23=7, F100=8, SU27=9, A7=10, Q5=11, TU160=12, AH64=13, CH47=14, F47=15
const TOKEN_COST := {
	0: 1,   ## UAV        — 最便宜的杂鱼
	1: 2,   ## UCAV       — 导弹杂鱼
	2: 4,   ## MiG-29     — 主力威胁
	3: 5,   ## J-7        — Lancer 打带跑，单次冲锋威胁高
	4: 6,   ## Sentinel   — Schemer 带光环+buff 僚机（首领级稀有，必带 5 架 UAV 僚机）
	5: 3,   ## F-86       — Gladiator 缠斗
	6: 8,   ## MiG-31     — Lancer 顶级（速度 3200，雷达弹，单机出现）
	7: 4,   ## MiG-23     — Gladiator 综合型（导弹+机炮编队）
	8: 5,   ## F-100      — Lancer 编队型（雷达弹打带跑）
	9: 7,   ## Su-27      — 主力威胁 + 眼镜蛇机动（单机/双机出现）
	10: 3,  ## A-7        — Lancer 亚音速攻击机（机炮+火箭弹编队）
	11: 4,  ## Q-5        — Lancer 超音速攻击机（机炮+火箭弹编队）
	12: 0,  ## Tu-160     — Adds 杂兵（独立波次，不占 Token，不被远距清理）
	13: 0,  ## AH-64      — Adds 直升机（纵阵，独立波次）
	14: 0,  ## CH-47      — Adds 重型直升机（纵阵，独立波次）
	15: 10, ## F-47       — BOSS 王牌狙击小队（全敌人最高 Token，事件触发）
	16: 10, ## F-14 Poltergeist — BOSS（CSG Phase 2，事件触发）
	17: 7,  ## AF-03      — Schemer 电磁炮狙击手（中后期，事件触发）
	18: 2,  ## Aegis UAV  — 激光拦截器，跟随 Sentinel 出现
}

## 每种敌人的同时存在上限（-1 = 无限制）
## 即使 Token 够也不会超过此数；保证 schemer/lancer 稀有度
## 注意：J-7 后期会改走编队（LATE_GAME_LEVEL+），故不再限制实例数
const TOKEN_INSTANCE_CAP := {
	0: -1,  ## UAV
	1: -1,  ## UCAV
	2: -1,  ## MiG
	3: -1,  ## J-7 截击机（早期单机/后期编队，无硬上限）
	4: 1,   ## Sentinel 指挥机：唯一单位
	5: -1,  ## F-86
	6: 2,   ## MiG-31：最强 Lancer，单机稀有，一次最多 2 台
	7: -1,  ## MiG-23
	8: 3,   ## F-100 编队：一次最多 3 台维持稀有感
	9: 2,   ## Su-27：精英单机，一次最多 2 台
	10: -1, ## A-7：编队出现，无硬上限
	11: -1, ## Q-5：编队出现，无硬上限
	12: -1, ## Tu-160：Adds 族群波次，数量由独立系统控制
	13: -1, ## AH-64：Adds 族群波次
	14: -1, ## CH-47：Adds 族群波次
	15: 4,  ## F-47：BOSS 小队（固定 4 架，不多不少）
	16: 4,  ## F-14 Poltergeist BOSS 小队
	17: 1,  ## AF-03：单机出现（独特狙击体验）
	18: 2,  ## Aegis UAV：每只 Sentinel 带 2 架
}

## 远距清理
const FAR_CLEANUP_DISTANCE := 7000.0   ## 超过此像素距离的敌机被静默移除
const FAR_CLEANUP_INTERVAL := 4.0      ## 清理检查间隔（秒）

## 后期分水岭：达到此等级后，杂鱼/低级飞机统一以编队形式出现，单机精英才允许单架
## - UAV / UCAV / F-86 / J-7 等不再有"落单 1 架"的尾巴
## - J-7 截击机由单机出现改为 2-3 编队
## - MiG-31 / Sentinel 不受影响（设计上保留单机出场）
const LATE_GAME_LEVEL := 10

## 后期刷怪最低 Token 门槛：等级 >= LATE_GAME_LEVEL 后，
## 不再生成 Token 消耗低于此值的敌人（UAV=1, UCAV=2 被淘汰）
const LATE_GAME_MIN_TOKEN := 3

## 导弹一击必杀：敌机 HP 上限（低于最弱玩家导弹 80 伤害），Sentinel 除外
const ENEMY_HP_MISSILE_CAP := 75.0

## P4：所有空战飞机走 TacticalPlanner（与玩家相同的决策路径）
## 2026-04-26 默认翻 true，迁移已覆盖：常规战机 9 种 + BOSS 中队 2 种 + 玩家僚机
## 仍走旧路径：Adds（Tu-160/AH-64/CH-47, simple_ai）/ Schemer（Sentinel, enable_combat=false）
## 这些类型不进 BFM 决策树，planner 对它们无意义
## 沙盒模式（main.gd 入口）不读此开关，敌机继续旧 BFMTactics 路径以保留沙盒兼容
const ENABLE_PLANNER_FOR_REGULAR_AI := true

# ── 战区敌情曲线 ─────────────────────────────────────────
# 设计原则（2026-04-21 修订，详见 docs/changelogs/2026-04-21-zone-level-curve.md）：
#   1. 玩家等级决定战区敌人池（不是单纯 Token），让开局能撞到 UAV/UCAV
#   2. 每种敌人有钟形权重：preview(解锁前 1 级) / peak(首发+2) / decay(衰减) / retire(淡出)
#   3. "能打就用" — 不硬塞预算，预算不够就少刷，宁缺毋滥
#   4. 护卫优先以"中队"整体出现 — 见 zone_mission._spawn_zone_defenders
#
# base_weight = 池子里的基线分量；level_factor 按 unlock/peak/retire 计算
# unlock:  低于此等级不出现（level_factor=0）
# preview: unlock-1 等级开始出现（level_factor=0.3，让玩家"预感"）
# peak:    最高权重 1.0 的等级
# retire:  >0 时到该等级权重开始衰减；-1 = 不淘汰
const ZONE_ENEMY_TABLE: Array[Dictionary] = [
	## type 对应 SurvivorSpawner.EnemyType 的 int 值
	{"type": 0,  "unlock": 1, "peak": 1,  "retire": 5,  "base_weight": 1.6},  ## UAV        杂鱼（早期主力）
	{"type": 1,  "unlock": 1, "peak": 2,  "retire": 6,  "base_weight": 1.4},  ## UCAV       带弹杂鱼
	{"type": 5,  "unlock": 2, "peak": 3,  "retire": 9,  "base_weight": 1.2},  ## F-86       入门 Gladiator
	{"type": 10, "unlock": 3, "peak": 4,  "retire": 10, "base_weight": 1.0},  ## A-7        亚音速攻击机
	{"type": 7,  "unlock": 4, "peak": 5,  "retire": -1, "base_weight": 1.0},  ## MiG-23     综合 Gladiator
	{"type": 3,  "unlock": 5, "peak": 6,  "retire": -1, "base_weight": 0.9},  ## J-7        Lancer 打带跑
	{"type": 11, "unlock": 5, "peak": 6,  "retire": -1, "base_weight": 0.9},  ## Q-5        超音速攻击机
	{"type": 8,  "unlock": 6, "peak": 7,  "retire": -1, "base_weight": 0.8},  ## F-100      Lancer 编队
	{"type": 2,  "unlock": 7, "peak": 8,  "retire": -1, "base_weight": 0.9},  ## MiG-29     主力威胁
	{"type": 9,  "unlock": 8, "peak": 10, "retire": -1, "base_weight": 0.6},  ## Su-27      精英+眼镜蛇
	{"type": 6,  "unlock": 9, "peak": 11, "retire": -1, "base_weight": 0.4},  ## MiG-31     顶级 Lancer
]

## 等级钟形权重：
##   level < unlock-1         → 0
##   unlock-1 ≤ level < unlock → 0.3（preview，极低概率"预告"）
##   unlock ≤ level ≤ peak    → 从 0.6 线性爬升到 1.0
##   peak < level < retire    → 从 1.0 线性衰减到 0.4
##   retire ≤ level           → 从 0.4 按半衰减（每 2 级 ×0.5），2 级后完全淡出
static func _zone_pool_level_factor(level: int, unlock: int, peak: int, retire: int) -> float:
	if level < unlock - 1:
		return 0.0
	if level < unlock:
		return 0.3
	if level <= peak:
		var span: float = float(maxi(peak - unlock, 1))
		return 0.6 + 0.4 * float(level - unlock) / span
	# level > peak
	if retire <= 0:
		# 无 retire：peak 后缓慢衰减到 0.4 并持平（老敌人不会完全消失）
		var decay: float = maxf(0.4, 1.0 - 0.1 * float(level - peak))
		return decay
	if level < retire:
		var span2: float = float(maxi(retire - peak, 1))
		return 1.0 - 0.6 * float(level - peak) / span2
	# level ≥ retire：2 级内完全淡出
	var over: int = level - retire
	if over >= 2:
		return 0.0
	return 0.4 * pow(0.5, float(over))

## 战区敌人池（按玩家等级加权）
##   player_level:     当前玩家等级
##   exclude_sentinel: elite 任务的 Sentinel 作为 TGT 已独占，守卫池排除 UAV_COMMANDER
##   squad_friendly:   true 时排除强制单机的机型（MiG-31），供中队批量使用
## 返回 [{type:int, cost:int, weight:float}, ...]，weight>0 的项
static func get_zone_enemy_pool(player_level: int, exclude_sentinel: bool = true,
		squad_friendly: bool = false) -> Array:
	var out: Array = []
	for row_any in ZONE_ENEMY_TABLE:
		var row: Dictionary = row_any
		var etype: int = int(row["type"])
		if exclude_sentinel and etype == 4:
			continue
		## 中队只收允许编队的机型（MiG-31 单机上限 2，强制排除；Sentinel 走独立 elite 流程）
		if squad_friendly and etype == 6:
			continue
		var f: float = _zone_pool_level_factor(player_level,
				int(row["unlock"]), int(row["peak"]), int(row["retire"]))
		if f <= 0.0:
			continue
		var cost: int = int(TOKEN_COST.get(etype, 99))
		out.append({
			"type": etype,
			"cost": cost,
			"weight": float(row["base_weight"]) * f,
		})
	return out

## 战区角色虚拟等级 — 用于选敌人池子。
## role "tgt" 永远比 "garrison" 高 ≥ 2 级，保证 TGT 比护卫硬。
## floor 机制的目的：低等级玩家（Lv 1-3）打 ★★/★★★ 战区时，护卫池不再
## 被 UAV/UCAV 淹没 —— 因为 UAV retire=5、UCAV retire=6，把虚拟等级顶到
## floor 以上就让它们进入衰减/淡出区间，自然腾出空间给中级敌人。
##
## | 星级 | TGT boost / floor | Garrison boost / floor |
## |------|-------------------|------------------------|
## | ★    | +0 / 3            | +0 / 3                 |
## | ★★   | +3 / 6            | +2 / 4                 |
## | ★★★  | +5 / 8            | +3 / 6                 |
##
## 例：Lv 1 玩家
##   ★   TGT/Gar = 3    → F-86 / UAV / UCAV 混合池
##   ★★  TGT = 6 / Gar = 4 → TGT 是 J-7 / Q-5 级；护卫 A-7 / F-86 / MiG-23，UAV 稀少
##   ★★★ TGT = 8 / Gar = 6 → TGT 可到 F-100 / MiG-29；护卫 J-7 / Q-5 / A-7 / MiG-23
static func zone_virtual_level(difficulty: int, player_level: int, role: String = "garrison") -> int:
	var boost: int
	var floor_lv: int
	match difficulty:
		3:
			if role == "tgt":
				boost = 5
				floor_lv = 8
			else:
				boost = 3
				floor_lv = 6
		2:
			if role == "tgt":
				boost = 3
				floor_lv = 6
			else:
				boost = 2
				floor_lv = 4
		_:
			boost = 0
			floor_lv = 3
	return maxi(player_level + boost, floor_lv)

## 向后兼容：TGT 虚拟等级的薄包装
static func tgt_level_for_zone(difficulty: int, player_level: int) -> int:
	return zone_virtual_level(difficulty, player_level, "tgt")

## 按战区星级决定空战中队规模
static func air_squadron_count_for_difficulty(difficulty: int) -> int:
	match difficulty:
		3: return 5
		2: return 4
		_: return 3

## 地面任务 TGT 数量（仅按星级缩放，单位 HP 不变）
## 返回 {"sam_count":int, "aa_count":int}
static func ground_tgt_scale(difficulty: int, _player_level: int) -> Dictionary:
	var sam_count: int
	var aa_count: int
	match difficulty:
		3:
			sam_count = 5
			aa_count = 5
		2:
			sam_count = 3
			aa_count = 3
		_:
			sam_count = 2
			aa_count = 2
	return {
		"sam_count": sam_count,
		"aa_count": aa_count,
	}

## 战区驻守预算：基础 + 等级线性加成
## 基础按难度（1-3 星）：8 / 15 / 30
## 每级 +8%（10 级时 ≈ ×1.72），让高等级战区实打实变重
const ZONE_DEFENDER_BASE_BUDGET := {1: 8, 2: 15, 3: 30}
const ZONE_DEFENDER_BUDGET_PER_LEVEL := 0.08
static func zone_defender_budget(difficulty: int, player_level: int) -> int:
	var base: int = int(ZONE_DEFENDER_BASE_BUDGET.get(difficulty, 8))
	var scale: float = 1.0 + ZONE_DEFENDER_BUDGET_PER_LEVEL * float(maxi(player_level - 1, 0))
	return int(round(float(base) * scale))

## 从等级加权池中抽一个负担得起的敌人（权重随机）
## 超出 unlock_level + 2 的敌人返回 {} —— 防止给低级玩家塞超纲威胁
## 返回 {type:int, cost:int} 或 {}
static func pick_zone_enemy(pool: Array, budget: int, player_level: int) -> Dictionary:
	var candidates: Array = []
	var total_weight := 0.0
	for c_any in pool:
		var c: Dictionary = c_any
		var cost: int = int(c["cost"])
		if cost > budget:
			continue
		## 寻找该敌人的 unlock，若 player_level + 2 < unlock 则跳过（等级钟形已处理，但硬门槛更保险）
		candidates.append(c)
		total_weight += float(c["weight"])
	if candidates.is_empty() or total_weight <= 0.0:
		return {}
	var r := randf() * total_weight
	var acc := 0.0
	for c_any in candidates:
		var c: Dictionary = c_any
		acc += float(c["weight"])
		if r <= acc:
			return {"type": int(c["type"]), "cost": int(c["cost"])}
	return {"type": int(candidates[-1]["type"]), "cost": int(candidates[-1]["cost"])}

# ── 敌人缩放 ─────────────────────────────────────────────

## MiG 敌人的属性缩放
static func enemy_scale_for_level(level: int) -> Dictionary:
	return {
		"hp_mult": 1.0 + (level - 1) * 0.15,
		"missile_add": int(level / 4),
		"gun_damage_mult": 1.0 + (level - 1) * 0.08,
	}

## UAV 敌人的属性缩放（较温和）
static func uav_scale_for_level(level: int) -> Dictionary:
	return {
		"hp_mult": 1.0 + (level - 1) * 0.08,
		"missile_add": 0,
		"gun_damage_mult": 1.0 + (level - 1) * 0.05,
	}

## 指挥 UAV 的属性缩放（仅 HP 缩放，无武装）
static func commander_scale_for_level(level: int) -> Dictionary:
	return {
		"hp_mult": 1.0 + (level - 1) * 0.10,
		"missile_add": 0,
		"gun_damage_mult": 1.0,
	}
