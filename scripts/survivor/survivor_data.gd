class_name SurvivorData
extends RefCounted

## 生存模式静态数据：敌人波次、升级定义、经验曲线

# ── 升级定义 ─────────────────────────────────────────────
# 每种升级直接修改 Aircraft 的 params（AircraftParams / GunParams / MissileParams）
# apply_func: 在 survivor_player.gd 中通过 stat 字段匹配执行

const UPGRADES: Array[Dictionary] = [
	{
		"id": "hp_up",
		"name": "装甲强化",
		"desc": "最大HP +30",
		"stat": "max_hp",
		"value": 30.0,
		"max_stacks": 5,
	},
	{
		"id": "missile_count",
		"name": "导弹挂架扩展",
		"desc": "导弹携带量 +1",
		"stat": "missile_count",
		"value": 1,
		"max_stacks": 4,
	},
	{
		"id": "missile_damage",
		"name": "战斗部改良",
		"desc": "导弹伤害 +25%",
		"stat": "missile_damage",
		"value": 0.25,
		"max_stacks": 4,
	},
	{
		"id": "gun_damage",
		"name": "穿甲弹药",
		"desc": "机炮伤害 +20%",
		"stat": "gun_damage",
		"value": 0.20,
		"max_stacks": 5,
	},
	{
		"id": "gun_ammo",
		"name": "弹药扩容",
		"desc": "机炮弹药 +200",
		"stat": "gun_ammo",
		"value": 200,
		"max_stacks": 3,
	},
	{
		"id": "radar_range",
		"name": "雷达升级",
		"desc": "雷达探测距离 +20%",
		"stat": "radar_range",
		"value": 0.20,
		"max_stacks": 3,
	},
	{
		"id": "lock_time",
		"name": "火控优化",
		"desc": "锁定时间 -0.5秒",
		"stat": "lock_time",
		"value": -0.5,
		"max_stacks": 3,
	},
	{
		"id": "speed_up",
		"name": "引擎强化",
		"desc": "最大速度/巡航速度 +10%",
		"stat": "speed",
		"value": 0.10,
		"max_stacks": 4,
	},
	{
		"id": "maneuver_up",
		"name": "飞控升级",
		"desc": "滚转速率 +15%，持续G +0.5",
		"stat": "maneuver",
		"value": 0.15,
		"max_stacks": 3,
	},
]

# ── 经验曲线 ─────────────────────────────────────────────

static func xp_for_level(level: int) -> int:
	return int(30.0 * pow(level, 1.4))

# ── 刷怪参数 ─────────────────────────────────────────────

const BASE_SPAWN_INTERVAL := 8.0    ## 初始刷怪间隔（秒）- 真实战斗机需要更大间隔
const MIN_SPAWN_INTERVAL := 3.0     ## 最小刷怪间隔
const ENEMIES_PER_WAVE_BASE := 1    ## 每波基础敌人数
const ENEMIES_PER_WAVE_GROWTH := 0.3  ## 每级额外敌人数
const SPAWN_DISTANCE := 3000.0      ## 刷怪距离（像素，较远以配合雷达探测）

# ── 敌人缩放 ─────────────────────────────────────────────
# 敌人使用 enemy_fighter.tres (MiG-29) 作为基础
# 随等级提升，修改复制的 params：HP、导弹数量

## 返回敌人 params 的缩放系数
static func enemy_scale_for_level(level: int) -> Dictionary:
	return {
		"hp_mult": 1.0 + (level - 1) * 0.15,           # HP 随等级增长
		"missile_add": int(level / 4),                   # 每4级多1枚导弹
		"gun_damage_mult": 1.0 + (level - 1) * 0.08,   # 机炮伤害微增
	}
