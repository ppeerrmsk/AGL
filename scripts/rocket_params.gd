class_name RocketParams
extends Resource

## 无制导火箭弹参数（例：F-86 的 FFAR）
## 直线发射 + 大散布 + 低命中率 + 低伤害。
## 目标为玩家不走直线时几乎不会被打中。

@export_group("基本")
@export var display_name: String = "FFAR"

@export_group("齐射")
@export var burst_count_min: int = 2           ## 单次齐射最少火箭数
@export var burst_count_max: int = 4           ## 单次齐射最多火箭数
@export var burst_interval: float = 0.08       ## 秒 齐射内单发间隔（连发效果）
@export var burst_cooldown: float = 3.5        ## 秒 两次齐射之间的冷却

@export_group("弹道")
@export var rocket_damage: float = 12.0        ## 每枚伤害（偏低，被打中也不致命）
@export var muzzle_velocity: float = 320.0     ## m/s 火箭初速（慢于炮弹）
@export var max_range: float = 1800.0          ## 米 有效射程（寿命由此推算）
@export var spread_angle: float = 8.0          ## 度 散布半角（大散布=低命中）
@export var fire_cone_half_angle: float = 12.0 ## 度 允许开火的机头偏角
@export var min_range: float = 400.0           ## 米 最小发射距离（太近不放）
@export var max_fire_range: float = 1500.0    ## 米 超过此距离不发射（大散布远距离无意义）

@export_group("弹药")
@export var max_ammo: int = 24                 ## 火箭总弹量
