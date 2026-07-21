class_name CommandWheelParams
extends Resource
## 命令轮盘参数（权威源：docs/specs/systems/command-wheel.md §2）。
## 手势组均为屏幕像素（UI 层）；命令组为世界坐标像素（PIXELS_PER_METER=0.5）。

@export_group("手势")
## 按住超过此时长呼出轮盘；短于此 = 普通单击。
## 2026-07-20 用户调参 0.15→0.35：0.15 太灵敏，快速双击就会误呼轮盘；
## 0.35 配合蓄力指示圈（转满才呼出）给出明确的"正在进入菜单"预期
@export var hold_threshold_s: float = 0.35
## 按住期间指针位移超过此值立即呼出（拖动意图明确，不等蓄力）；24→36 防双击带小位移误触
@export var drag_threshold_px: float = 36.0
## 按住多久后开始显示蓄力指示圈（普通快速单击完全不见任何 UI 噪音）
@export var charge_visual_delay_s: float = 0.08
## 中心死区半径：松开在死区内 = 取消
@export var dead_zone_radius_px: float = 30.0
## 一环选择区外沿
@export var ring1_outer_px: float = 110.0
## 轮盘呼出期间全局时间流速（子弹时间，不全停）
@export var time_scale_in_wheel: float = 0.3

@export_group("紧急集合")
## 到达判定半径（世界坐标，600px = 300m）
@export var arrival_radius_px: float = 600.0

@export_group("撤离此区")
## 撤离圈半径（世界坐标，1500px = 3km；原 5km 过大，2026-07-05 用户调参）
@export var evac_radius_px: float = 1500.0
## 禁入区持续时间
@export var evac_duration_s: float = 20.0

@export_group("防守此区")
## 警戒圈半径（世界坐标，1500px = 3km）
@export var guard_radius_px: float = 1500.0
## 空闲盘旋半径（世界坐标，500px = 1km）
@export var orbit_radius_px: float = 500.0
## 追击目标飞出 guard_radius × 此值即放弃回圈（滞回）
@export var leash_exit_mult: float = 1.15

@export_group("火力分配")
## SPREAD 各自接敌的目标池半径（世界坐标，以按下目标为锚点）
@export var spread_cluster_radius_px: float = 2000.0
## FOCUS 包围：相邻攻击机接近轴最小方位分离角（度）
@export var surround_min_axis_sep_deg: float = 45.0

@export_group("TIGHT 齐射（formation-discipline）")
## 齐射窗口时长：长机开火触发开窗，窗口内僚机在编队槽位里释放
@export var volley_window_s: float = 1.5
## 再武装安静期：窗口关闭后长机须停火 ≥ 此时长，下一轮开火才再开窗（防连环开窗=变相持续开火权）
@export var volley_rearm_quiet_s: float = 2.0
