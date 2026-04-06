class_name AircraftParams
extends Resource

@export_group("基本信息")
@export var display_name: String = "F-16"

@export_group("生存性")
@export var max_hp: float = 100.0
@export var armor: float = 0.0

@export_group("速度")
@export var max_speed: float = 2100.0       ## km/h 海平面最大速度
@export var cruise_speed: float = 900.0     ## km/h 巡航速度
@export var stall_speed_base: float = 220.0 ## km/h 1G海平面失速速度
@export var acceleration: float = 50.0      ## m/s² 加速能力

@export_group("机动性")
@export var max_g: float = 9.0
@export var roll_rate: float = 4.0          ## rad/s 滚转速率

@export_group("高度")
@export var max_altitude: float = 15000.0   ## 米 实用升限
@export var climb_rate_max: float = 250.0   ## m/s 最大爬升率

@export_group("引擎")
@export var thrust_to_weight: float = 1.1
@export var drag_coefficient: float = 0.02

@export_group("雷达")
@export var radar_range: float = 300.0          ## 探测距离（像素）
@export var radar_half_angle: float = 30.0      ## 扇形半角（度）
@export var lock_time: float = 3.0              ## 锁定所需持续照射时间（秒）

@export_group("视觉")
@export var icon_color: Color = Color.GREEN
