class_name GunParams
extends Resource

@export_group("基本")
@export var display_name: String = "M61A1"

@export_group("性能")
@export var fire_rate: float = 3000.0          ## 发/分钟
@export var bullet_damage: float = 8.0         ## 每发伤害
@export var muzzle_velocity: float = 1050.0    ## m/s 弹丸初速
@export var max_range: float = 1000.0          ## 米 最大有效射程
@export var spread_angle: float = 1.5          ## 度 散布半角（精度）
@export var fire_cone_half_angle: float = 5.0  ## 度 允许开火的机头偏角

@export_group("弹药")
@export var max_ammo: int = 200
