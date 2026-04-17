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
		"category": "survival",
		"accel_ratio": 0.5,        ## 加速提升 = value × 此值
	},
	{
		"id": "maneuver_up",
		"name": "UPGRADE_MANEUVER_UP_NAME",
		"desc": "UPGRADE_MANEUVER_UP_DESC",
		"stat": "maneuver",
		"value": 0.25,
		"max_stacks": 3,
		"category": "survival",
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
		"category": "survival",
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
		"category": "survival",
		"evolved": true,
		"requires": ["flare"],
		"bonus_flares": 2,         ## 额外赠送热诱弹数
	},
	{
		"id": "pilot_stamina",
		"name": "UPGRADE_PILOT_STAMINA_NAME",
		"desc": "UPGRADE_PILOT_STAMINA_DESC",
		"stat": "pilot_stamina",
		"value": 1.0,
		"max_stacks": 3,
		"category": "survival",
		"stamina_mult": 2.0,       ## 耐力上限倍率
		"recovery_mult": 2.0,      ## 恢复速率倍率
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
		"category": "combat",
		"requires": ["missile"],
	},
	{
		"id": "missile_tracking",
		"name": "UPGRADE_MISSILE_TRACKING_NAME",
		"desc": "UPGRADE_MISSILE_TRACKING_DESC",
		"stat": "missile_tracking",
		"value": 0.30,
		"max_stacks": 4,
		"category": "combat",
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
		"category": "combat",
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
		"category": "combat",
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
		"category": "combat",
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
		"category": "combat",
		"requires": ["missile"],
	},
	{
		"id": "gun_damage",
		"name": "UPGRADE_GUN_DAMAGE_NAME",
		"desc": "UPGRADE_GUN_DAMAGE_DESC",
		"stat": "gun_damage",
		"value": 0.20,
		"max_stacks": 5,
		"category": "combat",
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
		"category": "combat",
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
		"category": "combat",
		"requires": ["gun"],
	},
	{
		"id": "gun_reload",
		"name": "UPGRADE_GUN_RELOAD_NAME",
		"desc": "UPGRADE_GUN_RELOAD_DESC",
		"stat": "gun_reload",
		"value": 0.15,
		"max_stacks": 3,
		"category": "combat",
		"requires": ["gun"],
	},
	{
		"id": "gun_firerate",
		"name": "UPGRADE_GUN_FIRERATE_NAME",
		"desc": "UPGRADE_GUN_FIRERATE_DESC",
		"stat": "gun_firerate",
		"value": 0.25,
		"max_stacks": 4,
		"category": "combat",
		"requires": ["gun"],
	},
	{
		"id": "gun_range",
		"name": "UPGRADE_GUN_RANGE_NAME",
		"desc": "UPGRADE_GUN_RANGE_DESC",
		"stat": "gun_range",
		"value": 0.20,
		"max_stacks": 4,
		"category": "combat",
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
		"category": "combat",
		"evolved": true,
		"requires": ["gun"],
	},
	{
		"id": "radar_range",
		"name": "UPGRADE_RADAR_RANGE_NAME",
		"desc": "UPGRADE_RADAR_RANGE_DESC",
		"stat": "radar_range",
		"value": 0.20,
		"max_stacks": 3,
		"category": "combat",
	},
	{
		"id": "lock_time",
		"name": "UPGRADE_LOCK_TIME_NAME",
		"desc": "UPGRADE_LOCK_TIME_DESC",
		"stat": "lock_time",
		"value": -0.5,
		"max_stacks": 3,
		"category": "combat",
		"min_lock_time": 0.5,      ## 锁定时间不低于此值（秒）
	},
	{
		"id": "dogfight",
		"name": "UPGRADE_DOGFIGHT_NAME",
		"desc": "UPGRADE_DOGFIGHT_DESC",
		"stat": "dogfight",
		"value": 1,
		"max_stacks": 3,
		"category": "combat",
		"stall_speed_mult": 0.88,           ## -12% 失速速度
		"decel_mult": 1.3,                  ## +30% 减速
		"g_drag_mult": 1.2,                 ## +20% G 力阻力
		"overshoot_speed_margin_mult": 0.97, ## 更精确速度匹配
		"turn_slow_speed_mult": 0.9,        ## 大角度减速更多
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

## Adds 类（Tu-160/AH-64/CH-47）经验：单只 = 当前等级所需经验的 1/3（向上取整）
## 设计意图：
##   - 整组（3 只以上）击杀 → 保证至少 +1 级（"轰炸机奖励"）
##   - 进度接近升级线时，打一只也可能触发升级（让玩家感觉自然）
##   - flock 大小不影响单只奖励（与组大小解耦，简化设计）
const ADDS_XP_DIVISOR := 3
static func adds_xp_per_kill(level: int, _flock_size: int = 0) -> int:
	return int(ceil(float(xp_for_level(level)) / float(ADDS_XP_DIVISOR)))

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
const F47_CLOAK_CYCLE := 95.0       ## 隐形周期（秒）
const F47_CLOAK_DURATION := 5.5     ## 隐形持续时间（秒）
const F47_CLOAK_FADE := 0.5         ## 隐形淡入/淡出时间（秒）

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
