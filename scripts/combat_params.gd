class_name CombatParams
extends Resource

@export_group("导弹发射纪律")
## 导弹熟练度 0..1：影响"前置点是否在包络内 / 偏角是否合理 / 发射窗口是否稳定"三道门槛
##  0   = 不过滤窗口稳定度，前置点包络仍然检查（避免明显废弹）
##  0.4 = 杂兵基线：偶尔筛掉乱射
##  0.55 = 常规敌战斗机
##  0.85 = 玩家 / 王牌：严格 lead + 严格发射窗口
## 仅对装备导弹（params.missile != null）的飞机生效；纯机炮/纯火箭飞机此字段被忽略
@export_range(0.0, 1.0, 0.05) var missile_skill: float = 0.4
## 每次发射判断时的随机波动 ± 范围。skill=0.55 jitter=0.20 → 实际生效在 [0.35, 0.75]
## 让"老练飞行员"偶尔急了，"杂兵"偶尔抓到好窗口
@export_range(0.0, 0.4, 0.05) var missile_skill_jitter: float = 0.15

@export_group("追踪策略")
@export var intercept_range_mult: float = 2.5      ## 超过 射程×此值 进入拦截模式
@export var intercept_lead_max: float = 8.0        ## 秒 前置拦截最大预判时间
@export var closing_rate_threshold: float = 0.15   ## 闭合率低于 自身速度×此值 时放弃咬尾
@export var six_oclock_offset_ratio: float = 0.3   ## 六点钟偏移 = 射程 × 此值
@export var pure_pursuit_lead_factor: float = 0.4  ## 纯追击前置量系数

@export_group("开火纪律")
@export var opportunity_cone_mult: float = 2.5     ## 机会射击：角度放宽倍率
@export var opportunity_range_mult: float = 0.4    ## 机会射击：有效射程缩减比

@export_group("机动激进度")
@export var combat_bank_aggression: float = 1.0    ## 战斗转弯激进度 (0.5=保守, 1.0=标准, 1.5=极限)
@export var combat_full_bank_diff: float = 0.1     ## rad 战斗中航向偏差超过此值就压满坡度
@export var combat_half_bank_diff: float = 0.02    ## rad 低于此值归零，介于两者之间用50%坡度

@export_group("转向减速")
@export var turn_slow_angle: float = 45.0          ## 度 航向偏差超过此值开始减速
@export var turn_slow_max_angle: float = 120.0     ## 度 航向偏差达到此值时减到最低速度
@export var turn_slow_speed_mult: float = 0.85     ## 大角度转向时速度 = 巡航 × 此值

@export_group("速度管理")
@export var approach_speed_mult: float = 1.4       ## 接近阶段速度 = 巡航 × 此值
@export var maneuver_speed_mult: float = 1.0       ## 近距格斗速度 = 巡航 × 此值
@export var closing_speed_mult: float = 1.25       ## 咬尾未进射程时的速度 = 巡航 × 此值
@export var ab_cooldown: float = 2.0               ## 秒 加力开关切换最短间隔
@export var overshoot_speed_margin: float = 1.05   ## 近距速度上限 = 敌机速度 × 此值（防冲过）
@export var overshoot_decel_range: float = 2.0     ## 射程×此值 内开始减速匹配敌机速度
@export var overshoot_ab_range: float = 3.0        ## 射程×此值 内且比敌机快时禁用加力

@export_group("能量管理")
@export var dive_speed_ratio: float = 0.85         ## 速度 < 目标×此值 时俯冲换速
@export var dive_min_altitude: float = 2000.0      ## 米 低于此高度不俯冲
@export var dive_depth: float = 1000.0             ## 米 每次俯冲下降量
@export var dive_floor: float = 1500.0             ## 米 俯冲高度下限
@export var climb_brake_overspeed: float = 1.15    ## 速度 > 目标速度×此值 时爬升减速
@export var climb_brake_height: float = 800.0      ## 米 爬升减速的高度增量
@export var climb_brake_ceiling: float = 12000.0   ## 米 爬升减速的高度上限
@export var climb_speed_ratio: float = 1.15        ## 速度 > 巡航×此值 时蓄能爬升（巡航模式）
@export var climb_max_altitude: float = 8000.0     ## 米 蓄能爬升上限（巡航模式）
