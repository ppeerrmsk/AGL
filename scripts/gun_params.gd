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
@export var lifetime: float = 2.0              ## 秒 子弹存活时间（远端弹道长度）；bullet_manager 据此定 life
                                               ## 720 技能"枪械精度·子弹寿命"按 lifetime_bonus ×(1+n) 加长本值

@export_group("梭射")
@export var burst_count: int = 10              ## 每梭弹数（1 = 匀速点射）；节奏公式见 specs/weapons/gun-burst-fire.md

@export_group("弹药")
@export var max_ammo: int = 200
