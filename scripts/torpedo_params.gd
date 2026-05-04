class_name TorpedoParams
extends Resource

## 空中漂浮雷参数（A-10 实验武器）
##
## 现实灵感：英国二战 Long Aerial Mine (LAM) — 降落伞挂炸药，飘在敌机航线前方。
## 设计语义：
##   - 仅在飞机进入"规避模式"时投放（evasion_mode=true）
##   - CD 完毕在飞机当前位置周围投下若干颗（drop_count），各自往不同方向缓慢漂移
##   - **不追踪**目标，纯靠漂移 + 缓降 + 近炸引爆，运算极低
##   - 敌方进入 prox 半径自动引爆 → AOE 杀伤
##   - 不被 CIWS / Laser 拦截（独立武器槽）

@export_group("基本")
@export var display_name: String = "Drift Mine"

@export_group("投放")
## 投放冷却（秒，规避模式下持续倒数 → 0 即自动抛出）
@export var cooldown: float = 5.0
## 寿命（秒，超时不爆直接静默消失）
@export var lifetime: float = 14.0
## 单次投放数量（每个 CD 周期同时投下几颗，朝不同方向漂移）
@export var drop_count: int = 3

@export_group("漂移")
## 最小漂移速度（m/s，水平方向）
@export var drift_speed_min: float = 18.0
## 最大漂移速度（m/s）
@export var drift_speed_max: float = 45.0
## 缓降速率（m/s 高度下降，模拟降落伞下沉）
@export var descent_rate: float = 8.0

@export_group("追踪（弱）")
## 追踪扫描半径（米）— 内有敌人才会缓慢转向追，超出此距离纯漂移
@export var tracking_scan_range_m: float = 1500.0
## 追踪转向速率（度/秒）— 极慢，给"漂浮 + 微弱吸引"感
@export var tracking_turn_rate_dps: float = 20.0
## 目标重选间隔（秒）— 节流：每隔多久重扫一次最优目标
@export var retarget_interval: float = 0.5

@export_group("近炸 + AOE")
## 近炸引信触发距离（米）
@export var proximity_fuse_radius: float = 90.0
## AOE 爆炸半径（米）
@export var aoe_radius: float = 130.0
## AOE 伤害（半径内统一应用）
@export var aoe_damage: float = 45.0

@export_group("视觉")
## 弹体颜色（默认青色，区别于火箭弹的橙红 + 子弹的黄）
@export var body_color: Color = Color(0.4, 0.95, 1.0, 1.0)
## 降落伞 / 漂浮装置颜色
@export var canopy_color: Color = Color(0.7, 0.9, 1.0, 0.85)
