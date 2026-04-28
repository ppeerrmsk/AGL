class_name MissileParams
extends Resource

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
