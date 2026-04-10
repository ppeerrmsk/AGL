class_name SurvivorData
extends RefCounted

## 生存模式静态数据：敌人波次、升级定义、经验曲线

# ── 升级定义 ─────────────────────────────────────────────
# 每种升级直接修改 Aircraft 的 params（AircraftParams / GunParams / MissileParams）
# category: "combat" = 战斗轴, "survival" = 生存轴
# evolved: true = 进化技能，不出现在随机池中，由基础技能满级自动触发
# evolves_to: "xxx" = 满级后自动进化为指定技能

const UPGRADES: Array[Dictionary] = [
	# ── 生存轴 ──
	{
		"id": "hp_up",
		"name": "装甲强化",
		"desc": "最大HP +30，机炮闪避 +8%",
		"stat": "max_hp",
		"value": 30.0,
		"max_stacks": 5,
		"category": "survival",
	},
	{
		"id": "speed_up",
		"name": "引擎强化",
		"desc": "最大速度/巡航速度 +18%",
		"stat": "speed",
		"value": 0.18,
		"max_stacks": 4,
		"category": "survival",
	},
	{
		"id": "maneuver_up",
		"name": "飞控升级",
		"desc": "滚转速率 +25%，持续G +1.0",
		"stat": "maneuver",
		"value": 0.25,
		"max_stacks": 3,
		"category": "survival",
	},
	{
		"id": "flare_cooldown",
		"name": "红外对抗优化",
		"desc": "热诱弹冷却时间 -20%",
		"stat": "flare_cooldown",
		"value": 0.20,
		"max_stacks": 3,
		"category": "survival",
		"evolves_to": "flare_shield",
	},
	{
		"id": "flare_shield",
		"name": "★ 电子对抗套件",
		"desc": "进化！释放热诱弹时解除所有锁定，免疫锁定3秒",
		"stat": "flare_shield",
		"value": 3.0,
		"max_stacks": 1,
		"category": "survival",
		"evolved": true,
	},
	{
		"id": "pilot_stamina",
		"name": "体能强化",
		"desc": "飞行员耐力上限×2，恢复速率×2",
		"stat": "pilot_stamina",
		"value": 1.0,
		"max_stacks": 3,
		"category": "survival",
	},
	{
		"id": "kill_heal",
		"name": "战场急救",
		"desc": "击杀敌机时回复10 HP",
		"stat": "kill_heal",
		"value": 10.0,
		"max_stacks": 3,
		"category": "survival",
	},
	# ── 战斗轴 ──
	{
		"id": "missile_count",
		"name": "导弹挂架扩展",
		"desc": "导弹携带量 +1",
		"stat": "missile_count",
		"value": 1,
		"max_stacks": 4,
		"category": "combat",
	},
	{
		"id": "missile_tracking",
		"name": "制导升级",
		"desc": "导弹过载 +30%，导引常数 +0.5",
		"stat": "missile_tracking",
		"value": 0.30,
		"max_stacks": 4,
		"category": "combat",
		"evolves_to": "missile_bounce",
	},
	{
		"id": "missile_bounce",
		"name": "★ 连锁弹头",
		"desc": "进化！导弹命中后弹跳至最近的另一个敌机",
		"stat": "missile_bounce",
		"value": 1,
		"max_stacks": 1,
		"category": "combat",
		"evolved": true,
	},
	{
		"id": "missile_reload",
		"name": "快速挂载",
		"desc": "导弹装填时间 -15%",
		"stat": "missile_reload",
		"value": 0.15,
		"max_stacks": 3,
		"category": "combat",
	},
	{
		"id": "multi_lock",
		"name": "多目标追踪",
		"desc": "同时锁定并发射目标数 +1",
		"stat": "multi_lock",
		"value": 1,
		"max_stacks": 2,
		"category": "combat",
	},
	{
		"id": "gun_damage",
		"name": "穿甲弹药",
		"desc": "机炮伤害 +20%",
		"stat": "gun_damage",
		"value": 0.20,
		"max_stacks": 5,
		"category": "combat",
		"evolves_to": "gun_multishot",
	},
	{
		"id": "gun_multishot",
		"name": "★ 多管齐射",
		"desc": "进化！同时射出三道机炮（前方+左右15°）",
		"stat": "gun_multishot",
		"value": 2,
		"max_stacks": 1,
		"category": "combat",
		"evolved": true,
	},
	{
		"id": "gun_ammo",
		"name": "弹药扩容",
		"desc": "机炮弹药上限 +100",
		"stat": "gun_ammo",
		"value": 100,
		"max_stacks": 5,
		"category": "combat",
	},
	{
		"id": "gun_regen",
		"name": "自动装弹机",
		"desc": "机炮弹药恢复速度 +40%",
		"stat": "gun_regen",
		"value": 0.40,
		"max_stacks": 4,
		"category": "combat",
	},
	{
		"id": "gun_firerate",
		"name": "射速强化",
		"desc": "机炮射速 +25%",
		"stat": "gun_firerate",
		"value": 0.25,
		"max_stacks": 4,
		"category": "combat",
	},
	{
		"id": "radar_range",
		"name": "雷达升级",
		"desc": "雷达探测距离 +20%",
		"stat": "radar_range",
		"value": 0.20,
		"max_stacks": 3,
		"category": "combat",
	},
	{
		"id": "lock_time",
		"name": "火控优化",
		"desc": "锁定时间 -0.5秒",
		"stat": "lock_time",
		"value": -0.5,
		"max_stacks": 3,
		"category": "combat",
	},
	{
		"id": "dogfight",
		"name": "格斗大师",
		"desc": "失速速度 -12%，减速 +30%，低速机动增强",
		"stat": "dogfight",
		"value": 1,
		"max_stacks": 3,
		"category": "combat",
	},
]

# ── 经验曲线 ─────────────────────────────────────────────

static func xp_for_level(level: int) -> int:
	return int(20.0 * pow(level, 1.15))

# ── 刷怪参数 ─────────────────────────────────────────────

const BASE_SPAWN_INTERVAL := 8.0    ## 初始刷怪间隔（秒）
const MIN_SPAWN_INTERVAL := 3.0     ## 最小刷怪间隔
const ENEMIES_PER_WAVE_BASE := 1    ## 每波基础敌人数
const ENEMIES_PER_WAVE_GROWTH := 0.3  ## 每级额外敌人数
const SPAWN_DISTANCE := 3000.0      ## 刷怪距离（像素）
const MAX_ENEMIES_HARD := 40          ## 绝对上限
const MAX_ENEMIES_DEFAULT := 30       ## 默认上限
const MIN_ENEMIES_CAP := 8            ## 动态下限（至少允许这么多敌人）
const TARGET_FPS := 30                ## 目标最低帧率
const UCAV_UNLOCK_LEVEL := 3        ## 导弹无人机解锁等级
const UCAV_CHANCE_PER_LEVEL := 0.10 ## 每超过解锁等级，UCAV 出现概率增加
const UCAV_CHANCE_MAX := 0.4        ## UCAV 最大出现概率
const MIG_UNLOCK_LEVEL := 7         ## MiG 解锁等级
const MIG_CHANCE_PER_LEVEL := 0.08  ## 每超过解锁等级，MiG 出现概率增加
const MIG_CHANCE_MAX := 0.5         ## MiG 最大出现概率
const INTERCEPTOR_UNLOCK_LEVEL := 5  ## 截击机（J-7）解锁等级
const INTERCEPTOR_CHANCE_PER_LEVEL := 0.12  ## 每超过解锁等级，截击机出现概率增加
const INTERCEPTOR_CHANCE_MAX := 0.35 ## 截击机最大出现概率
const COMMANDER_UNLOCK_LEVEL := 4    ## 指挥 UAV 解锁等级
const COMMANDER_CHANCE_BASE := 0.12  ## 解锁时的基础出现概率
const COMMANDER_CHANCE_PER_LEVEL := 0.06  ## 每超过解锁等级，指挥 UAV 出现概率增加
const COMMANDER_CHANCE_MAX := 0.25   ## 指挥 UAV 最大出现概率
const COMMANDER_SQUAD_MIN := 2       ## 指挥 UAV 自带僚机最少数
const COMMANDER_SQUAD_MAX := 3       ## 指挥 UAV 自带僚机最多数
const COMMANDER_MAX_SQUAD := 6       ## 指挥 UAV 分队招募上限（含自己）
const XP_PER_KILL_COMMANDER := 50    ## 指挥 UAV 击杀经验

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
