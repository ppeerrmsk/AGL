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
		"requires": ["flare"],
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
		"requires": ["flare"],
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
		"requires": ["missile"],
	},
	{
		"id": "missile_tracking",
		"name": "制导升级",
		"desc": "导弹过载 +30%，导引常数 +0.5",
		"stat": "missile_tracking",
		"value": 0.30,
		"max_stacks": 4,
		"category": "combat",
		"evolves_to": "proximity_fuze",
		"requires": ["missile"],
	},
	{
		"id": "proximity_fuze",
		"name": "★ 近炸引信",
		"desc": "进化！导弹接近敌机时自动引爆，产生 AOE 伤害区域",
		"stat": "proximity_fuze",
		"value": 1,
		"max_stacks": 1,
		"category": "combat",
		"evolved": true,
		"requires": ["missile"],
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
		"requires": ["missile"],
	},
	{
		"id": "missile_reload",
		"name": "快速挂载",
		"desc": "导弹装填时间 -15%",
		"stat": "missile_reload",
		"value": 0.15,
		"max_stacks": 3,
		"category": "combat",
		"evolves_to": "missile_bounce",
		"requires": ["missile"],
	},
	{
		"id": "multi_lock",
		"name": "多目标追踪",
		"desc": "自动对所有锁定目标同时发射导弹",
		"stat": "multi_lock",
		"value": 1,
		"max_stacks": 1,
		"category": "combat",
		"requires": ["missile"],
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
		"requires": ["gun"],
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
		"requires": ["gun"],
	},
	{
		"id": "gun_ammo",
		"name": "弹药扩容",
		"desc": "机炮弹药上限 +100",
		"stat": "gun_ammo",
		"value": 100,
		"max_stacks": 5,
		"category": "combat",
		"requires": ["gun"],
	},
	{
		"id": "gun_reload",
		"name": "快速装弹机",
		"desc": "机炮装填时间 -15%",
		"stat": "gun_reload",
		"value": 0.15,
		"max_stacks": 3,
		"category": "combat",
		"requires": ["gun"],
	},
	{
		"id": "gun_firerate",
		"name": "射速强化",
		"desc": "机炮射速 +25%",
		"stat": "gun_firerate",
		"value": 0.25,
		"max_stacks": 4,
		"category": "combat",
		"requires": ["gun"],
	},
	{
		"id": "gun_range",
		"name": "延伸弹道",
		"desc": "机炮有效射程 +20%",
		"stat": "gun_range",
		"value": 0.20,
		"max_stacks": 4,
		"category": "combat",
		"evolves_to": "gun_ciws",
		"requires": ["gun"],
	},
	{
		"id": "gun_ciws",
		"name": "★ 近防炮",
		"desc": "进化！机炮自动拦截正面来袭导弹",
		"stat": "gun_ciws",
		"value": 1,
		"max_stacks": 1,
		"category": "combat",
		"evolved": true,
		"requires": ["gun"],
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
	var reqs: Variant = upgrade.get("requires", null)
	if reqs != null:
		for req in reqs:
			match str(req):
				"gun":
					if p == null or p.gun == null:
						return false
				"missile":
					if p == null or p.missile == null:
						return false
				"flare":
					if p == null or p.flare == null:
						return false
				"rocket":
					if p == null or p.rocket == null:
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
## UAV 与 UCAV 是等权重的杂鱼 adds，从 1 级一起出现，无解锁门槛/概率曲线
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
const COMMANDER_CHANCE_BASE := 0.12  ## 解锁时的基础出现概率
const COMMANDER_CHANCE_PER_LEVEL := 0.06  ## 每超过解锁等级，指挥 UAV 出现概率增加
const COMMANDER_CHANCE_MAX := 0.25   ## 指挥 UAV 最大出现概率
const COMMANDER_SQUAD_MIN := 2       ## 指挥 UAV 自带僚机最少数
const COMMANDER_SQUAD_MAX := 3       ## 指挥 UAV 自带僚机最多数
const COMMANDER_MAX_SQUAD := 9       ## 指挥 UAV 分队总上限（含自己；实际招募限制在 CommanderAura.MAX_WINGMEN=8）
const XP_PER_KILL_COMMANDER := 50    ## 指挥 UAV 击杀经验

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
## UAV=0, UCAV=1, MIG=2, INTERCEPTOR=3, UAV_COMMANDER=4, F86=5, MIG31=6, MIG23=7, F100=8, SU27=9, A7=10, Q5=11
const TOKEN_COST := {
	0: 1,   ## UAV        — 最便宜的杂鱼
	1: 2,   ## UCAV       — 导弹杂鱼
	2: 4,   ## MiG-29     — 主力威胁
	3: 5,   ## J-7        — Lancer 打带跑，单次冲锋威胁高
	4: 6,   ## Sentinel   — Schemer 带光环+buff 僚机
	5: 3,   ## F-86       — Gladiator 缠斗
	6: 8,   ## MiG-31     — Lancer 顶级（速度 3200，雷达弹，单机出现）
	7: 4,   ## MiG-23     — Gladiator 综合型（导弹+机炮编队）
	8: 5,   ## F-100      — Lancer 编队型（雷达弹打带跑）
	9: 7,   ## Su-27      — 主力威胁 + 眼镜蛇机动（单机/双机出现）
	10: 3,  ## A-7        — Lancer 亚音速攻击机（机炮+火箭弹编队）
	11: 4,  ## Q-5        — Lancer 超音速攻击机（机炮+火箭弹编队）
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
