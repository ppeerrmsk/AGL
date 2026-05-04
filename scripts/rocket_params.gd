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
@export var rocket_damage: float = 12.0        ## 每枚伤害（直击或近炸时的"满档"基础值）
## 距离衰减末端倍率：rocket 飞行到 max_range 时的伤害倍率（直击 + AOE 都按此衰减）。
## 默认 1.0 = 不衰减（敌方 AI 火箭弹保持向后兼容）。
## 玩家版（A-10）设 0.6-0.8，让"贴脸糊死、远端略弱"的近战定位明确。
@export var min_damage_mult: float = 1.0
@export var muzzle_velocity: float = 320.0     ## m/s 火箭初速（慢于炮弹）
@export var max_range: float = 1800.0          ## 米 有效射程（寿命由此推算）
@export var spread_angle: float = 8.0          ## 度 散布半角（大散布=低命中）
@export var fire_cone_half_angle: float = 12.0 ## 度 允许开火的机头偏角
@export var min_range: float = 400.0           ## 米 最小发射距离（太近不放）
@export var max_fire_range: float = 1500.0    ## 米 超过此距离不发射（大散布远距离无意义）

@export_group("弹药")
@export var max_ammo: int = 24                 ## 火箭总弹量
@export var infinite_ammo: bool = false        ## 无限弹药（玩家 A-10 等专属，绕过 rockets_remaining 扣减/检查）

@export_group("近炸引信 + AOE")
## > 0 时启用近炸引信：火箭弹接近敌方单位到此距离（米）即引爆，不必直接命中
@export var proximity_fuse_radius_m: float = 0.0
## > 0 时引爆生成 AOE 杀伤区，半径内所有敌方单位受 aoe_damage 伤害
@export var aoe_radius_m: float = 0.0
## AOE 伤害（与直接命中的 rocket_damage 独立；典型设置略低于 rocket_damage）
@export var aoe_damage: float = 0.0
