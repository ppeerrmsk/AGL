class_name CombatParams
extends Resource

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
## 转弯控制器自 2026-06-07 改为临界阻尼 PD（SEAM-012）：target_turn_rate = kp·误差 − kd·转速，
## bank = atan(turn_rate·v/g) 反推。下列字段在 PD 语义下的含义：
@export var combat_bank_aggression: float = 1.0    ## PD 比例增益 kp 的缩放（0.5=保守, 1.0=标准, 1.5=极限）；越大跟随越紧、稳态误差越小
@export var combat_full_bank_diff: float = 0.1     ## 【已弃用】旧位置式控制的"满坡度航向阈值"，PD 控制不再读取（保留仅为 .tres 兼容）
@export var combat_half_bank_diff: float = 0.02    ## rad PD 的 P 项死区：航向误差小于此值不压坡（防对准后微抖）；D 阻尼项仍生效

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
