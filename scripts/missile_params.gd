class_name MissileParams
extends Resource

# ── 副导弹槽位（开发代号 secondary_missile）目标过滤位域 ──
# 副槽武器靠 target_filter 决定能锁谁；主弹槽默认 TARGET_AIR 与历史行为一致
const TARGET_AIR: int = 1
const TARGET_GROUND: int = 2
const TARGET_SHIP: int = 4
const TARGET_MISSILE: int = 8           ## 来袭导弹（拦截弹用，预留）
const TARGET_ALL_VEHICLES: int = 7      ## 飞机+地面+船

# ── 副槽目标优先级策略（武器自己声明）──
# update_secondary_missile 的 _pick_secondary_target 按这个 enum 分发到不同 picker
const TARGET_PRIO_CLOSEST: int = 0           ## 默认：最近的锁定满目标
const TARGET_PRIO_DOGFIGHT_SIDE: int = 1     ## QMAAM：侧面（off-axis 大）+ 正在狗斗我

@export_group("基本信息")
@export var display_name: String = "MRM"

@export_group("性能")
## 最大飞行速度 (m/s)
@export var max_speed: float = 1400.0
## 发动机燃烧时间 (秒)
@export var motor_burn_time: float = 6.0
## 燃烧阶段加速度 (m/s²)
@export var motor_acceleration: float = 200.0
## 燃尽后空气阻力减速率 (m/s²)
@export var drag_deceleration: float = 15.0
## 导弹最大过载 (G)
@export var max_g: float = 35.0
## 比例导引常数 N (通常 3-5)
@export var nav_constant: float = 4.0

@export_group("射程")
## 后半球最大射程 (m)
@export var max_range_rear: float = 15000.0
## 前半球/后半球射程比 (前半球约为后半球 4 倍)
@export var front_rear_ratio: float = 4.0
## 最小射程 / 引信武装距离 (m)
@export var min_range: float = 500.0
## 绝对存活时间 (秒)
@export var max_lifetime: float = 60.0

@export_group("弹头")
## 命中伤害
@export var damage: float = 80.0
## 近炸引信半径 (m)
@export var proximity_fuse_radius: float = 20.0
## 近炸引信高度容差 (m)
@export var proximity_fuse_alt: float = 200.0

@export_group("生存性（抗 CIWS 拦截）")
## 被 CIWS 子弹累积打掉多少 HP 才算拦截成功。仅 CIWS 子弹消耗，不影响其他命中机制
## 小型 / 短程弹建议 30-40；中程 50-70；大型 / 齐射弹 70-100
@export var intercept_hp: float = 60.0

@export_group("制导")
## 导引头视场角 (度，总角)
@export var seeker_fov: float = 60.0
## 发射后制导启动延迟 (秒)
@export var guidance_delay: float = 0.5
## 发射后不管模式（不需要持续照射，不受热诱弹干扰）
@export var fire_and_forget: bool = false

@export_group("装载")
## 挂载数量
@export var max_count: int = 2
## 发射间隔 (秒)
@export var cooldown: float = 3.0

@export_group("副导弹槽位（仅当本资源挂在 AircraftParams.secondary_missile 时生效）")
## 目标类型过滤位域：MissileParams.TARGET_AIR / GROUND / SHIP / MISSILE 的或合
## 默认 TARGET_AIR，主弹槽零行为变化；副槽武器自己声明
@export var target_filter: int = TARGET_AIR
## 副雷达锁定锥半角（度）。>0 时覆盖飞机 params.radar_half_angle，独立于主雷达
## QMAAM: 70° 宽锥扩到侧面；普通副弹设 -1 沿用飞机默认
@export var lock_cone_half_angle_deg: float = -1.0
## 副雷达最大锁定距离（像素）。>0 时覆盖飞机 effective_radar_range_px，独立于主雷达
## QMAAM: 1500px ≈ 3km 近距锁定；普通副弹设 -1 沿用飞机默认
@export var lock_max_range_px: float = -1.0
## 目标优先级策略：MissileParams.TARGET_PRIO_*。武器自己声明纪律
@export var target_priority: int = TARGET_PRIO_CLOSEST
## HOBS 高离轴发射：发射时不沿载机机头，而是直接指向目标 LOS
## QMAAM 70° 宽锁定锥配此参数 = 起飞就指向目标，PN 立刻有效（否则 60G 也要先做大转弯）
@export var launch_toward_target: bool = false

@export_group("VLS 齐射（仅船用）")
## 是否为 VLS 齐射弹 —— 开启后走三段式弹道（垂直爬升 → 过渡俯冲 → 末端 PN）
@export var is_vls_salvo: bool = false
## 每波齐射数量
@export var vls_salvo_size: int = 5
## 齐射内相邻两发的发射间隔 (秒)
@export var vls_salvo_interval: float = 0.08
## 一波齐射结束后到下一波的冷却时间 (秒)
@export var vls_salvo_cooldown: float = 18.0
## 锁定玩家时的随机散布半径 (px)：每发齐射弹的锁定点在玩家附近随机偏移
@export var vls_point_scatter_px: float = 150.0

## 三段式弹道参数
## 阶段 1（垂直爬升）：维持初始朝向（统一朝世界北，屏幕上表现为一串火柱冲天）
##                    速度爬升到 max_speed 的 50%，无制导
@export var vls_climb_time: float = 0.8
## 阶段 2（过渡俯冲）：逐渐把朝向转向发射瞬间锁死的点，速度继续爬升到 max_speed
@export var vls_transition_time: float = 0.6
## 阶段 2 的最大转弯速率（度/秒）—— 决定弹道曲线的弯度
@export var vls_transition_turn_rate_degs: float = 150.0
## 每发齐射弹的速度随机系数范围（1.0 ± 此值），避免齐射弹完全重叠
## 例如 0.2 表示速度在 [0.80x, 1.20x] 之间随机
@export var vls_speed_variance: float = 0.18
