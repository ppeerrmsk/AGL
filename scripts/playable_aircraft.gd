class_name PlayableAircraft
extends Resource

## 主角飞机档案（Playable Aircraft Profile）
##
## 把"加一个新主角飞机"所需的所有信息封装到一个 .tres 里：
##   1. 选择界面卡片显示用的元数据
##   2. 一个引用的 AircraftParams（基础数据 + 默认武器装填）
##   3. 生存模式专属的属性/武器倍率（无需在代码里硬编码）
##   4. 生存模式专属的实例标志（无限燃油/装弹/伤害上限等）
##   5. 可选的起始僚机配置（小队主控）
##
## 加新主角的工作流程见 docs/reference/playable-aircraft-workflow.md

# ── UI 卡片显示 ──
@export_group("UI 卡片")
@export var id: StringName = &"f16"           ## 内部唯一 ID
@export var display_name: String = "F-16C Block 50"
@export var codename: String = "SmartFalcon"  ## 副名（HUD 显示为 "F-16 SmartFalcon"）
@export var card_tags: PackedStringArray      ## 短标签（["热诱弹","均衡机动",...]）
@export_multiline var card_desc: String       ## 卡片描述

# ── 基础机体 ──
@export_group("基础机体")
## 引用的 AircraftParams（飞行/雷达/默认武器装填）
## ⚠ 加载后会被深拷贝，原 .tres 不会被修改
@export var base_params: AircraftParams

# ── 生存模式：基础属性倍率/加成 ──
@export_group("生存模式 / 基础属性")
@export var radar_range_mult: float = 1.0     ## 雷达范围倍率
@export var max_speed_mult: float = 1.0       ## 最大速度倍率
@export var cruise_speed_mult: float = 1.0    ## 巡航速度倍率
@export var acceleration_mult: float = 1.0    ## 加速倍率
@export var roll_rate_mult: float = 1.0       ## 滚转速率倍率
@export var lock_time_mult: float = 1.0       ## 锁定时间倍率
@export var max_g_bonus: float = 0.0          ## 持续 G 力加成

# ── 生存模式：主导弹 ──
@export_group("生存模式 / 主导弹")
@export var missile_count_override: int = -1  ## -1 = 不修改

# ── 生存模式：机炮 ──
@export_group("生存模式 / 机炮")
@export var gun_damage_mult: float = 1.0      ## 机炮伤害倍率
@export var gun_range_override: float = 0.0   ## 0 = 不修改
@export var gun_cone_override: float = 0.0    ## 0 = 不修改
## 玩家飞行员瞄准技巧（0~1）：影响每 burst 的常驻 aim 偏移幅度
## 公式 base_err_deg = lerpf(5°, 0.5°, skill)；0 = 业余（±5°）/ 1 = 王牌（±0.5°）
## 默认 0.6 ≈ ±2.3°，比 Aircraft 默认 0.3（±3.65°）更准
## ⚠ 0 = 不修改（保留 Aircraft 默认 0.3）；显式设值才覆盖
@export var base_pilot_aim_skill: float = 0.0

# ── 生存模式：战斗风格覆盖 ──
@export_group("生存模式 / 战斗风格")
## 非空时整个替换 base_params.combat
## 留空时使用 base_params 自带的 combat
@export var combat_override: CombatParams

# ── 生存模式：热诱弹覆盖 ──
@export_group("生存模式 / 热诱弹")
## 非空时整个替换 base_params.flare
## 留空时使用 base_params 自带的 flare（如果 base 也没有，则该机型无热诱弹）
@export var flare_override: FlareParams

# ── 生存模式：实例标志 ──
@export_group("生存模式 / 实例配置")
@export var flares_guaranteed: bool = true    ## 热诱弹 100% 干扰
@export var enable_missile_reload: bool = true ## 导弹耗尽后自动装填
@export var enable_flare_reload: bool = true   ## 热诱弹耗尽后自动装填
@export var enable_gun_reload: bool = true     ## 机炮耗尽后自动装填
@export var infinite_fuel: bool = true         ## 无限燃油
@export var missile_damage_cap: float = 30.0   ## 收到的导弹伤害上限（0 = 不限）
@export var bullet_damage_cap: float = 5.0     ## 收到的子弹伤害上限（0 = 不限）
@export var bullet_dodge_chance: float = 0.10  ## 基础子弹闪避率

# （自然成长 growth_curve export 已退役删除，2026-07-19：等级只做门槛，成长走三轴里程碑）

# ── 生存模式：三轴里程碑覆写（spec evolution-attribute-gates §2.6 按起手机分化） ──
@export_group("生存模式 / 三轴里程碑覆写")
## 覆写基准表（SurvivorData.MILESTONE_TABLE）中 (axis, points) 相同的档位；空 = 全走基准表。
## 条目形如 {"axis": "gladiator", "points": 2, "stat": "max_hp", "kind": "add", "value": 40.0}
## axis ∈ gladiator/knight/schemer；kind ∈ add/mult；stat 键见 SurvivorData.MILESTONE_TABLE 注释。
## 四起手机分表由用户后续平衡时填（本槽只立机制）。
@export var milestone_overrides: Array[Dictionary] = []

# ── 生存模式：配件槽位预算 ──
@export_group("生存模式 / 配件槽位")
## 总槽位预算（默认 6 格）。配件占 1/2/3 格不等。≤0 时走 LoadoutLedger.DEFAULT_SLOT_BUDGET
@export var slot_budget: int = 6

# ── 起始僚机（小队主控） ──
## 僚机的飞行员属性固定为"完美执行"（skill=1, composure=1, focus=1, SA=1）；
## 所有生存模式调味（雷达/速度/武器/装填/伤害上限/闪避 等）与长机完全一致，
## 升级只作用于长机，所以僚机不随玩家成长。因此这里不再暴露 aggression/skill
## 的随机范围字段——故意去掉以免产生"僚机性格差异"这种现在不需要的概念。
@export_group("起始僚机")
@export var wingman_count: int = 0             ## 起始僚机数量（0 = 单机）
## 僚机使用的机体（缺省 = 与主角同型）
## 通常指向另一架 AircraftParams（不是 PlayableAircraft）
@export var wingman_params: AircraftParams
