class_name SurvivorData
extends RefCounted

## 生存模式静态数据：敌人波次、升级定义、经验曲线

# ── 性能开关（VLS / CSG BOSS 战导弹优化，详见 docs/changelogs/2026-04-29-missile-perf.md）
## 让 MissileManager 每帧建一份 (target / source-lock / cloud) 共享快照，
## 同源同目标的群弹（尤其 VLS 齐射 8~13 枚）共用查询结果，减少冗余 I/O
const ENABLE_MISSILE_FRAME_SNAPSHOT: bool = true
## VLS 齐射弹 phase 0(垂直爬升) / phase 1(过渡转向) 是确定性弹道 → 20Hz tick 即可
## phase 2 (TERMINAL) 立刻恢复 60Hz PN，不影响末端制导精度
const ENABLE_VLS_LOW_RATE_TICK: bool = true
## BulletManager 帧级共享缓存：CSG BOSS 战 12 CIWS × ~22 子弹/CIWS 在飞 → 减子弹 × 单位的
## 子节点遍历（get_maneuver / get_herbst）开销 + CIWS 子弹查导弹时只查共享列表
const ENABLE_BULLET_FRAME_CACHE: bool = true

# ── §5 稀有度系统 ─────────────────────────────────────────
## 5 档稀有度（粗调初版，后续按手感调）：
## STABLE        — 纯数值轻微提升（+5% 转弯率 / +1 max_hp 类）
## ADVANCED      — 数值显著提升 + 简单触发
## EXPERIMENTAL  — 解锁一个新战术维度（眼镜蛇 / 对头闪避 / 云中超载）
## CLASSIFIED    — 跨系统强联动（对头大范围恐惧 / 云中武器 cd 翻倍）
## NEXT_GEN      — 改变战斗节奏 / 颠覆性（导弹齐射全打 / evasion 隐身）
enum Rarity { STABLE, ADVANCED, EXPERIMENTAL, CLASSIFIED, NEXT_GEN }

const RARITY_LABEL_KEYS: Array[String] = [
	"RARITY_STABLE", "RARITY_ADVANCED", "RARITY_EXPERIMENTAL", "RARITY_CLASSIFIED", "RARITY_NEXT_GEN",
]

const RARITY_COLORS: Array[Color] = [
	Color(0.85, 0.85, 0.85),  ## STABLE        — 灰白
	Color(0.40, 0.75, 1.00),  ## ADVANCED      — 蓝
	Color(0.85, 0.50, 1.00),  ## EXPERIMENTAL  — 紫
	Color(1.00, 0.78, 0.20),  ## CLASSIFIED    — 金
	Color(1.00, 0.30, 0.30),  ## NEXT_GEN      — 红
]

## 抽卡基础权重（5 槽相对概率，未应用 pity / steering 前）
## 每升一级 normalize 后乘 keyword_steering_mult；高稀有未出 pity 累加见 _pick_3_upgrades
const RARITY_BASE_WEIGHT: Array[float] = [
	0.50,   # STABLE
	0.25,   # ADVANCED
	0.15,   # EXPERIMENTAL
	0.08,   # CLASSIFIED
	0.02,   # NEXT_GEN
]

## Pity 阈值：连续 N 次升级未出该档则下次保底必出
## advanced 不设 pity（base 25% 足够），exp/cla/next 强保底
const PITY_THRESHOLD: Dictionary = {
	Rarity.EXPERIMENTAL: 5,
	Rarity.CLASSIFIED: 8,
	Rarity.NEXT_GEN: 12,
}

# ── 升级定义 ─────────────────────────────────────────────
# 每种升级直接修改 Aircraft 的 params（AircraftParams / GunParams / MissileParams）
#
# 必填字段：
#   id / name / desc / stat / value / max_stacks / category
# category: "combat" = 战斗轴, "survival" = 生存轴
#
# 可选字段：
#   rarity: Rarity 枚举（默认 STABLE）— §5 抽卡分槽 + UI 染色用
#   keywords: Array[String] — §7 流派引导关键词（如 ["fear","head_on"]）；纯数值技能可不挂
#   evolved: true = 进化技能，不出现在随机池中，由基础技能满级自动触发（§4 后已弃用）
#   evolves_to: "xxx" = 满级后自动进化为指定技能（仍保留旧链）
#   requires: 数组 — 飞机必须具备的硬件标签才能获得此升级
#               可选值: "gun" / "missile" / "flare" / "rocket"
#               例：["gun"] 表示无机炮的飞机不会出现该升级
#               留空 = 无硬件要求
#   requires_skill: Array[String] — §6 前置链；至少持有列表中一个技能（stacks>0）才解锁
#   exclusive_to: 数组 — 仅允许指定的 PlayableAircraft.id 获得（专属升级）
#               例：["f14"] 表示只有 F-14 主角能 roll 到
#               留空 = 通用升级，所有飞机可获取
#   excludes: Array[String] — 互斥技能；列表中任一技能 stacks>0 时，本升级不再出现在抽卡池
#               例：cobra_skill ↔ evasion_herbst（激活条件相同，二选一）
#
# ── 归属词汇 v6（spec skills-720-rework §1.2 / squad-upgrade-ownership §2.8）──
#   scope: "" 缺省 = 通用全队（全队逐机生效）
#          "ace" = 王牌：仅当前操控机生效（AoE 控场/操作型强技；切控随人迁移）
#          "squad_once" = 队级单实例：只记 upgrade_stacks 账本、不逐机应用
#                         （消费点直接读账本，如数据链锁定共享 / xp_mult）
#   classes: Array[String] — 品类限定（"gladiator"/"knight"/"schemer"）；
#            非空 = 全队下发、仅品类身份匹配的机生效（身份=进化节点机种类，
#            见 EvolutionSystem.CLASS_IDENTITY_BY_CATEGORY）；可与 scope:"ace" 叠加（过滤∩操控机）
#   milestone_plus: "gladiator"/"knight"/"schemer" — 获得该技能时对应轴**里程碑进度** +1
#            （不给进化门槛点数；每轴 cap=2，见 SurvivorPlayer.MILESTONE_BONUS_CAP）
#
# 技能可用性判定见 SurvivorData.is_upgrade_available_for()

const UPGRADES: Array[Dictionary] = [
	# ── 生存轴 ──
	{
		"id": "hp_up",
		"name": "UPGRADE_HP_UP_NAME",
		"desc": "UPGRADE_HP_UP_DESC",
		"stat": "max_hp",
		"value": 30.0,  ## 720 批：+80→+30/层
		"max_stacks": 2,
		"category": "survival",
		"rarity": Rarity.STABLE,
		"keywords": ["hp"],
	},
	{
		"id": "bullet_dodge",
		"name": "UPGRADE_BULLET_DODGE_NAME",
		"desc": "UPGRADE_BULLET_DODGE_DESC",
		"stat": "bullet_dodge_flat",
		"value": 0.20,             ## 每层 +20% 机炮闪避（全局 cap MAX_BULLET_DODGE_CAP=0.85 兜底）
		"max_stacks": 2,
		"category": "survival",
		"rarity": Rarity.STABLE,
		"keywords": ["dodge"],
	},
	{
		"id": "speed_up",
		"name": "UPGRADE_SPEED_UP_NAME",
		"desc": "UPGRADE_SPEED_UP_DESC",
		"stat": "speed",
		"value": 0.20,  ## 720 批：+30%→+20%/层
		"max_stacks": 2,  ## 720 批 1→2
		"category": "mobility",
		"rarity": Rarity.STABLE,
		"keywords": ["speed"],
		"accel_ratio": 0.5,  ## 加速 +10%/层（value×0.5）
	},
	{
		"id": "maneuver_up",
		"name": "UPGRADE_MANEUVER_UP_NAME",
		"desc": "UPGRADE_MANEUVER_UP_DESC",
		"stat": "maneuver",
		"value": 0.30,  ## 滚转 +30%/层（720 批 45%→30%）
		"max_stacks": 2,  ## 720 批 1→2
		"category": "mobility",
		"rarity": Rarity.STABLE,
		"keywords": ["maneuver"],
		"max_g_bonus": 1.5,  ## 720 批 2.5→1.5
		"structural_g_bonus": 1.5,  ## 720 批 2.5→1.5
	},
	## flare_cooldown 已删除（C2：迁移到局外配件 ecm_t2/ecm_aegis_t3）
	{
		"id": "flare_shield",
		"name": "UPGRADE_FLARE_SHIELD_NAME",
		"desc": "UPGRADE_FLARE_SHIELD_DESC",
		"stat": "flare_shield",
		"value": 3.0,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["flare"],
		# evolved 字段已弃用（§4 战区奖励降级；后续按战区映射注册）
		"requires": ["flare"],
		"bonus_flares": 2,         ## 额外赠送热诱弹数
	},
	{
		"id": "armor_up",
		"name": "UPGRADE_ARMOR_UP_NAME",
		"desc": "UPGRADE_ARMOR_UP_DESC",
		"stat": "armor",
		"value": 120.0,            ## C2 重构：1 层 +120（原 4×40 总 160；现单层 ≈ 原 3 层效果）
		"max_stacks": 1,
		"category": "survival",
		"rarity": Rarity.STABLE,
		"keywords": ["armor"],
		## 公式 aircraft.gd _apply_armor：dr = armor / (armor + 100)
		## 导弹穿甲 50%（MISSILE_ARMOR_PENETRATION=0.5），机炮全额生效
		## 120 armor → 55%/机炮 38%/导弹
	},
	## stealth_pod 已删除（C2：迁移到配件 ecm_t2/ecm_aegis_t3 的 lock_resistance）
	{
		"id": "kill_heal",
		"name": "UPGRADE_KILL_HEAL_NAME",
		"desc": "UPGRADE_KILL_HEAL_DESC",
		"stat": "kill_heal",
		"value": 5.0,  ## 720 批：10→5
		"max_stacks": 1,  ## 720 批 3→1
		"category": "survival",
		"rarity": Rarity.ADVANCED,
		"keywords": ["heal", "kill"],
	},
	# ── 战斗轴 ──
	{
		"id": "missile_count",
		"name": "UPGRADE_MISSILE_COUNT_NAME",
		"desc": "UPGRADE_MISSILE_COUNT_DESC",
		"stat": "missile_count",
		"value": 2,                ## C2 重构：1×+2（主+副槽各 +2，与自然成长叠加）
		"max_stacks": 3,  ## 720 批 1→3
		"category": "missile",
		"rarity": Rarity.ADVANCED,
		"keywords": ["missile"],
		"requires": ["missile"],
	},
	## missile_tracking 已删除（C2：迁移到配件 missile_track_t1/t2/apex_t3 的 G/FOV）
	{
		"id": "proximity_fuze",
		"name": "UPGRADE_PROXIMITY_FUZE_NAME",
		"desc": "UPGRADE_PROXIMITY_FUZE_DESC",
		"stat": "proximity_fuze",
		"value": 1,
		"max_stacks": 1,
		"category": "missile",
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["missile", "swarm"],
		# evolved 字段已弃用（§4 战区奖励降级；后续按战区映射注册）
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
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["missile", "chain"],
		# evolved 字段已弃用（§4 战区奖励降级；后续按战区映射注册）
		"requires": ["missile"],
	},
	## missile_reload 已删除（C2：迁移到配件 missile_apex_t3 的 reload×0.7）
	{
		"id": "missile_swarm",
		"name": "UPGRADE_MISSILE_SWARM_NAME",
		"desc": "UPGRADE_MISSILE_SWARM_DESC",
		"stat": "missile_swarm",
		"value": 4,                 ## max_count +4
		"max_stacks": 1,
		"category": "missile",
		"rarity": Rarity.NEXT_GEN,
		"keywords": ["missile", "swarm"],
		"requires": ["missile"],
		## 解锁同时锁定 + 齐射；负面效果：导弹 max_g ×0.85（轻微追踪减劣，弹群压火力不靠精度）
		"tracking_penalty": 0.85,
		"classes": ["knight"],
		"scope": "ace",  ## 720 批：王牌专属（ACE_FIELD_STATS 配对 strip）
		"evolved": true,  ## 720 批：进战区奖励池
	},
	{
		"id": "gun_damage",
		"name": "UPGRADE_GUN_DAMAGE_NAME",
		"desc": "UPGRADE_GUN_DAMAGE_DESC",
		"stat": "gun_damage",
		"value": 0.30,  ## 720 批：+55%→+30%/层
		"max_stacks": 2,
		"category": "secondary",
		"rarity": Rarity.STABLE,
		"keywords": ["gun"],
		## evolves_to 已移除：max_stacks=1 时拿到即触发会白送 multishot；multishot 已独立在池中
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
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["gun", "swarm"],
		# evolved 字段已弃用（§4 战区奖励降级；后续按战区映射注册）
		"requires": ["gun"],
		"classes": ["gladiator"],  ## 720 批：机炮吊舱，斗士限定·全队
	},
	## gun_ammo / gun_reload / gun_firerate / gun_range 已删除（C2：全部迁移到配件
	## gun_dmg_t1 / gun_combat_t2 / gun_assault_t3）
	{
		"id": "gun_ciws",
		"name": "UPGRADE_GUN_CIWS_NAME",
		"desc": "UPGRADE_GUN_CIWS_DESC",
		"stat": "gun_ciws",
		"value": 1,
		"max_stacks": 1,
		"category": "secondary",
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["gun", "ciws"],
		# evolved 字段已弃用（§4 战区奖励降级；后续按战区映射注册）
		"requires": ["gun"],
		"classes": ["gladiator"],  ## v5：CIWS 归斗士系攻击机
	},
	{
		"id": "fear_squad_spread",
		"name": "UPGRADE_FEAR_SQUAD_SPREAD_NAME",
		"desc": "UPGRADE_FEAR_SQUAD_SPREAD_DESC",
		"stat": "fear_squad_spread",
		"value": 5.0,  ## FEAR 持续秒数（720 批 →5s）
		"max_stacks": 1,
		"category": "secondary",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["fear"],
		## 自身就是"能施加恐惧的技能"，不需要前置
		"classes": ["schemer"],
		"scope": "ace",  ## 720 批：惊鸿扩散，策士限定＋王牌
	},
	{
		"id": "fear_chills",
		"name": "UPGRADE_FEAR_CHILLS_NAME",
		"desc": "UPGRADE_FEAR_CHILLS_DESC",
		"stat": "fear_chills",
		"value": 1.0,
		"max_stacks": 1,
		"category": "secondary",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["fear", "slow"],
		## 修饰恐惧效果 → 必须先持有任意"能施加恐惧的"技能
		"requires_skill": ["fear_squad_spread", "skill_gun_kill_fear", "skill_head_on_aoe_fear"],
	},
	## radar_range / lock_time 已删除（C2：迁移到配件 radar_range_t1/radar_combat_t2/radar_aegis_t3）
	{
		"id": "dogfight",
		"name": "UPGRADE_DOGFIGHT_NAME",
		"desc": "UPGRADE_DOGFIGHT_DESC",
		"stat": "dogfight",
		"value": 1,
		"max_stacks": 3,
		"category": "mobility",
		"rarity": Rarity.ADVANCED,
		"keywords": ["maneuver", "dogfight"],
		"stall_speed_mult": 0.88,           ## -12% 失速速度
		"decel_mult": 1.3,                  ## +30% 减速
		"g_drag_mult": 0.85,                ## -15% G 力阻力（狗斗派转弯能量更省）
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
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["evasion_mode", "cobra"],
		"excludes": ["evasion_herbst"],   ## 与危机赫尔贝特互斥（激活条件相同）
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
		"category": "electronic_warfare",
		"rarity": Rarity.STABLE,
		"keywords": ["xp"],
		"xp_cap": 1.4,             ## 硬顶 ×1.4
		"scope": "squad_once",  ## 队级单实例：倍率记 SurvivorPlayer 层（720 T2 迁移）
	},
	## radar_angle / seeker_fov 已删除（C2：迁移到配件 radar_aegis_t3 / missile_seeker_t2/apex_t3）
	{
		"id": "gun_accuracy",
		"name": "UPGRADE_GUN_ACCURACY_NAME",
		"desc": "UPGRADE_GUN_ACCURACY_DESC",
		"stat": "gun_accuracy",
		"value": 0.20,             ## 每层 spread ×(1-value)=×0.80
		"max_stacks": 2,  ## 720 批 4→2
		"category": "secondary",
		"rarity": Rarity.STABLE,
		"keywords": ["gun"],
		"requires": ["gun"],
		"min_deg": 0.1,            ## 散布下限 0.1°
		"aim_skill_boost": 0.18,   ## 每层飞行员 aim_skill +0.18，4 层 = +0.72（基础 0.3 → 1.02 cap 1.0）
		"lifetime_bonus": 0.20,  ## 720 批追加：子弹生存时间 +20%/层
	},
	{
		"id": "aim_assist",
		"name": "UPGRADE_AIM_ASSIST_NAME",
		"desc": "UPGRADE_AIM_ASSIST_DESC",
		"stat": "aim_assist",
		"value": 0.25,             ## 每层 fire_cone ×1.25
		"max_stacks": 3,
		"category": "secondary",
		"rarity": Rarity.STABLE,
		"keywords": ["gun"],
		"requires": ["gun"],
		"max_deg": 45.0,
	},
	{
		"id": "missile_boost",
		"name": "UPGRADE_MISSILE_BOOST_NAME",
		"desc": "UPGRADE_MISSILE_BOOST_DESC",
		"stat": "missile_boost",
		"value": 1,
		"max_stacks": 2,  ## 720 批 3→2
		"category": "missile",
		"rarity": Rarity.ADVANCED,
		"keywords": ["missile"],
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
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["cloud", "altitude", "stealth"],
		# evolved 字段已弃用（§4 战区奖励降级；后续按战区映射注册）
		## 效果两件套：
		##   ① altitude_authority_mult ×2.0 — 切档响应度翻倍（gain/smooth ×2），物理顶速被 cap 在 +30%
		##      —— cap 是为了不让 PE↔KE (g·vs/spd·2.5) 把横速吃光，详见 known-seams 与 aircraft_physics.gd:273
		##   ② cloud_lock_stealth = true — 云中任意档位 lock_rate ×0.1
		"altitude_mult": 2.0,
		"classes": ["schemer"],  ## v5：电战技归策士
	},
	{
		"id": "ecm_pod",
		"name": "UPGRADE_ECM_POD_NAME",
		"desc": "UPGRADE_ECM_POD_DESC",
		"stat": "ecm_pod",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["radar", "stealth"],
		# evolved 字段已弃用（§4 战区奖励降级；后续按战区映射注册）
		## 效果：ecm_range_mult = 0.75 — 敌方雷达对我的有效距离缩短 25%
		## 在 main.gd / survivor_mode.gd 的雷达循环中，若 dist > radar_range × 此值 则视同脱锥
		"range_mult": 0.75,
		"classes": ["schemer"],  ## v5：电战技归策士
	},
	# fire_and_forget 升级已废除（2026-04-29）：下放为玩家飞机标配。
	# 见 survivor_playable_setup.gd `apply()` 末段的导弹处理。
	{
		"id": "shock_absorb",
		"name": "UPGRADE_SHOCK_ABSORB_NAME",
		"desc": "UPGRADE_SHOCK_ABSORB_DESC",
		"stat": "shock_absorb",
		"value": 1,
		"max_stacks": 1,
		"category": "survival",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["heal"],
		# evolved 字段已弃用（§4 战区奖励降级；后续按战区映射注册）
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
		"rarity": Rarity.ADVANCED,  ## 720 批：机密→先进
		"keywords": ["kill", "streak"],
		# evolved 字段已弃用（§4 战区奖励降级；后续按战区映射注册）
		## 效果：连续不受伤击杀，每 2 杀 +1 层（max 5 层）
		## 每层加成（详见 aircraft.gd _executioner_*_mult）：
		##   max_speed +5%、deceleration +10%、missile_reload ×0.92、lock_time ×0.90
		## 受到任意伤害立即清零所有层数 + 计数
		"classes": ["knight"],  ## 720 批：斗士限定→骑士限定
	},
	# ── X-02 专属：电磁炮 ──────────────────────────────────────
	{
		"id": "railgun_charge",
		"name": "UPGRADE_RAILGUN_CHARGE_NAME",
		"desc": "UPGRADE_RAILGUN_CHARGE_DESC",
		"stat": "railgun_charge",
		"value": 0.30,  ## 720 批：-20%→-30%/层
		"max_stacks": 2,  ## 720 批 3→2
		"category": "weapon",
		"rarity": Rarity.ADVANCED,
		"keywords": ["railgun"],
		"requires": ["railgun"],
	},
	{
		"id": "railgun_range",
		"name": "UPGRADE_RAILGUN_RANGE_NAME",
		"desc": "UPGRADE_RAILGUN_RANGE_DESC",
		"stat": "railgun_range",
		"value": 1500.0,  ## 720 批：+500m→+1500m/层
		"max_stacks": 3,
		"category": "weapon",
		"rarity": Rarity.STABLE,
		"keywords": ["railgun"],
		"requires": ["railgun"],
	},
	# ── X-02 专属：激光照射 ────────────────────────────────────
	{
		"id": "laser_cooldown",
		"name": "UPGRADE_LASER_COOLDOWN_NAME",
		"desc": "UPGRADE_LASER_COOLDOWN_DESC",
		"stat": "laser_cooldown",
		"value": 0.40,  ## 720 批：+25%→+40%/层
		"max_stacks": 2,  ## 720 批 3→2
		"category": "weapon",
		"rarity": Rarity.ADVANCED,
		"keywords": ["laser"],
		"requires": ["laser"],
	},
	{
		"id": "laser_range",
		"name": "UPGRADE_LASER_RANGE_NAME",
		"desc": "UPGRADE_LASER_RANGE_DESC",
		"stat": "laser_range",
		"value": 0.20,
		"max_stacks": 2,  ## 720 批 3→2
		"category": "weapon",
		"rarity": Rarity.STABLE,
		"keywords": ["laser"],
		"requires": ["laser"],
	},
	{
		"id": "laser_heat",
		"name": "UPGRADE_LASER_HEAT_NAME",
		"desc": "UPGRADE_LASER_HEAT_DESC",
		"stat": "laser_heat",
		"value": 0.50,  ## 720 批：+30%→+50%
		"max_stacks": 1,  ## 720 批 3→1
		"category": "weapon",
		"rarity": Rarity.ADVANCED,
		"keywords": ["laser"],
		"requires": ["laser"],
	},
	# ══════════════════════════════════════════════════════════════
	# §1.4 样例技能：钩子链验证用（5 张，覆盖 ADV/EXP/CLA 三档稀有度）
	# 这些技能的 id 与 SkillHooks 中的 SKILL_* 常量一一对应
	# 实际效果由 SkillHooks.dispatch_on_kill / dispatch_on_hit 触发，stat 字段仅占位
	# ══════════════════════════════════════════════════════════════
	# ── §1.2 Evasion 模式扩展（直接写 evasion_modifiers，set_evasion_mode 切换时差量应用）──
	{
		"id": "evasion_overstock",
		"name": "UPGRADE_EVASION_OVERSTOCK_NAME",
		"desc": "UPGRADE_EVASION_OVERSTOCK_DESC",
		"stat": "evasion_overstock",
		"value": 4.0,                ## evasion 期间每 4s 装填 1 发，cap = max_count×2
		"max_stacks": 1,
		"category": "missile",
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["evasion_mode", "missile"],
		"requires": ["missile"],
	},
	{
		"id": "low_alt_gun_dodge",
		"name": "UPGRADE_LOW_ALT_GUN_DODGE_NAME",
		"desc": "UPGRADE_LOW_ALT_GUN_DODGE_DESC",
		"stat": "low_alt_gun_dodge",
		"value": 0.50,                ## 低空时机炮闪避 +50%
		"max_stacks": 1,
		"category": "secondary",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["dodge", "low_alt", "chivalry"],
		"requires": ["gun"],
	},
	{
		"id": "jam_aura",
		"name": "UPGRADE_JAM_AURA_NAME",
		"desc": "UPGRADE_JAM_AURA_DESC",
		"stat": "jam_aura",
		"value": 1300.0,              ## JAM 光环半径（≈2.6km）
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["jam", "aura"],
		"classes": ["gladiator"],  ## 720 批：骑士限定→斗士限定
	},
	{
		"id": "rear_aura_slow",
		"name": "UPGRADE_REAR_AURA_SLOW_NAME",
		"desc": "UPGRADE_REAR_AURA_SLOW_DESC",
		"stat": "rear_aura_slow",
		"value": 1200.0,             ## 后半球 SLOW 光环半径 px (≈2.4km)
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["slow", "aura"],
		"classes": ["gladiator"],
		"scope": "ace",  ## 720 批：斗士限定＋王牌
		"milestone_plus": "gladiator",
	},
	{
		"id": "evasion_stealth",
		"name": "UPGRADE_EVASION_STEALTH_NAME",
		"desc": "UPGRADE_EVASION_STEALTH_DESC",
		"stat": "evasion_stealth",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.NEXT_GEN,
		"keywords": ["evasion_mode", "stealth"],
		"milestone_plus": "knight",
		"evolved": true,  ## 720 批：雾隐机动进战区奖励池
	},
	{
		"id": "evasion_herbst",
		"name": "UPGRADE_EVASION_HERBST_NAME",
		"desc": "UPGRADE_EVASION_HERBST_DESC",
		"stat": "evasion_herbst",
		"value": 1,
		"max_stacks": 1,
		"category": "mobility",
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["evasion_mode", "panic_save"],
		"excludes": ["cobra_skill"],   ## 与眼镜蛇机动互斥（激活条件相同）
	},
	{
		"id": "evasion_speed_boost",
		"name": "UPGRADE_EVASION_SPEED_BOOST_NAME",
		"desc": "UPGRADE_EVASION_SPEED_BOOST_DESC",
		"stat": "evasion_speed_boost",
		"value": 1.4,                ## evasion 模式 cruise ×1.4（≈ +40%）
		"max_stacks": 1,
		"category": "mobility",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["evasion_mode", "speed"],
	},
	{
		"id": "evasion_weapon_cd",
		"name": "UPGRADE_EVASION_WEAPON_CD_NAME",
		"desc": "UPGRADE_EVASION_WEAPON_CD_DESC",
		"stat": "evasion_weapon_cd",
		"value": 0.5,                ## evasion 模式 武器 cd ×0.5（更快）
		"max_stacks": 1,
		"category": "mobility",
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["evasion_mode", "gun", "missile"],
	},
	{
		"id": "skill_kill_bloodlust",
		"name": "UPGRADE_SKILL_KILL_BLOODLUST_NAME",
		"desc": "UPGRADE_SKILL_KILL_BLOODLUST_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "survival",
		"rarity": Rarity.ADVANCED,
		"keywords": ["bloodlust"],
	},
	{
		"id": "skill_damaged_bloodlust",
		"name": "UPGRADE_SKILL_DAMAGED_BLOODLUST_NAME",
		"desc": "UPGRADE_SKILL_DAMAGED_BLOODLUST_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "survival",
		"rarity": Rarity.ADVANCED,
		"keywords": ["bloodlust"],
	},
	{
		"id": "skill_head_on_perma_hp",
		"name": "UPGRADE_SKILL_HEAD_ON_PERMA_HP_NAME",
		"desc": "UPGRADE_SKILL_HEAD_ON_PERMA_HP_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "survival",
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["head_on", "chivalry"],
		"axis": "knight",  ## 720 批：斗士轴→骑士轴（对头=骑士武德）
	},
	{
		"id": "skill_head_on_aoe_fear",
		"name": "UPGRADE_SKILL_HEAD_ON_AOE_FEAR_NAME",
		"desc": "UPGRADE_SKILL_HEAD_ON_AOE_FEAR_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["head_on", "fear"],
		"scope": "ace",  ## 720 批：寒颤号令归王牌（AoE 控场强技）
		"milestone_plus": "knight",
	},
	{
		"id": "skill_missile_hit_invul",
		"name": "UPGRADE_SKILL_MISSILE_HIT_INVUL_NAME",
		"desc": "UPGRADE_SKILL_MISSILE_HIT_INVUL_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "survival",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["panic_save"],
		"classes": ["gladiator"],  ## v5：无敌保命归斗士
	},
	{
		"id": "skill_lowest_alt_kill_invul",
		"name": "UPGRADE_SKILL_LOWEST_ALT_KILL_INVUL_NAME",
		"desc": "UPGRADE_SKILL_LOWEST_ALT_KILL_INVUL_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "survival",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["low_alt", "chivalry"],
		"exclusive_to": ["a10"],  ## 720 批：空中战车，A-10 限定
	},
	{
		"id": "skill_gun_kill_fear",
		"name": "UPGRADE_SKILL_GUN_KILL_FEAR_NAME",
		"desc": "UPGRADE_SKILL_GUN_KILL_FEAR_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["fear", "gun"],
		"requires": ["gun"],
		"scope": "ace",  ## 720 批：机炮震慑归王牌
	},
	# ── 已有 SkillHooks 但缺 UPGRADES 入口的钩子激活技能 ──
	{
		"id": "skill_kill_status_heal",
		"name": "UPGRADE_SKILL_KILL_STATUS_HEAL_NAME",
		"desc": "UPGRADE_SKILL_KILL_STATUS_HEAL_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "survival",
		"rarity": Rarity.ADVANCED,
		"keywords": ["heal", "kill", "fear"],   ## 门控在【恐惧】doctrine 后——异常状态最常见的来源就是 FEAR
		"milestone_plus": "schemer",  ## 720 批：策士+1
	},
	{
		"id": "skill_flare_aoe_jam",
		"name": "UPGRADE_SKILL_FLARE_AOE_JAM_NAME",
		"desc": "UPGRADE_SKILL_FLARE_AOE_JAM_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.ADVANCED,
		"keywords": ["flare", "jam"],
		"requires": ["flare"],
		"classes": ["schemer"],  ## v5：电子战触发技归策士
	},
	{
		"id": "skill_gun_kill_flare_drop",
		"name": "UPGRADE_SKILL_GUN_KILL_FLARE_DROP_NAME",
		"desc": "UPGRADE_SKILL_GUN_KILL_FLARE_DROP_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "secondary",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["gun", "jam"],
		"requires": ["gun"],
		"classes": ["gladiator"],  ## 720 批：策士限定→斗士限定
		"milestone_plus": "gladiator",
	},
	{
		"id": "skill_missile_hit_aoe_jam",
		"name": "UPGRADE_SKILL_MISSILE_HIT_AOE_JAM_NAME",
		"desc": "UPGRADE_SKILL_MISSILE_HIT_AOE_JAM_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["jam", "panic_save"],
	},
	# ── 激光升级（按装备过滤）──
	{
		"id": "skill_laser_damage",
		"name": "UPGRADE_SKILL_LASER_DAMAGE_NAME",
		"desc": "UPGRADE_SKILL_LASER_DAMAGE_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "secondary",
		"rarity": Rarity.ADVANCED,
		"keywords": ["laser", "damage"],
		"requires": ["laser"],
	},
	{
		"id": "laser_extra_beams",
		"name": "UPGRADE_LASER_EXTRA_BEAMS_NAME",
		"desc": "UPGRADE_LASER_EXTRA_BEAMS_DESC",
		"stat": "laser_extra_beams",
		"value": 1,  ## 每层 max_simultaneous_targets +1（720 批 2→1）
		"max_stacks": 2,               ## 最多 2 层 = +4 束
		"category": "secondary",
		"rarity": Rarity.STABLE,
		"keywords": ["laser", "multishot"],
		"requires": ["laser"],
	},
	# ── 火箭弹 / 漂浮雷专属升级（按装备过滤，不限机型）──
	# requires 已保证只有挂相应武器的飞机才能 roll；不加 exclusive_to，
	# 这样未来任何机型挂上 rocket / torpedo 都能享用同一池
	{
		"id": "skill_torpedo_aoe_jam",
		"name": "UPGRADE_SKILL_TORPEDO_AOE_JAM_NAME",
		"desc": "UPGRADE_SKILL_TORPEDO_AOE_JAM_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.ADVANCED,
		"keywords": ["torpedo", "jam"],
		"requires": ["torpedo"],
		"classes": ["schemer"],  ## v5：电子战触发技归策士
	},
	{
		"id": "rocket_firerate_range",
		"name": "UPGRADE_ROCKET_FIRERATE_RANGE_NAME",
		"desc": "UPGRADE_ROCKET_FIRERATE_RANGE_DESC",
		"stat": "rocket_firerate_range",
		"value": 0.25,                 ## CD ×0.75，max_range ×1.25（每层）
		"max_stacks": 2,
		"category": "secondary",
		"rarity": Rarity.STABLE,
		"keywords": ["rocket"],
		"requires": ["rocket"],
	},
	{
		"id": "skill_rocket_homing",
		"name": "UPGRADE_SKILL_ROCKET_HOMING_NAME",
		"desc": "UPGRADE_SKILL_ROCKET_HOMING_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "secondary",
		"rarity": Rarity.ADVANCED,
		"keywords": ["rocket", "tracking"],
		"requires": ["rocket"],
	},
	{
		"id": "torpedo_tracking_boost",
		"name": "UPGRADE_TORPEDO_TRACKING_BOOST_NAME",
		"desc": "UPGRADE_TORPEDO_TRACKING_BOOST_DESC",
		"stat": "torpedo_tracking_boost",
		"value": 0.6,                  ## scan_range ×1.6，turn_rate ×2.0（每层）
		"max_stacks": 2,
		"category": "secondary",
		"rarity": Rarity.ADVANCED,
		"keywords": ["torpedo", "tracking"],
		"requires": ["torpedo"],
		"milestone_plus": "schemer",  ## 720 批：策士+1
	},
	# ── 数值类便利贴技能（直接改 Aircraft / params 字段）──
	{
		"id": "lock_panic_g",
		"name": "UPGRADE_LOCK_PANIC_G_NAME",
		"desc": "UPGRADE_LOCK_PANIC_G_DESC",
		"stat": "lock_panic_g",
		"value": 0.20,                ## 被锁时 max_g ×1.20
		"max_stacks": 2,
		"category": "mobility",
		"rarity": Rarity.STABLE,
		"keywords": ["maneuver", "panic"],
		"milestone_plus": "gladiator",  ## 720 批：斗士+1
	},
	{
		"id": "low_hp_flare_reload",
		"name": "UPGRADE_LOW_HP_FLARE_RELOAD_NAME",
		"desc": "UPGRADE_LOW_HP_FLARE_RELOAD_DESC",
		"stat": "low_hp_flare_reload",
		"value": 0.5,                 ## hp<50% 时 flare reload ×0.5（更快）
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.ADVANCED,
		"keywords": ["flare", "low_hp"],
		"requires": ["flare"],
		"axis": "knight",  ## 720 批：策士轴→骑士轴
	},
	{
		"id": "high_alt_lock_speed",
		"name": "UPGRADE_HIGH_ALT_LOCK_SPEED_NAME",
		"desc": "UPGRADE_HIGH_ALT_LOCK_SPEED_DESC",
		"stat": "high_alt_lock_speed",
		"value": 0.30,                ## HIGH 档时锁定速率 ×1.30
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.ADVANCED,
		"keywords": ["radar", "altitude"],
		"axis": "knight",  ## 720 批：策士轴→骑士轴
	},
	{
		"id": "ab_gun_regen",
		"name": "UPGRADE_AB_GUN_REGEN_NAME",
		"desc": "UPGRADE_AB_GUN_REGEN_DESC",
		"stat": "ab_gun_regen",
		"value": 25.0,                ## AB 时每秒 +25 发机炮弹
		"max_stacks": 1,
		"category": "secondary",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["gun", "afterburner"],
		"requires": ["gun"],
		"milestone_plus": "knight",  ## 720 批：骑士+1
	},
	{
		"id": "head_on_gun_dodge",
		"name": "UPGRADE_HEAD_ON_GUN_DODGE_NAME",
		"desc": "UPGRADE_HEAD_ON_GUN_DODGE_DESC",
		"stat": "head_on_gun_dodge",
		"value": 0.60,                ## 对头时机炮闪避 +60%
		"max_stacks": 1,
		"category": "secondary",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["gun", "head_on", "chivalry"],
		"requires": ["gun"],
		"axis": "knight",  ## 720 批：斗士轴→骑士轴
	},
	{
		"id": "gun_fire_dr",
		"name": "UPGRADE_GUN_FIRE_DR_NAME",
		"desc": "UPGRADE_GUN_FIRE_DR_DESC",
		"stat": "gun_fire_dr",
		"value": 0.5,                 ## 减伤比例 50%
		"window": 0.5,  ## 时间窗 0.5s（720 批 0.4→0.5）
		"max_stacks": 1,
		"category": "secondary",
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["gun", "panic_save"],
		"requires": ["gun"],
	},
	{
		"id": "fear_on_lock",
		"name": "UPGRADE_FEAR_ON_LOCK_NAME",
		"desc": "UPGRADE_FEAR_ON_LOCK_DESC",
		"stat": "fear_on_lock",
		"value": 6.0,                 ## 累积 6s（FEAR 期间不累积，消退后重置）
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.NEXT_GEN,  ## 720 批：实验→次世代
		"keywords": ["fear", "radar", "lock"],
		"scope": "ace",  ## 720 批：凝视压迫归王牌
	},
	{
		"id": "cloud_overload",
		"name": "UPGRADE_CLOUD_OVERLOAD_NAME",
		"desc": "UPGRADE_CLOUD_OVERLOAD_DESC",
		"stat": "cloud_overload",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["cloud", "overload"],
		"classes": ["knight"],
		"scope": "ace",
		"milestone_plus": "knight",
	},
	{
		"id": "cloud_weapon_cd",
		"name": "UPGRADE_CLOUD_WEAPON_CD_NAME",
		"desc": "UPGRADE_CLOUD_WEAPON_CD_DESC",
		"stat": "cloud_weapon_cd",
		"value": 0.5,                 ## 云中武器 cd ×0.5（更快）
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["cloud", "gun", "missile"],
	},
	{
		"id": "alt_change_stealth",
		"name": "UPGRADE_ALT_CHANGE_STEALTH_NAME",
		"desc": "UPGRADE_ALT_CHANGE_STEALTH_DESC",
		"stat": "alt_change_stealth",
		"value": 0.5,                 ## 高度变化时 lock_rate ×(1 - alt_velocity_norm × 0.5)
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["altitude", "stealth"],
	},
	{
		"id": "skill_evade_missile_overload",
		"name": "UPGRADE_SKILL_EVADE_MISSILE_OVERLOAD_NAME",
		"desc": "UPGRADE_SKILL_EVADE_MISSILE_OVERLOAD_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["flare", "overload"],
		"requires": ["flare"],
		"classes": ["knight"],  ## v5：超载家族归骑士
	},
	{
		"id": "skill_flare_overload",
		"name": "UPGRADE_SKILL_FLARE_OVERLOAD_NAME",
		"desc": "UPGRADE_SKILL_FLARE_OVERLOAD_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.ADVANCED,
		"keywords": ["flare", "overload"],
		"requires": ["flare"],
		"classes": ["knight"],  ## v5：超载家族归骑士
		"milestone_plus": "knight",
	},
	{
		"id": "missile_cd_stealth",
		"name": "UPGRADE_MISSILE_CD_STEALTH_NAME",
		"desc": "UPGRADE_MISSILE_CD_STEALTH_DESC",
		"stat": "missile_cd_stealth",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.ADVANCED,
		"keywords": ["missile", "stealth"],
		"requires": ["missile"],
	},
	{
		"id": "overload_duration_4x",
		"name": "UPGRADE_OVERLOAD_DURATION_4X_NAME",
		"desc": "UPGRADE_OVERLOAD_DURATION_4X_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["overload"],
		## 必须先有"能进入超载"的来源，避免单独 roll 到形同空技能
		"requires_skill": ["cloud_overload", "skill_evade_missile_overload", "skill_flare_overload"],
	},
	{
		"id": "overload_extended_ammo",
		"name": "UPGRADE_OVERLOAD_EXTENDED_AMMO_NAME",
		"desc": "UPGRADE_OVERLOAD_EXTENDED_AMMO_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["overload", "missile", "gun"],
		"requires_skill": ["cloud_overload", "skill_evade_missile_overload", "skill_flare_overload"],
	},
	{
		"id": "overload_to_bloodlust",
		"name": "UPGRADE_OVERLOAD_TO_BLOODLUST_NAME",
		"desc": "UPGRADE_OVERLOAD_TO_BLOODLUST_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["overload", "bloodlust"],
		"requires_skill": ["cloud_overload", "skill_evade_missile_overload", "skill_flare_overload"],
		"milestone_plus": "gladiator",  ## 720 批：噬血共振 斗士+1
	},
	{
		"id": "bloodlust_armor_mobility",
		"name": "UPGRADE_BLOODLUST_ARMOR_MOBILITY_NAME",
		"desc": "UPGRADE_BLOODLUST_ARMOR_MOBILITY_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "survival",
		"rarity": Rarity.ADVANCED,
		"keywords": ["bloodlust", "armor", "mobility"],
		"requires_skill": ["skill_kill_bloodlust", "skill_damaged_bloodlust", "overload_to_bloodlust"],
	},
	{
		"id": "full_hp_kill_perma_hp",
		"name": "UPGRADE_FULL_HP_KILL_PERMA_HP_NAME",
		"desc": "UPGRADE_FULL_HP_KILL_PERMA_HP_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "survival",
		"rarity": Rarity.EXPERIMENTAL,  ## 720 批：机密→实验（去掉满血前置后降档）
		"keywords": ["bloodlust", "hp"],
		"requires_skill": ["skill_kill_bloodlust", "skill_damaged_bloodlust", "overload_to_bloodlust"],
	},
	{
		"id": "head_on_jam",
		"name": "UPGRADE_HEAD_ON_JAM_NAME",
		"desc": "UPGRADE_HEAD_ON_JAM_DESC",
		"stat": "head_on_jam",
		"value": 3.0,                ## 累积 3s 后施加 JAM
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["head_on", "jam"],
		"classes": ["knight"],
		"scope": "ace",  ## 720 批：骑士限定＋王牌
		"milestone_plus": "knight",
	},
	{
		"id": "jam_self_overload",
		"name": "UPGRADE_JAM_SELF_OVERLOAD_NAME",
		"desc": "UPGRADE_JAM_SELF_OVERLOAD_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["jam", "overload"],
		## 必须先有"能施加 JAM"的来源；否则技能形同空
		"requires_skill": ["cloud_overload", "skill_evade_missile_overload", "skill_flare_overload"],  ## 720 批：需要词条改超载入门技
		"classes": ["knight"],
	},
	# ── F-14 专属：数据链 ──
	# 队友锁定的目标 = 玩家完成锁定（反之亦然）；同时强化僚机雷达范围
	# 仍受发射时 cone/envelope/range 校验，"看不见就能射" 不会发生
	{
		"id": "data_link",
		"name": "UPGRADE_DATA_LINK_NAME",
		"desc": "UPGRADE_DATA_LINK_DESC",
		"stat": "data_link",
		"value": 0.20,  ## 僚机雷达范围 ×1.2（720 批 +50%→+20%，取消 F-14 专属）
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.NEXT_GEN,
		"keywords": ["radar", "wingman", "f14"],
		"scope": "squad_once",  ## 队级单实例：锁定共享读账本（survivor_mode 雷达循环）
	},
	{
		"id": "f14_squad_lock_slow",
		"name": "UPGRADE_F14_SQUAD_LOCK_SLOW_NAME",
		"desc": "UPGRADE_F14_SQUAD_LOCK_SLOW_DESC",
		"stat": "f14_squad_lock_slow",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.EXPERIMENTAL,  ## 720 批：群猎注视，次世代→实验（§2.2 稀 3）
		"keywords": ["slow", "wingman", "f14"],
		"exclusive_to": ["f14"],
		## 前置：必须先有数据链；不然全队雷达不共享，锁同目标极难
		"requires_skill": ["data_link"],
		"scope": "squad_once",  ## 720 批：群猎注视（改名），队级单实例
	},
	# ── 720 批新增：装备门控强化组 + 座舱护甲（spec skills-720-rework §2.2）──
	{
		"id": "torpedo_extra",
		"name": "UPGRADE_TORPEDO_EXTRA_NAME",
		"desc": "UPGRADE_TORPEDO_EXTRA_DESC",
		"stat": "torpedo_extra",
		"value": 1,                    ## 每层投放数量 +1
		"max_stacks": 2,
		"category": "secondary",
		"rarity": Rarity.STABLE,
		"keywords": ["torpedo"],
		"requires": ["torpedo"],
		"milestone_plus": "knight",
	},
	{
		"id": "qmaam_boost",
		"name": "UPGRADE_QMAAM_BOOST_NAME",
		"desc": "UPGRADE_QMAAM_BOOST_DESC",
		"stat": "qmaam_boost",
		"value": 1,                    ## 每层格斗弹 +1
		"range_bonus": 0.10,           ## 射程 +10%/层
		"max_stacks": 2,
		"category": "missile",
		"axis": "gladiator",           ## §2.2 归斗士轴（近距格斗弹）
		"rarity": Rarity.STABLE,
		"keywords": ["missile"],
		"requires": ["secondary_missile"],
	},
	{
		"id": "wingman_extra",
		"name": "UPGRADE_WINGMAN_EXTRA_NAME",
		"desc": "UPGRADE_WINGMAN_EXTRA_DESC",
		"stat": "wingman_extra",
		"value": 1,                    ## 每层同屏上限 +1
		"max_stacks": 2,
		"category": "electronic_warfare",
		"rarity": Rarity.STABLE,
		"keywords": ["wingman"],
		"requires": ["loyal_wingman"],
	},
	{
		"id": "wingman_armed",
		"name": "UPGRADE_WINGMAN_ARMED_NAME",
		"desc": "UPGRADE_WINGMAN_ARMED_DESC",
		"stat": "wingman_armed",
		"value": 0.30,                 ## 无人机武器/自爆伤害 +30%
		"range_bonus": 0.20,           ## 无人机武器射程 +20%
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.STABLE,
		"keywords": ["wingman"],
		"requires": ["loyal_wingman"],
		"milestone_plus": "knight",
	},
	{
		"id": "cockpit_armor",
		"name": "UPGRADE_COCKPIT_ARMOR_NAME",
		"desc": "UPGRADE_COCKPIT_ARMOR_DESC",
		"stat": "cockpit_armor",
		"value": 0.5,                  ## 每层地面火力（SAM/AA/CIWS）伤害 ×0.5
		"max_stacks": 2,
		"category": "survival",
		"rarity": Rarity.ADVANCED,
		"keywords": ["hp"],
	},
	# ── 720 批 T3 新增：钩子技能组（spec skills-720-rework §2.2 / §3.2-§3.3）──
	{
		"id": "squad_revenge",
		"name": "UPGRADE_SQUAD_REVENGE_NAME",
		"desc": "UPGRADE_SQUAD_REVENGE_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "survival",
		"rarity": Rarity.EXPERIMENTAL,
		"scope": "squad_once",         ## 僚机阵亡事件（survivor_mode watcher）读账本触发
		"keywords": ["squad", "bloodlust"],
	},
	{
		"id": "guard_zone_buff",
		"name": "UPGRADE_GUARD_ZONE_BUFF_NAME",
		"desc": "UPGRADE_GUARD_ZONE_BUFF_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "survival",
		"rarity": Rarity.ADVANCED,
		"scope": "squad_once",         ## SquadCommandController 防守 tick 读账本打圈内 buff
		"keywords": ["squad"],
	},
	{
		"id": "gun_reserve_mag",
		"name": "UPGRADE_GUN_RESERVE_MAG_NAME",
		"desc": "UPGRADE_GUN_RESERVE_MAG_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 2,               ## 首层 30% / 双层 50%（SkillHooks.try_gun_reserve_mag）
		"category": "secondary",
		"rarity": Rarity.EXPERIMENTAL,
		"keywords": ["gun"],
		"requires": ["gun"],
	},
	{
		"id": "gun_out_free_missile",
		"name": "UPGRADE_GUN_OUT_FREE_MISSILE_NAME",
		"desc": "UPGRADE_GUN_OUT_FREE_MISSILE_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "secondary",
		"rarity": Rarity.ADVANCED,
		"keywords": ["gun", "missile"],
		"requires": ["gun", "missile"],
	},
	{
		"id": "headon_xp",
		"name": "UPGRADE_HEADON_XP_NAME",
		"desc": "UPGRADE_HEADON_XP_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "mobility",        ## 骑士轴（对头=骑士武德；survivor_spawner XP ×1.5）
		"rarity": Rarity.STABLE,
		"keywords": ["head_on"],
	},
	{
		"id": "ab_kill_charge",
		"name": "UPGRADE_AB_KILL_CHARGE_NAME",
		"desc": "UPGRADE_AB_KILL_CHARGE_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 2,               ## +3s/层（AfterburnerCharge.kill_charge_bonus 账本同步）
		"category": "mobility",
		"rarity": Rarity.STABLE,
		"keywords": ["afterburner"],
	},
	{
		"id": "ab_duration",
		"name": "UPGRADE_AB_DURATION_NAME",
		"desc": "UPGRADE_AB_DURATION_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 2,               ## 窗口 ×(1+0.5/层)：6→9→12s
		"category": "mobility",
		"rarity": Rarity.STABLE,
		"keywords": ["afterburner"],
	},
	{
		"id": "adapt_energy",
		"name": "UPGRADE_ADAPT_ENERGY_NAME",
		"desc": "UPGRADE_ADAPT_ENERGY_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "mobility",
		"rarity": Rarity.CLASSIFIED,
		"keywords": ["afterburner", "heal"],
	},
	{
		"id": "assassin_revenge",
		"name": "UPGRADE_ASSASSIN_REVENGE_NAME",
		"desc": "UPGRADE_ASSASSIN_REVENGE_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "mobility",
		"rarity": Rarity.ADVANCED,
		"scope": "squad_once",
		"keywords": ["squad", "overload"],
	},
	{
		"id": "evac_shift",
		"name": "UPGRADE_EVAC_SHIFT_NAME",
		"desc": "UPGRADE_EVAC_SHIFT_DESC",
		"stat": "evac_shift",
		"value": 1,
		"max_stacks": 1,
		"category": "mobility",
		"rarity": Rarity.ADVANCED,
		"keywords": ["squad"],
	},
	{
		"id": "levelup_heal",
		"name": "UPGRADE_LEVELUP_HEAL_NAME",
		"desc": "UPGRADE_LEVELUP_HEAL_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "survival",
		"axis": "schemer",             ## §2.2 归策士轴（经济/支援系）
		"rarity": Rarity.ADVANCED,
		"scope": "squad_once",
		"keywords": ["heal"],
	},
	{
		"id": "ground_crew",
		"name": "UPGRADE_GROUND_CREW_NAME",
		"desc": "UPGRADE_GROUND_CREW_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.STABLE,
		"scope": "squad_once",
		"keywords": ["squad"],
	},
	{
		"id": "blackbox_recovery",
		"name": "UPGRADE_BLACKBOX_RECOVERY_NAME",
		"desc": "UPGRADE_BLACKBOX_RECOVERY_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.STABLE,
		"scope": "squad_once",
		"keywords": ["squad"],
	},
	{
		"id": "qmaam_bloodlust",
		"name": "UPGRADE_QMAAM_BLOODLUST_NAME",
		"desc": "UPGRADE_QMAAM_BLOODLUST_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "missile",
		"axis": "gladiator",           ## §2.2 斗士轴（近距格斗弹家族）
		"rarity": Rarity.STABLE,
		"keywords": ["missile", "bloodlust"],
		"requires": ["secondary_missile"],
	},
	# ── 720 批 T4 新增：按轴计数缩放四技（recompute_axis_count_skills）──
	{
		"id": "veteran_hp",
		"name": "UPGRADE_VETERAN_HP_NAME",
		"desc": "UPGRADE_VETERAN_HP_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "survival",
		"rarity": Rarity.STABLE,
		"keywords": ["hp"],
	},
	{
		"id": "speed_by_knight",
		"name": "UPGRADE_SPEED_BY_KNIGHT_NAME",
		"desc": "UPGRADE_SPEED_BY_KNIGHT_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "mobility",
		"rarity": Rarity.STABLE,
		"keywords": ["speed"],
	},
	{
		"id": "ew_expert",
		"name": "UPGRADE_EW_EXPERT_NAME",
		"desc": "UPGRADE_EW_EXPERT_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "electronic_warfare",
		"rarity": Rarity.STABLE,
		"scope": "ace",                ## 王牌：只在操控机生效（meta 生效子集驱动，切控自动迁移）
		"keywords": ["radar"],
	},
	{
		"id": "weapon_master",
		"name": "UPGRADE_WEAPON_MASTER_NAME",
		"desc": "UPGRADE_WEAPON_MASTER_DESC",
		"stat": "skill_flag",
		"value": 1,
		"max_stacks": 1,
		"category": "secondary",
		"rarity": Rarity.ADVANCED,
		"scope": "ace",
		"keywords": ["gun", "missile"],
	},
]

# ── 词条联动：某类技能数量 → 某个参数 ────────────────────
## 数据驱动：每条规则按 category 数 owned_skills（去重），按 per_skill 累加倍率
## 写入 Aircraft 上对应的 *_mult 字段。每次拿升级 / 拿战区奖励后由 survivor_mode 调用 recompute。
## 计数语义：同一 category 下"已拥有的不同技能 id 数量"（每个技能算 1 次，不看堆叠层数）。
const CATEGORY_BONUSES: Array[Dictionary] = [
	{
		"category": "electronic_warfare",
		"field": "category_radar_mult",   ## Aircraft 上的运行时倍率字段
		"per_skill": 0.10,                ## 每持有 1 个该类技能 +10%
	},
]

## 某轴"已拥有的不同技能 id 数"（720 批 T4 按轴计数缩放用；不看堆叠层数）
static func count_owned_by_axis(stacks: Dictionary, axis: StringName) -> int:
	var n: int = 0
	for u in UPGRADES:
		if int(stacks.get(str(u.get("id", "")), 0)) > 0 and axis_of_upgrade(u) == axis:
			n += 1
	return n


## 720 批 T4：按轴计数缩放技能（历战者/全速推进/电子战专家/武器大师）。
## 由 recompute_category_bonuses 尾部调用（"每次拿到技能都要重算"= 同一重算点）；
## stacks 传"该机生效子集"→ 王牌两条（ew_expert/weapon_master）天然只在操控机 meta 里。
## 零技能路径：全部字段回默认值，行为与 baseline 一致。
static func recompute_axis_count_skills(ac: Aircraft, stacks: Dictionary) -> void:
	# 历战者：按斗士轴技能数 +5 HP/条，cap +100。差量幂等（applied 记账）；
	# 换型重放把 applied 清零后由本函数整额补回（挂 _replay_player_upgrades 序言）。
	var want_hp: float = 0.0
	if int(stacks.get("veteran_hp", 0)) > 0:
		want_hp = minf(5.0 * float(count_owned_by_axis(stacks, AXIS_GLADIATOR)), 100.0)
	var delta_hp: float = want_hp - ac.veteran_hp_bonus_applied
	if absf(delta_hp) > 0.01 and ac.params:
		ac.params.max_hp += delta_hp
		if delta_hp > 0.0:
			ac.hp = minf(ac.hp + delta_hp, ac.params.max_hp)
		else:
			ac.hp = minf(ac.hp, ac.params.max_hp)
		ac.veteran_hp_bonus_applied = want_hp
	# 全速推进：按骑士轴技能数顶速 +5%/条，cap +40%（effective_max_speed_kmh 消费）
	ac.speed_by_knight_mult = 1.0
	if int(stacks.get("speed_by_knight", 0)) > 0:
		ac.speed_by_knight_mult = 1.0 + minf(0.05 * float(count_owned_by_axis(stacks, AXIS_KNIGHT)), 0.40)
	# 电子战专家（王牌）：按策士轴技能数雷达 +100m/条（50px），cap +1km（500px）
	ac.ew_expert_radar_bonus_px = 0.0
	if int(stacks.get("ew_expert", 0)) > 0:
		ac.ew_expert_radar_bonus_px = minf(50.0 * float(count_owned_by_axis(stacks, AXIS_SCHEMER)), 500.0)
	# 武器大师（王牌）：按装备武器数全武器 CD −5%/件，cap −30%（起手 gun+msl = −10%）
	ac.weapon_master_cd_mult = 1.0
	if int(stacks.get("weapon_master", 0)) > 0 and ac.params:
		var wn: int = 0
		if ac.params.gun: wn += 1
		if ac.params.missile: wn += 1
		if ac.params.secondary_missile: wn += 1
		if ac.params.rocket: wn += 1
		if ac.params.torpedo: wn += 1
		if ac.params.loyal_wingman: wn += 1
		if ac.params.has_equipment_of_kind("railgun"): wn += 1
		if ac.params.has_equipment_of_kind("laser"): wn += 1
		ac.weapon_master_cd_mult = 1.0 - minf(0.05 * float(wn), 0.30)


## 重算所有 CATEGORY_BONUSES 规则，把结果写入 aircraft 对应字段。
##   stacks: survivor_mode.upgrade_stacks（id → 层数）
static func recompute_category_bonuses(aircraft: Aircraft, stacks: Dictionary) -> void:
	if aircraft == null:
		return
	# 预编 id → category 映射，避免每条规则都遍历 UPGRADES
	var id_to_cat: Dictionary = {}
	for u in UPGRADES:
		id_to_cat[u["id"]] = u.get("category", "")
	for rule in CATEGORY_BONUSES:
		var cat: String = rule["category"]
		var count := 0
		for uid in stacks.keys():
			if int(stacks[uid]) > 0 and id_to_cat.get(uid, "") == cat:
				count += 1
		var mult := 1.0 + float(rule["per_skill"]) * float(count)
		aircraft.set(rule["field"], mult)
	# 720 批 T4：按轴计数缩放四技（同一重算点，历战者/全速推进/电子战专家/武器大师）
	recompute_axis_count_skills(aircraft, stacks)


# ── 升级筛选 ─────────────────────────────────────────────

## 判断某个升级是否适用于指定主角
##   upgrade: UPGRADES 表中的一条
##   aircraft_id: PlayableAircraft.id（如 &"f16" / &"f14"）
##   p: 主角飞机当前的 AircraftParams（用于检测硬件存在性）
##
## 拒绝条件：
##   - upgrade.requires 中列出的硬件，主角缺失任意一项
##   - upgrade.exclusive_to 非空，且 aircraft_id 不在其中
static func is_upgrade_available_for(upgrade: Dictionary, aircraft_id: StringName, p: AircraftParams, owned_stacks: Dictionary = {}, squad_classes: Array = []) -> bool:
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

	# ── 品类池门控（squad-upgrade-ownership §2.8 实装草图 4）──
	# classes 非空时：队伍现有品类身份并集须与之相交，否则全队没人吃得到 → 不进池。
	# squad_classes 传空数组 = 调用方不启用该过滤（debug 通道 / 兼容旧调用）。
	var cls: Variant = upgrade.get("classes", null)
	if cls != null and not (cls as Array).is_empty() and not squad_classes.is_empty():
		var cls_hit := false
		for c in cls:
			if squad_classes.has(StringName(str(c))):
				cls_hit = true
				break
		if not cls_hit:
			return false

	# ── 互斥技能（excludes）──
	# 列表中任一技能已被选取（stacks > 0）时，本升级不再出现在抽卡池。
	# 用于"激活条件相同的二选一"（如 cobra_skill ↔ evasion_herbst 都在 evasion 模式被攻击触发）。
	var excludes: Variant = upgrade.get("excludes", null)
	if excludes != null and excludes.size() > 0:
		for excl_id in excludes:
			if int(owned_stacks.get(excl_id, 0)) > 0:
				return false

	# ── 技能前置（require_skill）──
	# 至少要拥有列表中的一个技能（stacks > 0）才解锁此升级。
	# 用于"派生类"技能（如恐惧扩散 / 恐惧附带减速）只有在玩家先选了一个能产生该状态的根技能后才进池。
	var prereq: Variant = upgrade.get("requires_skill", null)
	if prereq != null and prereq.size() > 0:
		var has_any := false
		for skill_id in prereq:
			if int(owned_stacks.get(skill_id, 0)) > 0:
				has_any = true
				break
		if not has_any:
			return false

	return true


# ── 归属词汇 v6 查询与生效谓词（spec skills-720-rework §1.2）─────────

## 技能 scope（"" = 通用全队 / "ace" 王牌 / "squad_once" 队级单实例）
static func upgrade_scope(u: Dictionary) -> String:
	return str(u.get("scope", ""))


## 技能品类限定数组（空 = 不限品类）
static func upgrade_classes(u: Dictionary) -> Array:
	var cls: Variant = u.get("classes", null)
	return (cls as Array) if cls != null else []


## 技能的 "+1 轴进度" 目标轴（&"" = 无）
static func milestone_plus_of(u: Dictionary) -> StringName:
	return StringName(str(u.get("milestone_plus", "")))


## 王牌 scope 中"写飞机字段/params"的 stat 白名单：切控迁移需要显式剥离（strip）→ 重应用。
## 触发型（skill_flag 走 meta 生效子集）不登记——meta 重建天然迁移。
## ⚠ 把技能标为 scope:"ace" 时：若其 stat 写字段/params，必须同步登记到这里，
## 并在 SurvivorPlayer.strip_upgrade_from 实现对应逆操作（否则切控双重叠加）。
const ACE_FIELD_STATS: Array[String] = [
	"missile_swarm",       # 导弹蜂群：params.missile 弹舱/追踪罚 + 齐射锁数
	"fear_on_lock",        # 凝视压迫：fear_on_lock_threshold 字段
	"fear_squad_spread",   # 惊鸿扩散：fear_squad_spread_duration 字段
	"head_on_jam",         # 对锋干扰：head_on_jam_threshold 字段
	"rear_aura_slow",      # 后半球减速光环：rear_aura_slow_radius_px 字段
	"cloud_overload",      # 云中超载：cloud_overload_active 开关
]


## 一条技能是否对某架机生效（纯谓词——全队下发过滤 / 生效子集 meta 重建共用）。
##   identity: 该机品类身份轴数组（EvolutionSystem.class_identity_of_profile）
##   is_controlled: 该机是否当前操控机（scope:"ace" 只落操控机）
## squad_once 恒 false：队级记账不落任何单机（效果由队级消费点读账本）。
static func upgrade_applies_to_machine(u: Dictionary, identity: Array, is_controlled: bool) -> bool:
	var scope := upgrade_scope(u)
	if scope == "squad_once":
		return false
	if scope == "ace" and not is_controlled:
		return false
	var cls: Array = upgrade_classes(u)
	if not cls.is_empty():
		var matched := false
		for c in cls:
			if identity.has(StringName(str(c))):
				matched = true
				break
		if not matched:
			return false
	return true


# ══════════════════════════════════════════════
# §5 / §7 抽卡 + Pity + 流派引导
# ══════════════════════════════════════════════

## 取技能稀有度（默认 STABLE）
static func get_rarity(upgrade: Dictionary) -> int:
	return int(upgrade.get("rarity", Rarity.STABLE))


## §7 流派引导：根据 owned_stacks 计算每个 keyword 的推荐倍率
## 返回 { keyword: float } —— 抽卡时同 keyword 技能权重 ×= 该值
## 公式：每 1 stack 同关键词 +20% 权重，封顶 +100%（5 stacks 即满）
##
## 注意：本函数 O(技能数 × 关键词数)，但只在升级时点调用 1 次（极低频），不每帧
static func compute_keyword_steering_weights(owned_stacks: Dictionary, level: int = 1) -> Dictionary:
	var counts: Dictionary = {}
	for u in UPGRADES:
		var uid: String = u.get("id", "")
		var stk: int = int(owned_stacks.get(uid, 0))
		if stk <= 0:
			continue
		var kws = u.get("keywords", null)
		if kws == null:
			continue
		for kw in kws:
			counts[kw] = int(counts.get(kw, 0)) + stk
	# 阶段开放：等级 < 5 时 steering 折半（避免新手被早期 funnel 锁死流派）
	var phase_mult: float = 0.5 if level < 5 else 1.0
	var steering: Dictionary = {}
	for kw in counts.keys():
		var n: int = int(counts[kw])
		var bump: float = minf(float(n), 5.0) * 0.20
		steering[kw] = 1.0 + bump * phase_mult
	return steering


## 取技能"流派权重倍率"——若技能挂多个 keyword，取最高 steering（鼓励同流派多归一）
static func _keyword_weight_mult(upgrade: Dictionary, steering: Dictionary) -> float:
	var kws = upgrade.get("keywords", null)
	if kws == null:
		return 1.0
	var max_mult: float = 1.0
	for kw in kws:
		max_mult = maxf(max_mult, float(steering.get(kw, 1.0)))
	return max_mult


## §5 三选一抽卡：返回 3 张 upgrade dict（保底至少 1 张 ≥ ADVANCED）
##
## 参数：
##   pool: 已通过 is_upgrade_available_for + max_stacks 过滤的候选 upgrade 列表
##   owned_stacks: 玩家当前 upgrade_stacks（用于 steering 计算）
##   pity_counter: { Rarity → int } 传引用，本函数会修改
##   level: 当前等级（影响 steering 阶段）
##
## 输出：3 张技能 dict（可能少于 3 张如 pool 不够）
##
## 算法：
##   1. 按 rarity 把 pool 分桶
##   2. 检查 pity：超阈值的最高档强制保底 1 张
##   3. 默认 2 槽 LOW (Stable+Advanced) + 1 槽 HIGH (Experimental+) 分布
##   4. 每槽内按 RARITY_BASE_WEIGHT × keyword_steering 加权随机
##   5. 不重复抽同一 id
static func pick_3_upgrades(pool: Array, owned_stacks: Dictionary, pity_counter: Dictionary, level: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if pool.is_empty():
		return result
	# 分桶
	var bucket: Dictionary = {
		Rarity.STABLE: [], Rarity.ADVANCED: [], Rarity.EXPERIMENTAL: [],
		Rarity.CLASSIFIED: [], Rarity.NEXT_GEN: [],
	}
	for u in pool:
		var r: int = get_rarity(u)
		(bucket[r] as Array).append(u)

	# 流派引导
	var steering: Dictionary = compute_keyword_steering_weights(owned_stacks, level)

	# Pity：找出超阈值的最高档（优先满足最高的）
	var forced_rarity: int = -1
	for r in [Rarity.NEXT_GEN, Rarity.CLASSIFIED, Rarity.EXPERIMENTAL]:
		var threshold: int = int(PITY_THRESHOLD.get(r, 999))
		var counter: int = int(pity_counter.get(r, 0))
		if counter >= threshold and (bucket[r] as Array).size() > 0:
			forced_rarity = r
			break

	# 选第 1 张 = 保底（如有 forced_rarity 否则 = HIGH 槽）
	var picked_ids: Dictionary = {}
	if forced_rarity >= 0:
		var forced_pick: Dictionary = _weighted_pick(bucket[forced_rarity], steering, picked_ids)
		if not forced_pick.is_empty():
			result.append(forced_pick)
			picked_ids[forced_pick["id"]] = true

	# HIGH 槽：从 EXP+ 抽（若 forced 没抽，就从 EXP+CLA+NEXT 加权）
	if result.is_empty():
		var high_pool: Array = []
		for r in [Rarity.EXPERIMENTAL, Rarity.CLASSIFIED, Rarity.NEXT_GEN]:
			high_pool.append_array(bucket[r] as Array)
		if high_pool.size() > 0:
			var hp: Dictionary = _weighted_pick(high_pool, steering, picked_ids)
			if not hp.is_empty():
				result.append(hp)
				picked_ids[hp["id"]] = true

	# LOW 槽 ×2：从 STABLE + ADVANCED
	var low_pool: Array = []
	for r in [Rarity.STABLE, Rarity.ADVANCED]:
		low_pool.append_array(bucket[r] as Array)
	while result.size() < 3:
		var pick: Dictionary
		if low_pool.size() > 0:
			pick = _weighted_pick(low_pool, steering, picked_ids)
		else:
			# LOW 池耗尽 → 从全 pool 兜底
			pick = _weighted_pick(pool, steering, picked_ids)
		if pick.is_empty():
			break  # pool 已全用，无法再抽
		result.append(pick)
		picked_ids[pick["id"]] = true

	# 更新 pity_counter：本次出现了什么档就清零，没出现的 +1
	var rarities_picked: Dictionary = {}
	for u in result:
		rarities_picked[get_rarity(u)] = true
	for r in PITY_THRESHOLD.keys():
		if rarities_picked.has(r):
			pity_counter[r] = 0
		else:
			pity_counter[r] = int(pity_counter.get(r, 0)) + 1

	return result


## 内部：按 RARITY_BASE_WEIGHT × keyword_steering 加权随机选一张，跳过 picked_ids 中的
static func _weighted_pick(items: Array, steering: Dictionary, picked_ids: Dictionary) -> Dictionary:
	if items.is_empty():
		return {}
	var weights: Array[float] = []
	var total: float = 0.0
	for u in items:
		var uid: String = u.get("id", "")
		if picked_ids.has(uid):
			weights.append(0.0)
			continue
		var r: int = get_rarity(u)
		var base_w: float = RARITY_BASE_WEIGHT[r] if r < RARITY_BASE_WEIGHT.size() else 0.1
		var kw_w: float = _keyword_weight_mult(u, steering)
		var w: float = base_w * kw_w
		weights.append(w)
		total += w
	if total <= 0.0:
		return {}
	var roll: float = randf() * total
	var acc: float = 0.0
	for i in items.size():
		acc += weights[i]
		if roll <= acc and weights[i] > 0.0:
			return items[i]
	# 兜底：返回最后一个有权重的
	for i in range(items.size() - 1, -1, -1):
		if weights[i] > 0.0:
			return items[i]
	return {}


# ──（旧"玩家自然成长"已退役，2026-07-19 spec player-aircraft-power-curve §6 阶段2：
#    等级只做门槛；成长改走下方三轴里程碑——卡片加点跨档触发，换型重放不丢失。）─────


# ── 玩家三轴属性与里程碑（spec evolution-attribute-gates）─────────

## 三轴 id。玩家可见名走 i18n（ATTR_* key，阶段 2+ 接 UI）；
## 敌机 AI 的 Gladiator/Lancer/Schemer 内部 archetype 词汇不上 UI 的既有约定不受影响。
const AXIS_GLADIATOR: StringName = &"gladiator"   ## 斗士：突击&近战 / 机炮 / 狗斗
const AXIS_KNIGHT: StringName = &"knight"          ## 骑士：机动力生存 / 雷达导弹
const AXIS_SCHEMER: StringName = &"schemer"        ## 策士：心理战 / 电子战
const AXES: Array[StringName] = [AXIS_GLADIATOR, AXIS_KNIGHT, AXIS_SCHEMER]

## 可获得点数上限 = floor(LV/3)：每 3 级一次卡片三选一（三卡=三轴各一），选卡=该轴 +1 点；
## 错过不补发，所以实际点数 ≤ 本值。满级 LV26 → 8 点。
static func axis_points_earnable(level: int) -> int:
	return floori(level / 3.0)

## 里程碑基准表（spec §2.6 v5）：每线 2/4/6/8 档 + 10 点预留（当前收入上限摸不到，等级上限抬高后启用）。
## 铁律：纯属性修改、陡递减（相对价值 100/60/25/15）——均衡 3/3/2 摊三首档 > 专精 8/0/0 吃单线。
## kind: "add"=加算 / "mult"=乘算。stat 键由里程碑应用器（阶段 2）统一解释，换型重放走同一入口：
##   max_hp / gun_damage / gun_range / max_g / gun_ammo / missile_count / radar_range /
##   speed（极速+巡航同乘）/ alt_speed（高度变化速度）/ flare_count / lock_time / flare_cd / radar_cone_deg
const MILESTONE_TABLE: Dictionary = {
	AXIS_GLADIATOR: [
		{"points": 2,  "stat": "max_hp",        "kind": "add",  "value": 25.0},
		{"points": 4,  "stat": "gun_damage",    "kind": "mult", "value": 1.08},
		{"points": 6,  "stat": "gun_range",     "kind": "mult", "value": 1.06},
		{"points": 8,  "stat": "max_g",         "kind": "add",  "value": 0.2},
		{"points": 10, "stat": "gun_ammo",      "kind": "mult", "value": 1.20},
	],
	AXIS_KNIGHT: [
		{"points": 2,  "stat": "missile_count", "kind": "add",  "value": 1.0},
		{"points": 4,  "stat": "radar_range",   "kind": "mult", "value": 1.10},
		{"points": 6,  "stat": "speed",         "kind": "mult", "value": 1.02},
		{"points": 8,  "stat": "alt_speed",     "kind": "mult", "value": 1.10},
		{"points": 10, "stat": "missile_count", "kind": "add",  "value": 1.0},
	],
	AXIS_SCHEMER: [
		{"points": 2,  "stat": "flare_count",   "kind": "add",  "value": 2.0},
		{"points": 4,  "stat": "lock_time",     "kind": "mult", "value": 0.90},
		{"points": 6,  "stat": "flare_cd",      "kind": "mult", "value": 0.92},
		{"points": 8,  "stat": "radar_cone_deg","kind": "add",  "value": 2.0},
		{"points": 10, "stat": "flare_count",   "kind": "add",  "value": 1.0},
	],
}

## 取某轴的里程碑表。起手机覆写（PlayableAircraft.milestone_overrides）：
## (axis, points) 相同的条目替换基准档；只替换、不新增档位（保持 2/4/6/8/10 骨架统一）。
static func milestones_for(axis: StringName, profile: PlayableAircraft = null) -> Array:
	var base: Array = MILESTONE_TABLE.get(axis, [])
	if profile == null or profile.milestone_overrides.is_empty():
		return base
	var merged: Array = []
	for entry in base:
		var use: Dictionary = entry
		for ov in profile.milestone_overrides:
			if StringName(str(ov.get("axis", ""))) == axis and int(ov.get("points", -1)) == int(entry["points"]):
				use = ov
				break
		merged.append(use)
	return merged

## 升级卡 → 轴归属：默认按 category 映射；跨界卡走逐 id 覆写；带显式 "axis" 字段的卡（专注卡）最优先
const AXIS_BY_CATEGORY: Dictionary = {
	"survival": AXIS_GLADIATOR,            # 突击近战的肉与回复
	"secondary": AXIS_GLADIATOR,           # 机炮系
	"mobility": AXIS_KNIGHT,               # 机动力生存
	"missile": AXIS_KNIGHT,                # 雷达导弹
	"weapon": AXIS_KNIGHT,                 # 特殊武器强化（电磁炮等远程件）
	"electronic_warfare": AXIS_SCHEMER,    # 电子战
}
const AXIS_OVERRIDE_BY_ID: Dictionary = {
	"dogfight": AXIS_GLADIATOR,                 # 狗斗能力=斗士定义轴（category=mobility）
	"fear_squad_spread": AXIS_SCHEMER,          # 心理战（category=secondary）
	"fear_chills": AXIS_SCHEMER,
	"skill_gun_kill_flare_drop": AXIS_SCHEMER,  # 效果主体是 jam（category=secondary）
	"laser_cooldown": AXIS_SCHEMER,             # 能量/电子系（category=weapon）
	"laser_range": AXIS_SCHEMER,
	"laser_heat": AXIS_SCHEMER,
}
## 轴 → 玩家可见名 i18n key（卡片标签 / Tab 面板用）
const AXIS_I18N_KEY: Dictionary = {
	AXIS_GLADIATOR: "ATTR_GLADIATOR",
	AXIS_KNIGHT: "ATTR_KNIGHT",
	AXIS_SCHEMER: "ATTR_SCHEMER",
}

## 三轴正式配色（2026-07-19 用户 mockup 定调：斗士琥珀 / 骑士青绿 / 策士紫）
## 卡片染色 / 三轴量表（AxisBarsPanel）/ 树缺口徽记共用同一套
const AXIS_COLORS: Dictionary = {
	AXIS_GLADIATOR: Color(0.95, 0.62, 0.18),   # 琥珀橙
	AXIS_KNIGHT: Color(0.38, 0.85, 0.58),      # 青绿
	AXIS_SCHEMER: Color(0.68, 0.45, 0.95),     # 紫
}

## 里程碑 stat → 短名 i18n key（Tab 面板下一档预览 / 里程碑达成提示共用）
const MILESTONE_STAT_I18N: Dictionary = {
	"max_hp": "ATTR_STAT_MAX_HP", "gun_damage": "ATTR_STAT_GUN_DAMAGE",
	"gun_range": "ATTR_STAT_GUN_RANGE", "max_g": "ATTR_STAT_MAX_G",
	"gun_ammo": "ATTR_STAT_GUN_AMMO", "missile_count": "ATTR_STAT_MISSILE_COUNT",
	"radar_range": "ATTR_STAT_RADAR_RANGE", "speed": "ATTR_STAT_SPEED",
	"alt_speed": "ATTR_STAT_ALT_SPEED", "flare_count": "ATTR_STAT_FLARE_COUNT",
	"lock_time": "ATTR_STAT_LOCK_TIME", "flare_cd": "ATTR_STAT_FLARE_CD",
	"radar_cone_deg": "ATTR_STAT_RADAR_CONE",
}

static func axis_of_upgrade(u: Dictionary) -> StringName:
	if u.has("axis"):
		return StringName(str(u["axis"]))
	var uid := str(u.get("id", ""))
	if AXIS_OVERRIDE_BY_ID.has(uid):
		return AXIS_OVERRIDE_BY_ID[uid]
	return AXIS_BY_CATEGORY.get(str(u.get("category", "")), AXIS_GLADIATOR)

## 轴内抽一张卡：稀有度基础权重 × keyword 流派引导（每 3 级卡片事件用）。
## pity 不参与——三卡一轴一张的结构本身保证多样性，保底需要时再接。
static func pick_card_for_axis(pool: Array, owned_stacks: Dictionary, level: int) -> Dictionary:
	if pool.is_empty():
		return {}
	var steering: Dictionary = compute_keyword_steering_weights(owned_stacks, level)
	var weights: Array[float] = []
	var total := 0.0
	for u in pool:
		var w: float = RARITY_BASE_WEIGHT[get_rarity(u)] * _keyword_weight_mult(u, steering)
		weights.append(w)
		total += w
	var roll := randf() * total
	for i in pool.size():
		roll -= weights[i]
		if roll <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]

## 轴池抽空时的兜底"专注"卡：无技能、纯 +1 点（stat=axis_focus 由 survivor_mode 特判不走 apply）
static func make_axis_focus_card(axis: StringName) -> Dictionary:
	return {
		"id": "axis_focus_%s" % axis,
		"name": "CARD_AXIS_FOCUS_NAME",
		"desc": "CARD_AXIS_FOCUS_DESC",
		"stat": "axis_focus",
		"value": 0.0,
		"max_stacks": 999,
		"category": "",
		"axis": String(axis),
		"rarity": Rarity.STABLE,
		"keywords": [],
	}


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
const TRAVEL_SPAWN_INTERVAL_BASE := 32.0   ## 玩家等级 1 时的旅途刷怪间隔（秒）（2026-07-06 60km 密度调优：45→32，边缘入场有 60~120s 运输延迟，节奏前移补偿）
const TRAVEL_SPAWN_INTERVAL_MIN := 18.0    ## 玩家高等级时的下限（25→18）
## 旅途刷怪方向扇形半角（弧度）。⚠ 旅途增援已改边缘入场不再使用（spec reinforcement-ingress）；
## 保留给 _pick_safe_spawn_angle 的事件/任务类"机头沿途"刷出备用。
const TRAVEL_SPAWN_FAN_HALF := PI * 70.0 / 180.0
const ENEMIES_PER_WAVE_BASE := 1    ## 每波基础敌人数
const ENEMIES_PER_WAVE_GROWTH := 0.4  ## 每级额外敌人数（2026-07-06 热度二轮：0.3→0.4）
## 刷怪选型"有效等级"提前量：_pick_enemy_type 按 level+此值 走解锁/概率公式 →
## 战斗机（成建制小队）更早登场、UAV 杂鱼更早退场（2026-07-06 热度二轮，用户要求
## "更早的敌机以小队方式出现"）。只影响选型，不影响间隔/预算/缩放。
const SPAWN_HEAT_LEVEL_SHIFT := 2
const SPAWN_DISTANCE := 3200.0      ## 刷怪距离（像素）。⚠ 旅途增援已不再使用（改走边缘入场，见下方 INGRESS_*）；仍被 ace_squad BOSS 入场 / adds 族群航线 / 沙盒 debug_panel 引用

## ── 增援入场（spec reinforcement-ingress，2026-07-05）─────────────
## 旅途增援不再刷在玩家周围（根治镜头挪回/拉满时敌机凭空出现），改为：
## 边界外生成 → TRANSIT 飞向中央锚点 → ONSTATION 绕环驻空 → token 饿着时 EGRESS 物理飞离
const INGRESS_SPAWN_OUTSET_PX := 400.0        ## 生成点在世界边界线外的推出量
const INGRESS_EDGE_CANDIDATES := 16           ## 每次入场在边界周长上取的候选点数
const INGRESS_MIN_PLAYER_DIST_PX := 5000.0    ## 候选边缘点距玩家的硬下限
const ANCHOR_DISC_RADIUS_FRAC := 0.35         ## 巡逻锚点盘半径 = 本系数 × WORLD_HALF_PX
const ANCHOR_ZONE_CLEARANCE_PX := 800.0       ## 锚点距任何战区圆边的最小距离
const ANCHOR_MIN_SEPARATION_PX := 2500.0      ## 新锚点与现存活跃锚点的最小间距
const ANCHOR_ARRIVE_DIST_PX := 900.0          ## 长机距锚点小于此值 → TRANSIT 转 ONSTATION
const PATROL_RING_RADIUS_BASE_PX := 1400.0    ## 驻空盘旋环半径基数
const PATROL_RING_RADIUS_JITTER_PX := 400.0   ## 驻空环半径 ± 抖动（每中队 roll 一次）
const HUNTER_TRANSIT_GRAB_DIST_PX := 4000.0   ## TRANSIT 途中可被 hunter 就近点名的距离
const EGRESS_STALE_SEC := 45.0                ## 中队连续无交战达此时长才有退场资格
const EGRESS_FREE_OUTSET_PX := 800.0          ## 全员飞出边界线外此距离才释放
const EGRESS_MAX_CONCURRENT := 1              ## 同时处于退场状态的中队数上限
const OPENING_GARRISON_SQUADS := 3            ## 开局 t≈0 直接以 ONSTATION 预置的中队数（2026-07-06 60km 密度调优：2→3）

## ── ROE 全图察觉与交战规则（spec global-awareness-roe）──
const ROE_TICK_S := 2.0                       ## 中队察觉判定 tick 间隔
const ROE_AWARE_MEMORY_S := 15.0              ## 察觉记忆：连续无感知刷新此时长 → 回未察觉
const ROE_GARRISON_LEASH_PX := 750.0          ## 守区 leash：交战对象须在 zone.radius + 此值内（=1500m）
const ROE_PATROL_LEASH_PX := 3000.0           ## 巡逻 leash：追击距锚点/巡逻线超此值放弃返航（=6000m）
const ROE_DATALINK_RANGE_PX := 10000.0        ## 敌雷达站 datalink 察觉半径（=20km，收编 60km-density-pass）
const ROE_ROUTE_PATROL_CHANCE := 0.3          ## 增援到站 roll 线路巡逻（而非定点环）的概率
const ROE_ROUTE_MIN_LEG_PX := 2000.0          ## 线路巡逻两锚点最小间距（=4000m），不足退化定点环
const MAX_ENEMIES_HARD := 48          ## 绝对上限（2026-07-06 60km 密度调优：40→48；FPS 动态降载兜底，须过 Sentinel+Lv5 压测）
const MAX_ENEMIES_DEFAULT := 36       ## 默认上限（30→36）
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
const AF03_UNLOCK_LEVEL := 8         ## AF-03（电磁炮狙击 Schemer，单机）解锁等级
const AF03_CHANCE_PER_LEVEL := 0.05  ## 每超过解锁等级，AF-03 出现概率增加（稀有）
const AF03_CHANCE_MAX := 0.18        ## AF-03 最大出现概率
const SU27_UNLOCK_LEVEL := 8         ## Su-27（主力威胁 + 眼镜蛇机动）解锁等级
const SU27_CHANCE_PER_LEVEL := 0.07  ## 每超过解锁等级，Su-27 出现概率增加
const SU27_CHANCE_MAX := 0.25        ## Su-27 最大出现概率
const SU35_UNLOCK_LEVEL := 9         ## Su-35（Su-27 强化版 + 眼镜蛇 + TVC）解锁等级
const SU35_CHANCE_PER_LEVEL := 0.07  ## 每超过解锁等级，Su-35 出现概率增加（与 MiG-31 同档稀有度）
const SU35_CHANCE_MAX := 0.22        ## Su-35 最大出现概率（略低于 Su-27 + 低于 MiG-31）
const F4_UNLOCK_LEVEL := 6           ## F-4 Phantom（Gladiator 中段，导弹卡车）解锁等级
const F4_CHANCE_PER_LEVEL := 0.10    ## 每超过解锁等级，F-4 出现概率增加
const F4_CHANCE_MAX := 0.30          ## F-4 最大出现概率
const F104_UNLOCK_LEVEL := 5         ## F-104 Starfighter（Lancer 纯速度截击）解锁等级
const F104_CHANCE_PER_LEVEL := 0.12  ## 每超过解锁等级，F-104 出现概率增加
const F104_CHANCE_MAX := 0.32        ## F-104 最大出现概率
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

const TOKEN_BUDGET_BASE := 8           ## 1 级时的 Token 预算（2026-07-06 60km 密度调优：5→8）
const TOKEN_BUDGET_PER_LEVEL := 1.8    ## 每级 Token 预算增量（1.5→1.8）
const TOKEN_BUDGET_MAX := 55           ## Token 预算绝对上限（45→55）

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
	19: 5,  ## F-4 Phantom — Gladiator 中段（双弹种导弹卡车）
	20: 4,  ## F-104       — Lancer 纯速度截击（BOOM-ZOOM 专家）
	21: 8,  ## Su-35       — Gladiator 顶级（Su-27 强化版 + TVC，单/双机出现）
	22: 0,  ## F/A-18      — CSG 航母舰载机（事件弹射，不占 Token；CSG Phase 1 期间定期出现）
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
	19: -1, ## F-4 Phantom：编队出现，无硬上限
	20: -1, ## F-104：编队出现，无硬上限
	21: 3,  ## Su-35：精英单/双机，一次最多 3 台（含编队）
	22: -1, ## F/A-18：航母 BOSS 持续弹射，不限同时存在数（CV 死时停刷）
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

# ── 敌人武器等级（V1-V8）─────────────────────────────────
# 仅作用于敌人。玩家武器不走 V_N（保持机型绑定 + 技能升级树强化）。
# 详见 docs/changelogs/2026-05-04-enemy-weapon-tiers.md
#
# 8 档铺满整个生存模式生命周期；玩家等级决定基线档位，敌人种类带 ±N 偏移。

## 玩家等级 → 敌人武器基线档位（1-8）
const PLAYER_LEVEL_TO_TIER: Dictionary = {
	1: 1, 2: 1,
	3: 2, 4: 2,
	5: 3, 6: 3,
	7: 4, 8: 4,
	9: 5, 10: 5,
	11: 6, 12: 6,
	13: 7, 14: 7,
	## ≥15 默认 V8
}

## 敌人种类 → tier 偏移（int 对应 SurvivorSpawner.EnemyType）。
## 同等级下 UAV 永远比 MiG 弱一截；BOSS / 精英带正偏移。
## 列表外的种类（Adds/无武器单位）默认 0。
const ENEMY_TIER_OFFSET: Dictionary = {
	0: -2,    # UAV
	1: -1,    # UCAV
	5: -1,    # F-86
	18: -1,   # UAV_LASER (Aegis)
	3:  0,    # INTERCEPTOR (J-7)
	10: 0,    # A-7
	11: 0,    # Q-5
	7:  0,    # MIG-23
	8:  0,    # F-100
	20: 0,    # F-104
	2:  1,    # MIG-29
	19: 1,    # F-4
	4:  1,    # UAV_COMMANDER (Sentinel)
	22: 1,    # FA-18 (CSG)
	6:  2,    # MIG-31
	9:  2,    # SU-27
	17: 2,    # AF-03
	21: 3,    # SU-35
	15: 4,    # F-47 BOSS
	16: 3,    # F-14 Poltergeist BOSS
	## Adds / 事件触发：默认 0；调用方可显式传 tier
	13: 0,    # AH-64（事件触发，默认 V5 由 _spawn_ah64_flock 传）
	14: 0,    # CH-47（无武器）
	12: 0,    # TU-160（无武器）
}

## 武器 tier 数组（索引 0 = V1，索引 7 = V8）
const ENEMY_GUN_TIERS: Array[GunParams] = [
	preload("res://resources/weapons/enemy_gun_v1.tres"),
	preload("res://resources/weapons/enemy_gun_v2.tres"),
	preload("res://resources/weapons/enemy_gun_v3.tres"),
	preload("res://resources/weapons/enemy_gun_v4.tres"),
	preload("res://resources/weapons/enemy_gun_v5.tres"),
	preload("res://resources/weapons/enemy_gun_v6.tres"),
	preload("res://resources/weapons/enemy_gun_v7.tres"),
	preload("res://resources/weapons/enemy_gun_v8.tres"),
]

const ENEMY_MISSILE_TIERS: Array[MissileParams] = [
	preload("res://resources/weapons/enemy_missile_v1.tres"),
	preload("res://resources/weapons/enemy_missile_v2.tres"),
	preload("res://resources/weapons/enemy_missile_v3.tres"),
	preload("res://resources/weapons/enemy_missile_v4.tres"),
	preload("res://resources/weapons/enemy_missile_v5.tres"),
	preload("res://resources/weapons/enemy_missile_v6.tres"),
	preload("res://resources/weapons/enemy_missile_v7.tres"),
	preload("res://resources/weapons/enemy_missile_v8.tres"),
]

const ENEMY_ROCKET_TIERS: Array[RocketParams] = [
	preload("res://resources/weapons/enemy_rocket_v1.tres"),
	preload("res://resources/weapons/enemy_rocket_v2.tres"),
	preload("res://resources/weapons/enemy_rocket_v3.tres"),
	preload("res://resources/weapons/enemy_rocket_v4.tres"),
	preload("res://resources/weapons/enemy_rocket_v5.tres"),
	preload("res://resources/weapons/enemy_rocket_v6.tres"),
	preload("res://resources/weapons/enemy_rocket_v7.tres"),
	preload("res://resources/weapons/enemy_rocket_v8.tres"),
]

## 玩家等级 + 敌人种类 → 武器 tier (1-8)
static func get_weapon_tier(etype: int, player_level: int) -> int:
	var base: int = PLAYER_LEVEL_TO_TIER.get(player_level, 8)
	var offset: int = ENEMY_TIER_OFFSET.get(etype, 0)
	return clampi(base + offset, 1, 8)

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
	{"type": 20, "unlock": 5, "peak": 6,  "retire": -1, "base_weight": 0.9},  ## F-104      Lancer 纯速度截击
	{"type": 8,  "unlock": 6, "peak": 7,  "retire": -1, "base_weight": 0.8},  ## F-100      Lancer 编队
	{"type": 19, "unlock": 6, "peak": 7,  "retire": -1, "base_weight": 0.85}, ## F-4        Gladiator 中段（导弹卡车）
	{"type": 2,  "unlock": 7, "peak": 8,  "retire": -1, "base_weight": 0.9},  ## MiG-29     主力威胁
	{"type": 9,  "unlock": 8, "peak": 10, "retire": -1, "base_weight": 0.6},  ## Su-27      精英+眼镜蛇
	{"type": 6,  "unlock": 9, "peak": 11, "retire": -1, "base_weight": 0.4},  ## MiG-31     顶级 Lancer
	{"type": 21, "unlock": 9, "peak": 11, "retire": -1, "base_weight": 0.4},  ## Su-35      顶级 Gladiator+TVC
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

## 按战区星级决定空战中队规模（2026-07-06 60km 密度调优：3/4/5 → 4/5/6）
static func air_squadron_count_for_difficulty(difficulty: int) -> int:
	match difficulty:
		3: return 6
		2: return 5
		_: return 4

## 地面任务 TGT 数量（仅按星级缩放，单位 HP 不变）
## 2026-07-06 60km 密度调优：★2+2/★★3+3/★★★5+5 → 3+3/4+4/6+6；
## 新增 radar_count：★★+ 附带雷达站 TGT（datalink 早期预警，击杀削弱战区感知——任务丰富化）
## 返回 {"sam_count":int, "aa_count":int, "radar_count":int}
static func ground_tgt_scale(difficulty: int, _player_level: int) -> Dictionary:
	var sam_count: int
	var aa_count: int
	var radar_count: int
	match difficulty:
		3:
			sam_count = 6
			aa_count = 6
			radar_count = 2
		2:
			sam_count = 4
			aa_count = 4
			radar_count = 1
		_:
			sam_count = 3
			aa_count = 3
			radar_count = 0
	return {
		"sam_count": sam_count,
		"aa_count": aa_count,
		"radar_count": radar_count,
	}

## 战区驻守预算：基础 + 等级线性加成
## 基础按难度（1-3 星）：12 / 22 / 42（2026-07-06 60km 密度调优，原 8/15/30——
## 战区半径同批扩到 3500，守军按面积感补量）
## 每级 +10%（10 级时 ≈ ×1.90），让高等级战区实打实变重
const ZONE_DEFENDER_BASE_BUDGET := {1: 12, 2: 22, 3: 42}
const ZONE_DEFENDER_BUDGET_PER_LEVEL := 0.10
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
