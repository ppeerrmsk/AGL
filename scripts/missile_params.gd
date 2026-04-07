class_name MissileParams
extends Resource

@export_group("基本信息")
@export var display_name: String = "AIM-7M"

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

@export_group("制导")
## 导引头视场角 (度，总角)
@export var seeker_fov: float = 60.0
## 发射后制导启动延迟 (秒)
@export var guidance_delay: float = 0.5

@export_group("装载")
## 挂载数量
@export var max_count: int = 2
## 发射间隔 (秒)
@export var cooldown: float = 3.0
